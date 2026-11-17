/* roottest : /sbin/init d'une racine reelle de type vfat, iso9660, minix,
   cramfs ou romfs (RUNROOT.SH, partie 38) : verifie le type monte comme
   racine (wantfs=... sur la ligne de commande) et le contenu. */
#include "ku.h"
static char b[512],cl[512];
static int slurp(const char*p,char*s,int max){int fd=open(p,O_RDONLY,0),n,t=0;if(fd<0)return fd;while(t<max-1&&(n=read(fd,s+t,max-1-t))>0)t+=n;s[t]=0;close(fd);return t;}
static int has(const char*h,const char*n){int l=strlen(n),i;for(i=0;h[i];i++)if(memcmp_(h+i,n,l)==0)return 1;return 0;}
int main(){
  int m=slurp("/proc/cmdline",cl,sizeof cl),i;char want[16]="";char mk[40];
  for(i=0;i+7<m;i++)if(memcmp_(cl+i,"wantfs=",7)==0){int k=0,j=i+7;while(cl[j]&&cl[j]!=' '&&cl[j]!='\n'&&k<15)want[k++]=cl[j++];want[k]=0;}
  ktest("root.pid1",getpid()==1);
  slurp("/proc/mounts",b,sizeof b);
  {char key[40];strcpy_(key," / ");strcpy_(key+3,want);strcpy_(key+3+strlen(want)," ");
   ktest("root.type",has(b,key));}
  strcpy_(mk,"marker-");strcpy_(mk+7,want);strcpy_(mk+7+strlen(want),"\n");
  ktest("root.marker",slurp("/etc/marker",b,sizeof b)>0&&strcmp(b,mk)==0);
  ktest("root.proc_dev",slurp("/proc/self/status",b,sizeof b)>0&&open("/dev/null",O_RDWR,0)>=0);
  puts("KTEST: root DONE\n");
  sync();reboot_off();
  return ku_fail?1:0;
}
