/* vboxtest : pilote VMMDev de VirtualBox contre le peripherique LOGICIEL de
   simulation du noyau (k32vboxfake=1, RUNVBOX.SH) : QEMU n'emule pas VMMDev,
   donc ce test prouve la structure des requetes et le chemin evdev contre la
   simulation seulement, pas contre VirtualBox. */
#include "ku.h"
static int slurp(const char*p,char*s,int max){int fd=open(p,O_RDONLY,0),n;if(fd<0)return fd;n=read(fd,s,max-1);if(n<0)n=0;s[n]=0;close(fd);return n;}
static int wr(const char*p,const char*s){int fd=open(p,O_WRONLY,0),n;if(fd<0)return fd;n=write(fd,s,strlen(s));close(fd);return n;}
static int has(const char*h,const char*n){int i,l=strlen(n);for(i=0;h[i];i++)if(memcmp_(h+i,n,l)==0)return 1;return 0;}
static void nap(long s,long ns){long ts[2];ts[0]=s;ts[1]=ns;nanosleep(ts,0);}
struct ev{long sec,usec;unsigned short type,code;int value;};
int main(void){
  static char b[2048];int fd,n,i;unsigned char bits[8];
  if(!ku_cmdline_has("k32vboxfake=1")){puts("  (vbox : essai ignore, voir RUNVBOX.SH)\n");return 0;}
  fd=open("/dev/input/event2",O_RDONLY|O_NONBLOCK,0);
  ktest("vbox.event2_exists",fd>=0);
  if(fd<0)return 1;
  n=ioctl(fd,0x80ff4506,(long)b);                       /* EVIOCGNAME(255) */
  ktest("vbox.evdev_name",n>0&&has(b,"VirtualBox mouse integration"));
  memset(bits,0,8);ioctl(fd,0x80084520,(long)bits);       /* EVIOCGBIT(0) */
  ktest("vbox.evdev_has_abs",(bits[0]&8)!=0&&(bits[0]&2)!=0);
  memset(bits,0,8);ioctl(fd,0x80084523,(long)bits);       /* EVIOCGBIT(EV_ABS) */
  ktest("vbox.evdev_abs_xy",(bits[0]&3)==3);
  {int ai[6];memset(ai,0,sizeof ai);ioctl(fd,0x80184540,(long)ai);   /* EVIOCGABS(ABS_X) */
   ktest("vbox.abs_range",ai[2]==65535&&ai[1]==0);}
  /* position imposee a la simulation : evenement 0x200, GetMouseStatus, EV_ABS */
  ktest("vbox.sim_set_x",wr("/proc/sys/k32/vbox_sim_x","12345")>0);
  ktest("vbox.sim_set_y",wr("/proc/sys/k32/vbox_sim_y","54321")>0);
  {int x=-1,y=-1,sy=0,k;struct ev e;
   for(k=0;k<30&&!sy;k++){
     while(read(fd,&e,sizeof e)==sizeof e){
       if(e.type==3&&e.code==0)x=e.value;
       if(e.type==3&&e.code==1)y=e.value;
       if(e.type==0&&e.code==0&&x==12345&&y==54321)sy=1;}
     if(!sy)nap(0,100000000);}
   ktest("vbox.abs_x",x==12345);
   ktest("vbox.abs_y",y==54321);
   ktest("vbox.syn",sy);}
  wr("/proc/sys/k32/vbox_sim_x","100");
  {int x=-1,k;struct ev e;
   for(k=0;k<30&&x!=100;k++){while(read(fd,&e,sizeof e)==sizeof e)if(e.type==3&&e.code==0)x=e.value;if(x!=100)nap(0,100000000);}
   ktest("vbox.abs_second_move",x==100);}
  /* compteurs et journal */
  n=slurp("/proc/k32perf",b,sizeof b);
  ktest("vbox.perf_requests",n>0&&has(b,"vbox_requests"));
  ktest("vbox.no_refused_request",has(b,"vbox_errors 0 0"));
  {static char km[16384];int kn=sc3(103,3,(long)km,sizeof km-1);int ok=0;
   for(i=0;i+20<kn;i++)if(memcmp_(km+i,"vbox: integration de",20)==0)ok=1;
   ktest("vbox.journal",ok);}
  close(fd);
  puts("KTEST: vbox DONE\n");
  return ku_fail?1:0;
}
