import argparse
import numpy as np
from soma import aims

# Parsing args

parser = argparse.ArgumentParser()

parser.add_argument("-v", "--verbose", action="store_true", help="Verbose mode")
parser.add_argument("-i", "--input", required=True, help="Input mask (should be binary)")
parser.add_argument("-o", "--output", required=True, help="Numpy file to save the bouding box mask")
parser.add_argument("--dilatation", required=True, help="Radius of the dilatation")
args = parser.parse_args()

# Main

## Compute the bounding box of the mask
aims_volume = aims.read(args.input)

val = np.array(np.where(aims_volume.np >= 1)) #Dim (4, flatten of 3D)
bbox_masks = np.array([np.min(val, axis = 1), np.max(val, axis = 1)]) 

bbox_masks = bbox_masks[:, :-1] # Remove time step related information

if args.verbose :
    print("Bounding box w/out dilatation")
    print(bbox_masks)

bbox_masks[0] = bbox_masks[0] - int(args.dilatation)
bbox_masks[1] = bbox_masks[1] + int(args.dilatation)

if args.verbose :
    print(f"Bounding box with dilatation of {args.dilatation} voxels")
    print(bbox_masks)

np.save(args.output, bbox_masks)

