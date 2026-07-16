################################################
# Mask preparation rules
#
# - copy Acapulco transforms and segmentations
# - resample T1w and Acapulco mask to MNI 0.5 mm iso
# - binarise the Acapulco mask
# - dilate per-substructure masks
# - compute / apply cerebellum bounding box (crops everything to a small volume)
# - fusion of substructure mask with the per-subject Acapulco mask
# - per-substructure bounding box (used at the very end to crop the foliation binary)
################################################

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

	params :
		subject_name = lambda wildcards : SUBJECT_NIFTI_NAME(wildcards.subject)

	log :
		LOG_SNAKEMAKE("copy_masks/{subject}.log")

	benchmark:
		BENCHMARK_SNAKEMAKE("copy_masks/{subject}.tsv")

	shell : """
	cp {input.acapulco_temp}/mni/{params.subject_name}_n4_affine.txt {output.masks[0]}
	cp {input.acapulco_temp}/mni/{params.subject_name}_n4_inv-affine.txt {output.masks[1]}
	cp {input.acapulco_temp}/parc/{params.subject_name}_n4_mni_seg_post.nii.gz {output.masks[2]}
	cp {input.acapulco_temp}/{params.subject_name}_n4_mni_seg_post_inverse.nii.gz {output.masks[3]}
	"""


rule resampling_mni_registration_t1w :
	input :
		raw_nifti = lambda wildcards : RAW_DATA(wildcards.subject),
		transf_matrix_acapulco = f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_n4_affine.txt"

	output :
		resampled_t1w_mni = maybe_temp(f"{OUTPUT_FOLDER}/{{subject}}/mni/{{subject}}_t1w_mni.nii.gz")

	params :
		script = SCRIPTS("resampling.py")

	log :
		LOG_SNAKEMAKE("resampling_t1w/{subject}.log")

	benchmark:
		BENCHMARK_SNAKEMAKE("resampling_t1w/{subject}.tsv")

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

	benchmark:
		BENCHMARK_SNAKEMAKE("resampling_acapulco/{subject}.tsv")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} --acapulco --mask --input {input.mask_native} --output {output.resampled_mask_mni} --transform_mat {input.transf_matrix_acapulco} --verbose > {log} 2>&1
	"""


rule binarisation_acapulco_mask :
	input :
		mask_acapulco = f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_seg_acapulco_mni.nii.gz"

	output :
		binary_mask_acapulco = f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_binary_acapulco_mni.nii.gz"

	params :
		script = SCRIPTS("binarisation_mask.py")

	log :
		LOG_SNAKEMAKE("binarisation_acapulco/{subject}.log")

	benchmark:
		BENCHMARK_SNAKEMAKE("binarisation_acapulco/{subject}.tsv")

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

	benchmark:
		BENCHMARK_SNAKEMAKE("dilatation_mask_sub/{substructure}.tsv")

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

	benchmark:
		BENCHMARK_SNAKEMAKE("cerebellum_bbox.tsv")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} --input {input.mask_cerebellum} --output {output} --dilatation {params.dilatation_cerebellum_mask} --verbose > {log} 2>&1
	"""


rule apply_cerebellum_bbox_bin_mask_acapulco :
	input :
		mask_acapulco = f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_binary_acapulco_mni.nii.gz",
		bbox_cerebellum = f"{OUTPUT_FOLDER}/common/bbox_cerebellum_atlas.npy"

	output :
		f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_binary_acapulco_cropped.nii.gz"

	params :
		script = SCRIPTS("apply_bounding_box.py")

	log :
		LOG_SNAKEMAKE("bbox_1_bin_acapulco/{subject}.log")

	benchmark:
		BENCHMARK_SNAKEMAKE("bbox_1_bin_acapulco/{subject}.tsv")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} --bbox_npy {input.bbox_cerebellum} --input {input.mask_acapulco} --output {output} --verbose > {log} 2>&1
	"""


rule apply_cerebellum_bbox_mask_acapulco :
	input :
		mask_acapulco = f"{OUTPUT_FOLDER}/{{subject}}/masks/{{subject}}_seg_acapulco_mni.nii.gz",
		bbox_cerebellum = f"{OUTPUT_FOLDER}/common/bbox_cerebellum_atlas.npy"

	output :
		f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_seg_acapulco_cropped.nii.gz"

	params :
		script = SCRIPTS("apply_bounding_box.py")

	log :
		LOG_SNAKEMAKE("bbox_1_seg_acapulco/{subject}.log")

	benchmark:
		BENCHMARK_SNAKEMAKE("bbox_1_seg_acapulco/{subject}.tsv")

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

	benchmark:
		BENCHMARK_SNAKEMAKE("bbox_1_t1w/{subject}.tsv")

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

	benchmark:
		BENCHMARK_SNAKEMAKE("bbox_1_substruct/{substructure}.tsv")

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

	benchmark:
		BENCHMARK_SNAKEMAKE("fusion_mask/{subject}_{substructure}.tsv")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} --mask_1 {input.mask_substructure} --mask_2 {input.mask_acapulco} --output {output} --verbose > {log} 2>&1
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

	benchmark:
		BENCHMARK_SNAKEMAKE("compute_bbox_substruct/{substructure}.tsv")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} --input {input.dilated_mask_substructure} --output {output} --dilatation 0 --verbose > {log} 2>&1
	"""
