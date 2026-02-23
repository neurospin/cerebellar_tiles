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

module switch dfldatadir/project
module use --append project/modulefiles
module load snakemake/9.14.0 #With cluster-generic-executor-plugin  

snakemake --version


# Root dir
ROOT="project_dir" # Be careful here for the root dir !

# Snakemake files (smk, yaml).
SMK=${ROOT}/scripts/cerebellar_tiles.smk                # Be careful here !
TSKCFG=${ROOT}/scripts/config.yaml    	# Be careful here !
PROFILE=${ROOT}/scripts/profiles/tgcc # Config to check !!
LOGS=${ROOT}/logs

# Maximum number of jobs
JOBS=20

# Locations
cat <<-____HH
Processing project
     SM files:          $SMK
     Task specific config:     $TSKCFG
     Profile used :     $PROFILE

     See logs in      : ${LOGS}
____HH

### Running snakemake

snakemake \
  --jobs ${JOBS} \
  -s ${SMK} \
  --configfile ${TSKCFG} \
  --profile ${PROFILE} \
  --until apply_cerebellum_bbox_mask_t1w \ #To apply until a rule
  --verbose 
  
# end
echo "Job Cerebellar first part tiles finished"
