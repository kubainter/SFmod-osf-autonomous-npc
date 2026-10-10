import os
import json, os, glob

osf_dir = os.environ.get("STARFIELD_ROOT", ".") + r"\\Data\\OSF"
all_edge_labels = set()
all_edge_ids = set()
scenes_with_edges = 0
scenes_without_edges = 0
sample_edges = []

for f in glob.glob(os.path.join(osf_dir, '*.osf.json')):
    with open(f, 'r', encoding='utf-8-sig') as fh:
        data = json.load(fh)
    scenes = data.get('scenes', [])
    for scene in scenes:
        sid = scene.get('id', '')
        # Check for 'edges' or 'graph' or 'nodes' structure
        edges = scene.get('edges', [])
        graph = scene.get('graph', {})
        nodes = scene.get('nodes', [])
        stages = scene.get('stages', [])
        
        if edges:
            scenes_with_edges += 1
            for edge in edges:
                label = edge.get('label', '')
                eid = edge.get('id', '')
                if label:
                    all_edge_labels.add(label)
                if eid:
                    all_edge_ids.add(eid)
                if len(sample_edges) < 20:
                    sample_edges.append((sid, eid, label, edge.get('from', ''), edge.get('to', '')))
        elif graph and graph.get('edges'):
            scenes_with_edges += 1
            for edge in graph['edges']:
                label = edge.get('label', '')
                eid = edge.get('id', '')
                if label:
                    all_edge_labels.add(label)
                if eid:
                    all_edge_ids.add(eid)
                if len(sample_edges) < 20:
                    sample_edges.append((sid, eid, label, edge.get('from', ''), edge.get('to', '')))
        else:
            scenes_without_edges += 1
        
        # Also check stages for edge info
        if stages and not edges and not graph:
            for stage in stages:
                s_edges = stage.get('edges', [])
                for edge in s_edges:
                    label = edge.get('label', '')
                    eid = edge.get('id', '')
                    if label:
                        all_edge_labels.add(label)
                    if eid:
                        all_edge_ids.add(eid)

print('Scenes with edges:', scenes_with_edges)
print('Scenes without edges:', scenes_without_edges)
print()
print('All edge labels (%d):' % len(all_edge_labels))
for l in sorted(all_edge_labels):
    print('  ', repr(l))
print()
print('All edge IDs (%d):' % len(all_edge_ids))
for i in sorted(all_edge_ids):
    print('  ', repr(i))
print()
print('Sample edges:')
for sid, eid, label, frm, to in sample_edges:
    print('  %s: id=%s label=%s from=%s to=%s' % (sid, repr(eid), repr(label), repr(frm), repr(to)))

# Also check scene structure keys
print()
print('Sample scene keys:')
for f in glob.glob(os.path.join(osf_dir, '*.osf.json'))[:1]:
    with open(f, 'r', encoding='utf-8-sig') as fh:
        data = json.load(fh)
    scenes = data.get('scenes', [])
    if scenes:
        print('  Scene keys:', list(scenes[0].keys()))
        # Print full first scene structure (abbreviated)
        import pprint
        scene = scenes[0]
        for k, v in scene.items():
            if isinstance(v, list) and len(v) > 0:
                print('  %s: list[%d], first item keys: %s' % (k, len(v), list(v[0].keys()) if isinstance(v[0], dict) else type(v[0]).__name__))
            elif isinstance(v, dict):
                print('  %s: dict keys: %s' % (k, list(v.keys())))
            else:
                print('  %s: %s' % (k, repr(v)[:80]))
