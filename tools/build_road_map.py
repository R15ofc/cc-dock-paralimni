#!/usr/bin/env python3
import argparse
import gzip
import io
import math
import re
import struct
import sys
import zipfile
import zlib
from collections import defaultdict, deque
from pathlib import Path

import nbtlib
from PIL import Image, ImageDraw


ROAD = 1
CROSSWALK_MARKER = 2
CROSSWALK_SURFACE = 4
SIDEWALK = 8
TUNNEL = 16
MAGIC = 0x52524D31

REGION_PATTERN = re.compile(r"(?:^|/)r\.(-?\d+)\.(-?\d+)\.mca$")
ROAD_BLOCKS = {"minecraft:polished_deepslate"}
CROSSWALK_MARKERS = {"minecraft:yellow_terracotta"}
CROSSWALK_SURFACES = {"create:polished_cut_calcite"}
SIDEWALK_BLOCKS = {"minecraft:smooth_stone_slab"}
TUNNEL_BLOCKS = {"minecraft:smooth_stone"}
TARGETS = ROAD_BLOCKS | CROSSWALK_MARKERS | CROSSWALK_SURFACES | SIDEWALK_BLOCKS | TUNNEL_BLOCKS


def read_chunk(region, index):
    location = int.from_bytes(region[index * 4:index * 4 + 3], "big")
    if location == 0:
        return None
    offset = location * 4096
    if offset + 5 > len(region):
        return None
    length = int.from_bytes(region[offset:offset + 4], "big")
    compression = region[offset + 4]
    payload = region[offset + 5:offset + 4 + length]
    try:
        if compression == 1:
            payload = gzip.decompress(payload)
        elif compression == 2:
            payload = zlib.decompress(payload)
        elif compression == 3:
            pass
        else:
            return None
        return nbtlib.File.parse(io.BytesIO(payload))
    except Exception:
        return None


def palette_name(entry):
    value = entry.get("Name")
    return str(value) if value is not None else ""


def section_blocks(section):
    states = section.get("block_states")
    if states is None:
        return
    palette = states.get("palette")
    if not palette:
        return
    names = [palette_name(entry) for entry in palette]
    target_indices = {index for index, name in enumerate(names) if name in TARGETS}
    if not target_indices:
        return

    data = states.get("data")
    if data is None:
        if 0 in target_indices:
            for index in range(4096):
                yield index, names[0]
        return

    bits = max(4, math.ceil(math.log2(len(palette))))
    values_per_long = 64 // bits
    mask = (1 << bits) - 1
    packed = [int(value) & 0xffffffffffffffff for value in data]
    for index in range(4096):
        long_index = index // values_per_long
        if long_index >= len(packed):
            break
        palette_index = (packed[long_index] >> ((index % values_per_long) * bits)) & mask
        if palette_index in target_indices:
            yield index, names[palette_index]


def keep_largest_road_components(roads, minimum_size):
    remaining = set(roads)
    kept = set()
    sizes = []
    while remaining:
        start = remaining.pop()
        component = {start}
        queue = deque([start])
        while queue:
            x, z = queue.popleft()
            for neighbor in ((x - 1, z), (x + 1, z), (x, z - 1), (x, z + 1)):
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    component.add(neighbor)
                    queue.append(neighbor)
        sizes.append(len(component))
        if len(component) >= minimum_size:
            kept.update(component)
    return kept, sorted(sizes, reverse=True)


def expanded(points, radius):
    result = set()
    for x, z in points:
        for dx in range(-radius, radius + 1):
            for dz in range(-radius, radius + 1):
                result.add((x + dx, z + dz))
    return result


def convert(archive, output, preview, min_component):
    categories = {
        "road": {},
        "marker": {},
        "surface": {},
        "sidewalk": {},
    }
    tunnel_columns = defaultdict(list)
    region_count = 0
    chunk_count = 0

    with zipfile.ZipFile(archive) as source:
        entries = []
        for info in source.infolist():
            match = REGION_PATTERN.search(info.filename)
            if not match or info.file_size == 0:
                continue
            region_x, region_z = map(int, match.groups())
            if abs(region_x) > 1024 or abs(region_z) > 1024:
                continue
            entries.append(info)

        for region_index, info in enumerate(entries, 1):
            region = source.read(info)
            region_count += 1
            for local_index in range(1024):
                chunk = read_chunk(region, local_index)
                if chunk is None:
                    continue
                chunk_count += 1
                chunk_x = int(chunk.get("xPos", 0))
                chunk_z = int(chunk.get("zPos", 0))
                for section in chunk.get("sections", []):
                    section_y = int(section.get("Y", 0))
                    for block_index, name in section_blocks(section) or ():
                        local_y = block_index // 256
                        local_z = (block_index % 256) // 16
                        local_x = block_index % 16
                        x = chunk_x * 16 + local_x
                        y = section_y * 16 + local_y
                        z = chunk_z * 16 + local_z
                        key = (x, z)
                        if name in ROAD_BLOCKS:
                            categories["road"][key] = max(y, categories["road"].get(key, -4096))
                        elif name in CROSSWALK_MARKERS:
                            categories["marker"][key] = max(y, categories["marker"].get(key, -4096))
                        elif name in CROSSWALK_SURFACES:
                            categories["surface"][key] = max(y, categories["surface"].get(key, -4096))
                        elif name in SIDEWALK_BLOCKS:
                            categories["sidewalk"][key] = max(y, categories["sidewalk"].get(key, -4096))
                        elif name in TUNNEL_BLOCKS:
                            tunnel_columns[key].append(y)
            if region_index % 20 == 0 or region_index == len(entries):
                print(f"regions {region_index}/{len(entries)} chunks={chunk_count}", flush=True)

    kept_roads, component_sizes = keep_largest_road_components(categories["road"], min_component)
    near_two = expanded(kept_roads, 2)
    near_three = expanded(kept_roads, 3)
    marker = {key for key in categories["marker"] if key in near_two}
    surface = {key for key in categories["surface"] if key in near_two}
    sidewalk = {key for key in categories["sidewalk"] if key in near_three}

    cells = {}
    for key in kept_roads:
        y = categories["road"][key]
        flags = ROAD
        if any(y + 2 <= roof_y <= y + 10 for roof_y in tunnel_columns.get(key, ())):
            flags |= TUNNEL
        cells[key] = [y, flags]
    for key in marker:
        y = categories["marker"][key]
        current = cells.setdefault(key, [y, 0])
        current[0] = max(current[0], y)
        current[1] |= CROSSWALK_MARKER
    for key in surface:
        y = categories["surface"][key]
        current = cells.setdefault(key, [y, 0])
        current[0] = max(current[0], y)
        current[1] |= CROSSWALK_SURFACE
    for key in sidewalk:
        y = categories["sidewalk"][key]
        current = cells.setdefault(key, [y, 0])
        current[0] = max(current[0], y)
        current[1] |= SIDEWALK

    ordered = sorted(cells.items(), key=lambda item: (item[0][1], item[0][0]))
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as target:
        target.write(struct.pack(">II", MAGIC, len(ordered)))
        for (x, z), (y, flags) in ordered:
            target.write(struct.pack(">iihB", x, z, max(-32768, min(32767, y)), flags))

    render_preview(cells, preview)
    xs = [key[0] for key in cells]
    zs = [key[1] for key in cells]
    print(f"regions={region_count} chunks={chunk_count}")
    print(f"components={component_sizes[:12]}")
    print(f"cells={len(cells)} bounds=({min(xs)},{min(zs)})..({max(xs)},{max(zs)})")
    print(output)
    print(preview)


def render_preview(cells, path):
    width, height = 1800, 1100
    image = Image.new("RGB", (width, height), "#0b1117")
    draw = ImageDraw.Draw(image)
    min_x = min(x for x, _ in cells)
    max_x = max(x for x, _ in cells)
    min_z = min(z for _, z in cells)
    max_z = max(z for _, z in cells)
    padding = 35
    scale = min((width - padding * 2) / max(1, max_x - min_x), (height - padding * 2) / max(1, max_z - min_z))

    def point(x, z):
        return padding + (x - min_x) * scale, height - padding - (z - min_z) * scale

    for (x, z), (_, flags) in cells.items():
        px, py = point(x, z)
        if flags & CROSSWALK_MARKER:
            color = "#ffd84d"
        elif flags & CROSSWALK_SURFACE:
            color = "#f5f5f5"
        elif flags & SIDEWALK and not flags & ROAD:
            color = "#65717d"
        elif flags & TUNNEL:
            color = "#8b98a5"
        else:
            color = "#39a9ff"
        size = max(1, int(math.ceil(scale)))
        draw.rectangle((px, py, px + size, py + size), fill=color)

    draw.rectangle((8, 8, width - 9, height - 9), outline="#33404d", width=2)
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("preview", type=Path)
    parser.add_argument("--min-component", type=int, default=48)
    args = parser.parse_args()
    convert(args.archive, args.output, args.preview, args.min_component)


if __name__ == "__main__":
    main()
