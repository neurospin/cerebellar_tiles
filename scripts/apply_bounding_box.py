import subprocess as sp
import numpy as np
import argparse

def compute_subvolume(input_path, output_path, bounding_box) :
    CMD_MEAN_CURV = ["AimsSubVolume",
            "-i", f"{input_path}",
            "-o", f"{output_path}",
            "-x", f"{bounding_box[0,0]}",
            "-y", f"{bounding_box[0,1]}",
            "-z", f"{bounding_box[0,2]}",
            "-X", f"{bounding_box[1,0]}",
            "-Y", f"{bounding_box[1,1]}",
            "-Z", f"{bounding_box[1,2]}",
            ]
    output = sp.run(CMD_MEAN_CURV, capture_output=True)
    return(output)

parser = argparse.ArgumentParser()
parser.add_argument("-v", "--verbose", action="store_true", help="Verbose mode")
parser.add_argument("-i", "--input", required=True, help="Input nifti file")
parser.add_argument("-o", "--output", required=True, help="Subvolume file")
parser.add_argument("--bbox_npy", required=True, help="Numpy file of the bounding box (form: [[x,y,z],[X,Y,Z]])")
args = parser.parse_args()

if args.verbose : 
    print(f"Computing subvolume with bbox : {args.bbox_npy}")

bbox = np.load(args.bbox_npy)

if args.verbose : 
    print(f"Bouding box : {bbox}")

compute_subvolume(args.input, args.output, bbox)

if args.verbose : 
    print(f"Succefully computed subvolume, saved at : {args.output}")
