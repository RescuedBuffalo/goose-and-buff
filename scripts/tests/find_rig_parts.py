"""
Connected-component bounding-box finder for the BUF-183 rigging sheets.

Walks every opaque pixel in the source PNG, flood-fills 4-connected regions,
emits a sorted list of {bbox, area, centroid} for each component large enough
to be a "real" part (filters out text labels and small noise). The output
is a candidate region table the rigger can copy into AtlasTexture defs.

Usage:
    python scripts/tests/find_rig_parts.py design/assets/characters/buffalo_rigging_sheet.png

Output is sorted top-to-bottom then left-to-right, which matches how the
Scenario sheets lay out parts (head row, body row, limb rows).
"""

from __future__ import annotations
import sys
from collections import deque
from pathlib import Path

from PIL import Image


MIN_AREA = 400  # filter out text labels (each glyph << 400 px)


def find_components(img: Image.Image, alpha_thresh: int = 128):
    w, h = img.size
    px = img.load()
    visited = bytearray(w * h)
    components = []

    def is_opaque(x: int, y: int) -> bool:
        return px[x, y][3] >= alpha_thresh

    for sy in range(h):
        for sx in range(w):
            if visited[sy * w + sx]:
                continue
            if not is_opaque(sx, sy):
                visited[sy * w + sx] = 1
                continue
            # BFS
            queue = deque([(sx, sy)])
            visited[sy * w + sx] = 1
            min_x, max_x = sx, sx
            min_y, max_y = sy, sy
            area = 0
            sum_x = 0
            sum_y = 0
            while queue:
                x, y = queue.popleft()
                area += 1
                sum_x += x
                sum_y += y
                if x < min_x: min_x = x
                if x > max_x: max_x = x
                if y < min_y: min_y = y
                if y > max_y: max_y = y
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h:
                        idx = ny * w + nx
                        if not visited[idx] and is_opaque(nx, ny):
                            visited[idx] = 1
                            queue.append((nx, ny))
            if area >= MIN_AREA:
                components.append({
                    "bbox": (min_x, min_y, max_x - min_x + 1, max_y - min_y + 1),
                    "area": area,
                    "centroid": (sum_x // area, sum_y // area),
                })

    return components


def main():
    if len(sys.argv) < 2:
        print("usage: find_rig_parts.py <png>")
        sys.exit(1)
    src = Path(sys.argv[1])
    img = Image.open(src).convert("RGBA")
    print(f"# {src.name}: {img.size[0]}x{img.size[1]}")
    comps = find_components(img)
    # Sort top-to-bottom (binned by 50px rows), then left-to-right
    comps.sort(key=lambda c: (c["bbox"][1] // 50, c["bbox"][0]))
    print(f"# {len(comps)} components (>= {MIN_AREA} px area)")
    print(f"# columns: idx, x, y, w, h, area, centroid_x, centroid_y")
    for i, c in enumerate(comps):
        x, y, w, h = c["bbox"]
        cx, cy = c["centroid"]
        print(f"  {i:3d}: x={x:4d} y={y:4d} w={w:4d} h={h:4d} area={c['area']:6d} centroid=({cx:4d},{cy:4d})")


if __name__ == "__main__":
    main()
