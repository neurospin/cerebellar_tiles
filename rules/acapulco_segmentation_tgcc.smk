rule acapulco_segmentation :
	input :
		raw_nifti = lambda wildcards : RAW_DATA(wildcards.subject)

	output :
		output_directory = temp(directory(f"{OUTPUT_FOLDER}/{{subject}}/acapulco")),

	params :
		method = config["segmentation_params"]["method"],
		data_folder = config["raw_data"],
		output_folder = OUTPUT_FOLDER
	
	log : 
		LOG_SNAKEMAKE("acapulco_segmentation/{subject}.log")

	benchmark:
		BENCHMARK_SNAKEMAKE("acapulco_segmentation/{subject}.tsv")

	shell : """
	mkdir -p {output.output_directory}
	pcocc-rs run n4h00001rs:acapulco-cpu-0.3.0 --mount src={params.data_folder},dst={params.data_folder} --mount src={params.output_folder},dst={params.output_folder} -- -i {input.raw_nifti} -o {output.output_directory} -m {params.method} > {log} 2>&1
	"""
