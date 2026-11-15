#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Audit de couverture de KERNEL32 par rapport au noyau Linux
#   i386 : genere KERNEL32/TOOLS/COUVERTURE.TXT. Table des appels systeme de
#   /usr/include/asm/unistd_32.h (implemente / stub / absent + test qui les
#   couvre), puis familles d'ioctl, systemes de fichiers, pilotes, entrees
#   /proc et /sys, familles de sockets, drapeaux mmap/clone/open.
#   Usage : python3 TOOLS/COUVERTURE.PY [sortie]
import re, sys, os, glob
HERE = os.path.dirname(os.path.abspath(__file__))
K32 = os.path.dirname(HERE)
src = open(os.path.join(K32, 'KERNEL32.PAS'), encoding='latin-1').read()
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'COUVERTURE.TXT')
hdr = '/usr/include/asm/unistd_32.h'
if not os.path.exists(hdr):
    hdr = '/usr/include/x86_64-linux-gnu/asm/unistd_32.h'
calls = {}
for l in open(hdr):
    m = re.match(r'#define __NR_(\w+)\s+(\d+)', l)
    if m:
        calls[int(m.group(2))] = m.group(1)
# enregistrements SysReg (normalises)
flat = re.sub(r'\s+', ' ', src)
reg = {}
for m in re.finditer(r'SysReg\((\d+), LongInt\(@(\w+)\), (\d+)\)', flat):
    reg[int(m.group(1))] = m.group(2)
# liste des ENOSYS explicites (partie 28)
enosys = set()
m = re.search(r"EnosysList = (.*?);", flat)
if m:
    for n in re.findall(r"\d+", m.group(1).replace("' + '", "")):
        enosys.add(int(n))
# corps des fonctions pour reconnaitre les stubs
def body(name):
    m = re.search(r'\nFunction ' + name + r'\b[^\n]*\n(.*?)\nEnd;', src, re.S | re.I)
    return m.group(1) if m else ''
def classify(name):
    if name in ('SysZero3', 'SysEperm', 'SysEnosys'):
        return 'stub'
    b = body(name)
    core = re.sub(r'\s+', ' ', b.split('Begin', 1)[-1]).strip()
    if re.fullmatch(r'\w+ := (0|-E\w+);', core, re.I):
        return 'stub'
    return 'reel'
tests = {}
for f in glob.glob(os.path.join(K32, 'TESTS', 'K', '*.[ch]')):
    t = open(f, encoding='latin-1').read()
    tn = os.path.basename(f)
    for nr, nm in calls.items():
        if re.search(r'\bSYS_' + nm + r'\b', t) or re.search(r'\bsc\d\(\s*%d\s*,' % nr, t) \
           or re.search(r'\bku_sc6\(\s*%d\b' % nr, t):
            tests.setdefault(nr, set()).add(tn)
lines = []
P = lines.append
P('COUVERTURE DE KERNEL32 PAR RAPPORT A LINUX i386')
P('genere par TOOLS/COUVERTURE.PY (ne pas editer a la main)')
P('=' * 72)
P('')
P('A. APPELS SYSTEME (%s)' % hdr)
P('   reel = fonction implementee ; stub = renvoie une constante sans agir ;')
P('   enosys = refus explicite et documente (-ENOSYS) ; absent = non enregistre')
P('   (ENOSYS implicite). Test : programme de TESTS/K qui l\'appelle.')
P('')
P('%4s  %-22s %-8s %s' % ('nr', 'nom', 'etat', 'test'))
cnt = {'reel': 0, 'stub': 0, 'enosys': 0, 'absent': 0}
for nr in sorted(calls):
    nm = calls[nr]
    if nr in reg:
        st = classify(reg[nr])
    elif nr in enosys:
        st = 'enosys'
    else:
        st = 'absent'
    cnt[st] += 1
    P('%4d  %-22s %-8s %s' % (nr, nm, st, ','.join(sorted(tests.get(nr, [])))))
tot = len(calls)
P('')
P('Total : %d appels ; reels %d (%.1f %%), stubs %d, ENOSYS explicites %d, absents %d' % (
    tot, cnt['reel'], 100.0 * cnt['reel'] / tot, cnt['stub'], cnt['enosys'], cnt['absent']))
def has(rx):
    return re.search(rx, src, re.I) is not None
def section(title, items):
    P('')
    P(title)
    n = 0
    for nm, rx, note in items:
        ok = has(rx)
        n += ok
        P('   %-34s %-8s %s' % (nm, 'present' if ok else 'absent', note))
    P('   -> %d / %d' % (n, len(items)))
    return n, len(items)
S = []
S.append(section('B1. FAMILLES D\'IOCTL', [
    ('TCGETS/TCSETS (termios)', r'\$5401', ''), ('TIOCGWINSZ/TIOCSWINSZ', r'\$5413', ''),
    ('TIOCGPGRP/TIOCSPGRP', r'\$540F', ''), ('TIOCSCTTY', r'\$540E', ''),
    ('TIOCSTI', r'\$5412', 'injection de caractere'), ('TIOCGPTN/TIOCSPTLCK (pty)', r'\$80045430', ''),
    ('FIONREAD', r'\$541B', ''), ('FIONBIO/FIOCLEX', r'\$5451|\$5421', ''),
    ('VT_* / KD_* (consoles virtuelles)', r'VT_ACTIVATE|\$5606', ''),
    ('KDSETMODE/KDGKBMODE', r'\$4B3A|\$4B44', ''),
    ('BLKGETSIZE/BLKGETSIZE64/BLKFLSBUF', r'\$80081272|BLKGETSIZE', ''),
    ('HDIO_GETGEO', r'\$0301|HDIO', ''), ('FBIOGET_*SCREENINFO', r'\$4600', ''),
    ('SIOCGIFADDR/SIOCSIFADDR (reseau)', r'\$8915', ''), ('SIOCGIFCONF/SIOCGIFHWADDR', r'\$8912|\$8927', ''),
    ('RTC_RD_TIME/RTC_SET_TIME', r'\$80247009', ''), ('LOOP_SET_FD (loop)', r'\$4C00|LOOP_SET', ''),
    ('EVIOCG* (evdev)', r'EVIOC', ''), ('TUNSETIFF (tun/tap)', r'TUNSETIFF', ''),
    ('SNDCTL_* (son)', r'SNDCTL', ''), ('CDROM* / SG_IO (SCSI)', r'CDROMEJECT|SG_IO', ''),
    ('FS_IOC_GETFLAGS (chattr)', r'FS_IOC|\$80046601', ''), ('FIFREEZE/FITRIM', r'FIFREEZE|FITRIM', ''),
]))
S.append(section('B2. SYSTEMES DE FICHIERS', [
    ('ext2', r"RegisterFs\('ext2'", ''), ('ext3 (journal rejoue)', r'jbd|Journal.*Replay|JbdReplay', 'monte comme ext2 sinon'),
    ('ext4 (extents)', r'ExtentTree|ExExtent', ''), ('tmpfs/ramfs', r"RegisterFs\('tmpfs'", ''),
    ('devtmpfs', r"RegisterFs\('devtmpfs'", ''), ('proc', r"RegisterFs\('proc'", ''),
    ('sysfs', r"RegisterFs\('sysfs'", ''), ('devpts', r"RegisterFs\('devpts'", ''),
    ('iso9660', r"RegisterFs\('iso9660'", ''), ('vfat/msdos', r"RegisterFs\('vfat'", ''),
    ('minix', r"RegisterFs\('minix'", ''), ('squashfs', r"RegisterFs\('squashfs'", ''),
    ('cramfs', r"RegisterFs\('cramfs'", ''), ('romfs', r"RegisterFs\('romfs'", ''),
    ('overlayfs', r"RegisterFs\('overlay'", ''), ('initramfs (cpio newc)', r'newc|070701', ''),
    ('loop (/dev/loopN)', r'MajLoop', ''), ('9p / nfs', r"RegisterFs\('(9p|nfs)'", 'hors perimetre'),
    ('cgroup', r"RegisterFs\('cgroup", ''), ('debugfs/tracefs', r"RegisterFs\('(debugfs|tracefs)", 'ENOSYS honnete'),
]))
S.append(section('B3. PILOTES ET PERIPHERIQUES', [
    ('IDE/ATA PIO (hda..hdd)', r'Function IdeReadSectors', ''), ('ATAPI CD-ROM', r'Function AtapiCmd', ''),
    ('disquette FDC', r'Function FlpSector', ''), ('ramdisk', r'Procedure RamInit', ''),
    ('clavier PS/2 + keymaps', r'Procedure KbdIrq', ''), ('souris PS/2', r'Procedure MouseIrq', ''),
    ('port serie 16550 (COM1)', r'Procedure SerialIrq', ''), ('4 ports serie', r'\$2F8|\$3E8', ''),
    ('port parallele', r'\$378', ''), ('console VGA texte + VT', r'NVc', ''),
    ('framebuffer Bochs', r'Procedure FbInit', ''), ('RTL8139', r'Procedure NicInit', ''),
    ('virtio-net/blk/rng/console', r'virtio', ''), ('AHCI/SATA', r'AHCI', ''), ('NVMe', r'NVMe', ''),
    ('USB UHCI/EHCI', r'UHCI|EHCI', ''), ('E1000 / NE2000 / PCnet', r'E1000|NE2000|PCnet', ''),
    ('son SB16/AC97', r'SB16|AC97', ''), ('evdev /dev/input/event*', r'event0', ''),
    ('SMP (APIC/IOAPIC/AP)', r'LAPIC|IOAPIC', ''), ('ACPI (arret, MADT)', r'ACPI|MADT', ''),
    ('HPET', r'HPET', ''), ('PCI (config + /proc/bus/pci)', r'Function PciRead', ''),
    ('/dev/null zero full random urandom', r"MkDev\(1, 9\)", ''), ('/dev/mem kmem port kmsg', r"/dev/kmsg", ''),
    ('/dev/rtc', r'/dev/rtc', ''), ('/dev/tty* /dev/ptmx pts', r'/dev/ptmx', ''),
    ('modules du noyau (.ko ET_REL, insmod/rmmod)', r'Function ModLoadImage', 'partie 36'),
    ('swap sur fichier ordinaire', r'Function SwapBmap', 'partie 36'),
]))
S.append(section('B4. /PROC ET /SYS', [
    ('/proc/meminfo uptime version cmdline', r"'meminfo'", ''), ('/proc/cpuinfo stat loadavg', r"'cpuinfo'", ''),
    ('/proc/mounts filesystems', r"'filesystems'", ''), ('/proc/PID/stat status cmdline maps', r"'maps'", ''),
    ('/proc/PID/fd fdinfo exe cwd root environ', r"'environ'", ''), ('/proc/PID/smaps statm limits io', r"'smaps'", ''),
    ('/proc/PID/mountinfo wchan task/', r"'mountinfo'", ''), ('/proc/net/dev route', r"'route'", ''),
    ('/proc/net/tcp udp arp', r"'/proc/net/tcp'|net/tcp", ''), ('/proc/devices partitions interrupts', r"'partitions'", ''),
    ('/proc/iomem ioports locks', r"'iomem'", ''), ('/proc/swaps', r"PrSwaps", 'partie 36'),
    ('/proc/modules kallsyms', r"'kallsyms'", 'partie 36'),
    ('/proc/sys (sysctl ecriture)', r"SyAddStr\('kernel/hostname", 'partie 36'), ('/sys/block class kernel', r"/sys/block", ''),
    ('/sys/bus /sys/devices PCI', r"/sys/bus", ''), ('/sys/fs/cgroup', r"/sys/fs/cgroup", ''),
]))
S.append(section('B5. FAMILLES DE SOCKETS', [
    ('AF_UNIX stream/dgram/socketpair', r'AF_UNIX', ''), ('AF_INET TCP/UDP', r'AF_INET', ''),
    ('AF_INET raw / ICMP', r'IPPROTO_ICMP', ''), ('AF_INET6', r'AF_INET6', ''),
    ('AF_PACKET', r'AF_PACKET', ''), ('AF_NETLINK', r'AF_NETLINK', ''),
    ('SCM_RIGHTS / SCM_CREDENTIALS', r'SCM_RIGHTS', ''), ('multicast UDP', r'IP_ADD_MEMBERSHIP', ''),
    ('netfilter', r'iptables|NF_', ''), ('TCP SACK / window scale', r'SACK', ''),
]))
S.append(section('B6. DRAPEAUX mmap / clone / open', [
    ('MAP_SHARED/PRIVATE/FIXED/ANONYMOUS', r'MAP_ANONYMOUS', ''), ('MAP_GROWSDOWN', r'MAP_GROWSDOWN', ''),
    ('MAP_POPULATE/MAP_LOCKED/MAP_HUGETLB', r'MAP_POPULATE|MAP_HUGETLB', ''), ('MAP_NORESERVE', r'MAP_NORESERVE', ''),
    ('CLONE_VM/FS/FILES/SIGHAND', r'CLONE_VM', ''), ('CLONE_THREAD', r'CLONE_THREAD', ''),
    ('CLONE_SETTLS / PARENT_SETTID / CHILD_CLEARTID', r'CLONE_SETTLS|CLONE_CHILD_CLEARTID', ''),
    ('CLONE_NEWNS/NEWPID/NEWUTS/NEWIPC/NEWNET', r'CLONE_NEWNS|CLONE_NEWPID', ''),
    ('O_CREAT/EXCL/TRUNC/APPEND/NONBLOCK/DIRECTORY', r'O_DIRECTORY', ''), ('O_CLOEXEC / O_NOFOLLOW', r'O_CLOEXEC', ''),
    ('O_SYNC/O_DSYNC/O_DIRECT/O_TMPFILE/O_PATH', r'O_TMPFILE|O_PATH', ''), ('O_LARGEFILE / fichiers > 2 Go (64 bits)', r'Function VfsLlseek', 'partie 35'),
]))
P('')
P('C. SYNTHESE')
P('   appels reels : %d / %d (%.1f %%) ; stubs %d ; ENOSYS explicites %d ; absents %d' % (cnt['reel'], tot, 100.0 * cnt['reel'] / tot, cnt['stub'], cnt['enosys'], cnt['absent']))
a = sum(x[0] for x in S); b = sum(x[1] for x in S)
P('   familles B1-B6 presentes : %d / %d (%.1f %%)' % (a, b, 100.0 * a / b))
open(out, 'w', encoding='ascii', errors='replace').write('\n'.join(lines) + '\n')
print('%s : %d reels / %d appels (%.1f %%), stubs %d, enosys %d, absents %d ; B %d/%d' % (
    os.path.basename(out), cnt['reel'], tot, 100.0 * cnt['reel'] / tot, cnt['stub'], cnt['enosys'], cnt['absent'], a, b))
