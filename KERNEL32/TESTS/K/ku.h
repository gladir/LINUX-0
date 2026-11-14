/* ku.h : mini bibliotheque pour les programmes de test du noyau KERNEL32.
   Programmes Linux i386 statiques sans libc : gcc -m32 -static -nostdlib
   -ffreestanding. Les appels systeme utilisent INT 80h (ABI Linux i386). */
#ifndef KU_H
#define KU_H

#define SYS_exit 1
#define SYS_fork 2
#define SYS_read 3
#define SYS_write 4
#define SYS_open 5
#define SYS_close 6
#define SYS_waitpid 7
#define SYS_creat 8
#define SYS_link 9
#define SYS_unlink 10
#define SYS_execve 11
#define SYS_chdir 12
#define SYS_time 13
#define SYS_mknod 14
#define SYS_chmod 15
#define SYS_lseek 19
#define SYS_getpid 20
#define SYS_mount 21
#define SYS_umount 22
#define SYS_setuid 23
#define SYS_getuid 24
#define SYS_alarm 27
#define SYS_pause 29
#define SYS_access 33
#define SYS_sync 36
#define SYS_kill 37
#define SYS_rename 38
#define SYS_mkdir 39
#define SYS_rmdir 40
#define SYS_dup 41
#define SYS_pipe 42
#define SYS_times 43
#define SYS_brk 45
#define SYS_ioctl 54
#define SYS_fcntl 55
#define SYS_setpgid 57
#define SYS_umask 60
#define SYS_dup2 63
#define SYS_getppid 64
#define SYS_getpgrp 65
#define SYS_setsid 66
#define SYS_sigaction 67
#define SYS_sigsuspend 72
#define SYS_symlink 83
#define SYS_readlink 85
#define SYS_reboot 88
#define SYS_munmap 91
#define SYS_ftruncate 93
#define SYS_gettimeofday 78
#define SYS_wait4 114
#define SYS_uname 122
#define SYS_mprotect 125
#define SYS_getdents 141
#define SYS_nanosleep 162
#define SYS_poll 168
#define SYS_rt_sigaction 174
#define SYS_rt_sigprocmask 175
#define SYS_getcwd 183
#define SYS_mmap2 192
#define SYS_stat64 195
#define SYS_lstat64 196
#define SYS_fstat64 197
#define SYS_getdents64 220
#define SYS_gettid 224
#define SYS_clock_gettime 265
#define SYS_sysinfo 116
#define SYS_getpriority 96
#define SYS_nice 34
#define SYS_clone 120
#define SYS_vfork 190
#define SYS_sched_yield 158

typedef long ssize_t;
typedef unsigned long size_t;

static inline long sc0(long n){long r;__asm__ volatile("int $0x80":"=a"(r):"0"(n):"memory");return r;}
static inline long sc1(long n,long a){long r;__asm__ volatile("int $0x80":"=a"(r):"0"(n),"b"(a):"memory");return r;}
static inline long sc2(long n,long a,long b){long r;__asm__ volatile("int $0x80":"=a"(r):"0"(n),"b"(a),"c"(b):"memory");return r;}
static inline long sc3(long n,long a,long b,long c){long r;__asm__ volatile("int $0x80":"=a"(r):"0"(n),"b"(a),"c"(b),"d"(c):"memory");return r;}
static inline long sc4(long n,long a,long b,long c,long d){long r;__asm__ volatile("int $0x80":"=a"(r):"0"(n),"b"(a),"c"(b),"d"(c),"S"(d):"memory");return r;}
static inline long sc5(long n,long a,long b,long c,long d,long e){long r;__asm__ volatile("int $0x80":"=a"(r):"0"(n),"b"(a),"c"(b),"d"(c),"S"(d),"D"(e):"memory");return r;}
static inline long sc6(long n,long a,long b,long c,long d,long e,long f){
  long r;__asm__ volatile("push %%ebp\n\tmov %7,%%ebp\n\tint $0x80\n\tpop %%ebp":"=a"(r):"0"(n),"b"(a),"c"(b),"d"(c),"S"(d),"D"(e),"m"(f):"memory");return r;}

#define O_RDONLY 0
#define O_WRONLY 1
#define O_RDWR 2
#define O_CREAT 0x40
#define O_EXCL 0x80
#define O_TRUNC 0x200
#define O_APPEND 0x400
#define O_NONBLOCK 0x800
#define O_DIRECTORY 0x10000
#define SIGHUP 1
#define SIGINT 2
#define SIGQUIT 3
#define SIGILL 4
#define SIGKILL 9
#define SIGUSR1 10
#define SIGSEGV 11
#define SIGUSR2 12
#define SIGPIPE 13
#define SIGALRM 14
#define SIGTERM 15
#define SIGCHLD 17
#define SIGCONT 18
#define SIGSTOP 19
#define SIGTSTP 20
#define SA_RESTART 0x10000000
#define SA_SIGINFO 4
#define SA_RESTORER 0x04000000
#define SA_NODEFER 0x40000000

static inline void _exit(int c){sc1(SYS_exit,c);for(;;);}
static inline int getpid(void){return sc0(SYS_getpid);}
static inline int getppid(void){return sc0(SYS_getppid);}
static inline int fork(void){return sc0(SYS_fork);}
static inline int read(int fd,void*b,size_t n){return sc3(SYS_read,fd,(long)b,n);}
static inline int write(int fd,const void*b,size_t n){return sc3(SYS_write,fd,(long)b,n);}
static inline int open(const char*p,int f,int m){return sc3(SYS_open,(long)p,f,m);}
static inline int close(int fd){return sc1(SYS_close,fd);}
static inline int waitpid(int p,int*st,int o){return sc3(SYS_waitpid,p,(long)st,o);}
static inline int execve(const char*p,char*const a[],char*const e[]){return sc3(SYS_execve,(long)p,(long)a,(long)e);}
static inline int pipe(int f[2]){return sc1(SYS_pipe,(long)f);}
static inline int dup(int f){return sc1(SYS_dup,f);}
static inline int dup2(int a,int b){return sc2(SYS_dup2,a,b);}
static inline int kill(int p,int s){return sc2(SYS_kill,p,s);}
static inline int unlink(const char*p){return sc1(SYS_unlink,(long)p);}
static inline int mkdir(const char*p,int m){return sc2(SYS_mkdir,(long)p,m);}
static inline int rmdir(const char*p){return sc1(SYS_rmdir,(long)p);}
static inline int chdir(const char*p){return sc1(SYS_chdir,(long)p);}
static inline int rename(const char*a,const char*b){return sc2(SYS_rename,(long)a,(long)b);}
static inline int link(const char*a,const char*b){return sc2(SYS_link,(long)a,(long)b);}
static inline int symlink(const char*a,const char*b){return sc2(SYS_symlink,(long)a,(long)b);}
static inline int readlink(const char*a,char*b,int n){return sc3(SYS_readlink,(long)a,(long)b,n);}
static inline int lseek(int fd,int o,int w){return sc3(SYS_lseek,fd,o,w);}
static inline int alarm(int s){return sc1(SYS_alarm,s);}
static inline int pause(void){return sc0(SYS_pause);}
static inline int getcwd(char*b,int n){return sc2(SYS_getcwd,(long)b,n);}
static inline int ioctl(int fd,int c,long a){return sc3(SYS_ioctl,fd,c,a);}
static inline int fcntl(int fd,int c,long a){return sc3(SYS_fcntl,fd,c,a);}
static inline int setsid(void){return sc0(SYS_setsid);}
static inline int setpgid(int p,int g){return sc2(SYS_setpgid,p,g);}
static inline int getpgrp(void){return sc0(SYS_getpgrp);}
static inline int umask(int m){return sc1(SYS_umask,m);}
static inline int mknod(const char*p,int m,int d){return sc3(SYS_mknod,(long)p,m,d);}
static inline int chmod(const char*p,int m){return sc2(SYS_chmod,(long)p,m);}
static inline int access(const char*p,int m){return sc2(SYS_access,(long)p,m);}
static inline long brk(void*a){return sc1(SYS_brk,(long)a);}
static inline int nice(int n){return sc1(SYS_nice,n);}
static inline void sync(void){sc0(SYS_sync);}
static inline int mount(const char*s,const char*t,const char*f,long fl,const void*d){return sc5(SYS_mount,(long)s,(long)t,(long)f,fl,(long)d);}
static inline int umount(const char*t){return sc1(SYS_umount,(long)t);}
static inline int sched_yield(void){return sc0(SYS_sched_yield);}
static inline void *mmap2(void*a,size_t l,int p,int f,int fd,long off){return (void*)sc6(SYS_mmap2,(long)a,l,p,f,fd,off);}
static inline int munmap(void*a,size_t l){return sc2(SYS_munmap,(long)a,l);}
static inline int mprotect(void*a,size_t l,int p){return sc3(SYS_mprotect,(long)a,l,p);}
static inline int nanosleep(const long*req,long*rem){return sc2(SYS_nanosleep,(long)req,(long)rem);}
static inline int uname(void*b){return sc1(SYS_uname,(long)b);}
static inline long gettid(void){return sc0(SYS_gettid);}
static inline int reboot_off(void){return sc4(SYS_reboot,0xfee1dead,672274793,0x4321FEDC,0);}
static inline int getdents(int fd,void*b,int n){return sc3(SYS_getdents,fd,(long)b,n);}
static inline int getdents64(int fd,void*b,int n){return sc3(SYS_getdents64,fd,(long)b,n);}

struct ksigaction { void (*handler)(int); unsigned long flags; void (*restorer)(void); unsigned long mask[2]; };
void __restore_rt(void);
__asm__(".text\n.global __restore_rt\n__restore_rt:\n\tmov $173,%eax\n\tint $0x80\n");
static inline int signal_set(int sig,void(*h)(int),unsigned long flags){
  struct ksigaction a; a.handler=h; a.flags=flags|SA_RESTORER; a.restorer=__restore_rt; a.mask[0]=a.mask[1]=0;
  return sc4(SYS_rt_sigaction,sig,(long)&a,0,8);}
static inline int sigblock(unsigned long m){unsigned long s[2]={m,0};return sc4(SYS_rt_sigprocmask,0,(long)s,0,8);}
static inline int sigunblock(unsigned long m){unsigned long s[2]={m,0};return sc4(SYS_rt_sigprocmask,1,(long)s,0,8);}

static inline size_t strlen(const char*s){size_t n=0;while(s[n])n++;return n;}
static inline int strcmp(const char*a,const char*b){while(*a&&*a==*b){a++;b++;}return (unsigned char)*a-(unsigned char)*b;}
static inline void *memset(void*d,int c,size_t n){volatile unsigned char*p=d;while(n--)*p++=c;return d;}
static inline void *memcpy(void*d,const void*s,size_t n){unsigned char*p=d;const unsigned char*q=s;while(n--)*p++=*q++;return d;}

static inline void puts_fd(int fd,const char*s){write(fd,s,strlen(s));}
static inline void puts(const char*s){puts_fd(1,s);}
static inline void putnum(long v,int base){
  char b[34];int i=33;unsigned long u=v;b[i]=0;
  if(base==10&&v<0){u=-v;}
  if(u==0)b[--i]='0';
  while(u){b[--i]="0123456789abcdef"[u%base];u/=base;}
  if(base==10&&v<0)b[--i]='-';
  puts(b+i);}
static inline void putd(long v){putnum(v,10);}
static inline void putx(long v){putnum(v,16);}

/* resultat d'un test : ligne "KTEST: nom OK|FAIL" lue par le banc d'essai */
static int ku_pass=0, ku_fail=0;
static inline void ktest(const char*name,int ok){
  puts("KTEST: ");puts(name);puts(ok?" OK\n":" FAIL\n");
  if(ok)ku_pass++;else ku_fail++;}

__asm__(".text\n.global _start\n_start:\n\txorl %ebp,%ebp\n\tmovl %esp,%eax\n\tandl $-16,%esp\n\tpushl %eax\n\tcall cmain\n");

int main();
void cmain(long*sp){int argc=sp[0];char**argv=(char**)(sp+1);char**envp=argv+argc+1;_exit(((int(*)(int,char**,char**))main)(argc,argv,envp));}
#endif
