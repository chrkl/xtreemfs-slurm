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
#SBATCH --nodes=5
#SBATCH --partition=CUMU2
#SBATCH --exclusive
#### SBATCH --export=python=/nfs/scratch/bzcseibe/geoms/gms-software2/python_GFZ/python/bin/python
#### SBATCH --export=python3=/nfs/scratch/bzcseibe/geoms/gms-software2/python_GFZ/python/bin/python

USAGE="Usage: sbatch -p<PARTITION> -A<ACCOUNT> flink-slurm-example.sh"

if [[ -z $SLURM_JOB_ID ]]; then
    echo "No Slurm environment detected. $USAGE"
    exit 1
fi

export FLINK_HOME=/scratch/bzcseibe/geoms/gms-software2/nov-2016/pyflink/flink-dist/target/flink-1.1-SNAPSHOT-bin/flink-1.1-SNAPSHOT

LOCAL_TMP_DIR="/local/$USER/flink-tmp"

### SATELLITE_DATA_ORIGIN=/scratch/bzcseibe/geoms/satellite_data/gmsdb
SATELLITE_DATA_ORIGIN=/local/geomultisens/data
SATELLITE_DATA_SET=/landsatXMGRS_ENVI
LUCAS_DATA_SET=/lucasMGRS

CLASSIFICATION_OUTPUT_FOLDER=/scratch/bzcseibe/geoms/satellite_data/gmsdb/cumulus_output

SHAPE_NUMBERS=(32)
#SHAPE=(32/32TQU)
SHAPE=(32/32UPV 32/32UPE 32/32UPD 32/32UPC)
#SHAPE=(32/32UPV)
#SHAPE=(32/32TKS 32/32TMS 32/32TNT 32/32TPU 32/32UKB 32/32ULC 32/32ULV 32/32UMD 32/32UMU 32/32UNC 32/32UNU 32/32UPC 32/32UPU 32/32UQC 32/32UQV 32/32TLS 32/32TMT 32/32TNU 32/32TQT 32/32UKC 32/32ULD 32/32UMA 32/32UME 32/32UMV 32/32UND 32/32UNV 32/32UPD 32/32UPV 32/32UQD 32/32TLT 32/32TMU 32/32TPS 32/32TQU 32/32ULA 32/32ULE 32/32UMB 32/32UMF 32/32UNA 32/32UNE 32/32UPA 32/32UPE 32/32UQA 32/32UQE 32/32TLU 32/32TNS 32/32TPT 32/32UKA 32/32ULB 32/32ULU 32/32UMC 32/32UMG 32/32UNB 32/32UNF 32/32UPB 32/32UPF 32/32UQB 32/32UQU)

$HOME/xtreemfs-slurm/xtreemfs_slurm.sh start

CONFIG_FOLDER=$(pwd)/slurm-$SLURM_JOB_ID
source $CONFIG_FOLDER/job_env.sh

echo "work: "$WORK
echo "python:"
srun -N1-1 which python

# move input data to xtreemfs
echo 'move input data to xtreemfs'
echo 'creating folders'
srun -N1-1 mkdir $WORK/$SATELLITE_DATA_SET
srun -N1-1 mkdir $WORK/$LUCAS_DATA_SET

for SHAPE_NUMBER in ${SHAPE_NUMBERS[@]}; do
    srun -N1-1 mkdir $WORK/$SATELLITE_DATA_SET/$SHAPE_NUMBER
    srun -N1-1 mkdir $WORK/$LUCAS_DATA_SET/$SHAPE_NUMBER
done

### TODO fix this!!!!! this is a very mean hack! ###
echo 'scping data into work folder:'
time {
for tile in ${SHAPE[@]}; do
    ### srun -N1-1 cp -r $SATELLITE_DATA_ORIGIN$SATELLITE_DATA_SET/$tile $WORK/$SATELLITE_DATA_SET/32
    echo 'copying tile: '$SATELLITE_DATA_ORIGIN$SATELLITE_DATA_SET/$tile'to: '$WORK/$SATELLITE_DATA_SET/32
    srun -N1-1 scp -r geomultisens:$SATELLITE_DATA_ORIGIN$SATELLITE_DATA_SET/$tile $WORK/$SATELLITE_DATA_SET/32
    ### srun -N1-1 cp -r $SATELLITE_DATA_ORIGIN$LUCAS_DATA_SET/$tile $WORK/$LUCAS_DATA_SET/32
    echo 'copying corresponding lucas tile: '$SATELLITE_DATA_ORIGIN$LUCAS_DATA_SET/$tile' to: '$WORK/$LUCAS_DATA_SET/32
    srun -N1-1 scp -r geomultisens:$SATELLITE_DATA_ORIGIN$LUCAS_DATA_SET/$tile $WORK/$LUCAS_DATA_SET/32
done
}

echo 'copying into xtreemfs done.'

# correct data layout
time srun -N1-1 python /home/csr/bzcseibe/git/geoms-felix/python/dms2/dms2.py $WORK/$SATELLITE_DATA_SET

srun -N1-1 du -sh $WORK

#echo "dirs in xfs mount:"
#srun -N1 ls $WORK
#srun -N1 ls $WORK/landsatXMGRS_ENVI
#srun -N1 ls $WORK/landsatXMGRS_ENVI/32
#srun -N1 ls $WORK/lucasMGRS

# Custom conf directory for this job. we use a subdir from the xfs dir
export FLINK_CONF_DIR="${CONFIG_FOLDER}"/flink
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
PARALLELISM=$(cat $FLINK_CONF_DIR/slaves | wc -l)
echo "number of nodes: "$PARALLELISM
PARALLELISM=$((PARALLELISM * NUM_CORES))
#PARALLELISM=1
sed -i "/parallelism\.default/c\parallelism.default: $PARALLELISM" "${FLINK_CONF_DIR}"/flink-conf.yaml
echo "parallelism.default: $PARALLELISM"

# number of network buffers: parallelism * parallelism + 1024? better number?
NETWORK_BUFFERS=$((PARALLELISM * PARALLELISM + 1024))
echo "taskmanager.network.numberOfBuffers: "$NETWORK_BUFFERS
sed -i "/taskmanager\.network\.numberOfBuffers/c\taskmanager.network.numberOfBuffers: $NETWORK_BUFFERS" "${FLINK_CONF_DIR}"/flink-conf.yaml 

echo "-----END FLINK CONFIG---"
echo

# create configuration file for the flink gms job

CURR_DIR=(pwd)
FLINK_JOB_CONF_FILE=$CONFIG_FOLDER/flink/gms-job.cfg

cd /home/csr/bzcseibe/git/geoms-felix/python/fjcg
echo \"${SHAPE[@]}\"
python fjcg.py $WORK $CLASSIFICATION_OUTPUT_FOLDER $FLINK_JOB_CONF_FILE "${SHAPE[*]}" $PARALLELISM

cd $pwd

echo "job configuration file:"
cat $CONFIG_FOLDER/flink/gms-job.cfg


echo "Starting master on ${FLINK_MASTER} and slaves on ${FLINK_SLAVES[@]}."



srun "${FLINK_HOME}"/bin/taskmanager.sh stop
srun "${FLINK_HOME}"/bin/jobmanager.sh stop
sleep 10 
srun --nodes=1-1 --nodelist=${FLINK_MASTER} "${FLINK_HOME}"/bin/jobmanager.sh start cluster

for slave in ${FLINK_SLAVES[@]}; do
    srun --nodes=1-1 --nodelist=$slave mkdir $LOCAL_TMP_DIR
#    srun --nodes=1-1 --nodelist=$slave /bin/hostname
#    srun --nodes=1-1 --nodelist=$slave "${FLINK_HOME}"/bin/taskmanager.sh stop
#    srun --nodes=1-1 --nodelist=$slave "${FLINK_HOME}"/bin/jobmanager.sh stop
#    sleep 2
    srun --nodes=1-1 --nodelist=$slave "${FLINK_HOME}"/bin/taskmanager.sh start
done

#srun --nodes=${#FLINK_SLAVES[*]}-${#FLINK_SLAVES[*]} --nodelist=\"${FLINK_SLAVES[@]}\" "${FLINK_HOME}"/bin/taskmanager.sh start
sleep 20
#sleep 10

#"${FLINK_HOME}"/bin/flink run "${FLINK_HOME}"/examples/EnumTrianglesBasic.jar file://$HOME/flink-slurm/edges.csv file://$HOME/flink-slurm/triangles.csv

#time "${FLINK_HOME}"/bin/pyflink3.sh /scratch/bzcseibe/geoms/gms-software2/nov-2016/gms-hu-inf/src/gms/staging/CubeInputWithBCVariables.py - $CONFIG_FOLDER/flink/gms-job.cfg
time "${FLINK_HOME}"/bin/pyflink3.sh /scratch/bzcseibe/geoms/gms-software2/nov-2016/gms-hu-inf/src/gms/staging/CubeInputWithBCVariables.py - $FLINK_JOB_CONF_FILE

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
