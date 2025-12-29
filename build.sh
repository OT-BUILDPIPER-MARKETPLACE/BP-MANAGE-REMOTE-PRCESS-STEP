#!/bin/bash
set -e

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
# Prepare SSH key (simple, without extra decryption)
# --------------------------------------------------
if [ ! -f "key.pem" ]; then
  echo "$CREDENTIAL_SSH_KEY" > key.pem
  chmod 400 key.pem
fi

# --------------------------------------------------
# Proxy settings (optional)
# --------------------------------------------------
PROXY_OPTION=""
if [ "$USE_PROXY_SERVER" = "true" ]; then
  PROXY_OPTION="-o ProxyCommand=\"ssh -A -W %h:%p $SSH_USERNAME@$PROXY_SERVER_IP -i key.pem -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no\""
  logInfoMessage "Proxy server enabled: $PROXY_SERVER_IP"
fi

# --------------------------------------------------
# SSH command
# --------------------------------------------------
SERVER="ssh -i key.pem -p $SSH_PORT $PROXY_OPTION -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $SSH_USERNAME@$SSH_IP"

# --------------------------------------------------
# Execute action
# --------------------------------------------------
TASK_STATUS=0

if [ -z "$ACTION" ] || [ -z "$SSH_USERNAME" ] || [ -z "$SSH_IP" ] || [ -z "$SSH_PORT" ]; then
    [ -z "$ACTION" ] && logErrorMessage "ACTION is not set"
    [ -z "$SSH_USERNAME" ] && logErrorMessage "SSH_USERNAME is not set"
    [ -z "$SSH_IP" ] && logErrorMessage "SSH_IP is not set"
    [ -z "$SSH_PORT" ] && logErrorMessage "SSH_PORT is not set"
    exit 1
fi

logInfoMessage "Performing action: $ACTION on $SSH_IP"

eval "$SERVER" "$ACTION" || {
    TASK_STATUS=1
    logErrorMessage "Failed to execute action on $SSH_IP"
}

logInfoMessage "Action execution finished"

# Save status
saveTaskStatus "$TASK_STATUS" "$ACTIVITY_SUB_TASK_CODE"

exit $TASK_STATUS
