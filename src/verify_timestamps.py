"""Check timestamp values for 480-frame and 481-frame accessors"""
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

def read_accessor_scalar(acc_idx, gltf, bin_data):
    acc = gltf['accessors'][acc_idx]
    bv = gltf['bufferViews'][acc['bufferView']]
    offset = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
    count = acc['count']
    return [struct.unpack_from('<f', bin_data, offset + i*4)[0] for i in range(count)]

# Our base
our_gltf, our_bin = parse_glb('G:/Starfield/Data/OSF/Autonomous/Animations/solo_standing_touch.glb')
our_anim = our_gltf['animations'][0]
our_samplers = our_anim['samplers']
our_accessors = our_gltf['accessors']

# Find a 480-frame sampler
for i, s in enumerate(our_samplers):
    acc = our_accessors[s['input']]
    if acc['count'] == 480:
        times = read_accessor_scalar(s['input'], our_gltf, our_bin)
        print(f'OUR 480-frame timestamps:')
        print(f'  First 3: {times[:3]}')
        print(f'  Last 3: {times[-3:]}')
        print(f'  Duration: {times[-1] - times[0]:.6f}s')
        break

# Find a 2-frame sampler
for i, s in enumerate(our_samplers):
    acc = our_accessors[s['input']]
    if acc['count'] == 2:
        times = read_accessor_scalar(s['input'], our_gltf, our_bin)
        print(f'OUR 2-frame timestamps: {times}')
        break

# GE donor
ge_gltf, ge_bin = parse_glb('G:/Starfield/Data/SAF/Animations/GE/ChO/Blowjob07-ChairOffice-1.glb')
ge_anim = ge_gltf['animations'][0]
ge_samplers = ge_anim['samplers']
ge_accessors = ge_gltf['accessors']

# Find a 481-frame sampler
for i, s in enumerate(ge_samplers):
    acc = ge_accessors[s['input']]
    if acc['count'] == 481:
        times = read_accessor_scalar(s['input'], ge_gltf, ge_bin)
        print(f'\nGE 481-frame timestamps:')
        print(f'  First 3: {times[:3]}')
        print(f'  Last 3: {times[-3:]}')
        print(f'  Duration: {times[-1] - times[0]:.6f}s')
        # Check if frame 0 == frame 480
        print(f'  Frame 0: {times[0]:.6f}')
        print(f'  Frame 480: {times[480]:.6f}')
        break

# Find a 2-frame sampler in GE
for i, s in enumerate(ge_samplers):
    acc = ge_accessors[s['input']]
    if acc['count'] == 2:
        times = read_accessor_scalar(s['input'], ge_gltf, ge_bin)
        print(f'GE 2-frame timestamps: {times}')
        break

# Check if our 480-frame timestamps match GE frames 1..480
our_times = None
for s in our_samplers:
    acc = our_accessors[s['input']]
    if acc['count'] == 480:
        our_times = read_accessor_scalar(s['input'], our_gltf, our_bin)
        break

ge_times = None
for s in ge_samplers:
    acc = ge_accessors[s['input']]
    if acc['count'] == 481:
        ge_times = read_accessor_scalar(s['input'], ge_gltf, ge_bin)
        break

if our_times and ge_times:
    print(f'\n=== TIMESTAMP COMPARISON ===')
    print(f'Our frame 0: {our_times[0]:.6f} vs GE frame 1: {ge_times[1]:.6f}')
    print(f'Our frame 1: {our_times[1]:.6f} vs GE frame 2: {ge_times[2]:.6f}')
    print(f'Our frame 479: {our_times[479]:.6f} vs GE frame 480: {ge_times[480]:.6f}')
    match = all(abs(our_times[i] - ge_times[i+1]) < 1e-5 for i in range(480))
    print(f'All 480 timestamps match GE[1..480]: {match}')
