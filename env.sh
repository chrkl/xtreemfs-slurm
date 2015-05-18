#!/bin/bash

###############################################################################
# Author: Robert Bärhold
# Date: 18.05.2015
#
# Settings file for the XtreemFS Farm script on cumulus.
# This file serves as source file for the different scripts.
# It contains user specific and general variables and shared functions.
# Boolean variables should be use with "true" and "false"
#
###############################################################################

####
 ##  System settings
####

SAME_DIR_AND_MRC_NODE=true
XTREEMFS_DIRECTORY="$(pwd)/xtreemfs"
LOCAL_PATH="/local/xtreemfs"

VOLUME_PARAMETER="" # e.g.: -a POSIX -p RAID0 -s 256 -w 1
LOCAL_MOUNT_PATH="/local/xtreemfs/mount"

NUMBER_OF_NODES=$SLURM_JOB_NUM_NODES #`scontrol show hostnames | wc -l`

####
 ##  Generic name and path settings
####

CURRENT_JOB_FOLDER_GENERIC="$(pwd)/cumulus-%JOBID%"
LOCAL_DIR_GENERIC="$LOCAL_PATH/%JOBID%"
SERVICE_PREFIX_GENERIC="xtreemfs-%JOBID%"
VOLUME_NAME_GENERIC="volume-%JOBID%"

PID_FILENAME_GENERIC="%NAME%.pid"
CONFIG_FILENAME_GENERIC="%NAME%.config"
LOG_FILENAME_GENERIC="%NAME%.log"

####
 ##  GITHUB CLONE
####

IS_CLONE_REPO=false
GITHUB_REPO=https://github.com/xtreemfs/xtreemfs.git
REPO_CLONE_LOCATION=$XTREEMFS_DIRECTORY/..

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

####
 ##  Substitute functions for generic variables
####


# Substitudes %JOBID% inside argument $1 with the slurm environment job id
function substitude_jobid() {
  echo "$1" | sed -e "s/%JOBID%/$SLURM_JOB_ID/g"
}


# Substitudes %name% in argument $1 with argument $2
function substitude_name() {
  echo "$1" | sed -e "s/%NAME%/$2/g"
}

# Searchs for the line containing $2 inside file $1 and replaces the line with $3,
# saving the new content back to file $1
function substitude_property() {
  LINE_NUMBER=`grep -nr "$2" "$1" | cut -d : -f 1`
  printf '%s\n' "${LINE_NUMBER}s#.*#$3#" w  | ed -s $1
}