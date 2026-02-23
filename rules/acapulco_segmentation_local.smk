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

	benchmark:
		BENCHMARK_SNAKEMAKE("acapulco_segmentation/{subject}.tsv")

	shell : """
	mkdir -p {output.output_directory}
	acapulco.sh -i {input.raw_nifti} -o {output.output_directory} -m {params.method} > {log} 2>&1
	"""
