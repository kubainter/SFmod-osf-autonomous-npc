#!/usr/bin/env python3
import os
"""Check PKIN navmesh, FURN keywords vs vanilla, and PACK records for NPC restrictions."""
import struct
import sys
import zlib
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

HEADER_SIZE = 24
GRUP_HEADER_SIZE = 24

def parse_subrecords_flat(data, start, end):
    """Parse all subrecords in a data range, return list of (type, size, data)."""
    subs = []
    pos = start
    while pos + 6 <= end:
        sub_type = data[pos:pos+4].decode('ascii', errors='replace')
        sub_size = struct.unpack_from('<H', data, pos+4)[0]
        if pos + 6 + sub_size > end:
            break
        sub_data = data[pos+6:pos+6+sub_size]
        subs.append((sub_type, sub_size, sub_data))
        pos += 6 + sub_size
    return subs

def parse_pkin_navmesh(data, start, end, formid, edid):
    """Check if PKIN has navmesh data (NAVM records or navmesh references)."""
    pos = start
    has_navm = False
    has_navmesh_ref = False
    sub_types_found = set()

    # First pass: collect subrecord types
    while pos + 6 <= end:
        sub_type = data[pos:pos+4].decode('ascii', errors='replace')
        sub_size = struct.unpack_from('<H', data, pos+4)[0]
        if pos + 6 + sub_size > end:
            break
        sub_types_found.add(sub_type)

        if sub_type == 'NAVM':
            has_navm = True
        if sub_type == 'NNAM':
            has_navmesh_ref = True

        pos += 6 + sub_size

    # Check for nested GRUP with NAVM
    pos2 = start
    while pos2 + GRUP_HEADER_SIZE <= end:
        if data[pos2:pos2+4] == b'GRUP':
            grp_size = struct.unpack_from('<I', data, pos2+4)[0]
            grp_end = min(pos2 + grp_size, end)
            inner = pos2 + GRUP_HEADER_SIZE
            while inner + HEADER_SIZE <= grp_end:
                rec_type = data[inner:inner+4].decode('ascii', errors='replace')
                rec_size = struct.unpack_from('<I', data, inner+4)[0]
                if rec_type == 'NAVM':
                    has_navm = True
                inner += HEADER_SIZE + rec_size
            pos2 = grp_end
        else:
            sub_size = struct.unpack_from('<H', data, pos2+4)[0] if pos2 + 6 <= end else 0
            pos2 += 6 + sub_size

    return has_navm, has_navmesh_ref, sub_types_found

def parse_furn_keywords(data, start, end, formid):
    """Parse FURN and extract EDID + keywords."""
    pos = start
    edid = ''
    keywords = []
    furn_flags = 0
    fnpr_count = 0

    while pos + 6 <= end:
        sub_type = data[pos:pos+4].decode('ascii', errors='replace')
        sub_size = struct.unpack_from('<H', data, pos+4)[0]
        if pos + 6 + sub_size > end:
            break
        sub_data = data[pos+6:pos+6+sub_size]

        if sub_type == 'EDID':
            edid = sub_data.split(b'\x00')[0].decode('ascii', errors='replace')
        elif sub_type == 'KWDA':
            count = sub_size // 4
            for i in range(count):
                keywords.append(struct.unpack_from('<I', sub_data, i*4)[0])
        elif sub_type == 'FNAM':
            if sub_size >= 2:
                furn_flags = struct.unpack_from('<H', sub_data, 0)[0]
        elif sub_type == 'FNPR':
            if sub_size >= 4:
                fnpr_count = struct.unpack_from('<I', sub_data, 0)[0]

        pos += 6 + sub_size

    return edid, keywords, furn_flags, fnpr_count

def parse_pack(data, start, end, formid):
    """Parse PACK record for AI package info."""
    pos = start
    edid = ''
    pack_flags = 0
    pack_type = 0
    keywords = []

    while pos + 6 <= end:
        sub_type = data[pos:pos+4].decode('ascii', errors='replace')
        sub_size = struct.unpack_from('<H', data, pos+4)[0]
        if pos + 6 + sub_size > end:
            break
        sub_data = data[pos+6:pos+6+sub_size]

        if sub_type == 'EDID':
            edid = sub_data.split(b'\x00')[0].decode('ascii', errors='replace')
        elif sub_type == 'PKDT':
            if sub_size >= 4:
                pack_flags = struct.unpack_from('<I', sub_data, 0)[0]
        elif sub_type == 'PTDT':
            if sub_size >= 4:
                pack_type = struct.unpack_from('<I', sub_data, 0)[0]

        pos += 6 + sub_size

    return edid, pack_flags, pack_type

def parse_esm(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()

    pkin_navmesh_info = []
    furn_info = []
    pack_info = []
    pos = 0

    tes4_size = struct.unpack_from('<I', data, 4)[0]
    pos = HEADER_SIZE + tes4_size

    def parse_record(pos):
        if pos + HEADER_SIZE > len(data):
            return None, len(data), None, None

        rec_type = data[pos:pos+4].decode('ascii', errors='replace')
        rec_size = struct.unpack_from('<I', data, pos+4)[0]
        rec_flags = struct.unpack_from('<I', data, pos+8)[0]
        rec_formid = struct.unpack_from('<I', data, pos+12)[0]

        data_start = pos + HEADER_SIZE
        data_end = data_start + rec_size

        if data_end > len(data):
            return None, len(data), None, None

        if rec_flags & 0x00040000:
            try:
                uncomp_size = struct.unpack_from('<I', data, data_start)[0]
                comp_data = data[data_start+4:data_end]
                decomp = zlib.decompress(comp_data)
                data_to_parse = decomp
                parse_start = 0
                parse_end = len(decomp)
            except:
                return rec_type, data_end, None, None
        else:
            data_to_parse = data
            parse_start = data_start
            parse_end = data_end

        if rec_type == 'PKIN':
            # First get EDID
            edid = ''
            for st, ss, sd in parse_subrecords_flat(data_to_parse, parse_start, parse_end):
                if st == 'EDID':
                    edid = sd.split(b'\x00')[0].decode('ascii', errors='replace')
                    break

            has_navm, has_navmesh_ref, sub_types = parse_pkin_navmesh(
                data_to_parse, parse_start, parse_end, rec_formid, edid)
            return rec_type, data_end, ('PKIN', {
                'formid': rec_formid, 'edid': edid,
                'has_navmesh': has_navm, 'has_navmesh_ref': has_navmesh_ref,
                'sub_types': sub_types,
            }), None

        elif rec_type == 'FURN':
            edid, keywords, furn_flags, fnpr_count = parse_furn_keywords(
                data_to_parse, parse_start, parse_end, rec_formid)
            return rec_type, data_end, ('FURN', {
                'formid': rec_formid, 'edid': edid, 'keywords': keywords,
                'furn_flags': furn_flags, 'fnpr_count': fnpr_count,
            }), None

        elif rec_type == 'PACK':
            edid, pack_flags, pack_type = parse_pack(
                data_to_parse, parse_start, parse_end, rec_formid)
            return rec_type, data_end, ('PACK', {
                'formid': rec_formid, 'edid': edid,
                'flags': pack_flags, 'type': pack_type,
            }), None

        return rec_type, data_end, None, None

    def parse_group(pos):
        if pos + GRUP_HEADER_SIZE > len(data):
            return len(data)

        grp_size = struct.unpack_from('<I', data, pos+4)[0]
        grp_end = pos + grp_size
        inner = pos + GRUP_HEADER_SIZE

        while inner < grp_end:
            if data[inner:inner+4] == b'GRUP':
                inner = parse_group(inner)
            else:
                _, inner, result, _ = parse_record(inner)
                if result:
                    if result[0] == 'PKIN':
                        pkin_navmesh_info.append(result[1])
                    elif result[0] == 'FURN':
                        furn_info.append(result[1])
                    elif result[0] == 'PACK':
                        pack_info.append(result[1])

        return grp_end

    while pos < len(data):
        if data[pos:pos+4] == b'GRUP':
            pos = parse_group(pos)
        else:
            _, pos, result, _ = parse_record(pos)
            if result:
                if result[0] == 'PKIN':
                    pkin_navmesh_info.append(result[1])
                elif result[0] == 'FURN':
                    furn_info.append(result[1])
                elif result[0] == 'PACK':
                    pack_info.append(result[1])

    return pkin_navmesh_info, furn_info, pack_info

if __name__ == '__main__':
    filepath = os.environ.get("STARFIELD_ROOT", ".") + r"\\Data\\stroudpremiumedition.esm"
    print(f"Analyzing: {filepath}\n")

    pkins, furns, packs = parse_esm(filepath)

    # === PKIN navmesh analysis ===
    print(f"{'='*120}")
    print(f"PKIN NAVMESH ANALYSIS ({len(pkins)} PKINs):")

    companion_pkins = [p for p in pkins if any(x in p['edid'].lower() for x in
        ['sarahroom', 'barrettroom', 'samroom', 'andrejaroom', 'coraroom',
         'shipdoctorroom', 'crewroom', 'companionway', 'crewdormitory',
         'berthingall', 'livingquarters', 'cptquarters'])]

    print(f"\nCompanion/crew hab PKINs: {len(companion_pkins)}")
    for p in companion_pkins:
        nav_status = "HAS NAVMESH" if p['has_navmesh'] else "NO NAVMESH!!!"
        nav_ref = " + NNAM ref" if p['has_navmesh_ref'] else ""
        print(f"  0x{p['formid']:08X} {p['edid']:<55s} {nav_status}{nav_ref}")

    # Count PKINs with/without navmesh
    with_nav = [p for p in pkins if p['has_navmesh']]
    without_nav = [p for p in pkins if not p['has_navmesh']]
    print(f"\n  PKINs with navmesh: {len(with_nav)}")
    print(f"  PKINs without navmesh: {len(without_nav)}")

    if without_nav:
        print(f"\n  PKINs WITHOUT NAVMESH (NPC can't walk here!):")
        for p in without_nav[:20]:
            print(f"    0x{p['formid']:08X} {p['edid']}")

    # === FURN keywords analysis ===
    print(f"\n{'='*120}")
    print(f"FURN KEYWORDS ANALYSIS ({len(furns)} FURNs):")
    for f in furns:
        print(f"\n  0x{f['formid']:08X} {f['edid']}")
        print(f"    FNAM=0x{f['furn_flags']:04X}, FNPR={f['fnpr_count']}")
        print(f"    Keywords: {', '.join(f'0x{k:08X}' for k in f['keywords'])}")

    # === PACK analysis ===
    print(f"\n{'='*120}")
    print(f"PACK (AI Package) ANALYSIS ({len(packs)} PACKs):")
    for p in packs:
        print(f"  0x{p['formid']:08X} {p['edid']} flags=0x{p['flags']:08X} type={p['type']}")
