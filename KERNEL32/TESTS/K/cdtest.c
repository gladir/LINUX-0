/* cdtest : /init de l'initramfs du CD-ROM d'installation (RUNCD.SH). Verifie
   que le CD amorce par El Torito a bien livre noyau + initrd + ligne de
   commande, monte le CD en iso9660 sous /cdrom et lit un fichier. */
#include "ku.h"
static char b[512];
static int slurp(const char*p,char*s,int max){int fd=open(p,O_RDONLY,0),n;if(fd<0)return fd;n=read(fd,s,max-1);if(n<0)n=0;s[n]=0;close(fd);return n;}
int main(void){
  int n,fd;
  puts("CD-LIVE-OK init pid ");putd(getpid());puts("\n");
  ktest("cd.init_pid1",getpid()==1);
  n=slurp("/proc/cmdline",b,sizeof b);
  ktest("cd.cmdline",n>0&&ku_cmdline_has("cdlive=1"));
  mkdir("/cdrom",0755);
  ktest("cd.mount",mount("/dev/hdc","/cdrom","iso9660",1,0)==0||mount("/dev/sr0","/cdrom","iso9660",1,0)==0);
  n=slurp("/cdrom/readme.txt",b,sizeof b);
  ktest("cd.readme",n==14&&memcmp_(b,"hello from cd\n",14)==0);
  fd=open("/cdrom/boot/linux0",O_RDONLY,0);
  ktest("cd.kernel_on_cd",fd>=0);if(fd>=0){n=read(fd,b,4);ktest("cd.kernel_elf",n==4&&b[0]==0x7f&&b[1]=='E'&&b[2]=='L'&&b[3]=='F');close(fd);}
  /* ejection : CDROMEJECT apres demontage (le script verifie "tray open" par
     le moniteur QEMU) ; verrou de porte, puis ejection */
  umount("/cdrom");
  {int cd=open("/dev/sr0",O_RDONLY|O_NONBLOCK,0),ok;if(cd<0)cd=open("/dev/hdc",O_RDONLY|O_NONBLOCK,0);
   ok=cd>=0&&ioctl(cd,0x5329,1)==0;ktest("cd.lockdoor",ok);
   ioctl(cd,0x5329,0);
   ktest("cd.eject",cd>=0&&ioctl(cd,0x5309,0)==0);
   ktest("cd.eject_notty_on_tty",ioctl(0,0x5309,0)<0);
   puts("CD-EJECTED\n");
   {long ts[2]={4,0};nanosleep(ts,0);}
   if(cd>=0)close(cd);}
  puts("KTEST: cd DONE\n");
  sync();reboot_off();
  return 0;
}
