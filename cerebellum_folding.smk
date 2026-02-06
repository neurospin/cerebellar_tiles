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

# Global parameters
RAW_PATH = config["raw_data"] # Raw data path (root of the file; e.g. folder/<subject_folder>/...)
PATH_STRUCTURE = config["data_structure"]
RAW_DATA = lambda s : f"{RAW_PATH}/{s}/{PATH_STRUCTURE}/{s}.nii.gz"
OUTPUT_FOLDER = config["output_folder"] # Output of the pipeline
PLATFORM = config["execution"]
SCRIPTS = lambda script : f"{workflow.basedir}/scripts/{script}"
LOG_SNAKEMAKE = lambda log : f"{config['logs']}/{log}"

## Retrieving subjects list
with open(config["subject_list"]) as f : 
	SUBJECTS = [line.strip() for line in f.readlines() if line.strip()]

SUBSTRUCTURES = config["substructures_masks"]


# To adapt the environment to the machine we execute it on (TGCC or local)

def morphologist_env() :
	if PLATFORM == "tgcc" :
		return f"module load {config['environments']['module_tgcc']} &&"
	else :
		return f"pixi run --manifest-path {config['environments']['pixi_env']}"

MORPHO_ENV_PREFIX = morphologist_env()

# ----------------------------------------------
# Rule all
# ----------------------------------------------

rule all:
	input:
		expand(f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_affine.txt", subject = SUBJECTS),
		expand(f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_inv-affine.txt", subject = SUBJECTS),
		expand(f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_mni_seg_post.nii.gz", subject = SUBJECTS),
		expand(f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_mni_seg_post_inverse.nii.gz", subject = SUBJECTS),
		expand(f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_seg_acapulco_mni.nii.gz", subject = SUBJECTS),
		expand(f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_binary_acapulco_mni.nii.gz", subject = SUBJECTS),

		expand(f"{OUTPUT_FOLDER}/{{subject}}/mni/{{subject}}_t1w_mni.nii.gz", subject = SUBJECTS),
		
		expand(f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_binary_acapulco_cropped.nii.gz", subject = SUBJECTS),
		expand(f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_t1w_cropped.nii.gz", subject = SUBJECTS),
		expand(f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_corrected_{{substructure}}_cropped.nii.gz", subject = SUBJECTS, substructure = SUBSTRUCTURES.keys()),
		expand(f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_{{substructure}}_persistence_band.nii.gz", subject = SUBJECTS, substructure = SUBSTRUCTURES.keys()),
		expand(f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_{{substructure}}_thresh_persistence.nii.gz", subject = SUBJECTS, substructure = SUBSTRUCTURES.keys()),

		expand(f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_{{substructure}}_masked_persistence.nii.gz", subject = SUBJECTS, substructure = SUBSTRUCTURES.keys()),
		expand(f"{OUTPUT_FOLDER}/{{subject}}/{{subject}}_{{substructure}}_skeleton_cropped.nii.gz", subject = SUBJECTS, substructure = SUBSTRUCTURES.keys())


# ----------------------------------------------
#  All the rules
# ----------------------------------------------


rule acapulco_segmentation :
	container : "containers/acapulco-cpu.sif"
	input :
		raw_nifti = lambda wildcards : RAW_DATA(wildcards.subject)

	output :
		output_directory = temp(directory(f"{OUTPUT_FOLDER}/{{subject}}/acapulco")),

	params :
		method = config["segmentation_params"]["method"]
	
	log : 
		LOG_SNAKEMAKE("acapulco_segmentation/{subject}.log")

	shell : """
	mkdir -p {output.output_directory}
	acapulco.sh -i {input.raw_nifti} -o {output.output_directory} -m {params.method} > {log} 2>&1
	"""

rule copy_mask_and_transform :
	input :
		acapulco_temp = f"{OUTPUT_FOLDER}/{{subject}}/acapulco"

	output :
		masks = [
		f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_affine.txt",
		f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_inv-affine.txt",
		f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_mni_seg_post.nii.gz",
		f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_mni_seg_post_inverse.nii.gz",
		]

	log : 
		LOG_SNAKEMAKE("copy_masks/{subject}.log")

	shell : """
	cp {input.acapulco_temp}/mni/{wildcards.subject}_n4_affine.txt {output.masks[0]}
	cp {input.acapulco_temp}/mni/{wildcards.subject}_n4_inv-affine.txt {output.masks[1]}
	cp {input.acapulco_temp}/parc/{wildcards.subject}_n4_mni_seg_post.nii.gz {output.masks[2]}
	cp {input.acapulco_temp}/{wildcards.subject}_n4_mni_seg_post_inverse.nii.gz {output.masks[3]}
	"""


rule resampling_mni_registration_t1w :
	input :
		raw_nifti = lambda wildcards : RAW_DATA(wildcards.subject),
		transf_matrix_acapulco = f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_affine.txt"

	output :
		resampled_t1w_mni = f"{OUTPUT_FOLDER}/{{subject}}/mni/{{subject}}_t1w_mni.nii.gz"
	
	params :
		script = SCRIPTS("resampling.py")
	
	log : 
		LOG_SNAKEMAKE("resampling_t1w/{subject}.log")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} --acapulco --input {input.raw_nifti} --output {output.resampled_t1w_mni} --transform_mat {input.transf_matrix_acapulco} --verbose > {log} 2>&1
	"""


rule resampling_mni_registration_acapulco_mask :
	input :
		mask_native = f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_mni_seg_post_inverse.nii.gz",
		transf_matrix_acapulco = f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_affine.txt"

	output :
		resampled_mask_mni = f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_seg_acapulco_mni.nii.gz"

	params :
		script = SCRIPTS("resampling.py")

	log : 
		LOG_SNAKEMAKE("resampling_acapulco/{subject}.log")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} --acapulco --mask --input {input.mask_native} --output {output.resampled_mask_mni} --transform_mat {input.transf_matrix_acapulco} --verbose > {log} 2>&1
	"""

rule binarisation_acapulco_mask :
	input :
		mask_acapulco =f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_seg_acapulco_mni.nii.gz"
	
	output : 
		binary_mask_acapulco = f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_binary_acapulco_mni.nii.gz"
	
	params :
		script = SCRIPTS("binarisation_mask.py")

	log : 
		LOG_SNAKEMAKE("binarisation_acapulco/{subject}.log")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} --input {input.mask_acapulco} --output {output.binary_mask_acapulco} --verbose > {log} 2>&1
	"""

rule dilatation_mask_substructure :
	input : 
		mask = lambda wildcards : SUBSTRUCTURES[wildcards.substructure]

	output : 
		f"{OUTPUT_FOLDER}/common/{{substructure}}_dilated_mask.nii.gz"

	params :
		dilatation = config["dilatation_substructure"],
		script = SCRIPTS("dilatation_mask.py")

	log : 
		LOG_SNAKEMAKE("dilatation_mask_sub/{substructure}.log")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} --input {input.mask} --output {output} --dilatation {params.dilatation} --verbose > {log} 2>&1
	"""

rule compute_bbox_cerebellum :
	input : 
		mask_cerebellum = config["cerebellum_atlas_path_mask"]

	output :
		f"{OUTPUT_FOLDER}/common/bbox_cerebellum_atlas.npy"
	
	params :
		dilatation_cerebellum_mask = config["dilatation_cerebellum_atlas_mask"],
		script = SCRIPTS("compute_bounding_box.py")
	
	log : 
		LOG_SNAKEMAKE("cerebellum_bbox.log")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} --input {input.mask_cerebellum} --output {output} --dilatation {params.dilatation_cerebellum_mask} --verbose > {log} 2>&1
	"""

rule apply_cerebellum_bbox_mask_acapulco : 
	input : 
		mask_acapulco = f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_binary_acapulco_mni.nii.gz",
		bbox_cerebellum = f"{OUTPUT_FOLDER}/common/bbox_cerebellum_atlas.npy"

	output : 
		f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_binary_acapulco_cropped.nii.gz"

	params :
		script = SCRIPTS("apply_bounding_box.py")

	log : 
		LOG_SNAKEMAKE("bbox_1_acapulco/{subject}.log")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} --bbox_npy {input.bbox_cerebellum} --input {input.mask_acapulco} --output {output} --verbose > {log} 2>&1
	"""

rule apply_cerebellum_bbox_mask_t1w : 
	input : 
		mask_t1w = f"{OUTPUT_FOLDER}/{{subject}}/mni/{{subject}}_t1w_mni.nii.gz",
		bbox_cerebellum = f"{OUTPUT_FOLDER}/common/bbox_cerebellum_atlas.npy"

	output : 
		f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_t1w_cropped.nii.gz"
	
	params : 
		script = SCRIPTS("apply_bounding_box.py")
	
	log : 
		LOG_SNAKEMAKE("bbox_1_t1w/{subject}.log")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} --bbox_npy {input.bbox_cerebellum} --input {input.mask_t1w} --output {output} --verbose > {log} 2>&1
	"""

rule apply_cerebellum_bbox_mask_substructure : 
	input : 
		mask_substructure = f"{OUTPUT_FOLDER}/common/{{substructure}}_dilated_mask.nii.gz",
		bbox_cerebellum = f"{OUTPUT_FOLDER}/common/bbox_cerebellum_atlas.npy"

	output : 
		f"{OUTPUT_FOLDER}/common/{{substructure}}_mask_cropped.nii.gz"
	
	params : 
		script = SCRIPTS("apply_bounding_box.py")

	log : 
		LOG_SNAKEMAKE("bbox_1_substruct/{substructure}.log")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} --bbox_npy {input.bbox_cerebellum} --input {input.mask_substructure} --output {output} --verbose > {log} 2>&1
	"""

rule fusion_acapulco_substructures_mask :
	input :
		mask_substructure = f"{OUTPUT_FOLDER}/common/{{substructure}}_mask_cropped.nii.gz",
		mask_acapulco = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_binary_acapulco_cropped.nii.gz"
	
	output : 
		f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_corrected_{{substructure}}_cropped.nii.gz"

	params : 
		script = SCRIPTS("fusion_mask.py")
	
	log : 
		LOG_SNAKEMAKE("fusion_mask/{subject}_{substructure}.log")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} --mask_1 {input.mask_substructure} --mask_2 {input.mask_acapulco} --output {output} --verbose > {log} 2>&1
	"""

rule compute_multiscale_mean_curvature_persistence :
	input :
		corrected_mask_substructure = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_corrected_{{substructure}}_cropped.nii.gz",
		cropped_T1w = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_t1w_cropped.nii.gz"
	
	output : 
		persistence_mean_curv = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_{{substructure}}_persistence_band.nii.gz",
		thresholded_persistence_mean_curv = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_{{substructure}}_thresh_persistence.nii.gz"
	
	params : 
		sigmas = " ".join(map(str, config["sigmas"])),
		thresh_persis = config["threshold_persistence"],
		min_quantile = config["min_quantile"],
		max_quantile = config["max_quantile"],
		script = SCRIPTS("persistence_mean_curvature.py"),
		tmp_folder = OUTPUT_FOLDER
	
	log : 
		LOG_SNAKEMAKE("multi_scale_curv/{subject}_{substructure}.log")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} \
	--input {input.cropped_T1w} \
	--tmp_folder {params.tmp_folder} \
	--output_persistence {output.persistence_mean_curv} \
	--output_thresholded {output.thresholded_persistence_mean_curv} \
	--cerebellum_mask {input.corrected_mask_substructure} \
	--threshold_persistence {params.thresh_persis} \
	--min_quantile {params.min_quantile} \
	--max_quantile {params.max_quantile} \
	--sigmas {params.sigmas} \
	--verbose > {log} 2>&1
	"""

rule apply_mask_corrected_substructure :
	input : 
		thresholded_persistence_mean_curv = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_{{substructure}}_thresh_persistence.nii.gz",
		corrected_mask_substructure = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_corrected_{{substructure}}_cropped.nii.gz"
	
	output : 
		f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_{{substructure}}_masked_persistence.nii.gz"
	
	params : 
		script = SCRIPTS("apply_mask.py")
	
	log : 
		LOG_SNAKEMAKE("apply_mask_sub/{subject}_{substructure}.log")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} --input {input.thresholded_persistence_mean_curv} --mask {input.corrected_mask_substructure} --output {output} --verbose > {log} 2>&1
	"""

rule compute_bbox_substructure : 
	input : 
		dilated_mask_substructure = f"{OUTPUT_FOLDER}/common/{{substructure}}_mask_cropped.nii.gz"

	output : 
		f"{OUTPUT_FOLDER}/common/{{substructure}}_bbox.npy"
	
	params : 
		script = SCRIPTS("compute_bounding_box.py")
	
	log : 
		LOG_SNAKEMAKE("compute_bbox_substruct/{substructure}.log")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} --input {input.dilated_mask_substructure} --output {output} --dilatation 0 --verbose > {log} 2>&1
	"""

rule apply_bbox_substructure : 
	input : 
		substructure_bbox = f"{OUTPUT_FOLDER}/common/{{substructure}}_bbox.npy",
		masked_persistence = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_{{substructure}}_masked_persistence.nii.gz"
	
	output : 
		cropped_substructure = f"{OUTPUT_FOLDER}/{{subject}}/{{subject}}_{{substructure}}_skeleton_cropped.nii.gz"
	
	params :
		script = SCRIPTS("apply_bounding_box.py")

	log : 
		LOG_SNAKEMAKE("bbox_2/{subject}_{substructure}.log")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} --input {input.masked_persistence} --output {output.cropped_substructure} --bbox_npy {input.substructure_bbox} --verbose > {log} 2>&1
	"""
