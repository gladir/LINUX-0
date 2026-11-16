#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: logrotate (USR/LOGROTATE.PAS) sur l'hote : rotate N, size,
#   notifempty, missingok, copytruncate, create, postrotate, include, -d.
#   usage : logrotatetest.py ./LOGROTATE
import os, subprocess, sys, tempfile

PROG = os.path.abspath(sys.argv[1])
bad = 0


def check(name, ok, detail=''):
    global bad
    print(('ok    ' if ok else 'ECHEC ') + name +
          ('' if ok else ' : ' + detail))
    if not ok:
        bad += 1


d = tempfile.mkdtemp()
os.makedirs(d + '/conf.d')
w = lambda p, s: open(d + '/' + p, 'w').write(s)
rd = lambda p: open(d + '/' + p).read() if os.path.exists(d + '/' + p) else None
w('a.log', 'AAAA\n')
w('b.log', 'x' * 100)
w('c.log', '')
w('d.log', 'DDDD\n')
w('e.log', 'tiny')
w('conf.d/more', '%s/e.log {\n size 1k\n rotate 1\n}\n' % d)
w('lr.conf', '''# essai
rotate 2
%(d)s/a.log {
  weekly
  create 600
  postrotate
    echo done > %(d)s/post.flag
  endscript
}
%(d)s/b.log {
  size 50
  rotate 3
  copytruncate
}
%(d)s/c.log %(d)s/absent.log {
  daily
  notifempty
  missingok
}
%(d)s/d.log {
  daily
  rotate 1
}
include %(d)s/conf.d
''' % {'d': d})
st = d + '/state'


def run(*a):
    return subprocess.run([PROG, '-s', st] + list(a) + [d + '/lr.conf'],
                          capture_output=True, text=True)


r = run('-d', '-f')
check('-d : rien n\'est modifie', rd('a.log') == 'AAAA\n' and
      rd('a.log.1') is None and 'rotation de' in r.stdout, r.stdout)
r = run('-f')
check('rotation forcee : a.log -> a.log.1, a.log recree (create 600)',
      rd('a.log.1') == 'AAAA\n' and rd('a.log') == '' and
      oct(os.stat(d + '/a.log').st_mode & 0o777) == '0o600',
      r.stdout + r.stderr)
check('postrotate execute', rd('post.flag') == 'done\n')
check('copytruncate : b.log.1 recoit les donnees, b.log est vide',
      rd('b.log.1') == 'x' * 100 and rd('b.log') == '')
check('notifempty / missingok : c.log et absent.log ignores',
      rd('c.log.1') is None and rd('absent.log.1') is None and
      r.returncode == 0)
check('include : e.log tourne', rd('e.log.1') == 'tiny')
w('a.log', 'SECOND\n')
run('-f')
check('rotate 2 : a.log.1 = recent, a.log.2 = ancien',
      rd('a.log.1') == 'SECOND\n' and rd('a.log.2') == 'AAAA\n')
w('a.log', 'THIRD\n')
run('-f')
check('rotate 2 : le plus ancien disparait', rd('a.log.2') == 'SECOND\n' and
      rd('a.log.3') is None)
w('b.log', 'y' * 10)
run()
check('size 50 : fichier de 10 octets non tourne',
      rd('b.log') == 'y' * 10)
w('b.log', 'z' * 60)
run()
check('size 50 : fichier de 60 octets tourne', rd('b.log') == '' and
      rd('b.log.1') == 'z' * 60)
w('d.log', 'D2\n')
r = run()
check('daily : pas de rotation le meme jour (etat)', rd('d.log') == 'D2\n')
check('fichier d\'etat ecrit',
      rd('state') is not None and 'a.log' in rd('state'))
sys.exit(1 if bad else 0)
