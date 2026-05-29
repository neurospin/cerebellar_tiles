from soma import aims
import numpy as np
import argparse
from scipy.ndimage import uniform_filter
import logging
from pathlib import Path

# Parsing arguments
parser = argparse.ArgumentParser()

parser.add_argument("-v", "--verbose", action="count", default=0, help="Verbose mode. -v for INFO? -vv for DEBUG")
parser.add_argument("-i", "--input", required=True, help="Input volume : Max aggregation of the sheetness values gamma normalized")
parser.add_argument("-m", "--mask", required=True, help="Mask of the cerebellum")
parser.add_argument("-o", "--output", required= True, help ="Output folder for volume")
parser.add_argument("--window_size", required=True, help="Window size for the computation of local statistics : Size of the cube in mm")
parser.add_argument("--save_intermediate", action="store_true", help="Save the intermediates : mean, std")

args = parser.parse_args()

# Setting the logger information

level = logging.WARNING - 10 * args.verbose
logging.basicConfig(level=level, format="%(levelname)s : %(message)s")
logger = logging.getLogger(__name__)

# Definition of the function

def convertion_mm_voxel(header_volume, window_size_vox : float):
    """
    Inputs :
        - header_volume : Header of the aims volume (volume.header())
        - window_size_vox (List[float]) : the window size in mm
    """
    voxel_size= np.array(header_volume["voxel_size"])
    if len(voxel_size) == 4 :
        voxel_size = np.array(voxel_size)[:-1] #Removing time dimension (last one) to make it 3D
    elif len(voxel_size) != 3 : 
        raise ValueError(f"Wrong voxel size parsed, got : {voxel_size}")
    logger.debug("Voxel size volume : %s", voxel_size)
    window_3D = np.array([window_size_vox] * 3)
    return (np.floor(window_3D / voxel_size) + 1).astype(np.int16)

def local_z_score_normalisation(volume : np.ndarray, header_volume, mask : np.ndarray, window_size_vox : float):
    # Adaptating the mm dimension to voxel of the volume
    filter_dimensions = convertion_mm_voxel(header_volume, window_size_vox)
    logger.debug("Voxel space dimensions from window_size_vox : %s", filter_dimensions)
    for ind,dim in enumerate(filter_dimensions) :
        if dim%2 == 0 :
            filter_dimensions[ind] += 1
            logger.warning("Changing dimension #%d from %s to %s", ind, dim, dim+1)
    logger.debug("After dimension check : %s", filter_dimensions)

    #Updating header
    header_volume["z_scoring_filter"] = filter_dimensions.tolist()

    # Masking volume : 
    vol_masked = volume * mask.astype(np.float32)

    #Number voxels in the cube
    n_vox = filter_dimensions[0] * filter_dimensions[1] * filter_dimensions[2]

    logger.debug("Number of voxels in filter : %s", n_vox)

    sum_v = uniform_filter(vol_masked, size=filter_dimensions, mode="constant") * n_vox
    sum_v2 = uniform_filter(vol_masked ** 2, size=filter_dimensions, mode="constant") * n_vox
    sum_m = uniform_filter(mask.astype(np.float32), size=filter_dimensions, mode="constant") * n_vox

    min_count = max(1, int(0.05 * n_vox)) #A filter results is valid if 5% of its voxel are in mask
    valid = sum_m >= min_count

    mean = np.zeros_like(volume)
    var = np.zeros_like(volume)

    np.divide(sum_v, sum_m, out=mean, where=valid)
    np.divide(sum_v2, sum_m, out=var, where=valid)
    var = var - mean**2
    var = np.clip(var, 1e-8, None)
    std = np.sqrt(var)

    z = np.zeros_like(volume)
    np.divide(volume - mean, std, out=z, where=valid)
    z = np.where(mask.astype(bool), z, z[mask.astype(bool)].min()).astype(np.float32)
    mean = np.where(mask.astype(bool), mean, 0.0).astype(np.float32)
    std = np.where(mask.astype(bool), std, 0.0).astype(np.float32)

    return z, mean, std

### _____________________ Computation _____________________

# Retrieving the data

input_path = Path(args.input)
subject_name = input_path.name.split("_")[0]

logger.info(" \n ________ Input information ________ \n Path volume : %s \n Subject name = %s", input_path, subject_name)

volume = aims.read(str(input_path))
header_volume = volume.header()
vol_np = np.squeeze(volume.np.copy())

logger.info(" Mask path : %s ", args.mask)

mask = aims.read(args.mask)
mask_np = np.squeeze(mask.np.copy())

# Computing z_score

z_score, mean, std = local_z_score_normalisation(vol_np, header_volume, mask_np, float(args.window_size))

# Saving the volume

z_score_aims = aims.Volume(z_score.astype(np.float32))
z_score_aims.copyHeaderFrom(header_volume)
saving_path = Path(args.output) / f"{subject_name}_local_z_score_sheetness_filter{args.window_size}mm.nii.gz"
logger.info("Saving z-score volume to : %s", saving_path)
aims.write(z_score_aims, str(saving_path))

if args.save_intermediate : 
    mean_aims = aims.Volume(mean.astype(np.float32))
    mean_aims.copyHeaderFrom(header_volume)

    std_aims = aims.Volume(std.astype(np.float32))
    std_aims.copyHeaderFrom(header_volume)

    saving_path_mean = Path(args.output) / f"{subject_name}_local_mean_sheetness_filter{args.window_size}mm.nii.gz"
    saving_path_std = Path(args.output) / f"{subject_name}_local_std_sheetness_filter{args.window_size}mm.nii.gz"

    logger.info(" ___________ SAVING INTERMEDIATES __________")
    logger.info("Saving mean at : %s", saving_path_mean)
    aims.write(mean_aims, str(saving_path_mean))
    logger.info("Saving std at : %s", saving_path_std)
    aims.write(std_aims, str(saving_path_std))

logger.info("Saved !")

