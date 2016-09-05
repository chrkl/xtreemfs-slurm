#!/bin/bash

###############################################################################
# Author: Robert Bärhold
# Date: 18.05.2015
#
# Settings file for the XtreemFS farm script on slurm.
# This file serves as source file for the different scripts.
# It contains user specific and general variables and shared functions.
# Boolean variables should be use with "true" and "false"
#
###############################################################################

####
 ##  System settings
####

__DEBUG=true

GENERATE_CONFIGS=true
SAME_DIR_AND_MRC_NODE=true
XTREEMFS_DIRECTORY="$HOME/xtreemfs"
LOCAL_PATH="/local/$USER/xtreemfs"

VOLUME_PARAMETER="" # e.g.: -a POSIX -p RAID0 -s 256 -w 1
KILLTERM="-SIGKILL" # or -SIGTERM

JOB_ID=$SLURM_JOB_ID # default the current ID
NUMBER_OF_NODES=$SLURM_JOB_NUM_NODES # or Number of OSD nodes + DIR ( + seperate MRC)
XTREEMFS_NODE_NAMES=`scontrol show hostnames` # flat list of node names seperated with space

MOUNT_OPTIONS=""

####
 ## Watchdog Settings
####

WATCHDOG_INTERVAL=5 # in seconds
WATCHDOG_SAVELOGS="" # "-savelogs"

####
 ##  Generic name and path settings
####

CURRENT_JOB_FOLDER_GENERIC="$(pwd)/slurm-%JOBID%"
CURRENT_JOB_ENV_FILE_GENERIC="$CURRENT_JOB_FOLDER_GENERIC/job_env.sh"
LOCAL_DIR_GENERIC="$LOCAL_PATH/%JOBID%"
LOCAL_MOUNT_PATH_GENERIC="$LOCAL_PATH/%JOBID%/mnt"
SERVICE_PREFIX_GENERIC="xtreemfs-%JOBID%"
VOLUME_NAME_GENERIC="volume-%JOBID%"

CONFIG_FILENAME_GENERIC="%NAME%.config"
LOG_FILENAME_GENERIC="%NAME%.log"
PID_FILENAME_EXTENSION=".pid"
PID_FILENAME_GENERIC="%NAME%$PID_FILENAME_EXTENSION"

####
 ## DEBUG Settings
####

DEBUG_CLIENT_ACTIVE=false
DEBUG_CLIENT_LEVEL="DEBUG"

#Default for all servers: 6 & all
DEBUG_DIR_LEVEL=6
DEBUG_DIR_CATEGORIES="all"
DEBUG_MRC_LEVEL=6
DEBUG_MRC_CATEGORIES="all"
DEBUG_OSD_LEVEL=6
DEBUG_OSD_CATEGORIES="all"

####
 ##  GITHUB CLONE
####

IS_CLONE_REPO=false
GITHUB_REPO=https://github.com/xtreemfs/xtreemfs.git
REPO_CLONE_LOCATION=$XTREEMFS_DIRECTORY/..

####
 ## Internal
####

SKIP_NODE_COUNT=0
if [[ "$SAME_DIR_AND_MRC_NODE" == false ]]; then
SKIP_NODE_COUNT=1
fi


XTREEMFS_NODES=($XTREEMFS_NODE_NAMES) # put into an array, easier access

####
 ##  Java settings
####

if [[ -z "$JAVA_HOME" ]]; then
  export JAVA_HOME=/usr
fi

JAVA_CLASSPATH="$XTREEMFS_DIRECTORY/java/servers/dist/XtreemFS.jar:"
JAVA_CLASSPATH+="$XTREEMFS_DIRECTORY/java/lib/BabuDB.jar:"
JAVA_CLASSPATH+="$XTREEMFS_DIRECTORY/java/flease/dist/Flease.jar:"
JAVA_CLASSPATH+="$XTREEMFS_DIRECTORY/java/lib/protobuf-java-2.5.0.jar:"
JAVA_CLASSPATH+="$XTREEMFS_DIRECTORY/java/foundation/dist/Foundation.jar:"
JAVA_CLASSPATH+="$XTREEMFS_DIRECTORY/java/lib/jdmkrt.jar:"
JAVA_CLASSPATH+="$XTREEMFS_DIRECTORY/java/lib/jdmktk.jar:"
JAVA_CLASSPATH+="$XTREEMFS_DIRECTORY/java/lib/commons-codec-1.3.jar"

JAVA_PROPERTIES=""  # e.g.: -Dfoo=bar

####
 ##  Substitute functions for generic variables
####


# Substitudes %JOBID% inside argument $1 with the slurm environment job id
function substitudeJobID() {
  echo "$1" | sed -e "s/%JOBID%/$JOB_ID/g"
}


# Substitudes %name% in argument $1 with argument $2
function substitudeName() {
  echo "$1" | sed -e "s/%NAME%/$2/g"
}

# Searchs for the line containing $2 inside file $1 and replaces the line with $3,
# saving the new content back to file $1
function substitudeProperty() {
  LINE_NUMBER=`grep -nr "$2" "$1" | cut -d : -f 1`
  printf '%s\n' "${LINE_NUMBER}s#.*#$3#" w  | ed -s $1
}

####
 ##  Shared functions
####

function outputDebug() {
  if [[ "$__DEBUG" == "true" ]]; then
    echo $@
  fi
}
