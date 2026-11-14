/* mousetest : souris PS/2 (/dev/input/mice) ; actif seulement avec k32mouse
   sur la ligne de commande : RUNMOUSE.SH injecte des evenements par le
   moniteur QEMU (mouse_move, mouse_button) */
#include "ku.h"
struct pfd{int fd;short ev,rev;};
int main(void){
  char cl[256];int fdc=open("/proc/cmdline",O_RDONLY,0),m=0,k,found=0,fd,n,got=0,btn=0,sdx=0,sdy=0,t;
  if(fdc>=0){m=read(fdc,cl,sizeof cl-1);close(fdc);}
  for(k=0;k+8<=m;k++)if(memcmp_(cl+k,"k32mouse",8)==0)found=1;
  if(!found){puts("  (souris : essai ignore, voir RUNMOUSE.SH)\n");return 0;}
  fd=open("/dev/input/mice",O_RDONLY|O_NONBLOCK,0);
  ktest("mouse.open",fd>=0);
  puts("MOUSE-READY\n");
  for(t=0;t<120&&got<4;t++){
    struct pfd p={fd,1,0};unsigned char b[3];
    if(sc3(SYS_poll,(long)&p,1,100)<=0)continue;
    while((n=read(fd,b,3))==3){got++;if(!(b[0]&8))got=-100;if(b[0]&1)btn=1;
      sdx+=(int)b[1]-((b[0]&0x10)?256:0);sdy+=(int)b[2]-((b[0]&0x20)?256:0);}
  }
  ktest("mouse.packets",got>=1);
  ktest("mouse.button",btn==1);
  ktest("mouse.motion",sdx!=0||sdy!=0);
  puts("MOUSE-DONE\n");
  return ku_fail?1:0;
}
