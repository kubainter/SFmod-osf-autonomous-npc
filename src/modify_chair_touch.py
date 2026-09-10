"""
modify_chair_touch.py — Build solo_chair_touch.glb

Combines seated lower body from GE donor with procedural upper body:
- Lower body: transplanted from Blowjob07-ChairOffice-1.glb (frames 1..480)
- Left arm: HUSH gesture (index finger at lips, other fingers curled)
- Right arm: groin massage with adduction correction from GE seated base
- Breathing: preserved with NECK_COUNTER_PITCH=0.0 (prevents lip-finger drift)
- Head: clamped to -16° recline, motion ±1.2° (backrest + lip contact safety)
- Pelvis: dampened 75% (seated constraint)

Architecture: Full GLB rebuild (not in-place) because lower body bones
need 480-frame data from GE donor but our base only has 2 frames for them.
"""
import gzip, struct, json, math, os, copy

# ============================================================================
# SOURCE FILES
# ============================================================================
OUR_BASE = 'G:/Starfield/Data/OSF/Autonomous/Animations/solo_standing_touch.glb'
GE_DONOR = 'G:/Starfield/Data/SAF/Animations/GE/ChO/Blowjob07-ChairOffice-1.glb'
DST_DIR = 'G:/Starfield/Data/OSF/Autonomous/Animations'
DST = os.path.join(DST_DIR, 'solo_chair_touch.glb')
DST_REF = 'G:/Starfield/StarfieldDev/animation_references/blender_edit/solo_chair_touch.glb'

os.makedirs(DST_DIR, exist_ok=True)
os.makedirs(os.path.dirname(DST_REF), exist_ok=True)

# ============================================================================
# PARAMETERS (validated by AGY kinematic analysis)
# ============================================================================

# --- Lower body bones to transplant from GE donor ---
LOWER_BODY_TRANSPLANT = [
    'C_Hips',
    'R_Thigh', 'L_Thigh',
    'R_Calf', 'L_Calf',
    'R_Foot', 'L_Foot',
    'R_Toe', 'L_Toe',
    'R_Thigh_Twist', 'R_Thigh_Twist1', 'L_Thigh_Twist', 'L_Thigh_Twist1',
    'R_CalfMass', 'L_CalfMass',
    'R_Knee', 'L_Knee',
    'L_Butt', 'R_Butt',
]

# --- Torso + Head: also transplant from GE donor (seated posture) ---
# CRITICAL: HUSH arm quaternions were calculated for seated torso at 10.1° recline.
# If we keep standing torso, the finger-to-lip gap is 11-14cm instead of 3-5mm.
# Head lift from standing touch is also baked in (-17° to -32°) — must use GE seated head.
TORSO_TRANSPLANT = [
    'C_Spine', 'C_Spine1', 'C_Spine2', 'C_Chest',
]

HEAD_TRANSPLANT = [
    'C_Neck', 'C_Neck1', 'C_Head',
]

# --- HUSH gesture: left arm (finger to lips) ---
# Absolute target quaternions from AGY forward kinematics
HUSH_LEFT_ARM_QUATS = {
    'L_Clavicle': [0.84613, -0.07673,  0.51754, -0.10168],
    'L_Biceps':   [0.23075,  0.71623, -0.65685,  0.04812],
    'L_Forearm':  [-0.02646, -0.85241, -0.42422,  0.30453],
    'L_Wrist':    [0.57855, -0.10917, -0.39861,  0.70319],
}

# HUSH left finger pose (degrees around Axis 1 = local Y)
# Index extended straight, middle/ring/pinky curled, thumb clamped
HUSH_LEFT_FINGERS = {
    'L_Index':   -15.0,  # Straighten from rest curve
    'L_Index1':  -30.0,
    'L_Index2':  -15.0,
    'L_Middle':   45.0,  # Curl into palm
    'L_Middle1':  55.0,
    'L_Middle2':  40.0,
    'L_Ring':     45.0,
    'L_Ring1':    50.0,
    'L_Ring2':    40.0,
    'L_Cup':      10.0,  # Palmar cupping
    'L_Pinky':    40.0,
    'L_Pinky1':   45.0,
    'L_Pinky2':   35.0,
    'L_Thumb':    15.0,  # Adduct + flex
    'L_Thumb1':   35.0,
    'L_Thumb2':   25.0,
}

# HUSH thumb also needs Axis 2 adduction
HUSH_LEFT_THUMB_AXIS2 = {
    'L_Thumb': 10.0,
}

# Micro-tremor for hush hand (very subtle, prevents frozen look)
HUSH_TREMOR_AMP = 0.15   # ±0.15°
HUSH_TREMOR_FREQ = 0.5   # 0.5 Hz (very slow breathing-synced)

# --- Right arm: groin massage with adduction correction ---
# GE donor right hand rests on outer thigh (X=0.27m). Need to adduct to groin (X=0.02m).
# Applied as offset quaternions on top of GE seated arm base
RIGHT_ARM_ADDUCTION_EULER = {
    # [axis0_deg, axis1_deg, axis2_deg] offsets from GE donor base
    'R_Biceps':  [-14.0, 13.1, 2.5],    # Adduct medially + forward
    'R_Forearm': [0.0, 13.8, 1.5],      # Flex across lap toward pubic symphysis
    'R_Wrist':   [-0.5, 3.0, -1.1],     # Fine alignment
}

# Right hand circular massage (same parameters as standing touch)
RIGHT_HAND_CYCLES = 10.0      # 10 cycles over 20s = 2.0s per circle
RIGHT_FOREARM_AMP = 0.6       # ±0.6° forearm compliance
RIGHT_WRIST_AMP = 1.2         # ±1.2° wrist circular massage

# Right finger procedural wave (same as standing touch)
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

# --- Torso breathing (same as standing, but NECK_COUNTER_PITCH=0.0) ---
NECK_COUNTER_PITCH = 0.0  # CRITICAL: 0.0 prevents lip-finger drift during breathing

TORSO_BREATHING_DEGREES = {
    'C_Spine':  {'pitch': -0.35, 'twist': 0.15},
    'C_Spine1': {'pitch': -0.45, 'twist': 0.25},
    'C_Spine2': {'pitch': -0.55, 'twist': 0.25},
    'C_Chest':  {'pitch': -0.75, 'twist': 0.30},
}

# --- Head: clamped for chair backrest + lip contact ---
HEAD_START_DEGREES = {
    'C_Neck': -2.0,
    'C_Neck1': -4.0,
    'C_Head': -10.0,
}

HEAD_LIFT_DEGREES = {
    'C_Neck': -2.0,    # Reduced from -6.0 (standing)
    'C_Neck1': -4.0,   # Reduced from -12.0
    'C_Head': -16.0,   # Clamped from -30.0 to -16.0 (backrest safety)
}

HEAD_MOTION_DEGREES = {
    'C_Neck': 0.5,     # Reduced from 2.0 (lip contact: ±1.5° max)
    'C_Neck1': 0.8,    # Reduced from 4.0
    'C_Head': 1.2,     # Reduced from 8.0
}

HEAD_MOTION_PHASE = {
    'C_Neck': 0.0,
    'C_Neck1': 0.12,
    'C_Head': 0.25,
}

# --- Pelvic sway: dampened ~75% for seated constraint ---
HIP_SWAY_PITCH = 0.5       # ±0.5° (was 2.0, -75%)
HIP_PULSE_PITCH = 0.1      # ±0.1° (was 0.4, -75%)
HIP_SWAY_ROLL = 0.08       # ±0.08° (was 0.3, -73%)
HIP_SWAY_YAW = 0.04        # ±0.04° (was 0.15, -73%)

# --- Spine: dampen SAF sway, layer breathing on seated base ---
SPINE_DAMPEN = 0.15  # Same as standing — clean base for procedural breathing

# ============================================================================
# GLB PARSING UTILITIES
# ============================================================================

def parse_glb(path):
    """Parse a gzip-compressed GLB and return (gltf_dict, bin_data)."""
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
    """Read accessor data as list of values."""
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
    """Get animation data for a specific node and path type."""
    anim = gltf['animations'][0]
    nodes = gltf['nodes']
    for ch in anim['channels']:
        if ch['target']['node'] == node_idx and ch['target']['path'] == path_type:
            sampler = anim['samplers'][ch['sampler']]
            times, _ = read_accessor(sampler['input'], gltf, bin_data)
            values, vtype = read_accessor(sampler['output'], gltf, bin_data)
            return times, values
    return None, None

def build_node_map(gltf):
    """Build name -> node_idx map."""
    return {n.get('name', f'node_{i}'): i for i, n in enumerate(gltf['nodes'])}

# ============================================================================
# MATH UTILITIES (same as modify_standself01.py)
# ============================================================================

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

def euler_to_quat(axis0_deg, axis1_deg, axis2_deg):
    """Convert Euler degrees (3 sequential axis rotations) to quaternion."""
    q = [0.0, 0.0, 0.0, 1.0]
    q = multiply_quaternions(q, axis_rotation_quaternion(0, axis0_deg))
    q = multiply_quaternions(q, axis_rotation_quaternion(1, axis1_deg))
    q = multiply_quaternions(q, axis_rotation_quaternion(2, axis2_deg))
    return q

# ============================================================================
# GLB BUILDER
# ============================================================================

class GLBBuilder:
    """Builds a new GLB from scratch with custom animation data."""

    def __init__(self, base_gltf):
        # Copy structural metadata from base
        self.gltf = copy.deepcopy(base_gltf)
        # Remove old animation, accessor, bufferView data
        self.gltf['accessors'] = []
        self.gltf['bufferViews'] = []
        self.gltf['animations'] = []
        self.bin_data = bytearray()
        self.samplers = []
        self.channels = []
        self._time_cache = {}

    def _add_buffer_view(self, data_bytes):
        """Add raw bytes to binary buffer, return bufferView index."""
        offset = len(self.bin_data)
        self.bin_data.extend(data_bytes)
        # Pad to 4-byte alignment
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
        """Add data as a new accessor, return accessor index."""
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
        """Get or create a time accessor with the given frame count."""
        if count in self._time_cache:
            return self._time_cache[count]

        if count == 480:
            # Match our base: t = (i+1)/24 for i=0..479
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
        """Add a rotation channel for a node. rotations = list of [x,y,z,w]."""
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
        """Add a translation channel for a node. translations = list of [x,y,z]."""
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
        """Write the final GLB file (gzip compressed)."""
        # Set up animation
        self.gltf['animations'] = [{
            'samplers': self.samplers,
            'channels': self.channels,
        }]

        # Pad bin to 4-byte alignment
        while len(self.bin_data) % 4 != 0:
            self.bin_data.append(0)

        # Build JSON
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

# Initialize builder
builder = GLBBuilder(our_gltf)

# Time values for 480-frame animation
TIMES_480 = [(i + 1) / 24.0 for i in range(480)]
DURATION = 20.0 - TIMES_480[0]

# Track what we did
transplanted = 0
hush_arm = 0
right_arm = 0
procedural = 0
unchanged = 0

# Process each node in our base (128 nodes)
for node_idx, node in enumerate(our_nodes):
    name = node.get('name', f'node_{node_idx}')

    # Get our base data
    our_times_rot, our_rots = get_channel_data(our_gltf, our_bin, node_idx, 'rotation')
    our_times_trans, our_trans = get_channel_data(our_gltf, our_bin, node_idx, 'translation')

    # Get GE donor data (if bone exists in GE)
    ge_node_idx = ge_map.get(name)
    ge_rots = None
    ge_trans = None
    if ge_node_idx is not None:
        _, ge_rots = get_channel_data(ge_gltf, ge_bin, ge_node_idx, 'rotation')
        _, ge_trans = get_channel_data(ge_gltf, ge_bin, ge_node_idx, 'translation')

    # --- Determine processing for this bone ---
    new_rots = None
    new_trans = None

    # 1. COM — use GE seated position (static 2-frame)
    if name == 'COM':
        if ge_rots is not None:
            new_rots = [normalize_quaternion(r) for r in ge_rots]
        else:
            new_rots = our_rots
        if ge_trans is not None:
            new_trans = [list(t) for t in ge_trans]
        else:
            new_trans = our_trans
        transplanted += 1

    # 2. Lower body — transplant from GE donor
    elif name in LOWER_BODY_TRANSPLANT:
        if ge_rots is not None and len(ge_rots) == 481:
            # Transplant rotation: slice frames 1..480
            new_rots = [normalize_quaternion(ge_rots[i]) for i in range(1, 481)]
        elif ge_rots is not None:
            # GE has only 2 frames — use as static pose
            new_rots = [normalize_quaternion(r) for r in ge_rots]
        else:
            new_rots = our_rots

        if ge_trans is not None and len(ge_trans) == 481:
            new_trans = [list(ge_trans[i]) for i in range(1, 481)]
        elif ge_trans is not None:
            new_trans = [list(t) for t in ge_trans]
        else:
            new_trans = our_trans

        # Zero out translation for lower body (prevent drift)
        if name in ('R_Thigh', 'L_Thigh', 'R_Calf', 'L_Calf',
                    'R_Foot', 'L_Foot', 'R_Toe', 'L_Toe'):
            new_trans = [list(new_trans[0])] * len(new_trans)

        transplanted += 1

    # 3. Torso — STATIC GE seated base (frame 1) + breathing overlay
    # CRITICAL: Use ge_rots[1] (static seated pose), NOT ge_rots[i+1] (animated)
    # GE donor has dynamic torso rocking from the adult scene — we want static seated + our breathing
    elif name in TORSO_TRANSPLANT:
        if ge_rots is not None and len(ge_rots) == 481:
            static_base = normalize_quaternion(ge_rots[1])  # Static seated pose
            new_rots = []
            for i in range(480):
                progress = (TIMES_480[i] - TIMES_480[0]) / DURATION
                rot = static_base
                # Add breathing (same parameters as standing, on seated base)
                if name in TORSO_BREATHING_DEGREES:
                    breath_phase = 10.0 * math.pi * progress
                    breath_env = 0.5 - 0.5 * math.cos(breath_phase)
                    twist_env = math.sin(breath_phase)
                    params = TORSO_BREATHING_DEGREES[name]
                    rot = multiply_quaternions(rot, axis_rotation_quaternion(2, params['pitch'] * breath_env))
                    rot = multiply_quaternions(rot, axis_rotation_quaternion(0, params['twist'] * twist_env))
                new_rots.append(rot)
        elif ge_rots is not None:
            new_rots = [normalize_quaternion(r) for r in ge_rots]
        else:
            new_rots = our_rots
        new_trans = our_trans
        transplanted += 1

    # 4. Head — STATIC GE seated base (frame 1) + small motion only
    # CRITICAL: Use ge_rots[1] (static seated pose), NOT ge_rots[i+1] (animated)
    # GE donor head bobs 33° during the scene — we want static seated head + ±1.2° micro-motion
    elif name in HEAD_TRANSPLANT:
        if ge_rots is not None and len(ge_rots) == 481:
            static_base = normalize_quaternion(ge_rots[1])  # Static seated head pose
            new_rots = []
            for i in range(480):
                progress = (TIMES_480[i] - TIMES_480[0]) / DURATION
                rot = static_base
                # Add very small head motion (±1.2° max for lip contact safety)
                if name in HEAD_MOTION_DEGREES:
                    emotion = 0.5 - 0.5 * math.cos(2.0 * math.pi * progress)
                    phase = 10.0 * math.pi * progress
                    motion = -HEAD_MOTION_DEGREES[name] * emotion * (0.5 - 0.5 * math.cos(phase + HEAD_MOTION_PHASE[name]))
                    rot = multiply_quaternions(rot, axis_rotation_quaternion(2, motion))
                # NECK_COUNTER_PITCH = 0.0 — no counter-pitch (prevents lip drift)
                new_rots.append(rot)
        elif ge_rots is not None:
            new_rots = [normalize_quaternion(r) for r in ge_rots]
        else:
            new_rots = our_rots
        new_trans = our_trans
        transplanted += 1

    # 6. Left arm — HUSH gesture
    elif name in HUSH_LEFT_ARM_QUATS:
        target_quat = normalize_quaternion(HUSH_LEFT_ARM_QUATS[name])
        new_rots = []
        for i in range(480):
            progress = (TIMES_480[i] - TIMES_480[0]) / DURATION
            # Static hush pose + very subtle micro-tremor
            tremor = HUSH_TREMOR_AMP * math.sin(2.0 * math.pi * HUSH_TREMOR_FREQ * progress)
            rot = multiply_quaternions(target_quat, axis_rotation_quaternion(1, tremor))
            # Add tiny breathing-synced sway
            breath = 0.1 * math.sin(10.0 * math.pi * progress)
            rot = multiply_quaternions(rot, axis_rotation_quaternion(2, breath))
            new_rots.append(rot)
        new_trans = our_trans
        hush_arm += 1

    # 7. Left fingers — HUSH pose
    elif name in HUSH_LEFT_FINGERS:
        if our_rots is not None and len(our_rots) > 0:
            rest = normalize_quaternion(our_rots[0])
            curl_deg = HUSH_LEFT_FINGERS[name]
            new_rots = []
            for i in range(480):
                progress = (TIMES_480[i] - TIMES_480[0]) / DURATION
                # Static curl + very subtle tremor
                tremor = 0.5 * math.sin(2.0 * math.pi * HUSH_TREMOR_FREQ * progress)
                rot = multiply_quaternions(rest, axis_rotation_quaternion(1, curl_deg + tremor))
                # Thumb adduction
                if name in HUSH_LEFT_THUMB_AXIS2:
                    rot = multiply_quaternions(rot, axis_rotation_quaternion(2, HUSH_LEFT_THUMB_AXIS2[name]))
                new_rots.append(rot)
            new_trans = our_trans
            hush_arm += 1
        else:
            new_rots = our_rots
            new_trans = our_trans
            unchanged += 1

    # 8. Right arm — GE seated base + adduction + procedural massage
    elif name in RIGHT_ARM_ADDUCTION_EULER:
        # Get GE donor seated arm base
        if ge_rots is not None and len(ge_rots) == 481:
            base_rots = [normalize_quaternion(ge_rots[i]) for i in range(1, 481)]
        elif ge_rots is not None:
            base_rots = [normalize_quaternion(r) for r in ge_rots]
        else:
            # Fallback: our base (standing) — expand to 480 if needed
            if our_rots and len(our_rots) == 480:
                base_rots = [normalize_quaternion(r) for r in our_rots]
            else:
                base_rots = [normalize_quaternion(our_rots[0])] * 480

        # Adduction offset
        adduction = RIGHT_ARM_ADDUCTION_EULER[name]
        adduction_quat = euler_to_quat(adduction[0], adduction[1], adduction[2])

        new_rots = []
        for i in range(480):
            progress = (TIMES_480[i] - TIMES_480[0]) / DURATION
            # Apply adduction
            rot = multiply_quaternions(base_rots[i], adduction_quat)

            # Procedural massage
            r_phase = RIGHT_HAND_CYCLES * 2.0 * math.pi * progress
            r_swell = 0.75 + 0.25 * math.cos(16.0 * math.pi * progress)
            if name == 'R_Forearm':
                rot = multiply_quaternions(rot, axis_rotation_quaternion(1, RIGHT_FOREARM_AMP * math.cos(r_phase) * r_swell))
                rot = multiply_quaternions(rot, axis_rotation_quaternion(2, RIGHT_FOREARM_AMP * math.sin(r_phase) * r_swell))
            elif name == 'R_Wrist':
                rot = multiply_quaternions(rot, axis_rotation_quaternion(1, RIGHT_WRIST_AMP * math.cos(r_phase) * r_swell))
                rot = multiply_quaternions(rot, axis_rotation_quaternion(2, RIGHT_WRIST_AMP * math.sin(r_phase) * r_swell))
            new_rots.append(rot)
        new_trans = our_trans
        right_arm += 1

    # 9. Right fingers — procedural wave (same as standing)
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

    # 10. R_Clavicle, R_Biceps — use GE seated base (part of right arm positioning)
    elif name in ('R_Clavicle', 'R_Biceps'):
        if ge_rots is not None and len(ge_rots) == 481:
            new_rots = [normalize_quaternion(ge_rots[i]) for i in range(1, 481)]
        elif ge_rots is not None:
            new_rots = [normalize_quaternion(r) for r in ge_rots]
        else:
            new_rots = our_rots
        new_trans = our_trans
        right_arm += 1

    # 11. L_Clavicle is in HUSH_LEFT_ARM_QUATS, already handled above

    # 12. Everything else — keep our base data unchanged
    else:
        new_rots = our_rots
        new_trans = our_trans
        unchanged += 1

    # Add channels to builder
    if new_rots is not None:
        builder.add_rotation_channel(node_idx, new_rots)
    if new_trans is not None:
        builder.add_translation_channel(node_idx, new_trans)

# ============================================================================
# POST-PROCESS: Add pelvic sway to C_Hips (which was transplanted from GE)
# ============================================================================
# C_Hips was transplanted in the LOWER_BODY_TRANSPLANT section.
# We need to find its channel and add procedural sway on top.
# Actually, let me handle C_Hips separately by restructuring...
# For now, the transplanted C_Hips rotation is the GE seated baseline.
# We need to add the dampened pelvic sway.

# Find C_Hips rotation channel and modify
c_hips_node_idx = our_map.get('C_Hips')
if c_hips_node_idx is not None:
    # Re-process C_Hips with pelvic sway
    # Get the transplanted data from GE
    ge_hips_idx = ge_map.get('C_Hips')
    if ge_hips_idx is not None:
        _, ge_hips_rots = get_channel_data(ge_gltf, ge_bin, ge_hips_idx, 'rotation')
        if ge_hips_rots and len(ge_hips_rots) == 481:
            # Take GE frames 1..480 as base, add dampened sway
            new_hips_rots = []
            for i in range(480):
                progress = (TIMES_480[i] - TIMES_480[0]) / DURATION
                base_rot = normalize_quaternion(ge_hips_rots[i + 1])
                # Dampened pelvic sway
                slow_wave = HIP_SWAY_PITCH * math.sin(10.0 * math.pi * progress)
                fast_pulse = HIP_PULSE_PITCH * math.sin(60.0 * math.pi * progress) * (0.75 + 0.25 * math.cos(16.0 * math.pi * progress))
                hip_pitch = slow_wave + fast_pulse
                hip_roll = HIP_SWAY_ROLL * math.cos(10.0 * math.pi * progress)
                hip_yaw = HIP_SWAY_YAW * math.sin(10.0 * math.pi * progress)
                rot = multiply_quaternions(base_rot, axis_rotation_quaternion(0, hip_pitch))
                rot = multiply_quaternions(rot, axis_rotation_quaternion(1, hip_roll))
                rot = multiply_quaternions(rot, axis_rotation_quaternion(2, hip_yaw))
                new_hips_rots.append(rot)

            # Find and replace the C_Hips rotation channel
            for ch in builder.channels:
                if ch['target']['node'] == c_hips_node_idx and ch['target']['path'] == 'rotation':
                    # Replace the output accessor data
                    sampler = builder.samplers[ch['sampler']]
                    acc_idx = sampler['output']
                    acc = builder.gltf['accessors'][acc_idx]
                    bv = builder.gltf['bufferViews'][acc['bufferView']]
                    offset = bv['byteOffset']
                    # Write new data
                    for j, rot in enumerate(new_hips_rots):
                        struct.pack_into('<4f', builder.bin_data, offset + j * 16, *rot)
                    break
            print(f'  C_Hips: added dampened pelvic sway on GE seated base')

# ============================================================================
# BUILD OUTPUT
# ============================================================================

print(f'\nProcessing summary:')
print(f'  Transplanted from GE: {transplanted}')
print(f'  HUSH left arm: {hush_arm}')
print(f'  Right arm/fingers: {right_arm}')
print(f'  Procedural (spine/head): {procedural}')
print(f'  Unchanged: {unchanged}')
print(f'  Total channels: {len(builder.channels)}')

# Write compressed (game) version
compressed_size = builder.build(DST)
print(f'\nWritten (compressed): {DST} ({compressed_size} bytes)')

# Write uncompressed (Blender reference) version
import struct as s
new_json = json.dumps(builder.gltf, separators=(',', ':')).encode('utf-8')
while len(new_json) % 4 != 0:
    new_json += b' '
while len(builder.bin_data) % 4 != 0:
    builder.bin_data.append(0)
new_total = 12 + 8 + len(new_json) + 8 + len(builder.bin_data)
ref_glb = s.pack('<4sII', b'glTF', 2, new_total)
ref_glb += s.pack('<I4s', len(new_json), b'JSON')
ref_glb += new_json
ref_glb += s.pack('<I4s', len(builder.bin_data), b'BIN\x00')
ref_glb += bytes(builder.bin_data)
with open(DST_REF, 'wb') as f:
    f.write(ref_glb)
print(f'Written (reference): {DST_REF} ({os.path.getsize(DST_REF)} bytes)')
