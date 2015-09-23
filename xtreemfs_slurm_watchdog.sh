#!/bin/bash

###############################################################################
# Author: Robert Bärhold
# Concept by: Dr. Thorsten Schütt
# Date: 21.09.2015
#
# The watchdog script runs in the background checking periodically, whether the
# current allocation (/batch job) is still running and iff it isn't, it will
# stop all running XtreemFS servers including unmounting the volume and saving
# the logs, if it was specified in the env.sh.
#
# Call:
#   ./xtreemfs_slurm_watchdog.sh /path/to/env.sh
#
# Parameter:
#   $1 path to source file (env.sh)
#
###############################################################################

if [[ "$#" -ne 1 ]]; then
  echo "Wrong parameter count!"
  echo "Expecting 1 arguments; found: $#"
  exit 1
fi

SOURCE_FILE="$1"
BASEDIR=$(dirname $SOURCE_FILE)

if [[ ! -f $SOURCE_FILE ]]; then
  echo "SOURCE_FILE $SOURCE_FILE not found!"
  exit 1;
fi
source $SOURCE_FILE

function cleanup_node(){

  # unmount
  LOCAL_MOUNT_PATH=$(substitudeJobID "$LOCAL_MOUNT_PATH_GENERIC")
  $XTREEMFS_DIRECTORY/bin/umount.xtreemfs "$LOCAL_MOUNT_PATH"

  # save client-log?
  if [[ ! -z "$WATCHDOG_SAVELOGS" ]] && [[ "$WATCHDOG_SAVELOGS" == "-savelogs" ]] && [[ "$DEBUG_CLIENT_ACTIVE" == true ]]; then
    LOCAL_DIR=$(substitudeJobID "$LOCAL_DIR_GENERIC")
    CURRENT_JOB_FOLDER=$(substitudeJobID "$CURRENT_JOB_FOLDER_GENERIC")

    mkdir -p "$CURRENT_JOB_FOLDER/savedLogs"
    cp "$LOCAL_DIR/$(hostname)-client.log" "$CURRENT_JOB_FOLDER/savedLogs/"
  fi

  CURRENT_LOCAL_FOLDER=$(substitudeJobID "$LOCAL_DIR_GENERIC")

  # stop server
  for server_pid in $CURRENT_LOCAL_FOLDER/*$PID_FILENAME_EXTENSION; do
    pid_filename=$(basename $server_pid)
    server_name=${pid_filename%.*}
    if [[ $server_name != "watchdog" ]]; then
      $BASEDIR/xtreemfs_slurm_rstop.sh $SOURCE_FILE $server_name "$WATCHDOG_SAVELOGS"
    fi
  done

  # cleanup files
  rm -r $CURRENT_LOCAL_FOLDER

  return 0
}

IS_RUNNING=($(sacct -j $JOB_ID -b | grep $JOB_ID | awk '{print $2}'))
while [[ ${IS_RUNNING[0]} == "RUNNING" ]]; do
    sleep $WATCHDOG_INTERVAL
    IS_RUNNING=($(sacct -j $JOB_ID -b | grep $JOB_ID | awk '{print $2}'))
done

cleanup_node
exit $?

