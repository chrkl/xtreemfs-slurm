#!/bin/bash

###############################################################################
# Author: Robert Bärhold
# Date: 18.05.2015
#
# Start script for the Xtreemfs Server.
# "rstart", cause it's called remote on a specific slurm node.
#
# Call:
# 	./xtreemfs_slurm_rstart.sh /path/to/env.sh (DIR|MRC|OSD) (DIR|MRC|OSD*)
#
# Parameter:
# 	$1 path to source file (env.sh)
# 	$2 Server type
# 	$3 Server name (instance)
#
###############################################################################

if [[ ! "$#" -ge 2 ]]; then
  echo "Wrong parameter count!"
  echo "Expecting at least 2 arguments; found: $#"
  exit 1
fi

SOURCE_FILE="$1"
SERVER_TYPE="$2"
SERVER_NAME="$3"

if [[ ! -f $SOURCE_FILE ]]; then
  echo "SOURCE_FILE $SOURCE_FILE not found!"
  exit 1;
fi
source $SOURCE_FILE

# Start xtreemfs server, redirect output into a log and save process id into pid file
function startServer() {

  SERVER_PID=$(substitudeName "$PID_FILENAME_GENERIC" "$SERVER_NAME")
  SERVER_LOG=$(substitudeName "$LOG_FILENAME_GENERIC" "$SERVER_NAME")
  SERVER_CONFIG=$(substitudeName "$CONFIG_FILENAME_GENERIC" "$SERVER_NAME")

  CURRENT_JOB_FOLDER=$(substitudeJobID "$CURRENT_JOB_FOLDER_GENERIC")
  CURRENT_LOCAL_FOLDER=$(substitudeJobID "$LOCAL_DIR_GENERIC")
  mkdir -p $CURRENT_LOCAL_FOLDER

  SERVER_TYPE_SMALL="${SERVER_TYPE,,}"

  #copy config file to local
  if [[ -e "$CURRENT_JOB_FOLDER/config/$SERVER_CONFIG" ]]; then
    cp "$CURRENT_JOB_FOLDER/config/$SERVER_CONFIG" "$CURRENT_LOCAL_FOLDER/$SERVER_CONFIG"
  else
    echo "Couldn't find the config file: $CURRENT_JOB_FOLDER/config/$SERVER_CONFIG"
    return 1
  fi

  #start server
  outputDebug -n "Starting XtreemFS $SERVER_TYPE Server on $(hostname): $SERVER_NAME ..."
  $JAVA_HOME/bin/java -ea ${JAVA_PROPERTIES} -cp ${JAVA_CLASSPATH} "org.xtreemfs.${SERVER_TYPE_SMALL}.${SERVER_TYPE}" "$CURRENT_LOCAL_FOLDER/$SERVER_CONFIG" >> "$CURRENT_LOCAL_FOLDER/$SERVER_LOG" 2>&1 &
  PROCPID="$!"
  echo "$PROCPID" > "$CURRENT_LOCAL_FOLDER/$SERVER_PID"
  sleep 1s

  if [[ -e "/proc/$PROCPID" ]]; then
   outputDebug "success"
  else
   outputDebug "failed"
   return 1
  fi

  return 0
}

function startWatchdog() {
  WATCHDOG_PID=$(substitudeName "$PID_FILENAME_GENERIC" "watchdog")
  CURRENT_LOCAL_FOLDER=$(substitudeJobID "$LOCAL_DIR_GENERIC")
  mkdir -p $CURRENT_LOCAL_FOLDER

  outputDebug -n "Starting Watchdog for XtreemFS on $(hostname) ..."

  BASEDIR=$(dirname $SOURCE_FILE)
  nohup $BASEDIR/xtreemfs_slurm_watchdog.sh $SOURCE_FILE > /dev/null 2>&1 &
  PROCPID="$!"
  echo "$PROCPID" > "$CURRENT_LOCAL_FOLDER/$WATCHDOG_PID"
  sleep 1s

  if [[ -e "/proc/$PROCPID" ]]; then
   outputDebug "success"
  else
   outputDebug "failed"
   return 1
  fi

  return 0
}

if [[ "$SERVER_TYPE" == "watchdog" ]]; then
  startWatchdog
else
  startServer
fi

exit $?
