from soma import aims
import numpy as np
import logging
import argparse
from pathlib import Path
import re

# Per-sigma file I/O for Snakemake compatibility.
# Old script parsed a whole folder; this version takes one input file and writes one output file.
# Sigma is parsed from the input filename (matches compute_sheetness.py naming).

REGEX_SHEET = re.compile(
    r"^(?P<subject>.+?)"
    r"_sheetness"
    r"_sigma(?P<sigma>\d+(?:\.\d+)?)"
    r"_alpha(?P<alpha>\d+)"
    r"_beta(?P<beta>\d+)"
    r"\.nii\.gz$"
)

# Parsing args
parser = argparse.ArgumentParser(
    description="Gamma-normalise a per-sigma sheetness volume by sigma**gamma_power."
)
parser.add_argument("-v", "--verbose", action="count", default=0,
                    help="Verbose mode : -v for INFO, -vv for DEBUG")
parser.add_argument("-i", "--input", required=True,
                    help="Input per-sigma sheetness nifti "
                         "(naming: <subject>_sheetness_sigma<sigma>_alpha<a>_beta<b>.nii.gz)")
parser.add_argument("-o", "--output", required=True,
                    help="Output per-sigma gamma-normalised sheetness nifti")
parser.add_argument("--gamma_power", type=float, default=1.0,
                    help="Exponent applied to sigma. Multiplier = sigma**gamma_power. "
                         "Default 1.0 reproduces the original `sigma * volume` behaviour.")

args = parser.parse_args()

# Logging setup
level = logging.WARNING - 10 * args.verbose
logging.basicConfig(level=level, format="%(levelname)s:%(message)s")
logger = logging.getLogger(__name__)

input_path = Path(args.input)
output_path = Path(args.output)

logger.debug("Input  : %s", input_path)
logger.debug("Output : %s", output_path)

# Parse sigma from filename
match = REGEX_SHEET.match(input_path.name)
if not match:
    raise ValueError(
        f"Input filename '{input_path.name}' does not match expected pattern "
        f"<subject>_sheetness_sigma<sigma>_alpha<a>_beta<b>.nii.gz"
    )

groupdict = match.groupdict()
subject = groupdict["subject"]
sigma = float(groupdict["sigma"])

logger.info(" _____ Sigma Normalisation _____ ")
logger.info("Subject     : %s", subject)
logger.info("Sigma       : %s", sigma)
logger.info("Gamma power : %s", args.gamma_power)

# Read, scale, write
volume = aims.read(str(input_path))
header_input = volume.header()
vol_np = np.squeeze(volume.np.copy())

multiplier = sigma ** args.gamma_power
logger.debug("Multiplicative factor (sigma**gamma_power) : %s", multiplier)

vol_np_normalised = (multiplier * vol_np).astype(np.float32)

logger.debug("Output shape : %s", vol_np_normalised.shape)

norm_aims = aims.Volume(vol_np_normalised)
norm_aims.copyHeaderFrom(header_input)
norm_aims.header()["sigma_gamma_normalisation"] = sigma
norm_aims.header()["gamma_power"] = args.gamma_power

aims.write(norm_aims, str(output_path))

logger.info("Saved gamma-normalised volume to %s", output_path)
