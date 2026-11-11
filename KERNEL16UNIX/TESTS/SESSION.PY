#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Essai d'une session LINUX-0 complete sous QEMU, par la console
#   serie (COM1 sert aussi de clavier) : init lance getty, connexion de
#   l'utilisateur invite (mot de passe), commandes du shell (variables, tubes,
#   redirections, motifs, arriere-plan, &&, ||, ^C), permissions, ps, kill,
#   passwd, va-et-vient, puis connexion de root.
#   Usage : python3 SESSION.PY IMAGE_DISQUE_DUR   (code de sortie 0 si OK)
import socket, subprocess, sys, time, re, os, shutil, tempfile

img = sys.argv[1]
tmp = tempfile.mkdtemp()
disk = os.path.join(tmp, 'hd.img')
shutil.copy(img, disk)
port = 4600 + os.getpid() % 300
q = subprocess.Popen(['qemu-system-i386', '-m', '1', '-display', 'none',
                      '-no-reboot', '-boot', 'c',
                      '-drive', 'file=%s,format=raw,if=ide' % disk,
                      '-serial', 'tcp:127.0.0.1:%d,server,nowait' % port],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
s = None
for i in range(50):
    try:
        s = socket.create_connection(('127.0.0.1', port))
        break
    except OSError:
        time.sleep(0.2)
if s is None:
    sys.exit('QEMU : pas de console serie')
s.settimeout(0.2)
out = ''
fails = 0


def pump(t):
    global out
    end = time.time() + t
    while time.time() < end:
        try:
            d = s.recv(4096)
            if not d:
                break
            out += d.decode('latin-1')
        except socket.timeout:
            pass


def expect(pat, t=30):
    global out
    end = time.time() + t
    while time.time() < end:
        m = re.search(pat, out)
        if m:
            seen = out[:m.end()]
            out = out[m.end():]
            return seen
        pump(0.3)
    raise TimeoutError('attendu %r, recu %r' % (pat, out[-300:]))


def send(line, cr=True):
    for c in line + ('\r' if cr else ''):
        s.send(c.encode('latin-1'))
        time.sleep(0.02)


def run(cmd, pat, prompt=r'\$ $', t=30):
    """commande -> sortie jusqu'a l'invite; verifie le motif pat"""
    global fails
    send(cmd)
    txt = expect(r'(?m)^' + prompt if prompt else pat, t)
    txt = txt.replace('\r', '')
    body = txt.split('\n', 1)[1] if '\n' in txt else ''
    ok = re.search(pat, body, re.S) is not None
    print(('ok    ' if ok else 'ECHEC ') + cmd)
    for l in body.split('\n')[:-1]:
        print('      | ' + l)
    if not ok:
        fails += 1
    return body


try:
    expect(r'login: ', 90)
    print('getty : invite "login:"')
    send('invite')
    expect(r'Mot de passe : ')
    send('mauvais')
    expect(r'Connexion refusee')
    print('ok    mot de passe faux refuse')
    expect(r'login: ')
    send('invite')
    expect(r'Mot de passe : ')
    send('invite')
    expect(r'Bienvenue sous LINUX-0')
    expect(r'\$ $')
    print('ok    connexion de invite (motd, invite $)')
    run('id', r'uid=100\(invite\) gid=100')
    run('pwd', r'/home/invite')
    run('echo $HOME $USER "$PATH" \'$HOME\'', r'/home/invite invite /bin:/usr/bin \$HOME')
    run('X=un; Y="deux trois"; echo $X-$Y; echo ${X}s', r'un-deux trois\nuns')
    run('ls /etc', r'getty.*init.*passwd')
    run('cat /etc/passwd | grep root | wc -l', r'\b1\b')
    run('echo bonjour > f.txt; echo suite >> f.txt; cat < f.txt', r'bonjour\nsuite')
    run('echo /bin/c*', r'/bin/cat.*/bin/chmod.*/bin/cp')
    run('true && echo et-ok; false && echo jamais; false || echo ou-ok', r'^et-ok\nou-ok\n')
    run('introuvable; echo $?', r'introuvable: introuvable\n127')
    run('introuvable 2> err.txt; cat err.txt', r'introuvable: introuvable')
    run('echo a b > /usr/interdit', r'Permission refusee')
    run('ls -l /usr | grep src', r'src')
    run('sleep 30 &', r'^\d+\n')
    # trois commandes en tube a cote d'une commande en arriere-plan : la
    # memoire manque, le va-et-vient prend le relais
    run('cat /etc/passwd | grep root | wc -l; ps', r'^1\n.*va-et-vient :')
    body = run('ps', r'sleep')
    pid = re.search(r'^\s*(\d+)\s+\d+\s+100 S.*sleep', body, re.M)
    if pid:
        run('kill -9 %s; wait; echo attendu' % pid.group(1), r'Tue\n.*attendu')
    run('kill 1', r'Operation non permise')
    send('sleep 20')
    time.sleep(2)
    t0 = time.time()
    s.send(b'\x03')
    expect(r'\$ $', 10)
    if time.time() - t0 < 5:
        print('ok    ^C interrompt la commande au premier plan, pas le shell')
    else:
        print('ECHEC ^C'); fails += 1
    run('echo $?', r'130')
    run('mkdir d; cd d; pwd; cd ..; rmdir d; echo $?', r'/home/invite/d\n0')
    send('passwd')
    expect(r'Ancien mot de passe : ')
    send('invite')
    expect(r'Nouveau mot de passe : ')
    send('secret')
    expect(r'\(encore\) : ')
    send('secret')
    expect(r'\$ $')
    run('grep invite /etc/passwd', r'invite:..[./0-9A-Za-z]{11}:100')
    send('exit')
    expect(r'login: ', 30)
    print('ok    fin de session : nouveau getty')
    send('invite')
    expect(r'Mot de passe : ')
    send('secret')
    expect(r'\$ $')
    print('ok    nouveau mot de passe accepte')
    send('exit')
    expect(r'login: ', 30)
    send('root')
    expect(r'# $')
    print('ok    connexion de root sans mot de passe (invite #)')
    run('id; echo a b > /etc/essai; cat /etc/essai; rm /etc/essai', r'uid=0\(root\).*a b', prompt=r'# $')
    run('umask; umask 077; umask', r'022\n077', prompt=r'# $')
    run('ls /usr/src | wc -l; echo /usr/src/W*', r'\b\d\d\b\n/usr/src/WC.PAS', prompt=r'# $')
except TimeoutError as e:
    print('ECHEC ' + str(e))
    fails += 1
finally:
    q.kill()
    shutil.rmtree(tmp)
print('Session : %d echec(s)' % fails)
sys.exit(1 if fails else 0)
