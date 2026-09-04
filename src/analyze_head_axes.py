import gzip, struct, json, math, glob, os

SOURCES = [
    'G:/Starfield/Data/SAF/Animations/standself01.glb',
    'G:/Starfield/Data/OSF/Autonomous/Animations/solo_standing_touch.glb',
]


def normalize(q):
    length = math.sqrt(sum(value * value for value in q))
    return [value / length for value in q]


def multiply(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return normalize([
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    ])


def rotate(q, vector):
    x, y, z, w = normalize(q)
    vx, vy, vz = vector
    tx = 2.0 * (y * vz - z * vy)
    ty = 2.0 * (z * vx - x * vz)
    tz = 2.0 * (x * vy - y * vx)
    return [
        vx + w * tx + (y * tz - z * ty),
        vy + w * ty + (z * tx - x * tz),
        vz + w * tz + (x * ty - y * tx),
    ]


def load(path):
    with gzip.open(path, 'rb') as stream:
        raw = stream.read()
    json_length = struct.unpack_from('<I', raw, 12)[0]
    gltf = json.loads(raw[20:20 + json_length].decode('utf-8'))
    binary_offset = 20 + json_length
    binary_length = struct.unpack_from('<I', raw, binary_offset)[0]
    binary = raw[binary_offset + 8:binary_offset + 8 + binary_length]
    return gltf, binary


def accessor(gltf, binary, index):
    item = gltf['accessors'][index]
    view = gltf['bufferViews'][item['bufferView']]
    offset = view.get('byteOffset', 0) + item.get('byteOffset', 0)
    components = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}[item['type']]
    stride = view.get('byteStride', components * 4)
    values = [list(struct.unpack_from(f'<{components}f', binary, offset + i * stride)) for i in range(item['count'])]
    return [value[0] for value in values] if components == 1 else values


def sample(values, frame, frame_count):
    if len(values) == 1:
        return values[0]
    index = round(frame * (len(values) - 1) / (frame_count - 1))
    return values[index]


def analyze(path):
    gltf, binary = load(path)
    nodes = gltf['nodes']
    animation = gltf['animations'][0]
    names = {node.get('name', ''): index for index, node in enumerate(nodes)}
    parents = {}
    for parent, node in enumerate(nodes):
        for child in node.get('children', []):
            parents[child] = parent
    tracks = {}
    frame_count = 2
    for channel in animation['channels']:
        sampler = animation['samplers'][channel['sampler']]
        values = accessor(gltf, binary, sampler['output'])
        tracks[(channel['target']['node'], channel['target']['path'])] = values
        frame_count = max(frame_count, len(values))

    def local(node_index, frame):
        node = nodes[node_index]
        rotation = sample(tracks.get((node_index, 'rotation'), [node.get('rotation', [0.0, 0.0, 0.0, 1.0])]), frame, frame_count)
        translation = sample(tracks.get((node_index, 'translation'), [node.get('translation', [0.0, 0.0, 0.0])]), frame, frame_count)
        return normalize(rotation), translation

    def world(node_index, frame, cache):
        key = (node_index, frame)
        if key in cache:
            return cache[key]
        local_rotation, local_translation = local(node_index, frame)
        if node_index not in parents:
            result = (local_rotation, local_translation)
        else:
            parent_rotation, parent_translation = world(parents[node_index], frame, cache)
            rotated_translation = rotate(parent_rotation, local_translation)
            result = (
                multiply(parent_rotation, local_rotation),
                [parent_translation[i] + rotated_translation[i] for i in range(3)],
            )
        cache[key] = result
        return result

    head = names['C_Head']
    left_eye = names['L_Eye']
    right_eye = names['R_Eye']
    elevations = []
    directions = []
    for frame in range(frame_count):
        cache = {}
        _, head_position = world(head, frame, cache)
        _, left_position = world(left_eye, frame, cache)
        _, right_position = world(right_eye, frame, cache)
        eye_position = [(left_position[i] + right_position[i]) * 0.5 for i in range(3)]
        direction = [eye_position[i] - head_position[i] for i in range(3)]
        horizontal = math.hypot(direction[0], direction[1])
        elevations.append(math.degrees(math.atan2(direction[2], horizontal)))
        length = math.sqrt(sum(value * value for value in direction))
        directions.append([value / length for value in direction])

    minimum = min(range(frame_count), key=lambda i: elevations[i])
    maximum = max(range(frame_count), key=lambda i: elevations[i])
    average = sum(elevations) / len(elevations)
    print(f'\n{os.path.basename(path)}')
    left_parent = nodes[parents[left_eye]].get('name') if left_eye in parents else '<none>'
    print(f'  eye-parent: {nodes[left_eye].get("name")} <- {left_parent}')
    print(f'  elevation: min={elevations[minimum]:.2f} deg, avg={average:.2f} deg, max={elevations[maximum]:.2f} deg')
    print(f'  first={elevations[0]:.2f} deg, quarter={elevations[frame_count // 4]:.2f} deg, half={elevations[frame_count // 2]:.2f} deg, last={elevations[-1]:.2f} deg')
    print(f'  min direction={directions[minimum]}')
    print(f'  max direction={directions[maximum]}')


for source in SOURCES:
    analyze(source)
