#!/usr/bin/env python3
"""Build the local screenshot tour. Requires Python 3 and Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps
import textwrap

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
 ('01-general.png','Automatic tiling','Eligible windows share the workspace as they open, close, minimize and return. Choose Dynamic splits, gaps and transitions.'),
 ('01-general.png','Resize naturally','Enable mouse resizing, then drag a normal window edge or corner. In Dynamic splits, neighboring tiles adjust when you release.'),
 ('02-borders-capture.png','Make it yours','Choose the border color and width. Adjust transition duration in General; Reduce Motion is respected.'),
 ('03-floating-apps.png','Keep apps floating','Choose exceptions with an application picker. System Settings is excluded by default.'),
 ('02-borders-capture.png','Capture a workspace','Name and capture the visible arrangement, then refine its app rules and monitor assignments in Layouts.'),
 ('04-shortcuts.png','Your keyboard workflow','Customize window actions and app launchers. Hyper means Control + Option + Shift + Command.'),
 ('05-shortcut-recorder.png','Press to record','Record a key combination directly. Escape cancels the recording without changing the shortcut.'),
 ('06-app-picker.png','Choose an application','Select launch targets from Applications instead of typing an app name.'),
 ('07-layouts.png','Design a layout','Place apps on a monitor canvas, resize rectangles and use snapping, quick positions and app colors.'),
 ('08-adaptive-layout.png','Adapt to open apps','Adaptive layouts share space among matching open windows. Configure gaps and the missing-display fallback.'),
 ('09-preview.png','Check before applying','Preview the planned arrangement and missing-window warnings before applying. This capture shows a missing Brave window.'),
 ('10-duplicate-layout.png','Reuse and recover','Duplicate a layout to explore a variant. Undo and redo restore one arrangement of surviving windows after applying; history is not demonstrated here.'),
 (None,'Switch when docking','Assign saved layouts to exact connected-monitor setups. Matching profiles apply at startup and after docking or undocking settles.'),
]
frames = []
for i, (filename, title, caption) in enumerate(slides):
    im = Image.new('RGB', (W,H), BG); d = ImageDraw.Draw(im)
    icon = Image.open(ROOT/'Resources/AppIcon.png').convert('RGBA'); icon.thumbnail((64,64))
    im.paste(icon,(40,28),icon)
    d.text((118,40),'HyperMac',font=font(31,True),fill=INK)
    d.text((1090,48),'0.6.2  /  Apple Silicon',font=font(21),fill=MUTED)
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
frames[8].save(OUT/'tour-poster.png')
# A static, legible review sheet for the most useful screenshots.
sheet=Image.new('RGB',(1600,1390),BG); d=ImageDraw.Draw(sheet)
d.text((35,26),'HyperMac 0.6.2 - interface gallery',font=font(34,True),fill=INK)
for n, idx in enumerate([0,5,8,10]):
    name,title,_=slides[idx]; x=35+(n%2)*790; y=100+(n//2)*640
    d.text((x,y),title,font=font(25,True),fill=CYAN)
    shot=ImageOps.contain(Image.open(OUT/'screenshots'/name).convert('RGB'),(750,575),Image.Resampling.LANCZOS)
    sheet.paste(shot,(x,y+42))
sheet.save(OUT/'overview.png')
print(f'Generated {len(frames)} frames, {len(frames)*5}s loop')
