#!/bin/bash

###############################################################################
# Author: Robert Bärhold
# Date: 18.05.2015
#
# Stop script for the Xtreemfs Server.
# "rstop", cause it's called remote on a specific slurm node.
# 
# Call: 
# 	./xtreemfs_slurm_rstop.sh /path/to/env.sh (DIR|MRC|OSD*) [-savelogs]
#
# Parameter:
# 	$1 path to source file (env.sh)
# 	$2 Server name (instance)
# 	$3 [optional] "-savelogs"
#
###############################################################################

if [[ ! "$#" -ge 2 ]]; then
  echo "Wrong parameter count!"
  echo "Expecting at least 2 arguments; found: $#"
  exit 1
fi

SOURCE_FILE="$1"
SERVER_NAME="$2"
SAVE_LOG="$3"

if [[ ! -f $SOURCE_FILE ]]; then
  echo "SOURCE_FILE $SOURCE_FILE not found!"
  exit 1;
fi
source $SOURCE_FILE

CURRENT_LOCAL_FOLDER=$(substitudeJobID "$LOCAL_DIR_GENERIC")

# Save logs to current job folder
function saveLogs() {

  CURRENT_JOB_FOLDER=$(substitudeJobID "$CURRENT_JOB_FOLDER_GENERIC")
  SERVER_LOG=$(substitudeName "$LOG_FILENAME_GENERIC" "$SERVER_NAME")

  # if server log exists, create backup folder (if not exists) and copy log
  if [[ -f "$CURRENT_LOCAL_FOLDER/$SERVER_LOG" ]]; then
    mkdir -p "$CURRENT_JOB_FOLDER/savedLogs"
    cp "$CURRENT_LOCAL_FOLDER/$SERVER_LOG" "$CURRENT_JOB_FOLDER/savedLogs/$SERVER_LOG"
  else
    echo "Couldn't save log file ($SERVER_LOG), because it doesn't exist!"
    return 1
  fi
  
  return 0
}

# Killing the process of the xtreemfs server using the saved process id (pid)
function stopServer() {

  SERVER_PID=$(substitudeName "$PID_FILENAME_GENERIC" "$SERVER_NAME") 

  if [[ -f "$CURRENT_LOCAL_FOLDER/$SERVER_PID" ]]; then
    outputDebug -n "Stopping XtreemFS Process: ${SERVER_PID%.*} ..."
    
    
    result=0
    if [[ -e "/proc/$(<"$CURRENT_LOCAL_FOLDER/$SERVER_PID")" ]]; then
      kill $KILLTERM $(<"$CURRENT_LOCAL_FOLDER/$SERVER_PID")
      result=$?
    fi
    
    if [[ "$result" -eq 0 ]]; then
      outputDebug "success"
    else
      outputDebug "failed"
    fi
  else
    echo "PID file ($CURRENT_LOCAL_FOLDER/$SERVER_PID) not found!"
    return 1
  fi
  
  return 0
}

# stop watchdog
function stopWatchdog(){

  WATCHDOG_PID=$(substitudeName "$PID_FILENAME_GENERIC" "watchdog")

  if [[ -f "$CURRENT_LOCAL_FOLDER/$WATCHDOG_PID" ]]; then
    outputDebug -n "Stopping Watchdog for XtreemFS on $(hostname) ..."

    result=0
    if [[ -e "/proc/$(<"$CURRENT_LOCAL_FOLDER/$WATCHDOG_PID")" ]]; then
      kill -SIGKILL $(<"$CURRENT_LOCAL_FOLDER/$WATCHDOG_PID")
      result=$?
    fi

    if [[ "$result" -eq 0 ]]; then
      outputDebug "success"
    else
      outputDebug "failed"
    fi
  else
    echo "PID file ($CURRENT_LOCAL_FOLDER/$WATCHDOG_PID) not found!"
    return 1
  fi

  return 0
}

if [[ "$SERVER_NAME" == "watchdog" ]]; then
  stopWatchdog
else
  stopServer
fi

RESULT=$?

if [[ ! -z "$SAVE_LOG" ]] && [[ "$SAVE_LOG" == "-savelogs" ]]; then
  saveLogs
fi

exit $RESULT