#!/usr/bin/env python3
"""Analyze kinematic profiles of solo animation .glb files.

Each file is GZIP-compressed binary glTF 2.0. We decompress, parse the glTF
JSON + BIN chunks, and measure biomechanical motion characteristics:
  - which bones move (angular delta > threshold)
  - how far (degrees for rotation, cm for translation)
  - how fast (dominant cycle frequency)
  - axis of dominant motion

Results are printed to stdout and written as JSON to
G:\\Starfield\\src\\OSFAutonomous\\kinematic_profiles.json
"""

import gzip
import json
import math
import os
import struct
import sys
from collections import defaultdict

import numpy as np

ANIM_DIR = r"G:\Starfield\Data\SAF\Animations"
OUT_JSON = r"G:\Starfield\src\OSFAutonomous\kinematic_profiles.json"

FILES = [
    "standself01.glb",
    "standself02.glb",
    "standself03.glb",
    "StandCover01.glb",
    "StandSurrender01.glb",
]

# Bones whose translation we explicitly report (if present)
TRANSLATION_REPORT = ["COM", "C_Hips", "Root"]

# Angular-delta threshold (degrees) for "active" bone
ACTIVE_THRESHOLD_DEG = 2.0


# ---------------------------------------------------------------------------
# glTF parsing helpers
# ---------------------------------------------------------------------------
def read_glb(path):
    """Decompress a gzip-compressed binary glTF and return (gltf_json, bin_bytes)."""
    with gzip.open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"glTF":
        raise ValueError(f"{path}: not a binary glTF (magic={data[:4]!r})")
    version, length = struct.unpack_from("<II", data, 4)
    if version != 2:
        raise ValueError(f"{path}: unsupported glTF version {version}")
    offset = 12
    gltf_json = None
    bin_bytes = b""
    while offset < length:
        chunk_len, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk_data = data[offset:offset + chunk_len]
        offset += chunk_len
        if chunk_type == 0x4E4F534A:  # "JSON"
            gltf_json = json.loads(chunk_data.decode("utf-8").rstrip("\x00"))
        elif chunk_type == 0x004E4942:  # "BIN\0"
            bin_bytes = chunk_data
    if gltf_json is None:
        raise ValueError(f"{path}: no JSON chunk")
    return gltf_json, bin_bytes


def accessor_dtype(accessor):
    """Return numpy dtype string for an accessor."""
    ctypes = {
        5120: "int8",   # BYTE
        5121: "uint8",  # UNSIGNED_BYTE
        5122: "int16",  # SHORT
        5123: "uint16", # UNSIGNED_SHORT
        5125: "uint32", # UNSIGNED_INT
        5126: "float32",# FLOAT
    }
    return ctypes[accessor.get("componentType", 5126)]


def accessor_shape(accessor):
    """Return element shape as a tuple given accessor.type."""
    t = accessor.get("type", "SCALAR")
    return {
        "SCALAR": (1,),
        "VEC2": (2,),
        "VEC3": (3,),
        "VEC4": (4,),
        "MAT4": (4, 4),
    }[t]


def read_accessor(accessor, bin_bytes, gltf):
    """Read an accessor's data from the binary buffer as a numpy array."""
    dtype = accessor_dtype(accessor)
    shape = accessor_shape(accessor)
    count = accessor.get("count", 0)
    view_idx = accessor.get("bufferView")
    if view_idx is None:
        return np.zeros((count,) + shape, dtype=dtype)
    view = gltf["bufferViews"][view_idx]
    buffer_idx = view.get("buffer", 0)
    # We only have one buffer (the BIN chunk)
    base = view.get("byteOffset", 0)
    stride = view.get("byteStride", 0)
    item_bytes = np.dtype(dtype).itemsize * int(np.prod(shape))
    if stride == 0:
        stride = item_bytes
    offset = base + accessor.get("byteOffset", 0)
    arr = np.zeros((count,) + shape, dtype=dtype)
    for i in range(count):
        start = offset + i * stride
        arr[i] = np.frombuffer(bin_bytes[start:start + item_bytes], dtype=dtype).reshape(shape)
    return arr


# ---------------------------------------------------------------------------
# Kinematic analysis
# ---------------------------------------------------------------------------
def quat_angle_deg(q0, q1):
    """Angle in degrees between two quaternions: angle = 2*acos(|q0.q1|)."""
    dot = float(np.dot(q0, q1))
    # clamp
    dot = max(-1.0, min(1.0, abs(dot)))
    return math.degrees(2.0 * math.acos(dot))


def rotation_delta_deg(quats):
    """Max pairwise angular delta across all keyframes (degrees)."""
    n = len(quats)
    if n < 2:
        return 0.0
    # Efficient: compute angle from first to every other, and also track min/max
    # The dominant swing is well approximated by max angle from the mean pose.
    # We compute the full pairwise max but cap comparisons for speed.
    max_ang = 0.0
    # Compare against first and against argmax so far (greedy) + a coarse sweep
    # For correctness on small arrays do full pairwise; these are small (<200 kf)
    if n <= 256:
        for i in range(n):
            for j in range(i + 1, n):
                a = quat_angle_deg(quats[i], quats[j])
                if a > max_ang:
                    max_ang = a
        return max_ang
    # Large array: greedy approximation
    pivot = 0
    for _ in range(3):
        best = 0.0
        best_k = pivot
        for k in range(n):
            if k == pivot:
                continue
            a = quat_angle_deg(quats[pivot], quats[k])
            if a > best:
                best = a
                best_k = k
        if best > max_ang:
            max_ang = best
        pivot = best_k
    return max_ang


def dominant_axis_and_freq(values, times):
    """Given an (N, D) array of values over time, return (dominant_axis_label, freq_hz).

    For VEC4 quaternions we look at the per-component swing (excluding the scalar
    channel that varies least) — but a simpler robust measure: convert each
    keyframe's rotation relative to the first keyframe into an axis-angle and
    pick the axis component with the largest range. For VEC3 translation we pick
    the axis with the largest peak-to-peak range.

    Frequency is estimated from the dominant component's zero-crossings of the
    detrended signal.
    """
    arr = np.asarray(values, dtype=np.float64)
    t = np.asarray(times, dtype=np.float64)
    if len(arr) < 2 or len(t) < 2:
        return "X", 0.0
    duration = t[-1] - t[0]
    if duration <= 0:
        return "X", 0.0

    if arr.shape[1] == 4:
        # quaternions: compute relative rotations vs first frame, get axis-angle
        q0 = arr[0]
        # ensure consistent hemisphere
        dots = np.sum(arr * q0, axis=1)
        arr = np.where(dots[:, None] < 0, -arr, arr)
        # relative quaternion = q0^-1 * q  (q0 is unit)
        rel = np.zeros((len(arr), 3), dtype=np.float64)
        w0, x0, y0, z0 = q0
        for i in range(len(arr)):
            w, x, y, z = arr[i]
            # conjugate(q0) * q
            rw = w0 * w + x0 * x + y0 * y + z0 * z
            rx = w0 * x - x0 * w - y0 * z + z0 * y
            ry = w0 * y + x0 * z - y0 * w - z0 * x
            rz = w0 * z - x0 * y + y0 * x - z0 * w
            # angle
            ang = 2.0 * math.acos(max(-1.0, min(1.0, abs(rw))))
            s = math.sqrt(max(1e-12, 1.0 - rw * rw))
            if s < 1e-8:
                rx = ry = rz = 0.0
            else:
                rx, ry, rz = rx / s, ry / s, rz / s
            rel[i] = [ang * rx, ang * ry, ang * rz]  # axis * angle vector
        comp = rel[:, :3]
        labels = ["X", "Y", "Z"]
    else:
        comp = arr
        labels = ["X", "Y", "Z"] if arr.shape[1] >= 3 else ["X", "Y"][:arr.shape[1]]

    # dominant axis = largest peak-to-peak range
    ranges = np.ptp(comp, axis=0)
    dom_idx = int(np.argmax(ranges))
    dom_label = labels[dom_idx]
    signal = comp[:, dom_idx]

    # frequency via zero crossings of detrended (mean-removed) signal
    detrended = signal - np.mean(signal)
    crossings = 0
    for i in range(1, len(detrended)):
        if detrended[i - 1] == 0:
            continue
        if np.sign(detrended[i]) != np.sign(detrended[i - 1]):
            crossings += 1
    # each full cycle = 2 crossings
    freq = (crossings / 2.0) / duration if duration > 0 else 0.0
    return dom_label, round(freq, 3)


def analyze_file(path):
    gltf, bin_bytes = read_glb(path)
    nodes = gltf.get("nodes", [])
    accessors = gltf.get("accessors", [])
    animations = gltf.get("animations", [])

    node_names = [n.get("name", f"node_{i}") for i, n in enumerate(nodes)]

    if not animations:
        return None

    # We assume one animation per file (solo anim)
    anim = animations[0]
    channels = anim.get("channels", [])
    samplers = anim.get("samplers", [])

    # Gather per-node, per-path data
    rotation_results = []   # (node_name, rot_delta_deg, freq_hz, dom_axis)
    translation_results = {}  # node_name -> {x,y,z deltas}

    for ch in channels:
        sampler_idx = ch.get("sampler")
        target = ch.get("target", {})
        node_idx = target.get("node")
        path = target.get("path")
        if node_idx is None or sampler_idx is None:
            continue
        sampler = samplers[sampler_idx]
        input_acc_idx = sampler.get("input")
        output_acc_idx = sampler.get("output")
        if input_acc_idx is None or output_acc_idx is None:
            continue

        times = read_accessor(accessors[input_acc_idx], bin_bytes, gltf).reshape(-1)
        out_data = read_accessor(accessors[output_acc_idx], bin_bytes, gltf)

        node_name = node_names[node_idx] if node_idx < len(node_names) else f"node_{node_idx}"

        if path == "rotation" and out_data.shape[1] == 4:
            delta = rotation_delta_deg(out_data)
            dom_label, freq = dominant_axis_and_freq(out_data, times)
            rotation_results.append((node_name, round(delta, 4), freq, dom_label))
        elif path == "translation" and out_data.shape[1] == 3:
            deltas = np.ptp(out_data, axis=0)  # peak-to-peak per axis
            translation_results[node_name] = {
                "x": round(float(deltas[0]), 4),
                "y": round(float(deltas[1]), 4),
                "z": round(float(deltas[2]), 4),
            }

    # Duration / FPS
    # Use the max time across all input accessors
    max_time = 0.0
    min_dt = float("inf")
    for s in samplers:
        iacc = s.get("input")
        if iacc is None:
            continue
        t = read_accessor(accessors[iacc], bin_bytes, gltf).reshape(-1)
        if len(t):
            max_time = max(max_time, float(t[-1]))
            if len(t) > 1:
                dts = np.diff(t)
                if len(dts):
                    min_dt = min(min_dt, float(np.min(dts)))
    duration = round(max_time, 4)
    if min_dt != float("inf") and min_dt > 0:
        fps = round(1.0 / min_dt)
    else:
        fps = 0

    # Active bones
    active = [
        {
            "name": name,
            "rot_delta_deg": delta,
            "freq_hz": freq,
            "dominant_axis": axis,
        }
        for (name, delta, freq, axis) in rotation_results
        if delta > ACTIVE_THRESHOLD_DEG
    ]
    active.sort(key=lambda b: b["rot_delta_deg"], reverse=True)

    # Translation deltas: always include the report set (even if zero) plus any
    # node with a non-zero delta.
    trans_out = {}
    for key in TRANSLATION_REPORT:
        if key in translation_results:
            trans_out[key] = translation_results[key]
    for k, v in translation_results.items():
        if k not in trans_out and (v["x"] != 0 or v["y"] != 0 or v["z"] != 0):
            trans_out[k] = v

    return {
        "duration": duration,
        "fps": fps,
        "active_bones": active,
        "translation_deltas": trans_out,
    }


def main():
    results = {}
    for fname in FILES:
        stem = os.path.splitext(fname)[0]
        path = os.path.join(ANIM_DIR, fname)
        print(f"\n{'='*78}")
        print(f"ANALYZING: {fname}")
        print(f"{'='*78}")
        try:
            res = analyze_file(path)
        except Exception as e:
            print(f"  ERROR: {e}")
            results[stem] = {"error": str(e)}
            continue
        if res is None:
            print("  No animations found.")
            results[stem] = {"error": "no animations"}
            continue
        results[stem] = res

        active = res["active_bones"]
        print(f"Duration: {res['duration']} s   FPS: {res['fps']}")
        print(f"Total active bones (rot delta > {ACTIVE_THRESHOLD_DEG} deg): {len(active)}")
        print(f"\nTop 15 bones by angular delta:")
        print(f"  {'#':>2}  {'Bone':<32} {'DeltaDeg':>9} {'FreqHz':>8} {'Axis':>5}")
        print(f"  {'--':>2}  {'-'*32} {'-'*9} {'-'*8} {'-'*5}")
        for i, b in enumerate(active[:15], 1):
            print(f"  {i:>2}  {b['name']:<32} {b['rot_delta_deg']:>9.3f} {b['freq_hz']:>8.3f} {b['dominant_axis']:>5}")
        print(f"\nTranslation deltas (cm, peak-to-peak):")
        if res["translation_deltas"]:
            print(f"  {'Node':<16} {'X':>10} {'Y':>10} {'Z':>10}")
            for k, v in res["translation_deltas"].items():
                print(f"  {k:<16} {v['x']:>10.4f} {v['y']:>10.4f} {v['z']:>10.4f}")
        else:
            print("  (none)")

    # Write JSON
    os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)
    with open(OUT_JSON, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\n{'='*78}")
    print(f"Wrote JSON: {OUT_JSON}")
    print(f"{'='*78}")


if __name__ == "__main__":
    main()
