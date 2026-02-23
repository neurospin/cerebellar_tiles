#!/usr/bin/env python3

import sys
import subprocess
import re
import os
from snakemake.utils import read_job_properties

jobscript = sys.argv[1]
job_properties = read_job_properties(jobscript)

# -----------------------------
# Extract Snakemake properties
# -----------------------------

rule = job_properties.get("rule", "unknown")
wildcards = job_properties.get("wildcards",{})
threads = job_properties.get("threads", 1)


resources = job_properties.get("resources", {})

log_path = resources.get("submission_logs", "logs/slurm")
runtime = resources.get("runtime", "3600")        # seconds
cores = resources.get("cores", 1)
partition = resources.get("partition", "normal")
qos = resources.get("qos", "normal")
project = resources.get("project", None)
filesystem = resources.get("filesystem", "work")
mem_mb = resources.get("mem_mb", 1781) # Default value of 1 core

merge_wildcards = "_".join(wildcards.values())

jobname = f"smk-{rule}-{merge_wildcards}" if merge_wildcards else f"smk-{rule}"

# -----------------------------
# Build ccc_msub command
# -----------------------------

# Creating log dirs
os.makedirs(log_path, exist_ok=True)

# Formatting command
cmd = [
        "ccc_msub",
        "-r", jobname,
        "-n", str(threads),
        "-T", str(runtime),
        "-q", partition,
        "-Q", qos,
        "-m", filesystem,
        "-c", str(cores),
        "-M", str(mem_mb),
        "-o" , f"{log_path}/{jobname}_%I.o",
        "-e" , f"{log_path}/{jobname}_%I.e",
        ]

if project:
    cmd.extend(["-A", project])

cmd.append(jobscript)


# -----------------------------
# Submit job
# -----------------------------

try:
    output = subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True)
except subprocess.CalledProcessError as e:
    print("Submission failed:\n", e.output, file=sys.stderr)
    sys.exit(1)

# -----------------------------
# Extract job ID
# -----------------------------

# Adjust regex if TGCC format differs
match = re.search(r'(\d+)', output)

if not match:
    print("Could not extract job ID from ccc_msub output:\n", output, file=sys.stderr)
    sys.exit(1)

jobid = match.group(1)

# IMPORTANT: Only print jobid
print(jobid)
