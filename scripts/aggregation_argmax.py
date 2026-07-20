from soma import aims
from pathlib import Path
import numpy as np
import logging
import argparse
import re

# Refactored 2026-05-29 — explicit file-list I/O for Snakemake compatibility.
# Old script parsed a folder via regex. This version takes an explicit list of per-sigma
# files (--inputs), and writes the max and argmax aggregated volumes to explicit paths.
# Sigmas are parsed from filenames and the input list is sorted by sigma before stacking,
# so the argmax indices line up with config["sigmas"] sorted ascending.

REGEX_PATTERN = re.compile(
    r"^(?P<subject>.+?)"
    r"_sheetness_norm"
    r"_sigma(?P<sigma>\d+(?:\.\d+)?)"
    r"\.nii\.gz$"
)


def parse_inputs(input_paths):
    """Return list of (sigma, subject, Path) tuples sorted by ascending sigma. Errors on subject mismatch."""
    parsed = []
    subjects = set()
    for path in input_paths:
        path = Path(path)
        match = REGEX_PATTERN.match(path.name)
        if not match:
            raise ValueError(
                f"Input filename '{path.name}' does not match expected pattern "
                f"<subject>_sheetness_norm_sigma<sigma>.nii.gz"
            )
        groupdict = match.groupdict()
        subjects.add(groupdict["subject"])
        if len(subjects) > 1:
            raise ValueError(f"Mixed subjects in input list : {subjects}")
        parsed.append((float(groupdict["sigma"]), groupdict["subject"], path))
    return sorted(parsed, key=lambda t: t[0])


# Parse arguments
parser = argparse.ArgumentParser(
    description="Stack per-sigma normalised sheetness volumes and emit max + argmax."
)
parser.add_argument("-v", "--verbose", action="count", default=0,
                    help="Verbose mode : -v for INFO, -vv for DEBUG")
parser.add_argument("--inputs", required=True, nargs="+",
                    help="Per-sigma gamma-normalised sheetness files "
                         "(naming: <subject>_sheetness_norm_sigma<sigma>.nii.gz)")
parser.add_argument("--output_max", required=True,
                    help="Output path for the voxel-wise max aggregation across sigmas")
parser.add_argument("--output_argmax", required=True,
                    help="Output path for the voxel-wise argmax aggregation across sigmas "
                         "(indices align with input sigmas sorted ascending)")

args = parser.parse_args()

level = logging.WARNING - 10 * args.verbose
logging.basicConfig(level=level, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

# Parse and sort by sigma
parsed = parse_inputs(args.inputs)
sigmas_sorted = [t[0] for t in parsed]
subject = parsed[0][1]
paths_sorted = [t[2] for t in parsed]

logger.info(" ____ Aggregation ____ ")
logger.info("Subject : %s", subject)
logger.info("Sigmas  : %s", sigmas_sorted)
logger.info("Number of files : %d", len(paths_sorted))

# Read and stack
logger.info("Reading files...")
np_list = []
header_template = None
for ind, path in enumerate(paths_sorted):
    logger.debug("Reading file %s (sigma=%s)", path, sigmas_sorted[ind])
    volume = aims.read(str(path))
    if ind == 0:
        header_template = volume.header()
    vol_np = volume.np.copy()
    np_list.append(vol_np)

logger.info("Stacking and aggregating...")

stacked = np.stack(np_list)
argmax_vol = np.argmax(stacked, axis=0)
max_vol = np.max(stacked, axis=0)

logger.debug("Aggregated volume shape : %s", argmax_vol.shape)
logger.debug("Unique argmax values   : %s", list(np.unique(argmax_vol)))

# Save
header_template["sigmas_aggregation"] = sigmas_sorted

max_agg_aims = aims.Volume(max_vol.astype(np.float32))
argmax_agg_aims = aims.Volume(argmax_vol.astype(np.float32))

max_agg_aims.copyHeaderFrom(header_template)
argmax_agg_aims.copyHeaderFrom(header_template)

output_max_path = Path(args.output_max)
output_argmax_path = Path(args.output_argmax)

logger.debug("Max vol    -> %s", output_max_path)
logger.debug("Argmax vol -> %s", output_argmax_path)

aims.write(max_agg_aims, str(output_max_path))
aims.write(argmax_agg_aims, str(output_argmax_path))

logger.info("Aggregated volumes saved !")
