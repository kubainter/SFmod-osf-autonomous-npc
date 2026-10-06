#!/usr/bin/env python3
"""Analiza Dick.esm — jakie stany/rozmiary definiuje i jak SnuSnuField.esm ich uzywa."""
import struct
import sys
import zlib

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

DICK = r'G:\Starfield\Data\Dick.esm'
SNUSNU = r'G:\Starfield\Data\SnuSnuField.esm'

HEADER_SIZE = 24
GRUP_HEADER_SIZE = 24

def read_file(path):
    with open(path, 'rb') as f:
        return f.read()

def parse_subrecords(body):
    subs = []
    p = 0
    while p + 6 <= len(body):
        st = body[p:p+4].decode('ascii', errors='replace')
        ss = struct.unpack_from('<H', body, p+4)[0]
        if p + 6 + ss > len(body):
            break
        sd = body[p+6:p+6+ss]
        subs.append((st, sd))
        p += 6 + ss
    return subs

def get_edid(subs):
    for st, sd in subs:
        if st == 'EDID':
            return sd.split(b'\x00')[0].decode('ascii', errors='replace')
    return ''

def get_full(subs):
    for st, sd in subs:
        if st == 'FULL':
            return sd.split(b'\x00')[0].decode('utf-8', errors='replace')
    return ''

def parse_all_records(data):
    """Liniowy skan wszystkich rekordow."""
    tes4_size = struct.unpack_from('<I', data, 4)[0]
    pos = HEADER_SIZE + tes4_size
    records = []

    def scan(pos):
        if pos + GRUP_HEADER_SIZE > len(data):
            return len(data)
        grp_size = struct.unpack_from('<I', data, pos+4)[0]
        grp_end = pos + grp_size
        inner = pos + GRUP_HEADER_SIZE
        while inner < grp_end:
            if data[inner:inner+4] == b'GRUP':
                inner = scan(inner)
            else:
                if inner + HEADER_SIZE > len(data):
                    break
                rec_type = data[inner:inner+4].decode('ascii', errors='replace')
                rec_size = struct.unpack_from('<I', data, inner+4)[0]
                rec_flags = struct.unpack_from('<I', data, inner+8)[0]
                rec_formid = struct.unpack_from('<I', data, inner+12)[0]
                data_start = inner + HEADER_SIZE
                data_end = data_start + rec_size
                rec_data = data[data_start:data_end]

                body = rec_data
                if rec_flags & 0x00040000:
                    try:
                        if len(rec_data) >= 4:
                            uncomp_size = struct.unpack_from('<I', rec_data, 0)[0]
                            body = zlib.decompress(rec_data[4:])
                    except:
                        body = rec_data

                subs = parse_subrecords(body)
                records.append({
                    'type': rec_type,
                    'formid': rec_formid,
                    'flags': rec_flags,
                    'edid': get_edid(subs),
                    'full': get_full(subs),
                    'subs': subs,
                })
                inner = data_end
        return grp_end

    while pos < len(data):
        if data[pos:pos+4] == b'GRUP':
            pos = scan(pos)
        else:
            if pos + HEADER_SIZE > len(data):
                break
            rec_size = struct.unpack_from('<I', data, pos+4)[0]
            pos += HEADER_SIZE + rec_size

    return records

# === DICK.ESM ===
print("=" * 100)
print("DICK.ESM")
print("=" * 100)
dick_data = read_file(DICK)
dick_recs = parse_all_records(dick_data)

print(f"\nTotal records: {len(dick_recs)}")
type_counts = {}
for r in dick_recs:
    type_counts[r['type']] = type_counts.get(r['type'], 0) + 1
print(f"Record types: {type_counts}")

print("\nAll records:")
for r in dick_recs:
    fid_hex = f"0x{r['formid']:08X}"
    extra = ""
    if r['type'] in ('NPC_', 'ARMO', 'ARMA', 'STAT', 'FURN', 'KYMD', 'KEYW', 'FLST', 'PROJ', 'MISC'):
        extra = f"  FULL={r['full']}" if r['full'] else ""
    # Show subrecord names
    sub_names = [s[0] for s in r['subs']]
    print(f"  {r['type']:6s} {fid_hex}  EDID={r['edid']}{extra}  subs=[{','.join(sub_names)}]")

# === SNUSNU.ESM ===
print("\n" + "=" * 100)
print("SNUSNUFIELD.ESM")
print("=" * 100)
snu_data = read_file(SNUSNU)
snu_recs = parse_all_records(snu_data)

print(f"\nTotal records: {len(snu_recs)}")
type_counts2 = {}
for r in snu_recs:
    type_counts2[r['type']] = type_counts2.get(r['type'], 0) + 1
print(f"Record types: {type_counts2}")

# Szukaj referencji do Dick.esm
print("\nReferencje do Dick.esm (FormID 0x00xxxxxx z zakresu Dick):")
# Najpierw znajdz FormID z Dick.esm
dick_formids = {r['formid'] for r in dick_recs}
fids = [r['formid'] for r in dick_recs]
print(f"Dick.esm FormID range: 0x{min(fids):08X} - 0x{max(fids):08X}")

# Sprawdz czy SnuSnu ma MAST Dick.esm
tes4_size = struct.unpack_from('<I', snu_data, 4)[0]
pos = HEADER_SIZE
while pos + 6 <= HEADER_SIZE + tes4_size:
    st = snu_data[pos:pos+4].decode('ascii', errors='replace')
    ss = struct.unpack_from('<H', snu_data, pos+4)[0]
    sd = snu_data[pos+6:pos+6+ss]
    if st == 'MAST':
        print(f"  MAST: {sd.split(b'\x00')[0].decode()}")
    elif st == 'ONAM':
        count = ss // 4
        print(f"  ONAM: {count} formIDs")
    pos += 6 + ss

# Szukaj jakichkolwiek referencji w subrekordach SnuSnu do FormID z Dick
print("\nReferencje w SnuSnu do obiektow z Dick.esm:")
for r in snu_recs:
    for st, sd in r['subs']:
        # Sprawdz czy jakis 4-bajtowy fragment pasuje do Dick FormID
        for i in range(0, len(sd) - 3, 4):
            fid = struct.unpack_from('<I', sd, i)[0]
            if fid in dick_formids:
                target = next((d for d in dick_recs if d['formid'] == fid), None)
                tname = target['edid'] if target else "???"
                print(f"  {r['type']} {r['edid']} sub={st} -> 0x{fid:08X} ({tname})")
                break
