#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @abstract(Target: Python 3)
# @description: Genere USR/STRACE.INC : noms et formats d'arguments des
#   appels systeme i386 (d'apres asm/unistd_32.h) et noms d'errno.
#   Usage : mkstrace.py [unistd_32.h] > USR/STRACE.INC
#   Lettres de format : d decimal, x hexa, p pointeur, s chaine, f fd,
#   o drapeaux open, m mode octal, B tampon (taille = retour), b tampon
#   (taille = argument suivant), g signal, a argv, e envp, w statut wait,
#   W options wait, r PROT_, M MAP_, y dirfd, k struct stat (sortie),
#   P int[2] (sortie), T chaine (sortie), l whence, A access, D domaine,
#   K type de socket.
import re, sys, errno, os

hdr = sys.argv[1] if len(sys.argv) > 1 else \
    '/usr/include/x86_64-linux-gnu/asm/unistd_32.h'
names = {}
for l in open(hdr):
    m = re.match(r'#define __NR_(\w+)\s+(\d+)', l)
    if m:
        names[int(m.group(2))] = m.group(1)

S = {
 'read': 'f B d', 'write': 'f b d', 'open': 's o m', 'close': 'f',
 'waitpid': 'd w W', 'creat': 's m', 'link': 's s', 'unlink': 's',
 'execve': 's a e', 'chdir': 's', 'time': 'p', 'mknod': 's m x',
 'chmod': 's m', 'lchown': 's d d', 'stat': 's k', 'lstat': 's k',
 'fstat': 'f k', 'lseek': 'f d l', 'getpid': '', 'mount': 's s s x p',
 'umount': 's', 'umount2': 's x', 'setuid': 'd', 'getuid': '',
 'ptrace': 'd d p p', 'alarm': 'd', 'pause': '', 'utime': 's p',
 'access': 's A', 'nice': 'd', 'sync': '', 'kill': 'd g',
 'rename': 's s', 'mkdir': 's m', 'rmdir': 's', 'dup': 'f', 'pipe': 'P',
 'times': 'p', 'brk': 'p', 'setgid': 'd', 'getgid': '', 'signal': 'g p',
 'geteuid': '', 'getegid': '', 'ioctl': 'f x x', 'setpgid': 'd d',
 'umask': 'm', 'chroot': 's', 'dup2': 'f f', 'getppid': '',
 'getpgrp': '', 'setsid': '', 'sigaction': 'g p p', 'sethostname': 's d',
 'setrlimit': 'd p', 'getrlimit': 'd p', 'getrusage': 'd p',
 'gettimeofday': 'p p', 'settimeofday': 'p p', 'symlink': 's s',
 'readlink': 's B d', 'reboot': 'x x x p', 'mmap': 'p', 'munmap': 'p d',
 'truncate': 's d', 'ftruncate': 'f d', 'fchmod': 'f m',
 'fchown': 'f d d', 'getpriority': 'd d', 'setpriority': 'd d d',
 'statfs': 's p', 'fstatfs': 'f p', 'wait4': 'd w W p',
 'swapoff': 's', 'sysinfo': 'p', 'fsync': 'f', 'clone': 'x x p p p',
 'uname': 'p', 'mprotect': 'p d r', 'sigprocmask': 'd p p',
 'getpgid': 'd', 'fchdir': 'f', 'personality': 'x',
 '_llseek': 'f d d p l', 'getdents': 'f p d', '_newselect': 'd p p p p',
 'flock': 'f d', 'readv': 'f p d', 'writev': 'f p d', 'getsid': 'd',
 'fdatasync': 'f', 'mlock': 'p d', 'munlock': 'p d',
 'sched_yield': '', 'nanosleep': 'p p', 'mremap': 'p d d x p',
 'poll': 'p d d', 'prctl': 'x x x x x', 'rt_sigaction': 'g p p d',
 'rt_sigprocmask': 'd p p d', 'rt_sigsuspend': 'p d', 'pread64': 'f B d d',
 'pwrite64': 'f b d d', 'chown': 's d d', 'getcwd': 'T d',
 'sigaltstack': 'p p', 'vfork': '', 'ugetrlimit': 'd p',
 'mmap2': 'p d r M f d', 'truncate64': 's d d', 'ftruncate64': 'f d d',
 'stat64': 's k', 'lstat64': 's k', 'fstat64': 'f k', 'lchown32': 's d d',
 'getuid32': '', 'getgid32': '', 'geteuid32': '', 'getegid32': '',
 'setreuid32': 'd d', 'setregid32': 'd d', 'fchown32': 'f d d',
 'setuid32': 'd', 'setgid32': 'd', 'chown32': 's d d',
 'getdents64': 'f p d', 'fcntl': 'f d x', 'fcntl64': 'f d x',
 'gettid': '', 'futex': 'p d d p p d', 'exit': 'd', 'exit_group': 'd',
 'set_tid_address': 'p', 'clock_gettime': 'd p', 'clock_nanosleep':
 'd x p p', 'tgkill': 'd d g', 'tkill': 'd g', 'utimes': 's p',
 'openat': 'y s o m', 'mkdirat': 'y s m', 'mknodat': 'y s m x',
 'fchownat': 'y s d d x', 'fstatat64': 'y s k d', 'newfstatat':
 'y s k d', 'unlinkat': 'y s d', 'renameat': 'y s y s',
 'linkat': 'y s y s x', 'symlinkat': 's y s', 'readlinkat': 'y s B d',
 'fchmodat': 'y s m', 'faccessat': 'y s A', 'faccessat2': 'y s A x',
 'unshare': 'x', 'pipe2': 'P x', 'dup3': 'f f x', 'socket': 'D K d',
 'bind': 'f p d', 'connect': 'f p d', 'listen': 'f d',
 'accept': 'f p p', 'accept4': 'f p p x', 'getsockopt': 'f d d p p',
 'setsockopt': 'f d d p d', 'getsockname': 'f p p',
 'getpeername': 'f p p', 'sendto': 'f b d x p d',
 'recvfrom': 'f B d x p p', 'shutdown': 'f d', 'sendmsg': 'f p x',
 'recvmsg': 'f p x', 'socketpair': 'D K d p', 'getrandom': 'p d x',
 'epoll_create1': 'x', 'epoll_wait': 'f p d d', 'eventfd2': 'd x',
 'rt_sigtimedwait': 'p p p d', 'rt_sigqueueinfo': 'd g p',
 'sendfile': 'f f p d', 'sendfile64': 'f f p d', 'msync': 'p d x',
 'madvise': 'p d d', 'mincore': 'p d p', 'readahead': 'f d d d',
 'select': 'd p p p p', 'pselect6': 'd p p p p p', 'ppoll': 'p d p p d',
 'chmod': 's m', 'statx': 'y s x x p', 'clone3': 'p d',
 'set_thread_area': 'p', 'get_thread_area': 'p', 'capget': 'p p',
 'capset': 'p p', 'setgroups32': 'd p', 'getgroups32': 'd p',
 'setresuid32': 'd d d', 'setresgid32': 'd d d', 'seccomp': 'd x p',
 'init_module': 'p d s', 'delete_module': 's x', 'bpf': 'd p d',
 'splice': 'f p f p d x', 'tee': 'f f d x', 'timerfd_create': 'd x',
 'inotify_init1': 'x', 'inotify_add_watch': 'f s x', 'fallocate':
 'f x d d d d', 'pidfd_open': 'd x', 'ioprio_set': 'd d d',
 'ioprio_get': 'd d', 'sched_getaffinity': 'd d p',
 'sched_setaffinity': 'd d p', 'getcpu': 'p p p', 'restart_syscall': '',
 'rt_sigreturn': '', 'sigreturn': '', 'sigpending': 'p',
 'rt_sigpending': 'p d', 'setfsuid32': 'd', 'setfsgid32': 'd',
 'getresuid32': 'p p p', 'getresgid32': 'p p p', 'lstat64': 's k',
 'removexattr': 's s', 'setxattr': 's s p d x', 'getxattr': 's s p d',
 'listxattr': 's p d', 'sethostname': 's d', 'setdomainname': 's d',
 'syslog': 'd p d', 'adjtimex': 'p', 'mlockall': 'x', 'munlockall': '',
 'pivot_root': 's s', 'swapon': 's x', 'quotactl': 'x s d p',
 'sched_getparam': 'd p', 'sched_setparam': 'd p',
 'sched_setscheduler': 'd d p', 'sched_getscheduler': 'd',
 'timer_create': 'd p p', 'times': 'p', 'setitimer': 'd p p',
 'getitimer': 'd p', 'io_setup': 'd p', 'lookup_dcookie': 'x p d',
 'mq_open': 's x m p', 'faccessat': 'y s A', 'umask': 'm',
 'getpmsg': 'd p p p p', 'prlimit64': 'd d p p', 'sync_file_range':
 'f d d d d', 'syncfs': 'f', 'name_to_handle_at': 'y s p p x',
 'open_by_handle_at': 'f p o', 'close_range': 'd d x',
 'openat2': 'y s p d', 'copy_file_range': 'f p f p d x',
 'getdents64': 'f p d', 'mprotect': 'p d r', 'modify_ldt': 'd p d',
 'pread': 'f B d d', 'pwrite': 'f b d d', 'fadvise64': 'f d d d d',
 'fadvise64_64': 'f d d d d d', 'epoll_ctl': 'f d f p',
 'epoll_pwait': 'f p d d p', 'signalfd4': 'd p d x', 'ftruncate': 'f d',
}

def q(s):
    return "'" + s.replace("'", "''") + "'"

top = max(names)
out = []
out.append('{ STRACE.INC : genere par TESTS/U/mkstrace.py - ne pas editer. }')
out.append('Const')
out.append('  ScMax = %d;' % top)
out.append('  ScNames : Array[0..%d] Of PChar = (' % top)
for i in range(top + 1):
    n = names.get(i, '')
    if n:
        sp = S.get(n)
        e = n + ((' ' + sp) if sp else '') if sp is not None else n + ' ?'
        if sp == '':
            e = n + ' -'
    else:
        e = ''
    out.append('    ' + q(e) + (',' if i < top else ''))
out.append('  );')
en = {}
for k, v in errno.errorcode.items():
    if 0 < k <= 133 and k not in en:
        en[k] = v
# noms canoniques de Linux
en[11] = 'EAGAIN'
en[35] = 'EDEADLK'
en[95] = 'EOPNOTSUPP'
out.append('  ErrMax = 133;')
out.append('  ErrNames : Array[0..133] Of PChar = (')
for i in range(134):
    out.append('    ' + q(en.get(i, '')) + (',' if i < 133 else ''))
out.append('  );')
sys.stdout.write('\n'.join(out) + '\n')
