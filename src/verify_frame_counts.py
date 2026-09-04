"""Check frame counts across ALL samplers in both GLBs"""
import gzip, struct, json

def parse_glb(path):
    with gzip.open(path, 'rb') as gz:
        raw = gz.read()
    chunk0_len = struct.unpack_from('<I', raw, 12)[0]
    gltf = json.loads(raw[20:20+chunk0_len].decode('utf-8'))
    bin_offset = 20 + chunk0_len
    bin_len = struct.unpack_from('<I', raw, bin_offset)[0]
    bin_data = bytearray(raw[bin_offset+8:bin_offset+8+bin_len])
    return gltf, bin_data

def check_all_samplers(path, label):
    print(f'\n=== {label} ===')
    gltf, bin_data = parse_glb(path)
    nodes = gltf['nodes']
    anim = gltf['animations'][0]
    channels = anim['channels']
    samplers = anim['samplers']
    accessors = gltf['accessors']

    # Collect frame counts per channel
    frame_counts = {}
    for ch in channels:
        node_idx = ch['target']['node']
        node_name = nodes[node_idx].get('name', f'node_{node_idx}')
        path_type = ch['target']['path']
        sampler = samplers[ch['sampler']]
        acc_in = accessors[sampler['input']]
        count = acc_in['count']
        key = f'{node_name}.{path_type}'
        frame_counts[key] = count

    # Get unique frame counts
    counts = list(frame_counts.values())
    unique = sorted(set(counts))
    print(f'Unique frame counts: {unique}')
    print(f'Min frames: {min(counts)}, Max frames: {max(counts)}')

    # Show distribution
    for uc in unique:
        bones_with_count = [k for k, v in frame_counts.items() if v == uc]
        print(f'  {uc} frames: {len(bones_with_count)} channels')
        if uc == max(counts) or uc == min(counts):
            # Show which bones have this count
            if len(bones_with_count) <= 10:
                for b in sorted(bones_with_count):
                    print(f'    - {b}')
            else:
                for b in sorted(bones_with_count)[:5]:
                    print(f'    - {b}')
                print(f'    ... and {len(bones_with_count)-5} more')

    # Specifically check lower body bones
    lower_body = ['COM', 'C_Hips', 'R_Thigh', 'L_Thigh', 'R_Calf', 'L_Calf',
                  'R_Foot', 'L_Foot', 'R_Toe', 'L_Toe']
    print(f'\nLower body frame counts:')
    for b in lower_body:
        rot_key = f'{b}.rotation'
        trans_key = f'{b}.translation'
        rot_count = frame_counts.get(rot_key, 'N/A')
        trans_count = frame_counts.get(trans_key, 'N/A')
        print(f'  {b}: rot={rot_count} frames, trans={trans_count} frames')

    # Check key animated bones
    key_bones = ['C_Spine', 'C_Chest', 'C_Neck', 'C_Head',
                 'L_Clavicle', 'L_Biceps', 'L_Forearm', 'L_Wrist',
                 'R_Clavicle', 'R_Biceps', 'R_Forearm', 'R_Wrist',
                 'L_Index', 'L_Index1', 'R_Index', 'R_Index1']
    print(f'Key animated bones frame counts:')
    for b in key_bones:
        rot_key = f'{b}.rotation'
        rot_count = frame_counts.get(rot_key, 'N/A')
        print(f'  {b}: rot={rot_count} frames')

    return max(counts)

our_max = check_all_samplers(
    'G:/Starfield/Data/OSF/Autonomous/Animations/solo_standing_touch.glb',
    'OUR BASE: solo_standing_touch.glb'
)
ge_max = check_all_samplers(
    'G:/Starfield/Data/SAF/Animations/GE/ChO/Blowjob07-ChairOffice-1.glb',
    'GE DONOR: Blowjob07-ChairOffice-1.glb'
)

print(f'\n=== SUMMARY ===')
print(f'Our max frames: {our_max}')
print(f'GE max frames: {ge_max}')
