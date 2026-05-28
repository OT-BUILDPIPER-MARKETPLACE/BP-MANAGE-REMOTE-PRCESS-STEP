#!/bin/bash

# ---------------------------------------------------------------
# NOTE: ACTIVITY_SUB_TASK_CODE is managed by the BuildPiper
#       environment. Do NOT override it here to ensure events
#       appear correctly in the UI.
# ---------------------------------------------------------------

SHELL_FUNCTIONS_PATH="/opt/buildpiper/shell-functions"
source "${SHELL_FUNCTIONS_PATH}/functions.sh"
source "${SHELL_FUNCTIONS_PATH}/log-functions.sh"
source "${SHELL_FUNCTIONS_PATH}/str-functions.sh"
source "${SHELL_FUNCTIONS_PATH}/file-functions.sh"
source "${SHELL_FUNCTIONS_PATH}/aws-functions.sh"

if [ "$DEBUG" = "true" ]; then
    set -x
fi

# ---------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------
AUTH_MODE="${AUTH_MODE:-key}"
SSH_PORT="${SSH_PORT:-22}"
TASK_STATUS=0

# ---------------------------------------------------------------
# Credential Helpers
# ---------------------------------------------------------------
getEncryptedCredential() {
    local credentialManagement="$1"
    local credentialKey="$2"
    echo "$credentialManagement" | jq -r "$credentialKey"
}

getDecryptedCredential() {
    local fernet_key="$1"
    local encrypted_value="$2"
    python3 - <<EOF
from cryptography.fernet import Fernet
f = Fernet("${fernet_key}".encode())
print(f.decrypt("${encrypted_value}".encode()).decode())
EOF
}

# ---------------------------------------------------------------
# 1. Initialization
# ---------------------------------------------------------------
logInfoMessage "> Starting step: manage_remote_process"
logInfoMessage "> Action: ${ACTION}"
logInfoMessage "> Target: ${SSH_USERNAME}@${SSH_IP}:${SSH_PORT}"
logInfoMessage "> Auth mode: ${AUTH_MODE}"

add_event "INITIALIZATION" "Successful" \
    "Manage Remote Process step initialized" \
    "Action: ${ACTION} | Target: ${SSH_IP}:${SSH_PORT} | Auth: ${AUTH_MODE}"

if [ -n "$SLEEP_DURATION" ] && [ "$SLEEP_DURATION" -gt 0 ] 2>/dev/null; then
    logInfoMessage "> Sleeping for ${SLEEP_DURATION} second(s)..."
    sleep "$SLEEP_DURATION"
fi

# ---------------------------------------------------------------
# 2. Input Validation
# ---------------------------------------------------------------
logInfoMessage "> Validating inputs..."

VALIDATION_ERRORS=""
[ -z "$ACTION" ]       && VALIDATION_ERRORS+="ACTION is not set. "
[ -z "$SSH_USERNAME" ] && VALIDATION_ERRORS+="SSH_USERNAME is not set. "
[ -z "$SSH_IP" ]       && VALIDATION_ERRORS+="SSH_IP is not set. "
[ -z "$SSH_PORT" ]     && VALIDATION_ERRORS+="SSH_PORT is not set. "

if [ -n "$VALIDATION_ERRORS" ]; then
    logErrorMessage "> Missing required variables: ${VALIDATION_ERRORS}"
    add_event "INPUT_VALIDATION" "Failed" \
        "Required environment variables are missing" \
        "${VALIDATION_ERRORS}"
    saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
    exit 1
fi

case "$AUTH_MODE" in
    key|password|public_key) ;;
    *)
        logErrorMessage "> Invalid AUTH_MODE: ${AUTH_MODE} — allowed: key, password, public_key"
        add_event "INPUT_VALIDATION" "Failed" \
            "Invalid AUTH_MODE: ${AUTH_MODE}" \
            "Allowed values: key | password | public_key"
        saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
        exit 1
        ;;
esac

if [ "$AUTH_MODE" = "password" ] && [ -z "$SSH_PASSWORD" ]; then
    logErrorMessage "> SSH_PASSWORD is required for password auth mode but is not set"
    add_event "INPUT_VALIDATION" "Failed" \
        "SSH_PASSWORD is not set" \
        "AUTH_MODE is 'password' but SSH_PASSWORD is missing"
    saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
    exit 1
fi

add_event "INPUT_VALIDATION" "Successful" \
    "All required inputs validated" \
    "Action: ${ACTION} | Host: ${SSH_IP}:${SSH_PORT} | Auth: ${AUTH_MODE}"

# ---------------------------------------------------------------
# 3. Execution Summary
# ---------------------------------------------------------------
echo ""
echo "> Manage Remote Process Execution Summary"
printf '+%-30s+%-50s+\n' '------------------------------' '--------------------------------------------------'
printf '| %-28s | %-48s |\n' "Parameter" "Value"
printf '+%-30s+%-50s+\n' '------------------------------' '--------------------------------------------------'
printf '| %-28s | %-48s |\n' "Remote Host" "${SSH_IP}:${SSH_PORT}"
printf '+%-30s+%-50s+\n' '------------------------------' '--------------------------------------------------'
printf '| %-28s | %-48s |\n' "SSH User" "${SSH_USERNAME}"
printf '+%-30s+%-50s+\n' '------------------------------' '--------------------------------------------------'
printf '| %-28s | %-48s |\n' "Auth Mode" "${AUTH_MODE}"
printf '+%-30s+%-50s+\n' '------------------------------' '--------------------------------------------------'
printf '| %-28s | %-48s |\n' "Use Proxy" "${USE_PROXY_SERVER:-false}"
printf '+%-30s+%-50s+\n' '------------------------------' '--------------------------------------------------'
printf '| %-28s | %-48s |\n' "Action" "${ACTION}"
printf '+%-30s+%-50s+\n' '------------------------------' '--------------------------------------------------'
echo ""

# ---------------------------------------------------------------
# 4. SSH Key Setup (key auth mode only)
# ---------------------------------------------------------------
KEY_FILE="key.pem"

if [ "$AUTH_MODE" = "key" ]; then
    logInfoMessage "> Setting up SSH key for key-based authentication..."

    if [ -z "$CREDENTIAL_MANAGEMENT" ] || [ -z "$FERNET_KEY" ]; then
        logErrorMessage "> CREDENTIAL_MANAGEMENT or FERNET_KEY is not set — required for key auth mode"
        add_event "SSH_KEY_SETUP" "Failed" \
            "Missing credential variables for key authentication" \
            "CREDENTIAL_MANAGEMENT and FERNET_KEY must be set for AUTH_MODE=key"
        saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
        exit 1
    fi

    ENCRYPTED_CREDENTIAL_SSH_KEY=$(
        getEncryptedCredential "$CREDENTIAL_MANAGEMENT" ".SSH_KEY.CREDENTIAL_ACCESS_TOKEN_OR_KEY"
    )

    if [ -z "$ENCRYPTED_CREDENTIAL_SSH_KEY" ] || [ "$ENCRYPTED_CREDENTIAL_SSH_KEY" = "null" ]; then
        logErrorMessage "> Failed to fetch encrypted SSH key from CREDENTIAL_MANAGEMENT"
        add_event "SSH_KEY_SETUP" "Failed" \
            "Encrypted SSH key not found in CREDENTIAL_MANAGEMENT" \
            "Key path: .SSH_KEY.CREDENTIAL_ACCESS_TOKEN_OR_KEY"
        saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
        exit 1
    fi

    CREDENTIAL_SSH_KEY=$(getDecryptedCredential "$FERNET_KEY" "$ENCRYPTED_CREDENTIAL_SSH_KEY")

    if [ ! -f "$KEY_FILE" ]; then
        echo "$CREDENTIAL_SSH_KEY" > "$KEY_FILE"
        chmod 400 "$KEY_FILE"
    fi

    logInfoMessage "> SSH key fetched, decrypted and saved: ${KEY_FILE}"
    add_event "SSH_KEY_SETUP" "Successful" \
        "SSH key fetched and decrypted successfully" \
        "Key file: ${KEY_FILE} (permissions: 400)"
fi

# ---------------------------------------------------------------
# 5. SSH Command Construction
# ---------------------------------------------------------------
SSH_BASE_OPTS="-p ${SSH_PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

PROXY_OPTION=""
if [ "$USE_PROXY_SERVER" = "true" ]; then
    logInfoMessage "> Proxy server enabled: ${PROXY_SERVER_IP}"
    PROXY_OPTION="-o ProxyCommand=\"ssh -W %h:%p ${SSH_USERNAME}@${PROXY_SERVER_IP} ${SSH_BASE_OPTS}\""
    add_event "PROXY_CONFIGURATION" "Successful" \
        "SSH proxy server configured" \
        "Proxy: ${PROXY_SERVER_IP}"
fi

SSH_TARGET="${SSH_USERNAME}@${SSH_IP}"

run_ssh_cmd() {
    local action="$1"
    case "$AUTH_MODE" in
        key)        ssh -i "$KEY_FILE" $SSH_BASE_OPTS $PROXY_OPTION "$SSH_TARGET" "$action" ;;
        password)   sshpass -p "$SSH_PASSWORD" ssh $SSH_BASE_OPTS $PROXY_OPTION "$SSH_TARGET" "$action" ;;
        public_key) ssh $SSH_BASE_OPTS $PROXY_OPTION "$SSH_TARGET" "$action" ;;
    esac
}

# ---------------------------------------------------------------
# 6. Remote Action Execution
# ---------------------------------------------------------------
logInfoMessage "> Executing remote action on ${SSH_IP}..."
logInfoMessage "> Action: ${ACTION}"

add_event "ACTION_EXECUTION_START" "Successful" \
    "Starting remote action execution" \
    "Action: ${ACTION} | Target: ${SSH_TARGET}"

run_ssh_cmd "${ACTION}"

RC=$?

if [ $RC -ne 0 ]; then
    logErrorMessage "> Remote action failed on ${SSH_IP} (exit: ${RC})"
    add_event "ACTION_EXECUTION_RESULT" "Failed" \
        "Remote action execution failed" \
        "Action: ${ACTION} | Host: ${SSH_IP} | Exit code: ${RC}"
    saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
    exit 1
fi

logInfoMessage "> Remote action completed successfully on ${SSH_IP}"
add_event "ACTION_EXECUTION_RESULT" "Successful" \
    "Remote action executed successfully" \
    "Action: ${ACTION} | Host: ${SSH_IP}"

# ---------------------------------------------------------------
# 7. Final Status
# ---------------------------------------------------------------
logInfoMessage "> Manage Remote Process step completed successfully"
saveTaskStatus 0 "${ACTIVITY_SUB_TASK_CODE}"
exit 0
