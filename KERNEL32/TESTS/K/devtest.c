/* devtest : /dev/mem, port, kmsg, rtc, fd, /proc/self/{fd,exe,cwd} */
#include "ku.h"
struct rtct{int s,m,h,d,mo,y,wd,yd,dst;};
static long timesys(void){long t=0;sc1(SYS_time,(long)&t);return t;}
int main(void){
  int fd,n,i;char b[256];
  fd=open("/dev/kmsg",O_RDONLY|O_NONBLOCK,0);
  ktest("dev.kmsg_open",fd>=0);
  n=read(fd,b,200);b[n>0?n:0]=0;
  {int ok=0;for(i=0;i+7<=n;i++)if(memcmp_(b+i,"LINUX-0",7)==0)ok=1;ktest("dev.kmsg_read",n>0&&ok);}
  close(fd);
  fd=open("/dev/kmsg",O_RDWR|O_NONBLOCK,0);
  write(fd,"devtest-marque-xyz\n",19);
  lseek(fd,0,0);
  {char big[16384];int tot=0,ok=0;
   for(;;){n=read(fd,big+tot,sizeof big-1-tot);if(n<=0)break;tot+=n;}
   big[tot]=0;for(i=0;i+18<=tot;i++)if(memcmp_(big+i,"devtest-marque-xyz",18)==0)ok=1;
   ktest("dev.kmsg_write",ok);}
  close(fd);
  fd=open("/dev/mem",O_RDWR,0);
  ktest("dev.mem_open",fd>=0);
  lseek(fd,0x100000,0);n=read(fd,b,16);
  ktest("dev.mem_read",n==16);
  close(fd);
  fd=open("/dev/port",O_RDWR,0);
  {unsigned char r=0x00;lseek(fd,0x70,0);write(fd,&r,1);lseek(fd,0x71,0);n=read(fd,b,1);
   ktest("dev.port_cmos",n==1);}
  close(fd);
  fd=open("/dev/rtc",O_RDONLY,0);
  ktest("dev.rtc_open",fd>=0);
  {struct rtct t;int r=ioctl(fd,0x80247009,(long)&t);
   ktest("dev.rtc_rd_time",r==0&&t.y+1900>=2020&&t.mo>=0&&t.mo<12&&t.d>=1&&t.d<=31&&t.h<24);
   {struct rtct u=t;u.y=130;u.mo=5;u.d=15;u.h=12;u.m=30;u.s=0;
    ktest("dev.rtc_set_time",ioctl(fd,0x4024700A,(long)&u)==0);
    r=ioctl(fd,0x80247009,(long)&t);
    ktest("dev.rtc_readback",r==0&&t.y==130&&t.mo==5&&t.d==15&&t.h==12&&t.m==30);
    {long ts=timesys();ktest("dev.rtc_time_follows",ts>1907000000&&ts<1908000000);}
    {long ts[2];sc2(SYS_gettimeofday,(long)ts,0);}
   }}
  close(fd);
  n=readlink("/dev/stdin",b,255);b[n>0?n:0]=0;
  ktest("dev.stdin_link",n>0&&strcmp(b,"/proc/self/fd/0")==0);
  n=readlink("/dev/fd",b,255);b[n>0?n:0]=0;
  ktest("dev.fd_link",n>0&&strcmp(b,"/proc/self/fd")==0);
  fd=open("/proc/self/fd/0",O_RDONLY,0);
  ktest("dev.proc_fd_open",fd>=0);
  close(fd);
  n=readlink("/proc/self/exe",b,255);b[n>0?n:0]=0;
  ktest("dev.proc_exe",n>0&&strcmp(b,"/bin/devtest")==0);
  n=readlink("/proc/self/cwd",b,255);b[n>0?n:0]=0;
  ktest("dev.proc_cwd",n==1&&b[0]=='/');
  fd=open("/dev/null",O_RDONLY,0);
  {char l[40];int fdn=fd;int k=0;l[0]='/';memcpy(l,"/proc/self/fd/",14);l[14]='0'+fdn/10;l[15]='0'+fdn%10;l[16]=0;
   if(fdn<10){l[14]='0'+fdn;l[15]=0;}
   n=readlink(l,b,255);b[n>0?n:0]=0;(void)k;
   ktest("dev.proc_fd_target",n>0&&strcmp(b,"/dev/null")==0);}
  {int d=open("/proc/self/fd",O_RDONLY|O_DIRECTORY,0);char db[512];int cnt=0,t;
   while((t=getdents64(d,db,sizeof db))>0){int o=0;while(o<t){struct{unsigned long long i,o;unsigned short l;unsigned char ty;char nm[1];}*e=(void*)(db+o);if(e->nm[0]>='0'&&e->nm[0]<='9')cnt++;o+=e->l;}}
   ktest("dev.proc_fd_list",d>=0&&cnt>=4);close(d);}
  close(fd);
  return ku_fail?1:0;
}
