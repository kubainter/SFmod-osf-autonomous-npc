"""
Modify standself01.glb to reduce leg/hip motion while preserving upper body animation.
Strategy: blend leg/hip rotation channels toward their rest-pose (first keyframe) value,
reducing amplitude by a factor. Keep translation channels for Root/COM/Hips at zero.
"""
import gzip, struct, json, math, shutil, os

SRC = 'G:/Starfield/Data/SAF/Animations/standself01.glb'
DST_DIR = 'G:/Starfield/Data/OSF/Autonomous/Animations'
DST = os.path.join(DST_DIR, 'solo_standing_touch.glb')

os.makedirs(DST_DIR, exist_ok=True)

# Bones to dampen (reduce rotation amplitude toward rest pose)
# These are the bones that had too much motion in analysis
DAMPEN_ROTATION = {
    # Hips - reduce to 0.05 for clean baseline (procedural sway added separately)
    'C_Hips': 0.05,
    # Thighs - reduce to minimal balance motion
    'R_Thigh': 0.08,       # 31.6° -> ~2.5°
    'L_Thigh': 0.08,       # 25.3° -> ~2.0°
    # Calves - keep very small
    'R_Calf': 0.0,         # already 0°
    'L_Calf': 0.0,         # already 0°
    # Feet - keep minimal
    'R_Foot': 0.1,
    'L_Foot': 0.1,
    'R_Toe': 0.1,
    'L_Toe': 0.1,
    # Thigh twist bones
    'R_Thigh_Twist': 0.1,
    'R_Thigh_Twist1': 0.1,
    'L_Thigh_Twist': 0.1,
    'L_Thigh_Twist1': 0.1,
    # Calf mass / knee
    'R_CalfMass': 0.1,
    'L_CalfMass': 0.1,
    'R_Knee': 0.1,
    'L_Knee': 0.1,
    # Butt
    'L_Butt': 0.1,
    'R_Butt': 0.1,
    'C_Head': 0.35,
    'C_Neck': 0.35,
    'C_Neck1': 0.35,
    # Spine/chest - dampen SAF irregular sway, clean base for procedural breathing
    'C_Spine': 0.15,
    'C_Spine1': 0.15,
    'C_Spine2': 0.15,
    'C_Chest': 0.15,
    # Right arm - dampen SAF walking weight shifts, clean baseline for stimulation circles
    'R_Forearm': 0.0,
    'R_Wrist': 0.05,
}

HEAD_START_DEGREES = {
    'C_Neck': -4.0,
    'C_Neck1': -8.0,
    'C_Head': -20.0,
}

HEAD_LIFT_DEGREES = {
    'C_Neck': -6.0,
    'C_Neck1': -12.0,
    'C_Head': -30.0,
}

HEAD_MOTION_DEGREES = {
    'C_Neck': 2.0,
    'C_Neck1': 4.0,
    'C_Head': 8.0,
}

HEAD_MOTION_PHASE = {
    'C_Neck': 0.0,
    'C_Neck1': 0.12,
    'C_Head': 0.25,
}

# Checkpoint B (Option 1): Full visible breathing + light torso twist
# Pitch (breathing) = local Z, negative = inhale/lift (same convention as head)
# Twist (yaw) = local X
# 5 cycles over 20s = 10π, synchronized with head motion to avoid polyrhythm
# Cumulative pitch: -2.10° (~1.3 cm chest expansion), twist: +0.95° (subtle)
NECK_COUNTER_PITCH = 2.0  # +2.0° forward cancels -2.10° chest pitch propagation to head

# Sensual pelvic sway: full 3D hip motion (pitch + roll + yaw)
# C_Hips local X (axis 0) = sagittal pitch (forward-backward rocking)
# C_Hips local Y (axis 1) = coronal roll (side-to-side lateral tilt)
# C_Hips local Z (axis 2) = transverse yaw (axial twist / wiggle)
# C_Hips is sibling of C_Spine under COM — zero propagation to upper body
# 90° phase offset between pitch and roll creates 3D circular hip roll every 4.0s
HIP_SWAY_PITCH = 2.0       # ±2.0° forward-backward base rock (5 cycles = 10π, 4.0s)
HIP_PULSE_PITCH = 0.4      # ±0.4° fast micro-thrusts (synchronized with hand caress, 30 cycles = 60π)
HIP_SWAY_ROLL = 0.3        # ±0.3° lateral side-to-side tilt (90° phase offset for circular roll)
HIP_SWAY_YAW = 0.15        # ±0.15° transverse twist/wiggle into the circular roll

# Right hand circular stimulation trace
RIGHT_HAND_CYCLES = 10.0     # 10 cycles (20π) over 20s = 2.0s per circle (3 finger strokes per circle)
RIGHT_FOREARM_AMP = 0.6      # ±0.6° subtle forearm rocking compliance
RIGHT_WRIST_AMP = 1.2        # ±1.2° wrist circular massage trace (~1.0-1.4cm fingertip orbit)

TORSO_BREATHING_DEGREES = {
    'C_Spine':  {'pitch': -0.35, 'twist': 0.15},
    'C_Spine1': {'pitch': -0.45, 'twist': 0.25},
    'C_Spine2': {'pitch': -0.55, 'twist': 0.25},
    'C_Chest':  {'pitch': -0.75, 'twist': 0.30},
}

LEFT_ARM_OFFSETS = {
    'L_Clavicle': [-0.01745, 0.00046, -0.05234, 0.99847],
    'L_Biceps': [-0.02617, 0.00069, -0.05234, 0.99828],
    'L_Forearm': [0.0, -0.03490, 0.0, 0.99939],
    'L_Wrist': [0.00046, -0.02617, 0.01745, 0.99951],
}

RIGHT_FINGER_PARAMS = {
    'R_Thumb': (8.0, 3.0, -0.10),
    'R_Index': (16.0, 0.0, 0.0),
    'R_Index1': (20.0, 0.0, 0.0),
    'R_Middle': (14.0, 0.0, 0.10),
    'R_Middle1': (22.0, 0.0, 0.10),
    'R_Ring': (15.0, 0.0, 0.20),
    'R_Ring1': (20.0, 0.0, 0.20),
    'R_Pinky': (9.0, 0.0, 0.30),
    'R_Pinky1': (18.0, 0.0, 0.30),
}

LEFT_FINGER_PARAMS = {
    'L_Thumb': (7.0, 3.0, 0.40),
    'L_Index': (9.0, 0.0, 0.50),
    'L_Index1': (15.0, 0.0, 0.50),
    'L_Index2': (9.0, 0.0, 0.50),
    'L_Middle': (11.0, 0.0, 0.58),
    'L_Middle1': (19.0, 0.0, 0.58),
    'L_Middle2': (11.0, 0.0, 0.58),
    'L_Ring': (9.0, 0.0, 0.66),
    'L_Ring1': (17.0, 0.0, 0.66),
    'L_Ring2': (9.0, 0.0, 0.66),
    'L_Pinky': (7.0, 0.0, 0.74),
    'L_Pinky1': (13.0, 0.0, 0.74),
}

# Bones where we zero out translation entirely (prevent root drift)
ZERO_TRANSLATION = {
    'Root', 'HumanExportRoot', 'COM', 'C_Hips',
    'R_Thigh', 'L_Thigh', 'R_Calf', 'L_Calf',
    'R_Foot', 'L_Foot', 'R_Toe', 'L_Toe',
}

# Read the GLB
with gzip.open(SRC, 'rb') as gz:
    raw = gz.read()

# Parse GLB header
magic, version, total_length = struct.unpack_from('<4sII', raw, 0)
chunk0_len, chunk0_type = struct.unpack_from('<I4s', raw, 12)
chunk0_data = raw[20:20+chunk0_len]
gltf = json.loads(chunk0_data.decode('utf-8'))

# Parse binary chunk
bin_offset = 20 + chunk0_len
bin_len, bin_type = struct.unpack_from('<I4s', raw, bin_offset)
bin_data = bytearray(raw[bin_offset+8:bin_offset+8+bin_len])

# Get animation data
anim = gltf['animations'][0]
channels = anim['channels']
samplers = anim['samplers']
accessors = gltf['accessors']
bufferViews = gltf['bufferViews']
nodes = gltf['nodes']

def read_accessor_data(acc_idx, data):
    acc = accessors[acc_idx]
    bv = bufferViews[acc['bufferView']]
    offset = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
    count = acc['count']
    acc_type = acc['type']
    
    result = []
    for i in range(count):
        if acc_type == 'SCALAR':
            val = struct.unpack_from('<f', data, offset + i*4)[0]
            result.append(val)
        elif acc_type == 'VEC3':
            vals = struct.unpack_from('<3f', data, offset + i*12)
            result.append(list(vals))
        elif acc_type == 'VEC4':
            vals = struct.unpack_from('<4f', data, offset + i*16)
            result.append(list(vals))
    return result, acc_type, offset

def write_accessor_data(acc_idx, values, data):
    acc = accessors[acc_idx]
    bv = bufferViews[acc['bufferView']]
    offset = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
    acc_type = acc['type']
    
    for i, val in enumerate(values):
        if acc_type == 'SCALAR':
            struct.pack_into('<f', data, offset + i*4, val)
        elif acc_type == 'VEC3':
            struct.pack_into('<3f', data, offset + i*12, *val)
        elif acc_type == 'VEC4':
            struct.pack_into('<4f', data, offset + i*16, *val)

def normalize_quaternion(q):
    magnitude = math.sqrt(sum(component * component for component in q))
    return [component / magnitude for component in q]

def multiply_quaternions(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return normalize_quaternion([
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    ])

def axis_rotation_quaternion(axis, degrees):
    half_angle = math.radians(degrees) * 0.5
    sine = math.sin(half_angle)
    components = [0.0, 0.0, 0.0, math.cos(half_angle)]
    components[axis] = sine
    return components

def z_rotation_quaternion(degrees):
    return axis_rotation_quaternion(2, degrees)

# Process each channel
modified_count = 0
for ch in channels:
    node_idx = ch['target']['node']
    node_name = nodes[node_idx].get('name', '')
    path_type = ch['target']['path']
    sampler_idx = ch['sampler']
    sampler = samplers[sampler_idx]

    if path_type == 'rotation' and node_name in RIGHT_FINGER_PARAMS:
        rots, acc_type, _ = read_accessor_data(sampler['output'], bin_data)
        if len(rots) <= 2:
            continue
        times = read_accessor_data(sampler['input'], bin_data)[0]
        duration = times[-1] - times[0] if len(times) > 1 else 0.0
        y_amp, z_amp, phase = RIGHT_FINGER_PARAMS[node_name]
        rest = normalize_quaternion(rots[0])
        previous = None
        for i in range(len(rots)):
            progress = (times[i] - times[0]) / duration if duration > 0 else 0.0
            carrier = 0.5 - 0.5 * math.cos(60.0 * math.pi * progress + phase)
            swell = 0.75 + 0.25 * math.cos(16.0 * math.pi * progress)
            envelope = carrier * swell
            curl_y = y_amp * envelope
            new_rot = multiply_quaternions(rest, axis_rotation_quaternion(1, curl_y))
            if z_amp != 0.0:
                curl_z = z_amp * envelope
                new_rot = multiply_quaternions(new_rot, axis_rotation_quaternion(2, curl_z))
            if previous is not None and sum(new_rot[j] * previous[j] for j in range(4)) < 0:
                new_rot = [-component for component in new_rot]
            rots[i] = new_rot
            previous = new_rot
        write_accessor_data(sampler['output'], rots, bin_data)
        modified_count += 1

    elif path_type == 'rotation' and node_name in LEFT_FINGER_PARAMS:
        rots, acc_type, _ = read_accessor_data(sampler['output'], bin_data)
        if len(rots) <= 2:
            continue
        times = read_accessor_data(sampler['input'], bin_data)[0]
        duration = times[-1] - times[0] if len(times) > 1 else 0.0
        y_amp, z_amp, phase = LEFT_FINGER_PARAMS[node_name]
        rest = normalize_quaternion(rots[0])
        previous = None
        for i in range(len(rots)):
            progress = (times[i] - times[0]) / duration if duration > 0 else 0.0
            envelope = 0.5 - 0.5 * math.cos(14.0 * math.pi * progress + phase)
            curl_y = y_amp * envelope
            new_rot = multiply_quaternions(rest, axis_rotation_quaternion(1, curl_y))
            if z_amp != 0.0:
                curl_z = z_amp * envelope
                new_rot = multiply_quaternions(new_rot, axis_rotation_quaternion(2, curl_z))
            if previous is not None and sum(new_rot[j] * previous[j] for j in range(4)) < 0:
                new_rot = [-component for component in new_rot]
            rots[i] = new_rot
            previous = new_rot
        write_accessor_data(sampler['output'], rots, bin_data)
        modified_count += 1

    elif path_type == 'rotation' and (node_name in DAMPEN_ROTATION or node_name in HEAD_LIFT_DEGREES or node_name in LEFT_ARM_OFFSETS):
        factor = DAMPEN_ROTATION.get(node_name, 1.0)
        rots, acc_type, _ = read_accessor_data(sampler['output'], bin_data)
        times = read_accessor_data(sampler['input'], bin_data)[0]
        rest = rots[0]
        arm_offset = normalize_quaternion(LEFT_ARM_OFFSETS[node_name]) if node_name in LEFT_ARM_OFFSETS else None
        duration = times[-1] - times[0] if len(times) > 1 else 0.0
        previous = None
        for i in range(len(rots)):
            current = rots[i]
            if sum(current[j] * rest[j] for j in range(4)) < 0:
                current = [-component for component in current]
            new_rot = normalize_quaternion([
                rest[j] * (1.0 - factor) + current[j] * factor
                for j in range(4)
            ])
            if node_name in HEAD_LIFT_DEGREES:
                progress = (times[i] - times[0]) / duration if duration > 0 else 0.0
                emotion = 0.5 - 0.5 * math.cos(2.0 * math.pi * progress)
                lift_degrees = HEAD_START_DEGREES[node_name] + (HEAD_LIFT_DEGREES[node_name] - HEAD_START_DEGREES[node_name]) * emotion
                new_rot = multiply_quaternions(new_rot, axis_rotation_quaternion(2, lift_degrees))
            if node_name in HEAD_MOTION_DEGREES:
                phase = 10.0 * math.pi * progress
                motion = -HEAD_MOTION_DEGREES[node_name] * emotion * (0.5 - 0.5 * math.cos(phase + HEAD_MOTION_PHASE[node_name]))
                new_rot = multiply_quaternions(new_rot, axis_rotation_quaternion(2, motion))
            if node_name == 'C_Neck':
                breath_env = 0.5 - 0.5 * math.cos(10.0 * math.pi * progress)
                new_rot = multiply_quaternions(new_rot, axis_rotation_quaternion(2, NECK_COUNTER_PITCH * breath_env))
            if node_name in TORSO_BREATHING_DEGREES:
                progress = (times[i] - times[0]) / duration if duration > 0 else 0.0
                breath_phase = 10.0 * math.pi * progress
                breath_env = 0.5 - 0.5 * math.cos(breath_phase)
                twist_env = math.sin(breath_phase)
                params = TORSO_BREATHING_DEGREES[node_name]
                new_rot = multiply_quaternions(new_rot, axis_rotation_quaternion(2, params['pitch'] * breath_env))
                new_rot = multiply_quaternions(new_rot, axis_rotation_quaternion(0, params['twist'] * twist_env))
            if node_name == 'C_Hips':
                progress = (times[i] - times[0]) / duration if duration > 0 else 0.0
                # Axis 0 (Local X) = Sagittal pitch: slow body wave + hand-synchronized micro-thrusts
                slow_wave = HIP_SWAY_PITCH * math.sin(10.0 * math.pi * progress)
                fast_pulse = HIP_PULSE_PITCH * math.sin(60.0 * math.pi * progress) * (0.75 + 0.25 * math.cos(16.0 * math.pi * progress))
                hip_pitch = slow_wave + fast_pulse
                # Axis 1 (Local Y) = Coronal roll: lateral side-to-side tilt (90° phase offset creates 3D circle)
                hip_roll = HIP_SWAY_ROLL * math.cos(10.0 * math.pi * progress)
                # Axis 2 (Local Z) = Transverse yaw: subtle axial twist swiveling into the turn
                hip_yaw = HIP_SWAY_YAW * math.sin(10.0 * math.pi * progress)
                new_rot = multiply_quaternions(new_rot, axis_rotation_quaternion(0, hip_pitch))
                new_rot = multiply_quaternions(new_rot, axis_rotation_quaternion(1, hip_roll))
                new_rot = multiply_quaternions(new_rot, axis_rotation_quaternion(2, hip_yaw))
            if arm_offset is not None:
                new_rot = multiply_quaternions(new_rot, arm_offset)
                phase = 14.0 * math.pi * (times[i] - times[0]) / duration if duration > 0 else 0.0
                if node_name == 'L_Biceps':
                    new_rot = multiply_quaternions(new_rot, axis_rotation_quaternion(1, 0.5 * math.cos(phase)))
                    new_rot = multiply_quaternions(new_rot, axis_rotation_quaternion(2, 0.7 * math.sin(phase)))
                elif node_name == 'L_Forearm':
                    new_rot = multiply_quaternions(new_rot, axis_rotation_quaternion(1, 1.8 * math.cos(phase)))
                    new_rot = multiply_quaternions(new_rot, axis_rotation_quaternion(2, 1.8 * math.sin(phase)))
                elif node_name == 'L_Wrist':
                    wrist_phase = phase + 0.25
                    new_rot = multiply_quaternions(new_rot, axis_rotation_quaternion(1, 0.8 * math.cos(wrist_phase)))
                    new_rot = multiply_quaternions(new_rot, axis_rotation_quaternion(2, 1.0 * math.sin(wrist_phase)))
            if node_name in ('R_Forearm', 'R_Wrist'):
                progress = (times[i] - times[0]) / duration if duration > 0 else 0.0
                r_phase = RIGHT_HAND_CYCLES * 2.0 * math.pi * progress
                r_swell = 0.75 + 0.25 * math.cos(16.0 * math.pi * progress)
                if node_name == 'R_Forearm':
                    new_rot = multiply_quaternions(new_rot, axis_rotation_quaternion(1, RIGHT_FOREARM_AMP * math.cos(r_phase) * r_swell))
                    new_rot = multiply_quaternions(new_rot, axis_rotation_quaternion(2, RIGHT_FOREARM_AMP * math.sin(r_phase) * r_swell))
                elif node_name == 'R_Wrist':
                    new_rot = multiply_quaternions(new_rot, axis_rotation_quaternion(1, RIGHT_WRIST_AMP * math.cos(r_phase) * r_swell))
                    new_rot = multiply_quaternions(new_rot, axis_rotation_quaternion(2, RIGHT_WRIST_AMP * math.sin(r_phase) * r_swell))
            if previous is not None and sum(new_rot[j] * previous[j] for j in range(4)) < 0:
                new_rot = [-component for component in new_rot]
            rots[i] = new_rot
            previous = new_rot
        
        write_accessor_data(sampler['output'], rots, bin_data)
        modified_count += 1
    
    elif path_type == 'translation' and node_name in ZERO_TRANSLATION:
        trans, acc_type, _ = read_accessor_data(sampler['output'], bin_data)
        if len(trans) <= 1:
            continue
        
        # Set all translations to the first keyframe value (rest pose)
        rest = trans[0]
        for i in range(len(trans)):
            trans[i] = list(rest)
        
        write_accessor_data(sampler['output'], trans, bin_data)
        modified_count += 1

print(f'Modified {modified_count} channels')

# Rebuild GLB
new_json = json.dumps(gltf, separators=(',', ':')).encode('utf-8')
# Pad JSON to 4-byte alignment
while len(new_json) % 4 != 0:
    new_json += b' '

# Pad bin to 4-byte alignment
while len(bin_data) % 4 != 0:
    bin_data.append(0)

new_total = 12 + 8 + len(new_json) + 8 + len(bin_data)
new_glb = struct.pack('<4sII', b'glTF', 2, new_total)
new_glb += struct.pack('<I4s', len(new_json), b'JSON')
new_glb += new_json
new_glb += struct.pack('<I4s', len(bin_data), b'BIN\x00')
new_glb += bytes(bin_data)

# Gzip compress
with gzip.open(DST, 'wb') as gz:
    gz.write(new_glb)

print(f'Written: {DST} ({os.path.getsize(DST)} bytes compressed)')
print(f'Uncompressed size: {len(new_glb)} bytes')
