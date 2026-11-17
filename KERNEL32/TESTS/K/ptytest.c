/* ptytest : pseudo-terminaux (/dev/ptmx, /dev/pts/N, devpts) */
#include "ku.h"
struct pfd{int fd;short ev,rev;};
static int poll1(int fd,int ev,int tmo){struct pfd p={fd,ev,0};int r=sc3(SYS_poll,(long)&p,1,tmo);return r<=0?r:p.rev;}
struct tio{unsigned iflag,oflag,cflag,lflag;unsigned char line,cc[19];};
int main(void){
  char b[64],nm[32];int m,s,n,idx=-1,unl=0;
  m=open("/dev/ptmx",O_RDWR,0);
  if(m<0){puts("  (pas de /dev/ptmx)\n");return 0;}
  ktest("pty.open_master",m>=0);
  ktest("pty.ptn",ioctl(m,0x80045430,(long)&idx)==0&&idx>=0);
  strcpy_(nm,"/dev/pts/");nm[9]='0'+idx;nm[10]=0;
  ktest("pty.locked",open(nm,O_RDWR,0)<0);
  ktest("pty.unlock",ioctl(m,0x40045431,(long)&unl)==0);
  s=open(nm,O_RDWR,0);
  ktest("pty.open_slave",s>=0);
  {unsigned short ws[4]={24,80,0,0},w2[4]={0,0,0,0};ioctl(m,0x5414,(long)ws);ioctl(s,0x5413,(long)w2);
   ktest("pty.winsize",w2[0]==24&&w2[1]==80);}
  write(m,"hello\n",6);n=read(s,b,63);b[n>0?n:0]=0;
  ktest("pty.master_to_slave",n==6&&strcmp(b,"hello\n")==0);
  n=read(m,b,63);b[n>0?n:0]=0;
  ktest("pty.echo",n==7&&strcmp(b,"hello\r\n")==0);
  write(s,"out\n",4);n=read(m,b,63);b[n>0?n:0]=0;
  ktest("pty.slave_to_master",n==5&&strcmp(b,"out\r\n")==0);
  {struct tio t;ioctl(s,0x5401,(long)&t);t.lflag&=~(8|2);ioctl(s,0x5402,(long)&t);}
  write(m,"x",1);n=read(s,b,1);
  ktest("pty.raw",n==1&&b[0]=='x');
  ktest("pty.poll_empty",poll1(m,1,0)==0);
  write(s,"z",1);
  ktest("pty.poll_in",(poll1(m,1,100)&1)==1);
  read(m,b,1);
  close(m);
  ktest("pty.hup_eof",read(s,b,10)==0);
  close(s);
  ktest("pty.slave_gone",open(nm,O_RDWR,0)<0);
  m=open("/dev/ptmx",O_RDWR,0);
  ktest("pty.reopen",m>=0&&ioctl(m,0x80045430,(long)&n)==0&&n==idx);
  close(m);
  return ku_fail?1:0;
}
