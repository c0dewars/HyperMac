#!/usr/bin/env python3
"""Build the 0.8.0 screenshot tour from unretouched app captures (Python + Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/media'
W, H = 1600, 1100
BG, INK, MUTED, CYAN = '#10151F', '#F1F5FC', '#B2BED0', '#26C7DA'


def font(size, bold=False):
    candidates = [
        Path('/System/Library/Fonts/Supplemental') / ('Arial Bold.ttf' if bold else 'Arial.ttf'),
        Path('/usr/share/fonts/truetype/dejavu') / ('DejaVuSans-Bold.ttf' if bold else 'DejaVuSans.ttf'),
    ]
    return ImageFont.truetype(str(next(p for p in candidates if p.exists())), size)


def wrap(draw, text, xy, width, size, fill=INK, bold=False):
    x, y = xy
    face = font(size, bold)
    line = ''
    for word in text.split():
        trial = (line + ' ' + word).strip()
        if draw.textlength(trial, font=face) > width and line:
            draw.text((x, y), line, font=face, fill=fill)
            y += int(size * 1.35)
            line = word
        else:
            line = trial
    draw.text((x, y), line, font=face, fill=fill)
    return y + int(size * 1.35)


# Crops are normalized coordinates into actual captures, never composited controls.
# The 4-window preview was captured earlier on the same installed build 34.
SLIDES = [
    ('screenshots/30-general-080.png', 'Make room for your work',
     'Choose Dynamic splits, gaps and transition timing. Resize neighboring tiles using a window edge. Live tiling is paused for this tour.', None),
    ('screenshots/30-general-080.png', 'Focus, your way',
     'Outline the focused window, choose border colors, and adjust blur intensity. Turn blur off completely. Valid edits save automatically.', (0.235, 0.526, 0.765, 0.91)),
    ('screenshots/34-layouts-080.png', 'Start with a display',
     'Each screen has its own arrangement: all windows, selected apps, custom positions, or leave unchanged. Horizontal scrolling has been removed.', None),
    ('screenshots/36-selected-apps-080.png', 'Choose your workspace',
     'Pick apps from Applications or the library. Selected open apps share this screen. The diagram shows the saved template.', None),
    ('screenshots/37-custom-positions-080.png', 'Place every app',
     'Move or resize rectangles in Custom positions. Use half-screen presets, snap to a grid, set an app border color, or remove an app.', None),
    ('normal-layout-preview-080.png', 'Preview before applying',
     'Review the destination display and matching open windows. Preview and runtime use the same planner. Apply was not pressed during capture.', None),
    ('screenshots/31-shortcuts-080.png', 'Your keys, your apps',
     'Browse app launchers and window controls. Search or filter the list, then expand a row to edit its action. These bindings are customized.', None),
    ('screenshots/32-focus-shortcuts-080.png', 'Find the right action',
     'Search for focus to see directional navigation. Hyper + H and L focus left and right. Hyper + arrows swap windows.', None),
    ('screenshots/33-recorder-080.png', 'Press your shortcut',
     'Click a combination and press your new keys. Escape cancels recording. Conflicting bindings remain unsaved with a clear error.', None),
]


def screenshot(filename, crop=None):
    shot = Image.open(OUT / filename).convert('RGB')
    if crop:
        shot = shot.crop(tuple(round(value * (shot.width if i % 2 == 0 else shot.height))
                               for i, value in enumerate(crop)))
    return shot


frames = []
for i, (filename, title, caption, crop) in enumerate(SLIDES):
    frame = Image.new('RGB', (W, H), BG)
    draw = ImageDraw.Draw(frame)
    icon = Image.open(ROOT / 'Resources/AppIcon.png').convert('RGBA')
    icon.thumbnail((68, 68))
    frame.paste(icon, (40, 26), icon)
    draw.text((124, 40), 'HyperMac', font=font(33, True), fill=INK)
    draw.text((1240, 48), '0.8.0 / Build 34', font=font(24), fill=MUTED)
    draw.line((40, 114, 1560, 114), fill='#2B3546')
    draw.text((40, 169), f'{i + 1:02d} / {len(SLIDES):02d}', font=font(22, True), fill=CYAN)
    y = wrap(draw, title, (40, 226), 320, 44, bold=True)
    wrap(draw, caption, (40, y + 32), 320, 26, MUTED)
    shot = ImageOps.contain(screenshot(filename, crop), (1150, 870), Image.Resampling.LANCZOS)
    x, y = 410 + (1150 - shot.width) // 2, 145 + (870 - shot.height) // 2
    frame.paste(shot, (x, y))
    draw.rounded_rectangle((x - 1, y - 1, x + shot.width, y + shot.height),
                           radius=8, outline='#41516D', width=1)
    detail = 'Actual UI detail' if crop else 'Actual app UI'
    draw.text((40, 1046), f'{detail} / Screenshot walkthrough / Live transitions not demonstrated',
              font=font(21), fill=MUTED)
    draw.rectangle((0, 1092, int(W * (i + 1) / len(SLIDES)), 1099), fill=CYAN)
    frames.append(frame)

frames[0].save(OUT / 'hypermac-feature-tour.gif', save_all=True, append_images=frames[1:],
               duration=5500, loop=0, optimize=True)
frames[4].save(OUT / 'tour-poster.png')
sheet = Image.new('RGB', (1600, 1390), BG)
draw = ImageDraw.Draw(sheet)
draw.text((35, 26), 'HyperMac 0.8.0 — interface gallery', font=font(34, True), fill=INK)
for n, idx in enumerate([2, 4, 6, 8]):
    name, title, _, crop = SLIDES[idx]
    x, y = 35 + (n % 2) * 790, 100 + (n // 2) * 640
    draw.text((x, y), title, font=font(25, True), fill=CYAN)
    shot = ImageOps.contain(screenshot(name, crop), (750, 575), Image.Resampling.LANCZOS)
    sheet.paste(shot, (x, y + 42))
sheet.save(OUT / 'overview.png')
print(f'Generated {len(frames)} frames, {len(frames) * 5.5:g}s loop')
