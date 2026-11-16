#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: Pilote QEMU pour les essais de l'installateur : lance
#   qemu-system-i386 (sortie serie dans un fichier, moniteur sur socket),
#   attend des motifs sur la console serie, injecte clavier et souris
#   (sendkey, mouse_move, mouse_button), capture l'ecran (screendump PPM ->
#   PNG reduit). Module importe par RUNINST.SH ; essai : QCTL.PY --help.
import os, re, socket, subprocess, sys, threading, time

KEYS = {' ': 'spc', '\n': 'ret', '\t': 'tab', '.': 'dot', ',': 'comma',
        '/': 'slash', '-': 'minus', '=': 'equal', ';': 'semicolon',
        "'": 'apostrophe', '\\': 'backslash', '[': 'bracket_left',
        ']': 'bracket_right', '`': 'grave_accent'}
SHIFT = {'!': '1', '@': '2', '#': '3', '$': '4', '%': '5', '^': '6',
         '&': '7', '*': '8', '(': '9', ')': '0', '_': 'minus',
         '+': 'equal', ':': 'semicolon', '"': 'apostrophe', '<': 'comma',
         '>': 'dot', '?': 'slash', '|': 'backslash', '{': 'bracket_left',
         '}': 'bracket_right', '~': 'grave_accent'}


class Q:
    def __init__(self, work, args, serial_io=False):
        self.work = work
        os.makedirs(work, exist_ok=True)
        self.out = os.path.join(work, 'serial.txt')
        self.mon = os.path.join(work, 'mon.sock')
        self.ser = os.path.join(work, 'ser.sock')
        for f in (self.out, self.mon, self.ser):
            if os.path.exists(f):
                os.unlink(f)
        # serial_io : console serie bidirectionnelle (socket) ; sinon fichier
        sdev = ('unix:%s,server,nowait' % self.ser) if serial_io \
            else 'file:' + self.out
        cmd = ['qemu-system-i386', '-serial', sdev,
               '-monitor', 'unix:%s,server,nowait' % self.mon,
               '-display', 'none', '-no-reboot'] + args
        self.sio = None
        self.p = subprocess.Popen(cmd, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL)
        self.s = None
        for _ in range(100):
            try:
                self.s = socket.socket(socket.AF_UNIX)
                self.s.connect(self.mon)
                break
            except OSError:
                self.s = None
                time.sleep(0.1)
        time.sleep(0.3)
        self._drain()
        if serial_io:
            open(self.out, 'w').close()
            for _ in range(100):
                try:
                    self.sio = socket.socket(socket.AF_UNIX)
                    self.sio.connect(self.ser)
                    break
                except OSError:
                    self.sio = None
                    time.sleep(0.1)
            threading.Thread(target=self._pump, daemon=True).start()

    def _pump(self):
        with open(self.out, 'ab', buffering=0) as f:
            while True:
                try:
                    d = self.sio.recv(4096)
                except OSError:
                    return
                if not d:
                    return
                f.write(d)

    def serial(self, s):
        """envoie du texte sur la console serie (serial_io=True)"""
        for ch in s:
            self.sio.send(ch.encode('latin-1'))
            time.sleep(0.01)

    def _drain(self):
        try:
            self.s.settimeout(0.3)
            while self.s.recv(65536):
                pass
        except Exception:
            pass

    def alive(self):
        return self.p.poll() is None

    def cmd(self, c, wait=0.15):
        try:
            self.s.send((c + '\n').encode())
        except OSError:
            return
        time.sleep(wait)
        self._drain()

    def text(self):
        try:
            return open(self.out, errors='replace').read().replace('\r', '')
        except OSError:
            return ''

    def wait(self, pat, timeout=120, after=0):
        rx = re.compile(pat)
        t0 = time.time()
        while time.time() - t0 < timeout:
            m = rx.search(self.text()[after:])
            if m:
                return True
            if not self.alive():
                return rx.search(self.text()[after:]) is not None
            time.sleep(0.2)
        return False

    def key(self, k, wait=0.12):
        self.cmd('sendkey ' + k, wait)

    def type(self, s, wait=0.1):
        for ch in s:
            if ch in KEYS:
                self.key(KEYS[ch], wait)
            elif ch in SHIFT:
                self.key('shift-' + SHIFT[ch], wait)
            elif ch.isupper():
                self.key('shift-' + ch.lower(), wait)
            else:
                self.key(ch, wait)

    def move(self, dx, dy):
        while dx or dy:
            sx = max(-120, min(120, dx))
            sy = max(-120, min(120, dy))
            self.cmd('mouse_move %d %d' % (sx, sy), 0.05)
            dx -= sx
            dy -= sy

    def click(self, left=True):
        self.cmd('mouse_button %d' % (1 if left else 4), 0.1)
        self.cmd('mouse_button 0', 0.1)

    def shot(self, name, png_max=300000):
        ppm = os.path.join(self.work, name + '.ppm')
        if os.path.exists(ppm):
            os.unlink(ppm)
        self.cmd('screendump ' + ppm, 0.5)
        for _ in range(20):
            if os.path.exists(ppm) and os.path.getsize(ppm) > 100:
                break
            time.sleep(0.2)
        time.sleep(0.2)
        png = os.path.join(self.work, name + '.png')
        try:
            from PIL import Image
            im = Image.open(ppm).convert('RGB')
            for colors in (256, 128, 64, 32):
                q = im.quantize(colors=colors, method=Image.MEDIANCUT,
                                dither=Image.NONE)
                q.save(png, optimize=True)
                if os.path.getsize(png) <= png_max:
                    break
            return png
        except Exception as e:
            print('shot:', e)
            return ppm

    def quit(self):
        try:
            self.cmd('quit', 0.2)
        except Exception:
            pass
        try:
            self.p.wait(timeout=5)
        except Exception:
            self.p.kill()


if __name__ == '__main__':
    print(__doc__)
