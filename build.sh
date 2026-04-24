#!/bin/bash

set -e
# Enable debug mode if DEBUG=true is set
if [ "$DEBUG" = "true" ]; then
    set -x
fi

# --------------------------------------------------
# Load shell functions
# --------------------------------------------------
SHELL_FUNCTIONS_PATH="/opt/buildpiper/shell-functions"

source "$SHELL_FUNCTIONS_PATH/functions.sh"
source "$SHELL_FUNCTIONS_PATH/log-functions.sh"
source "$SHELL_FUNCTIONS_PATH/str-functions.sh"
source "$SHELL_FUNCTIONS_PATH/file-functions.sh"
source "$SHELL_FUNCTIONS_PATH/aws-functions.sh"

# --------------------------------------------------
# Initial sleep
# --------------------------------------------------
sleep "${SLEEP_DURATION:-5s}"
add_event "INITIAL SLEEP" "In Progress" \
      "Sleeping before start" \
      "Duration: ${SLEEP_DURATION:-5s}"

# --------------------------------------------------
# Credential helpers
# --------------------------------------------------
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

# --------------------------------------------------
# Auth mode validation
# --------------------------------------------------
AUTH_MODE="${AUTH_MODE:-key}"

case "$AUTH_MODE" in
  key|password|public_key) ;;
  *)
    logErrorMessage "Invalid AUTH_MODE: $AUTH_MODE (allowed: key, password, public_key)"
    exit 1
    ;;
esac

# --------------------------------------------------
# Fetch & decrypt SSH key (ONLY for key auth)
# --------------------------------------------------
if [ "$AUTH_MODE" = "key" ]; then
  if [ -z "$CREDENTIAL_MANAGEMENT" ] || [ -z "$FERNET_KEY" ]; then
    logErrorMessage "Credential variables are missing for key authentication"
    exit 1
  fi

  ENCRYPTED_CREDENTIAL_SSH_KEY=$(
    getEncryptedCredential "$CREDENTIAL_MANAGEMENT" ".SSH_KEY.CREDENTIAL_ACCESS_TOKEN_OR_KEY"
  )

  if [ -z "$ENCRYPTED_CREDENTIAL_SSH_KEY" ] || [ "$ENCRYPTED_CREDENTIAL_SSH_KEY" = "null" ]; then
    logErrorMessage "Failed to fetch encrypted SSH key"
    exit 1
  fi

  CREDENTIAL_SSH_KEY=$(getDecryptedCredential "$FERNET_KEY" "$ENCRYPTED_CREDENTIAL_SSH_KEY")

  KEY_FILE="key.pem"
  if [ ! -f "$KEY_FILE" ]; then
    echo "$CREDENTIAL_SSH_KEY" > "$KEY_FILE"
    chmod 400 "$KEY_FILE"
  fi
fi
add_event "SSH KEY FETCH" "In Progress" \
      "Fetching and decrypting SSH key" \
      "Key file: ${KEY_FILE}"

# --------------------------------------------------
# Validate required inputs
# --------------------------------------------------
TASK_STATUS=0

if [ -z "$ACTION" ] || [ -z "$SSH_USERNAME" ] || [ -z "$SSH_IP" ] || [ -z "$SSH_PORT" ]; then
  [ -z "$ACTION" ] && logErrorMessage "ACTION is not set"
  [ -z "$SSH_USERNAME" ] && logErrorMessage "SSH_USERNAME is not set"
  [ -z "$SSH_IP" ] && logErrorMessage "SSH_IP is not set"
  [ -z "$SSH_PORT" ] && logErrorMessage "SSH_PORT is not set"
  exit 1
fi
add_event "INPUT VALIDATION" "Completed" \
      "Validated required inputs" \
      "All required variables are set"

if [ "$AUTH_MODE" = "password" ] && [ -z "$SSH_PASSWORD" ]; then
  logErrorMessage "SSH_PASSWORD is required for password authentication"
  exit 1
fi

# --------------------------------------------------
# Build SSH command
# --------------------------------------------------
SSH_AUTH_OPTION=""
PROXY_OPTION=""

case "$AUTH_MODE" in
  key)
    SSH_AUTH_OPTION="-i ${KEY_FILE}"
    ;;
  password)
    SSH_AUTH_OPTION=""
    ;;
  public_key)
    # Uses CI runner's ~/.ssh/id_* or ssh-agent
    SSH_AUTH_OPTION=""
    ;;
esac

if [ "$USE_PROXY_SERVER" = "true" ]; then
  PROXY_OPTION="-o ProxyCommand=ssh -W %h:%p ${SSH_USERNAME}@${PROXY_SERVER_IP} \
    ${SSH_AUTH_OPTION} \
    -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=no"
  logInfoMessage "Proxy server enabled: ${PROXY_SERVER_IP}"
add_event "PROXY CONFIGURED" "Completed" \
      "Proxy server setup" \
      "Proxy IP: ${PROXY_SERVER_IP}"
fi

SSH_CMD_BASE="ssh \
  -p ${SSH_PORT} \
  ${SSH_AUTH_OPTION} \
  ${PROXY_OPTION} \
  -o PreferredAuthentications=publickey,password \
  -o PubkeyAuthentication=yes \
  -o UserKnownHostsFile=/dev/null \
  -o StrictHostKeyChecking=no"

SSH_TARGET="${SSH_USERNAME}@${SSH_IP}"
add_event "SSH COMMAND BUILT" "In Progress" \
      "Constructed SSH command" \
      "Target: ${SSH_TARGET}"

# --------------------------------------------------
add_event "EXECUTE ACTION" "In Progress" \
      "Executing remote action" \
      "Action: ${ACTION}"
# Execute action
# --------------------------------------------------
logInfoMessage "Executing action on remote host"
logInfoMessage "Action: ${ACTION}"
logInfoMessage "Host: ${SSH_IP}"
logInfoMessage "Auth Mode: ${AUTH_MODE}"

set +e
if [ "$AUTH_MODE" = "password" ]; then
  sshpass -p "$SSH_PASSWORD" \
    ${SSH_CMD_BASE} "${SSH_TARGET}" "${ACTION}"
else
  ${SSH_CMD_BASE} "${SSH_TARGET}" "${ACTION}"
fi
RC=$?
set -e

if [ $RC -ne 0 ]; then
  TASK_STATUS=1
  logErrorMessage "Failed to execute action on ${SSH_IP}"
  exit 1
else
  logInfoMessage "Action executed successfully on ${SSH_IP}"
fi

# --------------------------------------------------
# Save task status
# --------------------------------------------------
saveTaskStatus "${TASK_STATUS}" "${ACTIVITY_SUB_TASK_CODE}"
add_event "TASK STATUS SAVED" "Completed" \
      "Task status saved" \
      "Status: ${TASK_STATUS}"
