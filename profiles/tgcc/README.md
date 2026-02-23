# Explanation of the profile

This profile is used to run snakemake jobs on the TGCC. 

## Requirements : 

To be able to use the profile `snakemake >=9.14.0` is required with the `cluster-generic-executor-plugin`. 

To check the availability of this plugin run : `snakemake -h` and check if the `--executor` flag as the `cluster-generic` plugin available.
 
## Files : 

This profile contains the following files :
- `config.yaml` : The profile specific configuration, it needs to be updated at each run (location of the logs of individual slurm submission is given in this file)
- `tgcc_submit.py` : Submission script used by snakemake to submit jobs to the TGCC 
- `status_cmd.sh` : Script used to determine the status of the submitted jobs

## Things to change for it to run

All the things to change are the following ones : 
- Path of the `cluster-generic-submit-cmd` to the absolute path of the `tgcc_submit.py`
- Path of the `cluster-generic-status-cmd` to the absolute path of the `status_cmd.sh`
- Path of `submission_logs` to the path of the slurm logs of each submission done by snakemake


