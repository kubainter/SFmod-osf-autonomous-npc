#!/usr/bin/env python3
"""Pełny scan Dick.esm — wszystkie rekordy w GRUPach."""
import struct
import sys
import zlib

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

DICK = r'G:\Starfield\Data\Dick.esm'

with open(DICK, 'rb') as f:
    data = f.read()

print(f"File size: {len(data)}")
tes4_size = struct.unpack_from('<I', data, 4)[0]
print(f"TES4 size: {tes4_size}")

# Masters
pos = 24
while pos + 6 <= 24 + tes4_size:
    st = data[pos:pos+4].decode('ascii', errors='replace')
    ss = struct.unpack_from('<H', data, pos+4)[0]
    sd = data[pos+6:pos+6+ss]
    if st == 'MAST':
        name = sd.split(b'\x00')[0].decode()
        print(f"MAST: {name}")
    pos += 6 + ss

# Scan all GRUPs and records
pos = 24 + tes4_size

def scan_grup(pos):
    grp_size = struct.unpack_from('<I', data, pos+4)[0]
    grp_label = struct.unpack_from('<I', data, pos+8)[0]
    grp_type = struct.unpack_from('<I', data, pos+16)[0]  # group type
    print(f"\nGRUP at {pos}, size={grp_size}, label=0x{grp_label:08X}, type={grp_type}")
    
    inner = pos + 24
    while inner < pos + grp_size:
        if data[inner:inner+4] == b'GRUP':
            inner = scan_grup(inner)
        else:
            if inner + 24 > len(data):
                break
            rec_type = data[inner:inner+4].decode('ascii', errors='replace')
            rec_size = struct.unpack_from('<I', data, inner+4)[0]
            rec_flags = struct.unpack_from('<I', data, inner+8)[0]
            rec_formid = struct.unpack_from('<I', data, inner+12)[0]
            data_start = inner + 24
            data_end = data_start + rec_size
            rec_data = data[data_start:data_end]
            
            body = rec_data
            if rec_flags & 0x00040000:
                try:
                    body = zlib.decompress(rec_data[4:])
                except:
                    body = rec_data
            
            p = 0
            edid = ''
            full = ''
            while p + 6 <= len(body):
                st2 = body[p:p+4].decode('ascii', errors='replace')
                ss2 = struct.unpack_from('<H', body, p+4)[0]
                sd2 = body[p+6:p+6+ss2]
                if st2 == 'EDID':
                    edid = sd2.split(b'\x00')[0].decode('ascii', errors='replace')
                if st2 == 'FULL':
                    full = sd2.split(b'\x00')[0].decode('utf-8', errors='replace')
                p += 6 + ss2
            
            print(f"  {rec_type} 0x{rec_formid:08X} EDID={edid} FULL={full}")
            inner = data_end
    
    return pos + grp_size

while pos < len(data):
    if data[pos:pos+4] == b'GRUP':
        pos = scan_grup(pos)
    else:
        if pos + 24 > len(data):
            break
        rec_size = struct.unpack_from('<I', data, pos+4)[0]
        pos += 24 + rec_size
