import os
import json, os, glob

osf_dir = os.environ.get("STARFIELD_ROOT", ".") + r"\\Data\\OSF"
all_tags = set()
all_scene_ids = []
all_packs = set()
tag_combinations = []
gender_tags = set()
mood_tags = set()

for f in glob.glob(os.path.join(osf_dir, '*.osf.json')):
    with open(f, 'r', encoding='utf-8-sig') as fh:
        data = json.load(fh)
    pack = data.get('pack', 'unknown')
    all_packs.add(pack)
    scenes = data.get('scenes', [])
    for scene in scenes:
        sid = scene.get('id', '')
        tags = scene.get('tags', [])
        all_scene_ids.append(sid)
        for t in tags:
            all_tags.add(t)
        tag_combinations.append((sid, tags))
        # Check for gender tags
        for t in tags:
            if t in ('mf', 'ff', 'mm', 'mff', 'mmf', 'mfm', 'fmf'):
                gender_tags.add(t)
            if t in ('romantic', 'sensual', 'intense', 'oral', 'blowjob', 'doggy', 'cowgirl', 'missionary', 'hugging', 'kissing'):
                mood_tags.add(t)

print('Total scene files:', len(glob.glob(os.path.join(osf_dir, '*.osf.json'))))
print('Total scenes:', len(all_scene_ids))
print('Packs:', sorted(all_packs))
print()
print('All unique tags (%d):' % len(all_tags))
for t in sorted(all_tags):
    print('  ', t)
print()
print('Gender tags:', sorted(gender_tags))
print('Mood/action tags:', sorted(mood_tags))
print()
print('Sample scenes with tags:')
for sid, tags in tag_combinations[:20]:
    print('  %s: %s' % (sid, tags))
