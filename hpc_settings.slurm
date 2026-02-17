#!/bin/bash
#MSUB -r UKB_cerebellar_tiles                                                                               # Name of the job submission
#MSUB -n 1
#MSUB -c 1
#MSUB -T 86400
#MSUB -o logs/slurm/UKB_cerebellar_tiles_%I.o    # Standard output. %I is the job id
#MSUB -e logs/slurm/UKB_cerebellar_tiles_%I.e    # Error output. %I is the job id
#MSUB -q rome                     									  # Queue
#MSUB -Q normal                                                                                           # Priority normal/ long
#MSUB -m workflash,scratch                                                                                # Available filesystems
#MSUB -A gen13800

echo "${HOSTNAME}"

#  Environments basic softwares

module switch dfldatadir/n4h00001
module load snakemake/9.14.0

snakemake --version


# Root dir
ROOT=path_to_root # Be careful here for the root dir !

# Snakemake files (smk, yml and json).
SMK=${ROOT}/cerebellar_tiles.smk                # Be careful here !
TSKCFG=${ROOT}/config.yaml    	# Be careful here !
CLUCFG=${ROOT}/Cluster_params.json	# Be careful here !

# logs entries
LOGS=${ROOT}/logs
LOGS_CLU=${LOGS}/smk/slurm                                          # Be careful here !
# Worker number limit
JOBS=150

#
cat <<-____HH
Processing project
     SM files:          $SMK
     Task specific:     $TSKCFG
     Cluster specifics: $CLUCFG

     See logs in      : ${LOGS}
     Running on       : ${JOBS} jobs
____HH

# emplacement des logs des jobs slurm/bridge tel que defini 
# dans le fichier json $CLUCFG
mkdir -p ${LOGS_CLU}

snakemake \
  --jobs ${JOBS} \
  -s ${SMK} \
  --configfile ${TSKCFG} \
  --cluster-config ${CLUCFG} \
  --verbose --printshellcmds --reason \
  --cluster ${SM_SLURM_SUBM_NODEP} \
  --cluster-status ${SM_SLURM_STATUS}  \
  --latency-wait 10

# end
echo "Job Cerebellar tiles finished"
