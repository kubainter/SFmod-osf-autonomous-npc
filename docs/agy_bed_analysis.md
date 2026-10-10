# AGY Bed Analysis - Solo Bed Touch

## Executive Summary
- Feasibility: 100% mechanically feasible
- Architecture: Static Frame 1 from donor + 480-frame procedural harmonics (same as chair)
- Donor: Missionary01-DoubleBed-2.glb (role x, lying on back)
- Frame count: 480 (20s) — NOT 300 (donor length)

## Key Decisions

### 1. Frame Count: 480 frames (20s)
- All procedural harmonics calibrated to 20s
- Breathing: 5 cycles, massage: 10 cycles, fingers: 30 cycles
- 300 frames would break loop seam (3.125 breaths = pop)

### 2. HUSH Left Arm Quaternions (supine)
```python
HUSH_LEFT_ARM_BED_QUATS = {
    'L_Clavicle': [0.84613, -0.07673,  0.51754, -0.10168],  # Same as chair
    'L_Biceps':   [0.01671,  0.67707, -0.72383, -0.13177],  # Elevate headward
    'L_Forearm':  [0.03653, -0.79803, -0.42347,  0.42718],  # Reduce flexion +17°
    'L_Wrist':    [0.59539, -0.07839, -0.37299,  0.70728],  # Fine pitch +5°
}
```
- Lip gap: 1.62mm (precise contact)
- Elbow clears mattress by +6.9cm

### 3. Right Arm: Use standing-touch procedural (NOT donor)
- Donor right arm reaches 51cm outward (holding partner)
- Standing-touch right arm naturally falls to groin when supine
- R_Wrist world: [0.120, 0.089, 0.724] — directly over pubic mound
- R_Elbow clears mattress by +4.7cm
- NO adduction offset needed (unlike chair)
- Standing RIGHT_FINGER_PARAMS transfer directly

### 4. Static Base (Frame 1) + Procedural
- Donor has coital motion: pelvis rocking, leg kicking, neck thrashing
- Use Frame 1 as static supine pose
- Layer our procedural breathing/massage/finger motion on top

### 5. Breathing
- Lying down: chest rises vertically (Z axis)
- Same breathing parameters as standing/chair work fine
- NECK_COUNTER_PITCH = 0.0 (same as chair)

### 6. Head
- Lying on back: head naturally faces up
- Keep static from donor Frame 1
- Small motion ±1.2° (same as chair)

### 7. Lower Body
- Static from donor Frame 1 (knees bent, legs spread)
- No animated transplant (donor has coital kicking)
- Zero out translations to prevent drift

### 8. COM
- [0.190, -0.016, 0.749] from donor Frame 1
- Static (2-frame)

### 9. Torso/Spine/Head
- Static from donor Frame 1
- Layer breathing on torso
- Small head motion only

## Anchor FormIDs (DoubleBed, 15 total)
0x1E2800, 0x00468C, 0x00468B, 0x00468A, 0x1E2722, 0x004689, 0x004688, 0x004687,
0x1E2802, 0x004686, 0x004685, 0x004684, 0x112343, 0x12A578, 0x2E395B

## Differences from Chair Version
- NO adduction offset for right arm (bed has open space)
- Different HUSH arm quaternions (head is further away)
- COM is [0.190, -0.016, 0.749] not [0.007, 0.181, 0.675]
- Donor has 300 frames not 481 — but we use only Frame 1 as static
- No backrest concern (flat surface)
