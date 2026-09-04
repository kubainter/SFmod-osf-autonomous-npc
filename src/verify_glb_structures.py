"""Verify AGY claims about GLB structures before building modify_chair_touch.py"""
import gzip, struct, json

def parse_glb(path):
    """Parse a gzip-compressed GLB and return (gltf_dict, bin_data, nodes_list)"""
    with gzip.open(path, 'rb') as gz:
        raw = gz.read()
    magic, version, total_length = struct.unpack_from('<4sII', raw, 0)
    chunk0_len, chunk0_type = struct.unpack_from('<I4s', raw, 12)
    gltf = json.loads(raw[20:20+chunk0_len].decode('utf-8'))
    bin_offset = 20 + chunk0_len
    bin_len, bin_type = struct.unpack_from('<I4s', raw, bin_offset)
    bin_data = bytearray(raw[bin_offset+8:bin_offset+8+bin_len])
    return gltf, bin_data

def analyze(path, label):
    print(f'\n=== {label} ===')
    print(f'Path: {path}')
    gltf, bin_data = parse_glb(path)
    nodes = gltf['nodes']
    anim = gltf['animations'][0]
    samplers = anim['samplers']
    accessors = gltf['accessors']

    print(f'Total nodes: {len(nodes)}')

    # Frame count from first sampler
    sampler0 = samplers[0]
    acc_in = accessors[sampler0['input']]
    acc_out = accessors[sampler0['output']]
    print(f'Frames (input): {acc_in["count"]}')
    print(f'Frames (output): {acc_out["count"]}')

    # List all node names
    node_names = [n.get('name', f'node_{i}') for i, n in enumerate(nodes)]

    # Check finger bones
    finger_prefixes = ['L_Index', 'L_Middle', 'L_Ring', 'L_Pinky', 'L_Thumb', 'L_Cup',
                       'R_Index', 'R_Middle', 'R_Ring', 'R_Pinky', 'R_Thumb', 'R_Cup']
    finger_bones = sorted([n for n in node_names if any(n.startswith(p) for p in finger_prefixes)])
    print(f'Finger bones ({len(finger_bones)}):')
    for fb in finger_bones:
        print(f'  {fb}')

    # Check key bones
    key_bones = ['Root', 'HumanExportRoot', 'COM', 'C_Hips',
                 'C_Spine', 'C_Spine1', 'C_Spine2', 'C_Chest',
                 'C_Neck', 'C_Neck1', 'C_Head',
                 'L_Clavicle', 'L_Biceps', 'L_Forearm', 'L_Wrist',
                 'R_Clavicle', 'R_Biceps', 'R_Forearm', 'R_Wrist',
                 'R_Thigh', 'L_Thigh', 'R_Calf', 'L_Calf',
                 'R_Foot', 'L_Foot', 'R_Toe', 'L_Toe',
                 'R_Thigh_Twist', 'R_Thigh_Twist1', 'L_Thigh_Twist', 'L_Thigh_Twist1',
                 'R_CalfMass', 'L_CalfMass', 'R_Knee', 'L_Knee',
                 'L_Butt', 'R_Butt', 'C_Waist']
    print(f'Key bones:')
    for b in key_bones:
        found = b in node_names
        print(f'  {b}: {"OK" if found else "MISSING"}')

    # Check animation channels - which bones have rotation/translation
    channels = anim['channels']
    rot_bones = []
    trans_bones = []
    for ch in channels:
        node_idx = ch['target']['node']
        node_name = nodes[node_idx].get('name', f'node_{node_idx}')
        path_type = ch['target']['path']
        if path_type == 'rotation':
            rot_bones.append(node_name)
        elif path_type == 'translation':
            trans_bones.append(node_name)
    print(f'Rotation channels: {len(rot_bones)} bones')
    print(f'Translation channels: {len(trans_bones)} bones')
    print(f'Translation bones: {sorted(trans_bones)}')

    # Check COM translation values (first frame)
    for ch in channels:
        node_idx = ch['target']['node']
        node_name = nodes[node_idx].get('name', '')
        if node_name == 'COM' and ch['target']['path'] == 'translation':
            sampler = samplers[ch['sampler']]
            acc = accessors[sampler['output']]
            bv = gltf['bufferViews'][acc['bufferView']]
            offset = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
            vals = struct.unpack_from('<3f', bin_data, offset)
            print(f'COM translation (frame 0): {vals}')
        if node_name == 'COM' and ch['target']['path'] == 'rotation':
            sampler = samplers[ch['sampler']]
            acc = accessors[sampler['output']]
            bv = gltf['bufferViews'][acc['bufferView']]
            offset = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
            vals = struct.unpack_from('<4f', bin_data, offset)
            print(f'COM rotation (frame 0): {vals}')
        if node_name == 'C_Hips' and ch['target']['path'] == 'rotation':
            sampler = samplers[ch['sampler']]
            acc = accessors[sampler['output']]
            bv = gltf['bufferViews'][acc['bufferView']]
            offset = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
            vals = struct.unpack_from('<4f', bin_data, offset)
            print(f'C_Hips rotation (frame 0): {vals}')

    return node_names

# Analyze our solo animation
our_nodes = analyze(
    'G:/Starfield/Data/OSF/Autonomous/Animations/solo_standing_touch.glb',
    'solo_standing_touch.glb (OUR BASE)'
)

# Analyze GE donor
ge_nodes = analyze(
    'G:/Starfield/Data/SAF/Animations/GE/ChO/Blowjob07-ChairOffice-1.glb',
    'Blowjob07-ChairOffice-1.glb (GE DONOR)'
)

# Compare node sets
our_set = set(our_nodes)
ge_set = set(ge_nodes)
print(f'\n=== COMPARISON ===')
print(f'Our nodes: {len(our_set)}')
print(f'GE nodes: {len(ge_set)}')
print(f'Common nodes: {len(our_set & ge_set)}')
print(f'Only in GE (not in ours): {sorted(ge_set - our_set)}')
print(f'Only in ours (not in GE): {sorted(our_set - ge_set)}')

# Check which lower-body bones exist in both
lower_body = ['COM', 'C_Hips', 'R_Thigh', 'L_Thigh', 'R_Calf', 'L_Calf',
              'R_Foot', 'L_Foot', 'R_Toe', 'L_Toe',
              'R_Thigh_Twist', 'R_Thigh_Twist1', 'L_Thigh_Twist', 'L_Thigh_Twist1',
              'R_CalfMass', 'L_CalfMass', 'R_Knee', 'L_Knee', 'L_Butt', 'R_Butt']
print(f'\nLower body bones in BOTH:')
for b in lower_body:
    in_our = b in our_set
    in_ge = b in ge_set
    print(f'  {b}: ours={"OK" if in_our else "MISSING"} ge={"OK" if in_ge else "MISSING"}')
