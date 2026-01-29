from soma import aims
from soma.aimsalgo import MorphoGreyLevel_S16
import numpy as np
import argparse

_AIMS_BINARY_ONE = 32767

def dilate(mask, radius):
    """
    """
    arr = np.asarray(mask)
    # Binarization of mask
    arr[arr < 1] = 0
    arr[arr >= 1] = _AIMS_BINARY_ONE
    # Dilates initial volume of 10 mm
    morpho = MorphoGreyLevel_S16()
    dilate = morpho.doDilation(mask, radius)
    arr_dilate = np.asarray(dilate)
    arr_dilate[arr_dilate >= 1] = 1
    return dilate

parser = argparse.ArgumentParser()
parser.add_argument("-v", "--verbose", action="store_true", help="Verbose mode")
parser.add_argument("-i", "--input", required=True, help="Input nifti file of the mask")
parser.add_argument("--dilatation", required=True, help="Dilatation (in voxels)")
parser.add_argument("-o", "--output", required=True, help="Subvolume file")
args = parser.parse_args()


vol_aims = aims.read(args.input)
dilated = dilate(vol_aims, radius = int(args.dilatation))

if args.verbose :
    print(f"Dilated volume (of {args.dilatation}) of {args.input} saved at : {args.output}")

aims.write(dilated, args.output) 
