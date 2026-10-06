import struct

with open(r'G:\Starfield\Data\OSFAutonomous.esm', 'rb') as f:
    b = f.read()

print(f'File size: {len(b)} bytes')
print()

# Parse TES4 record
assert b[0:4] == b'TES4', f'Expected TES4, got {b[0:4]}'
tes4_size = struct.unpack('<I', b[4:8])[0]
tes4_flags = struct.unpack('<I', b[8:12])[0]
tes4_formid = struct.unpack('<I', b[12:16])[0]
tes4_vc = struct.unpack('<I', b[16:20])[0]
tes4_ver = struct.unpack('<H', b[20:22])[0]
print(f'TES4: size={tes4_size} flags=0x{tes4_flags:08X} formID=0x{tes4_formid:08X} vc=0x{tes4_vc:08X} ver=0x{tes4_ver:04X}')

# Parse TES4 subrecords
offset = 24
subrecords = {}
while offset < 24 + tes4_size:
    sname = b[offset:offset+4].decode('ascii')
    slen = struct.unpack('<H', b[offset+4:offset+6])[0]
    sdata = b[offset+6:offset+6+slen]
    subrecords[sname] = sdata
    print(f'  {sname}: size={slen}', end='')
    if sname == 'HEDR':
        ver, count, flags = struct.unpack('<fII', sdata)
        print(f' version={ver} count={count} flags=0x{flags:08X}')
    elif sname == 'CNAM':
        print(f' value="{sdata[:-1].decode("ascii")}"')
    elif sname == 'MAST':
        print(f' master="{sdata[:-1].decode("ascii")}"')
    elif sname == 'BNAM':
        print(f' author="{sdata[:-1].decode("ascii")}"')
    else:
        print(f' data={sdata.hex()}')
    offset += 6 + slen

# Verify HEDR
assert 'HEDR' in subrecords, 'Missing HEDR'
assert 'CNAM' in subrecords, 'Missing CNAM'
assert 'MAST' in subrecords, 'Missing MAST'

# Parse GRUP
grup_offset = 24 + tes4_size
assert b[grup_offset:grup_offset+4] == b'GRUP', f'Expected GRUP at {grup_offset}'
grup_size = struct.unpack('<I', b[grup_offset+4:grup_offset+8])[0]
grup_label = b[grup_offset+8:grup_offset+12].decode('ascii')
grup_type = struct.unpack('<I', b[grup_offset+12:grup_offset+16])[0]
print(f'\nGRUP: size={grup_size} label={grup_label} type={grup_type}')

# Parse QUST record
quest_offset = grup_offset + 24
assert b[quest_offset:quest_offset+4] == b'QUST', f'Expected QUST at {quest_offset}'
quest_size = struct.unpack('<I', b[quest_offset+4:quest_offset+8])[0]
quest_flags = struct.unpack('<I', b[quest_offset+8:quest_offset+12])[0]
quest_formid = struct.unpack('<I', b[quest_offset+12:quest_offset+16])[0]
quest_vc = struct.unpack('<I', b[quest_offset+16:quest_offset+20])[0]
quest_ver = struct.unpack('<H', b[quest_offset+20:quest_offset+22])[0]
print(f'QUST: size={quest_size} flags=0x{quest_flags:08X} formID=0x{quest_formid:08X} vc=0x{quest_vc:08X} ver=0x{quest_ver:04X}')

# Parse QUST subrecords
offset = quest_offset + 24
while offset < quest_offset + 24 + quest_size:
    sname = b[offset:offset+4].decode('ascii')
    slen = struct.unpack('<H', b[offset+4:offset+6])[0]
    sdata = b[offset+6:offset+6+slen]
    print(f'  {sname}: size={slen}', end='')
    if sname == 'EDID':
        print(f' value="{sdata[:-1].decode("ascii")}"')
    elif sname == 'FULL':
        print(f' value="{sdata[:-1].decode("ascii")}"')
    elif sname == 'DNAM':
        flags_val = struct.unpack('<H', sdata[0:2])[0]
        print(f' flags=0x{flags_val:04X}')
    elif sname == 'VMAD':
        vmad_ver = struct.unpack('<H', sdata[0:2])[0]
        vmad_fmt = struct.unpack('<H', sdata[2:4])[0]
        vmad_count = struct.unpack('<H', sdata[4:6])[0]
        print(f' version={vmad_ver} format={vmad_fmt} scriptCount={vmad_count}')
        # Parse script name
        name_len = struct.unpack('<H', sdata[6:8])[0]
        script_name = sdata[8:8+name_len].decode('utf-8')
        script_status = sdata[8+name_len]
        prop_count = struct.unpack('<H', sdata[8+name_len+1:8+name_len+3])[0]
        print(f'    script="{script_name}" status={script_status} props={prop_count}')
    elif sname == 'NEXT':
        next_id = struct.unpack('<I', sdata)[0]
        print(f' nextFormID=0x{next_id:08X}')
    else:
        print(f' data={sdata.hex()}')
    offset += 6 + slen

# Summary
print(f'\n=== Summary ===')
print(f'TES4 + GRUP total: {grup_offset + grup_size} bytes (file: {len(b)} bytes)')
print(f'Match: {grup_offset + grup_size == len(b)}')
print(f'Masters: Starfield.esm only')
print(f'Quest FormID: 0x{quest_formid:08X}')
print(f'Record version: 0x{quest_ver:04X}')
print(f'CNAM: {subrecords["CNAM"][:-1].decode("ascii")}')
