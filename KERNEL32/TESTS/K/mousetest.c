/* mousetest : souris PS/2 (/dev/input/mice) ; actif seulement avec k32mouse
   sur la ligne de commande : RUNMOUSE.SH injecte des evenements par le
   moniteur QEMU (mouse_move, mouse_button) */
#include "ku.h"
struct pfd{int fd;short ev,rev;};
int main(void){
  char cl[256];int fdc=open("/proc/cmdline",O_RDONLY,0),m=0,k,found=0,fd,n,got=0,btn=0,sdx=0,sdy=0,t,ev0,ev1;
  if(fdc>=0){m=read(fdc,cl,sizeof cl-1);close(fdc);}
  for(k=0;k+8<=m;k++)if(memcmp_(cl+k,"k32mouse",8)==0)found=1;
  if(!found){puts("  (souris : essai ignore, voir RUNMOUSE.SH)\n");return 0;}
  fd=open("/dev/input/mice",O_RDONLY|O_NONBLOCK,0);
  ktest("mouse.open",fd>=0);
  ev1=open("/dev/input/event1",O_RDONLY|O_NONBLOCK,0);ev0=open("/dev/input/event0",O_RDONLY|O_NONBLOCK,0);
  ktest("evdev.open",ev0>=0&&ev1>=0);
  puts("MOUSE-READY\n");
  for(t=0;t<120&&got<4;t++){
    struct pfd p={fd,1,0};unsigned char b[3];
    if(sc3(SYS_poll,(long)&p,1,100)<=0)continue;
    while((n=read(fd,b,3))==3){got++;if(!(b[0]&8))got=-100;if(b[0]&1)btn=1;
      sdx+=(int)b[1]-((b[0]&0x10)?256:0);sdy+=(int)b[2]-((b[0]&0x20)?256:0);}
  }
  if(got<1){char ib[1024];int ifd=open("/proc/interrupts",O_RDONLY,0),r2;if(ifd>=0){r2=read(ifd,ib,sizeof ib-1);if(r2>0)write(1,ib,r2);close(ifd);}}
  ktest("mouse.packets",got>=1);
  ktest("mouse.button",btn==1);
  ktest("mouse.motion",sdx!=0||sdy!=0);
  /* ---- evdev : ioctl, evenements souris puis clavier ---- */
  {
    unsigned char bits[64];char nm[64];unsigned short idv[4];int ver=0;
    struct ie{long sec,usec;unsigned short type,code;int value;} e[16];
    int rx=0,ry=0,wheel=0,bl=0,blup=0,syn=0,r;
    ktest("evdev.version",ioctl(ev1,0x80044501,(long)&ver)==0&&ver==0x010001);
    ktest("evdev.id",ioctl(ev0,0x80084502,(long)idv)==0&&idv[0]==0x11);
    r=ioctl(ev0,0x80404506,(long)nm);ktest("evdev.name_kbd",r>8&&nm[0]=='A'&&nm[1]=='T');
    r=ioctl(ev1,0x80404506,(long)nm);ktest("evdev.name_mouse",r>8&&nm[0]!=0);
    memset(bits,0,32);ioctl(ev1,0x80204522,(long)bits);   /* EV_REL bits */
    ktest("evdev.bits_rel",(bits[0]&3)==3&&(bits[1]&1)==1);
    memset(bits,0,64);ioctl(ev1,0x80404521,(long)bits);   /* EV_KEY bits : BTN_LEFT=0x110 */
    ktest("evdev.bits_btn",(bits[0x110>>3]&1)==1);
    memset(bits,0,32);ioctl(ev0,0x80204520,(long)bits);
    ktest("evdev.bits_types_kbd",(bits[0]&3)==3&&(bits[0]&4)==0);
    ktest("evdev.read_size_einval",read(ev1,e,8)==-22);
    for(t=0;t<40;t++){
      while((n=read(ev1,e,sizeof e))>0){int i;
        for(i=0;i<n/16;i++){
          if(e[i].type==2&&e[i].code==0)rx+=e[i].value;
          if(e[i].type==2&&e[i].code==1)ry+=e[i].value;
          if(e[i].type==2&&e[i].code==8)wheel+=e[i].value;
          if(e[i].type==1&&e[i].code==0x110){if(e[i].value==1)bl=1;else blup=1;}
          if(e[i].type==0&&e[i].code==0)syn++;
        }}
      if(wheel!=0)break;
      {long rq[2]={0,100000000};nanosleep(rq,0);}
    }
    ktest("evdev.rel_x",rx==10+3-4);
    ktest("evdev.rel_y",ry==5+3+2);      /* REL_Y > 0 : vers le bas */
    ktest("evdev.button",bl==1&&blup==1);
    ktest("evdev.wheel",wheel!=0);
    ktest("evdev.syn",syn>=5);
    /* clavier : sendkey a, sendkey up (touche etendue E0 48) */
    puts("KEY-READY\n");
    {int ka=0,kar=0,kup=0,kupr=0;
     for(t=0;t<100&&!(kar&&kupr);t++){
       while((n=read(ev0,e,sizeof e))>0){int i;
         for(i=0;i<n/16;i++){
           if(e[i].type==1&&e[i].code==30){if(e[i].value==1)ka=1;else if(e[i].value==0)kar=1;}
           if(e[i].type==1&&e[i].code==103){if(e[i].value==1)kup=1;else if(e[i].value==0)kupr=1;}
         }}
       {long rq[2]={0,100000000};nanosleep(rq,0);}
     }
     ktest("evdev.key_a",ka&&kar);
     ktest("evdev.key_up_extended",kup&&kupr);}
    /* KDSKBMODE MEDIUMRAW sur la console : octets 0x30 (appui B) puis 0xB0 */
    {unsigned char tio[36],sv[36];int md=-1,got1=-1,got2=-1;unsigned char b[4];int tf=open("/dev/tty1",O_RDWR|0x100,0);
     ktest("kbd.getmode_xlate",ioctl(tf,0x4B44,(long)&md)==0&&md==1);
     ioctl(tf,0x5401,(long)tio);memcpy(sv,tio,36);
     *(unsigned*)(tio+12)&=~0x4b;   /* ISIG ICANON ECHO */
     *(unsigned*)(tio+0)&=~0x500;   /* ICRNL IXON */
     tio[17+6]=1;tio[17+5]=0;        /* VMIN, VTIME */
     ioctl(tf,0x5402,(long)tio);
     ktest("kbd.setmode_mediumraw",ioctl(tf,0x4B45,2)==0);
     ioctl(tf,0x4B44,(long)&md);ktest("kbd.getmode_mediumraw",md==2);
     puts("RAW-READY\n");
     for(t=0;t<100&&got2<0;t++){
       struct pfd p={tf,1,0};
       if(sc3(SYS_poll,(long)&p,1,100)>0){n=read(tf,b,1);if(n==1){if(b[0]==0x30)got1=0x30;else if(b[0]==0xb0&&got1==0x30)got2=0xb0;}}
     }
     ioctl(tf,0x4B45,1);ioctl(tf,0x5402,(long)sv);
     ktest("kbd.mediumraw_press_release",got1==0x30&&got2==0xb0);}
    /* KDSKBENT/KDGKBENT et touches mortes : la touche 30 (A) devient un
       accent circonflexe mort ; QEMU envoie a e / a espace / a a */
    {unsigned tio[9],sv[9];unsigned v,r;int tf=open("/dev/tty1",O_RDWR|0x100,0);
     unsigned char got[16];int ng=0,old;
     v=0|(30u<<8);r=ioctl(tf,0x4B46,(long)&v);old=v>>16;
     ktest("kbd.kdgkbent",r==0&&(v>>16)=='a');
     v=3|(30u<<8);ktest("kbd.kdgkbent_einval_table",ioctl(tf,0x4B46,(long)&v)==-22);
     v=0|(200u<<8);ktest("kbd.kdgkbent_einval_index",ioctl(tf,0x4B46,(long)&v)==-22);
     v=0|(30u<<8)|(0x502u<<16);ktest("kbd.kdskbent",ioctl(tf,0x4B47,(long)&v)==0);
     v=0|(30u<<8);ioctl(tf,0x4B46,(long)&v);ktest("kbd.kdskbent_readback",(v>>16)==0x502);
     ioctl(tf,0x5401,(long)tio);memcpy(sv,tio,36);
     tio[3]&=~0x4b;tio[0]&=~0x500;((unsigned char*)tio)[17+6]=1;((unsigned char*)tio)[17+5]=0;
     ioctl(tf,0x5402,(long)tio);
     puts("DEAD-READY\n");
     for(t=0;t<150&&ng<4;t++){
       struct pfd p={tf,1,0};
       if(sc3(SYS_poll,(long)&p,1,100)>0){n=read(tf,got+ng,4-ng);if(n>0)ng+=n;}
     }
     ioctl(tf,0x5402,(long)sv);
     v=0|(30u<<8)|((unsigned)old<<16);ioctl(tf,0x4B47,(long)&v);
     ktest("kbd.dead_circumflex_e",ng>=2&&got[0]==0xC3&&got[1]==0xAA);
     ktest("kbd.dead_space_sign",ng>=3&&got[2]=='^');
     ktest("kbd.dead_twice_sign",ng==4&&got[3]=='^');
     v=0|(30u<<8);ioctl(tf,0x4B46,(long)&v);ktest("kbd.kdskbent_restored",(v>>16)==old);}
  }
  puts("MOUSE-DONE\n");
  return ku_fail?1:0;
}
