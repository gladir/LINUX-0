/* misctest : appels systeme divers (mount, chroot, poll/select, readv, setitimer,
   sigaction ancien format, identifiants, sessions, limites...) */
#include "ku.h"
struct stat64 { unsigned long long st_dev; unsigned char pad0[4]; unsigned long st_ino; unsigned int st_mode,st_nlink,st_uid,st_gid;
  unsigned long long st_rdev; unsigned char pad3[4]; long long st_size; unsigned long st_blksize; unsigned long long st_blocks;
  unsigned long at,atn,mt,mtn,ct,ctn; unsigned long long ino; };
struct pollfd { int fd; short events,revents; };
struct iovec { void*base; size_t len; };
static volatile int old_sig;
static void oldh(int s){old_sig=s;}
static volatile int itv;
static void hitv(int s){itv++;}
int main(void){
  char b[256];int f[2],n,fd,st,p;struct stat64 s;
  /* mount / umount d'un tmpfs */
  mkdir("/mnt/t",0755);
  ktest("mount.tmpfs",mount("none","/mnt/t","tmpfs",0,0)==0);
  fd=open("/mnt/t/x",O_CREAT|O_WRONLY,0644);write(fd,"abc",3);close(fd);
  ktest("mount.file",access("/mnt/t/x",0)==0);
  ktest("umount",umount("/mnt/t")==0);
  ktest("umount.gone",access("/mnt/t/x",0)==-2);
  ktest("umount.einval",umount("/mnt/t")==-22);
  /* chroot */
  mkdir("/tmp/root",0755);mkdir("/tmp/root/etc",0755);
  fd=open("/tmp/root/etc/f",O_CREAT|O_WRONLY,0644);write(fd,"in",2);close(fd);
  p=fork();
  if(p==0){chroot("/tmp/root");chdir("/");_exit(access("/etc/f",0)==0&&access("/tmp",0)==-2?0:1);}
  waitpid(p,&st,0);
  ktest("chroot",st==0);
  /* boucle de liens symboliques */
  symlink("/tmp/la","/tmp/lb");symlink("/tmp/lb","/tmp/la");
  ktest("symlink.eloop",open("/tmp/la",O_RDONLY,0)==-40);
  unlink("/tmp/la");unlink("/tmp/lb");
  /* poll */
  pipe(f);
  struct pollfd pf[2]={{f[0],1,0},{f[1],4,0}};
  n=sc3(SYS_poll,(long)pf,2,0);
  ktest("poll.write_ready",n==1&&(pf[1].revents&4)&&!(pf[0].revents&1));
  write(f[1],"z",1);
  pf[0].revents=0;n=sc3(SYS_poll,(long)pf,2,0);
  ktest("poll.read_ready",n==2&&(pf[0].revents&1));
  n=sc3(SYS_poll,(long)pf,1,10);
  ktest("poll.timeout",n==1);
  read(f[0],b,1);
  pf[0].revents=0;n=sc3(SYS_poll,(long)pf,1,50);
  ktest("poll.timeout0",n==0);
  /* select (newselect) */
  unsigned long rs[32];memset(rs,0,sizeof rs);rs[0]=1UL<<f[0];
  long tv[2]={0,20000};
  n=sc5(142,f[0]+1,(long)rs,0,0,(long)tv);
  ktest("select.timeout",n==0);
  write(f[1],"q",1);rs[0]=1UL<<f[0];
  n=sc5(142,f[0]+1,(long)rs,0,0,(long)tv);
  ktest("select.ready",n==1&&(rs[0]&(1UL<<f[0])));
  /* readv / writev */
  struct iovec iv[2]={{"ab",2},{"cde",3}};
  pipe(f);
  ktest("writev",sc3(146,f[1],(long)iv,2)==5);
  char r1[3],r2[4];struct iovec rv[2]={{r1,2},{r2,3}};
  ktest("readv",sc3(145,f[0],(long)rv,2)==5&&r1[0]=='a'&&r2[2]=='e');
  /* pread */
  fd=open("/tmp/pr",O_CREAT|O_RDWR,0600);write(fd,"0123456789",10);
  n=sc5(180,fd,(long)b,4,6,0);
  ktest("pread64",n==4&&b[0]=='6'&&lseek(fd,0,1)==10);
  close(fd);unlink("/tmp/pr");
  /* fcntl, dup */
  fd=dup(1);
  ktest("dup",fd>2);
  ktest("fcntl.getfd",fcntl(fd,1,0)==0&&fcntl(fd,2,1)==0&&fcntl(fd,1,0)==1);
  int fd2=fcntl(fd,0,10);
  ktest("fcntl.dupfd",fd2>=10);
  close(fd);close(fd2);
  /* setitimer */
  signal_set(SIGALRM,hitv,0);
  struct{long ii[2],iv[2];}it={{0,50000},{0,50000}};
  sc3(104,0,(long)&it,0);
  long t0=0;while(itv<3&&t0<100000000)t0++;
  it.ii[1]=0;it.iv[1]=0;sc3(104,0,(long)&it,0);
  ktest("setitimer",itv>=3);
  /* ancien sigaction (67) + sigreturn (119) */
  struct{void(*h)(int);unsigned long mask,flags;void*rest;}oa={oldh,0,0,0};
  sc3(67,SIGUSR1,(long)&oa,0);
  kill(getpid(),SIGUSR1);
  ktest("sigaction.old",old_sig==SIGUSR1);
  /* identifiants et sessions */
  ktest("ids",sc0(24)==0&&sc0(47)==0&&sc0(49)==0);
  p=fork();
  if(p==0){int sid=setsid();_exit(sid==getpid()&&getpgrp()==sid?0:1);}
  waitpid(p,&st,0);
  ktest("setsid",st==0);
  p=fork();
  if(p==0){sc1(SYS_setuid,500);_exit(sc1(SYS_setuid,0)==-1?0:1);}
  waitpid(p,&st,0);
  ktest("setuid.eperm",st==0);
  ktest("umask",umask(077)==022&&umask(022)==077);
  /* getrlimit / setrlimit */
  long rl[2];sc2(76,7,(long)rl);
  ktest("getrlimit",rl[0]>=256);
  /* uname, sysinfo, clock_gettime, getrusage */
  long si[16];
  ktest("sysinfo",sc1(SYS_sysinfo,(long)si)==0&&si[4]>0);
  long ts[2];
  ktest("clock_gettime",sc2(SYS_clock_gettime,1,(long)ts)==0&&ts[0]>=0);
  /* statfs */
  long sf[16];
  ktest("statfs",sc2(99,(long)"/tmp",(long)sf)==0&&sf[0]==0x01021994);
  /* truncate par chemin et stat ancien */
  fd=open("/tmp/tr",O_CREAT|O_RDWR,0600);write(fd,"0123456789",10);close(fd);
  ktest("truncate",sc2(92,(long)"/tmp/tr",3)==0);
  char os[64];sc2(106,(long)"/tmp/tr",(long)os);
  ktest("stat.old",*(int*)(os+20)==3&&(*(unsigned short*)(os+8)&0xf000)==0x8000);
  unlink("/tmp/tr");
  /* utimes */
  fd=open("/tmp/ut",O_CREAT|O_RDWR,0600);close(fd);
  long tms[4]={1000000,0,2000000,0};
  ktest("utimes",sc2(271,(long)"/tmp/ut",(long)tms)==0);
  sc2(SYS_stat64,(long)"/tmp/ut",(long)&s);
  ktest("utimes.mtime",s.mt==2000000&&s.at==1000000);
  unlink("/tmp/ut");
  /* getdents ancien format */
  fd=open("/",O_RDONLY|O_DIRECTORY,0);
  n=getdents(fd,b,sizeof b);
  ktest("getdents.old",n>0&&*(unsigned short*)(b+8)>=12);
  close(fd);
  /* mmap fixe */
  char*m=mmap2((void*)0x50000000,8192,3,0x32,-1,0);
  ktest("mmap.fixed",(long)m==0x50000000);
  /* vfork */
  p=sc0(SYS_vfork);
  if(p==0)_exit(3);
  waitpid(p,&st,0);
  ktest("vfork",((st>>8)&0xff)==3);
  return ku_fail?1:0;
}
