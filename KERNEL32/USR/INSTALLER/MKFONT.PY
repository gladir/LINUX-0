#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Genere FONTS.INC (tableaux const Pascal) : police bitmap
#   monochrome a chasse fixe, jeu Windows-1252 (Latin-1 + Euro + oe/OE +
#   guillemets, tirets...), en trois tailles : 8x16, 12x24 et 16x32. Rendu
#   FreeType (mode 1 bit, hinting) de DejaVu Sans Mono (licence libre).
#   Usage : MKFONT.PY [-f police.ttf] [-o FONTS.INC] [-p fonts.png]
import sys, os
from PIL import Image, ImageDraw, ImageFont

FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf'
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'FONTS.INC')
PNG = None
a = sys.argv[1:]
while a:
    if a[0] == '-f': FONT = a[1]
    elif a[0] == '-o': OUT = a[1]
    elif a[0] == '-p': PNG = a[1]
    a = a[2:]

SIZES = [('F8', 8, 16, 13), ('F12', 12, 24, 20), ('F16', 16, 32, 26)]

def cp1252(c):
    try:
        return bytes([c]).decode('cp1252')
    except Exception:
        return None

def glyph(font, ch, cw, chh, oy):
    im = Image.new('1', (cw * 3, chh * 3), 0)
    d = ImageDraw.Draw(im)
    d.fontmode = '1'
    d.text((cw, chh + oy), ch, font=font, fill=1)
    return im.crop((cw, chh, cw + cw, chh + chh))

def best_offset(font, cw, chh):
    # decale verticalement pour que les accents ET les jambages tiennent
    best = None
    for oy in range(-6, 7):
        bad = 0
        for ch in 'ÉÜÇÅÑg jñpqy|¡¿§':
            big = Image.new('1', (cw * 3, chh * 3), 0)
            d = ImageDraw.Draw(big)
            d.fontmode = '1'
            d.text((cw, chh + oy), ch, font=font, fill=1)
            bb = big.getbbox()
            if bb is None:
                continue
            if bb[1] < chh: bad += chh - bb[1]
            if bb[3] > 2 * chh: bad += bb[3] - 2 * chh
        if best is None or bad < best[0]:
            best = (bad, oy)
    return best[1]

lines = []
lines.append('{ FONTS.INC : genere par MKFONT.PY (DejaVu Sans Mono, Windows-1252)')
lines.append('  Glyphe i = code i + 32 (32..255) ; ligne = octets de gauche a')
lines.append('  droite, bit 7 = pixel de gauche. Ne pas modifier a la main. }')
sheet = None
rows = []
for name, cw, chh, px in SIZES:
    font = ImageFont.truetype(FONT, px)
    oy = best_offset(font, cw, chh)
    bpr = (cw + 7) // 8
    data = []
    ims = []
    for code in range(32, 256):
        ch = cp1252(code)
        if code == 127 or ch is None or code == 0xAD or code == 0xA0:
            ch = ' ' if code in (127, 0xA0) else None
        if ch is None:
            im = Image.new('1', (cw, chh), 0)
            # glyphe "inconnu" : cadre
            d = ImageDraw.Draw(im)
            d.rectangle([1, 2, cw - 2, chh - 3], outline=1)
        else:
            im = glyph(font, ch, cw, chh, oy)
        ims.append(im)
        px_ = im.load()
        for y in range(chh):
            for b in range(bpr):
                v = 0
                for k in range(8):
                    x = b * 8 + k
                    if x < cw and px_[x, y]:
                        v |= 0x80 >> k
                data.append(v)
    rows.append((name, cw, chh, ims))
    n = len(data)
    lines.append('')
    lines.append('Const')
    lines.append('  %sW = %d;' % (name, cw))
    lines.append('  %sH = %d;' % (name, chh))
    lines.append('  %sB = %d;' % (name, bpr))
    lines.append('  %sData : Array[0..%d] Of Byte = (' % (name, n - 1))
    for i in range(0, n, 16):
        chunk = ','.join('$%02X' % v for v in data[i:i + 16])
        lines.append('    ' + chunk + (',' if i + 16 < n else ''))
    lines.append('  );')
open(OUT, 'w').write('\n'.join(lines) + '\n')
mx = max(len(l) for l in lines)
print(OUT, 'lignes', len(lines), 'largeur max', mx)

if PNG:
    S = 3
    txt = list(range(0, 224))
    sheetw = 32 * 18 * S
    tot = 0
    for name, cw, chh, ims in rows:
        tot += (7 * (chh + 2)) * S + 8
    sheet = Image.new('L', (32 * 34 * 1, tot), 30)
    sheet = Image.new('L', (32 * 20 * S // 1, tot), 30)
    y = 0
    for name, cw, chh, ims in rows:
        for i, im in enumerate(ims):
            gx = (i % 32) * (cw + 2) * S // 1
            gy = y + (i // 32) * (chh + 2) * S
            g = im.convert('L').point(lambda v: 255 if v else 0)
            g = g.resize((cw * S, chh * S), Image.NEAREST)
            sheet.paste(g, (gx, gy))
        y += 7 * (chh + 2) * S + 8
    sheet.save(PNG)
