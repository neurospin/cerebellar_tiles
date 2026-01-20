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

        # Mask and transformation matrixes

        expand(f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_mni_seg_post.nii.gz", subject=SUBJECTS)
        expand(f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_affine.txt", subject=SUBJECTS)
        expand(f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_inv-affine.txt", subject=SUBJECTS)

        expand(f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_binary_mask_cerebellum.txt", subject=SUBJECTS)
        expand(f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_{{substructure}}_mask.txt", subject=SUBJECTS, substructure=SUBSTRUCTURES.keys())


# ----------------------------------------------
#  All the rules
# ----------------------------------------------


rule acapulco_segmentation :

	container : acapulco-cpu

	input :
		raw_nifti = f"{RAW_DATA}/{{subject}}.nii.gz"

	params :
		method = config["segmentation_params"]["method"]

	output :
		output_directory = temp(directory(f"{OUTPUT_FOLDER}/{{subject}}/acapulco"))
		tmp_nii = temp(f"{OUTPUT_FOLDER}/{{subject}}/{{subject}}.nii")
		file_ok = f"{OUTPUT_FOLDER}/{{subject}}/.seg_done"

	shell :
	"""
	gunzip -c {raw_nifti} > {tmp_nii}
	mkdir -p {output_directory}
	acapulco.sh -i {tmp_nii} -o {output_directory} -m {params.method}
	touch .seg_done
	"""

rule copy_mask_and_transform :
	input :
		file_ok = f"{OUTPUT_FOLDER}/{{subject}}/.seg_done"
		acapulco_temp = f"{OUTPUT_FOLDER}/{{subject}}/acapulco"

	output :
	masks = [
	f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_affine.txt",
	f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_inv-affine.txt",
	f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_mni_seg_post.nii.gz",
	f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_mni_seg_post_inverse.nii.gz",
	]

	shell :
	"""
	cp {acapulco_temp}/{subject}_n4_affine.txt {output.masks[0]}
	cp {acapulco_temp}/{subject}_n4_inv-affine.txt {output.masks[1]} 
	cp {acapulco_temp}/{subject}_n4_mni_seg_post.nii.gz {output.masks[2]}
	cp {acapulco_temp}/{subject}_n4_mni_seg_post_inverse.nii.gz {output.masks[3]}
	"""


rule resampling_mni_registration_t1w :
	input :
		raw_nifti = f"{RAW_DATA}/{{subject}}.nii.gz"
		transf_matrix_acapulco = f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_affine.txt"

	output :
		resampled_t1w_mni = f"{OUTPUT_FOLDER}/{{subject}}/mni/{{subject}}_t1w_MNI_0-5iso.nii.gz"

	shell :
	"""
	module load {config["morphologist"]}

	python {workflow.basedir}/script/resampling.py --verbose --acapulco --input {raw_nifti} --output {resampled_t1w_mni} --transform_mask {transf_matrix_acapulco}
	"""


rule resampling_mni_registration_acapulco_mask :
	input :
		mask_native = f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_mni_seg_post_inverse.nii.gz"
		transf_matrix_acapulco = f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_affine.txt"

	output :
		resampled_mask_mni = "{{subject}}/mni/{{subject}}_seg_mni_0-5iso.nii.gz"

	shell :
	"""
	module load {config["morphologist"]}

	python {workflow.basedir}/script/resampling.py --verbose --acapulco --mask --input {mask_native} --output {resampled_mask_mni} --transform_mask {transf_matrix_acapulco}
	"""

rule compute_mean_curvature :
	input :
		t1w_mni = "{OUTPUT_FOLDER}/{{subject}}/mni/{{subject}}_t1w_MNI_0-5iso.nii.gz"

	output :
		 mean_curv_mni = "{OUTPUT_FOLDER}/{{subject}}/mni/{{subject}}_mc_MNI_0-5iso.nii.gz"

	shell :
	"""
	module load {config["morphologist"]}

	VipGeometry -m {config["vipgeometry_settings"]["method"]} -s {config["vipgeometry_settings"]["sigma"]} -i {t1w_mni} -o {mean_curv_mni}
	"""
