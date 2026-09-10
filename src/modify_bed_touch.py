"""
modify_bed_touch.py — Build solo_bed_touch.glb

Supine female actor on DoubleBed:
- Lower body + torso + head: static Frame 1 from Missionary01-DoubleBed-2.glb (lying on back)
- Left arm: HUSH gesture (index finger at lips, adjusted for supine pose)
- Right arm: standing-touch procedural groin massage (NO adduction offset needed)
- Breathing: NECK_COUNTER_PITCH=0.0 (same as chair)
- Head: static from donor + small motion ±1.2°
- 480 frames / 20s (NOT 300 — donor has 300 but we use only Frame 1 as static base)

Architecture: Same as chair — GLBBuilder rebuild with static donor pose + procedural harmonics.
Simpler than chair: no adduction offset, no backrest clearance, no pelvic sway dampening.
"""
import gzip, struct, json, math, os, copy

# ============================================================================
# SOURCE FILES
# ============================================================================
OUR_BASE = 'G:/Starfield/Data/OSF/Autonomous/Animations/solo_standing_touch.glb'
GE_DONOR = 'G:/Starfield/Data/SAF/Animations/GE/Dbd/Missionary01-DoubleBed-2.glb'
DST_DIR = 'G:/Starfield/Data/OSF/Autonomous/Animations'
DST = os.path.join(DST_DIR, 'solo_bed_touch.glb')
DST_REF = 'G:/Starfield/StarfieldDev/animation_references/blender_edit/solo_bed_touch.glb'

os.makedirs(DST_DIR, exist_ok=True)
os.makedirs(os.path.dirname(DST_REF), exist_ok=True)

# ============================================================================
# PARAMETERS (validated by AGY kinematic analysis for supine pose)
# ============================================================================

# --- All bones to transplant as STATIC from donor Frame 1 ---
# Donor is lying on back (C_Hips 180° pitch). Use Frame 1 as static pose.
# NO animated transplant — donor has coital motion (kicking, thrashing) unsuitable for solo.
SUPINE_TRANSPLANT = [
    'COM',
    'C_Hips',
    'C_Spine', 'C_Spine1', 'C_Spine2', 'C_Chest',
    'C_Neck', 'C_Neck1', 'C_Head',
    'R_Thigh', 'L_Thigh',
    'R_Calf', 'L_Calf',
    'R_Foot', 'L_Foot',
    'R_Toe', 'L_Toe',
    'R_Thigh_Twist', 'R_Thigh_Twist1', 'L_Thigh_Twist', 'L_Thigh_Twist1',
    'R_CalfMass', 'L_CalfMass',
    'R_Knee', 'L_Knee',
    'L_Butt', 'R_Butt',
    'C_Waist',
]

# --- HUSH gesture: left arm (finger to lips) for SUPINE pose ---
# Adjusted by AGY: head is 6.9cm further headward than chair
# Lip gap: 1.62mm, elbow clears mattress by +6.9cm
HUSH_LEFT_ARM_QUATS = {
    'L_Clavicle': [0.84613, -0.07673,  0.51754, -0.10168],  # Same as chair
    'L_Biceps':   [0.01671,  0.67707, -0.72383, -0.13177],  # Elevate headward
    'L_Forearm':  [0.03653, -0.79803, -0.42347,  0.42718],  # Reduce flexion +17°
    'L_Wrist':    [0.59539, -0.07839, -0.37299,  0.70728],  # Fine pitch +5°
}

# HUSH left finger pose (same as chair — finger curl doesn't change with body pose)
HUSH_LEFT_FINGERS = {
    'L_Index':   -15.0,
    'L_Index1':  -30.0,
    'L_Index2':  -15.0,
    'L_Middle':   45.0,
    'L_Middle1':  55.0,
    'L_Middle2':  40.0,
    'L_Ring':     45.0,
    'L_Ring1':    50.0,
    'L_Ring2':    40.0,
    'L_Cup':      10.0,
    'L_Pinky':    40.0,
    'L_Pinky1':   45.0,
    'L_Pinky2':   35.0,
    'L_Thumb':    15.0,
    'L_Thumb1':   35.0,
    'L_Thumb2':   25.0,
}

HUSH_LEFT_THUMB_AXIS2 = {
    'L_Thumb': 10.0,
}

HUSH_TREMOR_AMP = 0.15
HUSH_TREMOR_FREQ = 0.5

# --- Right arm: standing-touch procedural (NO adduction offset for bed) ---
# AGY verified: standing right arm naturally falls to groin when supine
# R_Wrist world: [0.120, 0.089, 0.724] — directly over pubic mound
# NO adduction offset needed (unlike chair which had -14°/+13.1°/+2.5°)
# Use our base standing-touch right arm directly
RIGHT_ARM_USE_STANDING = True  # Use our base right arm, not GE donor

RIGHT_HAND_CYCLES = 10.0
RIGHT_FOREARM_AMP = 0.6
RIGHT_WRIST_AMP = 1.2

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

# --- Torso breathing (same as chair/standing) ---
NECK_COUNTER_PITCH = 0.0

TORSO_BREATHING_DEGREES = {
    'C_Spine':  {'pitch': -0.35, 'twist': 0.15},
    'C_Spine1': {'pitch': -0.45, 'twist': 0.25},
    'C_Spine2': {'pitch': -0.55, 'twist': 0.25},
    'C_Chest':  {'pitch': -0.75, 'twist': 0.30},
}

# --- Head: small motion only (no backrest concern, but lip contact) ---
HEAD_MOTION_DEGREES = {
    'C_Neck': 0.5,
    'C_Neck1': 0.8,
    'C_Head': 1.2,
}

HEAD_MOTION_PHASE = {
    'C_Neck': 0.0,
    'C_Neck1': 0.12,
    'C_Head': 0.25,
}

# --- Pelvic sway: very subtle for bed (lying down, less natural sway) ---
HIP_SWAY_PITCH = 0.3
HIP_PULSE_PITCH = 0.06
HIP_SWAY_ROLL = 0.05
HIP_SWAY_YAW = 0.03

# ============================================================================
# GLB PARSING UTILITIES (same as chair)
# ============================================================================

def parse_glb(path):
    with gzip.open(path, 'rb') as gz:
        raw = gz.read()
    magic, version, total_length = struct.unpack_from('<4sII', raw, 0)
    chunk0_len, chunk0_type = struct.unpack_from('<I4s', raw, 12)
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

def get_channel_data(gltf, bin_data, node_idx, path_type):
    anim = gltf['animations'][0]
    for ch in anim['channels']:
        if ch['target']['node'] == node_idx and ch['target']['path'] == path_type:
            sampler = anim['samplers'][ch['sampler']]
            times, _ = read_accessor(sampler['input'], gltf, bin_data)
            values, vtype = read_accessor(sampler['output'], gltf, bin_data)
            return times, values
    return None, None

def build_node_map(gltf):
    return {n.get('name', f'node_{i}'): i for i, n in enumerate(gltf['nodes'])}

def normalize_quaternion(q):
    magnitude = math.sqrt(sum(c * c for c in q))
    return [c / magnitude for c in q]

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

# ============================================================================
# GLB BUILDER (same as chair)
# ============================================================================

class GLBBuilder:
    def __init__(self, base_gltf):
        self.gltf = copy.deepcopy(base_gltf)
        self.gltf['accessors'] = []
        self.gltf['bufferViews'] = []
        self.gltf['animations'] = []
        self.bin_data = bytearray()
        self.samplers = []
        self.channels = []
        self._time_cache = {}

    def _add_buffer_view(self, data_bytes):
        offset = len(self.bin_data)
        self.bin_data.extend(data_bytes)
        while len(self.bin_data) % 4 != 0:
            self.bin_data.append(0)
        bv_idx = len(self.gltf['bufferViews'])
        self.gltf['bufferViews'].append({
            'buffer': 0,
            'byteOffset': offset,
            'byteLength': len(data_bytes),
        })
        return bv_idx

    def _add_accessor(self, data, component_type, type_str):
        count = len(data)
        if type_str == 'SCALAR':
            data_bytes = b''.join(struct.pack('<f', v) for v in data)
        elif type_str == 'VEC3':
            data_bytes = b''.join(struct.pack('<3f', *v) for v in data)
        elif type_str == 'VEC4':
            data_bytes = b''.join(struct.pack('<4f', *v) for v in data)
        else:
            raise ValueError(f'Unsupported type: {type_str}')
        bv_idx = self._add_buffer_view(data_bytes)
        acc_idx = len(self.gltf['accessors'])
        self.gltf['accessors'].append({
            'bufferView': bv_idx,
            'componentType': component_type,
            'count': count,
            'type': type_str,
        })
        return acc_idx

    def get_time_accessor(self, count):
        if count in self._time_cache:
            return self._time_cache[count]
        if count == 480:
            times = [(i + 1) / 24.0 for i in range(480)]
        elif count == 2:
            times = [1.0/24.0, 20.0]
        elif count == 1:
            times = [1.0/24.0]
        else:
            times = [(i + 1) / 24.0 for i in range(count)]
        acc_idx = self._add_accessor(times, 5126, 'SCALAR')
        self._time_cache[count] = acc_idx
        return acc_idx

    def add_rotation_channel(self, node_idx, rotations):
        count = len(rotations)
        time_acc = self.get_time_accessor(count)
        rot_acc = self._add_accessor(rotations, 5126, 'VEC4')
        sampler_idx = len(self.samplers)
        self.samplers.append({'input': time_acc, 'output': rot_acc, 'interpolation': 'LINEAR'})
        self.channels.append({
            'sampler': sampler_idx,
            'target': {'node': node_idx, 'path': 'rotation'}
        })

    def add_translation_channel(self, node_idx, translations):
        count = len(translations)
        time_acc = self.get_time_accessor(count)
        trans_acc = self._add_accessor(translations, 5126, 'VEC3')
        sampler_idx = len(self.samplers)
        self.samplers.append({'input': time_acc, 'output': trans_acc, 'interpolation': 'LINEAR'})
        self.channels.append({
            'sampler': sampler_idx,
            'target': {'node': node_idx, 'path': 'translation'}
        })

    def build(self, dst_path):
        self.gltf['animations'] = [{'samplers': self.samplers, 'channels': self.channels}]
        while len(self.bin_data) % 4 != 0:
            self.bin_data.append(0)
        new_json = json.dumps(self.gltf, separators=(',', ':')).encode('utf-8')
        while len(new_json) % 4 != 0:
            new_json += b' '
        new_total = 12 + 8 + len(new_json) + 8 + len(self.bin_data)
        new_glb = struct.pack('<4sII', b'glTF', 2, new_total)
        new_glb += struct.pack('<I4s', len(new_json), b'JSON')
        new_glb += new_json
        new_glb += struct.pack('<I4s', len(self.bin_data), b'BIN\x00')
        new_glb += bytes(self.bin_data)
        with gzip.open(dst_path, 'wb') as gz:
            gz.write(new_glb)
        return os.path.getsize(dst_path)

# ============================================================================
# MAIN BUILD LOGIC
# ============================================================================

print('Parsing source GLBs...')
our_gltf, our_bin = parse_glb(OUR_BASE)
ge_gltf, ge_bin = parse_glb(GE_DONOR)

our_nodes = our_gltf['nodes']
our_map = build_node_map(our_gltf)
ge_map = build_node_map(ge_gltf)

print(f'  Our base: {len(our_nodes)} nodes')
print(f'  GE donor: {len(ge_gltf["nodes"])} nodes')

builder = GLBBuilder(our_gltf)
TIMES_480 = [(i + 1) / 24.0 for i in range(480)]
DURATION = 20.0 - TIMES_480[0]

transplanted = 0
hush_arm = 0
right_arm = 0
procedural = 0
unchanged = 0

for node_idx, node in enumerate(our_nodes):
    name = node.get('name', f'node_{node_idx}')

    our_times_rot, our_rots = get_channel_data(our_gltf, our_bin, node_idx, 'rotation')
    our_times_trans, our_trans = get_channel_data(our_gltf, our_bin, node_idx, 'translation')

    ge_node_idx = ge_map.get(name)
    ge_rots = None
    ge_trans = None
    if ge_node_idx is not None:
        _, ge_rots = get_channel_data(ge_gltf, ge_bin, ge_node_idx, 'rotation')
        _, ge_trans = get_channel_data(ge_gltf, ge_bin, ge_node_idx, 'translation')

    new_rots = None
    new_trans = None

    # 1. Supine transplant — static Frame 1 from donor + breathing/motion overlay
    if name in SUPINE_TRANSPLANT:
        if ge_rots is not None and len(ge_rots) > 0:
            static_base = normalize_quaternion(ge_rots[0])  # Frame 1 (0-indexed)
            new_rots = []
            for i in range(480):
                progress = (TIMES_480[i] - TIMES_480[0]) / DURATION
                rot = static_base

                # Add breathing to torso
                if name in TORSO_BREATHING_DEGREES:
                    breath_phase = 10.0 * math.pi * progress
                    breath_env = 0.5 - 0.5 * math.cos(breath_phase)
                    twist_env = math.sin(breath_phase)
                    params = TORSO_BREATHING_DEGREES[name]
                    rot = multiply_quaternions(rot, axis_rotation_quaternion(2, params['pitch'] * breath_env))
                    rot = multiply_quaternions(rot, axis_rotation_quaternion(0, params['twist'] * twist_env))

                # Add head motion
                if name in HEAD_MOTION_DEGREES:
                    emotion = 0.5 - 0.5 * math.cos(2.0 * math.pi * progress)
                    phase = 10.0 * math.pi * progress
                    motion = -HEAD_MOTION_DEGREES[name] * emotion * (0.5 - 0.5 * math.cos(phase + HEAD_MOTION_PHASE[name]))
                    rot = multiply_quaternions(rot, axis_rotation_quaternion(2, motion))

                # Add pelvic sway to C_Hips
                if name == 'C_Hips':
                    slow_wave = HIP_SWAY_PITCH * math.sin(10.0 * math.pi * progress)
                    fast_pulse = HIP_PULSE_PITCH * math.sin(60.0 * math.pi * progress) * (0.75 + 0.25 * math.cos(16.0 * math.pi * progress))
                    hip_pitch = slow_wave + fast_pulse
                    hip_roll = HIP_SWAY_ROLL * math.cos(10.0 * math.pi * progress)
                    hip_yaw = HIP_SWAY_YAW * math.sin(10.0 * math.pi * progress)
                    rot = multiply_quaternions(rot, axis_rotation_quaternion(0, hip_pitch))
                    rot = multiply_quaternions(rot, axis_rotation_quaternion(1, hip_roll))
                    rot = multiply_quaternions(rot, axis_rotation_quaternion(2, hip_yaw))

                new_rots.append(rot)
        else:
            new_rots = our_rots

        # Translation: use donor COM, zero out others to prevent drift
        if name == 'COM' and ge_trans is not None:
            new_trans = [list(ge_trans[0])] * 2  # Static 2-frame
        elif name in SUPINE_TRANSPLANT and ge_trans is not None:
            new_trans = [list(ge_trans[0])] * 2  # Static
        else:
            new_trans = our_trans

        transplanted += 1

    # 2. Left arm — HUSH gesture (supine quaternions)
    elif name in HUSH_LEFT_ARM_QUATS:
        target_quat = normalize_quaternion(HUSH_LEFT_ARM_QUATS[name])
        new_rots = []
        for i in range(480):
            progress = (TIMES_480[i] - TIMES_480[0]) / DURATION
            tremor = HUSH_TREMOR_AMP * math.sin(2.0 * math.pi * HUSH_TREMOR_FREQ * progress)
            rot = multiply_quaternions(target_quat, axis_rotation_quaternion(1, tremor))
            breath = 0.1 * math.sin(10.0 * math.pi * progress)
            rot = multiply_quaternions(rot, axis_rotation_quaternion(2, breath))
            new_rots.append(rot)
        new_trans = our_trans
        hush_arm += 1

    # 3. Left fingers — HUSH pose
    elif name in HUSH_LEFT_FINGERS:
        if our_rots is not None and len(our_rots) > 0:
            rest = normalize_quaternion(our_rots[0])
            curl_deg = HUSH_LEFT_FINGERS[name]
            new_rots = []
            for i in range(480):
                progress = (TIMES_480[i] - TIMES_480[0]) / DURATION
                tremor = 0.5 * math.sin(2.0 * math.pi * HUSH_TREMOR_FREQ * progress)
                rot = multiply_quaternions(rest, axis_rotation_quaternion(1, curl_deg + tremor))
                if name in HUSH_LEFT_THUMB_AXIS2:
                    rot = multiply_quaternions(rot, axis_rotation_quaternion(2, HUSH_LEFT_THUMB_AXIS2[name]))
                new_rots.append(rot)
            new_trans = our_trans
            hush_arm += 1
        else:
            new_rots = our_rots
            new_trans = our_trans
            unchanged += 1

    # 4. Right arm — standing-touch procedural (NO adduction for bed)
    # R_Clavicle, R_Biceps: use our base standing values
    # R_Forearm, R_Wrist: use our base + procedural massage
    elif name in ('R_Clavicle', 'R_Biceps', 'R_Forearm', 'R_Wrist'):
        if our_rots is not None and len(our_rots) > 0:
            # Handle both 480-frame and 2-frame (static) base channels
            if len(our_rots) == 480:
                base_rot = normalize_quaternion(our_rots[0])
            else:
                base_rot = normalize_quaternion(our_rots[0])
            new_rots = []
            for i in range(480):
                progress = (TIMES_480[i] - TIMES_480[0]) / DURATION
                # Start from standing base (no adduction offset needed for bed)
                # If 480-frame, use animated base; if 2-frame, use static
                if len(our_rots) == 480:
                    rot = normalize_quaternion(our_rots[i])
                else:
                    rot = base_rot

                # Procedural massage on forearm and wrist
                r_phase = RIGHT_HAND_CYCLES * 2.0 * math.pi * progress
                r_swell = 0.75 + 0.25 * math.cos(16.0 * math.pi * progress)
                if name == 'R_Forearm':
                    rot = multiply_quaternions(rot, axis_rotation_quaternion(1, RIGHT_FOREARM_AMP * math.cos(r_phase) * r_swell))
                    rot = multiply_quaternions(rot, axis_rotation_quaternion(2, RIGHT_FOREARM_AMP * math.sin(r_phase) * r_swell))
                elif name == 'R_Wrist':
                    rot = multiply_quaternions(rot, axis_rotation_quaternion(1, RIGHT_WRIST_AMP * math.cos(r_phase) * r_swell))
                    rot = multiply_quaternions(rot, axis_rotation_quaternion(2, RIGHT_WRIST_AMP * math.sin(r_phase) * r_swell))

                new_rots.append(rot)
        else:
            new_rots = our_rots
        new_trans = our_trans
        right_arm += 1

    # 5. Right fingers — procedural wave (same as standing/chair)
    elif name in RIGHT_FINGER_PARAMS:
        if our_rots is not None and len(our_rots) > 2:
            rest = normalize_quaternion(our_rots[0])
            y_amp, z_amp, phase_offset = RIGHT_FINGER_PARAMS[name]
            new_rots = []
            for i in range(480):
                progress = (TIMES_480[i] - TIMES_480[0]) / DURATION
                carrier = 0.5 - 0.5 * math.cos(60.0 * math.pi * progress + phase_offset)
                swell = 0.75 + 0.25 * math.cos(16.0 * math.pi * progress)
                envelope = carrier * swell
                curl_y = y_amp * envelope
                rot = multiply_quaternions(rest, axis_rotation_quaternion(1, curl_y))
                if z_amp != 0.0:
                    rot = multiply_quaternions(rot, axis_rotation_quaternion(2, z_amp * envelope))
                new_rots.append(rot)
        else:
            new_rots = our_rots
        new_trans = our_trans
        right_arm += 1

    # 6. Everything else — keep our base unchanged
    else:
        new_rots = our_rots
        new_trans = our_trans
        unchanged += 1

    if new_rots is not None:
        builder.add_rotation_channel(node_idx, new_rots)
    if new_trans is not None:
        builder.add_translation_channel(node_idx, new_trans)

# ============================================================================
# BUILD OUTPUT
# ============================================================================

print(f'\nProcessing summary:')
print(f'  Supine transplant: {transplanted}')
print(f'  HUSH left arm: {hush_arm}')
print(f'  Right arm/fingers: {right_arm}')
print(f'  Unchanged: {unchanged}')
print(f'  Total channels: {len(builder.channels)}')

compressed_size = builder.build(DST)
print(f'\nWritten (compressed): {DST} ({compressed_size} bytes)')

# Uncompressed reference for Blender
new_json = json.dumps(builder.gltf, separators=(',', ':')).encode('utf-8')
while len(new_json) % 4 != 0:
    new_json += b' '
while len(builder.bin_data) % 4 != 0:
    builder.bin_data.append(0)
new_total = 12 + 8 + len(new_json) + 8 + len(builder.bin_data)
ref_glb = struct.pack('<4sII', b'glTF', 2, new_total)
ref_glb += struct.pack('<I4s', len(new_json), b'JSON')
ref_glb += new_json
ref_glb += struct.pack('<I4s', len(builder.bin_data), b'BIN\x00')
ref_glb += bytes(builder.bin_data)
with open(DST_REF, 'wb') as f:
    f.write(ref_glb)
print(f'Written (reference): {DST_REF} ({os.path.getsize(DST_REF)} bytes)')
