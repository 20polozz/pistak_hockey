# Renders the roller-hockey header (needs: pip install cairosvg). Run from repo root,
# then convert to JPEG: assets/sports/hockey_hero.jpg (what the app uses).
import cairosvg
W,H=1600,700
BG='#0B0F14'; LIME='#B8F23A'; ORANGE='#FF8A3D'; WHITE='#FFFFFF'

def stick(x, y, angle, shaft='#E8ECF1', tape='#1A2029', blade=LIME):
    # roller hockey stick drawn pointing down, blade hooks to the right; rotated by angle around (x,y)=top
    L=500
    return f'''
    <g transform="translate({x},{y}) rotate({angle})">
      <path d="M0,0 L0,{L} Q0,{L+70} 60,{L+78} L120,{L+80}" fill="none" stroke="{shaft}" stroke-width="30" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M0,{L+20} Q0,{L+70} 60,{L+78} L120,{L+80}" fill="none" stroke="{blade}" stroke-width="30" stroke-linecap="round"/>
      <path d="M0,0 L0,150" stroke="{tape}" stroke-width="30" stroke-linecap="round"/>
      <path d="M-15,40 L15,30 M-15,80 L15,70 M-15,120 L15,110" stroke="#2C3542" stroke-width="5"/>
    </g>'''

def rink():
    # 40m x 20m rink, scale 30 px/m, corner radius 1m*? (rounded corners), drawn centered then rotated
    s=34; w,h=40*s,20*s; r=1.5*s
    x0,y0=-w/2,-h/2
    st='stroke="#FFFFFF" stroke-opacity="0.09" stroke-width="5" fill="none"'
    area_w,area_h=5.4*s,9*s   # penalty area (depth 5.4m, width 9m)
    g=[f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" rx="{r}" {st}/>',
       f'<line x1="0" y1="{y0}" x2="0" y2="{-y0}" stroke="{LIME}" stroke-opacity="0.22" stroke-width="5"/>',
       f'<circle cx="0" cy="0" r="{3*s}" {st}/>',
       f'<circle cx="0" cy="0" r="7" fill="#FFFFFF" fill-opacity="0.25"/>']
    for side in (-1,1):
        gx=side*(w/2-3.5*s)          # goal line ~3.5m from end
        g.append(f'<line x1="{gx}" y1="{-area_h/2}" x2="{gx}" y2="{area_h/2}" {st}/>')
        ax=gx if side<0 else gx-area_w
        g.append(f'<rect x="{min(gx, gx-side*area_w)}" y="{-area_h/2}" width="{area_w}" height="{area_h}" {st}/>')
        # goal (1.7m wide, 0.9 deep) behind goal line
        gw=1.7*s; gd=0.9*s
        bx=gx if side>0 else gx-gd
        g.append(f'<rect x="{bx}" y="{-gw/2}" width="{gd}" height="{gw}" stroke="#FFFFFF" stroke-opacity="0.18" stroke-width="5" fill="none"/>')
        # penalty spot 5.4m from goal line, free-hit spot 7.4m
        for dist,rad in ((5.4,6),(7.4,6)):
            g.append(f'<circle cx="{gx-side*dist*s}" cy="0" r="{rad}" fill="#FFFFFF" fill-opacity="0.2"/>')
        # goalkeeper semicircle 1.5m
        g.append(f'<path d="M{gx},{-1.5*s} A{1.5*s},{1.5*s} 0 0 {0 if side>0 else 1} {gx},{1.5*s}" {st}/>')
    return f'<g transform="translate(760,360) rotate(-9) scale(1.25)">{"".join(g)}</g>'

svg=f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
<defs>
  <radialGradient id="glow" cx="72%" cy="45%" r="55%">
    <stop offset="0" stop-color="{LIME}" stop-opacity="0.16"/>
    <stop offset="1" stop-color="{LIME}" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="fade" x1="0" x2="1" y1="0" y2="0">
    <stop offset="0" stop-color="{BG}" stop-opacity="0.85"/>
    <stop offset="0.45" stop-color="{BG}" stop-opacity="0.2"/>
    <stop offset="1" stop-color="{BG}" stop-opacity="0"/>
  </linearGradient>
  <linearGradient id="bottom" x1="0" x2="0" y1="0" y2="1">
    <stop offset="0.82" stop-color="{BG}" stop-opacity="0"/>
    <stop offset="1" stop-color="{BG}" stop-opacity="1"/>
  </linearGradient>
  <radialGradient id="ball" cx="38%" cy="35%" r="70%">
    <stop offset="0" stop-color="#FFB37A"/>
    <stop offset="0.55" stop-color="{ORANGE}"/>
    <stop offset="1" stop-color="#C85A14"/>
  </radialGradient>
</defs>
<rect width="{W}" height="{H}" fill="{BG}"/>
{rink()}
<rect width="{W}" height="{H}" fill="url(#glow)"/>
{stick(1060,30,-28)}
{stick(1400,30,28, blade=ORANGE)}
<g opacity="0.5" stroke="{WHITE}" stroke-width="6" stroke-linecap="round">
  <line x1="840" y1="520" x2="940" y2="520" stroke-opacity="0.35"/>
  <line x1="860" y1="552" x2="945" y2="552" stroke-opacity="0.2"/>
  <line x1="875" y1="488" x2="945" y2="488" stroke-opacity="0.2"/>
</g>
<circle cx="1000" cy="520" r="38" fill="url(#ball)"/><circle cx="988" cy="508" r="9" fill="#FFFFFF" fill-opacity="0.35"/>
<rect width="{W}" height="{H}" fill="url(#fade)"/>
<rect width="{W}" height="{H}" fill="url(#bottom)"/>
</svg>'''
open('hockey.svg','w').write(svg)
cairosvg.svg2png(bytestring=svg.encode(), write_to='assets/sports/hockey_hero_master.png', output_width=W, output_height=H)
