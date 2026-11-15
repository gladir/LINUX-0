#!/usr/bin/env python3
# MKROFS.PY : fabrique des images minix (v1/v2/v3, noms de 14 ou 30 octets) et
# romfs a partir d'un repertoire (essai des systemes de fichiers de la partie 38).
#   MKROFS.PY minix1|minix1l|minix2|minix2l|minix3 SRC IMAGE [taille_bloc]
#   MKROFS.PY romfs SRC IMAGE
import os, sys, struct, stat

kind, src, out = sys.argv[1:4]

def walk(root):
    """liste (chemin relatif, stat, contenu) en profondeur d'abord, '' = racine"""
    ents = []
    def rec(rel, ab):
        st = os.lstat(ab)
        ents.append((rel, st, ab))
        if stat.S_ISDIR(st.st_mode):
            for n in sorted(os.listdir(ab)):
                rec(rel + '/' + n if rel else n, os.path.join(ab, n))
    rec('', root)
    return ents

def content(st, ab):
    if stat.S_ISLNK(st.st_mode): return os.readlink(ab).encode()
    if stat.S_ISREG(st.st_mode): return open(ab, 'rb').read()
    return b''

def romfs():
    ents = walk(src)
    name = b'LINUX0'
    def pad16(n): return (n + 15) & ~15
    # disposition : superbloc (16 + nom arrondi), puis pour chaque repertoire
    # ses entrees ('.', '..', fichiers) ; on construit recursivement
    buf = bytearray()
    hdr0 = pad16(16 + len(name) + 1)
    buf += b'-rom1fs-' + struct.pack('>II', 0, 0) + name + b'\0'
    while len(buf) < hdr0: buf.append(0)
    def typ(st):
        m = st.st_mode
        t = 1 if stat.S_ISDIR(m) else 3 if stat.S_ISLNK(m) else 2
        if t == 2 and (m & 0o111): t |= 8
        return t
    def emit(nm, st, ab, dirinfo, nextoff_placeholder=True):
        """ecrit un en-tete + donnees ; retourne (offset_entete, position du champ next)"""
        off = len(buf)
        n = nm.encode() + b'\0'
        data = content(st, ab) if not stat.S_ISDIR(st.st_mode) else b''
        buf.extend(struct.pack('>IIII', typ(st), dirinfo, len(data), 0))
        buf.extend(n)
        while (len(buf) - off) % 16: buf.append(0)
        buf.extend(data)
        while len(buf) % 16: buf.append(0)
        return off
    def setnext(off, nxt):
        t = struct.unpack('>I', buf[off:off+4])[0]
        buf[off:off+4] = struct.pack('>I', (nxt & ~15) | (t & 15))
    def build_dir(nm, st, ab, parent_off, self_ref):
        # en-tete du repertoire lui-meme : spec = offset de son premier fichier (a remplir)
        off = emit(nm, st, ab, 0)
        return off
    # racine : en-tete '.' special
    def dir_entries(path_ab):
        return sorted(os.listdir(path_ab))
    def make(nm, st, ab, parent_off):
        """cree l'en-tete du repertoire 'nm' puis ses enfants ; retourne offset"""
        off = emit(nm, st, ab, 0)
        # premiers enfants : '.' (lien dur vers off) et '..' (lien dur vers parent)
        kids = []
        # '.' et '..' : en-tetes de type 0 (lien dur), spec = cible
        def hard(nmx, target):
            o = len(buf)
            n = nmx.encode() + b'\0'
            buf.extend(struct.pack('>IIII', 0, target, 0, 0)); buf.extend(n)
            while (len(buf) - o) % 16: buf.append(0)
            return o
        kids.append(hard('.', off))
        kids.append(hard('..', parent_off if parent_off is not None else off))
        for n in dir_entries(ab):
            p = os.path.join(ab, n); s2 = os.lstat(p)
            if stat.S_ISDIR(s2.st_mode):
                kids.append(make(n, s2, p, off))
            else:
                kids.append(emit(n, s2, p, 0))
        # chainage
        for a, b in zip(kids, kids[1:]): setnext(a, b)
        t = struct.unpack('>I', buf[off:off+4])[0]
        buf[off+4:off+8] = struct.pack('>I', kids[0])
        return off
    root = make('.', os.lstat(src), src, None)
    assert root == hdr0, (root, hdr0)
    while len(buf) % 1024: buf.append(0)
    buf[8:12] = struct.pack('>I', len(buf))
    # somme de controle : somme des mots (premiers 512 octets) = 0
    buf[12:16] = b'\0\0\0\0'
    s = sum(struct.unpack('>128I', buf[:512])) & 0xffffffff
    buf[12:16] = struct.pack('>I', (-s) & 0xffffffff)
    open(out, 'wb').write(buf)

def minix():
    ver = 3 if kind == 'minix3' else (1 if kind.startswith('minix1') else 2)
    namelen = 60 if ver == 3 else (30 if kind.endswith('l') else 14)
    bs = int(sys.argv[4]) if len(sys.argv) > 4 else 1024
    zsz = 2 if ver == 1 else 4
    isz = 32 if ver == 1 else 64
    ents = walk(src)
    n_inodes = len(ents) + 8
    ppb = bs // zsz
    # zones necessaires
    def nzones_file(sz):
        nb = (sz + bs - 1) // bs
        z = nb
        if nb > 7:
            z += 1
            rest = nb - 7
            if rest > ppb:
                rest2 = rest - ppb
                z += 1 + (rest2 + ppb - 1) // ppb
        return z
    data_zones = 0
    for rel, st, ab in ents:
        if stat.S_ISDIR(st.st_mode):
            sz = (2 + len([1 for _ in os.listdir(ab)])) * (namelen + (4 if ver == 3 else 2))
        else:
            sz = len(content(st, ab))
        data_zones += nzones_file(sz)
    imap = (n_inodes + 1 + bs * 8 - 1) // (bs * 8)
    itab = (n_inodes * isz + bs - 1) // bs
    first = 2 + imap + 1 + itab          # zmap provisoire : recalcule ci-dessous
    nzones = first + data_zones + 8
    zmap = (nzones - first + 1 + bs * 8 - 1) // (bs * 8)
    first = 2 + imap + zmap + itab
    nzones = first + data_zones + 8
    img = bytearray(nzones * bs)
    inodes = {}
    zused = [0]            # prochaine zone libre = first + zused
    def zalloc():
        z = first + zused[0]; zused[0] += 1; return z
    def wr_zone(z, data):
        img[z * bs:z * bs + len(data)] = data
    def put_ptr(zblock, idx, val):
        if zsz == 2: struct.pack_into('<H', img, zblock * bs + idx * 2, val)
        else: struct.pack_into('<I', img, zblock * bs + idx * 4, val)
    def store(data):
        """ecrit data dans des zones ; retourne la liste des 10 (ou 9) zones de l'inode"""
        nb = (len(data) + bs - 1) // bs
        zones = []
        for i in range(nb):
            z = zalloc()
            wr_zone(z, data[i * bs:(i + 1) * bs])
            zones.append(z)
        direct = zones[:7]; rest = zones[7:]
        ind = dind = tind = 0
        if rest:
            ind = zalloc()
            for i, z in enumerate(rest[:ppb]): put_ptr(ind, i, z)
            rest2 = rest[ppb:]
            if rest2:
                dind = zalloc()
                for k in range(0, len(rest2), ppb):
                    b = zalloc(); put_ptr(dind, k // ppb, b)
                    for i, z in enumerate(rest2[k:k + ppb]): put_ptr(b, i, z)
        zl = direct + [0] * (7 - len(direct)) + [ind, dind] + ([tind] if ver > 1 else [])
        return zl
    ino_of = {}
    for i, (rel, st, ab) in enumerate(ents): ino_of[rel] = i + 1
    def dirdata(rel, ab, parent_rel):
        es = namelen + (4 if ver == 3 else 2)
        d = bytearray()
        def ent(n, i):
            e = struct.pack('<I' if ver == 3 else '<H', i) + n.encode()[:namelen]
            e += b'\0' * (es - len(e)); return e
        d += ent('.', ino_of[rel]); d += ent('..', ino_of[parent_rel])
        for n in sorted(os.listdir(ab)):
            d += ent(n, ino_of[rel + '/' + n if rel else n])
        return bytes(d)
    for rel, st, ab in ents:
        parent = rel.rsplit('/', 1)[0] if '/' in rel else ''
        if stat.S_ISDIR(st.st_mode):
            data = dirdata(rel, ab, parent if rel else '')
        else: data = content(st, ab)
        zl = store(data)
        mode = st.st_mode & 0xFFFF
        nl = 2 + len([1 for n in os.listdir(ab) if os.path.isdir(os.path.join(ab, n)) and not os.path.islink(os.path.join(ab, n))]) if stat.S_ISDIR(st.st_mode) else 1
        off = 2 * bs + (imap + zmap) * bs + (ino_of[rel] - 1) * isz
        if ver == 1:
            struct.pack_into('<HHIIBB9H', img, off, mode, st.st_uid, len(data), int(st.st_mtime), st.st_gid, nl, *zl)
        else:
            struct.pack_into('<HHHHIIII10I', img, off, mode, nl, st.st_uid, st.st_gid, len(data),
                             int(st.st_atime), int(st.st_mtime), int(st.st_ctime), *zl)
    # bitmaps : bit 0 reserve
    def setbit(base_blk, nbits_used):
        for b in range(nbits_used):
            img[base_blk * bs + b // 8] |= 1 << (b % 8)
    setbit(2, len(ents) + 1)
    # zones : bit i = zone first-1+i ; le bit 0 est reserve
    setbit(2 + imap, zused[0] + 1)
    # padding de la bitmap : bits au-dela des zones valides a 1
    nz_valid = nzones - first + 1
    for b in range(nz_valid, zmap * bs * 8): img[(2 + imap) * bs + b // 8] |= 1 << (b % 8)
    for b in range(n_inodes + 1, imap * bs * 8): img[2 * bs + b // 8] |= 1 << (b % 8)
    maxsize = 7 * bs + ppb * bs + ppb * ppb * bs
    if ver == 3:
        struct.pack_into('<IHHHHHHIIHHHB', img, bs, n_inodes, 0, imap, zmap, first, 0, 0, maxsize, nzones, 0x4D5A, 0, bs, 3)
    else:
        magic = {(1, 14): 0x137F, (1, 30): 0x138F, (2, 14): 0x2468, (2, 30): 0x2478}[(ver, namelen)]
        struct.pack_into('<HHHHHHIHHI', img, bs, n_inodes, min(nzones, 65535), imap, zmap, first, 0, maxsize, magic, 1, nzones)
    open(out, 'wb').write(img)

if kind == 'romfs': romfs()
else: minix()
