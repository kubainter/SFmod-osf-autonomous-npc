import gzip, struct, json, os, sys

d = r'G:\Starfield\Data\OSF\Autonomous\Animations'
for f in sorted(os.listdir(d)):
    if not f.endswith('.glb'):
        continue
    p = os.path.join(d, f)
    raw = gzip.decompress(open(p, 'rb').read())
    magic, ver, total = struct.unpack_from('<4sII', raw, 0)
    # Parse chunk 0 header
    chunk0_len, chunk0_type = struct.unpack_from('<I4s', raw, 12)
    chunk0_data = raw[20:20+chunk0_len]
    gltf_json = json.loads(chunk0_data.decode('utf-8'))
    n_nodes = len(gltf_json.get('nodes', []))
    n_channels = len(gltf_json.get('animations', [{}])[0].get('channels', []))
    n_samplers = len(gltf_json.get('animations', [{}])[0].get('samplers', []))
    n_accessors = len(gltf_json.get('accessors', []))
    # Check chunk 1
    chunk1_off = 20 + chunk0_len
    chunk1_len, chunk1_type = struct.unpack_from('<I4s', raw, chunk1_off)
    print(f"{f}:")
    print(f"  magic={magic.decode()}, v{ver}, total={total}B (raw), {os.path.getsize(p)}B (compressed)")
    print(f"  chunk0: {chunk0_type.decode()} {chunk0_len}B | chunk1: {chunk1_type.decode()} {chunk1_len}B")
    print(f"  nodes={n_nodes}, channels={n_channels}, samplers={n_samplers}, accessors={n_accessors}")
    print(f"  generator={gltf_json.get('asset',{}).get('generator','?')}")
    # Verify first few node names
    names = [n.get('name','?') for n in gltf_json.get('nodes', [])[:5]]
    print(f"  first nodes: {names}")
    print()
