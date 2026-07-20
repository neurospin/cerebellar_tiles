################################################
# Workflow for Cerebellum folding pipeline
# Author : Timothée SANCHEZ
# Date : 08-12-2026 (refactored 2026-05-29)
################################################

# ----------------------------------------------
# Global settings
# ----------------------------------------------

shell.prefix("set -eo pipefail;")

# Workflow completion hooks

onsuccess:
    print("+++++++++++++++++++++++++++++++++++++++++")
    print("+++++ Workflow successfully ended. ++++++")
    print("+++++++++++++++++++++++++++++++++++++++++")
    # aims writes a `<file>.minf` sidecar next to every volume; Snakemake's temp() does not
    # track it, so it is orphaned when its data file is temp-removed. When cleanup_intermediates
    # is on, sweep orphan .minf sidecars (data file gone) then prune the empty dirs they leave.
    if config.get("cleanup_intermediates", True):
        import os
        removed_minf = 0
        for root, _, files in os.walk(OUTPUT_FOLDER):
            for fn in files:
                if fn.endswith(".minf") and not os.path.exists(os.path.join(root, fn[:-len(".minf")])):
                    os.remove(os.path.join(root, fn))
                    removed_minf += 1
        pruned = 0
        for root, _, _ in os.walk(OUTPUT_FOLDER, topdown=False):
            if os.path.abspath(root) == os.path.abspath(OUTPUT_FOLDER):
                continue
            try:
                if not os.listdir(root):
                    os.rmdir(root)
                    pruned += 1
            except OSError:
                pass
        print(f"[cleanup] removed {removed_minf} orphan .minf sidecar(s), pruned {pruned} empty dir(s)")

onerror:
    print("~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
    print("~~~~~ Workflow failed. ~~~~~")
    print("~~~~~~~~~~~~~~~~~~~~~~~~~~~~")

# ----------------------------------------------
# Load configuration
# ----------------------------------------------

import yaml
import json

# Global parameters
RAW_PATH = config["raw_data"] # Raw data path (root of the file; e.g. folder/<subject_folder>/...)
PATH_STRUCTURE = config["data_structure"]
SUFFIX_SUBJECT = config["suffix_nifti"]

def SUBJECT_NIFTI_NAME(subject, suffix_subject=SUFFIX_SUBJECT) :
	if suffix_subject == "":
		return subject
	else :
		return f"{subject}_{suffix_subject}"

RAW_DATA = lambda subject : f"{RAW_PATH}/{subject}/{PATH_STRUCTURE}/{SUBJECT_NIFTI_NAME(subject, SUFFIX_SUBJECT)}.nii.gz"

OUTPUT_FOLDER = config["output_folder"] # Output of the pipeline
PLATFORM = config["execution"]
SCRIPTS = lambda script : f"{workflow.basedir}/scripts/{script}"
LOG_SNAKEMAKE = lambda log : f"{config['logs']}/{log}"
BENCHMARK_SNAKEMAKE = lambda bench : f"{config['benchmark']}/{bench}"

## Retrieving subjects list
with open(config["subject_list"]) as f :
	SUBJECTS = [line.strip() for line in f.readlines() if line.strip()]

SUBSTRUCTURES = config["substructures_masks"]
SIGMAS = config["sigmas"]

# Intermediate cleanup : wrap an output in temp() iff config["cleanup_intermediates"] is true (default true).
# Used by per-sigma rules in foliation_hessian.smk so intermediates can optionally be kept for QC.
def maybe_temp(path):
	return temp(path) if config.get("cleanup_intermediates", True) else path

# To adapt the environment to the machine we execute it on (TGCC or local)

def morphologist_env() :
	if PLATFORM == "tgcc" :
		return f"module unload snakemake && module load {config['environments']['module_tgcc']} &&"
	else :
		return f"pixi run --manifest-path {config['environments']['pixi_env']}"

MORPHO_ENV_PREFIX = morphologist_env()

# ----------------------------------------------
# Rule all
# ----------------------------------------------

rule all:
	input:
		# Acapulco-derived transforms and segmentations
		expand(f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_affine.txt", subject = SUBJECTS),
		expand(f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_inv-affine.txt", subject = SUBJECTS),
		expand(f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_mni_seg_post.nii.gz", subject = SUBJECTS),
		expand(f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_mni_seg_post_inverse.nii.gz", subject = SUBJECTS),

		# Cropped T1w (kept as anchor so the cropping path always builds)
		expand(f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_t1w_cropped.nii.gz", subject = SUBJECTS),
		expand(f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_seg_acapulco_cropped.nii.gz", subject = SUBJECTS),

		# Per-substructure fusion masks (cropped)
		expand(f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_corrected_{{substructure}}_cropped.nii.gz", subject = SUBJECTS, substructure = SUBSTRUCTURES.keys()),

		# Final foliation binary, cropped to substructure bbox
		expand(f"{OUTPUT_FOLDER}/{{subject}}/{{subject}}_{{substructure}}_foliation_binary_cropped.nii.gz", subject = SUBJECTS, substructure = SUBSTRUCTURES.keys()),

		# Pre-baked substructure z-score tiles (parallel to the binary tiles above)
		expand(f"{OUTPUT_FOLDER}/{{subject}}/{{subject}}_{{substructure}}_zscore_cropped.nii.gz", subject = SUBJECTS, substructure = config.get("prebaked_tiles", [])),

		# DL bundle: one .npz per subject (whole-cerebellum zscore+binary+labels, + pre-baked tiles)
		expand(f"{OUTPUT_FOLDER}/{{subject}}/{{subject}}_tiles.npz", subject = SUBJECTS),

		# Dataset-level QC manifest + qc table (gathers per-subject validity checks)
		f"{OUTPUT_FOLDER}/manifest.json",
		f"{OUTPUT_FOLDER}/qc.csv",


# ----------------------------------------------
#  Rule includes
# ----------------------------------------------

if PLATFORM == "tgcc" :
	include : f"{workflow.basedir}/rules/acapulco_segmentation_tgcc.smk"
else : #Local
	include : f"{workflow.basedir}/rules/acapulco_segmentation_local.smk"

include : f"{workflow.basedir}/rules/masks.smk"
include : f"{workflow.basedir}/rules/foliation_hessian.smk"
include : f"{workflow.basedir}/rules/packaging.smk"
include : f"{workflow.basedir}/rules/qc.smk"
