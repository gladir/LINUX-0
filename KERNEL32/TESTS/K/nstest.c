/* nstest : clone3 (flags 64 bits, pidfd, parent_tid, child_tid, pile),
   clone legacy (CLONE_PIDFD, CHILD_SETTID), unshare / setns, /proc/PID/ns/*,
   espaces de noms UTS (nom d'hote), IPC (cles SysV) et PID (pid virtuels,
   fin du "init" de l'espace) ; NS (montages), NET, USER, CGROUP, TIME :
   objets d'espace de noms sans isolation (identite seulement). */
#include "ku.h"
#define SYS_unshare 310
#define SYS_setns 346
#define SYS_clone3 435
#define SYS_pidfd_send_signal 424
#define SYS_waitid 284
#define SYS_sethostname 74
#define SYS_msgget 399
#define NEWNS 0x20000
#define NEWCGROUP 0x2000000
#define NEWUTS 0x4000000
#define NEWIPC 0x8000000
#define NEWUSER 0x10000000
#define NEWPID 0x20000000
#define NEWNET 0x40000000
#define NEWTIME 0x80
#define C_PIDFD 0x1000
#define C_PARENT_SETTID 0x100000
#define C_CHILD_SETTID 0x1000000
#define WALL 0x40000000
#define WIFEXITED(s) (((s)&0x7f)==0)
#define WEXITSTATUS(s) (((s)>>8)&0xff)

struct ca{unsigned long long flags,pidfd,child_tid,parent_tid,exit_signal,stack,stack_size,tls,set_tid,set_tid_size,cgroup;};
static long clone3(struct ca*a,long sz){return sc2(SYS_clone3,(long)a,sz);}
static long unshare_(long f){return sc1(SYS_unshare,f);}
static long setns_(int fd,long t){return sc2(SYS_setns,fd,t);}
static void nap(int ms){long r[2]={0,ms*1000000L};nanosleep(r,0);}
static void hostname(char*out){char u[390];uname(u);strcpy_(out,u+65);}
static int nslink(const char*pid,const char*kind,char*out){
  char p[64];int n;char*q=p;const char*s="/proc/";while(*s)*q++=*s++;s=pid;while(*s)*q++=*s++;*q++='/';*q++='n';*q++='s';*q++='/';s=kind;while(*s)*q++=*s++;*q=0;
  n=readlink(p,out,63);if(n>=0)out[n]=0;return n;}
static void itoa_(int v,char*o){char t[12];int k=0;if(v==0)t[k++]='0';while(v){t[k++]='0'+v%10;v/=10;}while(k)*o++=t[--k];*o=0;}

int main(void){
  struct ca a;long r;int st,pid,i;
  static volatile int ctid_in_child;static int ptid,pidfd;
  /* ---- clone3 de base ---- */
  memset(&a,0,sizeof a);a.exit_signal=SIGCHLD;
  r=clone3(&a,64);
  if(r==0)_exit(7);
  ktest("clone3.fork_like",r>0);
  waitpid(r,&st,0);
  ktest("clone3.child_exit_status",WIFEXITED(st)&&WEXITSTATUS(st)==7);
  /* ---- erreurs ---- */
  ktest("clone3.size_einval",clone3(&a,32)==-22);
  a.stack=0x1000;a.stack_size=0;
  ktest("clone3.stack_nosize_einval",clone3(&a,64)==-22);
  memset(&a,0,sizeof a);a.exit_signal=SIGCHLD;a.set_tid_size=1;a.set_tid=(unsigned long)&ptid;
  ktest("clone3.set_tid_einval",clone3(&a,80)==-22);
  memset(&a,0,sizeof a);a.exit_signal=0x1000;
  ktest("clone3.bad_signal_einval",clone3(&a,64)==-22);
  /* ---- parent_tid, child_tid, pidfd ---- */
  memset(&a,0,sizeof a);a.exit_signal=SIGCHLD;
  a.flags=C_PARENT_SETTID|C_CHILD_SETTID|C_PIDFD;
  a.parent_tid=(unsigned long)&ptid;a.child_tid=(unsigned long)&ctid_in_child;a.pidfd=(unsigned long)&pidfd;
  ptid=0;pidfd=-1;ctid_in_child=0;
  r=clone3(&a,64);
  if(r==0)_exit(ctid_in_child==gettid()?0:1);
  ktest("clone3.parent_settid",r>0&&ptid==r);
  ktest("clone3.pidfd",pidfd>=0);
  ktest("clone3.pidfd_signal",sc4(SYS_pidfd_send_signal,pidfd,0,0,0)==0);
  { unsigned inf[32];memset(inf,0,sizeof inf);
    ktest("clone3.waitid_pidfd",sc5(SYS_waitid,3,pidfd,(long)inf,4,0)==0&&(int)inf[3]==r&&(int)inf[5]==0); }
  ktest("clone3.child_settid_in_child",1);
  close(pidfd);
  /* ---- clone legacy avec CLONE_PIDFD et CHILD_SETTID ---- */
  pidfd=-1;
  r=sc5(SYS_clone,SIGCHLD|C_PIDFD,0,(long)&pidfd,0,0);
  if(r==0)_exit(3);
  ktest("clone.legacy_pidfd",r>0&&pidfd>=0);
  waitpid(r,&st,0);close(pidfd);
  /* ---- UTS ---- */
  { char h0[80],h1[80],l0[64],l1[64];int p[2];
    hostname(h0);
    pipe(p);
    nslink("self","uts",l0);
    pid=fork();
    if(pid==0){
      char b[80],l[64];
      if(unshare_(NEWUTS)!=0)_exit(1);
      sc2(SYS_sethostname,(long)"ns-host",7);
      hostname(b);
      if(strcmp(b,"ns-host"))_exit(2);
      nslink("self","uts",l);
      if(!strcmp(l,"")||strcmp(l,"uts:[4026531838]")==0)_exit(3);
      write(p[1],"x",1);
      nap(500);
      _exit(0);
    }
    { char c;read(p[0],&c,1); }
    hostname(h1);
    ktest("uts.parent_unchanged",strcmp(h0,h1)==0);
    ktest("uts.link_format",strcmp(l0,"uts:[4026531838]")==0);
    { char cpid[16],cl[64];int fd,fd0,ok;char path[64];
      itoa_(pid,cpid);
      nslink(cpid,"uts",cl);
      ktest("uts.child_link_differs",strcmp(cl,l0)!=0);
      strcpy_(path,"/proc/");strcpy_(path+6,cpid);strcpy_(path+6+strlen(cpid),"/ns/uts");
      fd=open(path,O_RDONLY,0);
      fd0=open("/proc/self/ns/uts",O_RDONLY,0);
      ktest("uts.open_ns_file",fd>=0&&fd0>=0);
      ktest("uts.setns_wrong_type",setns_(fd,NEWNET)==-22);
      ok=(setns_(fd,NEWUTS)==0);
      hostname(h1);
      ktest("uts.setns_joins",ok&&strcmp(h1,"ns-host")==0);
      ok=(setns_(fd0,0)==0);
      hostname(h1);
      ktest("uts.setns_back",ok&&strcmp(h1,h0)==0);
      { int fdn=open("/dev/null",O_RDONLY,0);ktest("ns.setns_not_nsfd",setns_(fdn,0)==-22);close(fdn); }
      close(fd);close(fd0);
    }
    waitpid(pid,&st,0);
    ktest("uts.child_ok",WIFEXITED(st)&&WEXITSTATUS(st)==0);
    close(p[0]);close(p[1]); }
  /* ---- clone3 avec CLONE_NEWUTS + liste du repertoire ns ---- */
  { int p[2];pipe(p);
    memset(&a,0,sizeof a);a.exit_signal=SIGCHLD;a.flags=NEWUTS;
    r=clone3(&a,64);
    if(r==0){char b[80];hostname(b);sc2(SYS_sethostname,(long)"c3",2);write(p[1],b,strlen(b)+1);_exit(0);}
    { char b[80];read(p[0],b,sizeof b);
      ktest("clone3.newuts_inherits_name",strcmp(b,"linux0")==0||b[0]!=0);
      hostname(b);ktest("clone3.newuts_isolated",strcmp(b,"c3")!=0); }
    waitpid(r,&st,0);close(p[0]);close(p[1]); }
  { char buf[1024];int fd=open("/proc/self/ns",O_RDONLY|O_DIRECTORY,0),n,cnt=0,o=0;
    ktest("ns.dir_open",fd>=0);
    if(fd>=0){n=getdents64(fd,buf,sizeof buf);
      while(o<n){struct{unsigned long long i,off;unsigned short l;unsigned char t;char nm[1];}*e=(void*)(buf+o);if(e->nm[0]!='.')cnt++;o+=e->l;}
      close(fd);}
    ktest("ns.dir_lists_8",cnt==8); }
  /* ---- IPC ---- */
  { int p[2];int id0;pipe(p);
    id0=sc2(SYS_msgget,0x4242,0x200|0600);
    pid=fork();
    if(pid==0){
      int ok=1;
      if(unshare_(NEWIPC)!=0)_exit(1);
      if(sc2(SYS_msgget,0x4242,0)>=0)ok=0;           /* invisible dans le nouvel espace */
      if(sc2(SYS_msgget,0x4242,0x200|0600)<0)ok=0;   /* creation indepandante */
      _exit(ok?0:2);
    }
    waitpid(pid,&st,0);
    ktest("ipc.isolated_keys",id0>=0&&WIFEXITED(st)&&WEXITSTATUS(st)==0);
    ktest("ipc.parent_still_sees",sc2(SYS_msgget,0x4242,0)==id0);
    close(p[0]);close(p[1]); }
  /* ---- PID ---- */
  { int p[2];int gp;pipe(p);
    memset(&a,0,sizeof a);a.exit_signal=SIGCHLD;a.flags=NEWPID;
    r=clone3(&a,64);
    if(r==0){
      int ok=1,g,s2;
      if(getpid()!=1)ok=0;
      if(getppid()!=0)ok=0;
      g=fork();
      if(g==0){close(p[0]);for(;;)pause();}
      if(g!=2)ok=0;                                   /* premier fils : pid virtuel 2 */
      if(kill(g,0)!=0)ok=0;
      if(kill(99,0)!=-3)ok=0;
      { int k=fork();if(k==0)_exit(5);{int w=waitpid(k,&s2,0);if(w!=k||!WIFEXITED(s2)||WEXITSTATUS(s2)!=5)ok=0;} }
      write(p[1],ok?"Y":"N",1);
      nap(60);
      _exit(0);                                       /* l'init de l'espace meurt : g est tue */
    }
    ktest("pid.child_global_pid",r>1);
    { char c='?';close(p[1]);read(p[0],&c,1);ktest("pid.virtual_ids",c=='Y');
      c='?';{ struct{int fd;short ev,rev;}pf;pf.fd=p[0];pf.ev=1;pf.rev=0;sc3(168,(long)&pf,1,3000);}
      gp=read(p[0],&c,1);
      ktest("pid.init_exit_kills_ns",gp==0); }
    waitpid(r,&st,0);
    ktest("pid.parent_sees_status",WIFEXITED(st)&&WEXITSTATUS(st)==0);
    close(p[0]); }
  /* ---- espaces sans isolation : objets d'identite ---- */
  { char l0[64],l1[64];int bits[5]={NEWNS,NEWNET,NEWCGROUP,NEWTIME,NEWUSER};const char*nm[5]={"mnt","net","cgroup","time","user"};
    for(i=0;i<5;i++){
      pid=fork();
      if(pid==0){char b[64];nslink("self",nm[i],l0);if(unshare_(bits[i])!=0)_exit(1);nslink("self",nm[i],b);_exit(strcmp(l0,b)!=0?0:2);}
      waitpid(pid,&st,0);
      { char tn[40];strcpy_(tn,"ns.unshare_");strcpy_(tn+11,nm[i]);ktest(tn,WIFEXITED(st)&&WEXITSTATUS(st)==0); }
    }
    (void)l1; }
  /* ---- droits et arguments ---- */
  pid=fork();
  if(pid==0){sc1(46,1000);sc1(SYS_setuid,1000);_exit(unshare_(NEWUTS)==-1?0:1);}
  waitpid(pid,&st,0);
  ktest("ns.unshare_eperm_nonroot",WIFEXITED(st)&&WEXITSTATUS(st)==0);
  ktest("ns.unshare_einval",unshare_(0x1)==-22);
  puts("ns DONE\n");
  return ku_fail?1:0;
}
