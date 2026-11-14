/* isotest : CD-ROM ATAPI (/dev/hdc) et iso9660 avec Rock Ridge ; actif avec
   k32iso sur la ligne de commande (RUNISO.SH fabrique l'image) */
#include "ku.h"
static unsigned char pat(unsigned i){return (unsigned char)(i*7+(i>>8));}
int main(void){
  char cl[256],b[512],c[128];int fdc=open("/proc/cmdline",O_RDONLY,0),m=0,k,found=0,fd,n,i,ok,r;
  if(fdc>=0){m=read(fdc,cl,sizeof cl-1);close(fdc);}
  for(k=0;k+6<=m;k++)if(memcmp_(cl+k,"k32iso",6)==0)found=1;
  if(!found){puts("  (iso9660 : essai ignore, voir RUNISO.SH)\n");return 0;}
  fd=open("/dev/hdc",O_RDONLY,0);
  ktest("iso.cdrom_open",fd>=0);
  lseek(fd,16*2048,0);n=read(fd,b,8);
  ktest("iso.pvd",n==8&&b[0]==1&&memcmp_(b+1,"CD001",5)==0);
  close(fd);
  r=mount("/dev/hdc","/mnt","iso9660",1,0);
  ktest("iso.mount",r==0);
  if(r!=0)return 1;
  n=0;fd=open("/mnt/hello.txt",O_RDONLY,0);if(fd>=0){n=read(fd,b,100);close(fd);}
  ktest("iso.read_small",n==10&&memcmp_(b,"iso hello\n",10)==0);
  fd=open("/mnt/big.bin",O_RDONLY,0);ok=fd>=0;
  for(i=0;ok&&i<300000;){int w=read(fd,b,500),j;if(w<=0){ok=0;break;}for(j=0;j<w;j++)if((unsigned char)b[j]!=pat(i+j))ok=0;i+=w;}
  ktest("iso.read_big",ok&&i==300000);
  lseek(fd,131071,0);read(fd,b,10);ok=1;for(i=0;i<10;i++)if((unsigned char)b[i]!=pat(131071+i))ok=0;
  ktest("iso.seek_read",ok);close(fd);
  n=0;fd=open("/mnt/sub/deep/file.txt",O_RDONLY,0);if(fd>=0){n=read(fd,b,100);close(fd);}
  ktest("iso.deep_path",n==5&&memcmp_(b,"deep\n",5)==0);
  n=readlink("/mnt/link",c,127);
  ktest("iso.rr_symlink",n==9&&memcmp_(c,"hello.txt",9)==0);
  n=0;fd=open("/mnt/sub/up",O_RDONLY,0);if(fd>=0){n=read(fd,b,100);close(fd);}
  ktest("iso.symlink_follow",n==10);
  {char db[512];int d=open("/mnt/sub",O_RDONLY|O_DIRECTORY,0),t,cnt=0;
   while((t=getdents64(d,db,sizeof db))>0){int o=0;while(o<t){struct{unsigned long long i,o;unsigned short l;unsigned char ty;char nm[1];}*e=(void*)(db+o);cnt++;o+=e->l;}}
   ktest("iso.readdir",cnt==4);close(d);}
  ktest("iso.enoent",open("/mnt/nexiste",O_RDONLY,0)==-2);
  ktest("iso.rofs",open("/mnt/new",O_WRONLY|O_CREAT,0644)==-30);
  {unsigned long s[16];sc2(99,(long)"/mnt",(long)s);ktest("iso.statfs",s[1]==2048&&s[2]>100);}
  ktest("iso.umount",umount("/mnt")==0);
  return ku_fail?1:0;
}
