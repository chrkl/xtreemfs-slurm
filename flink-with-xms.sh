#!/usr/bin/env bash
################################################################################
#  Licensed to the Apache Software Foundation (ASF) under one
#  or more contributor license agreements.  See the NOTICE file
#  distributed with this work for additional information
#  regarding copyright ownership.  The ASF licenses this file
#  to you under the Apache License, Version 2.0 (the
#  "License"); you may not use this file except in compliance
#  with the License.  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
################################################################################

#SBATCH --job-name flink-slurm
#SBATCH --nodes=2
#SBATCH --exclusive

USAGE="Usage: sbatch -p<PARTITION> -A<ACCOUNT> flink-slurm-example.sh"

if [[ -z $SLURM_JOB_ID ]]; then
    echo "No Slurm environment detected. $USAGE"
    exit 1
fi

export FLINK_HOME=/scratch/bzcseibe/geoms/gms-software2/nov-2016/pyflink/flink-dist/target/flink-1.1-SNAPSHOT-bin/flink-1.1-SNAPSHOT

LOCAL_TMP_DIR="/local/$USER/flink-tmp"

SATELLITE_DATA_ORIGIN=/scratch/bzcseibe/geoms/satellite_data/gmsdb
SATELLITE_DATA_SET=/landsatXMGRS_ENVI
LUCAS_DATA_SET=/lucasMGRS

CLASSIFICATION_OUTPUT_FOLDER=/scratch/bzcseibe/geoms/satellite_data/gmsdb/cumulus_output

SHAPE_NUMBERS=(32)
SHAPE=(32/32TQU)

$HOME/xtreemfs-slurm/xtreemfs_slurm.sh start

CONFIG_FOLDER=$(pwd)/slurm-$SLURM_JOB_ID
source $CONFIG_FOLDER/job_env.sh

# move input data to xtreemfs
srun -N1-1 mkdir $WORK/$SATELLITE_DATA_SET
srun -N1-1 mkdir $WORK/$LUCAS_DATA_SET

for SHAPE_NUMBER in ${SHAPE_NUMBERS[@]}; do
    srun -N1-1 mkdir $WORK/$SATELLITE_DATA_SET/$SHAPE_NUMBER
    srun -N1-1 mkdir $WORK/$LUCAS_DATA_SET/$SHAPE_NUMBER
done

du -sh $WORK

### TODO fix this!!!!! this is a very mean hack! ###
for tile in ${SHAPE[@]}; do
    srun -N1-1 cp -r $SATELLITE_DATA_ORIGIN/$SATELLITE_DATA_SET/$tile $WORK/$SATELLITE_DATA_SET/32
    srun -N1-1 cp -r $SATELLITE_DATA_ORIGIN/$LUCAS_DATA_SET/$tile $WORK/$LUCAS_DATA_SET/32
done

du -sh $WORK

echo "dirs in xfs mount:"
srun /bin/hostname ; ls -R $WORK

# Custom conf directory for this job. we use a subdir from the xfs dir
export FLINK_CONF_DIR="${CONFIG_FOLDER}"/flink
cp -R "${FLINK_HOME}"/conf "${FLINK_CONF_DIR}"

# create configuration file for the flink gms job

CURR_DIR=(pwd)
FLINK_JOB_CONF_FILE=$CONFIG_FOLDER/flink/gms-job.cfg

cd /home/csr/bzcseibe/git/geoms-felix/python/fjcg
python fjcg.py $WORK $CLASSIFICATION_OUTPUT_FOLDER $FLINK_JOB_CONF_FILE "${SHAPE[@]}"

cd $pwd

cat $CONFIG_FOLDER/flink/gms-job.cfg

# First Slurm node is master, all others are slaves
FLINK_NODES=(`scontrol show hostnames`)

# Find out IP adresses of nodes
for ((i=0; i<${#FLINK_NODES[*]}; i++));
do
    NODE_IP=(`host ${FLINK_NODES[$i]} | awk '/has address/ { print $4 ; exit }'`)
    FLINK_NODES_IP[$i]=$NODE_IP
done

FLINK_MASTER=(${FLINK_NODES[0]})
FLINK_SLAVES=(${FLINK_NODES[@]:1})

printf "%s\n" "${FLINK_NODES_IP[0]}" > "${FLINK_CONF_DIR}/masters"
printf "%s\n" "${FLINK_NODES_IP[@]:1}" > "${FLINK_CONF_DIR}/slaves"

### Inspect nodes for CPU and memory and configure Flink accordingly ###

echo
echo "-----BEGIN FLINK CONFIG-----"

sed -i "/jobmanager\.rpc\.address/c\jobmanager.rpc.address: ${FLINK_NODES_IP[0]}" "${FLINK_CONF_DIR}"/flink-conf.yaml
echo "jobmanager.rpc.address: $FLINK_MASTER"

# 40 percent of available memory
JOBMANAGER_HEAP=$(srun --nodes=1-1 --nodelist=$FLINK_MASTER awk '/MemTotal/ {printf( "%.2d\n", ($2 / 1024) * 0.4 )}' /proc/meminfo)
sed -i "/jobmanager\.heap\.mb/c\jobmanager.heap.mb: $JOBMANAGER_HEAP" "${FLINK_CONF_DIR}"/flink-conf.yaml
echo "jobmanager.heab.mb: $JOBMANAGER_HEAP"

# 20 percent of available memory - we need to leave space for python!
TASKMANAGER_HEAP=$(srun --nodes=1-1 --nodelist=$FLINK_MASTER awk '/MemTotal/ {printf( "%.2d\n", ($2 / 1024) * 0.2 )}' /proc/meminfo)
sed -i "/taskmanager\.heap\.mb/c\taskmanager.heap.mb: $TASKMANAGER_HEAP" "${FLINK_CONF_DIR}"/flink-conf.yaml
echo "taskmanager.heap.mb: $TASKMANAGER_HEAP"

# set (node-)local tmp dir
sed -i "/taskmanager\.tmp\.dirs/c\taskmanager.tmp.dirs: $LOCAL_TMP_DIR" "${FLINK_CONF_DIR}"/flink-conf.yaml
echo "taskmanager.tmp.dirs: $LOCAL_TMP_DIR"

# number of phyical cores per task manager
NUM_CORES=$(srun --nodes=1-1 --nodelist=$FLINK_MASTER cat /proc/cpuinfo | egrep "core id|physical id" | tr -d "\n" | sed s/physical/\\nphysical/g | grep -v ^$ | sort | uniq | wc -l)
sed -i "/taskmanager\.numberOfTaskSlots/c\taskmanager.numberOfTaskSlots: $NUM_CORES" "${FLINK_CONF_DIR}"/flink-conf.yaml
echo "taskmanager.numberOfTaskSlots: $NUM_CORES"

# number of nodes * number of physical cores
PARALLELISM=$(cat $FLINK_HOME/conf/slaves | wc -l)
PARALLELISM=$((PARALLELISM * NUM_CORES))
#PARALLELISM=1
sed -i "/parallelism\.default/c\parallelism.default: $PARALLELISM" "${FLINK_CONF_DIR}"/flink-conf.yaml
echo "parallelism.default: $PARALLELISM"

echo "-----END FLINK CONFIG---"
echo

echo "Starting master on ${FLINK_MASTER} and slaves on ${FLINK_SLAVES[@]}."

srun --nodes=1-1 --nodelist=${FLINK_MASTER} "${FLINK_HOME}"/bin/jobmanager.sh start cluster

for slave in ${FLINK_SLAVES[@]}; do
#    srun --nodes=1-1 --nodelist=$slave mkdir $LOCAL_TMP_DIR
#    srun --nodes=1-1 --nodelist=$slave /bin/hostname
    srun --nodes=1-1 --nodelist=$slave "${FLINK_HOME}"/bin/taskmanager.sh start
done

#srun --nodes=${#FLINK_SLAVES[*]}-${#FLINK_SLAVES[*]} --nodelist=\"${FLINK_SLAVES[@]}\" "${FLINK_HOME}"/bin/taskmanager.sh start
sleep 20
#sleep 10

#"${FLINK_HOME}"/bin/flink run "${FLINK_HOME}"/examples/EnumTrianglesBasic.jar file://$HOME/flink-slurm/edges.csv file://$HOME/flink-slurm/triangles.csv

#time "${FLINK_HOME}"/bin/pyflink3.sh /scratch/bzcseibe/geoms/gms-software2/nov-2016/gms-hu-inf/src/gms/staging/CubeInputWithBCVariables.py - $CONFIG_FOLDER/flink/gms-job.cfg
time "${FLINK_HOME}"/bin/pyflink3.sh /scratch/bzcseibe/geoms/gms-software2/nov-2016/gms-hu-inf/src/gms/staging/ClassificationDriverWithBCVars.py - $FLINK_JOB_CONF_FILE

echo "Stopping flink cluster..."

for slave in ${FLINK_SLAVES[@]}; do
#    srun --nodes=1-1 --nodelist=$slave /bin/hostname
    srun --nodes=1-1 --nodelist=$slave "${FLINK_HOME}"/bin/taskmanager.sh stop
done

#srun --nodes=${#FLINK_SLAVES[*]}-${#FLINK_SLAVES[*]} --nodelist=\"${FLINK_SLAVES[@]}\" "${FLINK_HOME}"/bin/taskmanager.sh stop

srun --nodes=1-1 --nodelist=${FLINK_MASTER} "${FLINK_HOME}"/bin/jobmanager.sh stop


$HOME/xtreemfs-slurm/xtreemfs_slurm.sh stop -savelogs


#sleep 20

echo "Done."
