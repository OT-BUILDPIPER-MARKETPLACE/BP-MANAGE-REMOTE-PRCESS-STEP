#!/bin/bash

sleep  $SLEEP_DURATION

TASK_STATUS=0

if [ `isStrNonEmpty $ACTION` -ne 0 ]
then
    TASK_STATUS=1
    logErrorMessage "Action details are not provided please check"
elif [ `isStrNonEmpty ${PROCESS}` -ne 0 ]
then
    TASK_STATUS=1
    logErrorMessage "Process name not provided please check"
elif [ `isStrNonEmpty ${HOST}` -ne 0 ]
then
    TASK_STATUS=1
    logErrorMessage "Host alias not provided please check"
fi     

logInfoMessage "I'll perform [action: ${ACTION}] on [process: ${PROCESS}] at server [host: $HOST]" 

logInfoMessage "Received below arguments"
logInfoMessage "Action to be performed: ${ACTION}"
logInfoMessage "Process name on which actions is to be performed: ${PROCESS}"
logInfoMessage "Alias of host where action is to be performed: ${HOST}"

saveTaskStatus ${TASK_STATUS} ${ACTIVITY_SUB_TASK_CODE}