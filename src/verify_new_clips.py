#!/usr/bin/env python3
"""Verify kinematic profiles of newly generated solo clips."""
import analyze_kinematics as ak
import json, os

ANIM_DIR = r"G:\Starfield\Data\OSF\Autonomous\Animations"
files = ["solo_standing_touch.glb", "solo_sensual_caress.glb", "solo_sensual_touch.glb"]

for fname in files:
    path = os.path.join(ANIM_DIR, fname)
    try:
        res = ak.analyze_file(path)
        active = res["active_bones"]
        dur = res["duration"]
        print(f"=== {fname} === duration={dur}s  active_bones={len(active)}")
        for b in active[:30]:
            name = b["name"]
            delta = b["rot_delta_deg"]
            freq = b["freq_hz"]
            axis = b["dominant_axis"]
            print(f"  {name:<28} delta={delta:7.2f}deg  freq={freq:.3f}Hz  axis={axis}")
        td = res.get("translation_deltas", {})
        if td:
            print("  Translations:")
            for k, v in td.items():
                print(f"    {k:<16} X={v['x']:.4f} Y={v['y']:.4f} Z={v['z']:.4f}")
        print()
    except Exception as e:
        print(f"ERROR {fname}: {e}")
