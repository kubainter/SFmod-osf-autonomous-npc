import sys, struct, os
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

def parse_race(path):
    with open(path, 'rb') as f:
        data = f.read()
    tes4_size = struct.unpack_from('<I', data, 4)[0]
    pos = 24 + tes4_size
    while pos < len(data) - 24:
        if data[pos:pos+4] != b'GRUP':
            break
        grup_size = struct.unpack_from('<I', data, pos+4)[0]
        grup_label = data[pos+8:pos+12]
        grup_end = pos + grup_size
        if grup_label == b'RACE':
            rec_pos = pos + 24
            while rec_pos < grup_end - 24:
                rec_type = data[rec_pos:rec_pos+4]
                rec_size = struct.unpack_from('<I', data, rec_pos+4)[0]
                rec_end = rec_pos + 24 + rec_size
                if rec_type == b'RACE':
                    form_id = struct.unpack_from('<I', data, rec_pos+12)[0]
                    if form_id == 0x0000347D:
                        subs = {}
                        sub_pos = rec_pos + 24
                        while sub_pos < rec_end - 6:
                            st = data[sub_pos:sub_pos+4]; sub_pos += 4
                            ss = struct.unpack_from('<H', data, sub_pos)[0]; sub_pos += 2
                            sd = data[sub_pos:sub_pos+ss]; sub_pos += ss
                            name = st.decode('ascii', errors='replace')
                            subs[name] = subs.get(name, 0) + 1
                        return subs
                rec_pos = rec_end
        pos = grup_end
    return None

plugins = [
    ('SnuSnuField.esm', r'G:\Starfield\Data\SnuSnuField.esm'),
    ('Dick.esm', r'G:\Starfield\Data\Dick.esm'),
    ('SFF Body Replacer.esm', r'G:\Starfield\Data\SFF Body Replacer.esm'),
    ('Haters Body.esm', r'G:\Starfield\Data\Haters Body.esm'),
]

print("=== HumanRace (0x347D) subrecords per plugin ===")
print(f"{'Plugin':<30} {'FDSI':>5} {'FDSL':>5} {'MPGM':>5} {'FMRN':>5} {'HEAD':>5}")
print("-" * 65)
for name, path in plugins:
    if os.path.exists(path):
        subs = parse_race(path)
        if subs:
            print(f"{name:<30} {subs.get('FDSI',0):>5} {subs.get('FDSL',0):>5} {subs.get('MPGM',0):>5} {subs.get('FMRN',0):>5} {subs.get('HEAD',0):>5}")
        else:
            print(f"{name:<30}  --- no HumanRace record ---")
    else:
        print(f"{name:<30}  FILE NOT FOUND")
print(f"{'Vanilla':<30} {'98':>5} {'80':>5} {'162':>5} {'40':>5} {'14':>5}")
