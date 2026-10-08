#!/usr/bin/env python3
"""Build the local screenshot tour. Requires Python 3 and Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/media'
W, H = 1440, 1000
BG, INK, MUTED, CYAN = '#0D1426', '#F0F5FF', '#AEBED8', '#23CBE0'

def font(size, bold=False):
    candidates = [Path('/System/Library/Fonts/Supplemental') / ('Arial Bold.ttf' if bold else 'Arial.ttf'), Path('/usr/share/fonts/truetype/dejavu') / ('DejaVuSans-Bold.ttf' if bold else 'DejaVuSans.ttf')]
    return ImageFont.truetype(str(next(p for p in candidates if p.exists())), size)

def wrap(draw, text, xy, width, size, fill=INK, bold=False):
    x, y = xy
    f = font(size, bold)
    line = ''
    for word in text.split():
        trial = (line + ' ' + word).strip()
        if draw.textlength(trial, font=f) > width and line:
            draw.text((x,y), line, font=f, fill=fill)
            y += int(size*1.35)
            line = word
        else: line = trial
    draw.text((x,y), line, font=f, fill=fill)
    return y + int(size*1.35)

slides = [
 ('11-general-070.png','Automatic tiling','Open and close apps without arranging every window. Choose Dynamic splits, gaps and transitions; resize tiles using native window edges.'),
 ('12-blur-borders-070.png','Focus your workspace','Outline only the focused window. Turn blur off completely or adjust its intensity. Valid changes save automatically.'),
 ('26-shortcuts-070.png','A clearer shortcut editor','Browse compact action rows, filter Windows, Apps or Layouts, and expand an action to edit its target.'),
 ('27-navigation-shortcuts-070.png','Find your next window','Search for focus to find the horizontal controls. Hyper + H goes left; Hyper + L goes right. Hyper + arrows swaps windows.'),
 ('28-recorder-070.png','Press your combination','Click the current binding and press new keys. Escape cancels; conflicting bindings stay unsaved with an error.'),
 ('16-normal-layout-070.png','Your Normal preset','Adaptive layouts share each display among matching open apps. Add apps from the library and preview before applying.'),
 ('24-screen-layouts-070.png','Start with a screen','Choose a display card, then its mode. The app list and editor follow your selection. Each screen keeps its own app rules.'),
 ('25-per-screen-preview-070.png','Preview the destination','Review each screen before applying. Matching open apps move to their saved screens; unlisted windows stay on their current displays.'),
 ('17-horizontal-diagram-070.png','Design a horizontal strip','Expand Screen overview to drag rectangles sideways to reorder them, or into another rectangle’s lower third to stack apps.'),
 ('18-horizontal-groups-070.png','Two apps, one column','Stack apps vertically in a shared column. Drag the width handle to resize the column; drag a rectangle out to separate it.'),
 ('18-horizontal-groups-070.png','Remove apps directly','Use the x on a column card or the minus in the sidebar. Screen-specific exclusions keep removed apps out of include-all mode.'),
 ('19-app-width-070.png','Choose each app width','Pick one-third, half, two-thirds or Full width. Grouped apps share a width. The inspector also offers reorder and grouping actions.'),
 ('24-screen-layouts-070.png','A workspace per display','Choose Horizontal scroll, Automatic tiles, Tile saved apps, Custom positions or Leave unchanged separately for each screen.'),
 ('21-scroll-options-070.png','Tune the strip','Reserve space for neighbors, center focus, enable Hyper + scroll and choose transition timing. A shared display edge currently uses instant navigation.'),
 ('16-normal-layout-070.png','Reuse and recover','Duplicate a layout to explore a variant. Preview before applying. Undo/redo restore one arrangement of surviving windows; history is not demonstrated here.'),
 (None,'Switch when docking','Assign saved layouts to connected-monitor setups. Profiles match display IDs after docking settles. Illustration only; docking was not recorded.'),
]
frames = []
for i, (filename, title, caption) in enumerate(slides):
    im = Image.new('RGB', (W,H), BG); d = ImageDraw.Draw(im)
    icon = Image.open(ROOT/'Resources/AppIcon.png').convert('RGBA'); icon.thumbnail((64,64))
    im.paste(icon,(40,28),icon)
    d.text((118,40),'HyperMac',font=font(31,True),fill=INK)
    d.text((1090,48),'0.7.0  /  Preview',font=font(21),fill=MUTED)
    d.line((40,115,1400,115),fill='#29354E',width=1)
    d.text((40,166),f'{i+1:02d} / {len(slides):02d}',font=font(21,True),fill=CYAN)
    y=wrap(d,title,(40,224),310,42,bold=True)
    wrap(d,caption,(40,y+30),310,25,MUTED)
    if filename:
        shot=Image.open(OUT/'screenshots'/filename).convert('RGB')
        shot=ImageOps.contain(shot,(1020,770),Image.Resampling.LANCZOS)
        x,y=380+(1020-shot.width)//2,150+(770-shot.height)//2
        im.paste(shot,(x,y))
        d.rounded_rectangle((x-1,y-1,x+shot.width,y+shot.height),radius=8,outline='#41516D',width=1)
    else:
        d.rounded_rectangle((395,190,1390,850),radius=24,fill='#17223A')
        d.text((445,235),'MONITOR PROFILES',font=font(24,True),fill=CYAN)
        for x, name, label in [(450,'Laptop only','Focus layout'),(920,'Laptop + display','Desk layout')]:
            d.rounded_rectangle((x,365,x+250,525),radius=12,outline='#9A79FF',width=5)
            d.line((x-20,545,x+270,545),fill='#9A79FF',width=6)
            if x>500:
                d.rounded_rectangle((x+140,300,x+390,460),radius=8,outline='#93F0C3',width=5)
            d.text((x,600),name,font=font(26,True),fill=INK)
            d.text((x,644),label,font=font(24),fill=MUTED)
        d.text((445,760),'Concept illustration - not a captured docking session',font=font(23),fill=MUTED)
    label='Actual app UI  /  Screenshot walkthrough' if filename else 'Monitor-profile illustration  /  Docking not recorded'
    d.text((40,944),label,font=font(20),fill=MUTED)
    d.rectangle((0,990,int(W*(i+1)/len(slides)),999),fill=CYAN)
    frames.append(im)
frames[0].save(OUT/'hypermac-feature-tour.gif',save_all=True,append_images=frames[1:],duration=5000,loop=0,optimize=True)
frames[6].save(OUT/'tour-poster.png')
# A static, legible review sheet for the most useful screenshots.
sheet=Image.new('RGB',(1600,1390),BG); d=ImageDraw.Draw(sheet)
d.text((35,26),'HyperMac 0.7.0 - interface gallery',font=font(34,True),fill=INK)
for n, idx in enumerate([2,6,7,9]):
    name,title,_=slides[idx]; x=35+(n%2)*790; y=100+(n//2)*640
    d.text((x,y),title,font=font(25,True),fill=CYAN)
    shot=ImageOps.contain(Image.open(OUT/'screenshots'/name).convert('RGB'),(750,575),Image.Resampling.LANCZOS)
    sheet.paste(shot,(x,y+42))
sheet.save(OUT/'overview.png')
print(f'Generated {len(frames)} frames, {len(frames)*5}s loop')
