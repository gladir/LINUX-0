/* evttest : eventfd, timerfd, epoll, inotify */
#include "ku.h"
static int eventfd2(unsigned v,int f){return sc2(328,v,f);}
static int timerfd_create(int c,int f){return sc2(322,c,f);}
static int timerfd_settime(int fd,int f,const long*n,long*o){return sc4(325,fd,f,(long)n,(long)o);}
static int timerfd_gettime(int fd,long*c){return sc2(326,fd,(long)c);}
static int epoll_create1(int f){return sc1(329,f);}
static int epoll_ctl(int e,int op,int fd,void*ev){return sc4(255,e,op,fd,(long)ev);}
static int epoll_wait(int e,void*ev,int m,int t){return sc4(256,e,(long)ev,m,t);}
static int inotify_init1(int f){return sc1(332,f);}
static int inotify_add_watch(int fd,const char*p,unsigned m){return sc3(292,fd,(long)p,m);}
static int inotify_rm_watch(int fd,int wd){return sc2(293,fd,wd);}
struct pfd{int fd;short ev,rev;};
static int poll1(int fd,int ev,int tmo){struct pfd p={fd,ev,0};int r=sc3(SYS_poll,(long)&p,1,tmo);return r<=0?r:p.rev;}
struct epev{unsigned ev;unsigned d0,d1;};
struct inev{int wd;unsigned mask,cookie,len;char name[32];};
static char ib[1024];static int ilen,ipos;
static int ino_next(int fd,struct inev*e){
  int l;
  if(ipos>=ilen){ipos=ilen=0;l=read(fd,ib,sizeof ib);if(l<=0)return l;ilen=l;}
  l=16+*(int*)(ib+ipos+12);
  memset(e,0,sizeof *e);memcpy(e,ib+ipos,l>(int)sizeof *e?(int)sizeof *e:l);ipos+=l;return l;}
int main(void){
  unsigned long long v;int fd,n,i,ep;struct epev ev[4];
  /* ---- eventfd ---- */
  fd=eventfd2(3,0x800);
  ktest("evt.eventfd_create",fd>=0);
  n=read(fd,&v,8);ktest("evt.eventfd_initial",n==8&&v==3);
  ktest("evt.eventfd_eagain",read(fd,&v,8)==-11);
  v=5;write(fd,&v,8);v=7;write(fd,&v,8);
  n=read(fd,&v,8);ktest("evt.eventfd_sum",n==8&&v==12);
  ktest("evt.eventfd_poll",poll1(fd,1,0)==0&&(poll1(fd,4,0)&4));
  close(fd);
  fd=eventfd2(2,1|0x800);
  n=read(fd,&v,8);ktest("evt.eventfd_sem",n==8&&v==1);
  close(fd);
  /* ---- timerfd ---- */
  fd=timerfd_create(1,0);
  {long its[4]={0,0,0,50000000};long cur[4];
   ktest("evt.timerfd_settime",timerfd_settime(fd,0,its,0)==0);
   ktest("evt.timerfd_not_yet",poll1(fd,1,0)==0);
   n=read(fd,&v,8);ktest("evt.timerfd_read",n==8&&v==1);
   its[1]=100000000;its[3]=50000000;timerfd_settime(fd,0,its,0);
   {long ts[2]={0,350000000};nanosleep(ts,0);}
   n=read(fd,&v,8);ktest("evt.timerfd_interval",n==8&&v>=3&&v<=5);
   ktest("evt.timerfd_gettime",timerfd_gettime(fd,cur)==0&&cur[1]>0);
   its[0]=its[1]=its[2]=its[3]=0;timerfd_settime(fd,0,its,0);
   ktest("evt.timerfd_disarm",poll1(fd,1,100)==0);}
  close(fd);
  /* ---- epoll ---- */
  ep=epoll_create1(0);
  ktest("evt.epoll_create",ep>=0);
  {int p[2];pipe(p);
   ev[0].ev=1;ev[0].d0=0x1234;ev[0].d1=0;
   ktest("evt.epoll_add",epoll_ctl(ep,1,p[0],&ev[0])==0);
   ktest("evt.epoll_add_dup",epoll_ctl(ep,1,p[0],&ev[0])==-17);
   ktest("evt.epoll_timeout",epoll_wait(ep,ev,4,50)==0);
   write(p[1],"x",1);
   n=epoll_wait(ep,ev,4,1000);
   ktest("evt.epoll_ready",n==1&&(ev[0].ev&1)&&ev[0].d0==0x1234);
   ktest("evt.epoll_level",epoll_wait(ep,ev,4,0)==1);
   {char b[4];read(p[0],b,1);}
   ktest("evt.epoll_drained",epoll_wait(ep,ev,4,0)==0);
   epoll_ctl(ep,2,p[0],0);
   write(p[1],"y",1);
   ktest("evt.epoll_del",epoll_wait(ep,ev,4,0)==0);
   /* edge-triggered */
   ev[0].ev=1|0x80000000;ev[0].d0=7;epoll_ctl(ep,1,p[0],&ev[0]);
   ktest("evt.epoll_et_first",epoll_wait(ep,ev,4,0)==1);
   ktest("evt.epoll_et_second",epoll_wait(ep,ev,4,0)==0);
   epoll_ctl(ep,2,p[0],0);
   /* oneshot */
   ev[0].ev=1|0x40000000;epoll_ctl(ep,1,p[0],&ev[0]);
   n=epoll_wait(ep,ev,4,0);
   ktest("evt.epoll_oneshot",n==1&&epoll_wait(ep,ev,4,0)==0);
   epoll_ctl(ep,2,p[0],0);
   /* HUP */
   ev[0].ev=1;epoll_ctl(ep,1,p[0],&ev[0]);{char b[4];read(p[0],b,1);}
   close(p[1]);
   n=epoll_wait(ep,ev,4,100);
   ktest("evt.epoll_hup",n==1&&(ev[0].ev&0x10));
   close(p[0]);
   ktest("evt.epoll_closed_fd",epoll_wait(ep,ev,4,0)==0);}
  /* epoll sur une socket et un eventfd */
  {int sv[2],e2;socketpair_:;
   sc4(360,1,1,0,(long)sv);
   e2=eventfd2(0,0);
   ev[0].ev=1;ev[0].d0=1;epoll_ctl(ep,1,sv[0],&ev[0]);
   ev[0].ev=1;ev[0].d0=2;epoll_ctl(ep,1,e2,&ev[0]);
   write(sv[1],"s",1);
   n=epoll_wait(ep,ev,4,100);
   ktest("evt.epoll_socket",n==1&&ev[0].d0==1);
   {char b[2];read(sv[0],b,1);}
   {unsigned long long one=1;write(e2,&one,8);}
   n=epoll_wait(ep,ev,4,100);
   ktest("evt.epoll_eventfd",n==1&&ev[0].d0==2);
   close(sv[0]);close(sv[1]);close(e2);}
  close(ep);
  /* ---- inotify ---- */
  mkdir("/tmp/ino",0755);
  fd=inotify_init1(0x800);
  ktest("evt.inotify_init",fd>=0);
  {struct inev e;int wd=inotify_add_watch(fd,"/tmp/ino",0xFFF);
   ktest("evt.inotify_add",wd>=1);
   ktest("evt.inotify_empty",ino_next(fd,&e)==-11);
   {int f=open("/tmp/ino/a",O_RDWR|O_CREAT,0644);
    n=ino_next(fd,&e);
    ktest("evt.inotify_create",n>0&&e.wd==wd&&(e.mask&0x100)&&strcmp(e.name,"a")==0);
    n=ino_next(fd,&e);
    ktest("evt.inotify_open",n>0&&(e.mask&0x20)&&strcmp(e.name,"a")==0);
    write(f,"zz",2);
    n=ino_next(fd,&e);
    ktest("evt.inotify_modify",n>0&&(e.mask&2)&&strcmp(e.name,"a")==0);
    close(f);
    n=ino_next(fd,&e);
    ktest("evt.inotify_close_write",n>0&&(e.mask&8));}
   rename("/tmp/ino/a","/tmp/ino/b");
   {struct inev e2;n=ino_next(fd,&e);ino_next(fd,&e2);
    ktest("evt.inotify_move",(e.mask&0x40)&&strcmp(e.name,"a")==0&&(e2.mask&0x80)&&strcmp(e2.name,"b")==0&&e.cookie==e2.cookie&&e.cookie!=0);}
   unlink("/tmp/ino/b");
   n=ino_next(fd,&e);
   ktest("evt.inotify_delete",n>0&&(e.mask&0x200)&&strcmp(e.name,"b")==0);
   mkdir("/tmp/ino/d",0755);
   n=ino_next(fd,&e);
   ktest("evt.inotify_mkdir",n>0&&(e.mask&0x100)&&(e.mask&0x40000000)&&strcmp(e.name,"d")==0);
   rmdir("/tmp/ino/d");ino_next(fd,&e);
   ktest("evt.inotify_poll",poll1(fd,1,0)==0);
   ktest("evt.inotify_rm",inotify_rm_watch(fd,wd)==0);
   n=ino_next(fd,&e);
   ktest("evt.inotify_ignored",n>0&&(e.mask&0x8000));}
  close(fd);
  rmdir("/tmp/ino");
  return ku_fail?1:0;
}
