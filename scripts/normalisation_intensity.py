from soma import aims
from pathlib import Path
import argparse
import numpy as np
from scipy.ndimage import gaussian_filter
from scipy.signal import find_peaks

# Refactored 2026-05-29 — target_wm_value exposed via --target_wm (was hardcoded 1000.0).

def get_wm_peak(image, brain_mask, n_bins=512):
    """
    Estimate the WM intensity peak from the brain histogram.

    Strategy: in T1w, WM is the rightmost major peak of the
    brain intensity histogram. We find it by:
    1. Computing histogram within brain mask
    2. Smoothing to remove noise-induced spurious peaks
    3. Finding the highest-intensity major peak
    """
    intensities = image[brain_mask].ravel()

    # Remove bottom 2% (CSF/background leakage) and top 1% (vessels)
    low  = np.percentile(intensities, 2)
    high = np.percentile(intensities, 99)
    intensities = intensities[(intensities > low) & (intensities < high)]

    # Build histogram
    counts, bin_edges = np.histogram(intensities, bins=n_bins)
    bin_centers = (bin_edges[:-1] + bin_edges[1:]) / 2

    # Smooth histogram to avoid finding noise peaks
    smoothed = gaussian_filter(counts.astype(float), sigma=5)

    # Find peaks — prominence filter removes minor bumps
    peaks, properties = find_peaks(smoothed,
                                   prominence=smoothed.max() * 0.1,
                                   distance=n_bins // 10)

    if len(peaks) == 0:
        # Fallback: use 95th percentile as WM estimate
        return np.percentile(intensities, 95)

    # WM is the rightmost (highest intensity) major peak in T1w
    wm_peak_idx = peaks[-1]
    return bin_centers[wm_peak_idx]


def normalise_to_wm_peak(image, brain_mask, target_wm_value=1000.0, n_bins=512):
    """
    Normalise image so that WM peak intensity = target_wm_value.

    Multiplicative normalisation:
        I_normalised = I * (target_wm_value / wm_peak)

    Preserves: histogram shape, local contrast ratios (GM/WM, CSF/WM),
    relative spatial structure (no intensity warping).
    """
    wm_peak = get_wm_peak(image, brain_mask, n_bins=n_bins)
    scale = target_wm_value / wm_peak
    normalised = image * scale
    return normalised, wm_peak, scale


def verify_normalisation(image_norm, brain_mask, label="", verbose=True):
    """Print summary statistics to verify the normalisation worked."""
    intensities = image_norm[brain_mask]
    if verbose:
        print(f"{label}")
        print(f"  Mean   : {intensities.mean():.4f}")
        print(f"  Median : {np.median(intensities):.4f}")
        print(f"  P95    : {np.percentile(intensities, 95):.4f}")
        print(f"  P99    : {np.percentile(intensities, 99):.4f}")
        print(f"  Std    : {intensities.std():.4f}")
    return (intensities.mean(), np.median(intensities),
            np.percentile(intensities, 95), np.percentile(intensities, 99),
            intensities.std())


# Parsing args

parser = argparse.ArgumentParser()

parser.add_argument("-v", "--verbose", action="store_true", help="Verbose mode")
parser.add_argument("-i", "--input", required=True, help="T1w MRI (resampled or not)")
parser.add_argument("-m", "--mask", required=True, help="Mask used for the normalisation")
parser.add_argument("-o", "--output", required=True, help="Normalised T1w")
parser.add_argument("--target_wm", type=float, default=1000.0,
                    help="Target intensity value the WM peak is mapped to. Default 1000.0.")
parser.add_argument("--save_stats", action="store_true", help="Saving stats from subject")
args = parser.parse_args()

# Retrieving volume

saving_folder = Path(args.output).parent
file_name = Path(args.input).name
subject_name = file_name.split("_")[0]

if args.verbose:
    print(f"Input image : {args.input}")
    print(f"Subject_name : {subject_name}")
    print(f"Target WM value : {args.target_wm}")


volume = aims.read(args.input)
header_template = volume.header()

vol_np = np.squeeze(volume.np.copy())

mask = aims.read(args.mask)
mask_np = np.squeeze(mask.np.copy()).astype(bool)

norm_np, wm_peak, scale = normalise_to_wm_peak(vol_np, mask_np, target_wm_value=args.target_wm)

if args.verbose:
    print(f"White matter peak : {wm_peak}")
    print(f"Image scales by : {scale}")

mean_norm, median_norm, perc_95, perc_99, std_norm = verify_normalisation(norm_np, mask_np, verbose=args.verbose)

if args.save_stats:
    stats_dict = {
        "WM_peak": wm_peak,
        "Scale": scale,
        "Target_WM": args.target_wm,
        "Mean": mean_norm,
        "Median": median_norm,
        "P95": perc_95,
        "P99": perc_99,
        "Std": std_norm,
    }
    lines = [f"{name},{stat}" for name, stat in stats_dict.items()]
    with open(f"{saving_folder}/{subject_name}_stats_normalisation.txt", "x") as f:
        f.writelines("\n".join(lines))

if args.verbose:
    print("Saving normalised image...")

norm_vol_aims = aims.Volume(norm_np)
norm_vol_aims.copyHeaderFrom(header_template)
norm_vol_aims.header()["data_type"] = "FLOAT"  # Saving the image into float 32

aims.write(norm_vol_aims, args.output)

if args.verbose:
    print(f"Saved at {args.output} !")
