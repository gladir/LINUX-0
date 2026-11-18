/* usbtest : pilote USB OHCI + HID (QEMU : -device pci-ohci avec usb-tablet,
   usb-kbd ou usb-mouse). RUNUSB.SH lance le noyau avec init=/bin/usbtest et
   usbmode=abs | rel | prio, attend les marqueurs USB-READY-* sur le port
   serie et injecte les evenements par QMP (input-send-event).
     abs  : tablette (event2 EV_ABS 0..65535, boutons, molette) et clavier USB
            (event0, tty, repetition)
     rel  : souris USB (event1 et /dev/input/mice)
     prio : tablette USB + VMMDev (simulation) : la tablette a priorite */
#include "ku.h"
static int slurp(const char*p,char*s,int max){int fd=open(p,O_RDONLY,0),n;if(fd<0)return fd;n=read(fd,s,max-1);if(n<0)n=0;s[n]=0;close(fd);return n;}
static int wr(const char*p,const char*s){int fd=open(p,O_WRONLY,0),n;if(fd<0)return fd;n=write(fd,s,strlen(s));close(fd);return n;}
static int has(const char*h,const char*n){int i,l=strlen(n);for(i=0;h[i];i++)if(memcmp_(h+i,n,l)==0)return 1;return 0;}
static void nap(long s,long ns){long ts[2];ts[0]=s;ts[1]=ns;nanosleep(ts,0);}
struct ev{long sec,usec;unsigned short type,code;int value;};
static int ndev(int fd){return fd;}
static int abs_(int v){return v<0?-v:v;}
static int mode_is(const char*m){char cl[512];int n=slurp("/proc/cmdline",cl,sizeof cl);(void)n;return has(cl,m);}
static int wait_event2(void){int t,fd;for(t=0;t<100;t++){fd=open("/dev/input/event2",O_RDONLY|O_NONBLOCK,0);if(fd>=0)return fd;nap(0,100000000);}return -1;}
static void drain(int fd){struct ev e;while(read(fd,&e,sizeof e)==sizeof e);}
int main(void){
  static char b[2048];int fd,n,i,t;unsigned char bits[8];
  (void)ndev;
  if(!mode_is("usbmode=")){puts("  (usb : essai ignore, voir RUNUSB.SH)\n");return 0;}
  /* le fil kusbd enumere les ports apres le demarrage : on attend event2 et
     le nom de la tablette */
  if(mode_is("usbmode=abs")||mode_is("usbmode=prio")){
    int ok=0;
    fd=wait_event2();
    ktest("usb.event2_exists",fd>=0);
    if(fd<0)return 1;
    for(t=0;t<100&&!ok;t++){n=ioctl(fd,0x80ff4506,(long)b);if(n>0&&has(b,"QEMU USB Tablet"))ok=1;else nap(0,100000000);}
    ktest("usb.tablet_name",ok);
    memset(bits,0,8);ioctl(fd,0x80084520,(long)bits);
    ktest("usb.evdev_has_abs",(bits[0]&2)!=0&&(bits[0]&8)!=0);
    memset(bits,0,8);ioctl(fd,0x80084523,(long)bits);
    ktest("usb.evdev_abs_xy",(bits[0]&3)==3);
    {unsigned char kb[64];memset(kb,0,64);ioctl(fd,0x80404521,(long)kb);
     ktest("usb.evdev_btn",(kb[0x110>>3]&1)==1);}
    {int ai[6];memset(ai,0,sizeof ai);ioctl(fd,0x80184540,(long)ai);
     ktest("usb.abs_range",ai[2]==65535&&ai[1]==0);}
    {unsigned short id[4]={0,0,0,0};ioctl(fd,0x80084502,(long)id);
     ktest("usb.evdev_id",id[0]==3&&id[1]==0x0627);}
    if(mode_is("usbmode=prio")){
      int x=-1,k,got=0;struct ev e;
      ktest("usb.prio_journal",({static char km[32768];int kn=sc3(103,3,(long)km,sizeof km-1),ok2=0;
        for(i=0;i+20<kn;i++)if(memcmp_(km+i,"usb: VMMDev ne four",19)==0)ok2=1;ok2;}));
      drain(fd);
      wr("/proc/sys/k32/vbox_sim_x","11111");
      wr("/proc/sys/k32/vbox_sim_y","22222");
      for(k=0;k<8;k++){while(read(fd,&e,sizeof e)==sizeof e)if(e.type==3)got++;nap(0,100000000);}
      ktest("usb.prio_vmmdev_silent",got==0);
      (void)x;
      puts("USB-READY-ABS\n");
    }else puts("USB-READY-ABS\n");
    {int x=-1,y=-1,sy=0,k;struct ev e;
     for(k=0;k<150&&!sy;k++){
       while(read(fd,&e,sizeof e)==sizeof e){
         if(e.type==3&&e.code==0)x=e.value;
         if(e.type==3&&e.code==1)y=e.value;
         if(e.type==0&&e.code==0&&x>=0&&y>=0)sy=1;}
       if(!sy)nap(0,100000000);}
     ktest("usb.abs_x",abs_(x-16384)<=3);
     ktest("usb.abs_y",abs_(y-32769)<=3);
     ktest("usb.abs_syn",sy);}
    puts("USB-READY-MOVE2\n");
    {int x=-1,y=-1,k;struct ev e;
     for(k=0;k<150&&!(x>=65530&&y<=3&&y>=0);k++){
       while(read(fd,&e,sizeof e)==sizeof e){
         if(e.type==3&&e.code==0)x=e.value;
         if(e.type==3&&e.code==1)y=e.value;}
       nap(0,100000000);}
     ktest("usb.abs_corner",x>=65530&&y>=0&&y<=3);}
    if(mode_is("usbmode=prio")){puts("KTEST: usb DONE\n");return ku_fail?1:0;}
    puts("USB-READY-BTN\n");
    {int dn=0,up=0,k;struct ev e;
     for(k=0;k<150&&!up;k++){
       while(read(fd,&e,sizeof e)==sizeof e){
         if(e.type==1&&e.code==0x110){if(e.value==1)dn=1;else if(dn)up=1;}}
       if(!up)nap(0,100000000);}
     ktest("usb.button_left",dn&&up);}
    puts("USB-READY-WHEEL\n");
    {int w=0,k;struct ev e;
     for(k=0;k<150&&!w;k++){
       while(read(fd,&e,sizeof e)==sizeof e)if(e.type==2&&e.code==8)w+=e.value;
       if(!w)nap(0,100000000);}
     ktest("usb.wheel",w!=0);}
    /* clavier USB : event0 + tty */
    {int e0=open("/dev/input/event0",O_RDONLY|O_NONBLOCK,0),mk=0,br=0,k,rep=0;struct ev e;char c[16];int tn=0;
     ktest("usb.event0_open",e0>=0);
     drain(e0);
     puts("USB-READY-KEY\n");
     for(k=0;k<150&&!br;k++){
       while(read(e0,&e,sizeof e)==sizeof e){
         if(e.type==1&&e.code==30){if(e.value==1)mk=1;else if(e.value==0&&mk)br=1;}}
       if(!br)nap(0,100000000);}
     ktest("usb.key_a_make_break",mk&&br);
     {int cf=open("/dev/tty1",O_RDWR,0);
      for(k=0;k<30&&tn<2&&cf>=0;k++){struct{int fd;short ev,rev;}p;p.fd=cf;p.ev=1;p.rev=0;
       if(sc3(SYS_poll,(long)&p,1,100)>0){int r=read(cf,c+tn,sizeof c-tn);if(r>0)tn+=r;}}}
     ktest("usb.key_tty",tn>=2&&c[0]=='a'&&c[1]=='\n');
     drain(e0);
     br=0;
     puts("USB-READY-REPEAT\n");
     for(k=0;k<150&&!br;k++){
       br=0;
       while(read(e0,&e,sizeof e)==sizeof e){
         if(e.type==1&&e.code==48){if(e.value==2)rep++;if(e.value==0&&rep>0)br=1;}}
       if(!br)nap(0,100000000);}
     ktest("usb.key_repeat",rep>=3);
     close(e0);}
  }
  else if(mode_is("usbmode=rel")){
    int fm=open("/dev/input/mice",O_RDONLY|O_NONBLOCK,0),e1=open("/dev/input/event1",O_RDONLY|O_NONBLOCK,0);
    int rx=0,ry=0,wh=0,bl=0,blup=0,k,got=0,sx=0,sy=0;struct ev e;unsigned char pk[3];
    ktest("usb.mice_open",fm>=0&&e1>=0);
    nap(2,0);                                   /* enumeration par kusbd */
    puts("USB-READY-REL\n");
    for(k=0;k<200&&!(wh!=0&&blup);k++){
      while(read(e1,&e,sizeof e)==sizeof e){
        if(e.type==2&&e.code==0)rx+=e.value;
        if(e.type==2&&e.code==1)ry+=e.value;
        if(e.type==2&&e.code==8)wh+=e.value;
        if(e.type==1&&e.code==0x110){if(e.value==1)bl=1;else blup=1;}}
      nap(0,100000000);}
    ktest("usb.rel_x",rx==13);
    ktest("usb.rel_y",ry==8);
    ktest("usb.rel_button",bl&&blup);
    ktest("usb.rel_wheel",wh!=0);
    while(read(fm,pk,3)==3){got++;sx+=(int)pk[1]-((pk[0]&0x10)?256:0);sy+=(int)pk[2]-((pk[0]&0x20)?256:0);}
    ktest("usb.mice_packets",got>=3);
    /* /dev/input/mice : Dy > 0 vers le haut (PS/2), l'ecran vers le bas */
    ktest("usb.mice_motion",sx==13&&sy==-8);
  }
  puts("KTEST: usb DONE\n");
  return ku_fail?1:0;
}
