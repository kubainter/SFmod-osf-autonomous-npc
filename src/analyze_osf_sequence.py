import json, glob, os, sys

osf_dir = r'G:\Starfield\Data\OSF'

# Print full structure of first scene with sequence tag
for f in glob.glob(os.path.join(osf_dir, '*.osf.json')):
    with open(f, 'r', encoding='utf-8-sig') as fh:
        data = json.load(fh)
    scenes = data.get('scenes', [])
    for scene in scenes:
        if 'sequence' in scene.get('tags', []):
            print('Scene with sequence:', scene['id'])
            print(json.dumps(scene, indent=2)[:3000])
            print('...')
            # Count stages
            print('Stages:', len(scene.get('stages', [])))
            for i, stage in enumerate(scene.get('stages', [])):
                print('  Stage %d: name=%s loops=%s tags=%s' % (i, stage.get('name', ''), stage.get('loops', 0), stage.get('tags', [])))
            import sys
            sys.exit(0)
