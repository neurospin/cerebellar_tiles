# Importation of librairies
from soma import aims
import numpy as np
# import pandas as pd
import argparse
import subprocess as sp
import os
from pathlib import Path

# Function definition

def compute_mean_cuvature(input_path, output_path, sigma) :
    CMD_MEAN_CURV = ["VipGeometry",
            "-m", "mc",
            "-s", f"{sigma}", 
            "-i", f"{input_path}",
            "-o", f"{output_path}"
            ]

    output = sp.run(CMD_MEAN_CURV, capture_output=True)
    return(output)

def save_numpy_nifti(np_volume, saving_path, header = None):
    print(f"Volume dtype : {np_volume.dtype}")
    aims_volume = aims.Volume(np_volume.astype(np.float32))
    if header : 
        aims_volume.copyHeaderFrom(header)
    aims.write(aims_volume, str(saving_path))
    print(f"Saved np_volume to {saving_path}")

def save_dict_np_vol(dict_vol, header, base_name, mapping_endpath):
    for sigma, np_vol in dict_vol.items():
        full_path = f"{base_name}_{mapping_endpath[sigma]}.nii.gz"
        save_numpy_nifti(np_vol, full_path, header)


def parse_sigma(list_sigma): 
    str_sigmas = [str(sig).replace(".","_") for sig in list_sigma]
    return dict(zip(list_sigma, str_sigmas))


# 0. Parsing arguments
parser = argparse.ArgumentParser()
parser.add_argument("-v", "--verbose", action="store_true", help="Verbose mode")
parser.add_argument("--save_mc", action="store_true", help="Save mean curvature files (and associated files)")
parser.add_argument("--save_bands", action="store_true", help="Save mean curvature bands files (and associated files)")
parser.add_argument("--input", required=True, help="Input nifti path")
parser.add_argument("--tmp_folder", required=True, help="Temporary folder to keep files")
parser.add_argument("--output_persistence", required=True, help="Persistence nifti saving path")
parser.add_argument("--output_thresholded", required=True, help="Thresholded persistence nifti saving path")
parser.add_argument("--cerebellum_mask", required=True, help="TEMPORARY nifti file of the cerebellum mask")
parser.add_argument("--threshold_persistence", required=True, help="Threshold of the persistence band")
parser.add_argument("--min_quantile", required=True, help="Minimum quantile", type=float)
parser.add_argument("--max_quantile", required=True, help="Maximum quantile", type=float)
parser.add_argument("--sigmas", required=True, nargs="+", type=float, help="List of sigmas used for the multi-scale mean curvature computation")
args = parser.parse_args()

# Retrieving each sigmas
mapping_sigma = parse_sigma(args.sigmas)
if args.verbose :
    print(f"mapping sigma : {mapping_sigma}")

# Retrieve the resampled volume to ICBM2009 and its header : to add informations to new volumes
resampled_vol = aims.read(args.input)
header_input = resampled_vol.header()

# Retrieve cerebellum mask
mask_cerebellum = aims.read(args.cerebellum_mask).np.copy()
bin_cerebellum = np.where(mask_cerebellum != 0, 1, 0).astype(bool)

# Steps
# Compute mean curvature for each sigma
if args.verbose :
    print("Computing mean curvature \n")
def mean_curvature_path(subject : str, mask : str,  suffix : str, folder : str):
    return f"{folder}/{subject}_{mask}_mean_curvature_{suffix}.nii.gz"

def band_path(subject : str, mask : str,  suffix : str, folder : str, min_quant : float = args.min_quantile, max_quant : float = args.max_quantile):
    subject_name = subject.split("_")[0]
    return f"{folder}/{subject_name}/{subject_name}_{mask}_band_{min_quant}_{max_quant}_{suffix}.nii.gz"

dict_mean_curv = dict()
for sigma, path_end in mapping_sigma.items() : 
    sub_name = Path(args.input).stem # Remove gz
    sub_name = Path(sub_name).stem # Remove nii
    mask_name = Path(args.cerebellum_mask).stem
    full_path = mean_curvature_path(subject = sub_name, mask =mask_name, suffix = path_end, folder = args.tmp_folder)
    if args.verbose :
        print(f"Computing mean curvature of {args.input} with sigma : {sigma}")
    compute_mean_cuvature(args.input, full_path, sigma)
    if args.verbose :
        print(f"Success of sigma : {sigma}")
    np_vol = aims.read(full_path).np.copy()
    dict_mean_curv[sigma] = np_vol
    # os.remove(full_path)
    # os.remove(full_path + ".minf")


# Retrieve mask of negative values (i.e. White matter values)
if args.verbose :
    print("Retrieving mask negative values... \n")
neg_masks = dict()
for sigma, np_vol in dict_mean_curv.items() :
    neg_masks[sigma] = (np_vol < 0)

# Scaling mean curvature according to sigma 
if args.verbose :
    print("Scaling mean curvature according to sigma... \n")
dict_scaled_mc = dict()
for sigma, np_vol in dict_mean_curv.items() :
    dict_scaled_mc[sigma] = sigma * np_vol

# Retrieving individual quantiles : 
if args.verbose :
    print(" Quantile for each sigma values... \n")
dict_quantiles = dict()
for sigma, np_vol in dict_scaled_mc.items():
    mc_neg_val = np_vol[neg_masks[sigma] & bin_cerebellum]
    dict_quantiles[sigma] = np.quantile(mc_neg_val, [args.min_quantile, args.max_quantile])
if args.verbose :
    print("Quantiles \n", dict_quantiles)
# pd.DataFrame(dict_quantiles).to_csv("quantiles.csv")

# Retrieving bands
if args.verbose :
    print("\n Band computation... \n")
dict_band = dict()
for sigma, np_vol in dict_scaled_mc.items():
    band = neg_masks[sigma] & (np_vol >= dict_quantiles[sigma][0]) & (np_vol <= dict_quantiles[sigma][1])
    dict_band[sigma] = band

# Computing persistence
if args.verbose :
    print("Computing persistence... \n")
all_band = np.stack(list(dict_band.values()), axis=0)
all_scaled_mc = np.stack(list(dict_scaled_mc.values()), axis=0)

persis_band = np.sum(all_band, axis= 0)
persis_weighted = np.sum(all_scaled_mc, axis= 0)

# Thresholding persistence
thresholded_persistence_band = np.where(persis_band >= int(args.threshold_persistence), 1, 0)

# Saving persistence volume
save_numpy_nifti(persis_band, args.output_persistence, header=header_input)
save_numpy_nifti(thresholded_persistence_band, args.output_thresholded, header=header_input)

# Cleaning files
if not args.save_mc :
    if args.verbose : 
        print("Cleaning mean curvature files")
    for sigma, path_end in mapping_sigma.items() :
        sub_name = Path(args.input).stem # Remove gz
        sub_name = Path(sub_name).stem # Remove nii
        mask_name = Path(args.cerebellum_mask).stem
        full_path = mean_curvature_path(subject = sub_name, mask =mask_name, suffix = path_end, folder = args.tmp_folder)
        os.remove(full_path)
        os.remove(full_path + ".minf")

# Cleaning files
if args.save_bands :
    if args.verbose : 
        print("Saving bands")
    for sigma, path_end in mapping_sigma.items() :
        sub_name = Path(args.input).stem # Remove gz
        sub_name = Path(sub_name).stem # Remove nii
        mask_name = Path(args.cerebellum_mask).stem
        full_path = band_path(subject = sub_name, mask =mask_name, suffix = path_end, folder = args.tmp_folder)
        if args.verbose : 
            print("Band saved at : {full_path}")
        save_numpy_nifti(dict_band[sigma], full_path, header_input)
