# Description of the pipeline

# Inputs :

Inputs to run the pipeline are the following ones : 
- Raw T1w-MRI : 
- Mask of the cerebellum in the MNI (in our case it is an aggregation of 27 healthy subjects in the MNI)
- List of masks of subsctructures (vermis, hemispheres, etc, ...): Need at least one substructure which can be the mask of the cerebellum described above or other masks computed the same way. 
Those masks aims to focus on regions without getting a fine grained segmentation

Important : The masks need to be registered in the same space and at the same resolution as the target volumes. By default, they need to be registered in the MNI at 0.5mm isotropic.

# Produced files

In this section : `{{subject}}` refers to a specific subject and `{{substructure}}` to a substructure.
All those files can be saved at the end.

## Acapulco (subject specific)

Acapulco produces from a T1w-MRI a lot of files but the only one kept are : 

- `masks/{{subject}}_n4_affine.txt` : Transformation matrix of the MRI from native space of the subject to MNI
- `masks/{{subject}}_n4_inv-affine.txt` : Inverse transformation matrix of the MRI from native space of the subject to MNI
- `masks/{{subject}}_n4_mni_seg_post.nii.gz` : Segmentation done by acapulco in the MNI after post-processing steps
- `masks/{{subject}}_n4_mni_seg_post_inverse.nii.gz` : Segmentation of acapulco registered in patient native space

## Homemade (using aims)

### Common files used by all the subjects

- `common/{{substructure}}_dilated_mask.nii.gz` : Dilatation of the masks of the different substructures (to ensure that we capture all the information we need)
- `common/bbox_cerebellum_atlas.npy` : Coordinates of the bounding box of the mask of the cerebellum in the MNI space (to cropped the images)
- `common/{{substructure}}_mask_cropped.nii.gz` : Cropped mask of the substructures
- `common/{{substructure}}_bbox.npy` : Bounding box values of the substructure (to ensure that all the final volumes have the same shapes)

### Subject specific files :

**Using all the MRI**
- `mni/{{subject}}_t1w_mni.nii.gz` : T1w-MRI registered to MNI space using the affine transformation computed by acapulco (registration done with aims)
- `masks/{{subject}}_seg_acapulco_mni.nii.gz` : Segmentation of acapulco registered in the MNI (using aims)
- `masks/{{subject}}_binary_acapulco_mni.nii.gz` : Binarisation of acapulco segmentation (to merge different substructures masks)

**Working in a subspace of the cerebellum** :
- `bbox_cerebellum/{{subject}}_binary_acapulco_cropped.nii.gz` : Cropped binary mask of acapulco in a subspace of MNI space
- `bbox_cerebellum/{{subject}}_t1w_cropped.nii.gz` : Cropped T1w-MRI
- `bbox_cerebellum/{{subject}}_corrected_{{substructure}}_cropped.nii.gz` : Fusion of the mask of the substructure and the acapulco (subject's cerbellum segmentation) to retrieve a corrected version of the mask without external noise
- `bbox_cerebellum/{{subject}}_{{substructure}}_persistence_band.nii.gz` : Persistence bands computed multi-scale curvature persistence algorithm
- `bbox_cerebellum/{{subject}}_{{substructure}}_thresh_persistence.nii.gz` : Thresholded of the persistence bands for binarisation
- `bbox_cerebellum/{{subject}}_{{substructure}}_masked_persistence.nii.gz` : Masking the binary volume to retrieve the substructure
- `{{subject}}_{{substructure}}_skeleton_cropped.nii.gz` : final skeleton of the cerebellum white matter cropped around the subtructure of interest


