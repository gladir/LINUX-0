#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @abstract(Target: Python 3)
# @description: Essais de tcpdump (programme i386) sur l'hote : fabrique un
#   fichier pcap de trames connues (ARP, ICMP, TCP avec options, UDP, DNS,
#   BOOTP, IPv6), compare la sortie de "tcpdump -n -r" au texte attendu,
#   essaie les filtres, -e, -x, -c, et une capture reelle sur lo (-w puis
#   analyse du fichier pcap en Python).
#   Usage : tcpdumptest.py TCPDUMP
import os, socket, struct, subprocess, sys, tempfile, time

TD = os.path.abspath(sys.argv[1])
W = tempfile.mkdtemp(prefix='tdtest')
ok = ko = 0
ENV = dict(os.environ, TZ='UTC', LANG='C', LC_ALL='C')


def res(name, cond, extra=''):
    global ok, ko
    if cond:
        ok += 1
        print('ok    ' + name)
    else:
        ko += 1
        print('KO    %s %s' % (name, extra))


def mac(s):
    return bytes(int(x, 16) for x in s.split(':'))


def ip(s):
    return socket.inet_aton(s)


def csum(b):
    if len(b) % 2:
        b += b'\0'
    s = sum(struct.unpack('!%dH' % (len(b) // 2), b))
    while s >> 16:
        s = (s & 0xffff) + (s >> 16)
    return (~s) & 0xffff


def ipv4(src, dst, proto, payload, ident=1):
    h = struct.pack('!BBHHHBBH4s4s', 0x45, 0, 20 + len(payload), ident, 0,
                    64, proto, 0, ip(src), ip(dst))
    h = h[:10] + struct.pack('!H', csum(h)) + h[12:]
    return h + payload


M1 = '52:54:00:12:34:56'
M2 = '52:55:0a:00:02:02'


def eth(dst, src, typ, payload):
    return mac(dst) + mac(src) + struct.pack('!H', typ) + payload


def qname(n):
    return b''.join(bytes([len(p)]) + p.encode() for p in n.split('.')) + b'\0'


pk = []
t0 = 1700000000
# 0 ARP requete
arp = struct.pack('!HHBBH', 1, 0x800, 6, 4, 1) + mac(M1) + ip('10.0.2.15') + \
    bytes(6) + ip('10.0.2.2')
pk.append(eth('ff:ff:ff:ff:ff:ff', M1, 0x806, arp))
# 1 ARP reponse
arp = struct.pack('!HHBBH', 1, 0x800, 6, 4, 2) + mac(M2) + ip('10.0.2.2') + \
    mac(M1) + ip('10.0.2.15')
pk.append(eth(M1, M2, 0x806, arp))
# 2 ICMP echo request
icmp = struct.pack('!BBHHH', 8, 0, 0, 0x1234, 7) + b'x' * 56
pk.append(eth(M2, M1, 0x800, ipv4('10.0.2.15', '10.0.2.2', 1, icmp)))
# 3 ICMP echo reply
icmp = struct.pack('!BBHHH', 0, 0, 0, 0x1234, 7) + b'x' * 56
pk.append(eth(M1, M2, 0x800, ipv4('10.0.2.2', '10.0.2.15', 1, icmp)))
# 4 TCP SYN avec options
opts = b'\x02\x04\x05\xb4\x04\x02\x08\x0a' + struct.pack('!II', 100, 0) + \
    b'\x01\x03\x03\x07'
tcp = struct.pack('!HHIIBBHHH', 43210, 80, 1000, 0, (5 + len(opts) // 4) << 4,
                  2, 29200, 0, 0) + opts
pk.append(eth(M2, M1, 0x800, ipv4('10.0.2.15', '93.184.216.34', 6, tcp)))
# 5 TCP SYN-ACK
tcp = struct.pack('!HHIIBBHHH', 80, 43210, 5000, 1001, 5 << 4, 0x12, 65535,
                  0, 0)
pk.append(eth(M1, M2, 0x800, ipv4('93.184.216.34', '10.0.2.15', 6, tcp)))
# 6 TCP PSH-ACK 100 octets
tcp = struct.pack('!HHIIBBHHH', 43210, 80, 1001, 5001, 5 << 4, 0x18, 502, 0,
                  0) + b'G' * 100
pk.append(eth(M2, M1, 0x800, ipv4('10.0.2.15', '93.184.216.34', 6, tcp)))
# 7 DNS requete A? example.com
dns = struct.pack('!HHHHHH', 0x3039, 0x0100, 1, 0, 0, 0) + \
    qname('example.com') + struct.pack('!HH', 1, 1)
udp = struct.pack('!HHHH', 40000, 53, 8 + len(dns), 0) + dns
pk.append(eth(M2, M1, 0x800, ipv4('10.0.2.15', '10.0.2.3', 17, udp)))
# 8 DNS reponse 1 reponse A
dns = struct.pack('!HHHHHH', 0x3039, 0x8180, 1, 1, 0, 0) + \
    qname('example.com') + struct.pack('!HH', 1, 1) + \
    b'\xc0\x0c' + struct.pack('!HHIH', 1, 1, 300, 4) + ip('93.184.216.34')
udp = struct.pack('!HHHH', 53, 40000, 8 + len(dns), 0) + dns
pk.append(eth(M1, M2, 0x800, ipv4('10.0.2.3', '10.0.2.15', 17, udp)))
# 9 UDP quelconque
udp = struct.pack('!HHHH', 5000, 6000, 8 + 12, 0) + b'bonjour tout'
pk.append(eth(M2, M1, 0x800, ipv4('10.0.2.15', '10.0.2.2', 17, udp)))
# 10 DHCP discover
bootp = bytes([1, 1, 6, 0]) + bytes(24) + mac(M1) + bytes(266)
udp = struct.pack('!HHHH', 68, 67, 8 + len(bootp), 0) + bootp
pk.append(eth('ff:ff:ff:ff:ff:ff', M1, 0x800,
              ipv4('0.0.0.0', '255.255.255.255', 17, udp)))
# 11 IPv6
v6 = struct.pack('!IHBB', 0x60000000, 8, 58, 255) + \
    socket.inet_pton(socket.AF_INET6, 'fe80::1') + \
    socket.inet_pton(socket.AF_INET6, 'ff02::2') + bytes(8)
pk.append(eth('33:33:00:00:00:02', M1, 0x86dd, v6))
# 12 ICMP port unreachable
icmp = struct.pack('!BBHI', 3, 3, 0, 0) + bytes(28)
pk.append(eth(M1, M2, 0x800, ipv4('10.0.2.2', '10.0.2.15', 1, icmp)))
# 13 ethertype inconnu
pk.append(eth(M2, M1, 0x88b5, bytes(50)))

pcap = os.path.join(W, 'a.pcap')
with open(pcap, 'wb') as f:
    f.write(struct.pack('<IHHiIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1))
    for i, p in enumerate(pk):
        f.write(struct.pack('<IIII', t0 + i, 123456, len(p), len(p)))
        f.write(p)


def run(args, **kw):
    r = subprocess.run([TD] + args, capture_output=True, text=True, env=ENV,
                       cwd=W, timeout=30, **kw)
    return r


def T(i):
    s = (t0 + i) % 86400
    return '%02d:%02d:%02d.123456' % (s // 3600, s % 3600 // 60, s % 60)


exp = [
    T(0) + ' ARP, Request who-has 10.0.2.2 tell 10.0.2.15, length 28',
    T(1) + ' ARP, Reply 10.0.2.2 is-at 52:55:0a:00:02:02, length 28',
    T(2) + ' IP 10.0.2.15 > 10.0.2.2: ICMP echo request, id 4660, seq 7, '
    'length 64',
    T(3) + ' IP 10.0.2.2 > 10.0.2.15: ICMP echo reply, id 4660, seq 7, '
    'length 64',
    T(4) + ' IP 10.0.2.15.43210 > 93.184.216.34.80: Flags [S], seq 1000, '
    'win 29200, options [mss 1460,sackOK,TS val 100 ecr 0,nop,wscale 7], '
    'length 0',
    T(5) + ' IP 93.184.216.34.80 > 10.0.2.15.43210: Flags [S.], seq 5000, '
    'ack 1001, win 65535, length 0',
    T(6) + ' IP 10.0.2.15.43210 > 93.184.216.34.80: Flags [P.], '
    'seq 1001:1101, ack 5001, win 502, length 100',
    T(7) + ' IP 10.0.2.15.40000 > 10.0.2.3.53: 12345+ A? example.com. (29)',
    T(8) + ' IP 10.0.2.3.53 > 10.0.2.15.40000: 12345 1/0/0 A 93.184.216.34 '
    '(45)',
    T(9) + ' IP 10.0.2.15.5000 > 10.0.2.2.6000: UDP, length 12',
    T(10) + ' IP 0.0.0.0.68 > 255.255.255.255.67: BOOTP/DHCP, Request from '
    '52:54:00:12:34:56, length 300',
    T(11) + ' IP6 fe80::1 > ff02::2: ip6-proto-58, length 8',
    T(12) + ' IP 10.0.2.2 > 10.0.2.15: ICMP port unreachable, length 36',
    T(13) + ' ethertype 0x88b5, length 64',
]
r = run(['-n', '-r', pcap])
got = r.stdout.splitlines()
for i, e in enumerate(exp):
    res('decodage trame %d' % i, i < len(got) and got[i] == e,
        '\n  attendu %s\n  obtenu  %s' % (e, got[i] if i < len(got) else ''))
res('nombre de lignes', len(got) == len(exp), '%d' % len(got))

# filtres
def filt(args, idx):
    r = run(['-n', '-r', pcap] + args)
    return [l.split(' ', 1)[0] for l in r.stdout.splitlines()] == \
        [T(i) for i in idx]


res('filtre arp', filt(['arp'], [0, 1]))
res('filtre icmp', filt(['icmp'], [2, 3, 12]))
res('filtre tcp', filt(['tcp'], [4, 5, 6]))
res('filtre udp', filt(['udp'], [7, 8, 9, 10]))
res('filtre port 53', filt(['port', '53'], [7, 8]))
res('filtre dst port 53', filt(['dst', 'port', '53'], [7]))
res('filtre tcp and port 80', filt(['tcp', 'and', 'port', '80'], [4, 5, 6]))
res('filtre tcp dst port 80', filt(['tcp', 'dst', 'port', '80'], [4, 6]))
res('filtre host 10.0.2.3', filt(['host', '10.0.2.3'], [7, 8]))
res('filtre src host 93.184.216.34', filt(['src', 'host', '93.184.216.34'],
                                          [5]))
res('filtre net 93.184.0.0/16', filt(['net', '93.184.0.0/16'], [4, 5, 6]))
res('filtre udp or arp', filt(['udp', 'or', 'arp'], [0, 1, 7, 8, 9, 10]))
res('filtre not udp and ip', filt(['not', 'udp', 'and', 'ip'],
                                  [2, 3, 4, 5, 6, 12]))
res('filtre (arp or icmp) and host 10.0.2.2',
    filt(['(arp or icmp) and host 10.0.2.2'], [0, 1, 2, 3, 12]))
res('filtre ip6', filt(['ip6'], [11]))
res('filtre less 60', filt(['less', '60'], [i for i, p in enumerate(pk)
                                         if len(p) <= 60]))
res('filtre broadcast', filt(['broadcast'], [0, 10]))
res('-c 2', len(run(['-n', '-c', '2', '-r', pcap]).stdout.splitlines()) == 2)
r = run(['-n', '-e', '-c', '1', '-r', pcap])
res('-e : adresses MAC', '52:54:00:12:34:56 > ff:ff:ff:ff:ff:ff, ethertype '
    'ARP (0x0806), length 42: ARP, Request' in r.stdout, r.stdout)
r = run(['-n', '-x', '-c', '1', '-r', pcap])
res('-x : dump hexa', '\t0x0000:  0001 0800 0604 0001 5254 0012 3456 0a00 ' in
    r.stdout.replace('0x0000:  0001', '0x0000:  0001'), r.stdout)
r = run(['-n', '-q', '-r', pcap, 'tcp'])
res('-q', 'IP 10.0.2.15.43210 > 93.184.216.34.80: tcp 100' in r.stdout and
    'IP 93.184.216.34.80 > 10.0.2.15.43210: tcp 0' in r.stdout, r.stdout)
r = run(['-r', pcap, 'port', '53'])
res('noms de service sans -n', '.domain' in r.stdout, r.stdout)
r = run(['-n', '-r', pcap, 'foo', 'bar'])
res('expression invalide : code 1', r.returncode == 1 and
    'tcpdump: expression' in r.stderr)
r = run(['-r', os.path.join(W, 'absent.pcap')])
res('fichier absent : code 1', r.returncode == 1)
open(os.path.join(W, 'bad.pcap'), 'wb').write(b'x' * 100)
res('pas un pcap : code 1', run(['-r', os.path.join(W, 'bad.pcap')])
    .returncode == 1)

# ecriture : -r | -w, relire
r = run(['-n', '-r', pcap, '-w', os.path.join(W, 'b.pcap'), 'tcp'])
a = open(pcap, 'rb').read()
b = open(os.path.join(W, 'b.pcap'), 'rb').read()

def records(d):
    o = 24
    out = []
    while o + 16 <= len(d):
        sec, us, cl, ln = struct.unpack('<IIII', d[o:o + 16])
        out.append((sec, us, d[o + 16:o + 16 + cl]))
        o += 16 + cl
    return out


rb = records(b)
res('-w : en-tete pcap (magic, version, ethernet)',
    b[:4] == a[:4] and b[4:8] == a[4:8] and b[20:24] == a[20:24])
res('-w : 3 paquets TCP identiques avec leurs dates',
    rb == [(t0 + i, 123456, pk[i]) for i in (4, 5, 6)], len(rb))
r = run(['-n', '-r', os.path.join(W, 'b.pcap')])
res('-r relit le fichier ecrit par -w', len(r.stdout.splitlines()) == 3 and
    'Flags [P.]' in r.stdout, r.stdout)

# capture reelle sur lo
try:
    s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(3))
    s.close()
    live = True
except OSError:
    live = False
if live:
    wf = os.path.join(W, 'live.pcap')
    p = subprocess.Popen([TD, '-i', 'lo', '-c', '3', '-w', wf, '-n', 'udp',
                          'and', 'port', '45678'], stderr=subprocess.PIPE,
                         env=ENV, cwd=W)
    time.sleep(0.5)
    u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    for i in range(3):
        u.sendto(b'ping%d' % i, ('127.0.0.1', 45678))
        time.sleep(0.05)
    try:
        p.wait(timeout=10)
    except subprocess.TimeoutExpired:
        p.kill()
    err = p.stderr.read().decode()
    d = open(wf, 'rb').read() if os.path.exists(wf) else b''
    n = 0
    o = 24
    pays = []
    while o + 16 <= len(d):
        sec, us, cl, ln = struct.unpack('<IIII', d[o:o + 16])
        fr = d[o + 16:o + 16 + cl]
        o += 16 + cl
        n += 1
        pays.append(fr[-5:])
    res('capture lo -w : 3 paquets UDP', n == 3 and pays == [b'ping0',
        b'ping1', b'ping2'], '%d %s %s' % (n, pays, err))
    res('capture lo : resume sur stderr', '3 packets captured' in err, err)
    p = subprocess.Popen([TD, '-i', 'lo', '-c', '1', '-n', 'udp'],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         env=ENV, cwd=W)
    time.sleep(0.5)
    u.sendto(b'zzz', ('127.0.0.1', 45679))
    out = p.communicate(timeout=10)[0].decode()
    res('capture lo texte', 'IP 127.0.0.1.' in out and '.45679: UDP, length 3'
        in out, out)
    p = subprocess.Popen([TD, '-i', 'nonexistent0'], stderr=subprocess.PIPE,
                         env=ENV, cwd=W)
    p.wait(timeout=10)
    res('interface inconnue : code 1', p.returncode == 1)
else:
    print('(AF_PACKET indisponible sur cet hote : captures reelles omises)')

print('TCPDUMP-FIN ok=%d ko=%d' % (ok, ko))
sys.exit(1 if ko else 0)
