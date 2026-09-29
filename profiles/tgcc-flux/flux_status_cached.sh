#!/bin/bash
# ============================================================================
# flux_status_cached.sh — status command for cluster-generic on TGCC/Flux.
#
# DROP-IN REPLACEMENT for flux_status.sh. Same contract: takes a flux jobid,
# prints exactly one of  running | success | failed.
#
# WHY: the previous version spawned 1-2 `flux jobs` calls PER STATUS CHECK.
# `flux jobs` is a python CLI (~0.5-0.8s startup), and cluster-generic checks
# active jobs SERIALLY, so one sweep over N jobs cost N x ~1.5s. That capped
# in-flight jobs at N ~= T_job / 1.5s ~= 12 for the cheap downstream rules
# (measured: job 5290272, 2026-07-27, busy_cores 5-15 with 2040 free).
#
# HOW: a single `flux jobs -a` snapshot is refreshed at most once per TTL and
# shared by every check. Per-check cost drops to an awk over a tmpfs file.
# Staleness only delays completion detection by <= TTL, which is harmless.
#
# DEPLOY TO (next to config.yaml):
#   ${ROOT}/cerebellar_tiles/profiles/tgcc-flux/flux_status_cached.sh
#
# Tunables (env):
#   FLUX_STATUS_TTL    cache lifetime in seconds        (default 10)
#   FLUX_STATUS_CACHE  cache path, must be node-local   (default /dev/shm/...)
#   FLUX_STATUS_COUNT  max jobs in the snapshot         (default 200000)
#
# NOTE: `flux jobs` defaults to --count=1000. Without an explicit large count
# the snapshot silently truncates and finished jobs read as "running" forever.
# ============================================================================

set -u

jid="${1:-}"

# No jobid: report running rather than failed, so a transient arg-passing
# glitch cannot kill a healthy job. (Same fail-safe as the original.)
if [ -z "${jid}" ]; then
    echo "running"
    exit 0
fi

TTL="${FLUX_STATUS_TTL:-10}"
COUNT="${FLUX_STATUS_COUNT:-200000}"
CACHE="${FLUX_STATUS_CACHE:-/dev/shm/flux_status_cache.${USER}.${FLUX_JOB_ID:-0}}"
LOCK="${CACHE}.lock"

# One line per job:  <f58 id>|<STATE>|<returncode>
# `{returncode}` is empty while a job is still running, hence the explicit
# separator rather than whitespace splitting.
FMT='{id.f58}|{state}|{returncode}'

refresh() {
    flux jobs -a -c "${COUNT}" --no-header -o "${FMT}" > "${CACHE}.tmp.$$" 2>/dev/null \
        && mv -f "${CACHE}.tmp.$$" "${CACHE}"
    rc=$?
    rm -f "${CACHE}.tmp.$$" 2>/dev/null
    return $rc
}

now=$(date +%s)
mtime=$(stat -c %Y "${CACHE}" 2>/dev/null || echo 0)
age=$(( now - mtime ))

if [ ! -s "${CACHE}" ]; then
    # Cold start: block once so the very first checks are not all misses.
    mkdir "${LOCK}" 2>/dev/null && trap 'rmdir "${LOCK}" 2>/dev/null' EXIT
    refresh
elif [ "${age}" -ge "${TTL}" ]; then
    # Exactly one refresher at a time; concurrent callers use the stale copy
    # rather than piling up `flux jobs` processes.
    if mkdir "${LOCK}" 2>/dev/null; then
        trap 'rmdir "${LOCK}" 2>/dev/null' EXIT
        refresh
    fi
fi

# Stale lock guard: if a refresher died, the lock would block all future
# refreshes and every job would freeze at its last cached state.
if [ -d "${LOCK}" ]; then
    lock_age=$(( now - $(stat -c %Y "${LOCK}" 2>/dev/null || echo "${now}") ))
    [ "${lock_age}" -gt 300 ] && rmdir "${LOCK}" 2>/dev/null
fi

line=$(awk -F'|' -v j="${jid}" '$1==j {print $2 "|" $3; exit}' "${CACHE}" 2>/dev/null)

if [ -z "${line}" ]; then
    # Not in the snapshot: either submitted since the last refresh, or the
    # snapshot truncated. Fall back to a direct query for this one job before
    # giving up -- cheap, because it is rare.
    line=$(flux jobs -a -no "${FMT}" "${jid}" 2>/dev/null | awk -F'|' '{print $2 "|" $3}')
fi

st="${line%%|*}"
rc="${line##*|}"

case "${st}" in
    DEPEND|PRIORITY|SCHED|RUN|CLEANUP)
        echo "running"
        ;;
    "")
        # Job not (yet) visible to flux. Treat as running: reporting "failed"
        # here would abort a job that has merely not registered yet.
        echo "running"
        ;;
    INACTIVE|*)
        if [ "${rc}" = "0" ]; then
            echo "success"
        else
            echo "failed"
        fi
        ;;
esac

# ALWAYS exit 0. cluster-generic retries a failing status command up to 10
# times with a BLOCKING 1s sleep each, inside the serial status loop -- a
# flaky status command therefore costs 10s of dispatch time per check.
exit 0
