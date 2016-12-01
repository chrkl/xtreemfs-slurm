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
#SBATCH --nodes=4
#SBATCH --exclusive

USAGE="Usage: sbatch -p<PARTITION> -A<ACCOUNT> flink-slurm-example.sh"

if [[ -z $SLURM_JOB_ID ]]; then
    echo "No Slurm environment detected. $USAGE"
    exit 1
fi

export FLINK_HOME=/scratch/bzcseibe/geoms/gms-software2/pyflink/flink-dist/target/flink-1.1-SNAPSHOT-bin/flink-1.1-SNAPSHOT

LOCAL_TMP_DIR="#"

# Custom conf directory for this job
export FLINK_CONF_DIR="${FLINK_HOME}"/conf-slurm-$SLURM_JOB_ID
cp -R "${FLINK_HOME}"/conf "${FLINK_CONF_DIR}"

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

# 80 percent of available memory
TASKMANAGER_HEAP=$(srun --nodes=1-1 --nodelist=$FLINK_MASTER awk '/MemTotal/ {printf( "%.2d\n", ($2 / 1024) * 0.8 )}' /proc/meminfo)
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
# PARALLELISM=$(cat $FLINK_HOME/conf/slaves | wc -l)
# PARALLELISM=$((PARALLELISM * NUM_CORES))
PARALLELISM=1
sed -i "/parallelism\.default/c\parallelism.default: $PARALLELISM" "${FLINK_CONF_DIR}"/flink-conf.yaml
echo "parallelism.default: $PARALLELISM"

echo "-----END FLINK CONFIG---"
echo

echo "Starting master on ${FLINK_MASTER} and slaves on ${FLINK_SLAVES[@]}."

srun --nodes=1-1 --nodelist=${FLINK_MASTER} "${FLINK_HOME}"/bin/jobmanager.sh start cluster

for slave in ${FLINK_SLAVES[@]}; do
    srun --nodes=1-1 --nodelist=$slave "${FLINK_HOME}"/bin/taskmanager.sh start
done

#srun --nodes=${#FLINK_SLAVES[*]}-${#FLINK_SLAVES[*]} --nodelist=\"${FLINK_SLAVES[@]}\" "${FLINK_HOME}"/bin/taskmanager.sh start
sleep 20

echo "Stopping flink cluster..."

#"${FLINK_HOME}"/bin/flink run "${FLINK_HOME}"/examples/EnumTrianglesBasic.jar file://$HOME/flink-slurm/edges.csv file://$HOME/flink-slurm/triangles.csv

for slave in ${FLINK_SLAVES[@]}; do
    srun --nodes=1-1 --nodelist=$slave "${FLINK_HOME}"/bin/taskmanager.sh stop
done

#srun --nodes=${#FLINK_SLAVES[*]}-${#FLINK_SLAVES[*]} --nodelist=\"${FLINK_SLAVES[@]}\" "${FLINK_HOME}"/bin/taskmanager.sh stop

srun --nodes=1-1 --nodelist=${FLINK_MASTER} "${FLINK_HOME}"/bin/jobmanager.sh stop

sleep 20

echo "Done."
