#!/bin/bash

###############################################################################
# Author: Robert Bärhold
# Date: 18.05.2015
#
# Starting or stopping a distributed XtreemFS farm on cumulus.
# It is also possible to clone a git repository or to cleanup the local
# xtreemfs folder on each allocated node.
#
# Call: 
# 	./xtreemfsCumulus.sh (start|stop [-savelogs]|cleanup|clone)|
#
# Parameter:
# 	$1 [optional] -savelogs
 #		> only valid a "stop"
#
###############################################################################

set -e
shopt -s extglob

SOURCE_FILE=env.sh
source $SOURCE_FILE

LOCAL_DIR=""
SERVICE_PREFIX=""

# clones the git repository specified in the source file
function cloneGitHubRepository() {

  echo "cloneGitHubRepository"

  if [[ "$IS_CLONE_REPO" != "true" ]]; then
    return 0
  fi

  command -v git >/dev/null 2>&1 || {
    echo >&2 "Git is required to clone current GitHub repository. Aborting."
    exit 1
  }
  
  if [[ ! -z "$REPO_CLONE_LOCATION" ]] && [[ -d "$REPO_CLONE_LOCATION" ]]; then
    git clone "$GITHUB_REPO" "$REPO_CLONE_LOCATION"
  else
    echo "The given path $REPO_CLONE_LOCATION isn't a valid directory"
    exit 1
  fi
  
  return 0
}

# Checks generic variables and xtreemfs components and defines basic variables
function setup() {

  echo "Setup: Checking variables and environment"
  
  if [[ -z $SLURM_JOB_ID ]]; then
    echo "You're not inside an executing SLURM allocation"
    echo "Please alloc SLURM nodes with an active SLURM shell (no '--no-shell' argument)"
    exit 1
  fi


  if [[ ! -d "$XTREEMFS_DIRECTORY" ]] || [[ ! -f "$XTREEMFS_DIRECTORY/java/servers/dist/XtreemFS.jar" ]]; then
    echo -n "XtreemFS Directory $XTREEMFS_DIRECTORY does not exist" 
    echo " or doesn't include XtreemFS (missing ./java/XtreemFS.jar)."
    echo "Please adjust the SOURCE_FILE ($SOURCE_FILE) or the XTREEMFS_DIRECTORY ($XTREEMFS_DIRECTORY)."
    exit 1
  fi
  
  if [[ ! -e "$XTREEMFS_DIRECTORY/bin/mkfs.xtreemfs" ]] || [[ ! -e "$XTREEMFS_DIRECTORY/bin/rmfs.xtreemfs" ]] || 
     [[ ! -e "$XTREEMFS_DIRECTORY/bin/mount.xtreemfs" ]] || [[ ! -e "$XTREEMFS_DIRECTORY/bin/umount.xtreemfs" ]]; then
    echo "XtreemFS client hasn't been built correctly. One of the following files couldn't be found:"
    echo "mkfs.xtreemfs, rmfs.xtreemfs, mount.xtreemfs or umount.xtreemfs ."
    echo "Please run 'make client' inside the $XTREEMFS_DIRECTORY ."
    exit 1    
  fi
  
  for var in $LOCAL_DIR_GENERIC $XTREEMFS_LOCAL_GENERIC $SERVICE_PREFIX_GENERIC; do
    echo "$var" | grep %JOBID% > /dev/null || {
      echo "%JOBID% parameter was not found in variable: $var"
      exit 1
    }
  done
  
  for var in $CONFIG_FILENAME_GENERIC $LOG_FILENAME_GENERIC $PID_FILENAME_GENERIC; do
    echo "$var" | grep %NAME% > /dev/null || {
      echo "%NAME% parameter was not found in variable: $var"
      exit 1
    }
  done
  
  LOCAL_DIR=$(substitude_jobid "$LOCAL_DIR_GENERIC")
  SERVICE_PREFIX=$(substitude_jobid "$SERVICE_PREFIX_GENERIC")
  
}

# copies the dummy configurations and adjusts several parameter inside the configuration files
function prepareConfigs() {

  echo "Preparing configurations for DIR, MRC and OSD*"

  CURRENT_JOB_FOLDER=$(substitude_jobid "$CURRENT_JOB_FOLDER_GENERIC")
  mkdir -p "$CURRENT_JOB_FOLDER/config"
    
  ## DIR
  DIR_CONFIG_FILE="$CURRENT_JOB_FOLDER/config/$(substitude_name "$CONFIG_FILENAME_GENERIC" "DIR")"
  cp "$XTREEMFS_DIRECTORY/etc/xos/xtreemfs/dirconfig.properties" "$DIR_CONFIG_FILE"

  substitude_property "$DIR_CONFIG_FILE" "uuid" "uuid = $SERVICE_PREFIX-DIR"
  substitude_property "$DIR_CONFIG_FILE" "babudb.baseDir" "babudb.baseDir = $LOCAL_DIR/dir/datebase"
  substitude_property "$DIR_CONFIG_FILE" "babudb.logDir" "babudb.logDir = $LOCAL_DIR/dir/db-log"
  
  substitude_property "$DIR_CONFIG_FILE" "policy_dir" "policy_dir = $XTREEMFS_DIRECTORY/etc/xos/xtreemfs/policies"
    
  DIR_HOSTNAME=`scontrol show hostnames | head -n1`
  
  ## MRC
  
  MRC_CONFIG_FILE="$CURRENT_JOB_FOLDER/config/$(substitude_name "$CONFIG_FILENAME_GENERIC" "MRC")"
  cp "$XTREEMFS_DIRECTORY/etc/xos/xtreemfs/mrcconfig.properties" "$MRC_CONFIG_FILE"

  substitude_property "$MRC_CONFIG_FILE" "dir_service.host" "dir_service.host = $DIR_HOSTNAME"
  substitude_property "$MRC_CONFIG_FILE" "uuid" "uuid = $SERVICE_PREFIX-MRC"
  substitude_property "$MRC_CONFIG_FILE" "babudb.baseDir" "babudb.baseDir = $LOCAL_DIR/mrc/datebase"
  substitude_property "$MRC_CONFIG_FILE" "babudb.logDir" "babudb.logDir = $LOCAL_DIR/mrc/db-log"
  
  substitude_property "$MRC_CONFIG_FILE" "policy_dir" "policy_dir = $XTREEMFS_DIRECTORY/etc/xos/xtreemfs/policies"
  substitude_property "$MRC_CONFIG_FILE" "ssl.service_creds =" "ssl.service_creds = $XTREEMFS_DIRECTORY/etc/xos/xtreemfs/truststore/certs/mrc.p12"
  substitude_property "$MRC_CONFIG_FILE" "ssl.trusted_certs =" "ssl.trusted_certs = $XTREEMFS_DIRECTORY/etc/xos/xtreemfs/truststore/certs/trusted.jks"
  
  ## OSDs
  SKIP_NODE_COUNT=1
  if [[ "$SAME_DIR_AND_MRC_NODE" == false ]]; then
    SKIP_NODE_COUNT=2
  fi
  
  for (( counter=1; $counter <= $(( $NUMBER_OF_NODES - $SKIP_NODE_COUNT )); counter++ )) { 
  
    OSDNAME="OSD${counter}"
  
    OSD_CONFIG_FILE="$CURRENT_JOB_FOLDER/config/$(substitude_name "$CONFIG_FILENAME_GENERIC" "$OSDNAME")"
    cp "$XTREEMFS_DIRECTORY/etc/xos/xtreemfs/osdconfig.properties" "$OSD_CONFIG_FILE"

    substitude_property "$OSD_CONFIG_FILE" "dir_service.host" "dir_service.host = $DIR_HOSTNAME"
    substitude_property "$OSD_CONFIG_FILE" "uuid" "uuid = $SERVICE_PREFIX-OSD"
    substitude_property "$OSD_CONFIG_FILE" "object_dir" "object_dir = $LOCAL_DIR/$OSDNAME/objs"
        
    substitude_property "$OSD_CONFIG_FILE" "policy_dir" "policy_dir = $XTREEMFS_DIRECTORY/etc/xos/xtreemfs/policies"
    substitude_property "$OSD_CONFIG_FILE" "ssl.service_creds =" "ssl.service_creds = $XTREEMFS_DIRECTORY/etc/xos/xtreemfs/truststore/certs/osd.p12"
    substitude_property "$OSD_CONFIG_FILE" "ssl.trusted_certs =" "ssl.trusted_certs = $XTREEMFS_DIRECTORY/etc/xos/xtreemfs/truststore/certs/trusted.jks"
  }
}

# calls the start script remotely on each cumuslus node
function startServer() {
  DIR_HOSTNAME=`scontrol show hostnames | head -n1`
  srun -N1-1 --nodelist=$DIR_HOSTNAME xtreemfsCumulusRStart.sh "env.sh" "DIR" "DIR"
  
  SKIP_NODE_COUNT=1
  if [[ "$SAME_DIR_AND_MRC_NODE" == false ]]; then
    SKIP_NODE_COUNT=2
  fi  
  
  MRC_HOSTNAME=`scontrol show hostnames | head -n${SKIP_NODE_COUNT} | tail -n1`
  srun -N1-1 --nodelist=$MRC_HOSTNAME xtreemfsCumulusRStart.sh "env.sh" "MRC" "MRC"
  
  counter=1
  for osd_hostname in `scontrol show hostnames | tail -n +$(( $SKIP_NODE_COUNT + 1 ))`; do
    OSDNAME="OSD${counter}"
    srun -N1-1 --nodelist=$osd_hostname xtreemfsCumulusRStart.sh "env.sh" "OSD" "$OSDNAME"
    counter=$(($counter+1))
  done   
}

# deletes the local job folder on each cumulus node
function cleanUp() {

  for cumulus_host in `scontrol show hostnames`; do        
    echo "Cleaning... $cumulus_host of JOB: $SLURM_JOB_ID"
    srun -N1-1 --nodelist="$cumulus_host" rm -r "$LOCAL_DIR"
  done

  return 0
}

# calls the stop script remotely on each cumulus node, passing the savelogs flag if activated
function stopServerAndSaveLogs() {

  SAVE_LOGS=""
  if [[ ! -z "$1" ]] && [[ "$1" == "-savelogs" ]]; then
    echo "Saving logs is active"
    SAVE_LOGS="-savelogs"
  fi

  SKIP_NODE_COUNT=1
  if [[ "$SAME_DIR_AND_MRC_NODE" == false ]]; then
    SKIP_NODE_COUNT=2
  fi  
  
  counter=1
  for osd_hostname in `scontrol show hostnames | tail -n +$(( $SKIP_NODE_COUNT + 1 ))`; do
    OSDNAME="OSD${counter}"
    srun -N1-1 --nodelist=$osd_hostname xtreemfsCumulusRStop.sh "env.sh" "$OSDNAME" "$SAVE_LOGS"
    counter=$(($counter+1))
  done
  
  MRC_HOSTNAME=`scontrol show hostnames | head -n${SKIP_NODE_COUNT} | tail -n1`
  srun -N1-1 --nodelist=$MRC_HOSTNAME xtreemfsCumulusRStop.sh "env.sh" "MRC" "$SAVE_LOGS"
  
  DIR_HOSTNAME=`scontrol show hostnames | head -n1`
  srun -N1-1 --nodelist=$DIR_HOSTNAME xtreemfsCumulusRStop.sh "env.sh" "DIR" "$SAVE_LOGS"
    
  return 0
}

# unmounts the volume, deletes the volumes and stops and deletes the XtreemFS farm setup
function stop() {

  setup
  
  SKIP_NODE_COUNT=1
  if [[ "$SAME_DIR_AND_MRC_NODE" == false ]]; then
    SKIP_NODE_COUNT=2
  fi
  MRC_HOSTNAME=`scontrol show hostnames | head -n${SKIP_NODE_COUNT} | tail -n1`
  VOLUME_NAME=$(substitude_jobid "$VOLUME_NAME_GENERIC")

  echo "Stopping XtreemFS $SLURM_JOB_ID on cumulus..."

  $XTREEMFS_DIRECTORY/bin/umount.xtreemfs "$LOCAL_MOUNT_PATH"
  $XTREEMFS_DIRECTORY/bin/rmfs.xtreemfs -f $MRC_HOSTNAME/$VOLUME_NAME
  
  stopServerAndSaveLogs $1
  cleanUp

  return 0
}


# starts the XtreemFS farm setup, creates a volume and mounts it to the specified location
function start() {

  setup  
  
  SKIP_NODE_COUNT=1
  if [[ "$SAME_DIR_AND_MRC_NODE" == false ]]; then
    SKIP_NODE_COUNT=2
  fi
  DIR_HOSTNAME=`scontrol show hostnames | head -n1`
  MRC_HOSTNAME=`scontrol show hostnames | head -n${SKIP_NODE_COUNT} | tail -n1`

  VOLUME_NAME=$(substitude_jobid "$VOLUME_NAME_GENERIC")
  
  echo "Starting XtreemFS $SLURM_JOB_ID on cumulus..."

  prepareConfigs
  startServer
  
  mkdir -p $LOCAL_MOUNT_PATH
  
  $XTREEMFS_DIRECTORY/bin/mkfs.xtreemfs $VOLUME_PARAMETER $MRC_HOSTNAME/$VOLUME_NAME
  $XTREEMFS_DIRECTORY/bin/mount.xtreemfs $DIR_HOSTNAME/$VOLUME_NAME "$LOCAL_MOUNT_PATH"
  
  return 0  
}

result=0
case "$1" in
  start)
    start
    result=$?
    ;;
   stop)
    stop $2
    result=$?
    ;;
   cleanup)
    setup
    cleanUp
    result=$?
    ;;
   clone)
    cloneGitHubRepository
    result=$?
    ;;
   *)
    echo -e "Usage: $0 {start|stop [-savelogs]|cleanup|clone}\n"
    result=1
    ;;
esac

exit $result
