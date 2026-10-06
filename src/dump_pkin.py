#!/usr/bin/env python3
"""Dump raw structure of companion room PKIN records to understand the format."""
import struct
import sys
import zlib
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

HEADER_SIZE = 24
GRUP_HEADER_SIZE = 24

filepath = r"G:\Starfield\Data\stroudpremiumedition.esm"
with open(filepath, 'rb') as f:
    data = f.read()

# Find specific PKIN records by EDID
target_pkins = [
    'Vince134_ShipPI_SMOD_Hab_SPE_SarahRoom_1L1W1H_Aft_A',
    'Vince134_ShipPI_SMOD_Hab_SPE_AndrejaRoom_1L1W1H_Stb_A',
    'Vince134_ShipPI_SMOD_Hab_SPE_BarrettRoom_1L1W1H_Stb_A_Int',
    'Vince134_Hab_SarahRoom_A_1x1_Clutter01_SPE',
]

tes4_size = struct.unpack_from('<I', data, 4)[0]
pos = HEADER_SIZE + tes4_size

def parse_group(pos, depth=0):
    if pos + GRUP_HEADER_SIZE > len(data):
        return len(data)

    grp_size = struct.unpack_from('<I', data, pos+4)[0]
    grp_end = pos + grp_size
    inner = pos + GRUP_HEADER_SIZE

    while inner < grp_end:
        if data[inner:inner+4] == b'GRUP':
            inner = parse_group(inner, depth+1)
        else:
            if inner + HEADER_SIZE > len(data):
                break

            rec_type = data[inner:inner+4].decode('ascii', errors='replace')
            rec_size = struct.unpack_from('<I', data, inner+4)[0]
            rec_flags = struct.unpack_from('<I', data, inner+8)[0]
            rec_formid = struct.unpack_from('<I', data, inner+12)[0]
            data_start = inner + HEADER_SIZE
            data_end = data_start + rec_size

            if data_end > len(data):
                break

            if rec_type == 'PKIN':
                # Get EDID
                edid = ''
                p = data_start
                while p + 6 <= data_end:
                    st = data[p:p+4].decode('ascii', errors='replace')
                    ss = struct.unpack_from('<H', data, p+4)[0]
                    if p + 6 + ss > data_end:
                        break
                    sd = data[p+6:p+6+ss]
                    if st == 'EDID':
                        edid = sd.split(b'\x00')[0].decode('ascii', errors='replace')
                        break
                    p += 6 + ss

                if edid in target_pkins:
                    print(f"\n{'='*120}")
                    print(f"PKIN: 0x{rec_formid:08X} = {edid}")
                    print(f"  Size: {rec_size} bytes, Flags: 0x{rec_flags:08X}, Compressed: {bool(rec_flags & 0x00040000)}")

                    # Get the data to parse
                    if rec_flags & 0x00040000:
                        try:
                            uncomp_size = struct.unpack_from('<I', data, data_start)[0]
                            comp_data = data[data_start+4:data_end]
                            pkin_data = zlib.decompress(comp_data)
                            print(f"  Compressed: {rec_size} -> {len(pkin_data)} bytes")
                        except:
                            print(f"  FAILED to decompress")
                            pkin_data = data[data_start:data_end]
                    else:
                        pkin_data = data[data_start:data_end]

                    # Dump all subrecords
                    print(f"\n  Subrecords ({len(pkin_data)} bytes):")
                    sp = 0
                    sub_types = []
                    while sp + 6 <= len(pkin_data):
                        st = pkin_data[sp:sp+4].decode('ascii', errors='replace')
                        ss = struct.unpack_from('<H', pkin_data, sp+4)[0]
                        if sp + 6 + ss > len(pkin_data):
                            print(f"    [TRUNCATED] {st} size={ss} at offset {sp}")
                            break
                        sd = pkin_data[sp+6:sp+6+ss]
                        sub_types.append(st)

                        # Show interesting subrecords
                        if st == 'EDID':
                            print(f"    [{sp:6d}] {st} ({ss:5d}): {sd.split(b'\\x00')[0].decode('ascii', errors='replace')}")
                        elif st == 'GRUP':
                            # Nested group!
                            gsize = struct.unpack_from('<I', sd, 0)[0] if ss >= 4 else 0
                            glabel = sd[4:8].decode('ascii', errors='replace') if ss >= 8 else ''
                            gtype = struct.unpack_from('<I', sd, 8)[0] if ss >= 12 else 0
                            print(f"    [{sp:6d}] {st} ({ss:5d}): NESTED GRUP size={gsize} label='{glabel}' type={gtype}")
                        elif st in ('NAME', 'XOWN', 'XRNK', 'FULL'):
                            if ss >= 4:
                                val = struct.unpack_from('<I', sd, 0)[0]
                                print(f"    [{sp:6d}] {st} ({ss:5d}): 0x{val:08X}")
                            else:
                                print(f"    [{sp:6d}] {st} ({ss:5d}): {sd.hex()}")
                        elif st == 'DATA':
                            if ss >= 24:
                                # Position data
                                x, y, z = struct.unpack_from('<fff', sd, 0)
                                rx, ry, rz = struct.unpack_from('<fff', sd, 12)
                                print(f"    [{sp:6d}] {st} ({ss:5d}): pos=({x:.1f},{y:.1f},{z:.1f}) rot=({rx:.1f},{ry:.1f},{rz:.1f})")
                            else:
                                print(f"    [{sp:6d}] {st} ({ss:5d}): {sd.hex()}")
                        elif st == 'PNAM':
                            if ss >= 4:
                                val = struct.unpack_from('<I', sd, 0)[0]
                                print(f"    [{sp:6d}] {st} ({ss:5d}): parent=0x{val:08X}")
                        elif st in ('JREC', 'JCTX', 'JACT'):
                            print(f"    [{sp:6d}] {st} ({ss:5d}): {sd[:20].hex()}")
                        elif ss <= 40:
                            ascii_repr = ''.join(chr(b) if 32 <= b < 127 else '.' for b in sd[:40])
                            print(f"    [{sp:6d}] {st} ({ss:5d}): {sd[:40].hex()} | {ascii_repr}")
                        else:
                            print(f"    [{sp:6d}] {st} ({ss:5d}): {sd[:20].hex()}...")

                        sp += 6 + ss

                    # Count subrecord types
                    from collections import Counter
                    type_counts = Counter(sub_types)
                    print(f"\n  Subrecord type counts: {dict(type_counts)}")

                    # Check for GRUP inside
                    if 'GRUP' in sub_types:
                        print(f"\n  *** HAS NESTED GRUP - looking for REFRs inside ***")

            inner = data_end

    return grp_end

while pos < len(data):
    if data[pos:pos+4] == b'GRUP':
        pos = parse_group(pos)
    else:
        if pos + HEADER_SIZE > len(data):
            break
        rec_size = struct.unpack_from('<I', data, pos+4)[0]
        pos += HEADER_SIZE + rec_size
