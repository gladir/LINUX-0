#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Installation de LINUX-0 dans l'emulateur 8086 de DEVENV (depot
#   DEV-COOLS) en mode banc d'essai sans interface (/KERNELTEST, /KTBOOTIMG,
#   /KTHD, /KTSCRIPT : voir DEV-COOLS/DOC/KERNELTEST.txt). Aucune frappe
#   X11 : le script de DEVENV tape les reponses (type), change les
#   disquettes (mount A: ...) et capture l'ecran emule (screen).
#   Deux scenarios, avec une distribution reduite (le systeme de base,
#   environ 1,3 Mo : une disquette de donnees ou un CD) car le banc d'essai
#   de DEVENV est limite a 2 147 483 647 instructions au total, ce que
#   l'installation de la distribution complete (9 disquettes de donnees)
#   depasserait :
#   - disquettes : LINUX0-INST1.IMG (amorcable) + une disquette de donnees
#     (volume tar de la distribution reduite), disque cible vierge (/KTHD),
#     langue du systeme installe : SP (espagnol);
#   - CD-ROM : CD reduit (disque emule a une partition UFS1 avec /dist), le
#     disque cible est monte comme D: (81h) par la commande mount du script;
#   puis le disque installe est amorce seul (/KTBOOTIMG:disque.img), root se
#   connecte, /etc/profile est lu; le disque est verifie par TOOLS/UFSCHK.PAS
#   et par le lecteur UFS1 independant TESTS/UFSCMP.PY.
#   Usage : DEVENV=/chemin/devenv python3 DEVENV_INSTALL.PY [disquettes|cd]
#           [dossier_de_sortie]
#   Variables : W (repertoire de BUILD.SH), LD_LIBRARY_PATH (bibliotheques de
#   remplacement des DLL Windows). Xvfb (xvfb-run) est necessaire.
import os, re, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..'))
W = os.environ.get('W', '/tmp/linux0-build')
UFSCHK = os.path.join(W, 'bin', 'ufschk')
UFSCMP = os.path.join(HERE, 'UFSCMP.PY')
DEVENV = os.environ.get('DEVENV') or sys.exit('definir DEVENV (executable de DEVENV)')
MODE = sys.argv[1] if len(sys.argv) > 1 else 'disquettes'
OUT = os.path.abspath(sys.argv[2] if len(sys.argv) > 2 else 'devenv-install-' + MODE)
LANG = 'SP' if MODE == 'disquettes' else 'EN'
fails = 0


def ok(cond, what):
    global fails
    print(('ok    ' if cond else 'ECHEC ') + what, flush=True)
    if not cond:
        fails += 1


def sh(*cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode:
        sys.exit('echec : %s\n%s%s' % (' '.join(cmd), r.stdout, r.stderr))
    return r.stdout


def mini_distribution(work):
    """arbre reduit (systeme de base) et ses volumes tar"""
    tree = os.path.join(work, 'mini')
    sh('cp', '-a', os.path.join(W, 'fd144'), tree)
    lst = sh('bash', '-c', "cd '%s' && find . -mindepth 1 -printf '%%y %%m %%U %%G %%T@ %%P\\n' "
             "| LC_ALL=C sort -k6" % tree)
    open(os.path.join(work, 'LISTE'), 'w').write(lst)
    out = sh(os.path.join(W, 'bin', 'mkvol'), tree, os.path.join(work, 'LISTE'),
             os.path.join(work, 'INST'), '2')
    return tree, sorted(f for f in os.listdir(work) if re.match(r'INST\d+\.IMG$', f))


def run_devenv(work, name, img, hd, script, steps):
    open(os.path.join(work, name + '.txt'), 'w').write('\n'.join(script) + '\n')
    cmd = ['xvfb-run', '-a', DEVENV, '/KERNELTEST,' + work, '/KTBOOTIMG:' + img]
    if hd:
        cmd.append('/KTHD:' + hd)
    cmd += ['/KTSCRIPT:' + os.path.join(work, name + '.txt'), '/KTSTEPS:%d' % steps]
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=work, timeout=1800)
    open(os.path.join(OUT, name + '.out'), 'w').write(r.stdout)
    return r.stdout


def rechs(disk, out, heads=2, spt=18):
    """copie du disque installe dont la table des partitions est ecrite pour
    la geometrie du disque d'amorce de DEVENV : /KTHD (disque cible de
    l'installation) presente 255 tetes et 63 secteurs par piste, alors que
    /KTBOOTIMG presente un disque dur de 2 tetes et 18 secteurs (DEVENV.PAS,
    "disque dur de 1,44 Mo sans table de partitions", applique a toute image
    dure). Le MBR lit le secteur d'amorce par ses coordonnees CHS, qui
    doivent suivre la geometrie vue au demarrage; le noyau et UFSBOOT,
    eux, relisent la geometrie par l'INT 13h."""
    d = bytearray(open(disk, 'rb').read(1024 * 1024))

    def chs(lba):
        c, h, s = lba // (heads * spt), (lba // spt) % heads, lba % spt + 1
        if c > 1023:
            c, h, s = 1023, heads - 1, spt
        return bytes([h, s | ((c >> 2) & 0xC0), c & 255])
    for i in range(4):
        o = 446 + 16 * i
        if d[o + 4]:
            start = int.from_bytes(d[o + 8:o + 12], 'little')
            size = int.from_bytes(d[o + 12:o + 16], 'little')
            d[o + 1:o + 4] = chs(start)
            d[o + 5:o + 8] = chs(start + size - 1)
    shutil.copy(disk, out)
    with open(out, 'r+b') as f:
        f.write(bytes(d[:512]))
        # DEVENV lit aussi la geometrie dans les champs "secteurs par piste"
        # (1Ah) et "tetes" (18h) du secteur d'amorce de la partition active,
        # zone que UFSBOOT laisse a zero (BPB absent) et que DEVENV remplit
        # a sa guise quand le disque est monte comme D: ou /KTHD : on y met
        # la geometrie du disque d'amorce
        for i in range(4):
            if d[446 + 16 * i] == 0x80:
                start = int.from_bytes(d[446 + 16 * i + 8:446 + 16 * i + 12], 'little')
                f.seek(start * 512 + 0x18)
                f.write(spt.to_bytes(2, 'little') + heads.to_bytes(2, 'little'))


def boot_installed(work, disk, extra_profile):
    boot = os.path.join(work, 'amorce.img')
    rechs(disk, boot)
    disk = boot
    script = ['run 60000000', 'screen', 'type root', 'run 60000000',
              'type cat /etc/profile', 'run 40000000',
              'type ls /bin /etc', 'run 80000000', 'screen']
    out = run_devenv(work, 'demarrage', disk, None, script, 600000000)
    ok('racine : /dev/hda1 (UFS1)' in out and 'va-et-vient : /dev/hda2' in out,
       'le disque installe demarre seul sous DEVENV (racine /dev/hda1, va-et-vient /dev/hda2)')
    ok('LINUX-0 KERNEL16UNIX (linux0)' in out, 'banniere de getty : LINUX-0 KERNEL16UNIX (linux0)')
    ok(extra_profile in out, 'cat /etc/profile : ' + extra_profile)
    ok(re.search(r'\|(cat|ls)\s.*\n?', out) is not None and 'passwd' in out and 'getty' in out,
       'ls /bin /etc : les commandes et fichiers installes sont presents')


def verify_disk(disk, tree):
    r = subprocess.run([UFSCHK, '--hd', disk], capture_output=True, text=True)
    ok(r.returncode == 0, 'disque installe : UFS1, MBR et amorce coherents (%s)'
       % r.stdout.strip().splitlines()[-1])
    r = subprocess.run([sys.executable, UFSCMP, disk, tree, '--hd', '--extra', 'etc/profile'],
                       capture_output=True, text=True)
    ok(r.returncode == 0, 'disque installe : contenu identique a la distribution reduite (%s)'
       % r.stdout.strip().splitlines()[-1])
    if r.returncode:
        print(r.stdout)


def floppies(work):
    tree, vols = mini_distribution(work)
    shutil.copy(os.path.join(ROOT, 'IMAGE', 'LINUX0-INST1.IMG'), os.path.join(work, 'INST1.IMG'))
    disk = os.path.join(work, 'disque.img')
    with open(disk, 'wb') as f:
        f.truncate(64 * 1024 * 1024)
    script = ['run 40000000', 'screen', 'type install', 'run 40000000', 'screen',
              'type ' + LANG, 'run 20000000', 'type oui', 'run 300000000', 'screen']
    for v in vols:
        script += ['mount A: ' + os.path.join(work, v), 'type', 'run 300000000', 'screen']
    script += ['screen', 'type non', 'run 40000000', 'screen',
               'mount A: ' + os.path.join(work, 'INST1.IMG'), 'type', 'run 80000000', 'screen']
    out = run_devenv(work, 'installation', os.path.join(work, 'INST1.IMG'), disk, script,
                     2000000000)
    ok('Source : disquettes d\'installation' in out, 'installateur lance depuis la disquette 1')
    ok('Idioma del sistema instalado' in out or 'Langue du systeme installe' in out,
       'question sur la langue du systeme installe')
    ok('Inserez la disquette 2' in out, 'disquette 2 demandee')
    ok('Volume 2/%d' % (1 + len(vols)) in out and 'termine' in out, 'volumes de donnees lus')
    ok('Installation terminee' in out, 'Installation terminee')
    ok('Remettez la disquette 1' in out and out.rstrip().count('login:') >= 1,
       'retour a la disquette 1 : invite de connexion')
    verify_disk(disk, tree)
    boot_installed(work, disk, 'LANGUAGE=%s; export LANGUAGE' % LANG)


def cd(work):
    tree, vols = mini_distribution(work)
    inst = os.path.join(work, 'cd')
    sh('cp', '-a', os.path.join(W, 'inst'), inst)
    os.makedirs(os.path.join(inst, 'dist'))
    for v in vols:
        n = re.search(r'\d+', v).group()
        shutil.copy(os.path.join(work, 'INST%s.TAR' % n), os.path.join(inst, 'dist', 'vol%s.tar' % n))
    sh('chmod', '755', os.path.join(inst, 'dist'))
    ufs = os.path.join(work, 'cd.ufs')
    sh('makefs', '-t', 'ffs', '-o', 'version=1,minfree=0,density=16384', '-s', '8m', ufs, inst)
    hd = os.path.join(work, 'cdhd.img')
    sh(os.path.join(W, 'bin', 'mkimage'), 'HD', hd, os.path.join(ROOT, 'MBR.BIN'),
       os.path.join(ROOT, 'UFSBOOT.BIN'), ufs, '0')
    iso = os.path.join(work, 'cd.iso')
    sh(os.path.join(W, 'bin', 'mkiso'), iso, hd)
    disk = os.path.join(work, 'disque.img')
    with open(disk, 'wb') as f:
        f.truncate(64 * 1024 * 1024)
    # /KTHD n'est pas monte quand l'image d'amorce est un disque dur (ou un
    # CD en emulation de disque dur) : le disque cible est monte comme D:
    # (81h) par la commande mount, avant la premiere instruction
    script = ['mount D: ' + disk, 'run 60000000', 'screen', 'type install',
              'run 60000000', 'screen', 'type ' + LANG, 'run 20000000', 'type oui',
              'run 900000000', 'screen', 'type non', 'run 80000000', 'screen']
    out = run_devenv(work, 'installation', iso, None, script, 2000000000)
    ok('Source : CD-ROM (/dist)' in out, 'installateur lance depuis le CD-ROM (/dist)')
    ok('Installation terminee' in out, 'Installation terminee')
    verify_disk(disk, tree)
    boot_installed(work, disk, 'LANGUAGE=%s; export LANGUAGE' % LANG)


def main():
    os.makedirs(OUT, exist_ok=True)
    work = os.path.join(OUT, 'images')
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    if MODE == 'cd':
        cd(work)
    else:
        floppies(work)
    print('captures : ' + OUT)
    print(('OK DEVENV (%s)' if not fails else 'ECHEC DEVENV (%s)') % MODE)
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
