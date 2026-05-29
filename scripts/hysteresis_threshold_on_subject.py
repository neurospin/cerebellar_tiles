from soma import aims
from pathlib import Path
import numpy as np
from skimage.filters import apply_hysteresis_threshold
import logging
import argparse

def set_border_zero(vol_np):
    vol_np[0,:,:] = 0
    vol_np[-1,:,:] = 0

    vol_np[:,0,:] = 0
    vol_np[:,-1,:] = 0

    vol_np[:,:,0] = 0
    vol_np[:,:,-1] = 0

parser = argparse.ArgumentParser()

parser.add_argument("-v", "--verbose", action="count", default=0, help="Verbose mode. -v for INFO. -vv for DEBUG")
parser.add_argument("-i", "--input", required=True, help="Input file (aggregated normalised sheetness)")
parser.add_argument("-o", "--output", required=True, help="Binary volume obtained through hysteresis thresholding")
parser.add_argument("-m", "--mask", required=True, help="Mask of the cerebellum used for thresholding")
parser.add_argument("-pl", "--p_low", required=True, help="Lower percentile for hysteresis computation")
parser.add_argument("-ph", "--p_high", required=True, help="Higher percentile for hysteresis computation")

args= parser.parse_args()

level = logging.WARNING - 10 * args.verbose
logging.basicConfig(level=level, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

input_path = Path(args.input)
subject_name = input_path.name.split("_")[0]

output_path = Path(args.output)

logger.info("\n _____ Hysteresis thresholding _____ \n")
logger.info("Metadata : \n Input path : %s \n Subject name : %s \n Mask path : %s", input_path, subject_name, args.mask)

volume = aims.read(str(input_path))
header_vol = volume.header()
vol_np = np.squeeze(volume.np.copy())

mask = aims.read(args.mask)
mask_np = np.squeeze(mask.np.copy())

logger.debug("Mask shape : %s", mask_np.shape)

min_vol = vol_np[mask_np.astype(bool)].min()

logger.debug("Shifting values by %d to make them positive", abs(min_vol))

vol_np += abs(min_vol)

in_mask_val = vol_np[mask_np.astype(bool)]
t_low = np.percentile(in_mask_val, float(args.p_low))
t_high = np.percentile(in_mask_val, float(args.p_high))

logger.info("Percentile computed in the mask : \n - High (P %s) : %s \n - Low (P %s) : %s \n", args.p_high, t_high, args.p_low, t_low)

masked_vol_np = np.where(mask_np, vol_np, 0.0)

logger.debug("Masked volume shape %s", masked_vol_np.shape)

thresh_hyst = apply_hysteresis_threshold(masked_vol_np, t_low, t_high)
set_border_zero(thresh_hyst)

header_vol["hyst_param"] = [t_low, t_high]

thresh_hyst_aims = aims.Volume(thresh_hyst.astype(np.int16))
thresh_hyst_aims.copyHeaderFrom(header_vol)

logger.debug("Header for saving : \n %s", header_vol)
logger.debug("Saving threshold at : %s", args.output)

aims.write(thresh_hyst_aims, args.output)
logger.info("Tresholding finished !")
