#!/bin/bash

###############################################################################
# Author: Robert Bärhold
# Date: 18.05.2015
#
# Start script for the Xtreemfs Server.
# "RStart", cause it's called remote on a specific cumulus node.
# 
# Call: 
# 	./xtreemfsCumulusRStart.sh /path/to/env.sh (DIR|MRC|OSD) (DIR|MRC|OSD*)
#
# Parameter:
# 	$1 path to source file (env.sh)
# 	$2 Server type 
# 	$3 Server name (instance)
#
###############################################################################

if [[ "$#" -ne 3 ]]; then
  echo "Wrong parameter count!"
  echo "Expecting 3 arguments; found: $#"
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
  
  SERVER_PID=$(substitude_name "$PID_FILENAME_GENERIC" "$SERVER_NAME") 
  SERVER_LOG=$(substitude_name "$LOG_FILENAME_GENERIC" "$SERVER_NAME")
  SERVER_CONFIG=$(substitude_name "$CONFIG_FILENAME_GENERIC" "$SERVER_NAME")
  
  CURRENT_JOB_FOLDER=$(substitude_jobid "$CURRENT_JOB_FOLDER_GENERIC")
  CURRENT_LOCAL_FOLDER=$(substitude_jobid "$LOCAL_DIR_GENERIC")
  mkdir -p $CURRENT_LOCAL_FOLDER
  
  SERVER_TYPE_SMALL="${SERVER_TYPE,,}"
  
  #copy config file to local
  
  cp "$CURRENT_JOB_FOLDER/config/$SERVER_CONFIG" "$CURRENT_LOCAL_FOLDER/$SERVER_CONFIG"
  
  #start server
  echo -n "Starting XtreemFS $SERVER_TYPE Server on $(hostname): $SERVER_NAME ..."
  $JAVA_HOME/bin/java -ea -cp ${JAVA_CLASSPATH} "org.xtreemfs.${SERVER_TYPE_SMALL}.${SERVER_TYPE}" "$CURRENT_LOCAL_FOLDER/$SERVER_CONFIG" >> "$CURRENT_LOCAL_FOLDER/$SERVER_LOG" 2>&1 &
  PROCPID="$!"
  echo "$PROCPID" > "$CURRENT_LOCAL_FOLDER/$SERVER_PID"
  sleep 1s
  
  if [[ -e "/proc/$PROCPID" ]]; then
   echo "success"
  else
   echo "failed"
   return 1
  fi

  return 0
}

startServer

exit $?