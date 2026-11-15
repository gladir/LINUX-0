/* seccomptest : seccomp (SECCOMP_MODE_STRICT, SECCOMP_MODE_FILTER avec
   interpreteur BPF classique), prctl(PR_SET_NO_NEW_PRIVS), seccomp(2),
   retours ALLOW / KILL / ERRNO / TRAP / TRACE / LOG, empilement, heritage
   par fork, interaction avec ptrace. */
#include "ku.h"
#define PR_GET_SECCOMP 21
#define PR_SET_SECCOMP 22
#define PR_SET_NNP 38
#define PR_GET_NNP 39
#define RET_ALLOW 0x7fff0000u
#define RET_LOG 0x7ffc0000u
#define RET_TRACE 0x7ff00000u
#define RET_ERRNO 0x00050000u
#define RET_TRAP 0x00030000u
#define RET_KILL_THREAD 0u
#define RET_KILL_PROC 0x80000000u
#define ARCH_I386 0x40000003u
#define WALL 0x40000000
#define WIFSTOPPED(s) (((s)&0xff)==0x7f)
#define WSTOPSIG(s) (((s)>>8)&0xff)
#define WIFEXITED(s) (((s)&0x7f)==0)
#define WEXITSTATUS(s) (((s)>>8)&0xff)
#define WIFSIGNALED(s) (((s)&0x7f)!=0&&((s)&0x7f)!=0x7f)
#define WTERMSIG(s) ((s)&0x7f)

struct sf{unsigned short code;unsigned char jt,jf;unsigned k;};
struct fprog{unsigned short len;unsigned short pad;struct sf*f;};
#define ST(c,k) {c,0,0,k}
#define JM(c,k,jt,jf) {c,jt,jf,k}
#define LDW(k) ST(0x20,k)
#define RET(k) ST(0x06,k)
#define NRSYS 0
#define ARCH 4
#define ARG0 16
#define ARG1 24

static long prctl5(long o,long a,long b,long c,long d){return sc5(172,o,a,b,c,d);}
static int install(struct sf*f,int n){struct fprog p;p.len=n;p.pad=0;p.f=f;return prctl5(PR_SET_SECCOMP,2,(long)&p,0,0);}
static long sys_seccomp(long op,long fl,long a){return sc3(354,op,fl,a);}
static long pt(long r,long p,long a,long d){return sc4(26,r,p,a,d);}
static int setuid_(int u){return sc1(SYS_setuid,u);}

static volatile int sig_hit,sig_code,sig_nr,sig_arch,sig_addr_ok;
static void sysh(int s,unsigned*info,void*uc){
  sig_hit=s;sig_code=(int)info[2];sig_nr=(int)info[4];sig_arch=(int)info[5];sig_addr_ok=info[3]!=0;
}
static void nap(int ms){long r[2]={0,ms*1000000L};nanosleep(r,0);}
static int stopped(int pid,int*st){int r=waitpid(pid,st,WALL);return r==pid&&WIFSTOPPED(*st);}

/* ---- 1 : mode strict ---- */
static void c_strict(void){
  if(prctl5(PR_GET_SECCOMP,0,0,0,0)!=0)_exit(1);
  if(prctl5(PR_SET_SECCOMP,1,0,0,0)!=0)_exit(2);
  if(prctl5(PR_GET_SECCOMP,0,0,0,0)!=1)_exit(3);
  /* prctl lui meme est interdit : kill, on n'arrive jamais ici */
  _exit(4);
}
static void c_strict2(void){
  prctl5(PR_SET_SECCOMP,1,0,0,0);
  { const char*m="  (strict: write ok)\n";write(1,m,strlen(m)); }
  sc0(SYS_getpid);
  _exit(0);
}
static void c_strict_exit(void){
  prctl5(PR_SET_SECCOMP,1,0,0,0);
  _exit(11);
}

/* ---- 2 : filtre : ERRNO, TRAP, LOG, controle de l'architecture et des arguments ---- */
static void c_filter(void){
  struct sf f[]={
    LDW(ARCH),JM(0x15,ARCH_I386,1,0),RET(RET_KILL_PROC),
    LDW(NRSYS),
    JM(0x15,20,0,1),RET(RET_ERRNO|1),            /* getpid -> EPERM */
    JM(0x15,64,0,1),RET(RET_ERRNO|2),            /* getppid -> ENOENT */
    JM(0x15,224,0,1),RET(RET_TRAP),              /* gettid -> SIGSYS */
    JM(0x15,24,0,1),RET(RET_LOG),                /* getuid -> LOG (autorise) */
    JM(0x15,4,0,3),LDW(ARG0),JM(0x15,2,0,1),RET(RET_ERRNO|9),  /* write(2,..) -> EBADF */
    RET(RET_ALLOW),
    RET(RET_ALLOW)};
  /* note : les sauts ci-dessus sont verifies par le noyau */
  if(prctl5(PR_SET_NNP,1,0,0,0)!=0)_exit(1);
  if(prctl5(PR_GET_NNP,0,0,0,0)!=1)_exit(2);
  if(install(f,sizeof f/sizeof f[0])!=0)_exit(3);
  if(prctl5(PR_GET_SECCOMP,0,0,0,0)!=2)_exit(4);
  if(sc0(SYS_getpid)!=-1)_exit(5);
  if(sc0(SYS_getppid)!=-2)_exit(6);
  if(sc0(SYS_getuid)<0)_exit(7);
  { const char*m="  (filter: write(1) ok)\n";if(write(1,m,strlen(m))!=(int)strlen(m))_exit(8); }
  if(sc3(SYS_write,2,(long)"x",1)!=-9)_exit(9);
  signal_set(31,(void(*)(int))sysh,0);
  sig_hit=0;
  { long r=sc0(SYS_gettid);
    if(r!=-38)_exit(10);
    if(sig_hit!=31||sig_code!=1||sig_nr!=224||(unsigned)sig_arch!=ARCH_I386||!sig_addr_ok)_exit(11); }
  /* fork : le filtre est herite */
  { int p=fork(),st;
    if(p==0){_exit(sc0(SYS_getpid)==-1?0:1);}
    waitpid(p,&st,0);
    if(!WIFEXITED(st)||WEXITSTATUS(st)!=0)_exit(12); }
  _exit(0);
}
static void c_kill_thread(void){
  struct sf f[]={LDW(NRSYS),JM(0x15,122,0,1),RET(RET_KILL_THREAD),RET(RET_ALLOW)};
  prctl5(PR_SET_NNP,1,0,0,0);
  if(install(f,4)!=0)_exit(1);
  { char u[390];uname(u); }
  _exit(0);
}
static void c_kill_proc(void){
  struct sf f[]={LDW(NRSYS),JM(0x15,122,0,1),RET(RET_KILL_PROC),RET(RET_ALLOW)};
  prctl5(PR_SET_NNP,1,0,0,0);
  if(install(f,4)!=0)_exit(1);
  { char u[390];uname(u); }
  _exit(0);
}
static void c_badarch(void){
  struct sf f[]={LDW(ARCH),JM(0x15,ARCH_I386,0,3),LDW(NRSYS),JM(0x15,20,0,1),RET(RET_ERRNO|38),RET(RET_ALLOW),RET(RET_ALLOW)};
  prctl5(PR_SET_NNP,1,0,0,0);
  if(install(f,7)!=0)_exit(1);
  _exit(sc0(SYS_getpid)==-38?0:2);
}

/* ---- 3 : empilement : le plus severe l'emporte ---- */
static void c_stack(void){
  struct sf a[]={LDW(NRSYS),JM(0x15,20,0,1),RET(RET_ERRNO|1),JM(0x15,24,0,1),RET(RET_ALLOW),RET(RET_ALLOW)};
  struct sf b[]={LDW(NRSYS),JM(0x15,64,0,1),RET(RET_ERRNO|2),JM(0x15,24,0,1),RET(RET_ERRNO|7),RET(RET_ALLOW)};
  struct sf c[]={LDW(NRSYS),JM(0x15,20,0,1),RET(RET_KILL_THREAD),RET(RET_ALLOW)};
  prctl5(PR_SET_NNP,1,0,0,0);
  if(install(a,6)!=0)_exit(1);
  if(sc0(SYS_getpid)!=-1)_exit(2);
  if(sc0(SYS_getppid)<0)_exit(3);
  if(install(b,6)!=0)_exit(4);
  if(sc0(SYS_getppid)!=-2)_exit(5);
  if(sc0(SYS_getuid)!=-7)_exit(6);     /* ERRNO(b) plus severe que ALLOW(a) */
  if(sc0(SYS_getpid)!=-1)_exit(7);
  if(install(c,4)!=0)_exit(8);
  sc0(SYS_getpid);                    /* KILL : on n'y revient pas */
  _exit(9);
}

/* ---- 4 : verifications du programme, droits, seccomp(2) ---- */
static void c_checks(void){
  struct sf bad1[]={LDW(NRSYS)};                                  /* pas de RET final */
  struct sf bad2[]={LDW(NRSYS),JM(0x15,1,5,0),RET(RET_ALLOW)};    /* saut hors programme */
  struct sf bad3[]={LDW(3),RET(RET_ALLOW)};                       /* offset non aligne */
  struct sf bad4[]={ST(0x34,0),RET(RET_ALLOW)};                   /* division par 0 */
  struct sf bad5[]={ST(0x28,0),RET(RET_ALLOW)};                   /* LD half interdit */
  struct sf ok1[]={RET(RET_ALLOW)};
  unsigned act;
  if(setuid_(1000)!=0)_exit(1);
  if(install(ok1,1)!=-13)_exit(2);                      /* EACCES sans no_new_privs */
  if(prctl5(PR_SET_NNP,0,0,0,0)!=-22)_exit(3);
  if(prctl5(PR_SET_NNP,1,0,0,0)!=0)_exit(4);
  if(install(bad1,1)!=-22||install(bad2,3)!=-22||install(bad3,2)!=-22||install(bad4,2)!=-22||install(bad5,2)!=-22)_exit(5);
  { struct fprog p={0,0,ok1};if(prctl5(PR_SET_SECCOMP,2,(long)&p,0,0)!=-22)_exit(6); }
  if(prctl5(PR_SET_SECCOMP,3,0,0,0)!=-22)_exit(7);
  act=RET_ERRNO;if(sys_seccomp(2,0,(long)&act)!=0)_exit(8);
  act=0x12340000u;if(sys_seccomp(2,0,(long)&act)!=-95)_exit(9);
  if(sys_seccomp(9,0,0)!=-22)_exit(10);
  { struct fprog p;p.len=1;p.pad=0;p.f=ok1;
    if(sys_seccomp(1,1,(long)&p)!=0)_exit(11); }       /* TSYNC, un seul fil */
  if(prctl5(PR_GET_SECCOMP,0,0,0,0)!=2)_exit(12);
  if(sys_seccomp(0,0,0)!=-22)_exit(13);               /* strict apres filtre : EINVAL */
  _exit(0);
}

/* ---- 5 : interpreteur BPF : ALU, memoire, sauts ---- */
static void c_bpf(void){
  struct sf f[]={
    LDW(NRSYS),
    JM(0x15,20,0,16),                 /* si getpid sinon -> ALLOW */
    ST(0x24,3),                       /* A*=3   = 60 */
    ST(0x04,4),                       /* A+=4   = 64 */
    ST(0x64,1),                       /* A<<=1  = 128 */
    ST(0x74,2),                       /* A>>=2  = 32 */
    ST(0x34,4),                       /* A/=4   = 8 */
    ST(0x44,3),                       /* A|=3   = 11 */
    ST(0xa4,1),                       /* A^=1   = 10 */
    ST(0x54,7),                       /* A&=7   = 2 */
    ST(0x84,0),                       /* A=-A */
    ST(0x84,0),                       /* A=-A   = 2 */
    ST(0x02,3),                       /* M[3]=A */
    ST(0x61,3),                       /* X=M[3] = 2 */
    ST(0x0c,0),                       /* A+=X   = 4 */
    ST(0x07,0),                       /* X=A    = 4 */
    ST(0x87,0),                       /* A=X */
    ST(0x1c,0),                       /* A-=X   = 0 */
    JM(0x15,0,0,1),RET(RET_ERRNO|77),
    RET(RET_ALLOW),RET(RET_ALLOW),RET(RET_ALLOW)};
  f[1].jf=18;
  prctl5(PR_SET_NNP,1,0,0,0);
  if(install(f,sizeof f/sizeof f[0])!=0)_exit(1);
  if(sc0(SYS_getpid)!=-77)_exit(2);
  if(sc0(SYS_getppid)<0)_exit(3);
  _exit(0);
}
static void c_bpf2(void){
  /* ne filtre que write : fd > 4 -> 201 ; fd >= 3 -> 203 ; fd & 2 -> 240 */
  struct sf g[]={
    LDW(NRSYS),JM(0x15,4,1,0),RET(RET_ALLOW),
    LDW(ARG0),
    JM(0x25,4,0,1),                  /* jgt 4 : vrai -> suivant, faux -> saute 1 */
    RET(RET_ERRNO|201),
    JM(0x35,3,0,1),
    RET(RET_ERRNO|203),
    JM(0x45,2,0,1),
    RET(RET_ERRNO|240),
    RET(RET_ALLOW)};
  prctl5(PR_SET_NNP,1,0,0,0);
  if(install(g,sizeof g/sizeof g[0])!=0)_exit(1);
  if(sc3(SYS_write,7,(long)"x",1)!=-201)_exit(2);
  if(sc3(SYS_write,65,(long)"x",1)!=-201)_exit(3);
  if(sc3(SYS_write,3,(long)"x",1)!=-203)_exit(4);
  if(sc3(SYS_write,4,(long)"x",1)!=-203)_exit(5);
  if(sc3(SYS_write,2,(long)"x",1)!=-240)_exit(6);
  if(sc3(SYS_write,1,(long)"",0)!=0)_exit(7);
  _exit(0);
}

/* ---- 6 : SECCOMP_RET_TRACE avec un traceur ---- */
static void t_trace(void){
  int pid=fork(),st,ok=0;long msg=0;unsigned long regs[17];
  if(pid==0){
    struct sf f[]={LDW(NRSYS),JM(0x15,24,0,1),RET(RET_TRACE|0x55),RET(RET_ALLOW)};
    long v;
    sc4(26,0,0,0,0);
    kill(getpid(),SIGSTOP);
    prctl5(PR_SET_NNP,1,0,0,0);
    if(install(f,4)!=0)_exit(1);
    v=sc0(SYS_getuid);
    _exit(v==777?0:2);
  }
  stopped(pid,&st);
  pt(0x4200,pid,0,0x80);                  /* PTRACE_O_TRACESECCOMP */
  pt(7,pid,0,0);
  if(stopped(pid,&st)&&((st>>16)&0xff)==7&&WSTOPSIG(st)==5){
    unsigned char inf[88];
    pt(0x4201,pid,0,(long)&msg);
    memset(inf,0,sizeof inf);
    ok=(msg==0x55)&&pt(0x420e,pid,sizeof inf,(long)inf)==88&&inf[0]==3&&*(unsigned*)(inf+24)==24&&*(unsigned*)(inf+80)==0x55;
    ktest("seccomp.trace_event",ok);
    ktest("seccomp.get_filter",pt(0x420c,pid,0,0)==4);
    pt(12,pid,0,(long)regs);
    regs[6]=777;regs[11]=(unsigned long)-1;     /* eax, orig_eax = -1 : appel saute */
    pt(13,pid,0,(long)regs);
    pt(7,pid,0,0);
  }else ktest("seccomp.trace_event",0);
  waitpid(pid,&st,0);
  ktest("seccomp.trace_emulated",WIFEXITED(st)&&WEXITSTATUS(st)==0);
  /* sans traceur : TRACE -> ENOSYS */
  pid=fork();
  if(pid==0){struct sf f[]={LDW(NRSYS),JM(0x15,24,0,1),RET(RET_TRACE|1),RET(RET_ALLOW)};
    prctl5(PR_SET_NNP,1,0,0,0);install(f,4);_exit(sc0(SYS_getuid)==-38?0:1);}
  waitpid(pid,&st,0);
  ktest("seccomp.trace_no_tracer_enosys",WIFEXITED(st)&&WEXITSTATUS(st)==0);
}

static int run(void(*fn)(void)){
  int p=fork(),st;
  if(p==0){fn();_exit(0);}
  waitpid(p,&st,0);
  return st;
}

int main(void){
  int st;
  st=run(c_strict);
  ktest("seccomp.strict_kills_prctl",WIFSIGNALED(st)&&WTERMSIG(st)==9);
  st=run(c_strict2);
  ktest("seccomp.strict_getpid_kill",WIFSIGNALED(st)&&WTERMSIG(st)==9);
  st=run(c_strict_exit);
  ktest("seccomp.strict_exit_allowed",WIFEXITED(st)&&WEXITSTATUS(st)==11);
  st=run(c_filter);
  ktest("seccomp.filter_errno_trap_log_args",WIFEXITED(st)&&WEXITSTATUS(st)==0);
  if(!(WIFEXITED(st)&&WEXITSTATUS(st)==0)){puts("  c_filter status=");putd(st);puts("\n");}
  st=run(c_kill_thread);
  ktest("seccomp.kill_thread_sigsys",WIFSIGNALED(st)&&WTERMSIG(st)==31);
  st=run(c_kill_proc);
  ktest("seccomp.kill_process",WIFSIGNALED(st)&&WTERMSIG(st)==31);
  st=run(c_badarch);
  ktest("seccomp.arch_check",WIFEXITED(st)&&WEXITSTATUS(st)==0);
  st=run(c_stack);
  ktest("seccomp.stack_most_severe",WIFSIGNALED(st)&&WTERMSIG(st)==31);
  if(!(WIFSIGNALED(st)&&WTERMSIG(st)==31)){puts("  c_stack status=");putd(st);puts("\n");}
  st=run(c_checks);
  ktest("seccomp.checks_nnp_validation",WIFEXITED(st)&&WEXITSTATUS(st)==0);
  if(!(WIFEXITED(st)&&WEXITSTATUS(st)==0)){puts("  c_checks status=");putd(st);puts("\n");}
  st=run(c_bpf);
  ktest("seccomp.bpf_alu_mem",WIFEXITED(st)&&WEXITSTATUS(st)==0);
  if(!(WIFEXITED(st)&&WEXITSTATUS(st)==0)){puts("  c_bpf status=");putd(st);puts("\n");}
  st=run(c_bpf2);
  ktest("seccomp.bpf_jmp",WIFEXITED(st)&&WEXITSTATUS(st)==0);
  if(!(WIFEXITED(st)&&WEXITSTATUS(st)==0)){puts("  c_bpf2 status=");putd(st);puts("\n");}
  t_trace();
  puts("seccomp DONE\n");
  (void)nap;
  return ku_fail?1:0;
}
