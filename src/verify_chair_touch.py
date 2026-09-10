"""Verify solo_chair_touch.glb animation data"""
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

gltf, bin_data = parse_glb('G:/Starfield/Data/OSF/Autonomous/Animations/solo_chair_touch.glb')
nodes = gltf['nodes']
anim = gltf['animations'][0]
channels = anim['channels']
samplers = anim['samplers']
accessors = gltf['accessors']

# Build node map
node_map = {n.get('name', f'node_{i}'): i for i, n in enumerate(nodes)}

def get_data(name, path_type):
    node_idx = node_map.get(name)
    if node_idx is None:
        return None
    for ch in channels:
        if ch['target']['node'] == node_idx and ch['target']['path'] == path_type:
            sampler = samplers[ch['sampler']]
            times, _ = read_accessor(sampler['input'], gltf, bin_data)
            values, _ = read_accessor(sampler['output'], gltf, bin_data)
            return len(times), values
    return None

# Check key bones
print('=== SOLO_CHAIR_TOUCH VERIFICATION ===\n')

# 1. COM (should be seated position)
count, com_trans = get_data('COM', 'translation')
print(f'COM translation: {count} frames')
print(f'  Frame 0: {com_trans[0]}')
print(f'  Frame 479: {com_trans[-1]}')
print(f'  Expected Z~0.675 (seated) vs our standing Z~1.059')
print(f'  Static: {com_trans[0] == com_trans[-1]}')

# 2. C_Hips (should be seated + sway)
count, hips_rot = get_data('C_Hips', 'rotation')
print(f'\nC_Hips rotation: {count} frames')
print(f'  Frame 0: {[round(x,4) for x in hips_rot[0]]}')
print(f'  Frame 240: {[round(x,4) for x in hips_rot[240]]}')
print(f'  Frame 479: {[round(x,4) for x in hips_rot[479]]}')
# Check if there's variation (sway)
variations = [math.sqrt(sum((hips_rot[i][j]-hips_rot[0][j])**2 for j in range(4))) for i in range(0, 480, 48)]
print(f'  Variation from frame 0 (every 48 frames): {[round(v,4) for v in variations]}')

# 3. Left arm HUSH (should be static hush pose)
for bone in ['L_Clavicle', 'L_Biceps', 'L_Forearm', 'L_Wrist']:
    count, rots = get_data(bone, 'rotation')
    print(f'\n{bone} rotation: {count} frames')
    print(f'  Frame 0: {[round(x,5) for x in rots[0]]}')
    print(f'  Frame 240: {[round(x,5) for x in rots[240]]}')
    # Check if close to AGY target
    target = {
        'L_Clavicle': [0.84613, -0.07673, 0.51754, -0.10168],
        'L_Biceps':   [0.23075, 0.71623, -0.65685, 0.04812],
        'L_Forearm':  [-0.02646, -0.85241, -0.42422, 0.30453],
        'L_Wrist':    [0.57855, -0.10917, -0.39861, 0.70319],
    }[bone]
    dist = math.sqrt(sum((rots[0][j]-target[j])**2 for j in range(4)))
    print(f'  Distance from AGY target: {dist:.6f}')

# 4. Left index finger (should be extended)
count, idx_rot = get_data('L_Index', 'rotation')
print(f'\nL_Index rotation: {count} frames')
print(f'  Frame 0: {[round(x,5) for x in idx_rot[0]]}')

# 5. Right arm (should have adduction + massage)
for bone in ['R_Biceps', 'R_Forearm', 'R_Wrist']:
    count, rots = get_data(bone, 'rotation')
    print(f'\n{bone} rotation: {count} frames')
    print(f'  Frame 0: {[round(x,5) for x in rots[0]]}')
    print(f'  Frame 120: {[round(x,5) for x in rots[120]]}')
    # Check variation (massage motion)
    if count == 480:
        max_var = max(math.sqrt(sum((rots[i][j]-rots[0][j])**2 for j in range(4))) for i in range(480))
        print(f'  Max variation: {max_var:.6f}')

# 6. Head (should be clamped)
for bone in ['C_Neck', 'C_Head']:
    count, rots = get_data(bone, 'rotation')
    print(f'\n{bone} rotation: {count} frames')
    print(f'  Frame 0: {[round(x,5) for x in rots[0]]}')
    print(f'  Frame 240: {[round(x,5) for x in rots[240]]}')

# 7. Lower body (should be transplanted from GE)
for bone in ['R_Thigh', 'L_Thigh', 'R_Calf', 'L_Calf']:
    count, rots = get_data(bone, 'rotation')
    print(f'\n{bone} rotation: {count} frames')
    print(f'  Frame 0: {[round(x,5) for x in rots[0]]}')

# 8. Check for NaN
nan_count = 0
for ch in channels:
    sampler = samplers[ch['sampler']]
    values, _ = read_accessor(sampler['output'], gltf, bin_data)
    for v in values:
        if isinstance(v, float) and math.isnan(v):
            nan_count += 1
        elif isinstance(v, list):
            for x in v:
                if math.isnan(x):
                    nan_count += 1
print(f'\n=== NaN check: {nan_count} NaN values found ===')

# 9. Frame count distribution
frame_counts = {}
for ch in channels:
    sampler = samplers[ch['sampler']]
    acc = accessors[sampler['input']]
    count = acc['count']
    frame_counts[count] = frame_counts.get(count, 0) + 1
print(f'\nFrame count distribution: {frame_counts}')
