/* vttest : consoles virtuelles et KD_GRAPHICS (RUNVT.SH, fb=1024x768) :
   KDSETMODE, VT_SETMODE/VT_GETMODE (VT_PROCESS, signaux), VT_ACTIVATE depuis
   une console graphique (retour au texte, retour au graphique), restauration
   du texte a la fermeture de la console, TIOCGWINSZ/TIOCSWINSZ sur pty. Les
   captures d'ecran sont prises par le script a chaque marqueur VT-SHOT n. */
#include "ku.h"
#ifndef O_NOCTTY
#define O_NOCTTY 0x100
#endif
static volatile int got_rel,got_acq;
static void on_rel(int s){got_rel++;}
static void on_acq(int s){got_acq++;}
static unsigned row[1024];
static void nap(long s,long ns){long ts[2];ts[0]=s;ts[1]=ns;nanosleep(ts,0);}
static void paint(int fd,unsigned c){int y,i;for(i=0;i<1024;i++)row[i]=c;
  for(y=0;y<100;y++){lseek(fd,y*4096,0);write(fd,row,4096);}}
int main(void){
  int fb=open("/dev/fb0",O_RDWR,0),tty,r;unsigned v[40];char m[8];
  if(fb<0){puts("  (pas de /dev/fb0)\n");return 0;}
  tty=open("/dev/tty1",O_RDWR|O_NOCTTY,0);
  ktest("vt.open_tty1",tty>=0);
  signal_set(10,on_rel,0);signal_set(12,on_acq,0);
  paint(fb,0xFF0000);
  ktest("vt.kd_graphics",ioctl(tty,0x4B3A,1)==0);
  {int md=-1;ioctl(tty,0x4B3B,(long)&md);ktest("vt.kd_getmode",md==1);}
  memset(m,0,8);m[0]=1;m[2]=10;m[4]=12;                 /* VT_PROCESS, SIGUSR1, SIGUSR2 */
  ktest("vt.setmode",ioctl(tty,0x5602,(long)m)==0);
  memset(m,0,8);ioctl(tty,0x5601,(long)m);
  ktest("vt.getmode",m[0]==1&&m[2]==10&&m[4]==12);
  {int t2=open("/dev/tty2",O_RDWR|O_NOCTTY,0);if(t2>=0){int k;for(k=0;k<8;k++)write(t2,"Console virtuelle 2 : texte VGA visible apres Alt+F2 depuis le mode graphique\r\n",76);}}
  puts("VT-SHOT 0\n");nap(2,0);                          /* 1024x768 rouge */
  ktest("vt.activate_2",ioctl(tty,0x5606,2)==0);
  nap(0,200000000);
  ktest("vt.release_signal",got_rel==1);
  puts("VT-SHOT 1\n");nap(2,0);                          /* texte VGA 720x400 */
  ioctl(tty,0x5606,1);
  nap(0,200000000);
  ktest("vt.acquire_signal",got_acq==1);
  memset(v,0,160);ioctl(fb,0x4600,(long)v);
  ktest("vt.mode_restored",v[0]==1024&&v[1]==768&&v[6]==32);
  paint(fb,0x00FF00);
  puts("VT-SHOT 2\n");nap(2,0);                          /* 1024x768 vert */
  /* fermeture de la console graphique : retour au texte */
  close(tty);
  nap(0,200000000);
  puts("VT-SHOT 3\n");nap(2,0);                          /* texte VGA */
  /* pty : taille de fenetre */
  {int pm=open("/dev/ptmx",O_RDWR,0),n=0;unsigned short ws[4]={30,100,0,0},g[4]={0,0,0,0};
   char nm[24]="/dev/pts/";
   if(pm>=0){int ix=-1;ioctl(pm,0x80045430,(long)&ix);       /* TIOCGPTN */
     {int u=0;ioctl(pm,0x40045431,(long)&u);}                /* TIOCSPTLCK 0 */
     nm[9]='0'+ix;nm[10]=0;
     {int ps=open(nm,O_RDWR,0);
      ktest("vt.pty_open",ps>=0);
      ktest("vt.pty_setwinsz",ioctl(pm,0x5414,(long)ws)==0);
      ktest("vt.pty_getwinsz_slave",ioctl(ps,0x5413,(long)g)==0&&g[0]==30&&g[1]==100);
      /* FIONREAD sur le maitre : octets ecrits par l'esclave */
      write(ps,"abc",3);nap(0,50000000);
      ktest("vt.ptmx_fionread",ioctl(pm,0x541B,(long)&n)==0&&n>=3);
      /* poll du maitre */
      {struct{int fd;short ev,rev;}pf;pf.fd=pm;pf.ev=1;pf.rev=0;
       ktest("vt.ptmx_poll",sc3(168,(long)&pf,1,0)==1&&(pf.rev&1));}
      close(ps);}
     close(pm);}
   else ktest("vt.pty_open",0);}
  (void)r;
  puts("KTEST: vt DONE\n");
  return ku_fail?1:0;
}
