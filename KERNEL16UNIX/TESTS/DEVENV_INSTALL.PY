#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Installation de LINUX-0 dans l'onglet "Emulateur 8086" de
#   DEVENV (depot DEV-COOLS), pilote comme le ferait un utilisateur :
#   - l'IDE est lance en plein ecran (-maxscreen) avec un fichier .bat pour
#     l'Invite de commandes : IMGMOUNT A: LINUX0-INST1.IMG, IMGMOUNT C: disque
#     vierge, BOOT A: (ou BOOT /CDROM:LINUX0-CD.ISO puis IMGMOUNT D: disque);
#   - les reponses a l'installateur sont tapees dans l'onglet emulateur;
#   - a chaque "Inserez la disquette N", la disquette est changee dans
#     l'Invite de commandes (IMGMOUNT -u A puis IMGMOUNT A: LINUX0-INSTN.IMG);
#   - le disque installe est ensuite monte sur C: et amorce par BOOT C:.
#   L'ecran de l'emulateur est lu en reconnaissant les caracteres (police
#   8x8 de l'emulateur, lignes de 14 points), pour attendre chaque question
#   de l'installateur; chaque etape est capturee (PNG et texte) dans le
#   dossier de sortie. Le disque installe est verifie par TOOLS/UFSCHK.PAS.
#   Usage : DEVENV=/chemin/devenv python3 DEVENV_INSTALL.PY [disquettes|cd]
#           [dossier_de_sortie]
#   Sous Linux : Xvfb, xdotool et ImageMagick (import) sont necessaires.
import os, re, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..'))
# verificateur UFS1 (TOOLS/UFSCHK.PAS, compile par BUILD.SH)
UFSCHK = os.path.join(os.environ.get('W', '/tmp/unix0-build'), 'bin', 'ufschk')
DEVENV = os.environ.get('DEVENV') or sys.exit('definir DEVENV (executable de DEVENV)')
MODE = sys.argv[1] if len(sys.argv) > 1 else 'disquettes'
OUT = os.path.abspath(sys.argv[2] if len(sys.argv) > 2 else 'devenv-install-' + MODE)
DISPLAY = ':78'
TEXT_Y, ROWS, COLS = 96, 25, 80  # texte de l'onglet emulateur (plein ecran)
TERM_XY = (400, 1050)            # Invite de commandes (plein ecran 1920x1200)
EMU_XY = (300, 300)
env = dict(os.environ, DISPLAY=DISPLAY)
shots = 0

# police 8x8 de l'emulateur, caracteres 32 a 126
FONT = bytes.fromhex(
    '000000000000000030787878300030006c6c6c00000000006c6cfe6cfe6c6c00307cc078'
    '0cf8300000c6cc183066c600386c3876dccc76006060c000000000001830606060301800'
    '603018181830600000663cff3c660000003030fc303000000000000000303060000000fc'
    '000000000000000000303000060c183060c080007cc6c6c6c6c67c00307030303030fc00'
    '78cc0c3860ccfc0078cc0c380ccc78001c3c6cccfe0c1e00fcc0f80c0ccc78003860c0f8'
    'cccc7800fccc0c183030300078cccc78cccc780078cccc7c0c1870000030300000303000'
    '0030300000303060183060c0603018000000fc0000fc00006030180c1830600078cc0c18'
    '300030007cc6dededec07800386cc6c6fec6c600fcc6c6fcc6c6fc007cc6c6c0c0c67c00'
    'f8ccc6c6c6ccf800fec0c0fcc0c0fe00fec0c0fcc0c0c0007cc6c0cec6c67e00c6c6c6fe'
    'c6c6c60078303030303078001e060606c6c67c00c6ccd8f0d8ccc600c0c0c0c0c0c0fe00'
    'c6eefed6c6c6c600c6e6f6decec6c6007cc6c6c6c6c67c00fcc6c6fcc0c0c0007cc6c6c6'
    'c6c67c06fcc6c6fcc6c6c60078cc603018cc7800fc30303030303000c6c6c6c6c6c67c00'
    'c6c6c6c6c66c3800c6c6c6d6feeec600c6c66c386cc6c600c3c3663c18181800fe0c1830'
    '60c0fe003c30303030303c00c06030180c0603003c0c0c0c0c0c3c0000386cc600000000'
    '00000000000000ff303018000000000000007c067ec67e00c0c0fcc6c6e6dc0000007cc6'
    'c0c07e0006067ec6c6ce760000007cc6fec07e001e307c303030300000007ec6ce76067c'
    'c0c0fcc6c6c6c6001800381818183c0018003818181818f0c0c0ccd8f0d8cc0038181818'
    '18183c000000ccfed6c6c6000000fcc6c6c6c60000007cc6c6c67c000000fcc6c6e6dcc0'
    '00007ec6c6ce760600006e706060600000007cc07c06fc0030307c3030301c000000c6c6'
    'c6c67e000000c6c6c66c38000000c6c6d6fe6c000000c66c386cc6000000c6c6ce76067c'
    '0000fc183060fc001c3030e030301c001818180018181800e030301c3030e00076dc0000'
    '00000000'
)
GLYPHS = {}
for _k in range(95):
    _g = FONT[_k * 8:_k * 8 + 8]
    GLYPHS.setdefault(_g, chr(32 + _k))
    GLYPHS.setdefault(bytes(b | (b >> 1) for b in _g), chr(32 + _k))
GLYPHS[bytes(8)] = ' '


def sh(*cmd):
    return subprocess.run(cmd, env=env, capture_output=True, text=True).stdout


def screen():
    """lignes de texte de l'onglet emulateur ('0' et 'O' se confondent)"""
    raw = subprocess.run(['import', '-window', 'root', '-crop', '%dx%d+0+%d'
                          % (COLS * 8, ROWS * 14, TEXT_Y), '-depth', '8', 'rgb:-'],
                         env=env, capture_output=True).stdout
    w = COLS * 8
    if len(raw) < w * ROWS * 14 * 3:
        return []
    sample = [raw[i:i + 3] for i in range(0, len(raw), 3 * 97)]
    bg = max(set(sample), key=sample.count)     # couleur de fond
    lines = []
    for r in range(ROWS):
        s = ''
        for c in range(COLS):
            cell = bytearray(8)
            for y in range(8):
                o = ((r * 14 + y) * w + c * 8) * 3
                for x in range(8):
                    if raw[o + x * 3:o + x * 3 + 3] != bg:
                        cell[y] |= 128 >> x
            s += GLYPHS.get(bytes(cell), '?')
        lines.append(s.rstrip())
    return lines


def last_line(lines):
    for l in reversed(lines):
        if l.strip():
            return l
    return ''


def wait_for(pat, limit=1800, anywhere=False):
    """attend que la derniere ligne (ou l'ecran) corresponde a pat"""
    end = time.time() + limit
    lines = []
    while time.time() < end:
        lines = screen()
        text = '\n'.join(lines) if anywhere else last_line(lines)
        m = re.search(pat, text.replace('O', '0') if '0' in pat else text)
        if m:
            print('  vu : ' + last_line(lines))
            return m
        time.sleep(3)
    raise TimeoutError('attendu %r, ecran :\n%s' % (pat, '\n'.join(lines)))


def shot(name, crop='640x480+0+0'):
    global shots
    shots += 1
    p = os.path.join(OUT, '%02d-%s' % (shots, name))
    sh('import', '-window', 'root', '-crop', crop, p + '.png')
    if crop.startswith('640x480'):
        open(p + '.txt', 'w').write('\n'.join(screen()) + '\n')


def win():
    return sh('xdotool', 'search', '--onlyvisible', '--name', '.').split()[0]


def click(xy):
    w = win()
    sh('xdotool', 'mousemove', '--window', w, str(xy[0]), str(xy[1]))
    time.sleep(0.3)
    sh('xdotool', 'mousedown', '--window', w, '1')
    time.sleep(0.3)
    sh('xdotool', 'mouseup', '--window', w, '1')
    time.sleep(1)


def type_line(text):
    w = win()
    if text:
        sh('xdotool', 'type', '--window', w, '--delay', '120', text)
    sh('xdotool', 'key', '--window', w, 'Return')


def emulator(text):
    click(EMU_XY)
    type_line(text)


def terminal(*cmds):
    click(TERM_XY)
    for c in cmds:
        type_line(c)
        time.sleep(3)


def main():
    os.makedirs(OUT, exist_ok=True)
    work = os.path.join(OUT, 'images')
    os.makedirs(work, exist_ok=True)
    for f in os.listdir(os.path.join(ROOT, 'IMAGE')):
        if f.startswith('LINUX0-INST') or f == 'LINUX0-CD.ISO':
            shutil.copy(os.path.join(ROOT, 'IMAGE', f), work)
    disk = os.path.join(work, 'disque.img')
    with open(disk, 'wb') as f:
        f.truncate(64 * 1024 * 1024)
    bat = os.path.join(work, 'inst.bat')
    if MODE == 'cd':
        lines = ['BOOT /CDROM:%s/LINUX0-CD.ISO' % work, 'IMGMOUNT D: %s' % disk]
    else:
        lines = ['IMGMOUNT A: %s/LINUX0-INST1.IMG' % work, 'IMGMOUNT C: %s' % disk, 'BOOT A:']
    open(bat, 'w').write('\r\n'.join(lines) + '\r\n')
    xvfb = subprocess.Popen(['Xvfb', DISPLAY, '-screen', '0', '1920x1200x24'],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2)
    ide = subprocess.Popen([DEVENV, '-maxscreen', '/TERMINALDOS:' + bat], cwd=work, env=env,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    ok = False
    try:
        wait_for(r'^login:$', 600)
        shot('amorce')
        emulator('install')                     # connexion "install"
        wait_for(r'^Choix \[1\] :')
        shot('type-installation')
        emulator('' if MODE != 'cd' else '2')   # UFS seul / FAT16 + UFS
        wait_for(r'Continuer \? \(oui/non\)')
        emulator('oui')
        n = 2
        last = len([x for x in os.listdir(work) if x.startswith('LINUX0-INST')])
        while MODE != 'cd' and n <= last:
            wait_for(r'Inserez la disquette %d ' % n, 3600)
            shot('disquette-%d' % n)
            # changement de disquette par l'Invite de commandes
            terminal('IMGMOUNT -u A', 'IMGMOUNT A: %s/LINUX0-INST%d.IMG' % (work, n))
            shot('invite-de-commandes', '1360x200+0+880')
            emulator('')
            n += 1
        wait_for(r'Redemarrer maintenant \? \(oui/non\)', 3600)
        shot('installation-terminee')
        print('  ' + [l for l in screen() if 'Installation terminee' in l][-1].strip())
        emulator('non')                         # pas de redemarrage
        if MODE == 'cd':
            wait_for(r'^login:$', 120)
            terminal('IMGMOUNT -u C', 'IMGMOUNT -u D', 'IMGMOUNT C: %s' % disk, 'BOOT C:')
        else:
            wait_for(r'Remettez la disquette 1', 120)
            terminal('IMGMOUNT -u A', 'IMGMOUNT A: %s/LINUX0-INST1.IMG' % work)
            emulator('')
            wait_for(r'^login:$', 120)
            terminal('IMGMOUNT -u A', 'BOOT C:')
        # amorce UFS (disquettes : UFS seul) ou FAT16 (CD-ROM : FAT16 + UFS)
        wait_for(r'Chargement de /unix' if MODE != 'cd' else r'/boot : /dev/hda1', 300, anywhere=True)
        wait_for(r'^login:$', 600)
        shot('amorce-disque-installe')
        boot = '\n'.join(screen())
        emulator('invite')
        wait_for(r'Mot de passe', 120)
        emulator('invite')
        wait_for(r'^\$$', 300)
        emulator('id; ls /; ls /bin | wc -l')
        time.sleep(5)
        wait_for(r'^\$$', 300)
        shot('session-invite')
        r = subprocess.run([UFSCHK, '--hd', disk],
                           capture_output=True, text=True)
        print('UFS1 du disque installe : ' + r.stdout.strip().splitlines()[-1])
        want = 'racine : /dev/hda1 (UFS' if MODE != 'cd' else 'racine : /dev/hda2 (UFS'
        print('amorce du disque installe : ' + ('ok' if want in boot else 'ECHEC (' + want + ')'))
        ok = r.returncode == 0 and want in boot
    except TimeoutError as e:
        print(e)
        shot('erreur')
    finally:
        ide.kill()
        xvfb.kill()
    print('captures : ' + OUT)
    print('OK DEVENV (%s)' % MODE if ok else 'ECHEC DEVENV (%s)' % MODE)
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
