#!/bin/bash
#MSUB -r UKB_cerebellar_tiles                                                                               # Name of the job submission
#MSUB -n 16
#MSUB -c 128
#MSUB -T 18000
#MSUB -o logs_path/UKB_cerebellar_tiles_%I.o    # Standard output. %I is the job id
#MSUB -e logs_path/UKB_cerebellar_tiles_%I.e    # Error output. %I is the job id
#MSUB -q qos                     									  # Queue
#MSUB -Q long                                                                                           # Priority normal/ long
#MSUB -m workflash,scratch                                                                                # Available filesystems
#MSUB -A project_name
#MSUB -F # Flux management if needed

echo "${HOSTNAME}"
echo "Job start: $(date '+%F %T')"
SECONDS=0

#  Environments basic softwares

module switch dfldatadir/datadir
module use --append path_to/modulefiles
module load snakemake/9.14.0

snakemake --version


# Root dir
ROOT="root_hpc/" # Be careful here for the root dir !

# Snakemake files (smk, yml and json).
SMK=${ROOT}/cerebellar_tiles/cerebellar_tiles.smk                # Be careful here !
TSKCFG=${ROOT}/config/config_UKB_split_run_parallel.yaml # Be careful here !
PROFILE=${ROOT}/cerebellar_tiles/profiles/tgcc-flux
LOGS=${ROOT}/outputs/logs

# Locations
cat <<-____HH
Processing project
     SM files:          $SMK
     Task specific config:     $TSKCFG
     Profile used :     $PROFILE

     See logs in      : ${LOGS}
____HH

# ==================== PRE-FLIGHT CHECKS ====================
# Verify the allocation and the nested Flux instance are the size we asked for
# BEFORE launching, and abort early rather than burning the reservation at low
# concurrency. Effective parallelism = min(profile jobs, flux_cores / 9).
echo "==================== PRE-FLIGHT ===================="

echo "-- allocation (env) --"
env | grep -E '^(SLURM_(NNODES|NTASKS|CPUS_PER_TASK|JOB_NUM_NODES|NODELIST)|BRIDGE_MSUB)' | sort

echo "-- flux instance --"
echo "flux version : $(flux version 2>/dev/null | head -1)"
echo "brokers (should equal #nodes = 16): $(flux getattr size 2>/dev/null)"
flux uptime 2>/dev/null
flux resource info
flux resource list

# Total cores Flux actually manages (with a fallback parse for older flux)
FLUX_CORES=$(flux resource list -s all -no '{ncores}' 2>/dev/null | head -1)
if [ -z "${FLUX_CORES}" ]; then
  FLUX_CORES=$(flux resource info 2>/dev/null | grep -oiE '[0-9]+ *cores?' | grep -oE '[0-9]+' | head -1)
fi
JOBS=$(awk -F'[: ]+' '/^jobs:/{print $2}' "${PROFILE}/config.yaml")
ACA=9   # profile set-threads: acapulco_segmentation (the memory-bound rule)
GRP=6   # cores of the "subject_post" group job = widest layer of the per-subject
        # sub-DAG (the 6-sigma fan-out). Derived by snakemake, not set anywhere.

echo "flux_cores=${FLUX_CORES}  profile_jobs=${JOBS}"
if [ -n "${FLUX_CORES}" ]; then
  # Two job shapes coexist in one invocation, so report both phases.
  echo "phase 1 acapulco (${ACA} cores/job) : max $(( FLUX_CORES / ACA )) concurrent"
  echo "         -> effective = min(${JOBS}, $(( FLUX_CORES / ACA ))) = $(( JOBS < FLUX_CORES / ACA ? JOBS : FLUX_CORES / ACA ))"
  echo "phase 2 subject_post groups (${GRP} cores/job) : max $(( FLUX_CORES / GRP )) concurrent"
  echo "         -> effective = min(${JOBS}, $(( FLUX_CORES / GRP ))) = $(( JOBS < FLUX_CORES / GRP ? JOBS : FLUX_CORES / GRP ))"
fi

# GUARD: refuse to run if Flux got far fewer cores than planned (e.g. 1 node = 128)
MIN_FLUX_CORES="${MIN_FLUX_CORES:-1024}"
if [ -z "${FLUX_CORES}" ] || [ "${FLUX_CORES}" -lt "${MIN_FLUX_CORES}" ]; then
  echo "ABORT: Flux sees ${FLUX_CORES:-none} cores (expected >= ${MIN_FLUX_CORES}). Fix the allocation / Flux bootstrap; not wasting the reservation."
  exit 1
fi
echo "===================================================="

# ==================== LIVE MONITOR ====================
# Every 2 min, log core occupancy + job-state histogram + which rules are in
# flight + return codes, so the .o shows real concurrency and any failures.
( while true; do
    echo "[MON $(date +%T)] busy_cores=$(flux resource list -s allocated -no '{ncores}' 2>/dev/null) free_cores=$(flux resource list -s free -no '{ncores}' 2>/dev/null)  states: $(flux jobs -a --no-header -o '{state}' 2>/dev/null | sort | uniq -c | tr '\n' ' ')"
    echo "         rules: $(flux jobs -f running --no-header -o '{name}' 2>/dev/null | sed 's/^smk-//' | sort | uniq -c | tr '\n' ' ')"
    echo "         rc:    $(flux jobs -a --no-header -o '{returncode}' 2>/dev/null | sort | uniq -c | tr '\n' ' ')"
    sleep 120
  done ) &
MON_PID=$!
trap 'kill "${MON_PID}" 2>/dev/null' EXIT   # stop the monitor however the script ends

# ==================== SAFETY: clear any stale lock ====================
# A previous walltime kill can leave a lock. Safe here: the allocation just
# started, so no other snakemake can be holding this working directory.
echo "-- unlocking working directory --"
snakemake -s "${SMK}" --configfile "${TSKCFG}" --profile "${PROFILE}" --unlock

### Running snakemake
#
# `timeout` (SIGTERM at 4h40) stays below the -T 18000 (5h) wall so snakemake
# shuts down gracefully and removes its lock before Bridge sends SIGKILL.
# If you change -T, change this too (keep ~20 min of teardown margin). Budget
# for the onsuccess hook too: it walks the whole OUTPUT_FOLDER twice on the head
# node to sweep orphan .minf sidecars and prune empty dirs, which is a
# multi-minute Lustre metadata scan at 1000 subjects.
timeout --signal=TERM 16800 \
snakemake \
  -s ${SMK} \
  --configfile ${TSKCFG} \
  --profile ${PROFILE}
RC=$?

# end
echo "snakemake exit code: ${RC}"
echo "Job Cerebellar first part tiles finished"
echo "Job end: $(date '+%F %T')   elapsed: $((SECONDS/3600))h $(((SECONDS%3600)/60))m"
