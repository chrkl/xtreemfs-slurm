#!/usr/bin/env bash
#SBATCH --job-name stop-flink
#SBATCH --nodes=16
#SBATCH --partition=CUMU1

export FLINK_HOME=/scratch/bzcseibe/geoms/gms-software2/nov-2016/pyflink/flink-dist/target/flink-1.1-SNAPSHOT-bin/flink-1.1-SNAPSHOT

FLINK_NODES=(`scontrol show hostnames`)
echo "hosts: "$FLINK_NODES
echo "stopping flink JMs and TMs on all hosts..."

srun "${FLINK_HOME}"/bin/taskmanager.sh stop
srun "${FLINK_HOME}"/bin/jobmanager.sh stop

ps -ax | grep java
