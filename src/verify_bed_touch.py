"""Verify solo_bed_touch.glb animation data"""
import gzip, struct, json, math

def parse_glb(path):
    with gzip.open(path, 'rb') as gz:
        raw = gz.read()
    chunk0_len = struct.unpack_from('<I', raw, 12)[0]
    gltf = json.loads(raw[20:20+chunk0_len].decode('utf-8'))
    bin_offset = 20 + chunk0_len
    bin_len = struct.unpack_from('<I', raw, bin_offset)[0]
    bin_data = bytearray(raw[bin_offset+8:bin_offset+8+bin_len])
    return gltf, bin_data

def read_accessor(acc_idx, gltf, bin_data):
    acc = gltf['accessors'][acc_idx]
    bv = gltf['bufferViews'][acc['bufferView']]
    offset = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
    count = acc['count']
    acc_type = acc['type']
    result = []
    for i in range(count):
        if acc_type == 'SCALAR':
            result.append(struct.unpack_from('<f', bin_data, offset + i*4)[0])
        elif acc_type == 'VEC3':
            result.append(list(struct.unpack_from('<3f', bin_data, offset + i*12)))
        elif acc_type == 'VEC4':
            result.append(list(struct.unpack_from('<4f', bin_data, offset + i*16)))
    return result, acc_type

gltf, bin_data = parse_glb('G:/Starfield/Data/OSF/Autonomous/Animations/solo_bed_touch.glb')
nodes = gltf['nodes']
anim = gltf['animations'][0]
channels = anim['channels']
samplers = anim['samplers']
accessors = gltf['accessors']
node_map = {n.get('name', f'node_{i}'): i for i, n in enumerate(nodes)}

def get_data(name, path_type):
    node_idx = node_map.get(name)
    if node_idx is None: return None
    for ch in channels:
        if ch['target']['node'] == node_idx and ch['target']['path'] == path_type:
            sampler = samplers[ch['sampler']]
            times, _ = read_accessor(sampler['input'], gltf, bin_data)
            values, _ = read_accessor(sampler['output'], gltf, bin_data)
            return len(times), values
    return None

def quat_z_deg(q):
    return math.degrees(2 * math.atan2(q[2], q[3]))

print('=== SOLO_BED_TOUCH VERIFICATION ===\n')

# 1. COM (should be supine bed position)
count, com_trans = get_data('COM', 'translation')
print(f'COM translation: {count} frames')
print(f'  Frame 0: {com_trans[0]}')
print(f'  Expected: [0.190, -0.016, 0.749] (supine DoubleBed)')
print(f'  Static: {com_trans[0] == com_trans[-1]}')

# 2. C_Hips (should be 180° pitch = lying on back)
count, hips_rot = get_data('C_Hips', 'rotation')
print(f'\nC_Hips rotation: {count} frames')
print(f'  Frame 0 Z-pitch: {quat_z_deg(hips_rot[0]):.1f} deg (expect ~180°)')
print(f'  Frame 240 Z-pitch: {quat_z_deg(hips_rot[240]):.1f} deg')

# 3. Left arm HUSH (supine quaternions)
print(f'\n--- HUSH Left Arm (supine) ---')
for bone in ['L_Clavicle', 'L_Biceps', 'L_Forearm', 'L_Wrist']:
    count, rots = get_data(bone, 'rotation')
    target = {
        'L_Clavicle': [0.84613, -0.07673, 0.51754, -0.10168],
        'L_Biceps':   [0.01671, 0.67707, -0.72383, -0.13177],
        'L_Forearm':  [0.03653, -0.79803, -0.42347, 0.42718],
        'L_Wrist':    [0.59539, -0.07839, -0.37299, 0.70728],
    }[bone]
    dist = math.sqrt(sum((rots[0][j]-target[j])**2 for j in range(4)))
    print(f'  {bone}: dist from AGY target = {dist:.6f}')

# 4. Right arm (should be standing base, no adduction)
print(f'\n--- Right Arm (standing base, no adduction) ---')
for bone in ['R_Biceps', 'R_Forearm', 'R_Wrist']:
    count, rots = get_data(bone, 'rotation')
    if count == 480:
        max_var = max(math.sqrt(sum((rots[i][j]-rots[0][j])**2 for j in range(4))) for i in range(480))
        print(f'  {bone}: {count} frames, max variation: {max_var:.6f}')

# 5. Head (should be from donor, small motion)
print(f'\n--- Head ---')
for bone in ['C_Neck', 'C_Head']:
    count, rots = get_data(bone, 'rotation')
    if count == 480:
        z_degs = [quat_z_deg(r) for r in rots]
        print(f'  {bone}: Z-pitch {min(z_degs):.2f}° to {max(z_degs):.2f}° (span: {max(z_degs)-min(z_degs):.2f}°)')

# 6. Spine (breathing)
print(f'\n--- Spine (breathing) ---')
for bone in ['C_Spine', 'C_Chest']:
    count, rots = get_data(bone, 'rotation')
    if count == 480:
        z_degs = [quat_z_deg(r) for r in rots]
        print(f'  {bone}: Z-pitch {min(z_degs):.2f}° to {max(z_degs):.2f}° (span: {max(z_degs)-min(z_degs):.2f}°)')

# 7. Lower body (should be static supine)
print(f'\n--- Lower Body ---')
for bone in ['R_Thigh', 'L_Thigh', 'R_Calf', 'L_Calf']:
    count, rots = get_data(bone, 'rotation')
    print(f'  {bone}: {count} frames, Z-pitch: {quat_z_deg(rots[0]):.1f}°')

# 8. NaN check
nan_count = 0
for ch in channels:
    sampler = samplers[ch['sampler']]
    values, _ = read_accessor(sampler['output'], gltf, bin_data)
    for v in values:
        if isinstance(v, float) and math.isnan(v):
            nan_count += 1
        elif isinstance(v, list):
            for x in v:
                if math.isnan(x): nan_count += 1
print(f'\n=== NaN check: {nan_count} NaN values ===')

# 9. Frame count distribution
frame_counts = {}
for ch in channels:
    sampler = samplers[ch['sampler']]
    acc = accessors[sampler['input']]
    count = acc['count']
    frame_counts[count] = frame_counts.get(count, 0) + 1
print(f'Frame count distribution: {frame_counts}')

# 10. GLB structure
print(f'\n=== GLB Structure ===')
print(f'  Nodes: {len(nodes)}')
print(f'  Channels: {len(channels)}')
print(f'  Samplers: {len(samplers)}')
print(f'  Accessors: {len(accessors)}')
