"""Check both Missionary01 clips to find which one is lying on back"""
import gzip, struct, json, os

def parse_glb(path):
    with gzip.open(path, 'rb') as gz:
        raw = gz.read()
    chunk0_len = struct.unpack_from('<I', raw, 12)[0]
    gltf = json.loads(raw[20:20+chunk0_len].decode('utf-8'))
    bin_offset = 20 + chunk0_len
    bin_len = struct.unpack_from('<I', raw, bin_offset)[0]
    bin_data = bytearray(raw[bin_offset+8:bin_offset+8+bin_len])
    return gltf, bin_data

def get_channel(gltf, bin_data, node_name, path_type):
    nodes = gltf['nodes']
    node_map = {n.get('name',''): i for i, n in enumerate(nodes)}
    idx = node_map.get(node_name)
    if idx is None: return None
    anim = gltf['animations'][0]
    for ch in anim['channels']:
        if ch['target']['node'] == idx and ch['target']['path'] == path_type:
            sampler = anim['samplers'][ch['sampler']]
            acc = gltf['accessors'][sampler['output']]
            bv = gltf['bufferViews'][acc['bufferView']]
            offset = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
            count = acc['count']
            if acc['type'] == 'VEC3':
                vals = [list(struct.unpack_from('<3f', bin_data, offset + i*12)) for i in range(count)]
            elif acc['type'] == 'VEC4':
                vals = [list(struct.unpack_from('<4f', bin_data, offset + i*16)) for i in range(count)]
            elif acc['type'] == 'SCALAR':
                vals = [struct.unpack_from('<f', bin_data, offset + i*4)[0] for i in range(count)]
            return vals
    return None

def quat_z_deg(q):
    import math
    return math.degrees(2 * math.atan2(q[2], q[3]))

for clip_num in [1, 2]:
    path = f'Data/SAF/Animations/GE/Dbd/Missionary01-DoubleBed-{clip_num}.glb'
    if not os.path.exists(path):
        print(f'Clip {clip_num}: NOT FOUND')
        continue
    gltf, bin_data = parse_glb(path)
    com = get_channel(gltf, bin_data, 'COM', 'translation')
    hips_rot = get_channel(gltf, bin_data, 'C_Hips', 'rotation')
    spine_rot = get_channel(gltf, bin_data, 'C_Spine', 'rotation')
    chest_rot = get_channel(gltf, bin_data, 'C_Chest', 'rotation')
    neck_rot = get_channel(gltf, bin_data, 'C_Neck', 'rotation')
    
    anim = gltf['animations'][0]
    max_frames = 0
    for ch in anim['channels']:
        sampler = anim['samplers'][ch['sampler']]
        acc = gltf['accessors'][sampler['input']]
        if acc['count'] > max_frames:
            max_frames = acc['count']
    
    role = 'm' if clip_num == 1 else 'x'
    print(f'Clip {clip_num} (role {role}):')
    print(f'  Nodes: {len(gltf["nodes"])}, Max frames: {max_frames}')
    if com:
        print(f'  COM: [{com[0][0]:.4f}, {com[0][1]:.4f}, {com[0][2]:.4f}]')
    if hips_rot:
        print(f'  C_Hips Z-pitch: {quat_z_deg(hips_rot[0]):.1f} deg')
    if spine_rot:
        print(f'  C_Spine Z-pitch: {quat_z_deg(spine_rot[0]):.1f} deg')
    if chest_rot:
        print(f'  C_Chest Z-pitch: {quat_z_deg(chest_rot[0]):.1f} deg')
    if neck_rot:
        print(f'  C_Neck Z-pitch: {quat_z_deg(neck_rot[0]):.1f} deg')
    
    # Check if lying down: COM Z should be low (~0.735m for bed)
    # and spine/chest should be roughly horizontal (large pitch rotation)
    print()
