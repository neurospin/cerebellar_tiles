from soma import aims
import numpy as np
import argparse

# Parser for arguments
parser = argparse.ArgumentParser()
parser.add_argument("-v", "--verbose", action="store_true", help="Verbose mode")
parser.add_argument("-i", "--input",required=True, help="Input nifti path")
parser.add_argument("-o", "--output", required=True, help="Output nifti file")
parser.add_argument("--min", required = True, help="Minimum value of mean curvature to keep")
parser.add_argument("--max", required = True, help="Maximum value of mean curvature to keep")
args = parser.parse_args()

if not isinstance(args.min, float) or not isinstance(args.max, float) :
    args.min = float(args.min)
    args.max = float(args.max)

assert args.min < args.max, "Maximum value needs to be smaller than minimum value"

if args.verbose :
    print(f"Thresholding {args.input} with : \n - minimum : {args.min} \n - maximum : {args.max} ")

obj = aims.read(args.input)
vol_np = obj.np

#Apply Mask : 
vol_np[:] = np.where(((vol_np >= args.min) & (vol_np <= args.max)), 1, 0)

# Convert from float type to S16 more convinient
conv = aims.Converter(intype=obj, outtype=aims.Volume("S16")) 
vol = conv(obj)

if args.verbose :
    print(f"Saving thresholded volume to {args.output}")

aims.write(vol, args.output)
