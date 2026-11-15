/* preempttest : preemption du noyau (preempt=1). Latence : un processus fait
   des appels systeme longs (lectures/ecritures de gros tampons dans un tube
   et un fichier) pendant qu'un autre, en mode utilisateur pur, mesure les
   trous entre ses lectures de l'horloge ; avec preempt=1 le noyau est
   preempte (compteur kpreempt de /proc/stat) et le trou maximal reste
   borne. Sans preempt=1 le test est ignore. */
#include "ku.h"
#define SYS_gettimeofday 78
#define MAP_PRIVATE 2
#define MAP_ANONYMOUS 0x20
#define PROT_READ 1
#define PROT_WRITE 2
static unsigned long long rdtsc(void){unsigned lo,hi;__asm__ volatile("rdtsc":"=a"(lo),"=d"(hi));return ((unsigned long long)hi<<32)|lo;}
static long us(void){long tv[2];sc2(SYS_gettimeofday,(long)tv,0);return tv[0]*1000000+tv[1];}
static char sb[2048];
static long kp(int*on){
  int fd=open("/proc/stat",O_RDONLY,0),n,i;long v=-1;
  *on=0;
  if(fd<0)return -1;
  n=read(fd,sb,sizeof sb-1);close(fd);if(n<=0)return -1;sb[n]=0;
  for(i=0;i<n;i++)if(sb[i]=='k'&&memcmp_(sb+i,"kpreempt ",9)==0){
    int j=i+9;v=0;while(sb[j]>='0'&&sb[j]<='9'){v=v*10+sb[j]-'0';j++;}
    while(sb[j]==' ')j++;*on=sb[j]=='1';return v;}
  return -1;
}
int main(void){
  int on,p,st,i,round;long k0,k1;
  static char big[65536];
  unsigned long long c0,c,last;unsigned maxgap=0,cycles_per_ms,cpus;
  long t0,t1,n=0,gap_us;
  kp(&on);
  /* le pere reste en mode utilisateur pur (rdtsc, aucun appel systeme) :
     il ne peut pas etre bloque par le verrou du noyau */
  t0=us();c0=rdtsc();while(us()-t0<100000);t1=us();
  cycles_per_ms=(unsigned)(rdtsc()-c0)/(unsigned)((t1-t0)/1000);
  cpus=cycles_per_ms/1000;if(!cpus)cpus=1;
  for(round=0;round<3;round++){
  maxgap=0;n=0;
  k0=kp(&on);
  p=fork();
  if(p==0){
    /* fils : longues sections noyau (tubes, fichiers, mmap, lecture de 24 Mo) */
    int fd=open("/tmp/pre.dat",O_RDWR|O_CREAT|O_TRUNC,0644);
    long ts=us();
    while(us()-ts<2500000){
      for(i=0;i<20;i++){write(fd,big,sizeof big);lseek(fd,0,0);read(fd,big,sizeof big);lseek(fd,0,0);}
      {char*m=(char*)mmap2(0,4096*256,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
       if((long)m>0){for(i=0;i<256;i++)m[i*4096]=1;munmap(m,4096*256);}}
      {int z=open("/dev/zero",O_RDONLY,0);
       char*m=(char*)mmap2(0,24<<20,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
       if((long)m>0&&z>=0){read(z,m,24<<20);munmap(m,24<<20);}
       if(z>=0)close(z);}
    }
    unlink("/tmp/pre.dat");
    _exit(0);
  }
  c0=last=rdtsc();
  while((c=rdtsc())-c0<2000*cycles_per_ms){if((unsigned)(c-last)>maxgap)maxgap=(unsigned)(c-last);last=c;n++;}
  gap_us=(long)(maxgap/cpus);
  waitpid(p,&st,0);
  k1=kp(&on);
  if(!on||k1>k0)break;
  }
  ktest("preempt.user_loop_ran",n>1000);
  ktest("preempt.child_ok",st==0);
  if(on){
    ktest("preempt.kernel_preempted",k1>k0);
    ktest("preempt.max_gap_bounded",gap_us<200000);
  }
  puts("preempt on=");putd(on);puts(" maxgap_us=");putd(gap_us);puts(" kpreempt=");putd(k1-k0);puts(" loops=");putd(n);puts("\n");
  puts("preempt DONE\n");
  return 0;
}
