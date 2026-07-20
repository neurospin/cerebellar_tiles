import argparse
import numpy as np
from soma import aims

# Parsing args

parser = argparse.ArgumentParser()

parser.add_argument("-v", "--verbose", action="store_true", help="Verbose mode")
parser.add_argument("-i", "--input", required=True, help="Input volume")
parser.add_argument("--mask", required=True, help="Input mask (should be binary)")
parser.add_argument("-o", "--output", required=True, help="Output MRI - with mask applied")
args = parser.parse_args()

volume = aims.read(args.input)
header_template = volume.header()

mask = aims.read(args.mask)

assert mask.np.shape == volume.np.shape, "Volume aren't the same shape !"

masked_vol = volume.np * mask.np

if args.verbose :
    print(f"Masking {args.input} with mask from {args.mask}...")

masked_vol = volume.np * mask.np
output_aims = aims.Volume(masked_vol.astype(volume.np.dtype))
output_aims.copyHeaderFrom(header_template)

if args.verbose :
    print(f"Sucess, saved at {args.output}")

aims.write(output_aims, args.output)
