import gzip, struct, json, os, math, sys

def read_glb(path):
    with open(path, 'rb') as f:
        raw = f.read()
    if raw[:2] == b'\x1f\x8b':
        data = gzip.decompress(raw)
    else:
        data = raw
    chunk0_len, _ = struct.unpack_from('<I4s', data, 12)
    json_bytes = data[20:20+chunk0_len]
    gltf = json.loads(json_bytes.rstrip(b'\x00').rstrip().decode('utf-8'))
    # Get BIN chunk
    chunk1_off = 20 + chunk0_len
    chunk1_len, _ = struct.unpack_from('<I4s', data, chunk1_off)
    bin_data = data[chunk1_off+8:chunk1_off+8+chunk1_len]
    return gltf, bin_data

def read_accessor(acc, bin_data, gltf):
    view = gltf['bufferViews'][acc['bufferView']]
    offset = view.get('byteOffset', 0) + acc.get('byteOffset', 0)
    count = acc['count']
    ct = acc['componentType']
    dtype_size = {5126: 4}[ct]
    atype = acc['type']
    comps = {'SCALAR':1, 'VEC2':2, 'VEC3':3, 'VEC4':4}[atype]
    stride = view.get('byteStride', dtype_size * comps)
    vals = []
    for i in range(count):
        start = offset + i * stride
        raw = bin_data[start:start + dtype_size * comps]
        vals.append(struct.unpack(f'<{comps}f', raw))
    return vals

orig_path = sys.argv[1] if len(sys.argv) > 1 else r'G:\Starfield\Data\SAF\Animations\standself01.glb'
ours_path = sys.argv[2] if len(sys.argv) > 2 else r'G:\Starfield\Data\OSF\Autonomous\Animations\solo_standing_touch.glb'
orig_gltf, orig_bin = read_glb(orig_path)
ours_gltf, ours_bin = read_glb(ours_path)

orig_nodes = [n.get('name','') for n in orig_gltf['nodes']]
ours_nodes = [n.get('name','') for n in ours_gltf['nodes']]

# Get animation channels
orig_anim = orig_gltf['animations'][0]
ours_anim = ours_gltf['animations'][0]

def get_channel_data(gltf, anim, bin_data, node_names, bone_name, path):
    """Get keyframe values for a specific bone and path (rotation/translation)."""
    node_idx = node_names.index(bone_name) if bone_name in node_names else -1
    if node_idx < 0:
        return None
    for ch in anim['channels']:
        if ch['target']['node'] == node_idx and ch['target']['path'] == path:
            sampler = anim['samplers'][ch['sampler']]
            times = read_accessor(gltf['accessors'][sampler['input']], bin_data, gltf)
            vals = read_accessor(gltf['accessors'][sampler['output']], bin_data, gltf)
            return times, vals
    return None

# Compare key bones
bones_to_check = ['COM', 'C_Hips', 'C_Chest', 'C_Neck', 'C_Neck1', 'C_Head', 'L_Clavicle', 'L_Biceps', 'L_Forearm', 'L_Wrist', 'R_Wrist', 'R_Biceps', 'R_Index', 'R_Index1', 'R_Middle', 'R_Ring', 'R_Pinky', 'L_Thigh']
print("=== COMPARING KEY BONE VALUES (first 3 keyframes) ===\n")

for bone in bones_to_check:
    print(f"--- {bone} ---")
    for path in ['translation', 'rotation']:
        orig_data = get_channel_data(orig_gltf, orig_anim, orig_bin, orig_nodes, bone, path)
        ours_data = get_channel_data(ours_gltf, ours_anim, ours_bin, ours_nodes, bone, path)

        if orig_data is None and ours_data is None:
            print(f"  {path}: neither has data")
            continue

        print(f"  {path}:")
        if orig_data:
            times, vals = orig_data
            print(f"    ORIG: {len(vals)} keyframes, t0={times[0]}, tN={times[-1]}")
            print(f"    ORIG first 3: {vals[:3]}")
            if len(vals) > 2:
                first = vals[0]
                all_same = all(v == first for v in vals)
                print(f"    ORIG static: {all_same}")
        else:
            print(f"    ORIG: NO CHANNEL")

        if ours_data:
            times, vals = ours_data
            print(f"    OURS: {len(vals)} keyframes, t0={times[0]}, tN={times[-1]}")
            print(f"    OURS first 3: {vals[:3]}")
            if len(vals) > 2:
                first = vals[0]
                all_same = all(v == first for v in vals)
                print(f"    OURS static: {all_same}")
            if path == 'rotation' and orig_data:
                orig_first = orig_data[1][0]
                dot = min(1.0, abs(sum(orig_first[i] * vals[0][i] for i in range(4))))
                offset_angle = 2.0 * math.degrees(math.acos(dot))
                seam_dot = min(1.0, abs(sum(vals[0][i] * vals[-1][i] for i in range(4))))
                seam_angle = 2.0 * math.degrees(math.acos(seam_dot))
                frame_delta = max(
                    2.0 * math.degrees(math.acos(min(1.0, abs(sum(a[i] * b[i] for i in range(4))))))
                    for a, b in zip(orig_data[1], vals)
                )
                print(f"    First-frame offset: {offset_angle:.3f} deg; loop seam: {seam_angle:.3f} deg; max change: {frame_delta:.3f} deg")
        else:
            print(f"    OURS: NO CHANNEL")
    print()

# Also check total number of keyframes per channel
print("=== KEYFRAME COUNTS ===")
print(f"ORIG channels: {len(orig_anim['channels'])}")
print(f"OURS channels: {len(ours_anim['channels'])}")

# Check a few channels for keyframe count
for ch_idx in [0, 1, 2, 18, 19]:  # First few + COM area
    if ch_idx < len(orig_anim['channels']):
        ch = orig_anim['channels'][ch_idx]
        sampler = orig_anim['samplers'][ch['sampler']]
        orig_count = orig_gltf['accessors'][sampler['input']]['count']
        node_name = orig_nodes[ch['target']['node']]
        path = ch['target']['path']

        ch_o = ours_anim['channels'][ch_idx]
        sampler_o = ours_anim['samplers'][ch_o['sampler']]
        ours_count = ours_gltf['accessors'][sampler_o['input']]['count']

        print(f"  [{ch_idx}] {node_name}.{path}: orig={orig_count} kf, ours={ours_count} kf")
