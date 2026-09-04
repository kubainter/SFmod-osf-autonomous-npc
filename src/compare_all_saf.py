"""
Compare all SAF solo and paired animations to find patterns for solo animation improvement.
"""
import gzip, struct, json, math, os

ANIM_DIR = 'G:/Starfield/Data/SAF/Animations'

SOLO_FILES = [
    'standself01.glb', 'standself02.glb', 'standself03.glb',
    'standsensor01.glb', 'standsensor02.glb', 'standsensor03.glb',
]

PAIRED_FILES = [
    'bridge01bot.glb', 'bridge01top.glb',
    'bridge02bot.glb', 'bridge02top.glb',
    'downdog01bot.glb', 'downdog01top.glb',
]

KEY_BONES = [
    'C_Hips', 'C_Spine', 'C_Chest', 'C_Neck', 'C_Head',
    'L_Clavicle', 'R_Clavicle',
    'L_Biceps', 'R_Biceps',
    'L_Forearm', 'R_Forearm',
    'L_Wrist', 'R_Wrist',
    'L_Thigh', 'R_Thigh',
    'L_Calf', 'R_Calf',
    'COM', 'Root', 'HumanExportRoot',
]

def parse_glb(path):
    with gzip.open(path, 'rb') as gz:
        raw = gz.read()
    
    chunk0_len = struct.unpack_from('<I', raw, 12)[0]
    gltf = json.loads(raw[20:20+chunk0_len].decode('utf-8'))
    
    bin_offset = 20 + chunk0_len
    bin_len = struct.unpack_from('<I', raw, bin_offset)[0]
    bin_data = raw[bin_offset+8:bin_offset+8+bin_len]
    
    return gltf, bin_data

def read_accessor(acc_idx, accessors, bufferViews, bin_data):
    acc = accessors[acc_idx]
    bv = bufferViews[acc['bufferView']]
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
    return result

def quat_angle_deg(q1, q2):
    dot = abs(q1[0]*q2[0] + q1[1]*q2[1] + q1[2]*q2[2] + q1[3]*q2[3])
    dot = min(1.0, max(-1.0, dot))
    return 2 * math.degrees(math.acos(dot))

def analyze_file(path):
    gltf, bin_data = parse_glb(path)
    anim = gltf['animations'][0]
    channels = anim['channels']
    samplers = anim['samplers']
    accessors = gltf['accessors']
    bufferViews = gltf['bufferViews']
    nodes = gltf['nodes']
    
    # Duration
    time_accs = [accessors[s['input']] for s in samplers]
    duration = max(a.get('max', [0])[0] for a in time_accs)
    kf_counts = [a['count'] for a in time_accs]
    
    # Bone channels
    bone_data = {}  # name -> {'rotation': [...], 'translation': [...]}
    for ch in channels:
        node_name = nodes[ch['target']['node']].get('name', '')
        path_type = ch['target']['path']
        sampler = samplers[ch['sampler']]
        
        if node_name not in bone_data:
            bone_data[node_name] = {}
        
        if path_type == 'rotation':
            rots = read_accessor(sampler['output'], accessors, bufferViews, bin_data)
            bone_data[node_name]['rotation'] = rots
            if len(rots) > 1:
                max_delta = 0
                for i in range(len(rots)):
                    for j in range(i+1, len(rots)):
                        a = quat_angle_deg(rots[i], rots[j])
                        if a > max_delta:
                            max_delta = a
                bone_data[node_name]['rot_max_delta'] = max_delta
            else:
                bone_data[node_name]['rot_max_delta'] = 0
                
        elif path_type == 'translation':
            trans = read_accessor(sampler['output'], accessors, bufferViews, bin_data)
            bone_data[node_name]['translation'] = trans
            if len(trans) > 1:
                dx = max(t[0] for t in trans) - min(t[0] for t in trans)
                dy = max(t[1] for t in trans) - min(t[1] for t in trans)
                dz = max(t[2] for t in trans) - min(t[2] for t in trans)
                bone_data[node_name]['trans_range'] = (dx*100, dy*100, dz*100)  # cm
                seam = math.sqrt(
                    (trans[0][0]-trans[-1][0])**2 +
                    (trans[0][1]-trans[-1][1])**2 +
                    (trans[0][2]-trans[-1][2])**2
                ) * 100
                bone_data[node_name]['loop_seam_cm'] = seam
            else:
                bone_data[node_name]['trans_range'] = (0, 0, 0)
                bone_data[node_name]['loop_seam_cm'] = 0
    
    return {
        'duration': duration,
        'kf_counts': kf_counts,
        'bone_data': bone_data,
    }

# Analyze all files
print('=' * 80)
print('SOLO ANIMATIONS')
print('=' * 80)

results = {}
for f in SOLO_FILES + PAIRED_FILES:
    path = os.path.join(ANIM_DIR, f)
    if not os.path.exists(path):
        print(f'\n{f}: NOT FOUND')
        continue
    
    info = analyze_file(path)
    results[f] = info
    
    kf_unique = sorted(set(info['kf_counts']))
    is_solo = f in SOLO_FILES
    category = 'SOLO' if is_solo else 'PAIRED'
    
    print(f'\n--- {f} ({category}) ---')
    print(f'  Duration: {info["duration"]:.1f}s, Keyframes: min={min(info["kf_counts"])} max={max(info["kf_counts"])}')
    
    # Root motion
    for bone in ['Root', 'COM', 'C_Hips']:
        if bone in info['bone_data'] and 'trans_range' in info['bone_data'][bone]:
            tr = info['bone_data'][bone]['trans_range']
            seam = info['bone_data'][bone].get('loop_seam_cm', 0)
            print(f'  {bone} trans: dx={tr[0]:.1f}cm dy={tr[1]:.1f}cm dz={tr[2]:.1f}cm seam={seam:.1f}cm')
    
    # Key bone rotations
    print(f'  Rotations (degrees):')
    for bone in KEY_BONES:
        if bone in info['bone_data'] and 'rot_max_delta' in info['bone_data'][bone]:
            delta = info['bone_data'][bone]['rot_max_delta']
            if delta > 0.1:
                print(f'    {bone:20s}: {delta:6.1f}°')

# Summary comparison
print('\n\n' + '=' * 80)
print('COMPARISON SUMMARY')
print('=' * 80)

print('\n--- Solo Neutral (standself) vs Solo Sensual (standsensor) ---')
print(f'{"Bone":20s} {"self01":>8s} {"self02":>8s} {"self03":>8s} {"sens01":>8s} {"sens02":>8s} {"sens03":>8s}')
for bone in KEY_BONES:
    vals = []
    for f in SOLO_FILES:
        if f in results and bone in results[f]['bone_data'] and 'rot_max_delta' in results[f]['bone_data'][bone]:
            vals.append(f'{results[f]["bone_data"][bone]["rot_max_delta"]:6.1f}')
        else:
            vals.append('   -  ')
    if any(v.strip() != '-' for v in vals):
        print(f'{bone:20s} {vals[0]:>8s} {vals[1]:>8s} {vals[2]:>8s} {vals[3]:>8s} {vals[4]:>8s} {vals[5]:>8s}')

print('\n--- Paired bot/top (single actor from paired scene) ---')
print(f'{"Bone":20s} {"br01bot":>8s} {"br01top":>8s} {"br02bot":>8s} {"br02top":>8s} {"dd01bot":>8s} {"dd01top":>8s}')
for bone in KEY_BONES:
    vals = []
    for f in PAIRED_FILES:
        if f in results and bone in results[f]['bone_data'] and 'rot_max_delta' in results[f]['bone_data'][bone]:
            vals.append(f'{results[f]["bone_data"][bone]["rot_max_delta"]:6.1f}')
        else:
            vals.append('   -  ')
    if any(v.strip() != '-' for v in vals):
        print(f'{bone:20s} {vals[0]:>8s} {vals[1]:>8s} {vals[2]:>8s} {vals[3]:>8s} {vals[4]:>8s} {vals[5]:>8s}')

# Root motion comparison
print('\n--- Root motion (COM translation cm) ---')
print(f'{"File":25s} {"dx":>6s} {"dy":>6s} {"dz":>6s} {"seam":>6s}')
for f in SOLO_FILES + PAIRED_FILES:
    if f not in results:
        continue
    bd = results[f]['bone_data']
    if 'COM' in bd and 'trans_range' in bd['COM']:
        tr = bd['COM']['trans_range']
        seam = bd['COM'].get('loop_seam_cm', 0)
        print(f'{f:25s} {tr[0]:6.1f} {tr[1]:6.1f} {tr[2]:6.1f} {seam:6.1f}')
