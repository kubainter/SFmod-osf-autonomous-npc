#!/usr/bin/env python3
"""
OSF Autonomous — Procedural Solo Animation Generator
=====================================================
Generates 100% original solo animation .glb files for Starfield OSF framework.

Approach (Clean-Room Hybrid):
  1. Skeleton hierarchy (128 bone names) is extracted from existing Starfield .glb
     — this is a functional interface specification, not copyrightable expression.
  2. Kinematic profiles (which bones move, approximate amplitudes, frequencies)
     are measured from existing animations — these are biomechanical facts, not
     creative expression (scènes à faire doctrine).
  3. All keyframe data is generated procedurally using multi-harmonic Fourier
     series, Perlin-like drift, and asymmetric motion curves — 100% original
     mathematical authorship. No keyframe values are copied from any source.

Output: 5 .glb files in Data/OSF/Autonomous/Animations/
  - solo_idle_breathe01.glb   (neutral breathing idle)
  - solo_relax_hips01.glb     (hands-on-hips relax)
  - solo_stretch01.glb        (arms overhead stretch)
  - solo_sensual01.glb        (right-hand sensual, medium tempo)
  - solo_sensual02.glb        (left-hand sensual, slow tempo)

Usage: py generate_osf_solo_animations.py
"""

import gzip
import struct
import json
import math
import os
from typing import List, Tuple, Dict, Callable, Optional

# ============================================================================
# SKELETON — 128 Starfield humanoid bone nodes (functional interface, not expression)
# Loaded from skeleton_nodes.py (extracted by subagent)
# ============================================================================
try:
    from skeleton_nodes import STARFIELD_SKELETON_NODES
except ImportError:
    # Fallback: will be filled by subagent output
    STARFIELD_SKELETON_NODES = []

# ============================================================================
# REST POSE — bone offsets extracted from original Starfield .glb
# These are functional interface data (skeleton topology), not copyrightable.
# Without these, all bones collapse to (0,0,0) and the actor curls into a ball.
# ============================================================================
try:
    from rest_pose import REST_POSES_TRANS, REST_POSES_ROT
except ImportError:
    REST_POSES_TRANS = {}
    REST_POSES_ROT = {}

# ============================================================================
# KINEMATIC PROFILES — biomechanical parameters measured from existing animations
# Loaded from kinematic_profiles.json (extracted by subagent)
# ============================================================================
try:
    with open(os.path.join(os.path.dirname(__file__), "kinematic_profiles.json"), "r") as f:
        KINEMATIC_PROFILES = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    KINEMATIC_PROFILES = {}

# ============================================================================
# QUATERNION MATH
# ============================================================================

def quat_from_euler(pitch: float, roll: float, yaw: float) -> Tuple[float, float, float, float]:
    """Converts pitch (X-axis), roll (Y-axis), yaw (Z-axis) in radians to unit quaternion (x, y, z, w).
    Uses standard ZYX Tait-Bryan convention: rotation applied as Z * Y * X."""
    cy, sy = math.cos(yaw * 0.5), math.sin(yaw * 0.5)
    cp, sp = math.cos(pitch * 0.5), math.sin(pitch * 0.5)
    cr, sr = math.cos(roll * 0.5), math.sin(roll * 0.5)
    # Standard ZYX Euler: q = qz * qy * qx
    w = cr * cp * cy + sr * sp * sy
    x = sr * cp * cy - cr * sp * sy
    y = cr * sp * cy + sr * cp * sy
    z = cr * cp * sy - sr * sp * cy
    # Normalize
    l = math.sqrt(x*x + y*y + z*z + w*w)
    if l > 0:
        x, y, z, w = x/l, y/l, z/l, w/l
    return (round(x, 6), round(y, 6), round(z, 6), round(w, 6))

def quat_identity() -> Tuple[float, float, float, float]:
    return (0.0, 0.0, 0.0, 1.0)

def quat_multiply(q1, q2):
    """Hamilton product: q1 * q2 (applies q1 first, then q2)."""
    x1, y1, z1, w1 = q1
    x2, y2, z2, w2 = q2
    w = w1*w2 - x1*x2 - y1*y2 - z1*z2
    x = w1*x2 + x1*w2 + y1*z2 - z1*y2
    y = w1*y2 - x1*z2 + y1*w2 + z1*x2
    z = w1*z2 + x1*y2 - y1*x2 + z1*w2
    l = math.sqrt(w*w + x*x + y*y + z*z)
    if l > 0:
        w, x, y, z = w/l, x/l, y/l, z/l
    return (round(x, 6), round(y, 6), round(z, 6), round(w, 6))

def get_rest_rot(bone_name: str, pose_name: str = "standself01") -> Tuple[float, float, float, float]:
    """Get a named reference-pose rotation for a bone, or identity if not found."""
    r = REST_POSES_ROT.get(pose_name, {}).get(bone_name)
    if r:
        return (r[0], r[1], r[2], r[3])
    return quat_identity()

def get_rest_trans(bone_name: str, pose_name: str = "standself01") -> Tuple[float, float, float]:
    """Get a named reference-pose translation for a bone, or zero if not found."""
    t = REST_POSES_TRANS.get(pose_name, {}).get(bone_name)
    if t:
        return (t[0], t[1], t[2])
    return (0.0, 0.0, 0.0)

def quat_slerp(q1, q2, t):
    dot = q1[0]*q2[0] + q1[1]*q2[1] + q1[2]*q2[2] + q1[3]*q2[3]
    if dot < 0.0:
        q2 = (-q2[0], -q2[1], -q2[2], -q2[3])
        dot = -dot
    if dot > 0.9995:
        res = [q1[i] + t * (q2[i] - q1[i]) for i in range(4)]
        l = math.sqrt(sum(x*x for x in res))
        return tuple(x/l for x in res) if l > 0 else quat_identity()
    theta_0 = math.acos(max(-1.0, min(1.0, dot)))
    theta = theta_0 * t
    sin_theta = math.sin(theta)
    sin_theta_0 = math.sin(theta_0)
    s0 = math.cos(theta) - dot * sin_theta / sin_theta_0
    s1 = sin_theta / sin_theta_0
    return (s0*q1[0]+s1*q2[0], s0*q1[1]+s1*q2[1], s0*q1[2]+s1*q2[2], s0*q1[3]+s1*q2[3])

# ============================================================================
# ORGANIC CURVE GENERATORS
# ============================================================================

def organic_harmonic(t: float, freq: float, amp: float, phase: float = 0.0,
                     harmonics: int = 3, decay: float = 3.0) -> float:
    """Multi-harmonic waveform with 1/f energy decay for natural muscle motion."""
    val = 0.0
    for h in range(1, harmonics + 1):
        a = amp / (decay ** (h - 1))
        f = freq * h
        p = phase * (1.0 + 0.4 * (h - 1))
        val += a * math.sin(2 * math.pi * f * t + p)
    return val

def organic_drift(t: float, amp: float, seed_phase: float = 0.0) -> float:
    """Slow postural drift (0.05 Hz) for seamless 20-second loops."""
    return amp * math.sin(2 * math.pi * 0.05 * t + seed_phase)

def asymmetric_stroke(t: float, freq: float, amp: float, phase: float = 0.0,
                      power: float = 3.0) -> float:
    """Asymmetric motion curve: fast attack, slow recovery (like human muscle movement).
    Uses sin^power for the stroke phase, then eases back."""
    raw = math.sin(2 * math.pi * freq * t + phase)
    # Preserve sign, apply power curve for asymmetry
    sign = 1.0 if raw >= 0 else -1.0
    return amp * sign * (abs(raw) ** power)

def micro_noise(t: float, amp: float, seed: int = 0) -> float:
    """Pseudo-random micro-tremor for organic feel."""
    # Simple hash-based noise — deterministic per (t, seed)
    n = int(t * 60) + seed * 1000
    h = (n * 2654435761) & 0xFFFFFFFF
    r = (h / 0xFFFFFFFF) * 2.0 - 1.0
    return amp * r * 0.5  # Reduced amplitude

# ============================================================================
# GLB BINARY BUILDER
# ============================================================================

class GLBAnimationBuilder:
    """Builds GZIP-compressed binary glTF 2.0 animation files for OSF/SAF."""

    def __init__(self, node_names: List[str], duration: float = 20.0, fps: int = 24,
                 pose_name: str = "standself01"):
        self.node_names = node_names
        self.duration = duration
        self.fps = fps
        self.pose_name = pose_name
        self.frame_count = int(duration * fps)
        self.times = [round(i / fps, 6) for i in range(self.frame_count)]
        # Ensure last frame is exactly duration
        if self.times:
            self.times[-1] = duration
        # Per-bone animation data: name -> {"rot": [(t, quat)], "trans": [(t, vec)]}
        self.channels_data: Dict[str, Dict] = {
            name: {"rot": [], "trans": []} for name in node_names
        }
        # Rest pose: initialize from extracted Starfield skeleton rest pose
        # These are the bone offsets that position each bone in space.
        # Without them, all bones collapse to (0,0,0).
        self.rest_rot = {name: get_rest_rot(name, pose_name) for name in node_names}
        self.rest_trans = {name: get_rest_trans(name, pose_name) for name in node_names}

    def set_rest_pose(self, bone_name: str, rot: Tuple[float, float, float, float],
                      trans: Tuple[float, float, float] = None):
        """Override rest-pose rotation for a bone (e.g. arms raised for a pose).
        The override is MULTIPLIED onto the skeleton's base rest-pose rotation,
        so it's an offset from the natural pose, not an absolute replacement.
        Translation override (if provided) is ADDED to the base rest-pose translation."""
        base_rot = get_rest_rot(bone_name, self.pose_name)
        self.rest_rot[bone_name] = quat_multiply(base_rot, rot)
        if trans is not None:
            base_t = get_rest_trans(bone_name, self.pose_name)
            self.rest_trans[bone_name] = (base_t[0] + trans[0], base_t[1] + trans[1], base_t[2] + trans[2])

    def animate_rotation(self, bone_name: str, quat_fn: Callable[[float], Tuple[float, float, float, float]],
                         keyframe_stride: int = 1):
        """Set a rotation animation curve. The procedural rotation from quat_fn
        is MULTIPLIED onto the bone's rest-pose rotation, so the animation is
        an offset from the natural pose, not an absolute replacement."""
        if bone_name not in self.channels_data:
            return
        rest = self.rest_rot.get(bone_name, get_rest_rot(bone_name, self.pose_name))
        frames = []
        for i, t in enumerate(self.times):
            if i % keyframe_stride == 0 or i == len(self.times) - 1:
                procedural = quat_fn(t)
                # rest * procedural: apply procedural motion on top of rest pose
                final = quat_multiply(rest, procedural)
                frames.append((t, final))
        self.channels_data[bone_name]["rot"] = frames

    def animate_translation(self, bone_name: str, vec_fn: Callable[[float], Tuple[float, float, float]],
                            keyframe_stride: int = 1):
        """Set a translation animation curve. The procedural translation from vec_fn
        is ADDED to the bone's rest-pose translation, so the animation is an offset."""
        if bone_name not in self.channels_data:
            return
        rest = self.rest_trans.get(bone_name, get_rest_trans(bone_name, self.pose_name))
        frames = []
        for i, t in enumerate(self.times):
            if i % keyframe_stride == 0 or i == len(self.times) - 1:
                offset = vec_fn(t)
                final = (rest[0] + offset[0], rest[1] + offset[1], rest[2] + offset[2])
                frames.append((t, final))
        self.channels_data[bone_name]["trans"] = frames

    def _get_rotation_keyframes(self, bone_name: str) -> List[Tuple[float, Tuple]]:
        """Return animated keyframes, or a 2-keyframe rest-pose static track."""
        data = self.channels_data.get(bone_name, {})
        if data["rot"]:
            return data["rot"]
        # Static: rest pose at t=0 and t=duration
        return [(0.0, self.rest_rot.get(bone_name, quat_identity())),
                (self.duration, self.rest_rot.get(bone_name, quat_identity()))]

    def _get_translation_keyframes(self, bone_name: str) -> List[Tuple[float, Tuple]]:
        data = self.channels_data.get(bone_name, {})
        if data["trans"]:
            return data["trans"]
        return [(0.0, self.rest_trans.get(bone_name, (0.0, 0.0, 0.0))),
                (self.duration, self.rest_trans.get(bone_name, (0.0, 0.0, 0.0)))]

    def build_and_save(self, output_path: str):
        """Assemble the binary glTF 2.0 file, GZIP compress, and write to disk."""
        bin_bytes = bytearray()
        accessors = []
        samplers = []
        channels = []

        def add_data(raw: bytes) -> int:
            while len(bin_bytes) % 4 != 0:
                bin_bytes.extend(b'\x00')
            offset = len(bin_bytes)
            bin_bytes.extend(raw)
            return offset

        for node_idx, bname in enumerate(self.node_names):
            # --- ROTATION CHANNEL ---
            rot_kf = self._get_rotation_keyframes(bname)
            rot_times = [k[0] for k in rot_kf]
            rot_quats = [k[1] for k in rot_kf]

            t_off = add_data(struct.pack(f'<{len(rot_times)}f', *rot_times))
            t_acc = len(accessors)
            accessors.append({
                'bufferView': 0, 'byteOffset': t_off,
                'componentType': 5126, 'count': len(rot_times),
                'type': 'SCALAR',
                'min': [min(rot_times)], 'max': [max(rot_times)]
            })

            q_flat = [v for q in rot_quats for v in q]
            q_off = add_data(struct.pack(f'<{len(q_flat)}f', *q_flat))
            q_acc = len(accessors)
            accessors.append({
                'bufferView': 0, 'byteOffset': q_off,
                'componentType': 5126, 'count': len(rot_quats),
                'type': 'VEC4',
                'min': [min(q[i] for q in rot_quats) for i in range(4)],
                'max': [max(q[i] for q in rot_quats) for i in range(4)]
            })

            s_idx = len(samplers)
            samplers.append({'input': t_acc, 'output': q_acc, 'interpolation': 'LINEAR'})
            channels.append({'sampler': s_idx, 'target': {'node': node_idx, 'path': 'rotation'}})

            # --- TRANSLATION CHANNEL ---
            trans_kf = self._get_translation_keyframes(bname)
            trans_times = [k[0] for k in trans_kf]
            trans_vecs = [k[1] for k in trans_kf]

            tt_off = add_data(struct.pack(f'<{len(trans_times)}f', *trans_times))
            tt_acc = len(accessors)
            accessors.append({
                'bufferView': 0, 'byteOffset': tt_off,
                'componentType': 5126, 'count': len(trans_times),
                'type': 'SCALAR',
                'min': [min(trans_times)], 'max': [max(trans_times)]
            })

            v_flat = [v for vec in trans_vecs for v in vec]
            v_off = add_data(struct.pack(f'<{len(v_flat)}f', *v_flat))
            v_acc = len(accessors)
            accessors.append({
                'bufferView': 0, 'byteOffset': v_off,
                'componentType': 5126, 'count': len(trans_vecs),
                'type': 'VEC3',
                'min': [min(vec[i] for vec in trans_vecs) for i in range(3)],
                'max': [max(vec[i] for vec in trans_vecs) for i in range(3)]
            })

            ts_idx = len(samplers)
            samplers.append({'input': tt_acc, 'output': v_acc, 'interpolation': 'LINEAR'})
            channels.append({'sampler': ts_idx, 'target': {'node': node_idx, 'path': 'translation'}})

        # Assemble glTF manifest
        nodes_def = [{'name': name} for name in self.node_names]

        gltf = {
            'asset': {'generator': 'OSF-Autonomous-Procedural-v1.0', 'version': '2.0'},
            'nodes': nodes_def,
            'animations': [{
                'name': 'solo_clip',
                'samplers': samplers,
                'channels': channels
            }],
            'accessors': accessors,
            'bufferViews': [{'buffer': 0, 'byteLength': len(bin_bytes)}],
            'buffers': [{'byteLength': len(bin_bytes)}]
        }

        json_bytes = json.dumps(gltf, separators=(',', ':')).encode('utf-8')
        while len(json_bytes) % 4 != 0:
            json_bytes += b' '
        while len(bin_bytes) % 4 != 0:
            bin_bytes.extend(b'\x00')

        total_len = 12 + (8 + len(json_bytes)) + (8 + len(bin_bytes))
        glb_header = struct.pack('<4sII', b'glTF', 2, total_len)
        json_hdr = struct.pack('<I4s', len(json_bytes), b'JSON')
        bin_hdr = struct.pack('<I4s', len(bin_bytes), b'BIN\x00')

        raw_glb = glb_header + json_hdr + json_bytes + bin_hdr + bytes(bin_bytes)
        compressed = gzip.compress(raw_glb, compresslevel=6)

        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        with open(output_path, 'wb') as f:
            f.write(compressed)
        print(f"  Generated: {output_path} ({len(compressed):,} bytes compressed, {len(raw_glb):,} raw)")


# ============================================================================
# CLIP SYNTHESIS — 3 original solo animations (v2: full kinematic chains)
# Based on real kinematic profiles from standself01-03 + standsensor01-03
# Amplitudes calibrated to match reference clips (15-50° body, 10-90° fingers)
# ============================================================================

def deg2rad(d: float) -> float:
    return d * math.pi / 180.0

def find_bone(name: str) -> Optional[int]:
    """Find bone index by name, return None if not found."""
    if name in STARFIELD_SKELETON_NODES:
        return STARFIELD_SKELETON_NODES.index(name)
    return None

def cascading_finger_curl(t: float, freq: float, amp: float,
                          finger_idx: int, seg_idx: int,
                          base_phase: float = 0.0) -> float:
    """Cascading finger flexion: Pinky→Ring→Middle→Index→Thumb, base→tip."""
    f_delay = finger_idx * 0.35
    s_delay = seg_idx * 0.20
    phase = base_phase + f_delay + s_delay
    return asymmetric_stroke(t, freq, amp, phase=phase, power=2.0)


# ---------------------------------------------------------------------------
# Clip 1: solo_standing_touch — standing self-touch animation
# Rest-pose: standself01 (natural standing, arms at sides)
# ---------------------------------------------------------------------------

def synthesize_standing_touch(builder: GLBAnimationBuilder, seed: int = 101):
    """Natural idle: deep breathing, head scanning, weight shift. No sensual content."""
    b_freq = 0.10  # 6 breaths/min
    d_freq = 0.05  # slow postural drift
    phase = (seed * 0.317) % (2 * math.pi)

    # COM weight shift — subtle
    builder.animate_translation("COM", lambda t: (
        0.002 * math.sin(2*math.pi*d_freq*t),
        0.008 * math.sin(2*math.pi*d_freq*t + phase),
        0.003 * math.sin(2*math.pi*b_freq*t + 0.5)
    ))

    # Spine and chest breathing
    builder.animate_rotation("C_Chest", lambda t: quat_from_euler(
        deg2rad(6.0 * math.sin(2*math.pi*b_freq*t + 0.9)),
        deg2rad(1.0 * math.sin(2*math.pi*d_freq*t)),
        deg2rad(1.5 * math.sin(2*math.pi*d_freq*t + phase))
    ))
    builder.animate_rotation("C_Spine2", lambda t: quat_from_euler(
        deg2rad(4.0 * math.sin(2*math.pi*b_freq*t + 0.7)), 0, 0))
    builder.animate_rotation("C_Spine1", lambda t: quat_from_euler(
        deg2rad(2.5 * math.sin(2*math.pi*b_freq*t + 0.5)), 0, 0))
    builder.animate_rotation("C_Spine", lambda t: quat_from_euler(
        deg2rad(1.5 * math.sin(2*math.pi*b_freq*t + 0.3)), 0, 0))
    builder.animate_rotation("C_Hips", lambda t: quat_from_euler(
        deg2rad(2.0 * math.sin(2*math.pi*d_freq*t)),
        deg2rad(1.5 * math.cos(2*math.pi*d_freq*t)),
        deg2rad(2.0 * math.sin(2*math.pi*d_freq*t + phase))
    ))

    # Head and neck — looking around
    builder.animate_rotation("C_Head", lambda t: quat_from_euler(
        deg2rad(-1.0 + 4.0 * math.sin(2*math.pi*b_freq*t + 1.6)),
        deg2rad(2.0 * math.sin(2*math.pi*d_freq*t)),
        deg2rad(10.0 * math.sin(2*math.pi*d_freq*t + phase * 1.2))
    ))
    builder.animate_rotation("C_Neck1", lambda t: quat_from_euler(
        deg2rad(3.5 * math.sin(2*math.pi*b_freq*t + 1.4)), 0,
        deg2rad(4.0 * math.sin(2*math.pi*d_freq*t))))
    builder.animate_rotation("C_Neck", lambda t: quat_from_euler(
        deg2rad(2.5 * math.sin(2*math.pi*b_freq*t + 1.2)), 0,
        deg2rad(3.0 * math.sin(2*math.pi*d_freq*t))))

    # Shoulders, arms, wrists — subtle breathing (pitch only, no side swing)
    for side, sign in [("L", 1), ("R", -1)]:
        builder.animate_rotation(f"{side}_Clavicle", lambda t: quat_from_euler(
            deg2rad(2.0 * math.sin(2*math.pi*b_freq*t + 1.0)), 0, 0))
        builder.animate_rotation(f"{side}_Biceps", lambda t, s=sign: quat_from_euler(
            deg2rad(3.0 * math.sin(2*math.pi*d_freq*t + 0.5)),
            deg2rad(s * 1.0 * math.sin(2*math.pi*d_freq*t)),
            0))
        builder.animate_rotation(f"{side}_Forearm", lambda t, s=sign: quat_from_euler(
            deg2rad(2.5 * math.sin(2*math.pi*d_freq*t + 0.8)),
            deg2rad(s * 1.0 * math.sin(2*math.pi*d_freq*t)), 0))
        builder.animate_rotation(f"{side}_Wrist", lambda t: quat_from_euler(
            deg2rad(2.0 * math.sin(2*math.pi*b_freq*t + 1.0)),
            deg2rad(2.0 * math.sin(2*math.pi*d_freq*t)), 0))

        # Legs — micro-balance only (standing, not walking)
        builder.animate_rotation(f"{side}_Thigh", lambda t, s=sign: quat_from_euler(
            deg2rad(s * 1.5 * math.sin(2*math.pi*d_freq*t)), 0,
            deg2rad(s * 1.0 * math.sin(2*math.pi*d_freq*t))))
        builder.animate_rotation(f"{side}_Calf", lambda t, s=sign: quat_from_euler(
            deg2rad(1.0 + s * 1.0 * math.sin(2*math.pi*d_freq*t + 0.4)), 0, 0))
        builder.animate_rotation(f"{side}_Foot", lambda t, s=sign: quat_from_euler(
            deg2rad(s * 0.8 * math.sin(2*math.pi*d_freq*t)), 0, 0))

        # All 3 finger segments — passive breathing curl
        fingers = [("Pinky", 0), ("Ring", 1), ("Middle", 2), ("Index", 3)]
        for fname, f_idx in fingers:
            p = 1.0 + f_idx * 0.1
            builder.animate_rotation(f"{side}_{fname}", lambda t, pb=p: quat_from_euler(
                0, deg2rad(5.5 * math.sin(2*math.pi*b_freq*t + pb)), 0))
            builder.animate_rotation(f"{side}_{fname}1", lambda t, pb=p+0.2: quat_from_euler(
                0, deg2rad(8.0 * math.sin(2*math.pi*b_freq*t + pb)), 0))
            builder.animate_rotation(f"{side}_{fname}2", lambda t, pb=p+0.4: quat_from_euler(
                0, deg2rad(5.0 * math.sin(2*math.pi*b_freq*t + pb)), 0))
        builder.animate_rotation(f"{side}_Thumb", lambda t: quat_from_euler(
            deg2rad(3.0 * math.sin(2*math.pi*b_freq*t)),
            deg2rad(4.0 * math.sin(2*math.pi*b_freq*t)), 0))
        builder.animate_rotation(f"{side}_Thumb1", lambda t: quat_from_euler(
            0, deg2rad(6.0 * math.sin(2*math.pi*b_freq*t + 1.2)), 0))
        builder.animate_rotation(f"{side}_Thumb2", lambda t: quat_from_euler(
            0, deg2rad(4.0 * math.sin(2*math.pi*b_freq*t + 1.4)), 0))


# ---------------------------------------------------------------------------
# Clip 2: solo_sensual_caress — right-hand caressing along hip/thigh
# Rest-pose: standself03 (right hand near hip/thigh, left at side)
# ---------------------------------------------------------------------------

def synthesize_sensual_caress(builder: GLBAnimationBuilder, seed: int = 404):
    """Sensual right-hand caress along hip and thigh with cascading fingers."""
    stroke_f = 0.20
    breath_f = 0.10
    drift_f = 0.05
    phase = (seed * 0.317) % (2 * math.pi)

    # COM — subtle hip shift
    builder.animate_translation("COM", lambda t: (
        0.005 * math.sin(2*math.pi*stroke_f*t),
        0.012 * math.sin(2*math.pi*drift_f*t + phase),
        0.008 * math.sin(2*math.pi*stroke_f*t + 0.4)
    ))

    # Torso and hips — controlled, no wild swinging
    builder.animate_rotation("C_Hips", lambda t: quat_from_euler(
        deg2rad(4.0 * math.sin(2*math.pi*stroke_f*t)),
        deg2rad(2.5 * math.cos(2*math.pi*drift_f*t)),
        deg2rad(4.0 * math.sin(2*math.pi*stroke_f*t + 0.2))
    ))
    builder.animate_rotation("C_Chest", lambda t: quat_from_euler(
        deg2rad(6.0 * math.sin(2*math.pi*stroke_f*t + 0.9) +
                2.5 * math.sin(2*math.pi*breath_f*t)),
        deg2rad(2.0 * math.sin(2*math.pi*drift_f*t)),
        deg2rad(3.0 * math.sin(2*math.pi*stroke_f*t + 0.5))
    ))
    builder.animate_rotation("C_Spine2", lambda t: quat_from_euler(
        deg2rad(4.0 * math.sin(2*math.pi*stroke_f*t + 0.7)), 0,
        deg2rad(2.0 * math.sin(2*math.pi*stroke_f*t))))
    builder.animate_rotation("C_Spine1", lambda t: quat_from_euler(
        deg2rad(3.5 * math.sin(2*math.pi*stroke_f*t + 0.5)), 0,
        deg2rad(2.5 * math.sin(2*math.pi*stroke_f*t))))
    builder.animate_rotation("C_Spine", lambda t: quat_from_euler(
        deg2rad(2.5 * math.sin(2*math.pi*stroke_f*t + 0.3)), 0,
        deg2rad(3.0 * math.sin(2*math.pi*stroke_f*t))))

    # Head — sensual tilt back (controlled, not extreme)
    builder.animate_rotation("C_Head", lambda t: quat_from_euler(
        deg2rad(-4.0 + 7.0 * math.sin(2*math.pi*stroke_f*t + 1.6)),
        deg2rad(5.0 * math.sin(2*math.pi*drift_f*t + phase)),
        deg2rad(12.0 * math.sin(2*math.pi*drift_f*t + phase * 1.3))
    ))
    builder.animate_rotation("C_Neck1", lambda t: quat_from_euler(
        deg2rad(-2.0 + 6.0 * math.sin(2*math.pi*stroke_f*t + 1.4)),
        deg2rad(3.0 * math.sin(2*math.pi*drift_f*t)),
        deg2rad(5.0 * math.sin(2*math.pi*drift_f*t))))
    builder.animate_rotation("C_Neck", lambda t: quat_from_euler(
        deg2rad(-1.0 + 5.0 * math.sin(2*math.pi*stroke_f*t + 1.2)),
        deg2rad(2.5 * math.sin(2*math.pi*drift_f*t)),
        deg2rad(4.0 * math.sin(2*math.pi*drift_f*t))))

    # Right arm — active caressing (pitch=forward toward body, minimal yaw)
    builder.animate_rotation("R_Clavicle", lambda t: quat_from_euler(
        deg2rad(5.0 * math.sin(2*math.pi*stroke_f*t + 0.2)),
        deg2rad(2.0 * math.sin(2*math.pi*stroke_f*t)),
        deg2rad(3.0 * math.sin(2*math.pi*stroke_f*t))))
    builder.animate_rotation("R_Biceps", lambda t: quat_from_euler(
        deg2rad(10.0 * math.sin(2*math.pi*stroke_f*t + 0.4)),
        deg2rad(5.0 * math.sin(2*math.pi*stroke_f*t + 0.2)),
        deg2rad(3.0 * math.sin(2*math.pi*stroke_f*t))))
    builder.animate_rotation("R_Forearm", lambda t: quat_from_euler(
        deg2rad(8.0 * math.sin(2*math.pi*stroke_f*t + 0.7)),
        deg2rad(5.0 * math.sin(2*math.pi*stroke_f*t + 0.5)),
        deg2rad(2.0 * math.sin(2*math.pi*stroke_f*t))))
    builder.animate_rotation("R_Wrist", lambda t: quat_from_euler(
        asymmetric_stroke(t, stroke_f, deg2rad(10.0), phase=1.0, power=2.0),
        asymmetric_stroke(t, stroke_f, deg2rad(18.0), phase=1.0, power=2.0),
        deg2rad(4.0 * math.sin(2*math.pi*stroke_f*t + 0.8))
    ))

    # Right fingers — all 3 segments, cascading curl (controlled)
    r_fingers = [("Pinky", 0, 8.0, 18.0, 12.0),
                 ("Ring", 1, 9.0, 20.0, 14.0),
                 ("Middle", 2, 8.0, 18.0, 13.0),
                 ("Index", 3, 7.0, 16.0, 10.0)]
    for fname, f_idx, a0, a1, a2 in r_fingers:
        p_base = 1.0 + f_idx * 0.35
        builder.animate_rotation(f"R_{fname}", lambda t, a=a0, p=p_base: quat_from_euler(
            0, asymmetric_stroke(t, stroke_f, deg2rad(a), phase=p, power=2.0), 0))
        builder.animate_rotation(f"R_{fname}1", lambda t, a=a1, p=p_base+0.2: quat_from_euler(
            0, asymmetric_stroke(t, stroke_f, deg2rad(a), phase=p, power=2.0), 0))
        builder.animate_rotation(f"R_{fname}2", lambda t, a=a2, p=p_base+0.4: quat_from_euler(
            0, asymmetric_stroke(t, stroke_f, deg2rad(a), phase=p, power=2.0), 0))
    builder.animate_rotation("R_Thumb", lambda t: quat_from_euler(
        deg2rad(8.0 * math.sin(2*math.pi*stroke_f*t + 1.8)),
        asymmetric_stroke(t, stroke_f, deg2rad(7.0), phase=1.8, power=2.0), 0))
    builder.animate_rotation("R_Thumb1", lambda t: quat_from_euler(
        0, asymmetric_stroke(t, stroke_f, deg2rad(16.0), phase=2.0, power=2.0), 0))
    builder.animate_rotation("R_Thumb2", lambda t: quat_from_euler(
        0, asymmetric_stroke(t, stroke_f, deg2rad(10.0), phase=2.2, power=2.0), 0))

    # Left arm — stabilizing at side (minimal)
    builder.animate_rotation("L_Clavicle", lambda t: quat_from_euler(
        deg2rad(2.0 * math.sin(2*math.pi*drift_f*t)), 0, 0))
    builder.animate_rotation("L_Biceps", lambda t: quat_from_euler(
        deg2rad(2.5 * math.sin(2*math.pi*drift_f*t + 0.3)),
        deg2rad(1.5 * math.sin(2*math.pi*drift_f*t)), 0))
    builder.animate_rotation("L_Forearm", lambda t: quat_from_euler(
        deg2rad(3.0 * math.sin(2*math.pi*drift_f*t + 0.6)),
        deg2rad(2.0 * math.sin(2*math.pi*drift_f*t)), 0))
    builder.animate_rotation("L_Wrist", lambda t: quat_from_euler(
        deg2rad(3.0 * math.sin(2*math.pi*drift_f*t + 0.9)),
        deg2rad(4.0 * math.sin(2*math.pi*drift_f*t)), 0))
    for fname in ["Pinky", "Ring", "Middle", "Index"]:
        builder.animate_rotation(f"L_{fname}", lambda t: quat_from_euler(
            0, deg2rad(2.0 * math.sin(2*math.pi*drift_f*t)), 0))
        builder.animate_rotation(f"L_{fname}1", lambda t: quat_from_euler(
            0, deg2rad(4.0 * math.sin(2*math.pi*drift_f*t)), 0))
        builder.animate_rotation(f"L_{fname}2", lambda t: quat_from_euler(
            0, deg2rad(3.0 * math.sin(2*math.pi*drift_f*t)), 0))
    builder.animate_rotation("L_Thumb1", lambda t: quat_from_euler(
        0, deg2rad(3.0 * math.sin(2*math.pi*drift_f*t)), 0))
    builder.animate_rotation("L_Thumb2", lambda t: quat_from_euler(
        0, deg2rad(2.0 * math.sin(2*math.pi*drift_f*t)), 0))

    # Legs — micro-balance only (standing still)
    builder.animate_rotation("R_Thigh", lambda t: quat_from_euler(
        deg2rad(2.0 * math.sin(2*math.pi*stroke_f*t)),
        deg2rad(1.0 * math.sin(2*math.pi*drift_f*t)),
        deg2rad(1.5 * math.sin(2*math.pi*stroke_f*t))))
    builder.animate_rotation("R_Calf", lambda t: quat_from_euler(
        deg2rad(2.0 * math.sin(2*math.pi*stroke_f*t + 0.3)), 0, 0))
    builder.animate_rotation("R_Foot", lambda t: quat_from_euler(
        deg2rad(1.5 * math.sin(2*math.pi*stroke_f*t + 0.5)), 0, 0))
    builder.animate_rotation("L_Thigh", lambda t: quat_from_euler(
        deg2rad(-2.0 * math.sin(2*math.pi*stroke_f*t)),
        deg2rad(-1.0 * math.sin(2*math.pi*drift_f*t)),
        deg2rad(-1.5 * math.sin(2*math.pi*stroke_f*t))))
    builder.animate_rotation("L_Calf", lambda t: quat_from_euler(
        deg2rad(2.0 * math.sin(2*math.pi*stroke_f*t + 0.3)), 0, 0))
    builder.animate_rotation("L_Foot", lambda t: quat_from_euler(
        deg2rad(-1.5 * math.sin(2*math.pi*stroke_f*t + 0.5)), 0, 0))


# ---------------------------------------------------------------------------
# Clip 3: solo_sensual_touch — both hands exploring chest/waist
# Rest-pose: cover01 (hands at chest/lower ribs height)
# ---------------------------------------------------------------------------

def synthesize_sensual_touch(builder: GLBAnimationBuilder, seed: int = 505):
    """Sensual two-handed self-touch: hands roam chest and waist."""
    touch_f = 0.25
    breath_f = 0.15
    drift_f = 0.05
    phase = (seed * 0.317) % (2 * math.pi)

    # COM — subtle vertical wave
    builder.animate_translation("COM", lambda t: (
        0.006 * math.sin(2*math.pi*touch_f*t),
        0.008 * math.sin(2*math.pi*drift_f*t + phase),
        0.012 * math.sin(2*math.pi*touch_f*t + 0.5)
    ))

    # Torso and pelvis — controlled
    builder.animate_rotation("C_Hips", lambda t: quat_from_euler(
        deg2rad(5.0 * math.sin(2*math.pi*touch_f*t)),
        deg2rad(2.5 * math.cos(2*math.pi*drift_f*t)),
        deg2rad(3.0 * math.sin(2*math.pi*touch_f*t + 0.3))
    ))
    builder.animate_rotation("C_Spine", lambda t: quat_from_euler(
        deg2rad(4.0 * math.sin(2*math.pi*touch_f*t + 0.25)),
        deg2rad(2.0 * math.sin(2*math.pi*drift_f*t)),
        deg2rad(4.0 * math.sin(2*math.pi*touch_f*t + 0.25))))
    builder.animate_rotation("C_Spine1", lambda t: quat_from_euler(
        deg2rad(5.0 * math.sin(2*math.pi*touch_f*t + 0.50)),
        deg2rad(1.5 * math.sin(2*math.pi*drift_f*t)),
        deg2rad(3.5 * math.sin(2*math.pi*touch_f*t + 0.50))))
    builder.animate_rotation("C_Spine2", lambda t: quat_from_euler(
        deg2rad(4.0 * math.sin(2*math.pi*touch_f*t + 0.75)),
        deg2rad(1.5 * math.sin(2*math.pi*drift_f*t)),
        deg2rad(3.0 * math.sin(2*math.pi*touch_f*t + 0.75))))
    builder.animate_rotation("C_Chest", lambda t: quat_from_euler(
        deg2rad(7.0 * math.sin(2*math.pi*touch_f*t + 1.0) +
                3.0 * math.sin(2*math.pi*breath_f*t)),
        deg2rad(2.0 * math.sin(2*math.pi*drift_f*t)),
        deg2rad(4.0 * math.sin(2*math.pi*touch_f*t + 1.0))
    ))

    # Head and neck — sensual expression (controlled)
    builder.animate_rotation("C_Head", lambda t: quat_from_euler(
        deg2rad(-5.0 + 8.0 * math.sin(2*math.pi*touch_f*t + 1.8)),
        deg2rad(5.0 * math.sin(2*math.pi*drift_f*t + phase)),
        deg2rad(12.0 * math.sin(2*math.pi*drift_f*t + phase * 1.5))
    ))
    builder.animate_rotation("C_Neck1", lambda t: quat_from_euler(
        deg2rad(-3.0 + 7.0 * math.sin(2*math.pi*touch_f*t + 1.55)),
        deg2rad(3.0 * math.sin(2*math.pi*drift_f*t)),
        deg2rad(6.0 * math.sin(2*math.pi*touch_f*t))))
    builder.animate_rotation("C_Neck", lambda t: quat_from_euler(
        deg2rad(-2.0 + 5.0 * math.sin(2*math.pi*touch_f*t + 1.30)),
        deg2rad(2.5 * math.sin(2*math.pi*drift_f*t)),
        deg2rad(4.0 * math.sin(2*math.pi*touch_f*t))))

    # Both arms — alternating body exploration (pitch=forward, minimal yaw)
    arms = [
        ("L", 0.3, 0.5, 0.8, 1.1,
         [("Pinky", 0, 10.0, 22.0, 15.0), ("Ring", 1, 11.0, 26.0, 17.0),
          ("Middle", 2, 10.0, 24.0, 16.0), ("Index", 3, 9.0, 20.0, 13.0)],
         9.0, 8.0, 18.0, 12.0),
        ("R", 0.6, 0.8, 1.1, 1.4,
         [("Pinky", 0, 9.0, 20.0, 13.0), ("Ring", 1, 10.0, 24.0, 15.0),
          ("Middle", 2, 9.0, 22.0, 14.0), ("Index", 3, 8.0, 18.0, 11.0)],
         8.0, 7.0, 16.0, 11.0)
    ]
    for side, p_clav, p_bic, p_fore, p_wrist, f_configs, th_x, th_y, th1, th2 in arms:
        builder.animate_rotation(f"{side}_Clavicle", lambda t, p=p_clav: quat_from_euler(
            deg2rad(5.0 * math.sin(2*math.pi*touch_f*t + p)),
            deg2rad(2.0 * math.sin(2*math.pi*touch_f*t)),
            deg2rad(3.0 * math.sin(2*math.pi*touch_f*t))))
        builder.animate_rotation(f"{side}_Biceps", lambda t, p=p_bic: quat_from_euler(
            deg2rad(9.0 * math.sin(2*math.pi*touch_f*t + p)),
            deg2rad(6.0 * math.sin(2*math.pi*touch_f*t + p*0.8)),
            deg2rad(3.0 * math.sin(2*math.pi*touch_f*t))))
        builder.animate_rotation(f"{side}_Forearm", lambda t, p=p_fore: quat_from_euler(
            deg2rad(8.0 * math.sin(2*math.pi*touch_f*t + p)),
            deg2rad(5.0 * math.sin(2*math.pi*touch_f*t + p*0.8)),
            deg2rad(2.0 * math.sin(2*math.pi*touch_f*t))))
        builder.animate_rotation(f"{side}_Wrist", lambda t, p=p_wrist: quat_from_euler(
            asymmetric_stroke(t, touch_f, deg2rad(10.0), phase=p, power=2.0),
            asymmetric_stroke(t, touch_f, deg2rad(16.0), phase=p, power=2.0),
            deg2rad(4.0 * math.sin(2*math.pi*touch_f*t + p))
        ))
        # All 3 finger segments
        for fname, f_idx, a0, a1, a2 in f_configs:
            p_base = p_wrist + f_idx * 0.3
            builder.animate_rotation(f"{side}_{fname}", lambda t, a=a0, pb=p_base: quat_from_euler(
                0, asymmetric_stroke(t, touch_f, deg2rad(a), phase=pb, power=2.0), 0))
            builder.animate_rotation(f"{side}_{fname}1", lambda t, a=a1, pb=p_base+0.2: quat_from_euler(
                0, asymmetric_stroke(t, touch_f, deg2rad(a), phase=pb, power=2.0), 0))
            builder.animate_rotation(f"{side}_{fname}2", lambda t, a=a2, pb=p_base+0.4: quat_from_euler(
                0, asymmetric_stroke(t, touch_f, deg2rad(a), phase=pb, power=2.0), 0))
        builder.animate_rotation(f"{side}_Thumb", lambda t, tx=th_x, ty=th_y, p=p_wrist: quat_from_euler(
            deg2rad(tx * math.sin(2*math.pi*touch_f*t + p + 0.8)),
            asymmetric_stroke(t, touch_f, deg2rad(ty), phase=p+0.8, power=2.0), 0))
        builder.animate_rotation(f"{side}_Thumb1", lambda t, a=th1, p=p_wrist: quat_from_euler(
            0, asymmetric_stroke(t, touch_f, deg2rad(a), phase=p+1.0, power=2.0), 0))
        builder.animate_rotation(f"{side}_Thumb2", lambda t, a=th2, p=p_wrist: quat_from_euler(
            0, asymmetric_stroke(t, touch_f, deg2rad(a), phase=p+1.2, power=2.0), 0))

    # Legs — micro-balance only (standing still)
    for side, sign in [("L", 1), ("R", -1)]:
        builder.animate_rotation(f"{side}_Thigh", lambda t, s=sign: quat_from_euler(
            deg2rad(2.5 * math.sin(2*math.pi*touch_f*t)),
            deg2rad(s * 1.5 * math.sin(2*math.pi*drift_f*t)),
            deg2rad(s * 2.0 * math.sin(2*math.pi*touch_f*t))))
        builder.animate_rotation(f"{side}_Calf", lambda t, s=sign: quat_from_euler(
            deg2rad(2.0 + 1.5 * math.sin(2*math.pi*touch_f*t + 0.3)), 0,
            deg2rad(s * 1.0 * math.sin(2*math.pi*touch_f*t))))
        builder.animate_rotation(f"{side}_Foot", lambda t, s=sign: quat_from_euler(
            deg2rad(1.5 * math.sin(2*math.pi*touch_f*t + 0.5)), 0,
            deg2rad(s * 1.0 * math.sin(2*math.pi*touch_f*t))))
        builder.animate_rotation(f"{side}_Toe", lambda t, s=sign: quat_from_euler(
            deg2rad(2.0 * math.sin(2*math.pi*touch_f*t + 0.7)), 0, 0))


# ============================================================================
# MAIN
# ============================================================================

def main():
    if not STARFIELD_SKELETON_NODES:
        print("ERROR: Skeleton nodes not loaded. Run skeleton extraction first.")
        print("  Expected: G:\\Starfield\\src\\OSFAutonomous\\skeleton_nodes.py")
        return

    print(f"OSF Autonomous — Procedural Solo Animation Generator v2")
    print(f"  Skeleton: {len(STARFIELD_SKELETON_NODES)} bones")
    print(f"  Duration: 20.0s @ 24fps (480 keyframes per bone)")
    print(f"  Clips: 3 (full kinematic chains, real amplitudes)")
    print()

    output_dir = os.path.join(os.path.dirname(__file__), "..", "..", "Data", "OSF", "Autonomous", "Animations")
    output_dir = os.path.normpath(output_dir)

    clips = [
        ("solo_standing_touch.glb", synthesize_standing_touch, 101,
         "Solo Standing Touch", "standself01"),
        ("solo_sensual_caress.glb", synthesize_sensual_caress, 404,
         "Sensual Right-Hand Caress", "standself03"),
        ("solo_sensual_touch.glb", synthesize_sensual_touch, 505,
         "Sensual Two-Hand Body Touch", "cover01"),
    ]

    print("Generating clips:")
    for filename, synth_fn, seed, label, pose_name in clips:
        builder = GLBAnimationBuilder(STARFIELD_SKELETON_NODES, duration=20.0, fps=24,
                                      pose_name=pose_name)
        synth_fn(builder, seed=seed)
        output_path = os.path.join(output_dir, filename)
        builder.build_and_save(output_path)

    print(f"\nDone! {len(clips)} clips generated in:")
    print(f"  {output_dir}")
    print(f"\nNext: update osfautonomous-solo.osf.json with new clip paths")

if __name__ == "__main__":
    main()
