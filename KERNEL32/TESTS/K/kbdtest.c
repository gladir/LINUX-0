/* kbdtest : lit une ligne sur /dev/console (clavier) et la reecrit sur /dev/ttyS0
   (essai du clavier PS/2 et de la table de touches ; QEMU : sendkey) */
#include "ku.h"
int main(void){
  char b[128];int n,s;
  int c=open("/dev/console",O_RDWR,0);
  s=open("/dev/ttyS0",O_WRONLY,0);
  puts_fd(s,"KBD: pret\n");
  n=read(c,b,sizeof b-1);
  if(n<0)n=0;
  puts_fd(s,"KBD: ligne=[");write(s,b,n>0&&b[n-1]=='\n'?n-1:n);puts_fd(s,"]\n");
  return 0;
}
