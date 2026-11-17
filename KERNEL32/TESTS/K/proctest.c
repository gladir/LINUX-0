/* proctest : /proc (version, meminfo, uptime, mounts, self, N/stat, N/status, N/maps, N/cmdline) */
#include "ku.h"
static int slurp(const char*p,char*b,int n){int fd=open(p,O_RDONLY,0),r;if(fd<0)return fd;r=read(fd,b,n-1);close(fd);if(r>=0)b[r]=0;return r;}
static int has(const char*h,const char*n){size_t l=strlen(n),i;for(i=0;h[i];i++)if(!memcmp_(h+i,n,l))return 1;return 0;}
static void itoa_(int v,char*o){char t[16];int i=0,j=0;if(!v)t[i++]='0';while(v){t[i++]='0'+v%10;v/=10;}while(i)o[j++]=t[--i];o[j]=0;}
int main(void){
  char b[2048],p[64];int n;
  n=slurp("/proc/version",b,sizeof b);
  ktest("proc.version",n>0&&has(b,"KERNEL32"));
  n=slurp("/proc/meminfo",b,sizeof b);
  ktest("proc.meminfo",n>0&&has(b,"MemTotal:")&&has(b,"MemFree:"));
  n=slurp("/proc/uptime",b,sizeof b);
  ktest("proc.uptime",n>0&&b[0]>='0'&&b[0]<='9');
  n=slurp("/proc/mounts",b,sizeof b);
  ktest("proc.mounts",n>0&&has(b," / tmpfs")&&has(b,"proc"));
  n=slurp("/proc/self/stat",b,sizeof b);
  char me[16];itoa_(getpid(),me);
  ktest("proc.self.stat",n>0&&has(b,"(proctest)")&&b[0]==me[0]);
  n=slurp("/proc/self/status",b,sizeof b);
  ktest("proc.self.status",n>0&&has(b,"Name:   proctest")&&has(b,"Uid:    0"));
  strcpy_(p,"/proc/");strcpy_(p+6,me);strcpy_(p+6+strlen(me),"/cmdline");
  n=slurp(p,b,sizeof b);
  ktest("proc.cmdline",n>=9&&has(b,"/bin/proctest"));
  n=slurp("/proc/self/maps",b,sizeof b);
  ktest("proc.maps",n>0&&has(b,"r-xp")&&has(b,"[stack]"));
  n=slurp("/proc/filesystems",b,sizeof b);
  ktest("proc.filesystems",n>0&&has(b,"tmpfs"));
  int fd=open("/proc",O_RDONLY|O_DIRECTORY,0);char d[1024];int k=0,found=0;
  while((k=getdents64(fd,d,sizeof d))>0){int o=0;while(o<k){struct{unsigned long long i,o;unsigned short l;unsigned char t;char nm[1];}*e=(void*)(d+o);if(!strcmp(e->nm,me))found=1;o+=e->l;}}
  close(fd);
  ktest("proc.readdir_pid",found);
  ktest("proc.enoent",open("/proc/99999/stat",O_RDONLY,0)==-2);
  return ku_fail?1:0;
}
