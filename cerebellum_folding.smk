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
	SUBJECTS = [lines.strip() for line in f.readlines if line.strip()]

SUBSTRUCTURES = config["substructures_masks"]

# Raw data path (root of the file; e.g. folder/<subject_folder>/...)
RAW_DATA = config["raw_data"]

OUTPUT_FOLDER = config["output_folder"]


# ----------------------------------------------
# Rule all
# ----------------------------------------------

rule all:
	input:
		f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_affine.txt",
		f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_inv-affine.txt",
		f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_mni_seg_post.nii.gz",
		f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_mni_seg_post_inverse.nii.gz",
		f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_seg_acapulco_mni.nii.gz"
		f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_binary_acapulco_mni.nii.gz"

		f"{OUTPUT_FOLDER}/{{subject}}/mni/{{subject}}_t1w_mni.nii.gz"

		f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_binary_acapulco_cropped.nii.gz"
		f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_t1w_cropped.nii.gz"
		f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_corrected_substructure_cropped.nii.gz"
		f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_persistence_band.nii.gz"
		f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_thresh_persistence.nii.gz"
		f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_{{substructure}}_masked_persistence.nii.gz"

		f"{OUTPUT_FOLDER}/{{subject}}/{{subject}}_{{substructure}}_skeleton_cropped.nii.gz"


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
		resampled_t1w_mni = f"{OUTPUT_FOLDER}/{{subject}}/mni/{{subject}}_t1w_mni.nii.gz"
	
	params :
		name_morphologist = config["morphologist"]

	shell :
	"""
	module load {name_morphologist}

	python {workflow.basedir}/script/resampling.py --verbose --acapulco --input {raw_nifti} --output {resampled_t1w_mni} --transform_mask {transf_matrix_acapulco}
	"""


rule resampling_mni_registration_acapulco_mask :
	input :
		mask_native = f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_mni_seg_post_inverse.nii.gz"
		transf_matrix_acapulco = f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_affine.txt"

	output :
		resampled_mask_mni = f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_seg_acapulco_mni.nii.gz"

	params :
		name_morphologist = config["morphologist"]

	shell :
	"""
	module load {name_morphologist}

	python {workflow.basedir}/script/resampling.py --verbose --acapulco --mask --input {mask_native} --output {resampled_mask_mni} --transform_mask {transf_matrix_acapulco}
	"""

rule binarisation_acapulco_mask :
	input :
		mask_acapulco =f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_seg_acapulco_mni.nii.gz"
	
	output : 
		binary_mask_acapulco = f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_binary_acapulco_mni.nii.gz"
	
	params :
		name_morphologist = config["morphologist"]

	shell : 
	"""
	module load {name_morphologist}

	python {workflow.basedir}/script/binarisation_mask.py --input {mask_acapulco} --output {binary_mask_acapulco}
	"""

rule dilatation_mask_substructure :
	input : 
		mask = lambda wildcards : SUBSTRUCTURES[wildcards.substructure]

	output : 
		f"{OUTPUT_FOLDER}/common/{{substructure}}_dilated_mask.nii.gz"

	params :
		name_morphologist = config["morphologist"]
		dilatation = config["dilatation_substructure"]

	shell : 
	"""
	module load {name_morphologist}

	python {workflow.basedir}/script/dilatation_mask.py --input {input.mask} --output {output} --dilatation {dilatation}
	"""

rule compute_bbox_cerebellum :
	input : 
		mask_cerebellum = config["cerebellum_atlas_path_mask"]

	output :
		f"{OUTPUT_FOLDER}/common/bbox_cerebellum_atlas.npy"
	
	params :
		name_morphologist = config["morphologist"]
		dilatation_cerebellum_mask = config["dilatation_cerebellum_atlas_mask"]
	
	shell : 
	"""
	module load {name_morphologist}

	python {workflow.basedir}/script/compute_bounding_box.py --input mask_cerebellum --output {output} --dilatation {dilatation_cerebellum_mask}
	"""

rule apply_cerebellum_bbox_mask_acapulco : 
	input : 
		mask_acapulco = f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_binary_acapulco_mni.nii.gz"
		bbox_cerebellum = f"{OUTPUT_FOLDER}/common/bbox_cerebellum_atlas.npy"

	output : 
		f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_binary_acapulco_cropped.nii.gz"
	
	params :
		name_morphologist = config["morphologist"]

	shell :
	"""
	module load {name_morphologist}

	python {workflow.basedir}/script/apply_bounding_box.py --bbox_npy {input.bbox_cerebellum} --input {input.mask_acapulco} --output {output}
	"""

rule apply_cerebellum_bbox_mask_t1w : 
	input : 
		mask_t1w = f"{OUTPUT_FOLDER}/{{subject}}/mni/{{subject}}_t1w_mni.nii.gz"
		bbox_cerebellum = f"{OUTPUT_FOLDER}/common/bbox_cerebellum_atlas.npy"

	output : 
		f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_t1w_cropped.nii.gz"
	
	params :
		name_morphologist = config["morphologist"]

	shell :
	"""
	module load {name_morphologist}

	python {workflow.basedir}/script/apply_bounding_box.py --bbox_npy {input.bbox_cerebellum} --input {input.mask_t1w} --output {output}
	"""

rule apply_cerebellum_bbox_mask_substructure : 
	input : 
		mask_substructure = f"{OUTPUT_FOLDER}/common/{{substructure}}_dilated_mask.nii.gz"
		bbox_cerebellum = f"{OUTPUT_FOLDER}/common/bbox_cerebellum_atlas.npy"

	output : 
		f"{OUTPUT_FOLDER}/common/{{substructure}}_mask_cropped.nii.gz"
	
	params :
		name_morphologist = config["morphologist"]

	shell :
	"""
	module load {name_morphologist}

	python {workflow.basedir}/script/apply_bounding_box.py --bbox_npy {input.bbox_cerebellum} --input {input.mask_substructure} --output {output}
	"""

rule fusion_acapulco_substructures_mask :
	input :
		mask_substructure = f"{OUTPUT_FOLDER}/common/{{substructure}}_mask_cropped.nii.gz"
		mask_acapulco = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_binary_acapulco_cropped.nii.gz"
	
	output : 
		f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_corrected_substructure_cropped.nii.gz"

	params :
		name_morphologist = config["morphologist"]
	
	shell : 
	"""
	module load {name_morphologist}

	python {workflow.basedir}/script/fusion_mask.py --mask_1 {input.mask_substructure} --mask_2 {input.mask_acapulco} --output {output}
	"""

rule compute_multiscale_mean_curvature_persistence :
	input :
		corrected_mask_substructure = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_corrected_substructure_cropped.nii.gz"
		cropped_T1w = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_t1w_cropped.nii.gz"
	
	output : 
		persistence_mean_curv = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_persistence_band.nii.gz"
		thresholded_persistence_mean_curv = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_thresh_persistence.nii.gz"
	
	params : 
		name_morphologist = config["morphologist"]
		sigmas = " ".join(map(str, config["sigmas"]))
		thresh_persis = config["threshold_persistence"]
		min_quantile = config["min_quantile"]
		max_quantile = config["max_quantile"]
	
	shell :
	"""
	module load {name_morphologist}

	python {workflow.basedir}/script/persistence_mean_curvature.py \
	--input {input.cropped_T1w} \
	--output_persistence {output.persistence_mean_curv} \
	--output_thresholded {output.thresholded_persistence_mean_curv} \
	--cerebellum_mask {input.corrected_mask_substructure} \
	--threshold_persistence {thresh_persis} \
	--min_quantile {min_quantile]} \
	--max_quantile {max_quantile]} \
	--sigmas {sigmas}
	"""

rule apply_mask_corrected_substructure :
	input : 
		thresholded_persistence_mean_curv = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_thresh_persistence.nii.gz"
		corrected_mask_substructure = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_corrected_substructure_cropped.nii.gz"
	
	output : 
		f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_{{substructure}}_masked_persistence.nii.gz"
	
	params : 
		name_morphologist = config["morphologist"]
	
	shell :
	"""
	module load {name_morphologist}

	python {workflow.basedir}/script/apply_mask.py --input {thresholded_persistence_mean_curv} --mask {corrected_mask_substructure} --output {output}
	"""

rule compute_bbox_substructure : 
	input : 
		dilated_mask_substructure = f"{OUTPUT_FOLDER}/common/{{substructure}}_mask_cropped.nii.gz"

	output : 
		f"{OUTPUT_FOLDER}/common/{{substructure}}_bbox.npy"
	
	params : 
		name_morphologist = config["morphologist"]
	
	shell :
	"""
	module load {name_morphologist}

	python {workflow.basedir}/script/compute_bbox_cerebellum.py --input  {dilated_mask_substructure} --output {output} --dilatation 0
	"""

rule apply_bbox_substructure : 
	input : 
		substructure_bbox = f"{OUTPUT_FOLDER}/common/{{substructure}}_bbox.npy"
		masked_persistence = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_{{substructure}}_masked_persistence.nii.gz"
	
	output : 
		cropped_substructure = f"{OUTPUT_FOLDER}/{{subject}}/{{subject}}_{{substructure}}_skeleton_cropped.nii.gz"
	
	params : 
		name_morphologist = config["morphologist"]
	
	shell :
	"""
	module load {name_morphologist}

	python {workflow.basedir}/script/apply_bounding_box.py --input {masked_persistence} --output {cropped_subctructure} --bbox_npy substructure_bbox
	"""
