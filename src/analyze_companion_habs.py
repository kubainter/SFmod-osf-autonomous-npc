#!/usr/bin/env python3
import os
"""Check for NAVM records, and parse PKIN REFRs to find what furniture is placed in companion habs."""
import struct
import sys
import zlib
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

HEADER_SIZE = 24
GRUP_HEADER_SIZE = 24

def parse_all_records(filepath):
    """Parse ESM and return all records by type, including NAVM and REFRs inside PKINs."""
    with open(filepath, 'rb') as f:
        data = f.read()

    record_types_found = set()
    navm_count = 0
    pkin_furniture_refrs = []  # (pkin_edid, refr_formid, base_object, has_xown)
    all_pkin_refrs = {}  # pkin_edid -> [(refr_formid, base_object, has_xown, edid)]

    tes4_size = struct.unpack_from('<I', data, 4)[0]
    pos = HEADER_SIZE + tes4_size

    def parse_record(pos, parent_pkin=None):
        nonlocal navm_count

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

        record_types_found.add(rec_type)

        if rec_type == 'NAVM':
            navm_count += 1

        # Handle compressed
        if rec_flags & 0x00040000:
            try:
                uncomp_size = struct.unpack_from('<I', data, data_start)[0]
                comp_data = data[data_start+4:data_end]
                decomp = zlib.decompress(comp_data)
                parse_data = decomp
                parse_start = 0
                parse_end = len(decomp)
            except:
                return rec_type, data_end
        else:
            parse_data = data
            parse_start = data_start
            parse_end = data_end

        if rec_type == 'PKIN':
            # Get PKIN EDID
            pkin_edid = ''
            p = parse_start
            while p + 6 <= parse_end:
                st = parse_data[p:p+4].decode('ascii', errors='replace')
                ss = struct.unpack_from('<H', parse_data, p+4)[0]
                if p + 6 + ss > parse_end:
                    break
                sd = parse_data[p+6:p+6+ss]
                if st == 'EDID':
                    pkin_edid = sd.split(b'\x00')[0].decode('ascii', errors='replace')
                    break
                p += 6 + ss

            # Look for nested GRUP with REFRs
            p2 = parse_start
            while p2 + GRUP_HEADER_SIZE <= parse_end:
                if parse_data[p2:p2+4] == b'GRUP':
                    grp_size = struct.unpack_from('<I', parse_data, p2+4)[0]
                    grp_end = min(p2 + grp_size, parse_end)
                    inner = p2 + GRUP_HEADER_SIZE

                    if pkin_edid not in all_pkin_refrs:
                        all_pkin_refrs[pkin_edid] = []

                    while inner + HEADER_SIZE <= grp_end:
                        rt = parse_data[inner:inner+4].decode('ascii', errors='replace')
                        rs = struct.unpack_from('<I', parse_data, inner+4)[0]
                        rflags = struct.unpack_from('<I', parse_data, inner+8)[0]
                        rformid = struct.unpack_from('<I', parse_data, inner+12)[0]
                        rdata_start = inner + HEADER_SIZE
                        rdata_end = rdata_start + rs

                        if rdata_end > grp_end:
                            break

                        if rt == 'REFR':
                            # Parse REFR for NAME and XOWN
                            refr_edid = ''
                            base_obj = None
                            has_xown = False
                            rp = rdata_start
                            while rp + 6 <= rdata_end:
                                rst = parse_data[rp:rp+4].decode('ascii', errors='replace')
                                rss = struct.unpack_from('<H', parse_data, rp+4)[0]
                                if rp + 6 + rss > rdata_end:
                                    break
                                rsd = parse_data[rp+6:rp+6+rss]
                                if rst == 'EDID':
                                    refr_edid = rsd.split(b'\x00')[0].decode('ascii', errors='replace')
                                elif rst == 'NAME':
                                    if rss >= 4:
                                        base_obj = struct.unpack_from('<I', rsd, 0)[0]
                                elif rst == 'XOWN':
                                    has_xown = True
                                rp += 6 + rss

                            all_pkin_refrs[pkin_edid].append((rformid, base_obj, has_xown, refr_edid))

                        if rt == 'NAVM':
                            navm_count += 1

                        if rdata_end <= inner:
                            break
                        inner = rdata_end

                    p2 = grp_end
                else:
                    ss = struct.unpack_from('<H', parse_data, p2+4)[0] if p2 + 6 <= parse_end else 0
                    p2 += 6 + ss

        return rec_type, data_end

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
                _, inner = parse_record(inner)

        return grp_end

    while pos < len(data):
        if data[pos:pos+4] == b'GRUP':
            pos = parse_group(pos)
        else:
            _, pos = parse_record(pos)

    return record_types_found, navm_count, all_pkin_refrs

if __name__ == '__main__':
    filepath = os.environ.get("STARFIELD_ROOT", ".") + r"\\Data\\stroudpremiumedition.esm"
    print(f"Analyzing: {filepath}\n")

    rec_types, navm_count, pkin_refrs = parse_all_records(filepath)

    print(f"Record types found: {sorted(rec_types)}")
    print(f"NAVM records found: {navm_count}")
    print(f"PKINs with REFRs: {len(pkin_refrs)}")

    # Known FURN base IDs from our earlier analysis
    custom_furn_ids = {
        0xFD012DE1: 'Vince134_WorkbenchResearch',
        0xFD01CEBA: 'Vince134_BrigBed03',
        0xFD01CA74: 'Vince134_BrigBed02',
        0xFD012A3A: 'Vince134_NPCPullUpBar',
        0xFD0177F3: 'Vince134_NPCSitOnGround_PlayerFriendly',
        0xFD018AD5: 'Vince134_Ship_ToiletSit01_FURN',
        0xFD01CA69: 'Vince134_BrigBed01',
        0xFD012DF3: 'Vince134_WorkbenchChem',
        0xFD01872E: 'Vince134_NPCChairLodgeOpenArm01',
        0xFD016C17: 'Vince134_WorkbenchWeapon',
        0xFD019D1F: 'Vince134_Template_ShipChair_Cockpit_Console',
        0xFD019BE2: 'Vince134_ShipChair_Cockpit_01_Console',
        0xFD01872A: 'Vince134_NPCChairOfficeMod02_Desk',
        0xFD012DD6: 'Vince134_WorkbenchIndustrial',
        0xFD010F41: 'Vince134_WorkingStove',
        0xFD017C5F: 'Vince134_NPCPushUp',
        0xFD012251: 'Vince134_WorkbenchArmor',
        0xFD0148CB: 'Vince134_Bed_Double03_Alt02',
    }

    # Analyze companion habs
    companion_keywords = ['sarahroom', 'barrettroom', 'samroom', 'andrejaroom',
                          'coraroom', 'shipdoctorroom', 'crewroom']

    print(f"\n{'='*120}")
    print("FURNITURE IN COMPANION HAB PKINs:")

    for pkin_name, refrs in sorted(pkin_refrs.items()):
        if not any(kw in pkin_name.lower() for kw in companion_keywords):
            continue

        # Find furniture REFRs (those referencing custom FURN or vanilla furniture)
        furn_refrs = []
        for refr_id, base_obj, has_xown, edid in refrs:
            if base_obj in custom_furn_ids:
                furn_refrs.append((refr_id, base_obj, has_xown, edid, custom_furn_ids[base_obj]))

        if furn_refrs:
            print(f"\n  PKIN: {pkin_name} ({len(refrs)} total REFRs, {len(furn_refrs)} furniture)")
            for rid, base, xown, edid, base_name in furn_refrs:
                xown_mark = " [XOWN!]" if xown else ""
                print(f"    REFR 0x{rid:08X} -> base 0x{base:08X} ({base_name}){xown_mark}")

    # Also check: what are the most common base objects in companion habs?
    print(f"\n{'='*120}")
    print("ALL BASE OBJECTS in companion hab PKINs (frequency):")

    base_freq = {}
    for pkin_name, refrs in pkin_refrs.items():
        if not any(kw in pkin_name.lower() for kw in companion_keywords):
            continue
        for refr_id, base_obj, has_xown, edid in refrs:
            if base_obj is not None:
                key = base_obj
                if key not in base_freq:
                    base_freq[key] = {'count': 0, 'xown_count': 0, 'pkins': set()}
                base_freq[key]['count'] += 1
                if has_xown:
                    base_freq[key]['xown_count'] += 1
                base_freq[key]['pkins'].add(pkin_name)

    for base_id, info in sorted(base_freq.items(), key=lambda x: -x[1]['count'])[:30]:
        custom_name = custom_furn_ids.get(base_id, '')
        xown_info = f" (XOWN on {info['xown_count']})" if info['xown_count'] > 0 else ""
        print(f"  0x{base_id:08X}: {info['count']} refs in {len(info['pkins'])} PKINs{xown_info} {custom_name}")

    # Check specifically for XOWN in companion hab REFRs
    print(f"\n{'='*120}")
    print("REFRs WITH XOWN in companion hab PKINs:")
    xown_in_companion = 0
    for pkin_name, refrs in pkin_refrs.items():
        if not any(kw in pkin_name.lower() for kw in companion_keywords):
            continue
        for refr_id, base_obj, has_xown, edid in refrs:
            if has_xown:
                xown_in_companion += 1
                base_hex = f"0x{base_obj:08X}" if base_obj else "unknown"
                custom = custom_furn_ids.get(base_obj, '')
                print(f"  PKIN={pkin_name} REFR=0x{refr_id:08X} base={base_hex} {custom}")

    if xown_in_companion == 0:
        print("  NONE - No XOWN on any REFR in companion hab PKINs!")
