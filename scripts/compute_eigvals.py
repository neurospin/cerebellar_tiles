from soma import aims
import argparse
import numpy as np
from skimage.feature import hessian_matrix, hessian_matrix_eigvals
from pathlib import Path

# Refactored 2026-05-29 — no longer writes the per-subject header .hdr.
# Downstream (compute_sheetness) now reads the header directly from the input volume
# the eigvals were computed on (the WM-peak-normalised cropped T1w), which avoids the
# stale-header side-effect when multiple sigma rules run in parallel writing to a
# shared folder.

parser = argparse.ArgumentParser()

parser.add_argument("-v", "--verbose", action="store_true", help="Verbose mode")
parser.add_argument("-i", "--input", required=True, help="Input nifti")
parser.add_argument("-s", "--sigma", required=True, help="Sigma used for the computation of the hessian")
parser.add_argument("-o", "--output", required=True, help="Saving folder")
parser.add_argument("--sort_eigvals", action="store_true", help="Sort eigvals by raw values")
parser.add_argument("--save_eigvals", action="store_true", help="Save eigenvalues as nifti file for visualisation")
args = parser.parse_args()

# Retrieving volume

input_path = Path(args.input)
output_path = Path(args.output)
split_basename = input_path.name.split("_")
subject_name = split_basename[0]

if args.verbose :
    print("\n _____________ COMPUTING EIGENVALUES _____________ \n")
    print(f"Input path : {args.input}")
    print(f"Input subject name : {subject_name}")

volume = aims.read(args.input)
header_template = volume.header()

vol_np = np.squeeze(volume.np.copy()) # To retrieve a 3D image (removing the time dimension)

if args.verbose :
    print(f"Sigma used: {args.sigma}")

spacing = list(volume.header()["voxel_size"])
spacing = spacing[:-1] if len(spacing) == 4 else spacing # Removing the last element (time dimension if there)

sx, sy, sz = spacing

sigma = float(args.sigma)

sig_x = sigma / sx
sig_y = sigma / sy
sig_z = sigma / sz

if args.verbose :
    print(f"Spacing of voxel of input: {spacing}")
    print(f"Computing hessian with sigma : {(sig_x, sig_y, sig_z)}")

# Computing hessian and eigvals

if args.verbose :
    print("Computation of hessian eigenvalues")

H_elems = hessian_matrix(vol_np, sigma=(sig_x, sig_y, sig_z), use_gaussian_derivatives = True)
eigvals = hessian_matrix_eigvals(H_elems)

if args.sort_eigvals :
    print("Sorting eigenvalue by raw values")
    eigvals = np.sort(eigvals, axis=0)

if args.save_eigvals :
    if args.verbose :
        print(f"Saving eigenvalues with sorting = {args.sort_eigvals}")
        print(f"Saving at {output_path}")
    l1, l2, l3 = eigvals
    for ind,l_i in enumerate([l1, l2, l3]):
        saving_path = f"{output_path}/{subject_name}_lambda{ind + 1}_sigma{args.sigma}.nii.gz"
        l_i_aims = aims.Volume(l_i)
        l_i_aims.copyHeaderFrom(header_template)
        aims.write(l_i_aims, saving_path)

numpy_eigvals_path = f"{output_path}/{subject_name}_eigvals_raw_sigma{args.sigma}" if not args.sort_eigvals else f"{output_path}/{subject_name}_eigvals_sorted_sigma{sigma}"
if args.verbose :
    print(f"Saving npy file at {numpy_eigvals_path}")

np.save(numpy_eigvals_path,eigvals)
