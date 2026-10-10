#!/usr/bin/env python3
import os
"""Parse PKIN records and their nested REFRs to find ownership on furniture in companion habs."""
import struct
import sys
import zlib
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

HEADER_SIZE = 24
GRUP_HEADER_SIZE = 24

def parse_refr_in_pkin(data, start, end, formid, pkin_edid):
    """Parse a REFR inside a PKIN."""
    pos = start
    refr = {
        'formid': formid, 'edid': '', 'base_object': None,
        'ownership': None, 'pkin': pkin_edid,
    }
    while pos + 6 <= end:
        sub_type = data[pos:pos+4].decode('ascii', errors='replace')
        sub_size = struct.unpack_from('<H', data, pos+4)[0]
        if pos + 6 + sub_size > end:
            break
        sub_data = data[pos+6:pos+6+sub_size]
        if sub_type == 'EDID':
            refr['edid'] = sub_data.split(b'\x00')[0].decode('ascii', errors='replace')
        elif sub_type == 'NAME':
            if sub_size >= 4:
                refr['base_object'] = struct.unpack_from('<I', sub_data, 0)[0]
        elif sub_type == 'XOWN':
            if sub_size >= 4:
                refr['ownership'] = struct.unpack_from('<I', sub_data, 0)[0]
        pos += 6 + sub_size
    return refr

def parse_pkin_with_refrs(data, start, end, formid):
    """Parse PKIN record including nested REFRs in sub-GRUPs."""
    pos = start
    pkin = {
        'formid': formid, 'edid': '', 'refrs_with_ownership': [],
        'all_refrs': 0, 'furn_refrs_with_ownership': [],
    }

    # First pass: find EDID
    while pos + 6 <= end:
        sub_type = data[pos:pos+4].decode('ascii', errors='replace')
        sub_size = struct.unpack_from('<H', data, pos+4)[0]
        if pos + 6 + sub_size > end:
            break
        sub_data = data[pos+6:pos+6+sub_size]

        if sub_type == 'EDID':
            pkin['edid'] = sub_data.split(b'\x00')[0].decode('ascii', errors='replace')

        pos += 6 + sub_size

    # Now look for nested GRUPs inside the PKIN data
    # The PKIN data may contain a GRUP with REFR children
    pos2 = start
    while pos2 + GRUP_HEADER_SIZE <= end:
        if data[pos2:pos2+4] == b'GRUP':
            grp_size = struct.unpack_from('<I', data, pos2+4)[0]
            grp_end = pos2 + grp_size
            if grp_end > end:
                grp_end = end

            # Parse REFRs inside this nested GRUP
            inner = pos2 + GRUP_HEADER_SIZE
            while inner + HEADER_SIZE <= grp_end:
                rec_type = data[inner:inner+4].decode('ascii', errors='replace')
                rec_size = struct.unpack_from('<I', data, inner+4)[0]
                rec_flags = struct.unpack_from('<I', data, inner+8)[0]
                rec_formid = struct.unpack_from('<I', data, inner+12)[0]
                rec_data_start = inner + HEADER_SIZE
                rec_data_end = rec_data_start + rec_size

                if rec_data_end > grp_end:
                    break

                if rec_type == 'REFR':
                    pkin['all_refrs'] += 1
                    # Check for ownership
                    refr = parse_refr_in_pkin(data, rec_data_start, rec_data_end, rec_formid, pkin['edid'])
                    if refr['ownership'] is not None:
                        pkin['refrs_with_ownership'].append(refr)

                if rec_data_end <= inner:
                    break
                inner = rec_data_end

            pos2 = grp_end
        else:
            # Skip non-GRUP subrecords
            sub_size = struct.unpack_from('<H', data, pos2+4)[0] if pos2 + 6 <= end else 0
            pos2 += 6 + sub_size

    return pkin

def parse_esm_full(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()

    pkin_records = []
    pos = 0

    tes4_size = struct.unpack_from('<I', data, 4)[0]
    pos = HEADER_SIZE + tes4_size

    def parse_record(pos):
        if pos + HEADER_SIZE > len(data):
            return None, len(data), None

        rec_type = data[pos:pos+4].decode('ascii', errors='replace')
        rec_size = struct.unpack_from('<I', data, pos+4)[0]
        rec_flags = struct.unpack_from('<I', data, pos+8)[0]
        rec_formid = struct.unpack_from('<I', data, pos+12)[0]

        data_start = pos + HEADER_SIZE
        data_end = data_start + rec_size

        if data_end > len(data):
            return None, len(data), None

        if rec_flags & 0x00040000:
            try:
                uncomp_size = struct.unpack_from('<I', data, data_start)[0]
                comp_data = data[data_start+4:data_end]
                decomp = zlib.decompress(comp_data)
                if rec_type == 'PKIN':
                    rec = parse_pkin_with_refrs(decomp, 0, len(decomp), rec_formid)
                    return rec_type, data_end, rec
            except:
                pass
            return rec_type, data_end, None

        if rec_type == 'PKIN':
            rec = parse_pkin_with_refrs(data, data_start, data_end, rec_formid)
            return rec_type, data_end, rec

        return rec_type, data_end, None

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
                _, inner, rec = parse_record(inner)
                if rec:
                    pkin_records.append(rec)

        return grp_end

    while pos < len(data):
        if data[pos:pos+4] == b'GRUP':
            pos = parse_group(pos)
        else:
            _, pos, rec = parse_record(pos)
            if rec:
                pkin_records.append(rec)

    return pkin_records

if __name__ == '__main__':
    filepath = os.environ.get("STARFIELD_ROOT", ".") + r"\\Data\\stroudpremiumedition.esm"
    print(f"Parsing PKIN records with nested REFRs: {filepath}\n")

    pkins = parse_esm_full(filepath)
    print(f"Found {len(pkins)} PKIN records\n")

    # Filter PKINs that have REFRs with ownership
    pkins_with_ownership = [p for p in pkins if p['refrs_with_ownership']]

    print(f"PKINs with REFR ownership: {len(pkins_with_ownership)}")
    print()

    # Known vanilla bed/furniture base IDs
    # 0x001E2800 = double bed (from OSF ge-doublebed.osf.json)
    # 0x00004688, 0x00004685 = beds (vanilla)
    # 0x001FA770 = furniture
    # 0x000361AF = furniture
    bed_bases = {0x001E2800, 0x00004688, 0x00004685, 0x00004684, 0x00004687, 0x00004686}

    for pkin in pkins_with_ownership:
        is_companion = any(x in pkin['edid'].lower() for x in
            ['companion', 'crew', 'cora', 'doctor', 'barrett', 'sarah', 'sam', 'andreja',
             'room', 'dormitory', 'quarter', 'berthing', 'capt', 'cpt'])

        marker = "*** COMPANION HAB ***" if is_companion else ""

        print(f"\nPKIN 0x{pkin['formid']:08X}: {pkin['edid']} {marker}")
        print(f"  Total REFRs: {pkin['all_refrs']}, With ownership: {len(pkin['refrs_with_ownership'])}")

        for refr in pkin['refrs_with_ownership']:
            base = refr['base_object']
            is_bed = base in bed_bases
            bed_marker = "[BED]" if is_bed else ""
            base_hex = f"0x{base:08X}" if base else "unknown"
            print(f"  REFR 0x{refr['formid']:08X}: base={base_hex} {bed_marker} owner=0x{refr['ownership']:08X}")

    # Summary of unique owners
    print(f"\n{'='*120}")
    print("UNIQUE OWNER FORMIDs:")
    owners = {}
    for pkin in pkins_with_ownership:
        for refr in pkin['refrs_with_ownership']:
            owner = refr['ownership']
            if owner not in owners:
                owners[owner] = []
            owners[owner].append((pkin['edid'], refr['base_object']))

    for owner_id, refs in sorted(owners.items()):
        print(f"\n  Owner 0x{owner_id:08X} ({len(refs)} refs):")
        for pkin_name, base in refs[:5]:
            base_hex = f"0x{base:08X}" if base else "unknown"
            print(f"    PKIN={pkin_name}, base={base_hex}")
        if len(refs) > 5:
            print(f"    ... and {len(refs)-5} more")

    # Summary of unique base objects with ownership
    print(f"\n{'='*120}")
    print("UNIQUE BASE OBJECT FORMIDs with ownership:")
    bases = {}
    for pkin in pkins_with_ownership:
        for refr in pkin['refrs_with_ownership']:
            base = refr['base_object']
            if base not in bases:
                bases[base] = []
            bases[base].append(refr['ownership'])

    for base_id, owner_list in sorted(bases.items()):
        unique_owners = set(owner_list)
        print(f"  Base 0x{base_id:08X}: {len(owner_list)} refs, owners: {', '.join(f'0x{o:08X}' for o in unique_owners)}")
