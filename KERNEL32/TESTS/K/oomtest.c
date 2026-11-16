/* oomtest : tueur OOM (partie 39). Un fils qui consomme toute la memoire
   est tue par SIGKILL (message du journal, /proc/vmstat oom_kill), le pere
   et init survivent, la memoire est rendue. */
#include "ku.h"
#define MAP_PRIVATE 2
#define MAP_ANONYMOUS 0x20
static char sb[4096];
static int slurp(const char*p,char*s,int max){int fd=open(p,O_RDONLY,0),n;if(fd<0)return fd;n=read(fd,s,max-1);if(n<0)n=0;s[n]=0;close(fd);return n;}
static long vmstat(const char*key){int n=slurp("/proc/vmstat",sb,sizeof sb),i,kl=strlen(key);
  for(i=0;i+kl<n;i++)if((i==0||sb[i-1]=='\n')&&memcmp_(sb+i,key,kl)==0&&sb[i+kl]==' '){long v=0;int j=i+kl+1;while(sb[j]>='0'&&sb[j]<='9'){v=v*10+sb[j]-'0';j++;}return v;}
  return -1;}
int main(void){
  long k0=vmstat("oom_kill"),k1,free0,free1;int p,st=0,n;
  ktest("oom.vmstat_counter",k0>=0);
  if(k0<0){puts("KTEST: oom DONE\n");return 1;}
  free0=vmstat("nr_free_pages");
  p=fork();
  if(p==0){
    int i,j;
    for(i=0;i<400;i++){
      char*m=(char*)mmap2(0,1<<20,3,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
      if((long)m<0&&(long)m>-4096)continue;
      for(j=0;j<256;j++)m[j*4096]=1;
    }
    _exit(0);
  }
  waitpid(p,&st,0);
  ktest("oom.child_killed",(st&0x7f)==9);
  k1=vmstat("oom_kill");
  ktest("oom.counter_increased",k1==k0+1);
  free1=vmstat("nr_free_pages");
  ktest("oom.memory_returned",free1>free0-200);
  /* le pere peut encore allouer et utiliser de la memoire */
  {char*m=(char*)mmap2(0,4<<20,3,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);int j,ok=1;
   if((long)m<0&&(long)m>-4096)ok=0;
   else{for(j=0;j<1024;j++)m[j*4096]=(char)j;for(j=0;j<1024;j++)if(m[j*4096]!=(char)j)ok=0;munmap(m,4<<20);}
   ktest("oom.parent_alive",ok);}
  /* une seconde victime, de nouveau */
  p=fork();
  if(p==0){int i,j;for(i=0;i<400;i++){char*m=(char*)mmap2(0,1<<20,3,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);if((long)m<0&&(long)m>-4096)continue;for(j=0;j<256;j++)m[j*4096]=1;}_exit(0);}
  waitpid(p,&st,0);
  ktest("oom.second_kill",(st&0x7f)==9&&vmstat("oom_kill")==k0+2);
  n=getpid();ktest("oom.init_alive",n>0);
  puts("KTEST: oom DONE\n");
  return ku_fail?1:0;
}
