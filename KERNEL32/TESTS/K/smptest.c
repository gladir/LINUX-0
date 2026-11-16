/* smptest : SMP reel (partie 39) : les processeurs annonces par l'ACPI
   executent des taches en parallele sous le verrou noyau unique.
   Coherence de /sys et /proc, sched_setaffinity / sched_getaffinity /
   getcpu reels, execution parallele (comptabilite par CPU de /proc/stat),
   IPI de vidage de TLB (mprotect d'une page lue par un thread d'un autre
   CPU), /proc/interrupts par CPU. Avec un seul CPU : verifications
   mono-processeur. */
#include "ku.h"
#define SYS_getcpu 318
#define CLONE_FLAGS 0x50f00   /* VM FS FILES SIGHAND THREAD */
#define SYS_clone_ 120
#define WIFEXITED(s) (((s)&0x7f)==0)
#define WEXITSTATUS(s) (((s)>>8)&0xff)
static char b[4096];
static int slurp(const char*p,char*s,int max){int fd=open(p,O_RDONLY,0),n;if(fd<0)return fd;n=read(fd,s,max-1);if(n<0)n=0;s[n]=0;close(fd);return n;}
static unsigned long long rdtsc_(void){unsigned lo,hi;__asm__ volatile("rdtsc":"=a"(lo),"=d"(hi));return ((unsigned long long)hi<<32)|lo;}
static long us(void){long tv[2];sc2(SYS_gettimeofday,(long)tv,0);return tv[0]*1000000+tv[1];}
/* "0" ou "0-N" -> N+1 */
static int range_count(const char*s){int n=0,i;if(s[0]!='0')return 0;if(s[1]=='-'){for(i=2;s[i]>='0'&&s[i]<='9';i++)n=n*10+s[i]-'0';return n+1;}return 1;}
static int getcpu_(void){unsigned c=99,nd=99;sc3(SYS_getcpu,(long)&c,(long)&nd,0);return (int)c;}
static int setaff(int pid,unsigned long m){return sc3(241,pid,4,(long)&m);}
/* ticks utilisateur du CPU k lus dans /proc/stat (ligne "cpuK u n s i") */
static long cpu_user(int k){
  int r=slurp("/proc/stat",b,sizeof b),i;char key[8];int kl=0;
  key[kl++]='c';key[kl++]='p';key[kl++]='u';if(k>=10)key[kl++]='0'+k/10;key[kl++]='0'+k%10;key[kl++]=' ';
  for(i=0;i+kl<r;i++)if((i==0||b[i-1]=='\n')&&memcmp_(b+i,key,kl)==0){
    long v=0;int j=i+kl;while(b[j]>='0'&&b[j]<='9'){v=v*10+b[j]-'0';j++;}return v;}
  return -1;}
static long cpu_idle(int k){
  int r=slurp("/proc/stat",b,sizeof b),i,f;char key[8];int kl=0;
  key[kl++]='c';key[kl++]='p';key[kl++]='u';if(k>=10)key[kl++]='0'+k/10;key[kl++]='0'+k%10;key[kl++]=' ';
  for(i=0;i+kl<r;i++)if((i==0||b[i-1]=='\n')&&memcmp_(b+i,key,kl)==0){
    int j=i+kl;long v=0;for(f=0;f<4;f++){v=0;while(b[j]==' ')j++;while(b[j]>='0'&&b[j]<='9'){v=v*10+b[j]-'0';j++;}}
    return v;}
  return -1;}
/* ---- thread qui lit une page pendant que le pere change sa protection ---- */
static volatile int *vp;
static volatile int th_ready,th_segv,th_cpu=-1;
static unsigned long th_mask;
static char tstack[8192] __attribute__((aligned(16)));
static void on_segv(int s){(void)s;th_segv=1;sc1(SYS_exit,0);}
static void thread_fn(void){
  int v=0;
  setaff(0,th_mask);
  while(getcpu_()!=th_cpu&&v<100000){sched_yield();v++;}
  th_ready=1;
  for(;;){*vp=v++;}
}
static long clone_thread(void(*fn)(void),char*top){
  long r;
  ((long*)top)[-1]=(long)fn;
  __asm__ volatile("int $0x80\n\t"
    "test %%eax,%%eax\n\t"
    "jnz 1f\n\t"
    "pop %%eax\n\t"
    "call *%%eax\n\t"
    "mov $1,%%eax\n\txor %%ebx,%%ebx\n\tint $0x80\n"
    "1:"
    :"=a"(r):"a"(SYS_clone_),"b"(CLONE_FLAGS),"c"(top-4),"d"(0),"S"(0),"D"(0):"memory");
  return r;
}
int main(){
  int n_present,n_online,i,r,cnt;
  slurp("/sys/devices/system/cpu/present",b,sizeof b);
  n_present=range_count(b);
  ktest("smp.present_format",n_present>=1&&n_present<=16);
  slurp("/sys/devices/system/cpu/online",b,sizeof b);
  n_online=range_count(b);
  ktest("smp.online_format",n_online>=1&&n_online<=n_present);
  slurp("/sys/devices/system/cpu/offline",b,sizeof b);
  if(n_online<n_present){int m=0;for(i=0;b[i]>='0'&&b[i]<='9';i++)m=m*10+b[i]-'0';
    ktest("smp.offline_range",m==n_online);}
  else ktest("smp.offline_range",b[0]=='\n'||b[0]==0);
  {int ok=1;char p[64];for(i=0;i<n_present;i++){
     char d[4];d[0]='0'+i/10;d[1]='0'+i%10;d[2]=0;
     strcpy_(p,"/sys/devices/system/cpu/cpu");strcpy_(p+27,i<10?d+1:d);
     {int l=strlen(p);strcpy_(p+l,i?"/online":"");}
     if(i==0){int fd=open("/sys/devices/system/cpu/cpu0",O_RDONLY|O_DIRECTORY,0);if(fd<0)ok=0;else close(fd);}
     else{int rr=slurp(p,b,sizeof b);if(rr<1||b[0]!=(i<n_online?'1':'0'))ok=0;}}
   ktest("smp.cpu_dirs",ok);}
  cnt=0;r=slurp("/proc/cpuinfo",b,sizeof b);
  for(i=0;i<r;i++)if(b[i]=='p'&&memcmp_(b+i,"processor",9)==0)cnt++;
  ktest("smp.cpuinfo_count",cnt==n_online);
  {int has=0,k;for(k=0;k<r;k++)if(memcmp_(b+k,"apicid",6)==0)has=1;ktest("smp.cpuinfo_apicid",has);}
  {int ok=1;for(i=0;i<n_online;i++)if(cpu_user(i)<0)ok=0;
   ktest("smp.stat_per_cpu",ok&&cpu_user(n_online)<0);}
  {unsigned long m[4]={0,0,0,0};long rr=sc3(242,0,16,(long)m);
   ktest("smp.affinity_all",rr>=4&&m[0]==(n_online>=32?0xffffffffUL:((1UL<<n_online)-1)));
   m[0]=1UL<<n_online;ktest("smp.setaffinity_offline_cpu",sc3(241,0,4,(long)m)==-22);
   m[0]=0;ktest("smp.setaffinity_empty",sc3(241,0,4,(long)m)==-22);
   m[0]=1;ktest("smp.setaffinity_cpu0",sc3(241,0,4,(long)m)==0&&getcpu_()==0);
   m[0]=(1UL<<n_online)-1;ktest("smp.setaffinity_all",sc3(241,0,4,(long)m)==0);}
  ktest("smp.getcpu_range",getcpu_()>=0&&getcpu_()<n_online);
  ktest("smp.setaffinity_esrch",setaff(99999,1)==-3);
  if(n_online>1){
    int k,okall=1;
    /* chaque CPU execute vraiment une tache epinglee */
    for(k=0;k<n_online;k++){
      int p=fork(),st=0;
      if(p==0){
        long t0;int ok=0,v;
        setaff(0,1UL<<k);
        for(v=0;v<2000&&getcpu_()!=k;v++)sched_yield();
        t0=us();ok=1;
        while(us()-t0<150000){if(getcpu_()!=k){ok=0;break;}}
        _exit(ok?0:1);
      }
      waitpid(p,&st,0);
      if(!WIFEXITED(st)||WEXITSTATUS(st)!=0)okall=0;
    }
    ktest("smp.pinned_each_cpu",okall);
    /* parallelisme : deux processus epingles occupent deux CPU en meme temps */
    {long u0[16],u1[16],t0;int p[16],j,pk=n_online<4?n_online:4,par=0;
     unsigned long long c0,cyc;
     { long a=us();c0=rdtsc_();while(us()-a<100000);cyc=(rdtsc_()-c0)*12;}
     for(j=0;j<pk;j++)u0[j]=cpu_user(j);
     for(j=0;j<pk;j++){p[j]=fork();
       if(p[j]==0){unsigned long long t;setaff(0,1UL<<j);t=rdtsc_();while(rdtsc_()-t<cyc);_exit(0);}}
     t0=us();while(us()-t0<1000000)sched_yield();
     for(j=0;j<pk;j++)u1[j]=cpu_user(j);
     for(j=0;j<pk;j++){int st;waitpid(p[j],&st,0);}
     for(j=0;j<pk;j++)if(u1[j]-u0[j]>=60)par++;
     ktest("smp.parallel_user_ticks",par==pk);}
    /* TLB : un thread d'un autre CPU ecrit une page ; mprotect(PROT_READ) du
       pere doit lui valoir SIGSEGV (IPI de vidage de TLB ; PROT_NONE
       laisse la page lisible : limite connue) */
    {char*pg=(char*)mmap2(0,4096,3,0x22,-1,0);long t0;int ok=0;
     if((long)pg>0&&(long)pg<0xc0000000L){
       vp=(volatile int*)pg;*vp=1;th_ready=0;th_segv=0;
       th_cpu=1;th_mask=2;
       setaff(0,1);
       signal_set(11,on_segv,0);
       if(clone_thread(thread_fn,tstack+sizeof tstack)>0){
         t0=us();while(!th_ready&&us()-t0<2000000)sched_yield();
         if(th_ready){
           t0=us();while(us()-t0<50000);
           mprotect(pg,4096,1);
           t0=us();while(!th_segv&&us()-t0<2000000)sched_yield();
           ok=th_segv;}
       }
     }
     if(!ok){puts("  tlb: ready=");putd(th_ready);puts(" segv=");putd(th_segv);puts(" cpu=");putd(th_cpu);puts("\n");{int r2=slurp("/proc/interrupts",b,sizeof b);write(1,b,r2);}}
     ktest("smp.tlb_shootdown_mprotect",ok);}
    /* appels systeme sans verrou noyau : getpid en parallele sur 2 CPU */
    if(!ku_cmdline_has("nofastsys")){
      long t0,t1,t2,f0,f1;int p1,p2,st,j;
      #define NLOOP 300000
      #define STATV(key) ({int rr=slurp("/proc/stat",b,sizeof b),ii;long vv=-1;for(ii=0;ii+8<rr;ii++)if(memcmp_(b+ii,key" ",strlen(key)+1)==0){vv=0;int jj=ii+strlen(key)+1;while(b[jj]>='0'&&b[jj]<='9'){vv=vv*10+b[jj]-'0';jj++;}break;}vv;})
      f0=STATV("fastsys");
      t0=us();p1=fork();
      if(p1==0){setaff(0,1);for(j=0;j<NLOOP;j++)sc0(SYS_getpid);_exit(0);}
      waitpid(p1,&st,0);t1=us()-t0;
      f1=STATV("fastsys");
      ktest("smp.fastsys_counted",f0>=0&&f1-f0>=NLOOP);
      t0=us();p1=fork();
      if(p1==0){setaff(0,1);for(j=0;j<NLOOP;j++)sc0(SYS_getpid);_exit(0);}
      p2=fork();
      if(p2==0){setaff(0,2);for(j=0;j<NLOOP;j++)sc0(SYS_getpid);_exit(0);}
      waitpid(p1,&st,0);waitpid(p2,&st,0);t2=us()-t0;
      puts("  getpid : un CPU ");putd(t1/1000);puts(" ms, deux CPU ");putd(t2/1000);puts(" ms\n");
      /* sous un verrou unique le temps doublerait (rapport 2) ; en parallele il reste proche de 1 */
      /* temoin : getppid passe par le verrou noyau ; sur deux CPU son temps
         double presque, celui de getpid doit en rester nettement plus
         proche de celui d'un seul (QEMU ne donne pas un parallelisme
         parfait : on compare les deux rapports) */
      {long s1,s2;
       t0=us();p1=fork();
       if(p1==0){setaff(0,1);for(j=0;j<NLOOP/10;j++)sc0(SYS_getppid);_exit(0);}
       waitpid(p1,&st,0);s1=us()-t0;
       t0=us();p1=fork();
       if(p1==0){setaff(0,1);for(j=0;j<NLOOP/10;j++)sc0(SYS_getppid);_exit(0);}
       p2=fork();
       if(p2==0){setaff(0,2);for(j=0;j<NLOOP/10;j++)sc0(SYS_getppid);_exit(0);}
       waitpid(p1,&st,0);waitpid(p2,&st,0);s2=us()-t0;
       puts("  getppid (verrou) : un CPU ");putd(s1/1000);puts(" ms, deux CPU ");putd(s2/1000);puts(" ms\n");
       ktest("smp.fastsys_parallel",t2*10<t1*14||(long long)t2*s1*10<(long long)s2*t1*8);}
    }
    /* /proc/interrupts : une colonne par CPU, minuterie locale qui avance */
    r=slurp("/proc/interrupts",b,sizeof b);
    {char key[8];int has=0;key[0]='C';key[1]='P';key[2]='U';key[3]='0'+(n_online>9?9:n_online-1);key[4]=0;
     for(i=0;i+4<r;i++)if(memcmp_(b+i,key,4)==0)has=1;
     ktest("smp.interrupts_columns",has);}
    {int has=0;for(i=0;i+4<r;i++)if(memcmp_(b+i,"LOC:",4)==0)has=1;
     ktest("smp.interrupts_loc",has);}
    {long i0=cpu_idle(1),i1;long t0=us();while(us()-t0<500000)sched_yield();i1=cpu_idle(1);
     ktest("smp.idle_cpu_ticks",i1>i0);}
  }
  puts("KTEST: smp DONE\n");
  return ku_fail?1:0;
}
