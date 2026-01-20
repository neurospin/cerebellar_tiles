# Import libs
import argparse
import numpy as np
from soma import aims, aimsalgo

# Parser for arguments
parser = argparse.ArgumentParser()
parser.add_argument("-v", "--verbose", action="store_true", help="Verbose mode")
parser.add_argument("--input", required=True, help="Input nifti path")
parser.add_argument("--output", required=True, help="Output nifti file")
parser.add_argument("--transform_mat", required=True, help="Tranformation matrix file path (txt or trm)")
parser.add_argument("--output_vs", type=tuple, default= (0.5, 0.5, 0.5), help="Output voxel size (tuple), default to (0.5, 0.5, 0.5)")
parser.add_argument('--acapulco', action='store_true', help='the matrix is the one output by Acapulco (sub-xxx_n4_affine.txt)')
parser.add_argument('--mask', action='store_true', help='Apply nearest neighbor interpolation instead of cubic (for masks)')
args = parser.parse_args()

vol = aims.read(args.input)
vol_dt = vol.__array__() # Volume dtype 

header = aims.StandardReferentials.icbm2009cTemplateHeader()

if args.acapulco:
    with open(args.transform_mat) as f:
        lines = f.readlines()
    lines = [[str(x.strip()) for x in y.split()] for y in lines]
    if args.verbose : 
	print(lines)
    mni_to_sb = aims.AffineTransformation3d()
    mni_to_sb.affine()[:, :, 0, 0] = lines
    sbi = vol.header()['referentials'].index(
        aims.StandardReferentials.commonScannerBasedReferential())
    sb = aims.AffineTransformation3d(vol.header()['transformations'][sbi])
    tpl_to_mni = aims.AffineTransformation3d(header['transformations'][0])
    transform_mat = tpl_to_mni.inverse() * mni_to_sb.inverse() * sb
else:
    transform_mat = aims.read(args.transform_mat)

# New dimensions of the volume
output_vs = np.array(args.output_vs)

resampling_ratio = np.array(header["voxel_size"][:3]) / output_vs
origin_dim = header["volume_dimension"][:3]

new_dim = list((resampling_ratio * origin_dim).astype(int))

# Generating the new volume
resampled = aims.Volume(new_dim, dtype=vol_dt.dtype)
resampled.copyHeaderFrom(header) #Be careful it is a shallow copy 
resampled.header()["voxel_size"] = list(output_vs) + [1] 

interpolation = 0 if args.mask else 3 #NN interpolation for mask and cubic for regular images

#Resampler 
resampler = aimsalgo.ResamplerFactory(vol).getResampler(interpolation) #Interpolation Cubic 
resampler.setDefaultValue(0)
resampler.setRef(vol)

if args.verbose : 
    print(f"Registering {args.input} to MNI using {args.transform_mat} with resolution {args.output_vs}")
#Resampling
resampled = resampler.doit(
    transform_mat,
    new_dim[0],
    new_dim[1],
    new_dim[2],
    output_vs
)

if args.verbose : 
    print(f"Saving resampled at {args.output}")
