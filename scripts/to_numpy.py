################################################
# Package a subject's cerebellar-tiles outputs into a single .npz for the DL dataloader.
#
# Canonical DL input = whole-cerebellum volumes on the shared atlas cerebellum-bbox grid:
#   - zscore : continuous local-z-score sheetness field
#   - binary : hysteresis foliation binary
#   - labels : Acapulco tmc parcellation (ids per tmc_labels.json) -> on-the-fly substructures / STATS
# Plus, optionally, pre-baked substructure tiles (e.g. vermis) already masked+cropped by the pipeline.
#
# All subjects share the atlas-derived bbox, so every array has the same shape across subjects
# (directly stackable into [N, D, H, W]).
#
# NIfTI I/O via soma.aims (same handler as every other pipeline script -> single TGCC env,
# no extra dependency). Arrays are read in aims .np order, matching the rest of the pipeline.
################################################

import argparse
import json

import numpy as np
from soma import aims


def load_array(path):
    """Read a volume with aims, return a 3D numpy array (drop a singleton time axis)."""
    vol = aims.read(path)
    arr = np.asarray(vol.np)
    if arr.ndim == 4 and arr.shape[-1] == 1:
        arr = arr[..., 0]
    return arr


def load_affine(path):
    """Best-effort voxel->world (mm) affine from the aims header.

    affine = M @ diag(voxel_size), where M is the aims-mm -> referential transform.
    Consistent with arrays read in aims .np order. VERIFY once per grid (see script docstring
    / the Run note): round-trip a tile back to NIfTI and overlay on the original. The kept
    NIfTI holds the authoritative geometry regardless, so a wrong affine here is non-fatal.
    """
    hdr = aims.read(path).header()
    vs = np.asarray(hdr["voxel_size"][:3], dtype=np.float64)
    S = np.diag([vs[0], vs[1], vs[2], 1.0])
    try:
        M = np.asarray(hdr["transformations"][0], dtype=np.float64).reshape(4, 4)
        return (M @ S).astype(np.float32)
    except (KeyError, IndexError, ValueError):
        return S.astype(np.float32)


def main():
    ap = argparse.ArgumentParser(
        description="Bundle a subject's whole-cerebellum tiles + label map (+ pre-baked substructures) into one .npz."
    )
    ap.add_argument("--zscore", required=True, help="whole-cerebellum local z-score sheetness (NIfTI)")
    ap.add_argument("--binary", required=True, help="whole-cerebellum foliation binary (NIfTI)")
    ap.add_argument("--labels", required=True, help="Acapulco tmc parcellation, cerebellum-bbox grid (NIfTI)")
    ap.add_argument("--subject", required=True)
    ap.add_argument("--dataset", default="unknown")
    ap.add_argument("--meta-json", default="{}",
                    help="JSON string of pipeline metadata (working point, version).")
    # Pre-baked substructure tiles: three parallel repeatable lists (name / zscore / binary).
    ap.add_argument("--prebaked-name", action="append", default=[])
    ap.add_argument("--prebaked-zscore", action="append", default=[])
    ap.add_argument("--prebaked-binary", action="append", default=[])
    ap.add_argument("-o", "--output", required=True, help="output .npz")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    z = load_array(args.zscore)
    b = load_array(args.binary)
    lab = load_array(args.labels)
    affine = load_affine(args.zscore)

    if not (z.shape == b.shape == lab.shape):
        raise SystemExit(
            f"grid mismatch: zscore {z.shape}, binary {b.shape}, labels {lab.shape} "
            "- all three must be on the shared cerebellum-bbox grid."
        )

    store = {
        "zscore": z.astype(np.float32),
        "binary": (b > 0).astype(np.uint8),
        "labels": lab.astype(np.int16),
        "affine": affine,
    }

    n = len(args.prebaked_name)
    if not (len(args.prebaked_zscore) == len(args.prebaked_binary) == n):
        raise SystemExit("--prebaked-name/-zscore/-binary must be given in equal numbers.")
    for name, zp, bp in zip(args.prebaked_name, args.prebaked_zscore, args.prebaked_binary):
        zt = load_array(zp)
        bt = load_array(bp)
        if zt.shape != bt.shape:
            raise SystemExit(f"pre-baked '{name}' shape mismatch: zscore {zt.shape} vs binary {bt.shape}")
        store[f"{name}_zscore"] = zt.astype(np.float32)
        store[f"{name}_binary"] = (bt > 0).astype(np.uint8)

    meta = json.loads(args.meta_json)
    meta.update({
        "subject": args.subject,
        "dataset": args.dataset,
        "shape": list(z.shape),
        "prebaked": args.prebaked_name,
        "keys": sorted(store.keys()),
    })
    store["meta"] = np.array(json.dumps(meta))

    if args.verbose:
        mb = sum(v.nbytes for v in store.values() if isinstance(v, np.ndarray) and v.dtype != object) / 1e6
        print(f"[{args.subject}] shape {z.shape}, {len(store)-1} arrays, {mb:.1f} MB uncompressed -> {args.output}")
        if args.prebaked_name:
            print(f"  pre-baked tiles: {', '.join(args.prebaked_name)}")

    np.savez_compressed(args.output, **store)


if __name__ == "__main__":
    main()
