/* ptracetest : ptrace (TRACEME, ATTACH, SEIZE, DETACH, PEEK/POKE, GETREGS,
   SETREGS, FP, CONT, SYSCALL, SINGLESTEP, SYSEMU, KILL, SETOPTIONS,
   GETSIGINFO, GETEVENTMSG), arret aux signaux, evenements, points d'arret
   (int3, DR0-DR7), strace minimal sur un programme reel. */
#include "ku.h"
#define PT_TRACEME 0
#define PT_PEEKDATA 2
#define PT_PEEKUSER 3
#define PT_POKEDATA 5
#define PT_POKEUSER 6
#define PT_CONT 7
#define PT_KILL 8
#define PT_SINGLESTEP 9
#define PT_GETREGS 12
#define PT_SETREGS 13
#define PT_GETFPREGS 14
#define PT_SETFPREGS 15
#define PT_ATTACH 16
#define PT_DETACH 17
#define PT_GETFPXREGS 18
#define PT_SETFPXREGS 19
#define PT_SYSCALL 24
#define PT_SYSEMU 31
#define PT_SETOPTIONS 0x4200
#define PT_GETEVENTMSG 0x4201
#define PT_GETSIGINFO 0x4202
#define PT_GETREGSET 0x4204
#define PT_SEIZE 0x4206
#define PT_INTERRUPT 0x4207
#define PT_GET_SYSCALL_INFO 0x420e
#define SIGTRAP 5
#define WALL 0x40000000
#define WIFSTOPPED(s) (((s)&0xff)==0x7f)
#define WSTOPSIG(s) (((s)>>8)&0xff)
#define WIFEXITED(s) (((s)&0x7f)==0)
#define WEXITSTATUS(s) (((s)>>8)&0xff)
#define WIFSIGNALED(s) (((s)&0x7f)!=0&&((s)&0x7f)!=0x7f)
#define WTERMSIG(s) ((s)&0x7f)

struct regs{long ebx,ecx,edx,esi,edi,ebp,eax,xds,xes,xfs,xgs,orig_eax,eip,xcs,eflags,esp,xss;};
static long pt(long r,long p,long a,long d){return sc4(26,r,p,a,d);}
static long peek(int pid,long addr){long v=0;long r=pt(PT_PEEKDATA,pid,addr,(long)&v);return r<0?-1:v;}
static void nap(int ms){long r[2]={0,ms*1000000L};nanosleep(r,0);}
static int stopped(int pid,int*st){int r=waitpid(pid,st,WALL);return r==pid&&WIFSTOPPED(*st);}

static volatile int shared_var=1111;
static volatile int usr2_hit;
static volatile int wvar;
static void usr2h(int s){usr2_hit++;}

int target(void);
int target2(void);
void target_end(void);
__asm__(".text\n.global target\ntarget:\n\tnop\n\tnop\n\tnop\n\tnop\n\tnop\n\tmov $42,%eax\n\tret\n"
        ".global target2\ntarget2:\n\tmov $20,%eax\n\tint $0x80\n\tnop\n\tret\n"
        ".global target_end\ntarget_end:\n\tnop\n");

/* 1 : arret a un signal, GETSIGINFO, GETREGS, PEEK/POKE, suppression */
static void t_basic(void){
  int pid=fork(),st;struct regs r;unsigned si[32];
  if(pid==0){pt(PT_TRACEME,0,0,0);kill(getpid(),SIGUSR1);_exit(shared_var==2222?7:8);}
  ktest("ptrace.stop_usr1",stopped(pid,&st)&&WSTOPSIG(st)==SIGUSR1);
  memset(si,0,sizeof si);
  ktest("ptrace.getsiginfo",pt(PT_GETSIGINFO,pid,0,(long)si)==0&&si[0]==SIGUSR1&&si[2]==0&&(int)si[3]==pid);
  memset(&r,0,sizeof r);
  ktest("ptrace.getregs",pt(PT_GETREGS,pid,0,(long)&r)==0&&r.xcs==0x1b&&r.esp!=0&&r.eip>=0x08048000);
  ktest("ptrace.peekuser_eip",pt(PT_PEEKUSER,pid,12*4,(long)&r.ebx)==0&&r.ebx==r.eip);
  ktest("ptrace.peekdata",peek(pid,(long)&shared_var)==1111);
  ktest("ptrace.pokedata",pt(PT_POKEDATA,pid,(long)&shared_var,2222)==0&&peek(pid,(long)&shared_var)==2222&&shared_var==1111);
  ktest("ptrace.peek_efault",pt(PT_PEEKDATA,pid,0x10,(long)&r.ebx)==-5);
  { struct{void*b;long l;}iov;long rs[17];iov.b=rs;iov.l=sizeof rs;
    ktest("ptrace.getregset",pt(PT_GETREGSET,pid,1,(long)&iov)==0&&iov.l==68&&rs[12]==r.eip); }
  ktest("ptrace.cont_suppress",pt(PT_CONT,pid,0,0)==0);
  waitpid(pid,&st,0);
  ktest("ptrace.exit_code",WIFEXITED(st)&&WEXITSTATUS(st)==7);
}

/* 2 : injection d'un autre signal a la reprise */
static void t_inject(void){
  int pid=fork(),st;
  if(pid==0){pt(PT_TRACEME,0,0,0);signal_set(SIGUSR2,usr2h,0);kill(getpid(),SIGUSR1);_exit(usr2_hit==1?5:6);}
  stopped(pid,&st);
  ktest("ptrace.inject",pt(PT_CONT,pid,0,SIGUSR2)==0);
  waitpid(pid,&st,0);
  ktest("ptrace.inject_handler",WIFEXITED(st)&&WEXITSTATUS(st)==5);
}

/* 3 : strace minimal sur un programme reel */
static void t_strace(void){
  int pid=fork(),st,n=0,entry=1,nw=0,sawexit=0,okpair=1,info_ok=0,sawexec=0;char buf[64];
  if(pid==0){char*a[]={"/bin/hello",0};char*e[]={"PATH=/bin",0};
    pt(PT_TRACEME,0,0,0);execve("/bin/hello",a,e);_exit(99);}
  ktest("ptrace.exec_sigtrap",stopped(pid,&st)&&WSTOPSIG(st)==SIGTRAP);
  ktest("ptrace.setoptions",pt(PT_SETOPTIONS,pid,0,1)==0);
  for(;;){
    struct regs r;
    if(pt(PT_SYSCALL,pid,0,0)<0)break;
    waitpid(pid,&st,WALL);
    if(WIFEXITED(st)){sawexit=WEXITSTATUS(st)==0;break;}
    if(!WIFSTOPPED(st))break;
    if(WSTOPSIG(st)!=(SIGTRAP|0x80)){okpair=0;continue;}
    pt(PT_GETREGS,pid,0,(long)&r);
    n++;
    if(entry){
      if(r.eax!=-38)okpair=0;
      if(r.orig_eax==4&&r.ebx==1&&nw==0){
        int i;for(i=0;i<8;i++)buf[i]=0;
        { long w=peek(pid,r.ecx);memcpy(buf,&w,4);w=peek(pid,r.ecx+4);memcpy(buf+4,&w,4);}
        nw=1;
        { unsigned char inf[88];memset(inf,0,sizeof inf);
          long sz=pt(PT_GET_SYSCALL_INFO,pid,sizeof inf,(long)inf);
          info_ok=(sz==80&&inf[0]==1&&*(unsigned*)(inf+4)==0x40000003&&*(unsigned*)(inf+24)==4&&*(unsigned*)(inf+32)==1&&*(unsigned*)(inf+48)==(unsigned)r.edx);}
      }
      if(r.orig_eax==252)sawexit=2;
    }else{
      if(r.orig_eax==4&&nw==1){nw=2;if(r.eax!=r.edx)okpair=0;}
    }
    entry=!entry;
  }
  ktest("ptrace.strace_write_buf",nw==2&&memcmp_(buf,"Bonjour ",8)==0);
  ktest("ptrace.strace_syscall_info",info_ok);
  ktest("ptrace.strace_pairs",n>10&&okpair);
  ktest("ptrace.strace_exit",sawexit==1||sawexit==2);
  (void)sawexec;
}

/* 4 : pas a pas : nombre exact d'instructions, y compris au travers de INT 80h */
static int step_to(int pid,void*addr,struct regs*r){
  int st,i;
  pt(PT_GETREGS,pid,0,(long)r);
  for(i=0;i<3000&&(unsigned long)r->eip!=(unsigned long)addr;i++){
    if(pt(PT_SINGLESTEP,pid,0,0)<0)return 0;
    if(!stopped(pid,&st))return 0;
    pt(PT_GETREGS,pid,0,(long)r);
  }
  return (unsigned long)r->eip==(unsigned long)addr;
}
static int count_in(int pid,void*lo,void*hi,struct regs*r){
  int cnt=0,st;
  while((unsigned long)r->eip>=(unsigned long)lo&&(unsigned long)r->eip<(unsigned long)hi&&cnt<50){
    if(pt(PT_SINGLESTEP,pid,0,0)<0)break;
    if(!stopped(pid,&st)||WSTOPSIG(st)!=SIGTRAP)break;
    pt(PT_GETREGS,pid,0,(long)r);cnt++;
  }
  return cnt;
}
static void t_step(void){
  int pid=fork(),st;struct regs r;
  if(pid==0){pt(PT_TRACEME,0,0,0);kill(getpid(),SIGSTOP);{int a=target();int b=target2();_exit((a==42&&b==getpid())?0:1);}}
  stopped(pid,&st);
  ktest("ptrace.step_reach_target",step_to(pid,(void*)target,&r));
  ktest("ptrace.step_count_7",count_in(pid,(void*)target,(void*)target2,&r)==7);
  ktest("ptrace.step_reach_target2",step_to(pid,(void*)target2,&r));
  ktest("ptrace.step_int80_count_4",count_in(pid,(void*)target2,(void*)target_end,&r)==4);
  pt(PT_CONT,pid,0,0);
  waitpid(pid,&st,0);
  ktest("ptrace.step_finish",WIFEXITED(st)&&WEXITSTATUS(st)==0);
}

/* 5 : point d'arret logiciel int3 (ecriture forcee dans le code) */
static void t_bp(void){
  int pid=fork(),st;struct regs r;unsigned si[32];long orig,w;
  if(pid==0){pt(PT_TRACEME,0,0,0);kill(getpid(),SIGSTOP);_exit(target()==42?0:1);}
  stopped(pid,&st);
  orig=peek(pid,(long)target);
  w=(orig&~0xff)|0xcc;
  ktest("ptrace.bp_poke_text",pt(PT_POKEDATA,pid,(long)target,w)==0&&peek(pid,(long)target)==w);
  ktest("ptrace.bp_parent_unchanged",*(volatile unsigned char*)target==0x90);
  pt(PT_CONT,pid,0,0);
  ktest("ptrace.bp_hit",stopped(pid,&st)&&WSTOPSIG(st)==SIGTRAP);
  pt(PT_GETREGS,pid,0,(long)&r);
  memset(si,0,sizeof si);pt(PT_GETSIGINFO,pid,0,(long)si);
  ktest("ptrace.bp_eip",(unsigned long)r.eip==(unsigned long)target+1&&si[2]==0x80);
  pt(PT_POKEDATA,pid,(long)target,orig);
  r.eip=(long)target;
  pt(PT_SETREGS,pid,0,(long)&r);
  pt(PT_CONT,pid,0,0);
  waitpid(pid,&st,0);
  ktest("ptrace.bp_resume",WIFEXITED(st)&&WEXITSTATUS(st)==0);
}

/* 6 : point d'arret materiel (DR0/DR7) */
static void t_hw(void){
  int pid=fork(),st;long v=0;unsigned si[32];
  if(pid==0){pt(PT_TRACEME,0,0,0);kill(getpid(),SIGSTOP);wvar=5;_exit(wvar==5?0:1);}
  stopped(pid,&st);
  ktest("ptrace.dr_set",pt(PT_POKEUSER,pid,252,(long)&wvar)==0&&pt(PT_POKEUSER,pid,252+28,0x000D0001)==0);
  ktest("ptrace.dr_get",pt(PT_PEEKUSER,pid,252,(long)&v)==0&&v==(long)&wvar);
  ktest("ptrace.dr_reject",pt(PT_POKEUSER,pid,252+28,0x00020001)==-5);
  pt(PT_CONT,pid,0,0);
  ktest("ptrace.dr_hit",stopped(pid,&st)&&WSTOPSIG(st)==SIGTRAP);
  v=0;pt(PT_PEEKUSER,pid,252+24,(long)&v);
  memset(si,0,sizeof si);pt(PT_GETSIGINFO,pid,0,(long)si);
  ktest("ptrace.dr6_b0",(v&1)==1&&si[2]==4);
  pt(PT_POKEUSER,pid,252+24,0);
  pt(PT_POKEUSER,pid,252+28,0);
  pt(PT_CONT,pid,0,0);
  waitpid(pid,&st,0);
  ktest("ptrace.dr_clear_exit",WIFEXITED(st)&&WEXITSTATUS(st)==0);
}

/* 7 : evenements fork / exit */
static void t_events(void){
  int pid=fork(),st,gp=0,i;int evfork=0,evexit=0,gpst=-1,cst=-1,sawgpstop=0;long msg=0,gpmsg=-1;
  if(pid==0){pt(PT_TRACEME,0,0,0);kill(getpid(),SIGSTOP);
    {int g=fork();if(g==0)_exit(9);{int s2;waitpid(g,&s2,0);_exit(0);}}}
  stopped(pid,&st);
  ktest("ptrace.setopt_fork",pt(PT_SETOPTIONS,pid,0,2|1|64)==0);
  pt(PT_CONT,pid,0,0);
  for(i=0;i<40;i++){
    int w=waitpid(-1,&st,WALL);
    if(w<0)break;
    if(WIFEXITED(st)){if(w==pid)cst=WEXITSTATUS(st);else gpst=WEXITSTATUS(st);if(cst>=0&&gpst>=0)break;continue;}
    if(!WIFSTOPPED(st))continue;
    { int ev=(st>>16)&0xff;
      if(w==pid&&ev==1){evfork=1;pt(PT_GETEVENTMSG,w,0,(long)&msg);gp=msg;}
      else if(ev==6){evexit++;if(w!=pid)pt(PT_GETEVENTMSG,w,0,(long)&gpmsg);}
      else if(w!=pid&&WSTOPSIG(st)==SIGSTOP)sawgpstop=1;
      pt(PT_CONT,w,0,0);
    }
  }
  ktest("ptrace.event_fork",evfork&&gp>1&&gp!=pid);
  ktest("ptrace.child_autoattached",sawgpstop);
  ktest("ptrace.event_exit_msg",evexit==2&&gpmsg==(9<<8));
  ktest("ptrace.events_exit_codes",cst==0&&gpst==9);
}

/* 8 : exec event, SETOPTIONS invalide, ESRCH, EPERM, KILL */
static void t_misc(void){
  int pid,st;long msg=0;
  ktest("ptrace.esrch",pt(PT_PEEKDATA,getpid(),(long)&msg,(long)&msg)==-3&&pt(PT_ATTACH,99999,0,0)==-3);
  ktest("ptrace.eperm_self",pt(PT_ATTACH,getpid(),0,0)==-1);
  pid=fork();
  if(pid==0){char*a[]={"/bin/hello",0};char*e[]={"PATH=/bin",0};pt(PT_TRACEME,0,0,0);kill(getpid(),SIGSTOP);execve("/bin/hello",a,e);_exit(99);}
  stopped(pid,&st);
  ktest("ptrace.setoptions_einval",pt(PT_SETOPTIONS,pid,0,0x80000)==-22);
  ktest("ptrace.getregs_efault",pt(PT_GETREGS,pid,0,16)==-5);
  pt(PT_SETOPTIONS,pid,0,16);
  pt(PT_CONT,pid,0,0);
  { int ok=0;
    if(stopped(pid,&st)&&((st>>16)&0xff)==4){pt(PT_GETEVENTMSG,pid,0,(long)&msg);ok=(msg==pid);}
    ktest("ptrace.event_exec",ok); }
  ktest("ptrace.kill",pt(PT_KILL,pid,0,0)==0);
  waitpid(pid,&st,0);
  ktest("ptrace.kill_status",WIFSIGNALED(st)&&WTERMSIG(st)==9);
  ktest("ptrace.after_death_esrch",pt(PT_CONT,pid,0,0)==-3);
}

/* 9 : ATTACH / DETACH, zombie rendu au vrai pere, /proc TracerPid */
static int tracerpid_of(int pid){
  char p[40],b[1024];int fd,n,i,v,k;char t[12];char*q;
  strcpy_(p,"/proc/");q=p+6;v=pid;k=0;
  if(v==0)t[k++]='0';
  while(v){t[k++]='0'+v%10;v/=10;}
  while(k)*q++=t[--k];
  strcpy_(q,"/status");
  fd=open(p,O_RDONLY,0);if(fd<0)return -1;
  n=read(fd,b,sizeof b-1);close(fd);if(n<=0)return -1;b[n]=0;
  for(i=0;i+10<n;i++)if(memcmp_(b+i,"TracerPid:",10)==0){v=0;i+=10;while(b[i]==' '||b[i]=='\t')i++;while(b[i]>='0'&&b[i]<='9')v=v*10+b[i++]-'0';return v;}
  return -2;
}
static void t_attach(void){
  int s1,s2,t,st,fds[2];
  pipe(fds);
  /* S1 : sera detache ; S2 : meurt sous trace */
  s1=fork();if(s1==0){int i;for(i=0;i<60;i++)nap(10);_exit(33);}
  s2=fork();if(s2==0){int i;for(i=0;i<30;i++)nap(10);_exit(44);}
  t=fork();
  if(t==0){
    int ok=1,r;
    if(pt(PT_ATTACH,s1,0,0)!=0)ok=0;
    if(!stopped(s1,&st)||WSTOPSIG(st)!=SIGSTOP)ok=0;
    if(tracerpid_of(s1)!=getpid())ok=0;
    if(pt(PT_DETACH,s1,0,0)!=0)ok=0;
    nap(10);
    if(tracerpid_of(s1)!=0)ok=0;
    /* S2 : attache puis laisse mourir : le traceur recupere l'etat de sortie */
    if(pt(PT_ATTACH,s2,0,0)!=0)ok=0;
    if(!stopped(s2,&st))ok=0;
    pt(PT_CONT,s2,0,0);
    r=waitpid(s2,&st,WALL);
    if(r!=s2||!WIFEXITED(st)||WEXITSTATUS(st)!=44)ok=0;
    { char c=ok?'Y':'N';write(fds[1],&c,1); }
    _exit(0);
  }
  { char c='?';long p[3];struct{int fd;short ev,rev;}pf;pf.fd=fds[0];pf.ev=1;pf.rev=0;(void)p;
    sc3(168,(long)&pf,1,6000);read(fds[0],&c,1);
    ktest("ptrace.attach_detach_tracee_exit",c=='Y'); }
  { int a=0,b=0,r;
    r=waitpid(t,&st,0);a=(r==t&&WIFEXITED(st));
    r=waitpid(s1,&st,0);b=(r==s1&&WIFEXITED(st)&&WEXITSTATUS(st)==33);
    ktest("ptrace.detached_continues",a&&b);
    r=waitpid(s2,&st,0);
    ktest("ptrace.zombie_back_to_parent",r==s2&&WIFEXITED(st)&&WEXITSTATUS(st)==44); }
  close(fds[0]);close(fds[1]);
}

/* 10 : SEIZE + INTERRUPT */
static void t_seize(void){
  int pid=fork(),st;
  if(pid==0){nap(400);_exit(21);}
  nap(20);
  ktest("ptrace.seize",pt(PT_SEIZE,pid,0,0)==0);
  ktest("ptrace.seize_interrupt",pt(PT_INTERRUPT,pid,0,0)==0);
  ktest("ptrace.seize_event_stop",stopped(pid,&st)&&((st>>16)&0xff)==128&&WSTOPSIG(st)==SIGTRAP);
  ktest("ptrace.seize_tracerpid",tracerpid_of(pid)==getpid());
  pt(PT_CONT,pid,0,0);
  waitpid(pid,&st,0);
  ktest("ptrace.seize_resume",WIFEXITED(st)&&WEXITSTATUS(st)==21);
}

/* 11 : le traceur meurt : tracee detache (ou tuee avec EXITKILL) */
static void t_tracer_exit(void){
  int fds[2],kind,pid;
  for(kind=0;kind<2;kind++){
    char c='?';int m,st;
    pipe(fds);
    m=fork();
    if(m==0){
      int ch=fork();
      if(ch==0){pt(PT_TRACEME,0,0,0);kill(getpid(),SIGSTOP);nap(30);write(fds[1],"D",1);_exit(12);}
      stopped(ch,&st);
      if(kind==1)pt(PT_SETOPTIONS,ch,0,0x100000);
      _exit(0);
    }
    waitpid(m,&st,0);
    close(fds[1]);
    { struct{int fd;short ev,rev;}pf;pf.fd=fds[0];pf.ev=1;pf.rev=0;sc3(168,(long)&pf,1,4000);}
    read(fds[0],&c,1);
    close(fds[0]);
    ktest(kind==0?"ptrace.tracer_exit_detaches":"ptrace.exitkill",kind==0?c=='D':c!='D');
    nap(60);
  }
  (void)pid;
}

/* 12 : registres flottants */
static void t_fp(void){
  int pid=fork(),st;
  if(pid==0){
    static const double d=3.5;static unsigned pat[4]={0x11111111,0x22222222,0x33333333,0x44444444};unsigned out[4];
    pt(PT_TRACEME,0,0,0);
    __asm__ volatile("fldl %0\n\tmovups %1,%%xmm0"::"m"(d),"m"(*(unsigned(*)[4])pat):"st");
    kill(getpid(),SIGSTOP);
    __asm__ volatile("movups %%xmm0,%0":"=m"(*(unsigned(*)[4])out)::"memory");
    __asm__ volatile("fstp %%st(0)":::"st");
    _exit(out[0]==0x7777&&out[1]==0x22222222?0:1);
  }
  stopped(pid,&st);
  { unsigned char fp[108];unsigned char fx[512];unsigned long long mant;unsigned short ex;
    memset(fp,0,sizeof fp);
    ktest("ptrace.getfpregs",pt(PT_GETFPREGS,pid,0,(long)fp)==0);
    memcpy(&mant,fp+28,8);memcpy(&ex,fp+36,2);
    ktest("ptrace.fp_st0",mant==0xE000000000000000ULL&&ex==0x4000);
    ktest("ptrace.getfpxregs",pt(PT_GETFPXREGS,pid,0,(long)fx)==0&&*(unsigned*)(fx+160)==0x11111111&&*(unsigned*)(fx+164)==0x22222222);
    *(unsigned*)(fx+160)=0x7777;
    ktest("ptrace.setfpxregs",pt(PT_SETFPXREGS,pid,0,(long)fx)==0);
  }
  pt(PT_CONT,pid,0,0);
  waitpid(pid,&st,0);
  ktest("ptrace.fp_modified_seen",WIFEXITED(st)&&WEXITSTATUS(st)==0);
}

/* 13 : SYSEMU : un appel systeme emule par le traceur */
static void t_sysemu(void){
  int pid=fork(),st;struct regs r;int got=0,i;
  if(pid==0){pt(PT_TRACEME,0,0,0);kill(getpid(),SIGSTOP);{long v=sc0(SYS_getpid);_exit(v==0x1234?0:1);}}
  stopped(pid,&st);
  for(i=0;i<8;i++){
    pt(PT_SYSEMU,pid,0,0);
    if(!stopped(pid,&st))break;
    pt(PT_GETREGS,pid,0,(long)&r);
    if(r.orig_eax==20){r.eax=0x1234;pt(PT_SETREGS,pid,0,(long)&r);got=1;pt(PT_CONT,pid,0,0);break;}
  }
  ktest("ptrace.sysemu_stop",got==1);
  waitpid(pid,&st,0);
  ktest("ptrace.sysemu_result",WIFEXITED(st)&&WEXITSTATUS(st)==0);
}

int main(void){
  t_basic();
  t_inject();
  t_strace();
  t_step();
  t_bp();
  t_hw();
  t_events();
  t_misc();
  t_attach();
  t_seize();
  t_tracer_exit();
  t_fp();
  t_sysemu();
  puts("ptrace DONE\n");
  return ku_fail?1:0;
}
