import gzip, struct, json, os

def read_glb_json(path):
    with open(path, 'rb') as f:
        raw = f.read()
    if raw[:2] == b'\x1f\x8b':
        data = gzip.decompress(raw)
    else:
        data = raw
    magic, ver, total = struct.unpack_from('<4sII', data, 0)
    chunk0_len, chunk0_type = struct.unpack_from('<I4s', data, 12)
    json_bytes = data[20:20+chunk0_len]
    return json.loads(json_bytes.rstrip(b'\x00').rstrip().decode('utf-8'))

orig = read_glb_json(r'G:\Starfield\Data\SAF\Animations\standself01.glb')
ours = read_glb_json(r'G:\Starfield\Data\OSF\Autonomous\Animations\solo_idle_breathe01.glb')

print("=== ORIGINAL NODES (first 15) ===")
for i, n in enumerate(orig['nodes'][:15]):
    name = n.get('name', '?')
    trans = n.get('translation', None)
    rot = n.get('rotation', None)
    children = n.get('children', None)
    print(f"  [{i}] {name}: trans={trans}, rot={rot}, children={children is not None}")

print("\n=== OUR NODES (first 15) ===")
for i, n in enumerate(ours['nodes'][:15]):
    name = n.get('name', '?')
    trans = n.get('translation', None)
    rot = n.get('rotation', None)
    children = n.get('children', None)
    print(f"  [{i}] {name}: trans={trans}, rot={rot}, children={children is not None}")

# Count nodes with translation/rotation/children
orig_trans = sum(1 for n in orig['nodes'] if 'translation' in n)
orig_rot = sum(1 for n in orig['nodes'] if 'rotation' in n)
orig_child = sum(1 for n in orig['nodes'] if 'children' in n)
ours_trans = sum(1 for n in ours['nodes'] if 'translation' in n)
ours_rot = sum(1 for n in ours['nodes'] if 'rotation' in n)
ours_child = sum(1 for n in ours['nodes'] if 'children' in n)

print(f"\n=== SUMMARY ===")
print(f"Original: {len(orig['nodes'])} nodes, {orig_trans} with translation, {orig_rot} with rotation, {orig_child} with children")
print(f"Ours:     {len(ours['nodes'])} nodes, {ours_trans} with translation, {ours_rot} with rotation, {ours_child} with children")
