#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: dumpe2fs, tune2fs, e2label, resize2fs de USR/E2TOOLS.PAS contre
#   e2fsprogs (hote) sur des images mke2fs : lignes principales de dumpe2fs -h,
#   puis tune2fs -L -m -c -C -i -e et e2label, relus par dumpe2fs et e2fsck -fn.
#   usage : e2toolstest.py ./E2TOOLS (lie en dumpe2fs tune2fs e2label ...)
import os, re, subprocess, sys, tempfile

PROG = os.path.abspath(sys.argv[1])
d = tempfile.mkdtemp()
for n in ('dumpe2fs', 'tune2fs', 'e2label', 'resize2fs'):
    os.symlink(PROG, os.path.join(d, n))
bad = 0
KEYS = ['Filesystem volume name', 'Filesystem UUID', 'Filesystem magic number',
        'Filesystem features', 'Filesystem state', 'Errors behavior',
        'Inode count', 'Block count', 'Reserved block count', 'Free blocks',
        'Free inodes', 'First block', 'Block size', 'Blocks per group',
        'Inodes per group', 'Mount count', 'Maximum mount count',
        'Check interval', 'Inode size']


def check(name, ok, detail=''):
    global bad
    print(('ok    ' if ok else 'ECHEC ') + name +
          ('' if ok else ' : ' + detail))
    if not ok:
        bad += 1


def fields(txt):
    out = {}
    for ln in txt.split('\n'):
        k, _, v = ln.partition(':')
        v = v.strip()
        if k.strip() in KEYS:
            out[k.strip()] = re.sub(r'\s+', ' ', v)
    return out


def mk(name, *opts, label=None):
    img = os.path.join(d, name)
    subprocess.run(['truncate', '-s', '24M', img], check=True)
    cmd = ['mke2fs', '-q', '-F'] + list(opts)
    if label:
        cmd += ['-L', label]
    subprocess.run(cmd + [img], check=True)
    return img


cases = [('e2.img', ['-t', 'ext2', '-b', '1024'], 'vol2'),
         ('e3.img', ['-t', 'ext3', '-b', '2048'], None),
         ('e4.img', ['-t', 'ext4', '-b', '4096', '-O', 'metadata_csum,64bit'],
          'quatre')]
for name, o, lb in cases:
    img = mk(name, *o, label=lb)
    a = fields(subprocess.run([os.path.join(d, 'dumpe2fs'), '-h', img],
                              capture_output=True, text=True).stdout)
    b = fields(subprocess.run(['dumpe2fs', '-h', img], capture_output=True,
                              text=True).stdout)
    diff = [(k, a.get(k), b.get(k)) for k in KEYS if a.get(k) != b.get(k)]
    check('dumpe2fs -h %s : %d lignes identiques a e2fsprogs' %
          (name, len(KEYS)), not diff, str(diff))
    t = os.path.join(d, 'tune2fs')
    r = subprocess.run([t, '-L', 'nouveau', '-m', '3', '-c', '20', '-C', '5',
                        '-i', '2w', '-e', 'remount-ro', img],
                       capture_output=True, text=True)
    b = fields(subprocess.run(['dumpe2fs', '-h', img], capture_output=True,
                              text=True).stdout)
    ok = (b.get('Filesystem volume name') == 'nouveau' and
          b.get('Maximum mount count') == '20' and
          b.get('Mount count') == '5' and
          b.get('Errors behavior') == 'Remount read-only' and
          b.get('Check interval', '').startswith('1209600'))
    check('tune2fs -L -m -c -C -i -e (%s) relu par e2fsprogs' % name, ok,
          r.stdout + r.stderr + str(b))
    rc = subprocess.run(['e2fsck', '-fn', img], capture_output=True, text=True)
    check('e2fsck -fn propre apres tune2fs (%s)' % name, rc.returncode == 0,
          rc.stdout[-300:])
    rsv = int(b['Reserved block count'])
    tot = int(b['Block count'])
    check('blocs reserves = 3 %% de %d (%s)' % (tot, name),
          abs(rsv - tot * 3 // 100) <= 1, str(rsv))
    l = subprocess.run([os.path.join(d, 'e2label'), img], capture_output=True,
                       text=True).stdout.strip()
    subprocess.run([os.path.join(d, 'e2label'), img, 'autre'])
    l2 = subprocess.run(['e2label', img], capture_output=True,
                        text=True).stdout.strip()
    check('e2label lit puis change le nom (%s)' % name,
          l == 'nouveau' and l2 == 'autre', l + '/' + l2)
img = os.path.join(d, 'e4.img')
r = subprocess.run([os.path.join(d, 'resize2fs'), img, '99999'],
                   capture_output=True, text=True)
check('resize2fs : changement de taille refuse proprement',
      r.returncode == 1 and 'non pris en charge' in r.stderr, r.stderr)
r = subprocess.run([os.path.join(d, 'resize2fs'), img], capture_output=True,
                   text=True)
check('resize2fs sans taille : "Nothing to do"', 'Nothing to do' in r.stdout,
      r.stdout)
open(os.path.join(d, 'junk'), 'wb').write(b'x' * 4096)
r = subprocess.run([os.path.join(d, 'dumpe2fs'), os.path.join(d, 'junk')],
                   capture_output=True, text=True)
check('fichier sans superbloc : erreur propre', r.returncode == 1, r.stderr)
sys.exit(1 if bad else 0)
