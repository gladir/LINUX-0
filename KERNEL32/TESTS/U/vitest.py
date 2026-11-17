#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: essais de USR/VI.PAS sur un pty (hote) : touches envoyees,
#   fichier compare. Usage : vitest.py chemin/du/vi
import os, pty, sys, time, select, struct, fcntl, termios, tempfile, subprocess
VI = sys.argv[1]   # programme vi compile (lpc -3X USR/VI.PAS)

def run(initial, keys, timeout=6):
    d = tempfile.mkdtemp(prefix='vitest')
    f = os.path.join(d, 'f.txt')
    if initial is not None:
        open(f, 'w').write(initial)
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(d)
        os.execv(VI, [VI, 'f.txt'])
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
    time.sleep(0.15)
    out = b''
    for k in keys:
        os.write(fd, k.encode('latin-1') if isinstance(k, str) else k)
        time.sleep(0.01)
        while select.select([fd], [], [], 0)[0]:
            try: out += os.read(fd, 65536)
            except OSError: break
    t0 = time.time()
    status = None
    while time.time() - t0 < timeout:
        try:
            r = select.select([fd], [], [], 0.2)[0]
            if r:
                try:
                    data = os.read(fd, 65536)
                    if not data: break
                    out += data
                except OSError: break
        except Exception: break
        p, st = os.waitpid(pid, os.WNOHANG)
        if p:
            status = st; break
    else:
        os.kill(pid, 9); os.waitpid(pid, 0); status = 'TIMEOUT'
    if status is None:
        try:
            p, st = os.waitpid(pid, 0); status = st
        except Exception: status = 0
    res = open(f).read() if os.path.exists(f) else None
    return res, status, out

fails = 0
def t(name, initial, keys, expect):
    global fails
    res, st, out = run(initial, keys)
    if res != expect or st not in (0,):
        fails += 1
        print('FAIL', name, 'status', st)
        print('  got   ', repr(res)[:150])
        print('  expect', repr(expect)[:150])
    else:
        pass

E = '\x1b'
W = ':wq\r'
cases = [
 ('insert', 'abc\n', ['ihello ', E, W], 'hello abc\n'),
 ('append', 'abc\n', ['Aend', E, W], 'abcend\n'),
 ('open below', 'a\nb\n', ['ox', E, W], 'a\nx\nb\n'),
 ('open above', 'a\nb\n', ['jOx', E, W], 'a\nx\nb\n'),
 ('x', 'abcdef\n', ['3x', W], 'def\n'),
 ('dd', 'a\nb\nc\n', ['jdd', W], 'a\nc\n'),
 ('2dd', 'a\nb\nc\nd\n', ['2dd', W], 'c\nd\n'),
 ('dw', 'foo bar baz\n', ['dw', W], 'bar baz\n'),
 ('d2w', 'foo bar baz qux\n', ['d2w', W], 'baz qux\n'),
 ('de', 'foo bar\n', ['de', W], ' bar\n'),
 ('d$', 'foo bar\n', ['wd$', W], 'foo \n'),
 ('D', 'foo bar\n', ['wD', W], 'foo \n'),
 ('d0', 'foo bar\n', ['wd0', W], 'bar\n'),
 ('cw', 'foo bar\n', ['cwxx', E, W], 'xx bar\n'),
 ('cc', 'foo\nbar\n', ['ccnew', E, W], 'new\nbar\n'),
 ('C', 'foo bar\n', ['wCz', E, W], 'foo z\n'),
 ('yyp', 'a\nb\n', ['yyp', W], 'a\na\nb\n'),
 ('yyP', 'a\nb\n', ['jyyP', W], 'a\nb\nb\n'),
 ('3yyp', 'a\nb\nc\n', ['3yyGp', W], 'a\nb\nc\na\nb\nc\n'),
 ('ywP', 'foo bar\n', ['ywwP', W], 'foo foo bar\n'),
 ('xp', 'ab\n', ['xp', W], 'ba\n'),
 ('ddp', 'a\nb\nc\n', ['ddp', W], 'b\na\nc\n'),
 ('u', 'abc\n', ['xxu', W], 'bc\n'),
 ('u redo', 'abc\n', ['xuu', W], 'bc\n'),
 ('dot', 'a b c d\n', ['dw..', W], 'd\n'),
 ('dot ins', 'a\n', ['ix', E, 'j.', W], 'xxa\n'),
 ('J', 'a\nb\nc\n', ['J', W], 'a b\nc\n'),
 ('3J', 'a\nb\nc\nd\n', ['3J', W], 'a b c\nd\n'),
 ('r', 'abc\n', ['rx', W], 'xbc\n'),
 ('3r', 'abcd\n', ['3rx', W], 'xxxd\n'),
 ('R', 'abcd\n', ['Rxy', E, W], 'xycd\n'),
 ('~', 'abc\n', ['3~', W], 'ABC\n'),
 ('search', 'a\nfoo\nb\nfoo x\n', ['/foo\rx', W], 'a\noo\nb\nfoo x\n'),
 ('search n', 'a\nfoo\nb\nfoo x\n', ['/foo\rnx', W], 'a\nfoo\nb\noo x\n'),
 ('search back', 'foo\nb\nfoo x\n', ['G?foo\rx', W], 'oo\nb\nfoo x\n'),
 ('d/', 'one two three\n', ['d/thr\r', W], 'three\n'),
 ('s', 'foo foo\nfoo\n', [':s/foo/bar/\r', W], 'bar foo\nfoo\n'),
 ('s g', 'foo foo\nfoo\n', [':s/foo/bar/g\r', W], 'bar bar\nfoo\n'),
 ('%s', 'foo foo\nfoo\n', [':%s/foo/bar/g\r', W], 'bar bar\nbar\n'),
 ('s grp', 'ab cd\n', [':s/\\(a\\)b \\(c\\)/\\2-\\1/\r', W], 'c-ad\n'),
 ('s &', 'ab\n', [':s/b/[&]/\r', W], 'a[b]\n'),
 (':d', 'a\nb\nc\n', [':2d\r', W], 'a\nc\n'),
 (':1,2d', 'a\nb\nc\n', [':1,2d\r', W], 'c\n'),
 (':g d', 'a\nxb\nc\nxd\n', [':g/x/d\r', W], 'a\nc\n'),
 (':v d', 'a\nxb\nc\nxd\n', [':v/x/d\r', W], 'xb\nxd\n'),
 (':m', 'a\nb\nc\n', [':1m$\r', W], 'b\nc\na\n'),
 (':t', 'a\nb\n', [':1t.\r', W], 'a\na\nb\n'),
 (':N goto', 'a\nb\nc\n', [':3\rx', W], 'a\nb\n\n'),
 ('G', 'a\nb\nc\n', ['Gx', W], 'a\nb\n\n'),
 ('gg', 'a\nb\nc\n', ['Gggx', W], '\nb\nc\n'),
 ('f', 'a,b,c\n', ['f,x', W], 'ab,c\n'),
 ('t', 'a,b,c\n', ['t,x', W], ',b,c\n'),
 ('; repeat', 'a,b,c\n', ['f,;x', W], 'a,bc\n'),
 ('$', 'abc\n', ['$x', W], 'ab\n'),
 ('0', 'abc\n', ['$0x', W], 'bc\n'),
 ('^', '  abc\n', ['$^x', W], '  bc\n'),
 ('w move', 'foo bar\n', ['wx', W], 'foo ar\n'),
 ('b move', 'foo bar\n', ['$bx', W], 'foo ar\n'),
 ('e move', 'foo bar\n', ['ex', W], 'fo bar\n'),
 ('%', '(a(b)c)\n', ['%x', W], '(a(b)c\n'),
 ('>>', 'a\n', ['>>', W], '\ta\n'),
 ('<<', '\ta\n', ['<<', W], 'a\n'),
 ('o ai', '  a\n', [':set ai\r', 'ob', E, W], '  a\n  b\n'),
 ('3ix', '\n', ['3ix', E, W], 'xxx\n'),
 ('3o', 'a\n', ['3ox', E, W], 'a\nx\nx\nx\n'),
 ('S', 'abc\n', ['Sx', E, W], 'x\n'),
 ('s', 'abc\n', ['sx', E, W], 'xbc\n'),
 ('X', 'abc\n', ['$X', W], 'ac\n'),
 ('p chars', 'abc\n', ['xp', W], 'bac\n'),
 ('dG', 'a\nb\nc\n', ['jdG', W], 'a\n'),
 ('dgg', 'a\nb\nc\n', ['jdgg', W], 'c\n'),
 ('mark', 'a\nb\nc\n', ['majjd\'a', W], ''),
 ('y} ', 'a\nb\n\nc\n', ['y}Gp', W], 'a\nb\n\nca\nb\n'),
 ('iw', 'foo bar\n', ['wdiw', W], 'foo \n'),
 ('daw', 'foo bar baz\n', ['wdaw', W], 'foo baz\n'),
 ('ciw', 'foo bar\n', ['ciwx', E, W], 'x bar\n'),
 ('BS join', 'a\nb\n', ['ji\x7f', E, W], 'ab\n'),
 ('enter split', 'ab\n', ['li\r', E, W], 'a\nb\n'),
 ('tab', 'a\n', ['i\t', E, W], '\ta\n'),
 ('arrow ins', 'ab\n', ['i\x1b[Cx', E, W], 'axb\n'),
 ('ZZ', 'a\n', ['x', 'ZZ'], '\n'),
 (':q! no write', 'a\n', ['x', ':q!\r'], 'a\n'),
 (':w then q', 'a\n', ['x:w\r', ':q\r'], '\n'),
 ('new file', None, ['ihi', E, W], 'hi\n'),
 (':r', 'a\n', [':r f.txt\r', W], 'a\na\n'),
 ('x empty', '\n', ['x', W], '\n'),
 ('count motion', 'abcdef\n', ['3lx', W], 'abcef\n'),
 ('j k', 'a\nb\nc\n', ['jjkx', W], 'a\n\nc\n'),
 ('dj', 'a\nb\nc\n', ['dj', W], 'c\n'),
 ('dk', 'a\nb\nc\n', ['jdk', W], 'c\n'),
 ('yw P multiple', 'ab cd\n', ['yw$p', W], 'ab cdab \n'),
 ('& repeat', 'aa\naa\n', [':s/a/b/\r', 'j&', W], 'ba\nba\n'),
 ('*', 'foo bar foo\n', ['*x', W], 'foo bar oo\n'),
 (':set nu draws', 'a\n', [':set nu\r', W], 'a\n'),
 ('long file', ''.join('%d\n' % i for i in range(1, 501)), ['250Gdd', W],
  ''.join('%d\n' % i for i in range(1, 501) if i != 250)),
 ('ctrl-f', ''.join('%d\n' % i for i in range(1, 101)), ['\x06x', W], None),
]
for name, init, keys, exp in cases:
    if exp is None: continue
    t(name, init, keys, exp)
n = len([c for c in cases if c[3] is not None])
print('vi: %d cas, %d echecs' % (n, fails))
sys.exit(1 if fails else 0)
