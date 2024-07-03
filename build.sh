#!/bin/bash

source functions.sh
source log-functions.sh
source str-functions.sh
source file-functions.sh
source aws-functions.sh

sleep $SLEEP_DURATION

ENCRYPTED_CREDENTIAL_SSH_KEY=$(getEncryptedCredential "$CREDENTIAL_MANAGEMENT" "$SSH_CREDENTIAL_NAME.CREDENTIAL_ACCESS_TOKEN_OR_KEY")
CREDENTIAL_SSH_KEY=$(getDecryptedCredential "$FERNET_KEY" "$ENCRYPTED_CREDENTIAL_SSH_KEY")

if [ ! -f "key.pem" ]; then
   echo "$CREDENTIAL_SSH_KEY" > key.pem && chmod 400 key.pem
fi

PROXY_OPTION=""
if [ "$USE_PROXY_SERVER" = "true" ]; then
    PROXY_OPTION="-o ProxyCommand=\"ssh -A -W %h:%p $SSH_USERNAME@$PROXY_SERVER_IP -i key.pem -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no\""
    logInfoMessage "Proxy server enabled. Allows the SSH client to connect to the target host through a proxy server specified by $PROXY_SERVER_IP"
fi

SERVER="ssh -i key.pem -p $SSH_PORT $PROXY_OPTION -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $SSH_USERNAME@$SSH_IP"


TASK_STATUS=0

if [ -z "$ACTION" ] || [ -z "$SSH_USERNAME" ] || [ -z "$SSH_IP" ] || [ -z "$SSH_PORT" ]; then
   [ -z "$ACTION" ] && logErrorMessage "ACTION is not set. Please set the INSTANCE_ID environment variable."
   [ -z "$SSH_USERNAME" ] && logErrorMessage "SSH_USERNAME is not set. Please set the INSTANCE_ID environment variable."
   [ -z "$SSH_IP" ] && logErrorMessage "SSH_IP is not set. Please set the SSH_IP environment variable."
   [ -z "$SSH_PORT" ] && logErrorMessage "SSH_PORT is not set. Please set the SSH_IP environment variable."
   exit 1
fi

if [ $TASK_STATUS -eq 0 ]; then
    logInfoMessage "I'll perform [action: ${ACTION}] at server [host: $SSH_IP]"

    logInfoMessage "Received below arguments"
    logInfoMessage "Action to be performed: ${ACTION}"
    logInfoMessage "Alias of host where action is to be performed: ${SSH_IP}"

    eval "$SERVER" "$ACTION"
    if [ $? -ne 0 ]; then
        TASK_STATUS=1
        logErrorMessage "Failed to execute action on ${SSH_IP}"
        exit 1
    else
        logInfoMessage "Action executed successfully on ${SSH_IP}"
    fi
fi

saveTaskStatus ${TASK_STATUS} ${ACTIVITY_SUB_TASK_CODE}
