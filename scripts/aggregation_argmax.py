from soma import aims
from pathlib import Path
import numpy as np
import logging
import argparse
import re
import os

# Parse arguments

parser = argparse.ArgumentParser()

parser.add_argument("-v", "--verbose", action="count", default=0, help="Verbose mode : -v for INFO. -vv for DEBUG")
parser.add_argument("-i", "--input", required=True, help="Input folder containing normalised sheetness files")
parser.add_argument("-o", "--output", required=True, help="Output folder")

args=parser.parse_args()

# Logger set

level = logging.WARNING - 10 * args.verbose
logging.basicConfig(level=level, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

## Parsing folder

REGEX_PATTERN = re.compile(
    r"^(?P<subject>.+?)"
    r"_sheetness_norm"
    r"_sigma(?P<sigma>\d+(?:\.\d+)?)"
    r"\.nii\.gz$"
)

input_path = Path(args.input)
output_path = Path(args.output)

logger.debug("Input folder : %s", input_path)
logger.debug("Output folder : %s", output_path)

# Parsing folder

logger.info("\n ____ Parsing folder _____")

subject_set = set() # Ensure that we are working with only one subject
list_path = list()
list_sigmas = list()
logger.debug("Files in input path %s", os.listdir(input_path))
for file_name in os.listdir(input_path): 
    if os.path.isdir(file_name):
        continue
    match = REGEX_PATTERN.match(file_name)
    if match : 
        groupdict=match.groupdict()
        subject_set.add(groupdict["subject"])
        if len(subject_set) > 1 :
            raise ValueError(f"Multiple subjects in the folder ! Got : {subject_set}")
        file_path = input_path / file_name
        list_path.append(file_path)
        list_sigmas.append(float(groupdict["sigma"]))

sorted_ind = np.argsort(list_sigmas)
array_sigmas = np.array(list_sigmas)[sorted_ind]
array_path = np.array(list_path)[sorted_ind]

logger.info("Found %d normalisation in the folder", len(array_path))
logger.debug("List of paths : %s", array_path)

# Aggregation of the files

logger.info("\n ____ Aggregation files ____ \n")

np_list = list()

logger.info("Reading files...")
for ind,path in enumerate(array_path): 
    sigma = array_sigmas[ind]
    logger.debug("Reading file %s, sigma parsed : %d:2f", path, sigma)
    volume = aims.read(str(path))
    if ind==0 :
        header_template = volume.header()
    vol_np = volume.np.copy()
    np_list.append(vol_np)

logger.info("Aggregating...")

stacked = np.stack(np_list)
argmax_vol = np.argmax(stacked, axis=0)
max_vol = np.max(stacked, axis=0)
repartition_maxs = list(np.unique(argmax_vol))

logger.debug("Aggregated volume shape : %s", argmax_vol.shape)
logger.debug("Unique values : %s", repartition_maxs)

logger.info("Aggregated ! Saving files... ")

header_template["sigmas_aggregation"] = array_sigmas

max_agg_aims = aims.Volume(max_vol.astype(np.float32))
argmax_agg_aims = aims.Volume(argmax_vol.astype(np.float32))

logger.debug("Header used for output file : \n %s", header_template)

max_agg_aims.copyHeaderFrom(header_template)
argmax_agg_aims.copyHeaderFrom(header_template)

subject = subject_set.pop()

output_max_path = output_path / f"{subject}_aggregation_max.nii.gz"
output_argmax_path = output_path / f"{subject}_aggregation_argmax.nii.gz"

logger.debug("Max vol saved at : %s", output_max_path)
logger.debug("Argmax vol saved at : %s", output_argmax_path)

aims.write(max_agg_aims, str(output_max_path))
aims.write(argmax_agg_aims, str(output_argmax_path))

logger.info("Aggregated volume saved !")
