# Explanation of the pipeline

## Purpose of the pipeline
This pipeline aims to extract morphological features of the cerebellum as a 3D binary volume of a specified structure (whole cerebellum, vermis, ...)

## Workflow and requirements 

The pipeline workflow is managed by Snakemake to ease the distribution of the pipeline and the abstraction of parallelisation.
To run this pipeline the requirements are the following ones :
- Acapulco container (available on its [Gitlab](https://gitlab.com/shuohan/acapulco))
- `soma` library on python for nifti manipulation using `aims` (Available in [Morphologist tool](https://brainvisa.info/web/morphologist.html))
- `VipGeometry` for mean curvature computation (Available in [Morphologist tool](https://brainvisa.info/web/morphologist.html))

For instance, the pipeline runs on Morphologist 5.2 (`soma 5.2.0`), and Acapulco 0.3.0.

## Folder organization

```
.
├── cerebellum_folding.smk
├── config.yaml
├── containers
│   ├── acapulco-cpu.sif
│   └── acapulco-gpu.sif
├── envs
├── logs
├── profiles
├── README.md
├── inputs
├── results
├── scripts
└── subjects.txt
```

Explanation for the different files and folders : 
- `cerebellum_folding.smk` : Snakemake file that contains all the rules for the pipeline to be run.
- `config.yaml` : Configuration file for the different rules
- `containers` : Contains the different container logic.
- `envs` : Environements management
- `logs` : Folder to save log files
- `inputs` : Folder containing raw nifti
- `results` : Folder to save the main results
- `scripts` : Contains all the different scripts
- `subject.txt` : txt file containing all the subjects' ID that need to be processed by the pipeline

## How to run the pipeline :

This pipeline needs snakemake to run (installation via bioconda).

The steps to run the pipeline are the following ones : 
1. Prepare `config.yaml` file with you options (environements managements, parameters, paths, ...)
2. Run the command :
```
snakemake -s cerebellum_folding.smk --configfile <your_config> -j <number_jobs_max> --use-apptainer --apptainer-args "--bind <paths_necessary_to_access_data> --home $PWD"
```

