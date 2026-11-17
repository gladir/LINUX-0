/* cgtest : cgroup v2 minimal (fs cgroup2 monte sur /sys/fs/cgroup) :
   fichiers de controle, deplacement de processus, pids.max, memory.max,
   cpu.weight, /proc/PID/cgroup, rmdir, droits */
#include "ku.h"
#ifndef WIFEXITED
#define WIFEXITED(s) (((s)&0x7f)==0)
#define WEXITSTATUS(s) (((s)>>8)&0xff)
#define WIFSIGNALED(s) (((s)&0x7f)!=0&&((s)&0x7f)!=0x7f)
#endif
static char*strcat_(char*d,const char*s){char*r=d;while(*d)d++;while((*d++=*s++));return r;}
static int slurp(const char*p,char*s,int max){int fd=open(p,O_RDONLY,0),n;if(fd<0)return fd;n=read(fd,s,max-1);if(n<0)n=0;s[n]=0;close(fd);return n;}
static int wr(const char*p,const char*s){int fd=open(p,O_WRONLY,0),n;if(fd<0)return fd;n=write(fd,s,strlen(s));close(fd);return n;}
static void utoa_(unsigned v,char*b){char t[12];int n=0,i;if(!v)t[n++]='0';while(v){t[n++]='0'+v%10;v/=10;}for(i=0;i<n;i++)b[i]=t[n-1-i];b[n]=0;}
static int setaff(int pid,unsigned long m){return sc3(241,pid,4,(long)&m);}
static int has(const char*h,const char*n){int i,l=strlen(n);for(i=0;h[i];i++)if(memcmp_(h+i,n,l)==0)return 1;return 0;}
static long utime_of(int pid){char p[40]="/proc/",b[512];int n,i,f=0;long v=0;utoa_(pid,p+6);strcat_(p,"/stat");n=slurp(p,b,sizeof b);
  for(i=0;i<n;i++)if(b[i]==')'){i+=2;break;}
  for(;i<n;i++){if(b[i]==' '){f++;if(f==11){i++;while(b[i]>='0'&&b[i]<='9')v=v*10+b[i++]-'0';return v;}}}
  return -1;}
#define CG "/sys/fs/cgroup"
int main(void){
  char b[512],pid[16];int r,p[2],q[2],st;
  mkdir("/sys/fs",0755);mkdir(CG,0755);
  r=mount("none",CG,"cgroup2",0,0);
  ktest("cg.mount",r==0);
  if(r!=0)return 1;
  r=slurp(CG "/cgroup.controllers",b,sizeof b);
  ktest("cg.root_controllers",r>0&&has(b,"cpu")&&has(b,"memory")&&has(b,"pids"));
  ktest("cg.mkdir",mkdir(CG "/t1",0755)==0);
  r=slurp(CG "/t1/pids.max",b,sizeof b);ktest("cg.pids_max_default",r==4&&memcmp_(b,"max\n",4)==0);
  r=slurp(CG "/t1/memory.max",b,sizeof b);ktest("cg.memory_max_default",r==4&&memcmp_(b,"max\n",4)==0);
  r=slurp(CG "/t1/cpu.weight",b,sizeof b);ktest("cg.cpu_weight_default",r==4&&memcmp_(b,"100\n",4)==0);
  ktest("cg.create_denied",open(CG "/t1/x",O_CREAT|O_WRONLY,0644)<0);
  ktest("cg.weight_invalid",wr(CG "/t1/cpu.weight","0")==-22&&wr(CG "/t1/cpu.weight","abc")==-22);
  ktest("cg.weight_set",wr(CG "/t1/cpu.weight","400\n")==4);
  r=slurp(CG "/t1/cpu.weight",b,sizeof b);ktest("cg.weight_readback",r==4&&memcmp_(b,"400\n",4)==0);
  wr(CG "/t1/cpu.weight","100");
  /* pids.max */
  pipe(p);pipe(q);
  {int c=fork();
   if(c==0){char t;int g1,g2,qq[2];close(p[1]);read(p[0],&t,1);pipe(qq);
     g1=fork();if(g1==0){char u;close(qq[1]);read(qq[0],&u,1);_exit(0);}
     g2=fork();
     close(qq[1]);if(g1>0)waitpid(g1,0,0);
     _exit(g1>0&&g2==-11?0:1);}
   utoa_(c,pid);
   ktest("cg.pids_max_set",wr(CG "/t1/pids.max","2\n")==2);
   ktest("cg.move",wr(CG "/t1/cgroup.procs",pid)>0);
   r=slurp(CG "/t1/cgroup.procs",b,sizeof b);ktest("cg.procs_lists",r>0&&has(b,pid));
   r=slurp(CG "/t1/pids.current",b,sizeof b);ktest("cg.pids_current",r==2&&b[0]=='1');
   {char pp[40]="/proc/";utoa_(c,pp+6);strcat_(pp,"/cgroup");r=slurp(pp,b,sizeof b);
    ktest("cg.proc_cgroup",r>0&&has(b,"0::/t1"));}
   ktest("cg.rmdir_busy",rmdir(CG "/t1")==-16);
   write(p[1],"x",1);waitpid(c,&st,0);
   ktest("cg.pids_limit_eagain",WIFEXITED(st)&&WEXITSTATUS(st)==0);}
  /* memory.max : une tache qui depasse est tuee */
  pipe(p);
  wr(CG "/t1/pids.max","max");
  {int c=fork();
   if(c==0){char t;close(p[1]);read(p[0],&t,1);
     {volatile char*m=(char*)mmap2(0,4<<20,3,0x22,-1,0);long i;if((long)m<=0)_exit(2);
      for(i=0;i<(4<<20);i+=4096)m[i]=1;}
     _exit(0);}
   utoa_(c,pid);
   ktest("cg.memory_set",wr(CG "/t1/memory.max","1M\n")==3);
   r=slurp(CG "/t1/memory.max",b,sizeof b);ktest("cg.memory_readback",r>0&&has(b,"1048576"));
   wr(CG "/t1/cgroup.procs",pid);
   write(p[1],"x",1);waitpid(c,&st,0);
   ktest("cg.memory_kill",WIFSIGNALED(st)&&(st&0x7f)==9);}
  r=slurp(CG "/t1/cgroup.procs",b,sizeof b);ktest("cg.procs_empty_after_exit",r==0);
  /* droits : un utilisateur ordinaire ne modifie rien */
  {int c=fork();if(c==0){int x;sc1(23,1000);x=wr(CG "/t1/pids.max","5");_exit(x==-13?0:1);}
   waitpid(c,&st,0);ktest("cg.nonroot_eacces",WIFEXITED(st)&&WEXITSTATUS(st)==0);}
  ktest("cg.rmdir",rmdir(CG "/t1")==0);
  ktest("cg.rmdir_gone",slurp(CG "/t1/pids.max",b,sizeof b)<0);
  /* cpu.weight : deux taches liees au meme CPU, poids 400 contre 100 */
  mkdir(CG "/hi",0755);mkdir(CG "/lo",0755);
  wr(CG "/hi/cpu.weight","400");wr(CG "/lo/cpu.weight","100");
  {int ch[2],k;long u[2];
   for(k=0;k<2;k++){ch[k]=fork();
     if(ch[k]==0){volatile unsigned long x=0;setaff(0,1);for(;;)x++;}}
   for(k=0;k<2;k++){utoa_(ch[k],pid);setaff(ch[k],1);wr(k==0?CG "/hi/cgroup.procs":CG "/lo/cgroup.procs",pid);}
   {long ts[2]={4,0};nanosleep(ts,0);}
   for(k=0;k<2;k++)u[k]=utime_of(ch[k]);
   for(k=0;k<2;k++){kill(ch[k],9);waitpid(ch[k],0,0);}
   puts("  cpu.weight : ticks 400 -> ");putd(u[0]);puts(", 100 -> ");putd(u[1]);puts("\n");
   ktest("cg.cpu_weight_share",u[0]>0&&u[1]>0&&u[0]>=2*u[1]);}
  rmdir(CG "/hi");rmdir(CG "/lo");
  umount(CG);
  puts("KTEST: cg DONE\n");
  return ku_fail?1:0;
}
