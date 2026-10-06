#!/usr/bin/env python3
import os
"""Parse PKIN/REFR records in StroudPremium ESM to find per-reference ownership (XOWN)."""
import struct
import sys
import zlib
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

HEADER_SIZE = 24
GRUP_HEADER_SIZE = 24

def parse_refr(data, start, end, formid):
    """Parse a REFR record to find ownership and base object."""
    pos = start
    refr = {
        'formid': formid, 'edid': '', 'base_object': None,
        'ownership': None, 'xown_faction': None,
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
        elif sub_type == 'XRNK':
            pass  # ownership rank
        elif sub_type == 'XGLB':
            pass  # global variable for ownership

        pos += 6 + sub_size

    return refr

def parse_pkin(data, start, end, formid):
    """Parse a PKIN record — contains REFR records as subrecords or nested GRUPs."""
    pos = start
    pkin = {
        'formid': formid, 'edid': '', 'refrs': [],
        'has_furn_refs': False, 'furn_with_ownership': [],
    }

    # PKIN data starts with subrecords, then has a GRUP containing REFRs
    while pos + 6 <= end:
        sub_type = data[pos:pos+4].decode('ascii', errors='replace')
        sub_size = struct.unpack_from('<H', data, pos+4)[0]
        if pos + 6 + sub_size > end:
            break
        sub_data = data[pos+6:pos+6+sub_size]

        if sub_type == 'EDID':
            pkin['edid'] = sub_data.split(b'\x00')[0].decode('ascii', errors='replace')

        pos += 6 + sub_size

    return pkin

def parse_esm_pkin(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()

    pkin_records = []
    refr_with_ownership = []
    pos = 0

    # Skip TES4
    tes4_size = struct.unpack_from('<I', data, 4)[0]
    pos = HEADER_SIZE + tes4_size

    def parse_record(pos, inside_pkin=False):
        if pos + HEADER_SIZE > len(data):
            return None, len(data)

        rec_type = data[pos:pos+4].decode('ascii', errors='replace')
        rec_size = struct.unpack_from('<I', data, pos+4)[0]
        rec_flags = struct.unpack_from('<I', data, pos+8)[0]
        rec_formid = struct.unpack_from('<I', data, pos+12)[0]

        data_start = pos + HEADER_SIZE
        data_end = data_start + rec_size

        if data_end > len(data):
            return None, len(data)

        if rec_flags & 0x00040000:
            try:
                uncomp_size = struct.unpack_from('<I', data, data_start)[0]
                comp_data = data[data_start+4:data_end]
                decomp = zlib.decompress(comp_data)
                if rec_type == 'PKIN':
                    rec = parse_pkin(decomp, 0, len(decomp), rec_formid)
                    return ('PKIN', rec), data_end
                elif rec_type == 'REFR':
                    refr = parse_refr(decomp, 0, len(decomp), rec_formid)
                    return ('REFR', refr), data_end
            except:
                pass
            return None, data_end

        if rec_type == 'PKIN':
            rec = parse_pkin(data, data_start, data_end, rec_formid)
            return ('PKIN', rec), data_end
        elif rec_type == 'REFR':
            refr = parse_refr(data, data_start, data_end, rec_formid)
            if refr['ownership'] is not None:
                refr_with_ownership.append(refr)
            return ('REFR', refr), data_end

        return None, data_end

    def parse_group(pos, depth=0):
        if pos + GRUP_HEADER_SIZE > len(data):
            return len(data)

        grp_size = struct.unpack_from('<I', data, pos+4)[0]
        grp_label = data[pos+8:pos+12].decode('ascii', errors='replace')
        grp_type = struct.unpack_from('<I', data, pos+12)[0]
        grp_end = pos + grp_size
        inner = pos + GRUP_HEADER_SIZE

        while inner < grp_end:
            if data[inner:inner+4] == b'GRUP':
                inner = parse_group(inner, depth+1)
            else:
                result, inner = parse_record(inner)
                if result and result[0] == 'PKIN':
                    pkin_records.append(result[1])

        return grp_end

    while pos < len(data):
        if data[pos:pos+4] == b'GRUP':
            pos = parse_group(pos)
        else:
            result, pos = parse_record(pos)
            if result and result[0] == 'PKIN':
                pkin_records.append(result[1])

    return pkin_records, refr_with_ownership

if __name__ == '__main__':
    filepath = os.environ.get("STARFIELD_ROOT", ".") + r"\\Data\\stroudpremiumedition.esm"
    print(f"Parsing PKIN records from: {filepath}\n")

    pkins, refr_owns = parse_esm_pkin(filepath)

    print(f"Found {len(pkins)} PKIN records")
    print(f"Found {len(refr_owns)} REFR records with ownership (across all types)\n")

    # Filter for companion/crew/doctor/cora related PKINs
    companion_pkins = [p for p in pkins if any(x in p['edid'].lower() for x in
        ['companion', 'crew', 'cora', 'doctor', 'barrett', 'sarah', 'sam', 'andreja',
         'room', 'dormitory', 'hab', 'quarter'])]

    print(f"Companion/crew/room-related PKINs: {len(companion_pkins)}")
    print()

    # Show all PKINs with companion-related names
    for p in companion_pkins:
        print(f"  PKIN 0x{p['formid']:08X}: {p['edid']}")

    # Show all REFRs with ownership
    if refr_owns:
        print(f"\n{'='*120}")
        print(f"ALL REFR records with ownership ({len(refr_owns)}):")
        for r in refr_owns:
            base = f"base=0x{r['base_object']:08X}" if r['base_object'] else "no base"
            print(f"  REFR 0x{r['formid']:08X}: edid={r['edid']:<30s} {base} owner=0x{r['ownership']:08X}")

    # Also show all PKINs (there might be many)
    print(f"\n{'='*120}")
    print(f"All PKIN records ({len(pkins)}):")
    for p in pkins[:50]:
        print(f"  0x{p['formid']:08X}: {p['edid']}")
    if len(pkins) > 50:
        print(f"  ... and {len(pkins)-50} more")
