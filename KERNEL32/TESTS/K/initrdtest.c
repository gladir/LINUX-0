/* initrdtest : /init d'un initramfs (partie 38) fabrique par MKCPIO.PY :
   verifie l'extraction cpio newc (fichiers, modes, proprietaires, dates,
   liens physiques et symboliques, noeuds de peripheriques, tubes nommes,
   parents absents, fichiers vides, gros fichier). Lance par RUNINITRD.SH. */
#include "ku.h"
static char b[4096];
static int slurp(const char*p,char*s,int max){int fd=open(p,O_RDONLY,0),n,t=0;if(fd<0)return fd;while(t<max-1&&(n=read(fd,s+t,max-1-t))>0)t+=n;s[t]=0;close(fd);return t;}
static unsigned long long sz(const char*p){unsigned char s[96];if(sc2(SYS_stat64,(long)p,(long)s))return ~0ULL;return *(unsigned long long*)(s+44);}
static unsigned fld(const char*p,int off){unsigned char s[96];if(sc2(SYS_stat64,(long)p,(long)s))return 0xdeadbeef;return *(unsigned*)(s+off);}
int main(int argc,char**argv){
  int n,fd,i,ok;
  ktest("initrd.pid1",getpid()==1&&strcmp(argv[0],"/init")==0);
  n=slurp("/etc/hello",b,sizeof b);
  ktest("initrd.file",n==16&&strcmp(b,"hello initramfs\n")==0);
  ktest("initrd.mode",(fld("/init",16)&07777)==0755&&(fld("/etc/hello",16)&07777)==0644);
  ktest("initrd.suid",(fld("/suid",16)&07777)==04755);
  ktest("initrd.owner",fld("/dir/sub/deep.txt",24)==1000&&fld("/dir/sub/deep.txt",28)==100&&fld("/dir",24)==1000);
  ktest("initrd.dirmode",(fld("/dir",16)&07777)==0700&&(fld("/emptydir",16)&0xF000)==0x4000);
  ktest("initrd.mtime",fld("/etc/hello",72)==1234567890);
  ktest("initrd.parent_created",slurp("/dir/sub/deep.txt",b,sizeof b)==5&&strcmp(b,"deep\n")==0);
  ktest("initrd.dotslash",slurp("/dot/prefixed",b,sizeof b)==9&&strcmp(b,"dotslash\n")==0);
  ktest("initrd.empty_file",sz("/empty.txt")==0&&(fld("/empty.txt",16)&0xF000)==0x8000);
  {char l[64];int r=readlink("/lnk",l,63);if(r>0)l[r]=0;ktest("initrd.symlink",r==9&&strcmp(l,"etc/hello")==0);}
  ktest("initrd.symlink_follow",slurp("/lnk",b,sizeof b)==16);
  ktest("initrd.hardlink",fld("/etc/hl1",12)==fld("/etc/hl2",12)&&fld("/etc/hl1",20)==2&&slurp("/etc/hl1",b,sizeof b)==20&&strcmp(b,"shared by two names\n")==0);
  ktest("initrd.chr_node",(fld("/mynull",16)&0xF000)==0x2000&&fld("/mynull",32)==((1<<8)|3));
  fd=open("/mynull",O_RDWR,0);
  ktest("initrd.chr_works",fd>=0&&write(fd,"x",1)==1&&read(fd,b,1)==0);
  if(fd>=0)close(fd);
  ktest("initrd.fifo",(fld("/myfifo",16)&0xF000)==0x1000);
  /* gros fichier */
  fd=open("/big.bin",O_RDONLY,0);ok=fd>=0&&sz("/big.bin")==300000;
  if(ok){int tot=0,r;while((r=read(fd,b,sizeof b))>0){for(i=0;i<r;i++){int k=tot+i;if((unsigned char)b[i]!=(unsigned char)((k*7+(k>>8))&255)){ok=0;break;}}tot+=r;if(!ok)break;}if(tot!=300000)ok=0;close(fd);}
  ktest("initrd.big_file",ok);
  ktest("initrd.dev_proc_present",(fld("/dev",16)&0xF000)==0x4000&&(fld("/proc",16)&0xF000)==0x4000);
  if(ku_cmdline_has("initrdmulti")){n=slurp("/etc/second",b,sizeof b);ktest("initrd.second_module",n==14&&strcmp(b,"from module b\n")==0);}
  ktest("initrd.proc_mounted",slurp("/proc/self/status",b,sizeof b)>0);
  ktest("initrd.no_embedded",sz("/bin/hello")==~0ULL);
  puts("KTEST: initrd DONE\n");
  sync();
  reboot_off();
  return ku_fail?1:0;
}
