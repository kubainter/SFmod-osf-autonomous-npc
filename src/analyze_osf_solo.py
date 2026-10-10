import os
import json, glob, os

osf_dir = os.environ.get("STARFIELD_ROOT", ".") + r"\\Data\\OSF"

# Find scenes with only 1 role (solo scenes)
solo_scenes = []
all_roles = set()

for f in glob.glob(os.path.join(osf_dir, '*.osf.json')):
    with open(f, 'r', encoding='utf-8-sig') as fh:
        data = json.load(fh)
    scenes = data.get('scenes', [])
    for scene in scenes:
        roles = scene.get('roles', [])
        all_roles.add(','.join(str(r) for r in roles))
        if len(roles) == 1:
            solo_scenes.append((scene['id'], roles, scene.get('tags', [])))

print('All role combinations:')
for r in sorted(all_roles):
    print('  ', r)

print()
print('Solo scenes (1 role):', len(solo_scenes))
for sid, roles, tags in solo_scenes[:20]:
    print('  %s: roles=%s tags=%s' % (sid, roles, tags))

# Also check for idle/relax/solo tags in all scenes
print()
print('Scenes with idle/relax/solo tags:')
for f in glob.glob(os.path.join(osf_dir, '*.osf.json')):
    with open(f, 'r', encoding='utf-8-sig') as fh:
        data = json.load(fh)
    scenes = data.get('scenes', [])
    for scene in scenes:
        tags = scene.get('tags', [])
        if any(t in tags for t in ['idle', 'relax', 'solo', 'self', 'pose']):
            print('  %s: tags=%s' % (scene['id'], tags))
