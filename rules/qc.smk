################################################
# Tier-1 validity QC + dataset manifest
#
#   freeze_config  -> snapshot the full config to the dataset dir (provenance)
#   qc_subject     -> per-subject validity checks -> {subject}_qc.json
#   gather_manifest-> aggregate QC + config -> manifest.json (dataset card) + qc.csv
#
# QC flags, it does NOT gate: a bad subject still builds, but gather marks it flagged and
# lists it in the manifest so it can be excluded from the DL dataset downstream.
################################################

# Run in the snakemake process rather than as cluster jobs. freeze_config is a `run:`
# directive (trivial, and `run:` needs snakemake inside the job); gather_manifest is a
# single cross-subject aggregation. Neither is worth a flux submission + status poll,
# and keeping gather_manifest off the cluster also keeps it out of any rule group.
localrules : freeze_config, gather_manifest


rule freeze_config :
	output :
		f"{OUTPUT_FOLDER}/config_snapshot.json"
	run :
		with open(output[0], "w") as f :
			json.dump(dict(config), f, indent=2)


rule qc_subject :
	group : "subject_post"
	input :
		raw = lambda wildcards : RAW_DATA(wildcards.subject),
		cerebellum_mask = f"{OUTPUT_FOLDER}/{{subject}}/bbox_cerebellum/{{subject}}_binary_acapulco_cropped.nii.gz",
		binary = f"{OUTPUT_FOLDER}/{{subject}}/sheetness/{{subject}}_foliation_binary.nii.gz",
		zscore = f"{OUTPUT_FOLDER}/{{subject}}/sheetness/{{subject}}_local_z_score_sheetness_filter{config['window_size']}mm.nii.gz",
		npz = f"{OUTPUT_FOLDER}/{{subject}}/{{subject}}_tiles.npz"

	output :
		qc = f"{OUTPUT_FOLDER}/{{subject}}/qc/{{subject}}_qc.json"

	params :
		script = SCRIPTS("qc_subject.py")

	log :
		LOG_SNAKEMAKE("qc_subject/{subject}.log")

	benchmark:
		BENCHMARK_SNAKEMAKE("qc_subject/{subject}.tsv")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} \
		--subject {wildcards.subject} \
		--raw {input.raw} \
		--cerebellum-mask {input.cerebellum_mask} \
		--binary {input.binary} \
		--zscore {input.zscore} \
		--npz {input.npz} \
		--output {output.qc} > {log} 2>&1
	"""


rule gather_manifest :
	input :
		qc_json = expand(f"{OUTPUT_FOLDER}/{{subject}}/qc/{{subject}}_qc.json", subject = SUBJECTS),
		config_snapshot = f"{OUTPUT_FOLDER}/config_snapshot.json"

	output :
		manifest = f"{OUTPUT_FOLDER}/manifest.json",
		qc_csv = f"{OUTPUT_FOLDER}/qc.csv"

	params :
		script = SCRIPTS("gather_manifest.py"),
		dataset_name = config.get("dataset", {}).get("name", "unknown"),
		dataset_version = config.get("dataset", {}).get("version", "0.0.0"),
		pipeline_dir = workflow.basedir

	log :
		LOG_SNAKEMAKE("gather_manifest.log")

	shell : """
	{MORPHO_ENV_PREFIX} python {params.script} \
		--qc-json {input.qc_json} \
		--config-json {input.config_snapshot} \
		--dataset-name {params.dataset_name} \
		--dataset-version {params.dataset_version} \
		--pipeline-dir {params.pipeline_dir} \
		--out-manifest {output.manifest} \
		--out-csv {output.qc_csv} > {log} 2>&1
	"""
