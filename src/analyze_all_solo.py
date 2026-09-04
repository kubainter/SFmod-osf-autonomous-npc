#!/usr/bin/env python3
"""Analyze all solo reference clips including standsensor (sensual)."""
import analyze_kinematics as ak
import json, os

files = [
    'standself01.glb', 'standself02.glb', 'standself03.glb',
    'standsensor01.glb', 'standsensor02.glb', 'standsensor03.glb',
]
results = {}
for fname in files:
    stem = os.path.splitext(fname)[0]
    path = os.path.join(ak.ANIM_DIR, fname)
    try:
        res = ak.analyze_file(path)
        results[stem] = res
        active = res['active_bones']
        dur = res['duration']
        fps = res['fps']
        print(f"=== {fname} === duration={dur}s fps={fps}  active_bones={len(active)}")
        for b in active[:25]:
            name = b['name']
            delta = b['rot_delta_deg']
            freq = b['freq_hz']
            axis = b['dominant_axis']
            print(f"  {name:<28} delta={delta:7.2f}deg  freq={freq:.3f}Hz  axis={axis}")
        td = res.get('translation_deltas', {})
        if td:
            print("  Translations:")
            for k, v in td.items():
                print(f"    {k:<16} X={v['x']:.4f} Y={v['y']:.4f} Z={v['z']:.4f}")
        print()
    except Exception as e:
        print(f"ERROR {fname}: {e}")
        results[stem] = {"error": str(e)}

with open("kinematic_profiles_all.json", "w") as f:
    json.dump(results, f, indent=2)
print("Wrote kinematic_profiles_all.json")
