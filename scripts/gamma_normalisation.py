from soma import aims
import numpy as np
import logging
import argparse
import os
from pathlib import Path
import re

# Parsing args

parser = argparse.ArgumentParser()

parser.add_argument("-v", "--verbose", action="count", default=0, help="Verbose mode : -v for INFO and -vv for DEBUG")
parser.add_argument("-i", "--input", required=True, help="Input folder containing the sheetness values")
parser.add_argument("-o", "--output", required=True, help="Output folder for gamma normalised sheetness values")

args = parser.parse_args()

## Logging parameters 

level = logging.WARNING - 10 * args.verbose
logging.basicConfig(level=level, format="%(levelname)s:%(message)s")
logger = logging.getLogger(__name__)

#Retrieving files for gamma normalisation

REGEX_SHEET = re.compile(
    r"^(?P<subject>.+?)"
    r"_sheetness"
    r"_sigma(?P<sigma>\d+(?:\.\d+)?)"
    r"_alpha(?P<alpha>\d+)"
    r"_beta(?P<beta>\d+)"
    r"\.nii\.gz$"
)

input_folder = Path(args.input)
output_folder = Path(args.output)

logger.debug("Input folder : %s", input_folder)
logger.debug("Output folder : %s", output_folder)

# Parsing folder

logger.info("\n _____ Parsing sheetness files _____ \n")
params_list = list()
subjects = set()
for file_name in os.listdir(input_folder):
    if os.path.isdir(file_name):
        continue
    match = REGEX_SHEET.match(file_name)
    if match : 
        dict_sub = match.groupdict().copy()
        sub_name = dict_sub["subject"]
        subjects.add(sub_name)
        dict_sub["path_file"] = input_folder / file_name
        # fixing types
        dict_sub["sigma"] = float(dict_sub["sigma"])
        dict_sub["alpha"] = int(dict_sub["alpha"])
        dict_sub["beta"] = int(dict_sub["beta"])
        params_list.append(dict_sub)
    else :
        continue

logger.info("Found %d files", len(params_list))
logger.debug("Parsed information : \n %s", params_list)
if len(subjects) > 1 :
    logger.warning("Multiple subjects in the input folder %s", subjects)

logger.info("\n _____ Sigma Normalisation of values _____ \n")

for dict_sub in params_list :
    sub = dict_sub["subject"]
    sigma = dict_sub["sigma"]
    logger.info("\nNormalisation of %s for sigma : %d", sub, sigma)
    path_file = str(dict_sub["path_file"])
    logger.debug("Parameters \n Path : %s \n Sigma: %f \n Alpha : %d \n  Beta : %d",
                 path_file,
                 sigma,
                 dict_sub["alpha"],
                 dict_sub["beta"])

    volume = aims.read(path_file)
    header_input = volume.header()
    vol_np = np.squeeze(volume.np.copy())
    logger.debug("File read, shape : %s", vol_np.shape)
    vol_np_normalised = sigma* vol_np
    logger.debug("Subject : %s normalised for sigma %s", sub, sigma)
    norm_aims = aims.Volume(vol_np_normalised)
    logger.debug("Header file to copy: %s", header_input )
    norm_aims.copyHeaderFrom(header_input)
    output_file = output_folder / f"{sub}_sheetness_norm_sigma{sigma}.nii.gz"
    logger.debug("Saving file at : %s", output_file)
    aims.write(norm_aims, str(output_file))

logger.info("Finished folder normalisation !")
