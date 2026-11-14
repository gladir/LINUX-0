/* swaptest : swap sur disque (noyau lance avec swap=/dev/hdb sur un disque
   prepare par mkswap, et peu de memoire : voir RUNSWAP.SH). Remplit plus de
   memoire anonyme qu'il n'y a de RAM, verifie le contenu apres page-out et
   page-in, fork avec cases de swap partagees, liberation des cases,
   swapoff (refuse faute de memoire, puis accepte), swapon. Sans swap actif
   (SwapTotal = 0 dans /proc/meminfo) le test est ignore. */
#include "ku.h"
#define PROT_READ 1
#define PROT_WRITE 2
#define MAP_PRIVATE 2
#define MAP_ANONYMOUS 0x20
static char mi[1024];
static long meminfo(const char*key){
  int fd=open("/proc/meminfo",O_RDONLY,0),n,i,k;
  long v=0;
  if(fd<0)return -1;
  n=read(fd,mi,sizeof mi-1);close(fd);
  if(n<=0)return -1;
  mi[n]=0;
  for(i=0;i<n;i++){
    for(k=0;key[k]&&mi[i+k]==key[k];k++);
    if(!key[k]){
      i+=k;
      while(mi[i]==' ')i++;
      while(mi[i]>='0'&&mi[i]<='9')v=v*10+(mi[i++]-'0');
      return v;
    }
  }
  return -1;
}
static unsigned val(unsigned i){return i*2654435761u^0x1234u;}
static int verify(unsigned char*p,unsigned pages,unsigned skip){
  unsigned i;
  for(i=0;i<pages;i++){
    if(skip&&i%skip==0)continue;
    if(*(unsigned*)(p+i*4096)!=val(i))return 0;
    if(p[i*4096+4095]!=(unsigned char)i)return 0;
  }
  return 1;
}
int main(void){
  long sw0,free0,sz,swused;
  unsigned pages,i;
  unsigned char*p;
  int pid,st;
  sw0=meminfo("SwapTotal:");
  if(sw0<=0){puts("  (pas de swap actif : tests swap ignores)\n");return 0;}
  free0=meminfo("MemFree:");
  sz=(free0+6*1024)*1024;
  pages=sz/4096;
  p=(unsigned char*)mmap2(0,sz,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
  ktest("swap.mmap",(long)p>0);
  if((long)p<=0)return 1;
  for(i=0;i<pages;i++){*(unsigned*)(p+i*4096)=val(i);p[i*4096+4095]=(unsigned char)i;}
  swused=sw0-meminfo("SwapFree:");
  ktest("swap.paged_out",swused>=2048);
  ktest("swap.verify_1",verify(p,pages,0));
  ktest("swap.verify_2",verify(p,pages,0));
  /* un fils lit tout (cases partagees) et modifie une page sur trois */
  pid=fork();
  if(pid==0){
    unsigned j;
    if(!verify(p,pages,0))_exit(1);
    for(j=0;j<pages;j+=3){*(unsigned*)(p+j*4096)=~val(j);}
    for(j=0;j<pages;j+=3)if(*(unsigned*)(p+j*4096)!=~val(j))_exit(2);
    for(j=0;j<pages;j++)if(j%3&&*(unsigned*)(p+j*4096)!=val(j))_exit(3);
    _exit(0);
  }
  waitpid(pid,&st,0);
  ktest("swap.fork_child",st==0);
  ktest("swap.parent_intact",verify(p,pages,0));
  /* swapoff avec des pages sur le disque : pas assez de RAM */
  ktest("swap.swapoff_enomem",sc1(115,(long)"/dev/hdb")==-12);
  ktest("swap.still_works",verify(p,pages,0)&&meminfo("SwapTotal:")==sw0);
  /* ecriture apres relecture, puis liberation */
  for(i=0;i<pages;i+=7)*(unsigned*)(p+i*4096)=val(i);
  ktest("swap.rewrite",verify(p,pages,0));
  ktest("swap.munmap",munmap(p,sz)==0);
  ktest("swap.slots_freed",sw0-meminfo("SwapFree:")<=64);
  ktest("swap.swapoff",sc1(115,(long)"/dev/hdb")==0&&meminfo("SwapTotal:")==0);
  ktest("swap.swapoff_twice",sc1(115,(long)"/dev/hdb")==-22);
  ktest("swap.swapon",sc2(87,(long)"/dev/hdb",0)==0&&meminfo("SwapTotal:")==sw0);
  ktest("swap.swapon_busy",sc2(87,(long)"/dev/hdb",0)==-16);
  puts("swap DONE\n");
  return 0;
}
