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
static char pbuf[1024];
static int has(const char*hay,const char*needle){
  int l=strlen(needle),i;
  for(i=0;hay[i];i++)if(memcmp_(hay+i,needle,l)==0)return 1;
  return 0;
}
int main(void){
  long sw0,free0,sz,swused;
  unsigned pages,i;
  unsigned char*p;
  int pid,st,isfile=0;
  const char*swp="/dev/hdb";
  sw0=meminfo("SwapTotal:");
  if(sw0<=0&&ku_cmdline_has("swapfile")){
    /* swap sur fichier ordinaire d'un ext2 (disque hdb sans partition) */
    int fd;
    static unsigned char pg[4096];
    unsigned k;
    ktest("swapfile.mount",mount("/dev/hdb","/mnt","ext2",0,0)==0);
    /* creation du fichier de swap (24 Mo non creux, entete SWAPSPACE2 version 1) */
    fd=open("/mnt/swapfile",O_RDWR|O_CREAT|O_TRUNC,0600);
    {int ok=fd>=0;
     for(k=0;ok&&k<6144;k++){
       memset(pg,0x55,sizeof pg);
       if(k==0){memset(pg,0,sizeof pg);*(unsigned*)(pg+1024)=1;*(unsigned*)(pg+1028)=6143;memcpy(pg+4086,"SWAPSPACE2",10);}
       if(write(fd,pg,4096)!=4096)ok=0;
     }
     ktest("swapfile.create",ok);}
    if(fd>=0){sync();close(fd);}
    ktest("swapfile.holes_einval",sc2(87,(long)"/mnt/holes",0)==-22);
    ktest("swapfile.notswap_einval",sc2(87,(long)"/mnt/filler",0)==-22);
    ktest("swapfile.dir_einval",sc2(87,(long)"/mnt",0)==-22);
    ktest("swapfile.enoent",sc2(87,(long)"/mnt/nexistepas",0)<0);
    ktest("swapfile.swapon",sc2(87,(long)"/mnt/swapfile",0x8000|5)==0);
    sw0=meminfo("SwapTotal:");
    ktest("swapfile.total",sw0>=8192);
    fd=open("/proc/swaps",O_RDONLY,0);
    st=fd>=0?read(fd,pbuf,sizeof pbuf-1):0;if(st<0)st=0;pbuf[st]=0;if(fd>=0)close(fd);
    ktest("swapfile.proc_swaps",has(pbuf,"/mnt/swapfile")&&has(pbuf,"file")&&has(pbuf,"\t5"));
    ktest("swapfile.busy",sc2(87,(long)"/mnt/swapfile",0)==-16);
    ktest("swapfile.open_write_txtbsy",open("/mnt/swapfile",O_WRONLY,0)==-26);
    ktest("swapfile.trunc_txtbsy",open("/mnt/swapfile",O_RDONLY|O_TRUNC,0)==-26);
    ktest("swapfile.open_read_ok",({int f=open("/mnt/swapfile",O_RDONLY,0);int ok=f>=0;if(ok)close(f);ok;}));
    ktest("swapfile.umount_busy",umount("/mnt")==-16);
    swp="/mnt/swapfile";isfile=1;
  }
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
  ktest("swap.swapoff_enomem",sc1(115,(long)swp)==-12);
  ktest("swap.still_works",verify(p,pages,0)&&meminfo("SwapTotal:")==sw0);
  /* ecriture apres relecture, puis liberation */
  for(i=0;i<pages;i+=7)*(unsigned*)(p+i*4096)=val(i);
  ktest("swap.rewrite",verify(p,pages,0));
  ktest("swap.munmap",munmap(p,sz)==0);
  ktest("swap.slots_freed",sw0-meminfo("SwapFree:")<=64);
  ktest("swap.swapoff",sc1(115,(long)swp)==0&&meminfo("SwapTotal:")==0);
  ktest("swap.swapoff_twice",sc1(115,(long)swp)==-22);
  ktest("swap.swapon",sc2(87,(long)swp,0)==0&&meminfo("SwapTotal:")==sw0);
  ktest("swap.swapon_busy",sc2(87,(long)swp,0)==-16);
  if(isfile){
    ktest("swapfile.swapoff",sc1(115,(long)swp)==0);
    ktest("swapfile.writable_again",({int f=open("/mnt/swapfile",O_WRONLY,0);int ok=f>=0;if(ok)close(f);ok;}));
    ktest("swapfile.umount",umount("/mnt")==0);
  }
  puts("swap DONE\n");
  return 0;
}
