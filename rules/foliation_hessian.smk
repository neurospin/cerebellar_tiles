################################################
# Hessian-based foliation extraction
#
# Chain (locked 2026-05-26 — Run 11 Strand A endorsed pipeline) :
#   wm_peak_normalisation
#     -> compute_eigvals (per sigma)
#     -> compute_sheetness (per sigma)
#     -> gamma_normalisation (per sigma)
#     -> aggregation (max + optional argmax across sigma)
#     -> z_score_normalisation (cerebellum mask)
#     -> hysteresis_threshold (cerebellum mask)
#     -> apply_mask_substructure (per substructure)
#     -> apply_bbox_substructure (per substructure -> final deliverable)
#
# Substructure axis enters only at the final two rules. z-score and
# hysteresis run on the full cropped cerebellum mask so the percentile
# base is stable across substructures (matches the FAS7 working point
# `(5 mm / 50-95)` as tuned on the cerebellum).
################################################

wildcard_constraints :
	subject = r"[^/]+",
	substructure = r"[^/]+",
	sigma = r"\d+(?:\.\d+)?"


# -----------------------------------------------
# Subject-level upstream : intensity normalisation
# -----------------------------------------------

rule wm_peak_normalisation :
	input :
		t1w_cropped = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_t1w_cropped.nii.gz",
		cerebellum_mask = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_binary_acapulco_cropped.nii.gz"

	output :
		normalised_t1w = f"{OUTPUT_FOLDER}/{{subject}}/sheetness/{{subject}}_t1w_cropped_wm_norm.nii.gz"

	params :
		script = SCRIPTS("normalisation_intensity.py"),
		target_wm = config["target_wm_value"],
		save_stats = "--save_stats" if config.get("save_normalisation_stats", False) else ""

	log :
		LOG_SNAKEMAKE("wm_peak_normalisation/{subject}.log")

	benchmark:
		BENCHMARK_SNAKEMAKE("wm_peak_normalisation/{subject}.tsv")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} \
		--input {input.t1w_cropped} \
		--mask {input.cerebellum_mask} \
		--output {output.normalised_t1w} \
		--target_wm {params.target_wm} \
		{params.save_stats} \
		--verbose > {log} 2>&1
	"""


# -----------------------------------------------
# Per-sigma : eigenvalues, sheetness, gamma-norm
# -----------------------------------------------

rule compute_eigvals :
	input :
		normalised_t1w = f"{OUTPUT_FOLDER}/{{subject}}/sheetness/{{subject}}_t1w_cropped_wm_norm.nii.gz"

	output :
		eigvals_npy = maybe_temp(f"{OUTPUT_FOLDER}/{{subject}}/sheetness/eigvals/sigma{{sigma}}/{{subject}}_eigvals_sorted_sigma{{sigma}}.npy")

	params :
		script = SCRIPTS("compute_eigvals.py"),
		output_dir = lambda wildcards : f"{OUTPUT_FOLDER}/{wildcards.subject}/sheetness/eigvals/sigma{wildcards.sigma}",
		save_eigvals = "--save_eigvals" if config.get("save_eigvals_nifti", False) else ""

	log :
		LOG_SNAKEMAKE("compute_eigvals/{subject}_sigma{sigma}.log")

	benchmark:
		BENCHMARK_SNAKEMAKE("compute_eigvals/{subject}_sigma{sigma}.tsv")

	shell : """
	mkdir -p {params.output_dir}
	{MORPHO_ENV_PREFIX} python {params.script} \
		--input {input.normalised_t1w} \
		--sigma {wildcards.sigma} \
		--output {params.output_dir} \
		--sort_eigvals \
		{params.save_eigvals} \
		--verbose > {log} 2>&1
	"""


rule compute_sheetness :
	input :
		eigvals_npy = f"{OUTPUT_FOLDER}/{{subject}}/sheetness/eigvals/sigma{{sigma}}/{{subject}}_eigvals_sorted_sigma{{sigma}}.npy",
		header_volume = f"{OUTPUT_FOLDER}/{{subject}}/sheetness/{{subject}}_t1w_cropped_wm_norm.nii.gz"

	output :
		sheetness = maybe_temp(f"{OUTPUT_FOLDER}/{{subject}}/sheetness/raw/sigma{{sigma}}/{{subject}}_sheetness_sigma{{sigma}}_alpha{config['alpha']}_beta{config['beta']}.nii.gz")

	params :
		script = SCRIPTS("compute_sheetness.py"),
		output_dir = lambda wildcards : f"{OUTPUT_FOLDER}/{wildcards.subject}/sheetness/raw/sigma{wildcards.sigma}",
		alpha = config["alpha"],
		beta = config["beta"],
		save_intermediate = "--save_intermediate" if config.get("save_sheetness_intermediates", False) else ""

	log :
		LOG_SNAKEMAKE("compute_sheetness/{subject}_sigma{sigma}.log")

	benchmark:
		BENCHMARK_SNAKEMAKE("compute_sheetness/{subject}_sigma{sigma}.tsv")

	shell : """
	mkdir -p {params.output_dir}
	{MORPHO_ENV_PREFIX} python {params.script} \
		--input {input.eigvals_npy} \
		--header_file {input.header_volume} \
		--output {params.output_dir} \
		--alpha {params.alpha} \
		--beta {params.beta} \
		{params.save_intermediate} \
		--verbose > {log} 2>&1
	"""


rule gamma_normalisation :
	input :
		sheetness = f"{OUTPUT_FOLDER}/{{subject}}/sheetness/raw/sigma{{sigma}}/{{subject}}_sheetness_sigma{{sigma}}_alpha{config['alpha']}_beta{config['beta']}.nii.gz"

	output :
		sheetness_norm = maybe_temp(f"{OUTPUT_FOLDER}/{{subject}}/sheetness/normalised/{{subject}}_sheetness_norm_sigma{{sigma}}.nii.gz")

	params :
		script = SCRIPTS("gamma_normalisation.py"),
		gamma_power = config.get("gamma_power", 1.0)

	log :
		LOG_SNAKEMAKE("gamma_normalisation/{subject}_sigma{sigma}.log")

	benchmark:
		BENCHMARK_SNAKEMAKE("gamma_normalisation/{subject}_sigma{sigma}.tsv")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} \
		--input {input.sheetness} \
		--output {output.sheetness_norm} \
		--gamma_power {params.gamma_power} \
		-vv > {log} 2>&1
	"""


# -----------------------------------------------
# Multiscale aggregation (max + optional argmax)
# -----------------------------------------------

rule aggregation_argmax :
	input :
		per_sigma = lambda wildcards : expand(
			f"{OUTPUT_FOLDER}/{wildcards.subject}/sheetness/normalised/{wildcards.subject}_sheetness_norm_sigma{{sigma}}.nii.gz",
			sigma = SIGMAS
		)

	output :
		max_vol = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_aggregation_max.nii.gz",
		argmax_vol = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_aggregation_argmax.nii.gz"

	params :
		script = SCRIPTS("aggregation_argmax.py")

	log :
		LOG_SNAKEMAKE("aggregation_argmax/{subject}.log")

	benchmark:
		BENCHMARK_SNAKEMAKE("aggregation_argmax/{subject}.tsv")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} \
		--inputs {input.per_sigma} \
		--output_max {output.max_vol} \
		--output_argmax {output.argmax_vol} \
		-vv > {log} 2>&1
	"""


# -----------------------------------------------
# z-score and hysteresis (cerebellum-mask scope)
# -----------------------------------------------

rule z_score_normalisation :
	input :
		max_vol = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_aggregation_max.nii.gz",
		cerebellum_mask = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_binary_acapulco_cropped.nii.gz"

	output :
		z_score = f"{OUTPUT_FOLDER}/{{subject}}/sheetness/{{subject}}_local_z_score_sheetness_filter{config['window_size']}mm.nii.gz"

	params :
		script = SCRIPTS("z-score_normalisation.py"),
		output_dir = f"{OUTPUT_FOLDER}/{{subject}}/sheetness",
		window_size = config["window_size"],
		save_intermediate = "--save_intermediate" if config.get("save_z_score_intermediates", False) else ""

	log :
		LOG_SNAKEMAKE("z_score_normalisation/{subject}.log")

	benchmark:
		BENCHMARK_SNAKEMAKE("z_score_normalisation/{subject}.tsv")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} \
		--input {input.max_vol} \
		--mask {input.cerebellum_mask} \
		--output {params.output_dir} \
		--window_size {params.window_size} \
		{params.save_intermediate} \
		-vv > {log} 2>&1
	"""


rule hysteresis_threshold :
	input :
		z_score = f"{OUTPUT_FOLDER}/{{subject}}/sheetness/{{subject}}_local_z_score_sheetness_filter{config['window_size']}mm.nii.gz",
		cerebellum_mask = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_binary_acapulco_cropped.nii.gz"

	output :
		binary = f"{OUTPUT_FOLDER}/{{subject}}/sheetness/{{subject}}_foliation_binary.nii.gz"

	params :
		script = SCRIPTS("hysteresis_threshold_on_subject.py"),
		p_low = config["min_percentile"],
		p_high = config["max_percentile"]

	log :
		LOG_SNAKEMAKE("hysteresis_threshold/{subject}.log")

	benchmark:
		BENCHMARK_SNAKEMAKE("hysteresis_threshold/{subject}.tsv")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} \
		--input {input.z_score} \
		--mask {input.cerebellum_mask} \
		--output {output.binary} \
		--p_low {params.p_low} \
		--p_high {params.p_high} \
		-vv > {log} 2>&1
	"""


# -----------------------------------------------
# Substructure split : mask + bbox to deliverable
# -----------------------------------------------

rule apply_mask_substructure :
	input :
		binary = f"{OUTPUT_FOLDER}/{{subject}}/sheetness/{{subject}}_foliation_binary.nii.gz",
		corrected_mask_substructure = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_corrected_{{substructure}}_cropped.nii.gz"

	output :
		f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_{{substructure}}_foliation_binary_masked.nii.gz"

	params :
		script = SCRIPTS("apply_mask.py")

	log :
		LOG_SNAKEMAKE("apply_mask_substructure/{subject}_{substructure}.log")

	benchmark:
		BENCHMARK_SNAKEMAKE("apply_mask_substructure/{subject}_{substructure}.tsv")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} \
		--input {input.binary} \
		--mask {input.corrected_mask_substructure} \
		--output {output} \
		--verbose > {log} 2>&1
	"""


rule apply_bbox_substructure :
	input :
		substructure_bbox = f"{OUTPUT_FOLDER}/common/{{substructure}}_bbox.npy",
		masked_binary = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_{{substructure}}_foliation_binary_masked.nii.gz"

	output :
		cropped = f"{OUTPUT_FOLDER}/{{subject}}/{{subject}}_{{substructure}}_foliation_binary_cropped.nii.gz"

	params :
		script = SCRIPTS("apply_bounding_box.py")

	log :
		LOG_SNAKEMAKE("apply_bbox_substructure/{subject}_{substructure}.log")

	benchmark:
		BENCHMARK_SNAKEMAKE("apply_bbox_substructure/{subject}_{substructure}.tsv")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} \
		--input {input.masked_binary} \
		--output {output.cropped} \
		--bbox_npy {input.substructure_bbox} \
		--verbose > {log} 2>&1
	"""
