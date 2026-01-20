################################################
# Workflow for Cerebellum folding pipeline
# Author : Timothée SANCHEZ
# Date : 08-12-2026
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

onerror:
    print("~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
    print("~~~~~ Workflow failed. ~~~~~")
    print("~~~~~~~~~~~~~~~~~~~~~~~~~~~~")

# ----------------------------------------------
# Load configuration
# ----------------------------------------------

import yaml

configfile : "config.yaml"

# Retrieving subjects list
with open(config["subject_file"]) as f : 
	SUBJECTS = [lines.strip() for line in f if line.strip()]

SUBSTRUCTURES = config["substructures_masks"]

# Raw data path (root of the file; e.g. folder/<subject_folder>/...)
RAW_DATA = config["raw_data"]

OUTPUT_FOLDER = config["output_folder"]


# ----------------------------------------------
# Rule all
# ----------------------------------------------

rule all:
	input: 
        # Cropped images
	
        expand(f"{OUTPUT_FOLDER}/{{subject}}/cropped/{{subject}}_crop_{{substructure}}_t1w.nii.gz", subject=SUBJECTS, substructure=SUBSTRUCTURES.keys()) # Cropped T1w volume for visualisation
        expand(f"{OUTPUT_FOLDER}/{{subject}}/cropped/{{subject}}_crop_thresholded_{{substructure}}_mc.nii.gz", subject=SUBJECTS, substructure=SUBSTRUCTURES.keys()) #Final volume as nifti
        expand(f"{OUTPUT_FOLDER}/{{subject}}/{{subject}}_crop_{{substructure}}.npy", subject=SUBJECTS, substructure=SUBSTRUCTURES.keys()) #Finale volume

        # Masksf and transformation matrixes{diw

        expand(f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_mni_seg_post.nii.gz", subject=SUBJECTS)
        expand(f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_affine.txt", subject=SUBJECTS)
        expand(f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_inv-affine.txt", subject=SUBJECTS)

        expand(f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_binary_mask_cerebellum.txt", subject=SUBJECTS)
        expand(f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_{{substructure}}_mask.txt", subject=SUBJECTS, substructure=SUBSTRUCTURES.keys())

