#!/usr/bin/env python3
"""Reproduce the 240-sample MATLAB/Q8.8 numerical analysis from MLP_reference.mat.

This is a software reference calculation, not an RTL simulation. It deliberately
models the archived product-wise arithmetic right shift and accumulation order.
Requires Python 3.10+, NumPy, SciPy; Matplotlib is optional for figures.
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import json
import math
import sys
from pathlib import Path
from typing import Any

import numpy as np
from scipy.io import loadmat

HERE = Path(__file__).resolve().parent
DATA_ROOT = HERE.parent
MODEL_PATH = DATA_ROOT / "model-and-scripts" / "MLP_reference.mat"
EXISTING_CSV = HERE / "test_240_predictions.csv"
SCALE = 256
ACC20_MIN, ACC20_MAX = -(1 << 19), (1 << 19) - 1
INT16_MIN, INT16_MAX = -(1 << 15), (1 << 15) - 1


def matlab_round(values: np.ndarray) -> np.ndarray:
    """MATLAB round semantics: nearest integer, ties away from zero."""
    values = np.asarray(values, dtype=np.float64)
    return (np.sign(values) * np.floor(np.abs(values) + 0.5)).astype(np.int64)


def metrics(reference: np.ndarray, prediction: np.ndarray) -> dict[str, float]:
    err = np.asarray(prediction, dtype=np.float64) - np.asarray(reference, dtype=np.float64)
    return {
        "mae": float(np.mean(np.abs(err))),
        "rmse": float(np.sqrt(np.mean(err * err))),
        "max_abs_error": float(np.max(np.abs(err))),
        "mean_error_signed": float(np.mean(err)),
    }


def require_scalar_mat(mat: dict[str, Any], key: str) -> int:
    if key not in mat:
        raise ValueError(f"Required MATLAB variable {key!r} is absent from {MODEL_PATH}")
    return int(np.asarray(mat[key]).reshape(-1)[0])


def compute() -> tuple[list[dict[str, Any]], dict[str, Any]]:
    if not MODEL_PATH.is_file():
        raise FileNotFoundError(f"Cannot find MATLAB reference model: {MODEL_PATH}")
    mat = loadmat(MODEL_PATH)
    required = ("W1", "b1", "W2", "b2", "W1_q", "b1_q", "W2_q", "b2_q", "X_test", "Y_test")
    missing = [name for name in required if name not in mat]
    if missing:
        raise ValueError(f"MAT file is missing required variables: {', '.join(missing)}")

    W1 = np.asarray(mat["W1"], dtype=np.float64)
    b1 = np.asarray(mat["b1"], dtype=np.float64).reshape(-1)
    W2 = np.asarray(mat["W2"], dtype=np.float64).reshape(-1)
    b2 = float(np.asarray(mat["b2"], dtype=np.float64).reshape(-1)[0])
    W1q = np.asarray(mat["W1_q"], dtype=np.int64)
    b1q = np.asarray(mat["b1_q"], dtype=np.int64).reshape(-1)
    W2q = np.asarray(mat["W2_q"], dtype=np.int64).reshape(-1)
    b2q = require_scalar_mat(mat, "b2_q")
    X = np.asarray(mat["X_test"], dtype=np.float64)
    Y = np.asarray(mat["Y_test"], dtype=np.float64).reshape(-1)

    if W1.shape != (8, 4) or W1q.shape != (8, 4) or W2.shape != (8,) or W2q.shape != (8,):
        raise ValueError(f"Unexpected network dimensions: W1={W1.shape}, W1_q={W1q.shape}, W2={W2.shape}, W2_q={W2q.shape}")
    if X.shape != (4, 240) or Y.shape != (240,):
        raise ValueError(f"Expected X_test 4x240 and Y_test 240 values; got {X.shape} and {Y.shape}")
    if b1.shape != (8,) or b1q.shape != (8,):
        raise ValueError(f"Expected 8 hidden biases; got {b1.shape} and {b1q.shape}")

    # Floating-point reference inference: W2 * ReLU(W1*X + b1) + b2.
    floating_pred = W2 @ np.maximum(0.0, W1 @ X + b1[:, None]) + b2

    # Quantize inputs using MATLAB's round(x*256), then emulate per-product
    # arithmetic shift before accumulation. Python's signed right shift has
    # the same floor behavior as a two's-complement arithmetic right shift.
    Xq = matlab_round(X * SCALE)
    q_raw = np.zeros(X.shape[1], dtype=np.int64)
    all_hidden_acc = np.zeros((X.shape[1], 8), dtype=np.int64)
    all_hidden_relu = np.zeros((X.shape[1], 8), dtype=np.int64)
    accum_max_abs = 0
    relu_max = 0
    signed20_overflow_count = 0
    signed16_overflow_count = 0

    for sample in range(X.shape[1]):
        hidden_acc = np.empty(8, dtype=np.int64)
        for neuron in range(8):
            acc = int(b1q[neuron])
            for inp in range(4):
                product = int(Xq[inp, sample]) * int(W1q[neuron, inp])
                acc += product >> 8
            hidden_acc[neuron] = acc
        all_hidden_acc[sample] = hidden_acc
        accum_max_abs = max(accum_max_abs, int(np.max(np.abs(hidden_acc))))
        signed20_overflow_count += int(np.count_nonzero((hidden_acc < ACC20_MIN) | (hidden_acc > ACC20_MAX)))
        hidden_relu = np.maximum(hidden_acc, 0)
        signed16_overflow_count += int(np.count_nonzero((hidden_relu < INT16_MIN) | (hidden_relu > INT16_MAX)))
        # The existing MATLAB flow transfers layer activations through int16.
        # No value overflows for the checked 240-sample test set.
        hidden_relu16 = np.clip(hidden_relu, INT16_MIN, INT16_MAX).astype(np.int64)
        all_hidden_relu[sample] = hidden_relu16
        relu_max = max(relu_max, int(np.max(hidden_relu16)))
        out_acc = int(b2q)
        for neuron in range(8):
            out_acc += (int(hidden_relu16[neuron]) * int(W2q[neuron])) >> 8
        q_raw[sample] = out_acc

    fixed_pred = q_raw.astype(np.float64) / SCALE
    err_fixed_float = fixed_pred - floating_pred
    err_float_target = floating_pred - Y
    err_fixed_target = fixed_pred - Y

    rows: list[dict[str, Any]] = []
    for i in range(X.shape[1]):
        rows.append({
            "sample_id": i + 1,
            "x1_float": X[0, i], "x2_float": X[1, i],
            "x3_float": X[2, i], "x4_float": X[3, i],
            "target_float": Y[i],
            "matlab_floating_pred_recomputed": floating_pred[i],
            "q8_8_raw_pred": int(q_raw[i]),
            "q8_8_real_pred": fixed_pred[i],
            "fixed_minus_float": err_fixed_float[i],
            "float_minus_target": err_float_target[i],
            "fixed_minus_target": err_fixed_target[i],
        })

    metrics_json: dict[str, Any] = {
        "analysis_type": "software_recomputation_from_saved_MAT_model",
        "source_model": MODEL_PATH.relative_to(DATA_ROOT).as_posix(),
        "source_model_sha256": hashlib.sha256(MODEL_PATH.read_bytes()).hexdigest(),
        "dataset": {
            "sample_count": int(X.shape[1]),
            "network": "4-8-1 fully connected MLP",
            "input_data_origin": "synthetic nonlinear target function generated by the archived MATLAB script",
            "is_rtl_simulation": False,
        },
        "arithmetic": {
            "format": "signed Q8.8",
            "scale": SCALE,
            "input_quantization": "MATLAB round(x * 256), ties away from zero",
            "multiply_rescale": "arithmetic right shift by 8 per product before accumulation",
            "hidden_activation": "ReLU followed by signed-16 transfer to output layer",
            "accumulator_width_bits": 20,
            "overflow_check_scope": "intermediate hidden accumulators and ReLU outputs in this software recomputation",
        },
        "metrics": {
            "q8_8_vs_floating_same_model": metrics(floating_pred, fixed_pred),
            "floating_model_vs_target": metrics(Y, floating_pred),
            "q8_8_vs_target": metrics(Y, fixed_pred),
        },
        "range_checks": {
            "max_abs_hidden_accumulator_integer": accum_max_abs,
            "max_hidden_relu_integer": relu_max,
            "signed_20bit_hidden_accumulator_overflow_values": signed20_overflow_count,
            "signed_16bit_hidden_activation_overflow_values": signed16_overflow_count,
            "sample_1_hidden_accumulators_integer": all_hidden_acc[0].tolist(),
            "sample_1_hidden_relu_integer": all_hidden_relu[0].tolist(),
            "sample_1_output_integer": int(q_raw[0]),
        },
        "historical_cycle_claims": {
            "cached_done_interval_cycles": 31,
            "reload_done_interval_cycles": 35,
            "raw_throughput_testbench_and_transcript_in_this_repository": False,
            "note": "Recorded in a supplementary report but cannot be independently recreated from the present files; do not treat them as a fresh simulation result.",
        },
    }
    return rows, metrics_json


def compare_existing(rows: list[dict[str, Any]]) -> dict[str, Any]:
    if not EXISTING_CSV.is_file():
        return {"exists": False, "rows": 0, "all_fields_match": False}
    with EXISTING_CSV.open("r", encoding="utf-8-sig", newline="") as f:
        old = list(csv.DictReader(f))
    numeric_fields = [k for k in rows[0] if k != "sample_id"]
    if len(old) != len(rows):
        return {"exists": True, "rows": len(old), "expected_rows": len(rows), "all_fields_match": False}
    max_diff = {k: 0.0 for k in numeric_fields}
    mismatch_count = 0
    for a, b in zip(rows, old):
        try:
            if int(b["sample_id"]) != int(a["sample_id"]):
                mismatch_count += 1
            for key in numeric_fields:
                d = abs(float(b[key]) - float(a[key]))
                max_diff[key] = max(max_diff[key], d)
                # The stored CSV was generated from these exact values. Use a
                # tight tolerance to remain robust to decimal formatting only.
                if not math.isclose(float(b[key]), float(a[key]), rel_tol=1e-13, abs_tol=1e-14):
                    mismatch_count += 1
        except (KeyError, TypeError, ValueError):
            mismatch_count += 1
            break
    return {
        "exists": True,
        "rows": len(old),
        "expected_rows": len(rows),
        "all_fields_match": mismatch_count == 0,
        "mismatch_count": mismatch_count,
        "maximum_absolute_difference_by_field": max_diff,
    }


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()), lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({k: (format(v, ".17g") if isinstance(v, (float, np.floating)) else v) for k, v in row.items()})


def make_figures(rows: list[dict[str, Any]], fig_dir: Path) -> bool:
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        print("Matplotlib not installed; numerical outputs were created, figures were skipped.")
        return False
    fig_dir.mkdir(parents=True, exist_ok=True)
    ids = np.array([r["sample_id"] for r in rows])
    target = np.array([r["target_float"] for r in rows], dtype=float)
    floating = np.array([r["matlab_floating_pred_recomputed"] for r in rows], dtype=float)
    fixed = np.array([r["q8_8_real_pred"] for r in rows], dtype=float)
    ef = fixed - floating
    em = floating - target
    eq = fixed - target

    fig, ax = plt.subplots(figsize=(10, 5.4), constrained_layout=True)
    ax.plot(ids, target, linewidth=1.1, label="Target")
    ax.plot(ids, floating, linewidth=1.0, label="Floating-point model")
    ax.plot(ids, fixed, linewidth=0.9, label="Q8.8 software model")
    ax.set(title="Reference MLP: target and model predictions", xlabel="Test sample", ylabel="Output value")
    ax.grid(True, alpha=.25); ax.legend(ncols=3, fontsize=9)
    fig.savefig(fig_dir / "predictions_vs_target.png", dpi=160); plt.close(fig)

    fig, ax = plt.subplots(figsize=(10, 4.8), constrained_layout=True)
    ax.plot(ids, ef, linewidth=0.9)
    ax.axhline(0, linewidth=.8)
    ax.set(title="Q8.8 quantization error (fixed-point minus floating-point)", xlabel="Test sample", ylabel="Output error")
    ax.grid(True, alpha=.25)
    fig.savefig(fig_dir / "fixed_point_quantization_error.png", dpi=160); plt.close(fig)

    fig, ax = plt.subplots(figsize=(10, 4.8), constrained_layout=True)
    ax.plot(ids, em, linewidth=0.9, label="Floating prediction − target")
    ax.plot(ids, eq, linewidth=0.9, label="Q8.8 prediction − target")
    ax.axhline(0, linewidth=.8)
    ax.set(title="Model error versus target function", xlabel="Test sample", ylabel="Output error")
    ax.grid(True, alpha=.25); ax.legend(fontsize=9)
    fig.savefig(fig_dir / "error_comparison.png", dpi=160); plt.close(fig)

    # The 31/35-cycle figures are historical claims; throughput on this plot is
    # explicitly conditional math, not a board measurement or simulator result.
    periods = np.linspace(10.0, 20.0, 201)
    cached = 1e3 / (31.0 * periods)  # million inferences/s
    reload = 1e3 / (35.0 * periods)
    fig, ax = plt.subplots(figsize=(9.4, 5.2), constrained_layout=True)
    ax.plot(periods, cached, label="Cached input (31-cycle interval)")
    ax.plot(periods, reload, label="Reload input (35-cycle interval)")
    ax.axvline(15.104, linestyle="--", linewidth=1.0, label="Fanout reported period: 15.104 ns")
    ax.axvline(16.5, linestyle=":", linewidth=1.0, label="Architecture comparison constraint: 16.5 ns")
    ax.set(title="Conditional throughput from historical cycle intervals", xlabel="Assumed clock period (ns)", ylabel="Calculated throughput (million inferences/s)")
    ax.grid(True, alpha=.25); ax.legend(fontsize=8)
    ax.text(.01, -.24, "Calculated from reported intervals; throughput testbench/transcript is not present in this repository. Not a board measurement.", transform=ax.transAxes, fontsize=8, va="top")
    fig.savefig(fig_dir / "conditional_throughput.png", dpi=160, bbox_inches="tight"); plt.close(fig)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv-out", type=Path, default=HERE / "test_240_predictions_recomputed.csv", help="output CSV (default: sidecar file; preserves the original CSV)")
    parser.add_argument("--metrics-out", type=Path, default=HERE / "result_metrics.json", help="output JSON metrics file")
    parser.add_argument("--figures-dir", type=Path, default=HERE / "figures", help="directory for optional PNG plots")
    parser.add_argument("--no-figures", action="store_true", help="skip plots even if Matplotlib is installed")
    parser.add_argument("--strict-existing-match", action="store_true", help="fail if the original archived 240-row CSV does not match the recomputation")
    args = parser.parse_args()

    rows, report = compute()
    existing = compare_existing(rows)
    report["comparison_with_archived_csv"] = existing
    if existing.get("exists") and existing.get("all_fields_match"):
        report["comparison_with_archived_csv"]["status"] = "PASS: all 240 rows and numeric fields match"
    elif existing.get("exists"):
        report["comparison_with_archived_csv"]["status"] = "MISMATCH: inspect CSV and MAT source"
    else:
        report["comparison_with_archived_csv"]["status"] = "NOT FOUND"

    write_csv(args.csv_out, rows)
    args.metrics_out.parent.mkdir(parents=True, exist_ok=True)
    args.metrics_out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    figures_created = False if args.no_figures else make_figures(rows, args.figures_dir)

    print(f"MAT source: {MODEL_PATH}")
    print(f"Recomputed samples: {len(rows)}")
    print(f"Archived CSV comparison: {report['comparison_with_archived_csv']['status']}")
    for label, block in report["metrics"].items():
        print(f"{label}: MAE={block['mae']:.12f}; RMSE={block['rmse']:.12f}; max_abs_error={block['max_abs_error']:.12f}")
    print(f"CSV written: {args.csv_out}")
    print(f"Metrics written: {args.metrics_out}")
    print(f"Figures created: {figures_created}")
    print("SCOPE: software numerical recomputation only; no RTL/modelsim/Xilinx ISE/physical board run is performed.")
    if args.strict_existing_match and not existing.get("all_fields_match", False):
        print("ERROR: archived CSV did not match the current recomputation.", file=sys.stderr)
        return 1
    if report["range_checks"]["signed_20bit_hidden_accumulator_overflow_values"] or report["range_checks"]["signed_16bit_hidden_activation_overflow_values"]:
        print("ERROR: fixed-point range check detected overflow.", file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
