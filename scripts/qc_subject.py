################################################
# Per-subject validity QC. Writes one {subject}_qc.json.
#
# Absolute sanity checks (flag here):
#   - header split (sform vs qform) on the raw input (a split header misplaces the MNI registration)
#   - foliation binary empty / NaN-inf in the z-score field
#   - tile shape recorded (cross-subject consistency checked at gather time)
#   - npz loads and has the expected keys
# Raw metrics (cerebellum volume, foliation fraction) are recorded; cohort-relative
# outlier flagging is done at gather time (median +/- k*MAD), which is more robust than
# hardcoded bands.
#
# Header check: pure-stdlib NIfTI-1 parser (gzip + struct) so it needs neither aims
# (which hides sform/qform) nor nibabel. Volume stats: soma.aims.
################################################

import argparse
import gzip
import json
import struct

import numpy as np
from soma import aims


def read_nifti_forms(path):
    """Return (sform_code, qform_code, sform_origin, qform_origin) from a NIfTI-1 header.

    Only the fields needed for the split-header check; pure stdlib. Handles .nii / .nii.gz
    and both byte orders. qform origin = qoffset_{x,y,z}; sform origin = srow_*[3].
    """
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rb") as f:
        hdr = f.read(352)
    if len(hdr) < 348:
        raise ValueError(f"{path}: truncated NIfTI header")
    # endianness from sizeof_hdr (must be 348)
    endian = "<"
    if struct.unpack("<i", hdr[0:4])[0] != 348:
        endian = ">"
        if struct.unpack(">i", hdr[0:4])[0] != 348:
            raise ValueError(f"{path}: not a NIfTI-1 header (bad sizeof_hdr)")
    qform_code = struct.unpack(endian + "h", hdr[252:254])[0]
    sform_code = struct.unpack(endian + "h", hdr[254:256])[0]
    qoffset = struct.unpack(endian + "3f", hdr[268:280])
    srow_x = struct.unpack(endian + "4f", hdr[280:296])
    srow_y = struct.unpack(endian + "4f", hdr[296:312])
    srow_z = struct.unpack(endian + "4f", hdr[312:328])
    sform_origin = (srow_x[3], srow_y[3], srow_z[3])
    return sform_code, qform_code, list(sform_origin), list(qoffset)


def load_mask(path):
    arr = np.asarray(aims.read(path).np)
    if arr.ndim == 4 and arr.shape[-1] == 1:
        arr = arr[..., 0]
    return arr


def main():
    ap = argparse.ArgumentParser(description="Per-subject validity QC -> {subject}_qc.json")
    ap.add_argument("--subject", required=True)
    ap.add_argument("--raw", required=True, help="raw ingestion NIfTI (for the header split check)")
    ap.add_argument("--cerebellum-mask", required=True, help="binary_acapulco_cropped (NIfTI)")
    ap.add_argument("--binary", required=True, help="whole-cerebellum foliation binary (NIfTI)")
    ap.add_argument("--zscore", required=True, help="whole-cerebellum z-score (NIfTI)")
    ap.add_argument("--npz", required=True, help="the subject .npz to integrity-check")
    ap.add_argument("--header-split-mm", type=float, default=5.0,
                    help="flag if |sform origin - qform origin| exceeds this (mm)")
    ap.add_argument("--expected-keys", default="zscore,binary,labels,affine,meta")
    ap.add_argument("-o", "--output", required=True)
    args = ap.parse_args()

    qc = {"subject": args.subject, "flags": []}

    # --- header split (sform / qform disagree: misplaced registration) ---
    try:
        sc, qc_code, so, qo = read_nifti_forms(args.raw)
        delta = float(np.max(np.abs(np.array(so) - np.array(qo)))) if qc_code > 0 and sc > 0 else 0.0
        qc["header"] = {"sform_code": sc, "qform_code": qc_code,
                        "sform_origin": so, "qform_origin": qo, "origin_delta_mm": delta}
        if sc > 0 and qc_code > 0 and delta > args.header_split_mm:
            qc["flags"].append(f"header_split_{delta:.1f}mm")
    except Exception as e:
        qc["header"] = {"error": str(e)}
        qc["flags"].append("header_unreadable")

    # --- volumes ---
    cmask = load_mask(args.cerebellum_mask) > 0
    binv = load_mask(args.binary) > 0
    ncereb = int(cmask.sum())
    nfol = int((binv & cmask).sum()) if binv.shape == cmask.shape else int(binv.sum())
    qc["cerebellum_voxels"] = ncereb
    qc["foliation_voxels"] = nfol
    qc["foliation_fraction"] = (nfol / ncereb) if ncereb else 0.0
    if ncereb == 0:
        qc["flags"].append("empty_cerebellum_mask")
    if nfol == 0:
        qc["flags"].append("empty_foliation")

    # --- z-score sanity ---
    z = np.asarray(aims.read(args.zscore).np, dtype=np.float64)
    if z.ndim == 4 and z.shape[-1] == 1:
        z = z[..., 0]
    zin = z[cmask] if z.shape == cmask.shape else z.ravel()
    n_nan = int(np.isnan(z).sum())
    n_inf = int(np.isinf(z).sum())
    qc["zscore"] = {"n_nan": n_nan, "n_inf": n_inf,
                    "min": float(np.nanmin(zin)) if zin.size else None,
                    "max": float(np.nanmax(zin)) if zin.size else None,
                    "mean": float(np.nanmean(zin)) if zin.size else None}
    if n_nan or n_inf:
        qc["flags"].append(f"zscore_nonfinite_{n_nan+n_inf}")

    # --- shape + npz integrity ---
    qc["shape"] = list(cmask.shape)
    try:
        d = np.load(args.npz)
        missing = [k for k in args.expected_keys.split(",") if k not in d.files]
        qc["npz_keys"] = sorted(d.files)
        if missing:
            qc["flags"].append("npz_missing_keys:" + ",".join(missing))
    except Exception as e:
        qc["npz_keys"] = None
        qc["flags"].append("npz_unreadable")

    qc["status"] = "pass" if not qc["flags"] else "flag"

    with open(args.output, "w") as f:
        json.dump(qc, f, indent=2)
    print(f"[{args.subject}] {qc['status']} "
          f"(cereb={qc['cerebellum_voxels']}, fol_frac={qc['foliation_fraction']:.3f}, flags={qc['flags']})")


if __name__ == "__main__":
    main()
