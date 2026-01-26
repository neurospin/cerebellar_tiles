from soma import aims
import numpy as np
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("-v", "--verbose", action="store_true", help="Verbose mode")
parser.add_argument("-i", "--input", required=True, help="Input nifti file")
parser.add_argument("-o", "--output", required=True, help="Subvolume file")
args = parser.parse_args()

vol_aims = aims.read(args.input)
vol_np = vol_aims.np.copy()

vol_aims.np[:] = np.where(vol_np != 0, 1, 0).astype(np.int32)

aims.write(vol_aims, args.output)
if args.verbose : 
    print(f"Binarisation of {args.input} saved at {args.output}")
