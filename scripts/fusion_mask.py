import argparse
import numpy as np
from soma import aims

# Parsing args

parser = argparse.ArgumentParser()

parser.add_argument("-v", "--verbose", action="store_true", help="Verbose mode")
parser.add_argument("--mask_1", required=True, help="First mask for the merge (binary)")
parser.add_argument("--mask_2", required=True, help="Second mask for the merge (should be the same dimension as the first one and binary...)")
parser.add_argument("-o", "--output", required=True, help="Merge nifti file name")
args = parser.parse_args()

# Main

if args.verbose : 
    print(f"Merging mask 1 : {args.mask_1} and mask 2 {args.mask_2}")

mask_1 = aims.read(args.mask_1)
mask_2 = aims.read(args.mask_2)
header_template = mask_1.header()

# Asserting the shape are the same
assert mask_1.np.shape == mask_2.np.shape,f"Mask should have the same shapes, got mask 1 : {mask_1.np.shape}, mask 2 {mask_2.np.shape}"
# Checking content of the masks
assert np.unique(mask_1.np).astype(np.int16) == [0,1]
assert np.unique(mask_2.np).astype(np.int26) == [0,1]

merged_mask_np = mask_1.np * mask_2.np

merge_mask_aims = aims.Volume(merged_mask_np.astype(np.int16))
merge_mask_aims.copyFromHeader(header_template)

aims.write(merge_mask_aims, args.output)

if args.verbose : 
    print(f"Masked merge ! Saved at {args.output}")
