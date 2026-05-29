from soma import aims
import numpy as np
import argparse
from pathlib import Path
import re

# Defintion
def sheetness(l1, l2, l3, alpha, beta):
    l1 = np.abs(l1)
    l2 = np.abs(l2)
    l3 = np.abs(l3)

    R = l1 / (l3 + 1e-10) # Small values : GM+WM
    S = np.sqrt(l1**2 + l2**2 + l3**2) # Highlights high magnitude curvatures : CSF (fissures) and WM (goal)

    R_norm = 1- np.exp(-R/alpha)
    struct_norm = 1 - np.exp(-S/beta)

    P = R_norm * struct_norm #Probability of WM and Grey matter

    return P, R_norm, struct_norm, R, S

# Parsing arguments
parser = argparse.ArgumentParser()
parser.add_argument("-v", "--verbose", action="store_true", help="Verbose mode")
parser.add_argument("-i", "--input", required=True, help="Input npy file containing eigvals at a given sigma")
parser.add_argument("--header_file", required=True, help="Header to use for saving as nifti")
parser.add_argument("-o", "--output", required=True, help="Output folder")
parser.add_argument("--alpha", required=True, default=1, help="Alpha parameter for sheetness computation")
parser.add_argument("--beta", required=True, default=200, help="Beta parameter for sheetness computation")
parser.add_argument("--save_intermediate", action="store_true", help="Save all the intermediates")

args= parser.parse_args()

sigma_pattern = re.compile(r"sigma(\d+(?:\.\d+)?)")

input_path = Path(args.input)
file_name = input_path.name
subject_name = file_name.split("_")[0]

output_path = Path(args.output)

if args.verbose : 
    print("\n _____________ COMPUTING SHEETNESS  _____________ \n")
    print(f"Computing sheetness with : {input_path}")
    print(f"Subject name : {subject_name}")
    print(f"Header used : {args.header_file}")

matched_sigma = sigma_pattern.search(file_name)

if args.verbose : 
    print(matched_sigma)

if matched_sigma:
    sigma = matched_sigma.group(1)
else :
    raise ValueError(f"File name ({file_name}) must contain a specification of sigma")

if args.verbose : 
    print(f"Computing sheetness with : {input_path}")
    print(f"Subject name : {subject_name}")
    print(f"Header used : {args.header_file}")
    print(f"Parsed sigma value : {sigma}")

pattern_sort = re.compile("sorted")
match_sort = pattern_sort.search(file_name)
if not match_sort: 
    raise ValueError(f"Eigenvalues must be sorted, working with {file_name}")

header_template = aims.read(args.header_file)
l1, l2, l3 = np.load(input_path)

if args.verbose : 
    print(f"Computing sheetness with parameters : alpha={args.alpha} ; beta={args.beta}")

sheet, R_norm, struct_norm, R, S = sheetness(l1, l2, l3, int(args.alpha), int(args.beta))

if args.verbose :
    print("Done")

if args.save_intermediate : 
    if args.verbose :
        print(f"Saving intermediates at : {output_path}")
    saving_names = [
        f"{output_path}/{subject_name}_R_sigma{sigma}.nii.gz",
        f"{output_path}/{subject_name}_R_norm_sigma{sigma}_alpha{args.alpha}.nii.gz",
        f"{output_path}/{subject_name}_S_sigma{sigma}.nii.gz",
        f"{output_path}/{subject_name}_S_norm_sigma{sigma}_beta{args.beta}.nii.gz",
    ]
    to_save = [R, R_norm,S, struct_norm]
    for file_name, file in zip(saving_names, to_save):
        file_aims = aims.Volume(file)
        file_aims.copyHeaderFrom(header_template)
        aims.write(file_aims, file_name)

sheetness_output_file = f"{args.output}/{subject_name}_sheetness_sigma{sigma}_alpha{args.alpha}_beta{args.beta}.nii.gz"
if args.verbose : 
    print(f"Saving sheetness at {sheetness_output_file}")

sheetness_aims = aims.Volume(sheet)
sheetness_aims.copyHeaderFrom(header_template)
aims.write(sheetness_aims, sheetness_output_file)
