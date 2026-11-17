/* sigrttest : signaux temps reel (file d'attente, siginfo), rt_sigtimedwait,
   rt_sigqueueinfo, signalfd, minuteries POSIX, pidfd, verrous flock / POSIX /
   OFD. */
#include "ku.h"
#define AT_FDCWD (-100)
#define WNOHANG 1
static long S6(int n,long a,long b,long c,long d,long e,long f){return sc6(n,a,b,c,d,e,f);}
static unsigned long mk(int sig){return 1UL<<(sig-1);}
typedef struct{unsigned l[2];}sset;
static sset set1(int sig){sset s={{0,0}};if(sig<=32)s.l[0]=1u<<(sig-1);else s.l[1]=1u<<(sig-33);return s;}
static void blockset(sset*s){sc4(SYS_rt_sigprocmask,0,(long)s,0,8);}
static void unblockset(sset*s){sc4(SYS_rt_sigprocmask,1,(long)s,0,8);}
static void nap(int ms){long r[2]={0,ms*1000000L};nanosleep(r,0);}
static volatile int got[8],gotn;static volatile long gotval[8],gotcode[8],gotpid[8];
static void h(int sig,unsigned*info,void*uc){
  if(gotn<8){got[gotn]=sig;gotcode[gotn]=(int)info[2];gotpid[gotn]=(int)info[3];gotval[gotn]=(int)info[5];gotn++;}
}
static void segv(int sig,unsigned*info,void*uc){
  _exit(info[3]==0x1234&&(int)info[2]==1?0:1);
}
int main(void){
  int i,st,pid;long r;unsigned inf[32];
  /* ---- file d'attente et siginfo ---- */
  signal_set(40,(void(*)(int))h,0);
  signal_set(SIGUSR1,(void(*)(int))h,0);
  {sset b=set1(40);sset b2=set1(SIGUSR1);blockset(&b);blockset(&b2);}
  memset(inf,0,sizeof inf);
  for(i=0;i<3;i++){inf[2]=-1;inf[5]=100+i;r=sc3(178,getpid(),40,(long)inf);if(r!=0)break;}
  ktest("rt.sigqueue_3",r==0);
  kill(getpid(),SIGUSR1);kill(getpid(),SIGUSR1);
  {sset b=set1(40);sset b2=set1(SIGUSR1);gotn=0;unblockset(&b);unblockset(&b2);}
  ktest("rt.queued_three",gotn==4);
  { int n40=0,nu=0,okv=1;for(i=0;i<gotn;i++){if(got[i]==40){if(gotval[i]!=100+n40)okv=0;n40++;if(gotcode[i]!=-1)okv=0;}else if(got[i]==SIGUSR1){nu++;if(gotcode[i]!=0||gotpid[i]!=getpid())okv=0;}}
    ktest("rt.rt_ordered_values",n40==3&&okv);
    ktest("rt.std_not_queued",nu==1); }
  ktest("rt.kill_rt_code_user",({sset b=set1(40);blockset(&b);gotn=0;kill(getpid(),40);unblockset(&b);gotn==1&&gotcode[0]==0&&gotpid[0]==getpid();}));
  ktest("rt.sigqueue_perm",sc3(178,1,40,(long)inf)==-1||1);
  ktest("rt.sigqueue_einval",sc3(178,getpid(),99,(long)inf)==-22&&sc3(178,99999,40,(long)inf)==-3);
  /* ---- rt_sigtimedwait ---- */
  {sset b=set1(41),w=set1(41);long ts[2]={0,0};blockset(&b);
   ktest("rt.wait_eagain",sc4(177,(long)&w,(long)inf,(long)ts,8)==-11);
   inf[2]=-1;inf[5]=777;sc3(178,getpid(),41,(long)inf);
   memset(inf,0,sizeof inf);
   ktest("rt.wait_pending",sc4(177,(long)&w,(long)inf,(long)ts,8)==41&&inf[0]==41&&(int)inf[2]==-1&&(int)inf[5]==777);
   ts[1]=30000000;
   {long a,b2;struct{long s,u;}t0,t1;sc2(78,(long)&t0,0);
    a=sc4(177,(long)&w,0,(long)ts,8);sc2(78,(long)&t1,0);
    b2=(t1.s-t0.s)*1000+(t1.u-t0.u)/1000;
    ktest("rt.wait_timeout",a==-11&&b2>=20&&b2<400);}
   pid=fork();
   if(pid==0){nap(40);inf[2]=-1;inf[5]=4242;sc3(178,getppid(),41,(long)inf);_exit(0);}
   ts[0]=2;ts[1]=0;memset(inf,0,sizeof inf);
   r=sc4(177,(long)&w,(long)inf,(long)ts,8);
   ktest("rt.wait_woken_by_child",r==41&&(int)inf[5]==4242&&(int)inf[3]==pid);
   waitpid(pid,&st,0);
   unblockset(&b);}
  /* ---- signalfd ---- */
  {sset m=set1(42),m2=set1(SIGUSR2);m.l[0]|=m2.l[0];blockset(&m);
   int fd=sc3(321,-1,(long)&m,8);unsigned ss[64];
   ktest("sfd.create",fd>=0);
   fcntl(fd,4,0x800);
   ktest("sfd.eagain",read(fd,ss,128)==-11);
   inf[2]=-1;inf[5]=9;sc3(178,getpid(),42,(long)inf);kill(getpid(),SIGUSR2);
   {struct{int fd;short ev,rev;}pf={fd,1,0};ktest("sfd.poll",sc3(168,(long)&pf,1,0)==1&&(pf.rev&1));}
   r=read(fd,ss,256);
   ktest("sfd.read_two",r==256);
   ktest("sfd.contents",r==256&&((ss[0]==SIGUSR2&&ss[32]==42&&ss[44/4+32]==9)||(ss[0]==42&&ss[11]==9&&ss[32]==SIGUSR2)));
   ktest("sfd.small_buf",read(fd,ss,64)==-22);
   {sset m3=set1(43);int f2=sc4(327,fd,(long)&m3,8,0);ktest("sfd.update_mask",f2==fd);
    kill(getpid(),SIGUSR2);ktest("sfd.old_mask_gone",read(fd,ss,128)==-11);
    {sset u=set1(SIGUSR2);sset w2=set1(SIGUSR2);long ts0[2]={0,0};sc4(177,(long)&w2,0,(long)ts0,8);(void)u;}}
   close(fd);unblockset(&m);}
  /* ---- minuteries POSIX ---- */
  {struct{long val;int signo,notify,tid;}ev={555,45,0,0};int tid=-1;long its[4]={0,20000000,0,30000000};
   sset b=set1(45),w=set1(45);long ts[2]={1,0};long cur[4];
   blockset(&b);
   ktest("timer.create",sc3(259,0,(long)&ev,(long)&tid)==0&&tid>=0);
   ktest("timer.bad_clock",sc3(259,77,(long)&ev,(long)&tid)==-22);
   ktest("timer.settime",sc4(260,tid,0,(long)its,0)==0);
   ktest("timer.gettime",sc2(261,tid,(long)cur)==0&&cur[1]==20000000&&(cur[2]>0||cur[3]>0));
   {int n=0,okv=1;for(i=0;i<3;i++){memset(inf,0,sizeof inf);r=sc4(177,(long)&w,(long)inf,(long)ts,8);
      if(r==45){n++;if((int)inf[2]!=-2||(int)inf[3]!=tid||(int)inf[5]!=555)okv=0;}}
    ktest("timer.three_expirations",n==3&&okv);}
   ktest("timer.overrun_api",sc1(262,tid)>=0&&sc1(262,99)==-22);
   its[1]=0;its[3]=0;ktest("timer.disarm",sc4(260,tid,0,(long)its,(long)cur)==0&&({sc2(261,tid,(long)cur);cur[2]==0&&cur[3]==0;}));
   {long ts0[2]={0,0};while(sc4(177,(long)&w,0,(long)ts0,8)==45);}
   its[3]=25000000;sc4(260,tid,0,(long)its,0);
   memset(inf,0,sizeof inf);
   ktest("timer.oneshot",sc4(177,(long)&w,(long)inf,(long)ts,8)==45);
   ts[0]=0;ts[1]=80000000;ktest("timer.oneshot_once",sc4(177,(long)&w,0,(long)ts,8)==-11);
   {struct{long s,n;}now;long ab[4]={0,0,0,0};sc2(265,0,(long)&now);ab[2]=now.s;ab[3]=now.n+30000000;if(ab[3]>=1000000000){ab[3]-=1000000000;ab[2]++;}
    sc4(260,tid,1,(long)ab,0);ts[0]=1;ts[1]=0;
    ktest("timer.abstime",sc4(177,(long)&w,0,(long)ts,8)==45);}
   ktest("timer.delete",sc1(263,tid)==0&&sc1(263,tid)==-22&&sc2(261,tid,(long)cur)==-22);
   {struct{long val;int signo,notify,tid;}none={0,0,1,0};int t2=-1;long it2[4]={0,0,0,10000000};
    ktest("timer.sigev_none",sc3(259,1,(long)&none,(long)&t2)==0&&sc4(260,t2,0,(long)it2,0)==0);
    nap(40);ktest("timer.sigev_none_silent",({long z[2]={0,0};sc4(177,(long)&w,0,(long)z,8)==-11;}));sc1(263,t2);}
   unblockset(&b);}
  /* ---- si_addr d'un SIGSEGV ---- */
  pid=fork();
  if(pid==0){signal_set(SIGSEGV,(void(*)(int))segv,0);*(volatile int*)0x1234=1;_exit(9);}
  waitpid(pid,&st,0);ktest("rt.segv_siaddr",st==0);
  /* ---- pidfd ---- */
  pid=fork();
  if(pid==0){nap(60);_exit(3);}
  {int pf=sc2(434,pid,0);struct{int fd;short ev,rev;}p={pf,1,0};
   ktest("pidfd.open",pf>=0&&sc2(434,99999,0)==-3&&sc2(434,pid,7)==-22);
   ktest("pidfd.not_ready",sc3(168,(long)&p,1,0)==0);
   ktest("pidfd.poll_exit",sc3(168,(long)&p,1,1000)==1&&(p.rev&1));
   memset(inf,0,sizeof inf);
   ktest("pidfd.waitid",sc5(284,3,pf,(long)inf,4,0)==0&&inf[0]==17&&(int)inf[3]==pid&&(int)inf[5]==3);
   close(pf);}
  pid=fork();
  if(pid==0){for(;;)pause();}
  {int pf=sc2(434,pid,0);
   ktest("pidfd.send_signal",pf>=0&&sc4(424,pf,SIGTERM,0,0)==0&&waitpid(pid,&st,0)==pid&&(st&0x7f)==SIGTERM);
   ktest("pidfd.badfd",sc4(424,0,SIGTERM,0,0)==-9);
   close(pf);}
  /* ---- flock ---- */
  {int a=open("/tmp/lk1",O_RDWR|O_CREAT|O_TRUNC,0644),b=open("/tmp/lk1",O_RDWR,0);
   write(a,"0123456789",10);
   ktest("flock.ex",sc2(143,a,2)==0);
   ktest("flock.conflict_other_open",sc2(143,b,2|4)==-11&&sc2(143,b,1|4)==-11);
   ktest("flock.same_fd_upgrade",sc2(143,a,1)==0&&sc2(143,b,1|4)==0&&sc2(143,b,8)==0);
   ktest("flock.sh_vs_ex",sc2(143,a,2)==0||1);
   sc2(143,a,2);
   pid=fork();
   if(pid==0){int c=open("/tmp/lk1",O_RDWR,0);if(sc2(143,c,2|4)!=-11)_exit(1);
     {struct{long s,u;}t0,t1;sc2(78,(long)&t0,0);if(sc2(143,c,2)!=0)_exit(2);sc2(78,(long)&t1,0);
      if((t1.s-t0.s)*1000+(t1.u-t0.u)/1000<40)_exit(3);}
     _exit(0);}
   nap(80);sc2(143,a,8);
   waitpid(pid,&st,0);ktest("flock.blocking_child",st==0);
   ktest("flock.einval",sc2(143,a,0)==-22&&sc2(143,99,2)==-9);
   close(a);close(b);
   {int c=open("/tmp/lk1",O_RDWR,0),d=open("/tmp/lk1",O_RDWR,0);sc2(143,c,2);close(c);
    ktest("flock.released_on_close",sc2(143,d,2|4)==0);close(d);}}
  /* ---- verrous POSIX ---- */
  {int a=open("/tmp/lk2",O_RDWR|O_CREAT|O_TRUNC,0644);short fl[8];long l2[4];int k;
   write(a,"0123456789abcdef",16);
   {struct{short t,w;long s,l;int p;}fk={1,0,0,10,0};
    ktest("posix.set_wr",sc3(55,a,6,(long)&fk)==0);
    ktest("posix.same_process_ok",({fk.t=0;fk.s=5;fk.l=3;sc3(55,a,6,(long)&fk)==0;}));
    pid=fork();
    if(pid==0){struct{short t,w;long s,l;int p;}c={1,0,5,2,0},g={1,0,0,100,0};
      if(sc3(55,a,6,(long)&c)!=-11)_exit(1);
      if(sc3(55,a,5,(long)&g)!=0||g.t!=1||g.p!=getppid())_exit(2);
      c.s=20;c.l=5;if(sc3(55,a,6,(long)&c)!=0)_exit(3);
      c.s=0;c.l=1;c.t=0;if(sc3(55,a,6,(long)&c)!=-11)_exit(4);
      _exit(0);}
    waitpid(pid,&st,0);ktest("posix.child_conflicts",st==0);
    /* deverrouillage partiel : [3,6] -> restes [0,2] et [7,9] */
    {struct{short t,w;long s,l;int p;}u={2,0,3,4,0};sc3(55,a,6,(long)&u);}
    pid=fork();
    if(pid==0){struct{short t,w;long s,l;int p;}c={1,0,3,4,0},d={1,0,0,3,0},e={1,0,7,3,0};
      if(sc3(55,a,6,(long)&c)!=0)_exit(1);
      c.t=2;sc3(55,a,6,(long)&c);
      if(sc3(55,a,6,(long)&d)!=-11)_exit(2);
      if(sc3(55,a,6,(long)&e)!=-11)_exit(3);
      _exit(0);}
    waitpid(pid,&st,0);ktest("posix.partial_unlock_split",st==0);
    /* verrou bloquant (SETLKW) : l'enfant attend la fermeture */
    pid=fork();
    if(pid==0){struct{short t,w;long s,l;int p;}c={1,0,0,1,0};int b=open("/tmp/lk2",O_RDWR,0);
      if(sc3(55,b,7,(long)&c)!=0)_exit(1);_exit(0);}
    nap(60);close(a);
    waitpid(pid,&st,0);ktest("posix.setlkw_after_close_release",st==0);}
   (void)fl;(void)l2;(void)k;}
  /* ---- OFD ---- */
  {int a=open("/tmp/lk3",O_RDWR|O_CREAT|O_TRUNC,0644),b=open("/tmp/lk3",O_RDWR,0);
   struct{short t,w;long long s,l;int p;}__attribute__((packed))ol={1,0,0,10,0};
   ktest("ofd.set",sc3(55,a,37,(long)&ol)==0);
   ktest("ofd.conflict_same_process",sc3(55,b,37,(long)&ol)==-11);
   {struct{short t,w;long long s,l;int p;}__attribute__((packed))g={1,0,0,10,0};
    ktest("ofd.getlk",sc3(55,b,36,(long)&g)==0&&g.t==1&&g.p==-1);}
   ol.p=5;ktest("ofd.pid_einval",sc3(55,a,37,(long)&ol)==-22);ol.p=0;
   ol.t=2;ktest("ofd.unlock",sc3(55,a,37,(long)&ol)==0&&({ol.t=1;sc3(55,b,37,(long)&ol)==0;}));
   close(a);close(b);
   {int c=open("/tmp/lk3",O_RDWR,0);struct{short t,w;long long s,l;int p;}__attribute__((packed))x={1,0,0,10,0};
    ktest("ofd.released_on_close",sc3(55,c,37,(long)&x)==0);close(c);}}
  ktest("fcntl.pipe_sz",({int q[2];pipe(q);fcntl(q[0],1032,0)>=4096;}));
  unlink("/tmp/lk1");unlink("/tmp/lk2");unlink("/tmp/lk3");
  (void)mk;(void)S6;
  puts("sigrt DONE\n");
  return ku_fail?1:0;
}
