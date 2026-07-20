# Cerebellar tiles pipeline

Snakemake pipeline that extracts the cerebellar white-matter foliation (arbor vitae) from a
T1-weighted MRI as a Hessian-based *sheetness* field, and packages per-subject volumes for
downstream deep learning. It runs one subject per DAG branch and is designed to scale to large
cohorts on an HPC (TGCC).

## Purpose

For each subject the pipeline produces, on a shared MNI 0.5 mm cerebellum grid:
- a continuous **local z-score sheetness** field (the DL input),
- a **hysteresis foliation binary** (the extracted arbor vitae),
- per-substructure tiles (e.g. vermis), whole cerebellum or any lobule,
- a single `.npz` bundle per subject for a dataloader,
- per-subject **QC** and a dataset-level **manifest**.

## Outputs

Per subject (`results/<subject>/`):
| Output | What it is |
|---|---|
| `<sub>_tiles.npz` | DL bundle: whole-cerebellum `zscore` (f32) + `binary` (uint8) + Acapulco `labels` (int16) + `affine` + `meta`, plus any pre-baked substructure tiles (`vermis_zscore`, `vermis_binary`) |
| `sheetness/<sub>_local_z_score_sheetness_filter5mm.nii.gz` | continuous sheetness field |
| `sheetness/<sub>_foliation_binary.nii.gz` | whole-cerebellum foliation binary |
| `<sub>_<substructure>_foliation_binary_cropped.nii.gz` | per-substructure binary tile (deliverable) |
| `<sub>_<substructure>_zscore_cropped.nii.gz` | per-substructure sheetness tile (pre-baked substructures only) |
| `bbox_cerebellum/<sub>_seg_acapulco_cropped.nii.gz` | Acapulco lobule labels (for on-the-fly substructures / stats) |
| `bbox_cerebellum/<sub>_t1w_cropped.nii.gz`, `masks/…`, transforms | cropped T1w, masks, MNI affines |
| `qc/<sub>_qc.json` | per-subject validity checks |

Dataset level (`results/`): `manifest.json` (dataset card — provenance, frozen working point,
composition, QC summary, caveats), `qc.csv`, `config_snapshot.json`.

On-the-fly substructure in a dataloader:
```python
d = np.load("<sub>_tiles.npz")
vermis = d["zscore"] * np.isin(d["labels"], [60, 70, 80, 90, 100])  # any lobule set (tmc ids)
```

## Requirements

- **Snakemake** ≥ 9.14.0 (with the `cluster-generic` executor plugin for the TGCC profile).
- **Acapulco** container (cerebellum segmentation) — CPU `.sif`, [GitLab](https://gitlab.com/shuohan/acapulco). This pipeline uses 0.3.0.
- **`soma`/`aims`** (NIfTI I/O) and **`VipGeometry`** (mean curvature), both from the
  [Morphologist](https://brainvisa.info/web/morphologist.html) tool — provided by the pixi env
  (`morphologist ≥ 6.0.5`) locally, or `module load morphologist/5.2` on TGCC.

Local env is reproducible via **pixi** (`pixi.toml`): `pixi install`, then rules run under
`pixi run …` (see `config.yaml → environments.pixi_env`).

## Repository structure

```
.
├── cerebellar_tiles.smk        # master Snakefile: config, subjects, rule all, includes, onsuccess cleanup
├── config.yaml                 # all parameters + paths (gitignored; commit a template only)
├── subjects.txt                # one subject id per line (path set in config)
├── rules/
│   ├── acapulco_segmentation_tgcc.smk    # Acapulco via pcocc-rs (TGCC)
│   ├── acapulco_segmentation_local.smk   # Acapulco via apptainer .sif (local)  [one is included by platform]
│   ├── masks.smk               # transforms, MNI resample, binarise, dilate, bbox, fusion
│   ├── foliation_hessian.smk   # the locked sheetness extraction chain
│   ├── packaging.smk           # substructure z-score tiles + per-subject .npz
│   └── qc.smk                  # per-subject QC + dataset manifest
├── scripts/                    # one script per rule (all soma.aims / numpy)
├── containers/                 # Acapulco .sif files (gitignored)
├── profiles/tgcc/              # TGCC cluster-generic submit + status scripts
├── hpc_running_example.slurm   # example ccc_msub job wrapping the snakemake call
├── pixi.toml / pixi.lock       # reproducible local env
├── logs/  inputs/  results/    # created at runtime; paths set in config (gitignored)
```

## Configuration

Edit `config.yaml` (paths, env, parameters). Key groups:
- **Inputs**: `raw_data`, `data_structure`, `suffix_nifti`, `subject_list`; **outputs**: `output_folder`, `logs`, `benchmark`.
- **Frozen working point** (do not change casually — this is the locked pipeline): `sigmas`,
  `alpha`, `beta`, `gamma_power`, `target_wm_value`, `window_size` (z-score, mm),
  `min_percentile`/`max_percentile` (hysteresis).
- **Masks**: `substructures_masks` (atlas ROIs), `prebaked_tiles` (subset to bake as tiles),
  dilations.
- **Cleanup**: `cleanup_intermediates` (temp per-sigma/aggregation volumes + sweep orphan
  `.minf` sidecars and empty dirs on success).

To run a subset of subjects, edit `subjects.txt`.

## How to run

1. Fill in `config.yaml` (paths, env, parameters) and `subjects.txt`.
2. Install the container(s) into `containers/` and the local env (`pixi install`).
3. Launch:

**Locally** (apptainer for Acapulco):
```sh
snakemake -s cerebellar_tiles.smk --configfile config.yaml \
  -j <max_jobs> --use-apptainer --apptainer-args "--bind <data_paths>"
```

**On an HPC (TGCC)** via the cluster profile:
```sh
snakemake -s cerebellar_tiles.smk --configfile config.yaml \
  -j <max_jobs> --profile profiles/tgcc
```
See `hpc_running_example.slurm` for a full `ccc_msub` wrapper. Keep `-j` under the queue's
`MaxSub` and set the profile's status-poll rate low (TGCC asks for ≤ 1–2 scheduler queries/min).

**NB** `rules/acapulco_segmentation_*.smk` depends on the HPC's container policy — TGCC uses
`pcocc-rs`, local uses apptainer; the platform switch is `config → execution`.

Re-running when everything is already built completes as a no-op and still fires the
`onsuccess` cleanup (removes orphan `.minf` + empty dirs) — a convenient way to clean after the fact.

## Pipeline steps

One subject per branch. Space is MNI152-ICBM2009c 0.5 mm iso throughout after registration.

**Segmentation** (`acapulco_segmentation_*`)
- `acapulco_segmentation` — run Acapulco → native + MNI lobule segmentation and the N4 affine transforms (temp dir).

**Masks & registration to MNI** (`masks.smk`)
- `copy_mask_and_transform` — copy Acapulco's affine/inverse-affine and MNI/native segmentations out of the temp dir.
- `resampling_mni_registration_t1w` / `_acapulco_mask` — resample raw T1w and the native segmentation to MNI 0.5 mm using the Acapulco affine.
- `binarisation_acapulco_mask` — binarise the MNI segmentation → whole-cerebellum mask.
- `dilatation_mask_substructure` — dilate each atlas substructure ROI (vermis, cerebellum, …).
- `compute_bbox_cerebellum` — bounding box of the (dilated) cerebellum atlas mask (shared by all subjects → fixed tile shape).
- `apply_cerebellum_bbox_*` — crop the binary mask, the lobule labels, the T1w, and the substructure ROIs to that cerebellum bbox.
- `fusion_acapulco_substructures_mask` — intersect each atlas substructure ROI with the subject's whole-cerebellum mask (trims dilation to real tissue; uses the robust whole-cerebellum mask, **not** error-prone lobule labels).
- `compute_bbox_substructure` — per-substructure bounding box (shared across subjects), used to crop the final tiles.

**Hessian foliation extraction** — the locked chain (`foliation_hessian.smk`)
- `wm_peak_normalisation` — rescale the T1w so the white-matter histogram peak hits a fixed target value.
- `compute_eigvals` — Hessian eigenvalues per scale σ, sorted by raw value (signs preserved).
- `compute_sheetness` — sheetness `F = (1 − e^(−R/α))·(1 − e^(−S/β))` per σ from the eigenvalues (R = |λ₁|/|λ₃|, S = Frobenius norm).
- `gamma_normalisation` — scale each σ response by σ^γ before aggregation.
- `aggregation_argmax` — max (and argmax) of the sheetness across scales.
- `z_score_normalisation` — local box-filter z-score of the max response, within the cerebellum mask.
- `hysteresis_threshold` — hysteresis binarisation with percentiles computed in the cerebellum mask → foliation binary.
- `apply_mask_substructure` / `apply_bbox_substructure` — mask the binary by each substructure and crop to its bbox → per-substructure binary deliverable.

**DL packaging** (`packaging.smk`)
- `apply_mask_substructure_zscore` / `apply_bbox_substructure_zscore` — same mask+crop path for the z-score field → pre-baked substructure sheetness tiles.
- `package_npz` — bundle whole-cerebellum z-score + binary + lobule labels (+ pre-baked tiles) + affine + metadata into one `<subject>_tiles.npz`.

**QC & manifest** (`qc.smk`)
- `freeze_config` — snapshot the full config into the results dir (provenance).
- `qc_subject` — per-subject validity checks (header sform/qform split, empty/NaN fields, tile shape, npz integrity) → `<subject>_qc.json`; flags, never blocks.
- `gather_manifest` — aggregate all QC (+ cohort-relative outlier flags) and the frozen config → `manifest.json` + `qc.csv`.

## Notes / TODO

- **Betti / topology metrics** are computed by a *separate* analysis pass (needs `gudhi`), not by
  this pipeline — keeps the production env dependency-free on the HPC.
- The `.npz` `affine` is a best-effort extraction from the aims header; verify once per grid that
  its voxel scale is ~0.5 mm (the kept NIfTI holds authoritative geometry regardless).
- `scripts/persistence_mean_curvature.py` is an unused mean-curvature reference (not in the DAG).
