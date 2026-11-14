/* ttytest : termios, ioctl, tty en mode canonique et brut, session */
#include "ku.h"
struct termios { unsigned long iflag,oflag,cflag,lflag; unsigned char line,cc[19]; };
struct winsize { unsigned short row,col,x,y; };
int main(void){
  struct termios t;struct winsize w;int fd=0;
  ktest("tty.tcgets",ioctl(fd,0x5401,(long)&t)==0);
  ktest("tty.canon",(t.lflag&2)!=0&&(t.lflag&8)!=0);
  ktest("tty.winsz",ioctl(fd,0x5413,(long)&w)==0&&w.col>0&&w.row>0);
  int pg=0;
  ktest("tty.tcgetpgrp",ioctl(fd,0x540f,(long)&pg)==0&&pg>0);
  struct termios r=t;r.lflag&=~(2|8);r.cc[6]=1;r.cc[5]=0;
  ktest("tty.tcsets",ioctl(fd,0x5402,(long)&r)==0);
  ioctl(fd,0x5401,(long)&r);
  ktest("tty.raw",(r.lflag&2)==0);
  ioctl(fd,0x5402,(long)&t);
  int f[2];pipe(f);
  ktest("tty.enotty",ioctl(f[0],0x5401,(long)&t)==-25);
  int tt=open("/dev/tty",O_RDWR,0);
  ktest("tty.devtty",tt>=0);
  if(tt>=0){write(tt,"[ecriture via /dev/tty]\n",24);close(tt);}
  ktest("tty.write",write(1,"x\n",2)==2);
  return ku_fail?1:0;
}
