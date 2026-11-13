#!/usr/bin/env python3
"""
generate-wallpapers.py — Generates 3 high-resolution (1920x1080) dark monochrome wallpapers
for Neuxon OS:
  1. neuxon-geometric-01.png (Isometric wireframe grid & polyhedron)
  2. neuxon-topographic-02.png (Contour elevation lines)
  3. neuxon-stealth-03.png (Monolithic glass slabs & specular hairlines)
"""

import os
import math
import subprocess

WIDTH = 1920
HEIGHT = 1080

def create_geometric_svg(out_path):
    elements = []
    # Background
    elements.append(f'<rect width="{WIDTH}" height="{HEIGHT}" fill="#050505"/>')

    # Grid lines
    step = 60
    for x in range(0, WIDTH, step):
        elements.append(f'<line x1="{x}" y1="0" x2="{x}" y2="{HEIGHT}" stroke="#101010" stroke-width="1"/>')
    for y in range(0, HEIGHT, step):
        elements.append(f'<line x1="0" y1="{y}" x2="{WIDTH}" y2="{y}" stroke="#101010" stroke-width="1"/>')

    # Central Isometric Wireframe Diamond / Polyhedron
    cx, cy = WIDTH // 2, HEIGHT // 2
    size = 240
    # Outer diamond
    p_top = f"{cx},{cy - size}"
    p_right = f"{cx + size * 1.4},{cy}"
    p_bottom = f"{cx},{cy + size}"
    p_left = f"{cx - size * 1.4},{cy}"
    elements.append(f'<polygon points="{p_top} {p_right} {p_bottom} {p_left}" fill="#0A0A0A" stroke="#2A2A2A" stroke-width="2"/>')

    # Inner faceted lines
    elements.append(f'<line x1="{cx}" y1="{cy - size}" x2="{cx}" y2="{cy + size}" stroke="#333333" stroke-width="1.5"/>')
    elements.append(f'<line x1="{cx - size * 1.4}" y1="{cy}" x2="{cx + size * 1.4}" y2="{cy}" stroke="#333333" stroke-width="1.5"/>')

    # Specular white accent node at center
    elements.append(f'<circle cx="{cx}" cy="{cy}" r="4" fill="#FFFFFF"/>')
    elements.append(f'<circle cx="{cx}" cy="{cy - size}" r="3" fill="#FFFFFF"/>')
    elements.append(f'<circle cx="{cx + size * 1.4}" cy="{cy}" r="3" fill="#FFFFFF"/>')
    elements.append(f'<circle cx="{cx}" cy="{cy + size}" r="3" fill="#FFFFFF"/>')
    elements.append(f'<circle cx="{cx - size * 1.4}" cy="{cy}" r="3" fill="#FFFFFF"/>')

    # Watermark branding text
    elements.append(f'<text x="{WIDTH - 80}" y="{HEIGHT - 40}" fill="#2A2A2A" font-family="monospace" font-size="14" text-anchor="end" letter-spacing="3">NEUXON // GEOMETRIC 01</text>')

    svg_content = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {WIDTH} {HEIGHT}" width="{WIDTH}" height="{HEIGHT}">
{''.join(elements)}
</svg>'''
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(svg_content)


def create_topographic_svg(out_path):
    elements = []
    elements.append(f'<rect width="{WIDTH}" height="{HEIGHT}" fill="#050505"/>')

    cx, cy = WIDTH // 2 + 100, HEIGHT // 2
    # Generate undulating contour rings
    num_rings = 28
    for r_idx in range(1, num_rings + 1):
        radius = r_idx * 24
        points = []
        num_points = 120
        stroke_color = "#1C1C1C" if r_idx % 4 != 0 else "#363636"
        stroke_w = "1" if r_idx % 4 != 0 else "1.5"

        for p_idx in range(num_points + 1):
            angle = (p_idx / num_points) * 2 * math.pi
            noise = math.sin(angle * 3 + r_idx * 0.4) * 18 + math.cos(angle * 5 - r_idx * 0.2) * 12
            rad = radius + noise
            px = cx + rad * 1.6 * math.cos(angle)
            py = cy + rad * math.sin(angle)
            points.append(f"{px:.1f},{py:.1f}")

        elements.append(f'<polyline points="{" ".join(points)}" fill="none" stroke="{stroke_color}" stroke-width="{stroke_w}"/>')

    # Watermark
    elements.append(f'<text x="{WIDTH - 80}" y="{HEIGHT - 40}" fill="#2A2A2A" font-family="monospace" font-size="14" text-anchor="end" letter-spacing="3">NEUXON // TOPOGRAPHIC 02</text>')

    svg_content = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {WIDTH} {HEIGHT}" width="{WIDTH}" height="{HEIGHT}">
{''.join(elements)}
</svg>'''
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(svg_content)


def create_stealth_svg(out_path):
    elements = []
    elements.append(f'<rect width="{WIDTH}" height="{HEIGHT}" fill="#050505"/>')

    # Diagonal carbon shards
    shards = [
        ("0,0 700,0 500,1080 0,1080", "#080808", "#1A1A1A"),
        ("400,0 1200,0 950,1080 200,1080", "#0B0B0B", "#262626"),
        ("850,0 1600,0 1400,1080 650,1080", "#0E0E0E", "#333333"),
        ("1300,0 1920,0 1920,1080 1100,1080", "#090909", "#202020"),
    ]
    for pts, fill, stroke in shards:
        elements.append(f'<polygon points="{pts}" fill="{fill}" stroke="{stroke}" stroke-width="1"/>')

    # Specular hairline accent across the primary division
    elements.append(f'<line x1="850" y1="0" x2="650" y2="{HEIGHT}" stroke="#FFFFFF" stroke-width="1.5" opacity="0.85"/>')

    # Small tech badge
    elements.append(f'<rect x="120" y="80" width="180" height="32" fill="#0E0E0EDB" stroke="#FFFFFF" stroke-width="1" rx="4"/>')
    elements.append(f'<text x="210" y="101" fill="#FFFFFF" font-family="monospace" font-size="11" font-weight="bold" text-anchor="middle" letter-spacing="2">STEALTH // 03</text>')

    elements.append(f'<text x="{WIDTH - 80}" y="{HEIGHT - 40}" fill="#2A2A2A" font-family="monospace" font-size="14" text-anchor="end" letter-spacing="3">NEUXON // STEALTH GLASS 03</text>')

    svg_content = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {WIDTH} {HEIGHT}" width="{WIDTH}" height="{HEIGHT}">
{''.join(elements)}
</svg>'''
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(svg_content)


def main():
    target_dir = os.path.join(os.path.dirname(__file__), '..', 'config', 'branding', 'wallpapers')
    os.makedirs(target_dir, exist_ok=True)

    wallpapers = [
        ("neuxon-geometric-01", create_geometric_svg),
        ("neuxon-topographic-02", create_topographic_svg),
        ("neuxon-stealth-03", create_stealth_svg),
    ]

    for name, generator in wallpapers:
        svg_file = os.path.join(target_dir, f"{name}.svg")
        png_file = os.path.join(target_dir, f"{name}.png")
        generator(svg_file)
        print(f"Generated {svg_file}")

        # Try converting via rsvg-convert or magick if available
        converted = False
        for cmd in [
            ["rsvg-convert", "-w", str(WIDTH), "-h", str(HEIGHT), svg_file, "-o", png_file],
            ["magick", svg_file, png_file],
            ["convert", svg_file, png_file]
        ]:
            try:
                subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                print(f"Converted -> {png_file}")
                converted = True
                break
            except Exception:
                pass

        if not converted:
            # Fallback: create PNG directly via python Pillow if installed, or keep SVG copy as fallback
            try:
                from PIL import Image, ImageDraw
                im = Image.new("RGB", (WIDTH, HEIGHT), (5, 5, 5))
                draw = ImageDraw.Draw(im)
                draw.rectangle([0, 0, WIDTH, HEIGHT], fill=(5, 5, 5))
                im.save(png_file)
                print(f"Saved PNG placeholder {png_file}")
            except Exception:
                pass

if __name__ == "__main__":
    main()
