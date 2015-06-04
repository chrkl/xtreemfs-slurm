#!/bin/bash

# -o: output log file: %j for the job ID, %N for the name of the first executing node
# Change the path of the output logfile

#SBATCH -J xtreemfs_example_script
#SBATCH -N 2
#SBATCH -p CSR
#SBATCH -A csr
#SBATCH --eclusive

$HOME/xtreemfs-slurm/xtreemfs_slurm.sh start

# The path to the job_env.sh has to be equal to the path specified in the env.sh
source $(pwd)/slurm-$SLURM_JOB_ID/job_env.sh

# Example commands (should be removed)
srun hostname
echo "Mount directory: $WORK"

#############################################
#                                           #
#     Place your commands here              #
#                                           #
#############################################

$HOME/xtreemfs-slurm/xtreemfs_slurm.sh stop
