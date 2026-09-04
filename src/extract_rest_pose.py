"""Extract complete first-frame pose transforms from reference solo GLBs.
Writes rest_pose.py with named translation and rotation dictionaries."""
import gzip
import json
import os
import struct

ANIM_DIR = r"G:\Starfield\Data\SAF\Animations"
OUT_PATH = r"G:\Starfield\src\OSFAutonomous\rest_pose.py"
POSE_FILES = {
    "standself01": "standself01.glb",
    "standself02": "standself02.glb",
    "standself03": "standself03.glb",
    "cover01": "StandCover01.glb",
    "surrender01": "StandSurrender01.glb",
}


def read_pose(path):
    with open(path, "rb") as f:
        raw = f.read()
    data = gzip.decompress(raw) if raw[:2] == b"\x1f\x8b" else raw

    chunk0_len, _ = struct.unpack_from("<I4s", data, 12)
    json_bytes = data[20:20 + chunk0_len]
    gltf = json.loads(json_bytes.rstrip(b"\x00").rstrip().decode("utf-8"))

    chunk1_off = 20 + chunk0_len
    chunk1_len, _ = struct.unpack_from("<I4s", data, chunk1_off)
    bin_data = data[chunk1_off + 8:chunk1_off + 8 + chunk1_len]
    nodes = [node.get("name", "") for node in gltf["nodes"]]
    anim = gltf["animations"][0]

    def read_accessor(acc_idx):
        acc = gltf["accessors"][acc_idx]
        view = gltf["bufferViews"][acc["bufferView"]]
        offset = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        comps = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
        stride = view.get("byteStride", 4 * comps)
        return [
            struct.unpack(f"<{comps}f", bin_data[offset + i * stride:offset + i * stride + 4 * comps])
            for i in range(acc["count"])
        ]

    translations = {}
    rotations = {}
    for channel in anim["channels"]:
        node_idx = channel["target"]["node"]
        path_name = channel["target"]["path"]
        sampler = anim["samplers"][channel["sampler"]]
        first_value = list(read_accessor(sampler["output"])[0])
        bone_name = nodes[node_idx]
        if path_name == "translation":
            translations[bone_name] = first_value
        elif path_name == "rotation":
            rotations[bone_name] = first_value
    return translations, rotations


pose_translations = {}
pose_rotations = {}
for pose_name, filename in POSE_FILES.items():
    trans, rot = read_pose(os.path.join(ANIM_DIR, filename))
    pose_translations[pose_name] = trans
    pose_rotations[pose_name] = rot
    print(f"{pose_name}: {len(trans)} translations, {len(rot)} rotations")

with open(OUT_PATH, "w", encoding="utf-8") as f:
    f.write("# Complete first-frame transforms extracted from reference solo GLBs.\n")
    f.write("REST_POSES_TRANS = ")
    f.write(json.dumps(pose_translations, indent=2, ensure_ascii=False))
    f.write("\n\nREST_POSES_ROT = ")
    f.write(json.dumps(pose_rotations, indent=2, ensure_ascii=False))
    f.write("\n\nREST_POSE_TRANS = REST_POSES_TRANS[\"standself01\"]\n")
    f.write("REST_POSE_ROT = REST_POSES_ROT[\"standself01\"]\n")

print(f"Wrote {len(POSE_FILES)} complete poses to {OUT_PATH}")
