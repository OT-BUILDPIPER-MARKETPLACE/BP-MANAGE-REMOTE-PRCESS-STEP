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

# --------------------------------------------------
# Credential helpers (implement since functions.sh doesn't have them)
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
# Fetch & decrypt SSH key
# --------------------------------------------------
if [ -z "$CREDENTIAL_MANAGEMENT" ] || [ -z "$FERNET_KEY" ]; then
  logErrorMessage "Credential variables are missing"
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

# --------------------------------------------------
# Write SSH key
# --------------------------------------------------
KEY_FILE="key.pem"
if [ ! -f "$KEY_FILE" ]; then
  echo "$CREDENTIAL_SSH_KEY" > "$KEY_FILE"
  chmod 400 "$KEY_FILE"
fi

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

# --------------------------------------------------
# Build SSH command
# --------------------------------------------------
PROXY_OPTION=""
if [ "$USE_PROXY_SERVER" = "true" ]; then
  PROXY_OPTION="-o ProxyCommand=ssh -A -W %h:%p ${SSH_USERNAME}@${PROXY_SERVER_IP} -i ${KEY_FILE} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
  logInfoMessage "Proxy server enabled: ${PROXY_SERVER_IP}"
fi

SSH_CMD="ssh -i ${KEY_FILE} -p ${SSH_PORT} \
  ${PROXY_OPTION} \
  -o UserKnownHostsFile=/dev/null \
  -o StrictHostKeyChecking=no \
  ${SSH_USERNAME}@${SSH_IP}"

# --------------------------------------------------
# Execute action
# --------------------------------------------------
logInfoMessage "Executing action on remote host"
logInfoMessage "Action: ${ACTION}"
logInfoMessage "Host: ${SSH_IP}"

set +e
${SSH_CMD} "${ACTION}"
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

