import gzip
import json
import struct

GLB_PATH = r"G:\Starfield\Data\SAF\Animations\standself01.glb"
OUT_PATH = r"G:\Starfield\src\OSFAutonomous\skeleton_nodes.py"

with open(GLB_PATH, "rb") as f:
    raw = f.read()

# The entire file is gzip-compressed (magic \x1f\x8b)
if raw[:2] == b"\x1f\x8b":
    data = gzip.decompress(raw)
    print(f"Decompressed whole file: {len(raw)} -> {len(data)} bytes")
else:
    data = raw

# Header: 12 bytes
magic = data[0:4]
version = struct.unpack("<I", data[4:8])[0]
total_length = struct.unpack("<I", data[8:12])[0]
print(f"magic={magic}, version={version}, total_length={total_length}")

# Chunk 0 header: bytes 12-19
chunk0_len = struct.unpack("<I", data[12:16])[0]
chunk0_type = data[16:20]
print(f"chunk0_len={chunk0_len}, chunk0_type={chunk0_type}")

# JSON data starts at byte 20
json_bytes = data[20:20 + chunk0_len]

# Strip trailing nulls/spaces
json_text = json_bytes.rstrip(b"\x00").rstrip().decode("utf-8")

gltf = json.loads(json_text)

nodes = gltf.get("nodes", [])
print(f"Node count: {len(nodes)}")

names = [n.get("name", "") for n in nodes]
print(f"First 10 names: {names[:10]}")
print(f"Last 10 names: {names[-10:]}")

# Hierarchy for first 10 nodes
print("\nHierarchy for first 10 nodes:")
for i in range(min(10, len(nodes))):
    n = nodes[i]
    children = n.get("children", None)
    print(f"  node[{i}] name={n.get('name')!r} children={children}")

# Write output file
with open(OUT_PATH, "w", encoding="utf-8") as f:
    f.write("STARFIELD_SKELETON_NODES = ")
    f.write(json.dumps(names, indent=4, ensure_ascii=False))
    f.write("\n")

print(f"\nWrote {len(names)} names to {OUT_PATH}")
