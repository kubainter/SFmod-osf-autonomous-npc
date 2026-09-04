import gzip, struct, json, math

import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'G:/Starfield/Data/SAF/Animations/standself01.glb'
with gzip.open(path, 'rb') as gz:
    data = gz.read()

# Parse GLB
json_len = struct.unpack('<I', data[12:16])[0]
json_data = json.loads(data[20:20+json_len].decode('utf-8'))

anim = json_data['animations'][0]
channels = anim['channels']
samplers = anim['samplers']
accessors = json_data['accessors']
bufferViews = json_data['bufferViews']
nodes = json_data['nodes']

# Get duration
time_accessors = [accessors[sampler['input']] for sampler in samplers]
time_max = max(accessor.get('max', [0])[0] for accessor in time_accessors)
time_counts = [accessor['count'] for accessor in time_accessors]

anim_name = anim.get('name', 'unnamed')
print(f'Animation: {anim_name}')
print(f'Duration: {time_max:.3f}s')
print(f'Keyframes per sampler: min={min(time_counts)} max={max(time_counts)} unique={sorted(set(time_counts))}')
print(f'Channels: {len(channels)}')

# Check which bones are animated
bone_channels = {}
for ch in channels:
    node_idx = ch['target']['node']
    node_name = nodes[node_idx].get('name', f'node_{node_idx}')
    path_type = ch['target']['path']
    if node_name not in bone_channels:
        bone_channels[node_name] = []
    bone_channels[node_name].append(path_type)

print(f'Animated bones: {len(bone_channels)}')

# Check root motion
for check_name in ['Root', 'HumanExportRoot', 'COM', 'C_Hips']:
    if check_name in bone_channels:
        paths = bone_channels[check_name]
        has_trans = 'translation' in paths
        has_rot = 'rotation' in paths
        print(f'  {check_name}: translation={has_trans} rotation={has_rot}')

# Now extract actual translation values for Root/COM to measure root motion
# Get binary data
bin_chunk_start = 20 + json_len
bin_len, bin_type = struct.unpack_from('<I4s', data, bin_chunk_start)
bin_data = data[bin_chunk_start + 8:bin_chunk_start + 8 + bin_len]

def read_accessor(acc_idx):
    acc = accessors[acc_idx]
    bv = bufferViews[acc['bufferView']]
    offset = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
    count = acc['count']
    acc_type = acc['type']
    comp_type = acc.get('componentType', 5126)
    
    if comp_type == 5126:  # FLOAT
        floats = []
        for i in range(count):
            if acc_type == 'SCALAR':
                val = struct.unpack_from('<f', bin_data, offset + i*4)[0]
                floats.append(val)
            elif acc_type == 'VEC3':
                vals = struct.unpack_from('<3f', bin_data, offset + i*12)
                floats.append(list(vals))
            elif acc_type == 'VEC4':
                vals = struct.unpack_from('<4f', bin_data, offset + i*16)
                floats.append(list(vals))
        return floats
    return []

# Check translation ranges for key bones
print('\n=== Translation analysis ===')
for ch in channels:
    node_idx = ch['target']['node']
    node_name = nodes[node_idx].get('name', '')
    if ch['target']['path'] == 'translation' and node_name in ['Root', 'HumanExportRoot', 'COM', 'C_Hips']:
        sampler = samplers[ch['sampler']]
        times = read_accessor(sampler['input'])
        trans = read_accessor(sampler['output'])
        
        min_x = min(t[0] for t in trans)
        max_x = max(t[0] for t in trans)
        min_y = min(t[1] for t in trans)
        max_y = max(t[1] for t in trans)
        min_z = min(t[2] for t in trans)
        max_z = max(t[2] for t in trans)
        
        dx = max_x - min_x
        dy = max_y - min_y
        dz = max_z - min_z
        
        print(f'{node_name}: dx={dx*100:.1f}cm dy={dy*100:.1f}cm dz={dz*100:.1f}cm')
        print(f'  first: {trans[0]}')
        print(f'  last:  {trans[-1]}')
        
        # Check loop seam
        seam = math.sqrt(
            (trans[0][0]-trans[-1][0])**2 +
            (trans[0][1]-trans[-1][1])**2 +
            (trans[0][2]-trans[-1][2])**2
        )
        print(f'  loop seam: {seam*100:.2f}cm')

# Check rotation ranges for arms and legs
print('\n=== Rotation analysis (degrees) ===')
for ch in channels:
    node_idx = ch['target']['node']
    node_name = nodes[node_idx].get('name', '')
    if ch['target']['path'] == 'rotation' and (node_name in [
        'C_Hips', 'C_Spine', 'C_Chest', 'C_Head', 'C_Neck',
        'L_Clavicle', 'R_Clavicle', 'L_Biceps', 'R_Biceps',
        'L_Forearm', 'R_Forearm', 'L_Wrist', 'R_Wrist',
        'L_Thigh', 'R_Thigh', 'L_Calf', 'R_Calf'
    ] or node_name.startswith(('R_Thumb', 'R_Index', 'R_Middle', 'R_Ring', 'R_Pinky'))):
        sampler = samplers[ch['sampler']]
        rots = read_accessor(sampler['output'])
        
        max_angle = 0
        for i in range(len(rots)):
            for j in range(i+1, len(rots)):
                q1 = rots[i]
                q2 = rots[j]
                dot = abs(q1[0]*q2[0] + q1[1]*q2[1] + q1[2]*q2[2] + q1[3]*q2[3])
                dot = min(1.0, max(-1.0, dot))
                angle = 2 * math.degrees(math.acos(dot))
                if angle > max_angle:
                    max_angle = angle
        
        seam_dot = abs(sum(rots[0][i] * rots[-1][i] for i in range(4)))
        seam_angle = 2 * math.degrees(math.acos(min(1.0, max(-1.0, seam_dot))))
        print(f'  {node_name}: max rotation delta = {max_angle:.1f} degrees, seam = {seam_angle:.3f} degrees')

weight_channels = [ch for ch in channels if ch['target']['path'] == 'weights']
morph_meshes = []
for mesh_idx, mesh in enumerate(json_data.get('meshes', [])):
    target_count = max((len(primitive.get('targets', [])) for primitive in mesh.get('primitives', [])), default=0)
    if target_count:
        morph_meshes.append((mesh_idx, mesh.get('name', ''), target_count))
print(f'\nWeight animation channels: {len(weight_channels)}')
print(f'Meshes with morph targets: {morph_meshes}')
for target_name in ['C_Neck', 'C_Neck1', 'C_Head']:
    for ch in channels:
        if nodes[ch['target']['node']].get('name', '') == target_name and ch['target']['path'] == 'rotation':
            sampler = samplers[ch['sampler']]
            output_accessor = sampler['output']
            users = sum(s['output'] == output_accessor for s in samplers)
            print(f'{target_name} rotation: sampler={ch["sampler"]} output={output_accessor} output_users={users}')
