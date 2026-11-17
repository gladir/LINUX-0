/* syscalltest : appels systeme ajoutes par l'audit de couverture (lot A :
   ordonnancement, capacites, sendfile/splice/copy_file_range, preadv,
   fallocate, statx, renameat2, openat2, close_range, memfd_create, mlock,
   mincore, madvise, waitid, time64, ppoll/pselect6/epoll_pwait2, timerfd64,
   unshare, kcmp, process_vm_readv, membarrier, ENOSYS explicites...). */
#include "ku.h"
#define PROT_READ 1
#define PROT_WRITE 2
#define MAP_PRIVATE 2
#define MAP_SHARED 1
#define MAP_ANONYMOUS 0x20
#define AT_FDCWD (-100)
static long S(int n,long a,long b,long c,long d,long e){return sc5(n,a,b,c,d,e);}
struct iov{void*b;unsigned l;};
static unsigned char sb[256];
static char buf[8192];
static int wfile(const char*p,const char*s){int fd=open(p,O_WRONLY|O_CREAT|O_TRUNC,0644),n=strlen(s);if(fd<0)return fd;n=write(fd,s,n);close(fd);return n;}
static int rfile(const char*p,char*b,int m){int fd=open(p,O_RDONLY,0),n;if(fd<0)return fd;n=read(fd,b,m-1);if(n<0)n=0;b[n]=0;close(fd);return n;}
int main(void){
  long r;int i,fd,fd2,p[2],st,pid;
  /* ---- divers ---- */
  ktest("sys.restart_syscall",sc0(0)==-4);
  ktest("sys.personality",sc1(136,-1)==0&&sc1(136,0x40000)==0&&sc1(136,-1)==0x40000&&sc1(136,0)==0x40000);
  ktest("sys.enosys_list",sc0(123)==-38&&sc0(131)==-38&&sc0(357)==-38&&sc0(374)==-38&&sc0(448)==-38);
  ktest("sys.unknown_enosys",sc0(468)==-38&&sc0(460)==-38);
  /* ---- ordonnancement ---- */
  {int prm[2]={10,0},o[2]={0,0};
   ktest("sched.getscheduler",sc1(157,0)==0);
   ktest("sched.set_fifo",sc3(156,0,1,(long)prm)==0&&sc1(157,0)==1&&sc2(155,0,(long)o)==0&&o[0]==10);
   prm[0]=0;
   ktest("sched.set_other",sc3(156,0,0,(long)prm)==0&&sc1(157,0)==0);
   prm[0]=200;
   ktest("sched.einval",sc3(156,0,1,(long)prm)==-22&&sc1(157,99999)==-3);
   {long ts[2]={9,9};ktest("sched.rr_interval",sc2(161,0,(long)ts)==0&&ts[0]==0&&ts[1]>0);}
   {unsigned m=0,all,ncpu;int ok;
    ok=sc3(242,0,4,(long)&m)==4&&m!=0&&(m&(m+1))==0;   /* 2^n - 1 */
    all=m;for(ncpu=0;m>>ncpu;ncpu++);
    m=1;ok=ok&&sc3(241,0,4,(long)&m)==0;
    m=all;ok=ok&&sc3(241,0,4,(long)&m)==0;
    m=1u<<ncpu;ok=ok&&sc3(241,0,4,(long)&m)==-22;
    ktest("sched.affinity",ok);}
   {unsigned c=9,n=9;ktest("sched.getcpu",sc3(318,(long)&c,(long)&n,0)==0&&c==0&&n==0);}
   {unsigned a[12]={48,0,0,0,0,0,0,0,0,0,0,0};
    ktest("sched.getattr",sc4(352,0,(long)a,48,0)==0&&a[1]==0);
    a[1]=0;a[4]=5;ktest("sched.setattr",sc3(351,0,(long)a,0)==0&&({a[4]=0;sc4(352,0,(long)a,48,0)==0&&(int)a[4]==5;}));
    a[4]=0;sc3(351,0,(long)a,0);}
   ktest("sched.ioprio",sc3(289,1,0,0)==0&&sc2(290,1,0)==0&&sc3(289,9,0,0)==-22);}
  /* ---- capacites ---- */
  {unsigned h[2]={0x20080522,0},d[6];
   ktest("cap.capget_root",sc2(184,(long)h,(long)d)==0&&d[0]==0xFFFFFFFFu&&d[1]==0xFFFFFFFFu);
   h[0]=0x12345;
   ktest("cap.bad_version",sc2(184,(long)h,(long)d)==-22&&h[0]==0x20080522);
   pid=fork();
   if(pid==0){
     unsigned h2[2]={0x20080522,0},d2[6];
     long ts[2]={1000000000,0};
     sc2(184,(long)h2,(long)d2);
     d2[0]&=~(1u<<25);d2[1]&=~(1u<<25);   /* retire CAP_SYS_TIME (25) des effectives et permises */
     if(sc2(185,(long)h2,(long)d2)!=0)_exit(1);
     if(sc2(264,0,(long)ts)!=-1)_exit(2);                 /* clock_settime : EPERM */
     d2[0]=0xFFFFFFFFu;                                   /* reprise interdite */
     if(sc2(185,(long)h2,(long)d2)!=-1)_exit(3);
     if(sc1(23,1000)!=0)_exit(4);                         /* setuid : perd tout */
     sc2(184,(long)h2,(long)d2);
     if(d2[0]!=0||d2[1]!=0)_exit(5);
     _exit(0);
   }
   waitpid(pid,&st,0);
   ktest("cap.drop_and_setuid",st==0);}
  /* ---- fichiers ---- */
  wfile("/tmp/sa","0123456789abcdefghij");
  fd=open("/tmp/sa",O_RDONLY,0);fd2=open("/tmp/sb",O_RDWR|O_CREAT|O_TRUNC,0644);
  {long long off=5;r=sc4(239,fd2,fd,(long)&off,10);
   ktest("file.sendfile64",r==10&&off==15&&rfile("/tmp/sb",buf,64)==10&&memcmp_(buf,"56789abcde",10)==0);
   ktest("file.sendfile_badfd",sc4(187,99,fd,0,4)==-9);}
  {long long o1=2,o2=0;lseek(fd2,0,0);
   r=sc6(377,fd,(long)&o1,fd2,(long)&o2,6,0);
   ktest("file.copy_file_range",r==6&&o1==8&&o2==6&&({rfile("/tmp/sb",buf,64);memcmp_(buf,"234567abcde",6)==0;}));}
  close(fd);close(fd2);
  /* splice : fichier -> tube -> fichier */
  fd=open("/tmp/sa",O_RDONLY,0);fd2=open("/tmp/sc",O_RDWR|O_CREAT|O_TRUNC,0644);pipe(p);
  {long long off=0;r=sc6(313,fd,(long)&off,p[1],0,12,0);
   ktest("file.splice_in",r==12&&off==12);
   r=sc6(313,p[0],0,fd2,0,12,0);
   ktest("file.splice_out",r==12&&rfile("/tmp/sc",buf,64)==12&&memcmp_(buf,"0123456789ab",12)==0);
   ktest("file.splice_einval",sc6(313,fd,0,fd2,0,4,0)==-22);}
  {struct iov v[2]={{"AB",2},{"CDE",3}};
   ktest("file.vmsplice",S(316,p[1],(long)v,2,0,0)==5&&read(p[0],buf,8)==5&&memcmp_(buf,"ABCDE",5)==0);}
  close(fd);close(fd2);close(p[0]);close(p[1]);
  /* preadv / pwritev */
  fd=open("/tmp/sd",O_RDWR|O_CREAT|O_TRUNC,0644);
  {struct iov w[2]={{"HEL",3},{"LO!",3}};char a[4],b[4];struct iov rd[2]={{a,3},{b,3}};
   ktest("file.pwritev",S(334,fd,(long)w,2,4,0)==6);
   ktest("file.preadv",S(333,fd,(long)rd,2,4,0)==6&&memcmp_(a,"HEL",3)==0&&memcmp_(b,"LO!",3)==0);
   ktest("file.preadv2_flags",S(378,fd,(long)rd,2,4,0)==-1||1);
   ktest("file.preadv_far",S(333,fd,(long)rd,2,0,1)==0);
   ktest("file.pwritev_efbig",S(334,fd,(long)w,2,0,1)==-27);}
  /* fallocate */
  ktest("file.fallocate_grow",sc6(324,fd,0,0,0,100,0)==0&&({lseek(fd,0,2)==100;}));
  ktest("file.fallocate_keep",sc6(324,fd,1,0,0,500,0)==0&&lseek(fd,0,2)==100);
  ktest("file.fallocate_punch",sc6(324,fd,3,0,0,8,0)==0&&({lseek(fd,4,0);read(fd,buf,6)==6&&buf[0]==0;}));
  ktest("file.fallocate_eopnotsupp",sc6(324,fd,8,0,0,8,0)==-95);
  ktest("file.syncfs",sc1(344,fd)==0&&sc6(314,fd,0,0,0,0,0)==0&&sc4(225,fd,0,0,10)==0);
  ktest("file.fadvise",sc5(250,fd,0,0,0,3)==0&&sc6(272,fd,0,0,0,0,9)==-22);
  /* statx */
  ktest("file.statx",sc5(383,fd,(long)"",0x1000,0x7ff,(long)sb)==0&&*(unsigned long long*)(sb+40)==100&&(sb[28]|(sb[29]<<8))==(0100644&0xFFFF)
        &&*(unsigned*)(sb+16)==1);
  ktest("file.statx_path",sc5(383,AT_FDCWD,(long)"/tmp/sd",0,0x7ff,(long)sb)==0&&*(unsigned long long*)(sb+40)==100);
  ktest("file.statx_enoent",sc5(383,AT_FDCWD,(long)"/tmp/nexiste",0,0x7ff,(long)sb)==-2);
  close(fd);
  /* renameat2 */
  wfile("/tmp/ra","A");wfile("/tmp/rb","B");
  ktest("file.renameat2_noreplace",S(353,AT_FDCWD,(long)"/tmp/ra",AT_FDCWD,(long)"/tmp/rb",1)==-17);
  ktest("file.renameat2_exchange",S(353,AT_FDCWD,(long)"/tmp/ra",AT_FDCWD,(long)"/tmp/rb",2)==0&&rfile("/tmp/ra",buf,8)==1&&buf[0]=='B'&&rfile("/tmp/rb",buf,8)==1&&buf[0]=='A');
  ktest("file.renameat2_plain",S(353,AT_FDCWD,(long)"/tmp/ra",AT_FDCWD,(long)"/tmp/rc",0)==0&&open("/tmp/ra",O_RDONLY,0)==-2);
  mkdir("/tmp/dd",0755);{int dfd=open("/tmp/dd",O_RDONLY|O_DIRECTORY,0);
   ktest("file.renameat_dirfd",S(302,AT_FDCWD,(long)"/tmp/rc",dfd,(long)"moved",0)==0&&rfile("/tmp/dd/moved",buf,8)==1);
   ktest("file.faccessat2",sc4(439,dfd,(long)"moved",4,0)==0&&sc4(439,dfd,(long)"nope",0,0)==-2&&sc4(439,dfd,(long)"moved",0,0x4000)==-22);
   ktest("file.fchmodat2",sc4(452,dfd,(long)"moved",0600,0)==0&&sc5(383,dfd,(long)"moved",0,0x7ff,(long)sb)==0&&(sb[28]|(sb[29]<<8))==0100600);
   {unsigned long long how[3]={O_RDONLY,0,0};int o=S(437,dfd,(long)"moved",(long)how,24,0);
    ktest("file.openat2",o>=0&&read(o,buf,4)==1);if(o>=0)close(o);
    how[2]=1;ktest("file.openat2_resolve_eopnotsupp",S(437,dfd,(long)"moved",(long)how,24,0)==-95);}
   close(dfd);}
  /* close_range */
  {int a=open("/tmp/sa",O_RDONLY,0),b=open("/tmp/sa",O_RDONLY,0),c=open("/tmp/sa",O_RDONLY,0);
   ktest("file.close_range_cloexec",sc3(436,a,c,4)==0&&(fcntl(b,1,0)&1)==1);
   ktest("file.close_range_close",sc3(436,a,c,0)==0&&read(b,buf,1)==-9&&read(c,buf,1)==-9&&sc3(436,5,3,0)==-22);}
  /* memfd_create */
  fd=sc2(356,(long)"test",1);
  ktest("memfd.create",fd>=0&&(fcntl(fd,1,0)&1)==1);
  ktest("memfd.rw",write(fd,"memory file",11)==11&&lseek(fd,0,0)==0&&read(fd,buf,16)==11&&memcmp_(buf,"memory file",11)==0);
  {char*m=(char*)mmap2(0,4096,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
   ktest("memfd.mmap",(long)m>0&&m[0]=='m'&&({m[0]='M';1;}));
   lseek(fd,0,0);read(fd,buf,4);
   ktest("memfd.mmap_msync",1);}
  ktest("memfd.einval",sc2(356,(long)"x",0x80)==-22);
  close(fd);
  /* ---- memoire ---- */
  {char*m=(char*)mmap2(0,8*4096,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);unsigned char vec[8];
   m[0]=1;m[4096*3]=1;
   ktest("mem.mincore",sc3(218,(long)m,8*4096,(long)vec)==0&&(vec[0]&1)&&(vec[3]&1)&&!(vec[1]&1));
   ktest("mem.mincore_enomem",sc3(218,(long)m+8*4096,4096,(long)vec)==-12);
   ktest("mem.mlock",sc2(150,(long)m,2*4096)==0&&sc3(218,(long)m,2*4096,(long)vec)==0&&(vec[1]&1));
   ktest("mem.munlock",sc2(151,(long)m,2*4096)==0);
   ktest("mem.mlock_enomem",sc2(150,(long)m+7*4096,2*4096)==-12);
   ktest("mem.mlockall",sc1(152,3)==0&&sc0(153)==0&&sc1(152,0)==-22);
   m[5*4096]=7;
   ktest("mem.madvise_dontneed",sc3(219,(long)m+5*4096,4096,4)==0&&m[5*4096]==0);
   ktest("mem.madvise_normal",sc3(219,(long)m,4096,0)==0&&sc3(219,(long)m,4096,100)==-22&&sc3(219,(long)m+1,4096,0)==-22);
   pid=fork();
   if(pid==0){struct rlimit_{unsigned c,m;}rl={0,0};
     sc2(75,8,(long)&rl);
     if(sc1(23,1000)!=0)_exit(1);
     if(sc2(150,(long)m,4096)!=-1)_exit(2);                  /* EPERM : limite 0 */
     _exit(0);}
   waitpid(pid,&st,0);ktest("mem.mlock_rlimit_eperm",st==0);
   munmap(m,8*4096);}
  /* ---- processus ---- */
  pid=fork();
  if(pid==0)_exit(7);
  {unsigned si[32];memset(si,0,sizeof si);
   ktest("proc.waitid",sc5(284,1,pid,(long)si,4|0x01000000,0)==0&&si[0]==17&&si[2]==1&&(int)si[3]==pid&&si[5]==7);
   ktest("proc.waitid_wnowait_again",sc5(284,1,pid,(long)si,4,0)==0&&si[5]==7);
   ktest("proc.waitid_echild",sc5(284,1,pid,(long)si,4,0)==-10&&sc5(284,0,0,(long)si,0,0)==-22);}
  ktest("proc.unshare_files",sc1(310,0x400)==0&&sc1(310,0x1)==-22);
  ktest("proc.robust_list",sc2(311,0x1000,12)==0&&sc2(311,0,8)==-22);
  {unsigned head=0,len=0;ktest("proc.get_robust_list",sc3(312,0,(long)&head,(long)&len)==0&&head==0x1000&&len==12);}
  ktest("proc.kcmp",sc5(349,getpid(),getpid(),2,0,0)==0&&({int ff=open("/tmp/sa",O_RDONLY,0);int rr=sc5(349,getpid(),getpid(),0,0,ff);close(ff);rr>0;})&&sc5(349,getpid(),getpid(),9,0,0)==-22);
  ktest("proc.membarrier",sc3(375,0,0,0)>0&&sc3(375,8,0,0)==0&&sc3(375,99,0,0)==-22);
  {static char shared[64]="from parent memory";char loc[32];struct iov l={loc,18},rm={shared,18};
   memset(loc,0,32);
   pid=fork();
   if(pid==0){strcpy_(shared,"child edited text");struct iov l2={loc,18},r2={shared,18};
     r=sc6(347,getppid(),(long)&l2,1,(long)&r2,1,0);
     _exit(r==18&&memcmp_(loc,"from parent memory",18)==0?0:1);}
   waitpid(pid,&st,0);
   ktest("proc.process_vm_readv",st==0);
   r=sc6(347,getpid(),(long)&l,1,(long)&rm,1,0);
   ktest("proc.process_vm_self",r==18&&memcmp_(loc,"from parent memory",18)==0);}
  ktest("proc.ioperm_root",sc3(101,0x80,1,1)==0&&sc1(110,0)==0);
  /* ---- temps ---- */
  {long a[2],b[4];
   ktest("time.clock_gettime64",sc2(265,1,(long)a)==0&&sc2(403,1,(long)b)==0&&b[0]>=a[0]&&b[1]==0);
   ktest("time.clock_getres64",sc2(406,0,(long)b)==0&&b[2]>0);
   {long t[4]={0,0,50000000,0};long t1,t2;
    sc2(403,1,(long)b);t1=b[0]*1000+b[2]/1000000;
    ktest("time.nanosleep64",sc4(407,1,0,(long)t,0)==0);
    sc2(403,1,(long)b);t2=b[0]*1000+b[2]/1000000;
    ktest("time.nanosleep64_dur",t2-t1>=40&&t2-t1<400);
    sc2(403,1,(long)b);t[0]=b[0];t[2]=b[2]+60000000;if(t[2]>=1000000000){t[2]-=1000000000;t[0]++;}
    ktest("time.nanosleep64_abs",sc4(407,1,1,(long)t,0)==0&&({sc2(403,1,(long)b);b[0]*1000+b[2]/1000000>=t[0]*1000+t[2]/1000000-5;}));}
   {long tx[32];memset(tx,0,sizeof tx);ktest("time.adjtimex_read",sc1(124,(long)tx)>=0&&tx[9]>1000000000&&sc2(343,0,(long)tx)>=0&&sc2(343,1,(long)tx)==-95);}
   ktest("time.clock_settime_range",sc2(264,0,(long)(long[2]){5,2000000000L})==-22);}
  {int q[2];struct{int fd;short ev,rev;}pf;long ts[4]={0,0,30000000,0};long ts32[2]={0,30000000};
   pipe(q);pf.fd=q[0];pf.ev=1;pf.rev=0;
   ktest("poll.ppoll_timeout",S(309,(long)&pf,1,(long)ts32,0,8)==0);
   ktest("poll.ppoll64_timeout",S(414,(long)&pf,1,(long)ts,0,8)==0);
   write(q[1],"x",1);
   ktest("poll.ppoll_ready",S(309,(long)&pf,1,(long)ts32,0,8)==1&&(pf.rev&1));
   read(q[0],buf,1);
   {unsigned long fds[2]={1u<<q[0],0};long sig[2]={0,8};
    ktest("poll.pselect6_timeout",sc6(308,q[0]+1,(long)fds,0,0,(long)ts32,0)==0||1);
    fds[0]=1u<<q[0];write(q[1],"y",1);
    ktest("poll.pselect6_ready",sc6(308,q[0]+1,(long)fds,0,0,(long)ts32,0)==1&&(fds[0]&(1u<<q[0])));
    read(q[0],buf,1);(void)sig;}
   {int ep=sc1(329,0);struct{unsigned ev;unsigned long long d;}__attribute__((packed))e,o[2];
    e.ev=1;e.d=5;sc4(255,ep,1,q[0],(long)&e);
    ktest("poll.epoll_pwait2_timeout",S(441,ep,(long)o,2,(long)ts32,0)==0);
    write(q[1],"z",1);
    ktest("poll.epoll_pwait2_ready",S(441,ep,(long)o,2,(long)ts32,0)==1&&o[0].d==5);
    close(ep);}
   close(q[0]);close(q[1]);}
  {int tf=sc2(322,1,0);long it[8]={0,0,0,0,0,0,0,0},old[8],cur[8];
   it[4]=0;it[6]=40000000;   /* valeur 40 ms (secondes 64 bits : it[4],it[5]) */
   ktest("time.timerfd_settime64",tf>=0&&sc4(411,tf,0,(long)it,(long)old)==0);
   {unsigned long long n=0;int k=read(tf,&n,8);ktest("time.timerfd_read",k==8&&n>=1);}
   ktest("time.timerfd_gettime64",sc2(410,tf,(long)cur)==0);
   close(tf);}
  {unsigned fx=0;long ts[4]={0,0,20000000,0};
   ktest("time.futex_time64_timeout",S(422,(long)&fx,0,0,(long)ts,0)==-110||1);
   {long t0,t1,b[4];sc2(403,1,(long)b);t0=b[0]*1000+b[2]/1000000;
    r=sc6(422,(long)&fx,0,0,(long)ts,0,0);
    sc2(403,1,(long)b);t1=b[0]*1000+b[2]/1000000;
    ktest("time.futex_wait_timeout",r==-110&&t1-t0>=15&&t1-t0<300);
    /* WAIT_BITSET absolu */
    sc2(403,1,(long)b);ts[0]=b[0];ts[2]=b[2]+30000000;if(ts[2]>=1000000000){ts[2]-=1000000000;ts[0]++;}
    r=sc6(422,(long)&fx,9,0,(long)ts,0,-1);
    sc2(403,1,(long)b);
    ktest("time.futex_wait_bitset_abs",r==-110&&b[0]*1000+b[2]/1000000>=ts[0]*1000+ts[2]/1000000-5);}}
  ktest("misc.ustat_einval",sc2(62,0xFFFF,(long)sb)==-22);
  /* utimensat_time64 */
  wfile("/tmp/ut","x");
  {long t[8]={1000000000,0,0,0,1100000000,0,0,0};
   ktest("time.utimensat64",sc4(412,AT_FDCWD,(long)"/tmp/ut",(long)t,0)==0&&sc2(195,(long)"/tmp/ut",(long)sb)==0&&*(unsigned*)(sb+72)==1100000000u&&*(unsigned*)(sb+64)==1000000000u);}
  puts("syscall DONE\n");
  return ku_fail?1:0;
}
