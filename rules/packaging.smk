################################################
# DL packaging
#
# 1. Pre-baked substructure z-score tiles: mirror the binary's mask+bbox path so a
#    configured substructure (e.g. vermis) has a ready sheetness tile matching its binary tile.
#    (The binary already has apply_mask_substructure + apply_bbox_substructure in
#    foliation_hessian.smk; these two rules add the same for the z-score field.)
# 2. package_npz: bundle whole-cerebellum zscore + binary + Acapulco label map (+ any
#    pre-baked substructure tiles) into one .npz per subject for the dataloader.
#
# PREBAKED_TILES = config.get("prebaked_tiles", []) — subset of SUBSTRUCTURES to pre-bake.
# On-the-fly extraction of ANY substructure is always possible from the bundled `labels`.
################################################

PREBAKED_TILES = config.get("prebaked_tiles", [])


# -----------------------------------------------
# Pre-baked substructure z-score tiles (parallel to the binary path)
# -----------------------------------------------

rule apply_mask_substructure_zscore :
	group : "subject_post"
	input :
		z_score = f"{OUTPUT_FOLDER}/{{subject}}/sheetness/{{subject}}_local_z_score_sheetness_filter{config['window_size']}mm.nii.gz",
		corrected_mask_substructure = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_corrected_{{substructure}}_cropped.nii.gz"

	output :
		maybe_temp(f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_{{substructure}}_zscore_masked.nii.gz")

	params :
		script = SCRIPTS("apply_mask.py")

	log :
		LOG_SNAKEMAKE("apply_mask_substructure_zscore/{subject}_{substructure}.log")

	benchmark:
		BENCHMARK_SNAKEMAKE("apply_mask_substructure_zscore/{subject}_{substructure}.tsv")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} \
		--input {input.z_score} \
		--mask {input.corrected_mask_substructure} \
		--output {output} \
		--verbose > {log} 2>&1
	"""


rule apply_bbox_substructure_zscore :
	group : "subject_post"
	input :
		substructure_bbox = f"{OUTPUT_FOLDER}/common/{{substructure}}_bbox.npy",
		masked_zscore = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_{{substructure}}_zscore_masked.nii.gz"

	output :
		cropped = f"{OUTPUT_FOLDER}/{{subject}}/{{subject}}_{{substructure}}_zscore_cropped.nii.gz"

	params :
		script = SCRIPTS("apply_bounding_box.py")

	log :
		LOG_SNAKEMAKE("apply_bbox_substructure_zscore/{subject}_{substructure}.log")

	benchmark:
		BENCHMARK_SNAKEMAKE("apply_bbox_substructure_zscore/{subject}_{substructure}.tsv")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} \
		--input {input.masked_zscore} \
		--output {output.cropped} \
		--bbox_npy {input.substructure_bbox} \
		--verbose > {log} 2>&1
	"""


# -----------------------------------------------
# Bundle into one .npz per subject
# -----------------------------------------------

rule package_npz :
	group : "subject_post"
	input :
		zscore = f"{OUTPUT_FOLDER}/{{subject}}/sheetness/{{subject}}_local_z_score_sheetness_filter{config['window_size']}mm.nii.gz",
		binary = f"{OUTPUT_FOLDER}/{{subject}}/sheetness/{{subject}}_foliation_binary.nii.gz",
		labels = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_seg_acapulco_cropped.nii.gz",
		prebaked_zscore = expand(
			f"{OUTPUT_FOLDER}/{{{{subject}}}}/{{{{subject}}}}_{{substructure}}_zscore_cropped.nii.gz",
			substructure = PREBAKED_TILES),
		prebaked_binary = expand(
			f"{OUTPUT_FOLDER}/{{{{subject}}}}/{{{{subject}}}}_{{substructure}}_foliation_binary_cropped.nii.gz",
			substructure = PREBAKED_TILES)

	output :
		npz = f"{OUTPUT_FOLDER}/{{subject}}/{{subject}}_tiles.npz"

	params :
		script = SCRIPTS("to_numpy.py"),
		dataset = config.get("dataset_name", "unknown"),
		prebaked_names = " ".join(f"--prebaked-name {s}" for s in PREBAKED_TILES),
		prebaked_z = lambda wildcards, input : " ".join(f"--prebaked-zscore {p}" for p in input.prebaked_zscore),
		prebaked_b = lambda wildcards, input : " ".join(f"--prebaked-binary {p}" for p in input.prebaked_binary),
		meta_json = lambda wildcards : json.dumps({
			"pipeline_version": config.get("dataset", {}).get("version", "0.0.0"),
			"working_point": {
				"sigmas": SIGMAS, "alpha": config["alpha"], "beta": config["beta"],
				"gamma_power": config.get("gamma_power", 1.0),
				"window_mm": config["window_size"],
				"p_low": config["min_percentile"], "p_high": config["max_percentile"],
			},
		})

	log :
		LOG_SNAKEMAKE("package_npz/{subject}.log")

	benchmark:
		BENCHMARK_SNAKEMAKE("package_npz/{subject}.tsv")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} \
		--zscore {input.zscore} \
		--binary {input.binary} \
		--labels {input.labels} \
		--subject {wildcards.subject} \
		--dataset {params.dataset} \
		--meta-json '{params.meta_json}' \
		{params.prebaked_names} {params.prebaked_z} {params.prebaked_b} \
		--output {output.npz} \
		--verbose > {log} 2>&1
	"""
