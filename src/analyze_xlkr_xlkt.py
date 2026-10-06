#!/usr/bin/env python3
import os
"""Analiza XLKR (Linked Reference) i XLKT (Link Type) w 28 target REFR.
Sprawdza czy linki blokuja uzycie furniture (beds).

XLKR format w Starfield:
  - keyword FormID (4B) — referencja do KYMD
  - target FormID (4B) — referencja do innego REFR
  - flagi (1B?)

XLKT format:
  - keyword FormID (4B)
  - link type (1B)
"""
import struct
import sys
from collections import defaultdict

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

SOURCE = os.environ.get("STARFIELD_ROOT", ".") + r"\\Data\\stroudpremiumedition.esm"
STARFIELD = os.environ.get("STARFIELD_ROOT", ".") + r"\\Data\\Starfield.esm"

target_refrs = {
    0xFD017809, 0xFD01257F, 0xFD01288E, 0xFD0129E4, 0xFD0178BE,
    0xFD012285, 0xFD017A95, 0xFD01230F, 0xFD017A2E, 0xFD012586,
    0xFD0123F4, 0xFD012911, 0xFD017523, 0xFD0179C8, 0xFD0127FB,
    0xFD013F14, 0xFD01795D, 0xFD013E8F, 0xFD01768E, 0xFD017680,
    0xFD0176A8, 0xFD0176A4, 0xFD0178D2, 0xFD01766D, 0xFD01765F,
    0xFD0178E5, 0xFD01706A, 0xFD012280,
}

# NPC map
npc_names = {
    0x00005787: "Companion_Barrett",
    0x00005983: "Companion_SarahMorgan",
    0x00005999: "Companion_SamCoe",
    0x000059A7: "Companion_Andreja",
    0x0000D653: "COM_CoraCoe",
    0x001D635D: "Crew_Elite_RosieTannehill",
}

HEADER_SIZE = 24
GRUP_HEADER_SIZE = 24

with open(SOURCE, 'rb') as f:
    data = f.read()

tes4_size = struct.unpack_from('<I', data, 4)[0]
pos = HEADER_SIZE + tes4_size

refr_info = {}
group_stack = []

def parse_subrecords(data, start, end):
    subs = []
    p = start
    while p + 6 <= end:
        st = data[p:p+4].decode('ascii', errors='replace')
        ss = struct.unpack_from('<H', data, p+4)[0]
        if p + 6 + ss > end:
            break
        sd = data[p+6:p+6+ss]
        subs.append((st, sd))
        p += 6 + ss
    return subs

def parse(pos):
    if pos + GRUP_HEADER_SIZE > len(data):
        return len(data)

    grp_size = struct.unpack_from('<I', data, pos+4)[0]
    grp_label = data[pos+8:pos+12]
    grp_type = struct.unpack_from('<I', data, pos+12)[0]
    grp_end = pos + grp_size
    inner = pos + GRUP_HEADER_SIZE

    if grp_type == 6:
        group_stack.append(('cell', struct.unpack_from('<I', grp_label, 0)[0]))

    while inner < grp_end:
        if data[inner:inner+4] == b'GRUP':
            inner = parse(inner)
        else:
            if inner + HEADER_SIZE > len(data):
                break
            rec_type = data[inner:inner+4].decode('ascii', errors='replace')
            rec_size = struct.unpack_from('<I', data, inner+4)[0]
            rec_formid = struct.unpack_from('<I', data, inner+12)[0]
            data_start = inner + HEADER_SIZE
            data_end = data_start + rec_size

            if rec_type == 'REFR' and rec_formid in target_refrs:
                subs = parse_subrecords(data, data_start, data_end)
                cell_id = None
                for gtype, gval in group_stack:
                    if gtype == 'cell':
                        cell_id = gval
                refr_info[rec_formid] = {'cell': cell_id, 'subs': subs}

            inner = data_end

    if grp_type == 6:
        if group_stack:
            group_stack.pop()

    return grp_end

while pos < len(data):
    if data[pos:pos+4] == b'GRUP':
        pos = parse(pos)
    else:
        if pos + HEADER_SIZE > len(data):
            break
        rec_size = struct.unpack_from('<I', data, pos+4)[0]
        pos += HEADER_SIZE + rec_size

# Zbuduj mapę wszystkich REFR w ESM (do identyfikacji targetów XLKR)
all_refrs = {}  # formid -> {NAME, EDID, subs}

pos = HEADER_SIZE + tes4_size
def parse_all(pos):
    if pos + GRUP_HEADER_SIZE > len(data):
        return len(data)
    grp_size = struct.unpack_from('<I', data, pos+4)[0]
    grp_end = pos + grp_size
    inner = pos + GRUP_HEADER_SIZE
    while inner < grp_end:
        if data[inner:inner+4] == b'GRUP':
            inner = parse_all(inner)
        else:
            if inner + HEADER_SIZE > len(data):
                break
            rec_type = data[inner:inner+4].decode('ascii', errors='replace')
            rec_size = struct.unpack_from('<I', data, inner+4)[0]
            rec_formid = struct.unpack_from('<I', data, inner+12)[0]
            data_start = inner + HEADER_SIZE
            data_end = data_start + rec_size
            if rec_type == 'REFR':
                subs = parse_subrecords(data, data_start, data_end)
                name_fid = None
                for st, sd in subs:
                    if st == 'NAME' and len(sd) >= 4:
                        name_fid = struct.unpack_from('<I', sd, 0)[0]
                all_refrs[rec_formid] = {'NAME': name_fid, 'subs': subs}
            inner = data_end
    return grp_end

while pos < len(data):
    if data[pos:pos+4] == b'GRUP':
        pos = parse_all(pos)
    else:
        if pos + HEADER_SIZE > len(data):
            break
        rec_size = struct.unpack_from('<I', data, pos+4)[0]
        pos += HEADER_SIZE + rec_size

print(f"Total REFR in ESM: {len(all_refrs)}")

# Teraz analizuj XLKR/XLKT w target REFR
print("\n" + "=" * 120)
print("ANALIZA XLKR / XLKT / XLMS / XOWN w 28 target REFR")
print("=" * 120)

# Grupuj po cell
by_cell = defaultdict(list)
for fid, info in refr_info.items():
    by_cell[info['cell']].append(fid)

for cell_id in sorted(by_cell.keys()):
    cell_hex = f"0x{cell_id:08X}" if cell_id else "???"
    print(f"\n{'='*100}")
    print(f"CELL {cell_hex} ({len(by_cell[cell_id])} REFR)")
    print(f"{'='*100}")

    for fid in sorted(by_cell[cell_id]):
        fid_hex = f"{fid >> 24:02X}:{fid & 0xFFFFFF:06X}"
        info = refr_info[fid]
        subs = info['subs']

        # Wyciagnij kluczowe subrekordy
        name_fid = xown_fid = None
        xlkr_list = []
        xlkt_list = []
        xlms_data = None

        for st, sd in subs:
            if st == 'NAME' and len(sd) >= 4:
                name_fid = struct.unpack_from('<I', sd, 0)[0]
            elif st == 'XOWN' and len(sd) >= 4:
                xown_fid = struct.unpack_from('<I', sd, 0)[0]
            elif st == 'XLKR':
                xlkr_list.append(sd)
            elif st == 'XLKT':
                xlkt_list.append(sd)
            elif st == 'XLMS':
                xlms_data = sd

        owner = npc_names.get(xown_fid, f"0x{xown_fid:08X}" if xown_fid else "BRAK")
        name_hex = f"0x{name_fid:08X}" if name_fid else "brak"

        print(f"\n  REFR {fid_hex}  NAME={name_hex}  XOWN={owner}")

        # XLKR analiza
        for i, xlkr_sd in enumerate(xlkr_list):
            print(f"    XLKR[{i}]: {xlkr_sd.hex()} ({len(xlkr_sd)}B)")
            if len(xlkr_sd) >= 8:
                kw_fid = struct.unpack_from('<I', xlkr_sd, 0)[0]
                tgt_fid = struct.unpack_from('<I', xlkr_sd, 4)[0]
                tgt_info = all_refrs.get(tgt_fid, {})
                tgt_name = tgt_info.get('NAME', None)
                tgt_name_hex = f"0x{tgt_name:08X}" if tgt_name else "???"
                print(f"      keyword=0x{kw_fid:08X}, target=0x{tgt_fid:08X} (NAME={tgt_name_hex})")
            elif len(xlkr_sd) >= 4:
                kw_fid = struct.unpack_from('<I', xlkr_sd, 0)[0]
                print(f"      keyword=0x{kw_fid:08X} (tylko keyword, brak target)")

        # XLKT analiza
        for i, xlkt_sd in enumerate(xlkt_list):
            print(f"    XLKT[{i}]: {xlkt_sd.hex()} ({len(xlkt_sd)}B)")
            if len(xlkt_sd) >= 4:
                kw_fid = struct.unpack_from('<I', xlkt_sd, 0)[0]
                print(f"      keyword=0x{kw_fid:08X}")

        # XLMS analiza (furniture marker)
        if xlms_data:
            print(f"    XLMS: {xlms_data.hex()} ({len(xlms_data)}B)")
        else:
            print(f"    XLMS: brak")

# Podsumowanie: czy XLKR/XLKT sa identyczne dla wszystkich REFR tego samego companion?
print("\n" + "=" * 120)
print("PODSUMOWANIE: wzorce XLKR/XLKT per companion")
print("=" * 120)

companion_refrs = defaultdict(list)
for fid, info in refr_info.items():
    for st, sd in info['subs']:
        if st == 'XOWN' and len(sd) >= 4:
            xown = struct.unpack_from('<I', sd, 0)[0]
            companion_refrs[xown].append(fid)

for xown, fids in sorted(companion_refrs.items()):
    name = npc_names.get(xown, f"0x{xown:08X}")
    print(f"\n{name} ({len(fids)} REFR):")
    for fid in sorted(fids):
        info = refr_info[fid]
        subs = info['subs']
        xlkr_count = sum(1 for st, _ in subs if st == 'XLKR')
        xlkt_count = sum(1 for st, _ in subs if st == 'XLKT')
        has_xlms = any(st == 'XLMS' for st, _ in subs)
        name_fid = None
        for st, sd in subs:
            if st == 'NAME' and len(sd) >= 4:
                name_fid = struct.unpack_from('<I', sd, 0)[0]
        print(f"  {fid >> 24:02X}:{fid & 0xFFFFFF:06X}  NAME=0x{name_fid:08X}  XLKR={xlkr_count}  XLKT={xlkt_count}  XLMS={'tak' if has_xlms else 'nie'}")
