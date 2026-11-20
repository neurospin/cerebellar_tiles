################################################
# Aggregate per-subject QC into the dataset manifest (dataset card) + qc.csv.
#
# - reads every {subject}_qc.json
# - adds cohort-relative outlier flags (median +/- k*MAD) for cerebellum volume + foliation fraction
# - snapshots the frozen working point from config, provenance (git, env), and QC summary
# - writes manifest.json (the dataset card) and qc.csv (one row per subject)
#
# Written next to the data: it lists subject IDs, keep it out of public places.
################################################

import argparse
import csv
import datetime as dt
import json
import subprocess
from pathlib import Path

import numpy as np


def _run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout.strip() or None
    except Exception:
        return None


def mad_outliers(values, k=5.0):
    """Boolean mask of robust outliers: |x - median| > k * 1.4826 * MAD."""
    v = np.asarray(values, dtype=np.float64)
    med = np.median(v)
    mad = np.median(np.abs(v - med))
    if mad == 0:
        return np.zeros_like(v, dtype=bool), med, 0.0
    scale = 1.4826 * mad
    return np.abs(v - med) > k * scale, float(med), float(scale)


def main():
    ap = argparse.ArgumentParser(description="Aggregate per-subject QC -> manifest.json + qc.csv")
    ap.add_argument("--qc-json", nargs="+", required=True, help="all {subject}_qc.json files")
    ap.add_argument("--config-json", required=True, help="frozen config snapshot as a JSON string or file")
    ap.add_argument("--dataset-name", default="unknown")
    ap.add_argument("--dataset-version", default="0.0.0")
    ap.add_argument("--pipeline-dir", default=".", help="repo dir for git provenance")
    ap.add_argument("--mad-k", type=float, default=5.0)
    ap.add_argument("--out-manifest", required=True)
    ap.add_argument("--out-csv", required=True)
    args = ap.parse_args()

    subs = [json.loads(Path(p).read_text()) for p in args.qc_json]
    subs.sort(key=lambda s: s.get("subject", ""))

    # config may be a JSON string or a path to a JSON file
    try:
        cfg = json.loads(args.config_json)
    except (json.JSONDecodeError, ValueError):
        cfg = json.loads(Path(args.config_json).read_text())

    # cohort-relative outlier flags
    for metric in ("cerebellum_voxels", "foliation_fraction"):
        present = [s for s in subs if isinstance(s.get(metric), (int, float))]
        if len(present) >= 5:
            mask, med, scale = mad_outliers([s[metric] for s in present], args.mad_k)
            for s, is_out in zip(present, mask):
                if is_out:
                    s.setdefault("flags", []).append(f"cohort_outlier_{metric}")
    # recompute status after cohort flags
    for s in subs:
        s["status"] = "pass" if not s.get("flags") else "flag"

    # cross-subject shape consistency
    shapes = {tuple(s["shape"]) for s in subs if s.get("shape")}
    shape_consistent = len(shapes) <= 1

    n_pass = sum(s["status"] == "pass" for s in subs)
    flagged = [s["subject"] for s in subs if s["status"] == "flag"]

    def summ(metric):
        vals = [s[metric] for s in subs if isinstance(s.get(metric), (int, float))]
        if not vals:
            return None
        a = np.asarray(vals, float)
        return {"min": float(a.min()), "median": float(np.median(a)),
                "max": float(a.max()), "mad": float(np.median(np.abs(a - np.median(a))))}

    manifest = {
        "dataset": {"name": args.dataset_name, "version": args.dataset_version},
        "provenance": {
            "processed_utc": dt.datetime.utcnow().isoformat(timespec="seconds") + "Z",
            "pipeline_git_commit": _run(["git", "-C", args.pipeline_dir, "rev-parse", "HEAD"]),
            "pipeline_git_dirty": bool(_run(["git", "-C", args.pipeline_dir, "status", "--porcelain"])),
            "snakemake_version": _run(["snakemake", "--version"]),
        },
        "working_point": {
            "sigmas": cfg.get("sigmas"), "alpha": cfg.get("alpha"), "beta": cfg.get("beta"),
            "gamma_power": cfg.get("gamma_power"), "target_wm_value": cfg.get("target_wm_value"),
            "window_size_mm": cfg.get("window_size"),
            "p_low": cfg.get("min_percentile"), "p_high": cfg.get("max_percentile"),
            "segmentation_method": cfg.get("segmentation_params", {}).get("method"),
            "dilatation_cerebellum": cfg.get("dilatation_cerebellum_atlas_mask"),
            "dilatation_substructure": cfg.get("dilatation_substructure"),
            "prebaked_tiles": cfg.get("prebaked_tiles", []),
            "space": "MNI152-ICBM2009c 0.5mm iso, rigid registration",
            "eigenvalue_sort": "raw value, signs preserved",
            "vermis_definition": "atlas-ROI intersect whole-cerebellum-Acapulco, masked (DL input); "
                                 "lobule labels bundled for stats only",
        },
        "composition": {
            "n_requested": len(subs), "n_pass": n_pass, "n_flagged": len(flagged),
            "tile_shape": list(next(iter(shapes))) if shape_consistent and shapes else None,
            "tile_shape_consistent": shape_consistent,
            "flagged_subjects": flagged,
        },
        "qc_summary": {
            "cerebellum_voxels": summ("cerebellum_voxels"),
            "foliation_fraction": summ("foliation_fraction"),
            "mad_k": args.mad_k,
        },
        "caveats": [
            "No bias-field correction in the pipeline; inputs keep their own bias state.",
            "Acapulco lobule labels are error-prone -> stats only, not input masking.",
            "Sheetness magnitude is not invariant to field strength or site; compare cohorts with care.",
        ],
        "subjects": subs,
    }

    Path(args.out_manifest).write_text(json.dumps(manifest, indent=2))

    cols = ["subject", "status", "cerebellum_voxels", "foliation_voxels",
            "foliation_fraction", "flags"]
    with open(args.out_csv, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(cols)
        for s in subs:
            w.writerow([s.get("subject"), s.get("status"), s.get("cerebellum_voxels"),
                        s.get("foliation_voxels"), s.get("foliation_fraction"),
                        ";".join(s.get("flags", []))])

    print(f"manifest: {len(subs)} subjects, {n_pass} pass, {len(flagged)} flagged, "
          f"shape_consistent={shape_consistent} -> {args.out_manifest}")


if __name__ == "__main__":
    main()
