/* effects : parametres sysctl qui agissent (partie 38) : randomize_va_space
   (adresses de pile et de mmap), overcommit_memory/ratio, kernel.sysrq et
   /proc/sysrq-trigger. */
#include "ku.h"
static char b[512];
static int slurp(const char*p,char*s,int max){int fd=open(p,O_RDONLY,0),n,t=0;if(fd<0)return fd;while(t<max-1&&(n=read(fd,s+t,max-1-t))>0)t+=n;s[t]=0;close(fd);return t;}
static int put(const char*p,const char*s){int fd=open(p,O_WRONLY|O_TRUNC,0),n;if(fd<0)return fd;n=write(fd,s,strlen(s));close(fd);return n;}
static void* mm(unsigned long len,int prot,int flags){return mmap2(0,len,prot,flags|0x22&~flags?flags:flags,-1,0);}
#define MAP_PRIVATE 2
#define MAP_ANON 0x20
#define MAP_NORESERVE 0x4000
static long anon(unsigned long len,int prot,int fl){return (long)mmap2(0,len,prot,MAP_PRIVATE|MAP_ANON|fl,-1,0);}
static void hex(char*o,unsigned long v){int i;for(i=0;i<8;i++)o[i]="0123456789abcdef"[(v>>(28-4*i))&15];o[8]=0;}
/* un enfant exec(effects child) : affiche l'adresse d'une variable de pile et d'un mmap */
static void run_child(char*out){
  int p[2],r;pipe(p);
  r=fork();
  if(r==0){char*a[]={"/bin/effects","child",0};char*e[]={"X=1",0};dup2(p[1],1);close(p[0]);execve("/bin/effects",a,e);_exit(127);}
  close(p[1]);r=read(p[0],out,63);if(r<0)r=0;out[r]=0;close(p[0]);waitpid(-1,0,0);
}
int main(int argc,char**argv){
  int i,ok,distinct;char res[8][64];
  if(argc>1){char o[40];int local=0;long m=anon(4096,3,0);hex(o,(unsigned long)&local);o[8]=' ';hex(o+9,(unsigned long)m);o[17]='\n';o[18]=0;puts(o);return 0;}
  /* ASLR */
  ktest("aslr.default_2",slurp("/proc/sys/kernel/randomize_va_space",b,sizeof b)>0&&b[0]=='2');
  for(i=0;i<8;i++)run_child(res[i]);
  distinct=0;for(i=1;i<8;i++){int k,dup=0;for(k=0;k<i;k++)if(strcmp(res[i],res[k])==0)dup=1;if(!dup)distinct++;}
  ktest("aslr.randomized",distinct>=3);
  put("/proc/sys/kernel/randomize_va_space","0");
  for(i=0;i<4;i++)run_child(res[i]);
  ktest("aslr.disabled_stable",strcmp(res[0],res[1])==0&&strcmp(res[1],res[2])==0&&strcmp(res[2],res[3])==0&&res[0][0]);
  put("/proc/sys/kernel/randomize_va_space","2");
  /* overcommit */
  put("/proc/sys/vm/overcommit_memory","0");
  ktest("overcommit.heuristic_refuses_huge",anon(512UL<<20,3,0)==-12);
  ktest("overcommit.heuristic_small_ok",({long a=anon(1<<20,3,0);int g=a>0;if(g)munmap((void*)a,1<<20);g;}));
  ktest("overcommit.noreserve_ok",({long a=anon(512UL<<20,3,MAP_NORESERVE);int g=a>0;if(g)munmap((void*)a,512UL<<20);g;}));
  ktest("overcommit.none_ok",({long a=anon(512UL<<20,0,0);int g=a>0;if(g)munmap((void*)a,512UL<<20);g;}));
  put("/proc/sys/vm/overcommit_memory","1");
  ktest("overcommit.always",({long a=anon(512UL<<20,3,0);int g=a>0;if(g)munmap((void*)a,512UL<<20);g;}));
  put("/proc/sys/vm/overcommit_memory","2");put("/proc/sys/vm/overcommit_ratio","10");
  ktest("overcommit.strict_refuses",anon(100<<20,3,0)==-12);
  ktest("overcommit.strict_small_ok",({long a=anon(1<<20,3,0);int g=a>0;if(g)munmap((void*)a,1<<20);g;}));
  put("/proc/sys/vm/overcommit_ratio","100");
  ktest("overcommit.strict_ratio_100",({long a=anon(8<<20,3,0);int g=a>0;if(g)munmap((void*)a,8<<20);g;}));
  put("/proc/sys/vm/overcommit_memory","0");put("/proc/sys/vm/overcommit_ratio","50");
  /* sysrq */
  ktest("sysrq.default",slurp("/proc/sys/kernel/sysrq",b,sizeof b)>0&&b[0]=='1');
  ktest("sysrq.file_mode",({unsigned char s[96];sc2(SYS_stat64,(long)"/proc/sysrq-trigger",(long)s)==0&&((*(unsigned*)(s+16))&0777)==0200;}));
  ktest("sysrq.write_count",put("/proc/sysrq-trigger","s")==1&&put("/proc/sysrq-trigger","m")==1&&put("/proc/sysrq-trigger","h")==1&&put("/proc/sysrq-trigger","z")==1);
  {int p=fork();
   if(p==0){for(;;)pause();}
   put("/proc/sys/kernel/sysrq","0");
   put("/proc/sysrq-trigger","i");
   {int st=0,r=waitpid(p,&st,1/*WNOHANG*/);ktest("sysrq.disabled_no_kill",r==0);}
   put("/proc/sys/kernel/sysrq","64");
   put("/proc/sysrq-trigger","b");   /* b interdit par le masque (128) : sans effet */
   put("/proc/sysrq-trigger","i");
   {int st=0,r=waitpid(p,&st,0);ktest("sysrq.mask_signal_kill",r==p&&(st&0x7f)==9);}
   put("/proc/sys/kernel/sysrq","1");}
  {int p=fork();
   if(p==0){for(;;)pause();}
   put("/proc/sysrq-trigger","e");
   {int st=0,r=waitpid(p,&st,0);ktest("sysrq.term_all",r==p&&(st&0x7f)==15);}}
  ktest("sysrq.nonroot_denied",({int p=fork();int ok2=0;if(p==0){sc1(SYS_setuid,1000);_exit(open("/proc/sysrq-trigger",O_WRONLY,0)<0?0:1);}{int st=0;waitpid(p,&st,0);ok2=st==0;}ok2;}));
  (void)ok;(void)mm;
  if(ku_cmdline_has("effcrash")){puts("KTEST: effects crash\n");put("/proc/sysrq-trigger","c");}
  puts("KTEST: effects DONE\n");
  return ku_fail?1:0;
}
