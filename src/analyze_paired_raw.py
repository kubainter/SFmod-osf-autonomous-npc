import os, glob

anim_dir = os.environ.get("STARFIELD_ROOT", ".") + r"\\Data\\SAF\\Animations"

# Categorize all root .glb files
files = [f for f in os.listdir(anim_dir) if f.endswith('.glb')]

# Group by prefix (remove bot/top suffix and number)
groups = {}
for f in files:
    name = f.replace('.glb', '')
    # Determine if bot or top
    is_bot = name.endswith('bot')
    is_top = name.endswith('top')
    # Extract base name
    base = name
    if is_bot:
        base = name[:-3]  # remove 'bot'
    elif is_top:
        base = name[:-3]  # remove 'top'
    
    # Group by category
    if base not in groups:
        groups[base] = {'bot': None, 'top': None, 'solo': None, 'files': []}
    
    if is_bot:
        groups[base]['bot'] = f
    elif is_top:
        groups[base]['top'] = f
    else:
        groups[base]['solo'] = f
    groups[base]['files'].append(f)

print("=== PAIRED ANIMATIONS (bot+top) ===")
paired = {}
for base in sorted(groups.keys):
    g = groups[base]
    if g['bot'] and g['top']:
        bot_size = os.path.getsize(os.path.join(anim_dir, g['bot'])) // 1024
        top_size = os.path.getsize(os.path.join(anim_dir, g['top'])) // 1024
        print(f"  {base}: bot={g['bot']} ({bot_size}KB) + top={g['top']} ({top_size}KB)")
        # Group by category prefix
        prefix = base.rstrip('0123456789')
        if prefix not in paired:
            paired[prefix] = []
        paired[prefix].append(base)
    elif g['solo']:
        size = os.path.getsize(os.path.join(anim_dir, g['solo'])) // 1024
        print(f"  SOLO: {base}: {g['solo']} ({size}KB)")

print()
print("=== CATEGORIES ===")
for prefix in sorted(paired.keys):
    bases = paired[prefix]
    print(f"  {prefix}: {len(bases)} variants")
    for b in bases:
        print(f"    {b}")

# Check if custom01x01bot == bridge01bot (same size pattern?)
print()
print("=== SIZE COMPARISON (check if duplicates) ===")
for base in sorted(groups.keys):
    g = groups[base]
    if g['bot'] and g['top']:
        bot_size = os.path.getsize(os.path.join(anim_dir, g['bot']))
        top_size = os.path.getsize(os.path.join(anim_dir, g['top']))
        print(f"  {base}: bot={bot_size} top={top_size}")

# Also check GE directory for comparison - are these already registered?
print()
print("=== Check if GE pack already has these ===")
ge_dir = os.path.join(anim_dir, 'GE')
if os.path.exists(ge_dir):
    # Search for 'boundhogtie' or 'bridge' or 'custom' or 'downdog' in GE subdirs
    for root, dirs, filenames in os.walk(ge_dir):
        for fn in filenames:
            if fn.endswith('.glb'):
                lower = fn.lower()
                if any(t in lower for t in ['boundhogtie', 'bridge', 'custom', 'downdog', 'chokepole']):
                    print(f"  FOUND in GE: {os.path.relpath(os.path.join(root, fn), ge_dir)}")
