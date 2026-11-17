/* looptest : peripheriques loop (partie 38) : /dev/loop0..7, loop-control,
   LOOP_SET_FD/CLR_FD/SET_STATUS64/GET_STATUS64/CONFIGURE/CHANGE_FD,
   offset et sizelimit, BLKGETSIZE64, lecture/ecriture a travers le loop. */
#include "ku.h"

#define LOOP_SET_FD 0x4C00
#define LOOP_CLR_FD 0x4C01
#define LOOP_SET_STATUS 0x4C02
#define LOOP_GET_STATUS 0x4C03
#define LOOP_SET_STATUS64 0x4C04
#define LOOP_GET_STATUS64 0x4C05
#define LOOP_CHANGE_FD 0x4C06
#define LOOP_SET_CAPACITY 0x4C07
#define LOOP_CONFIGURE 0x4C0A
#define LOOP_CTL_ADD 0x4C80
#define LOOP_CTL_REMOVE 0x4C81
#define LOOP_CTL_GET_FREE 0x4C82
#define BLKGETSIZE64 0x80081272
#define BLKGETSIZE 0x1260

struct li64{unsigned long long dev,ino,rdev,off,lim;unsigned num,enc,keysz,flags;char name[64],cname[64];unsigned char key[32];unsigned long long init[2];};
struct lcfg{unsigned fd,bs;struct li64 info;unsigned long long res[8];};

static char buf[8192],buf2[8192];
static unsigned st_ino(int fd){unsigned char s[96];if(sc2(SYS_fstat64,fd,(long)s))return 0;return *(unsigned*)(s+88);}
static void fill(char*b,int n,int seed){int i;for(i=0;i<n;i++)b[i]=(char)((i*7+seed)&0xff);}

int main(){
  int bf,lo,ctl,r,i,k;
  struct li64 li;
  unsigned long long sz;
  /* fichier de support de 256 Ko, motif (i*7+(i>>9)) par bloc de 512 */
  unlink("/tmp/loop.img");
  bf=open("/tmp/loop.img",O_CREAT|O_RDWR,0644);
  for(i=0;i<64;i++){fill(buf,4096,i);write(bf,buf,4096);}
  ktest("loop.nodes",open("/dev/loop0",O_RDONLY,0)>=0&&open("/dev/loop7",O_RDONLY,0)>=0&&open("/dev/loop-control",O_RDWR,0)>=0);
  lo=open("/dev/loop0",O_RDWR,0);
  ktest("loop.unbound_enxio",ioctl(lo,LOOP_GET_STATUS64,(long)&li)==-6&&read(lo,buf,512)==-6);
  ctl=open("/dev/loop-control",O_RDWR,0);
  ktest("loop.ctl_get_free",ioctl(ctl,LOOP_CTL_GET_FREE,0)==0);
  ktest("loop.set_fd",ioctl(lo,LOOP_SET_FD,bf)==0);
  ktest("loop.set_fd_busy",ioctl(lo,LOOP_SET_FD,bf)==-16);
  ktest("loop.ctl_get_free_next",ioctl(ctl,LOOP_CTL_GET_FREE,0)==1);
  ktest("loop.size",ioctl(lo,BLKGETSIZE64,(long)&sz)==0&&sz==262144);
  {unsigned n;ktest("loop.blkgetsize",ioctl(lo,BLKGETSIZE,(long)&n)==0&&n==512);}
  r=read(lo,buf,4096);fill(buf2,4096,0);
  ktest("loop.read",r==4096&&memcmp_(buf,buf2,4096)==0);
  lseek(lo,3*4096,0);r=read(lo,buf,4096);fill(buf2,4096,3);
  ktest("loop.read_off",r==4096&&memcmp_(buf,buf2,4096)==0);
  /* ecriture a travers le loop, visible dans le fichier de support */
  fill(buf,4096,200);lseek(lo,5*4096,0);r=write(lo,buf,4096);
  sync();
  lseek(bf,5*4096,0);read(bf,buf2,4096);
  ktest("loop.write",r==4096&&memcmp_(buf,buf2,4096)==0);
  memset(&li,0,sizeof li);
  r=ioctl(lo,LOOP_GET_STATUS64,(long)&li);
  ktest("loop.get_status64",r==0&&li.ino==st_ino(bf)&&li.num==0&&li.off==0&&li.lim==0&&li.rdev==(7<<8));
  ktest("loop.get_status64_name",strcmp(li.name,"/tmp/loop.img")==0);
  /* offset 4096 et limite de 32 Ko */
  memset(&li,0,sizeof li);li.off=4096;li.lim=32768;strcpy_(li.name,"/tmp/loop.img");
  ktest("loop.set_status64",ioctl(lo,LOOP_SET_STATUS64,(long)&li)==0);
  ioctl(lo,BLKGETSIZE64,(long)&sz);
  ktest("loop.size_limit",sz==32768);
  lseek(lo,0,0);r=read(lo,buf,4096);fill(buf2,4096,1);
  ktest("loop.offset_read",r==4096&&memcmp_(buf,buf2,4096)==0);
  lseek(lo,32768,0);
  ktest("loop.eof",read(lo,buf,4096)==0);
  memset(&li,0,sizeof li);li.enc=1;
  ktest("loop.set_status64_enc",ioctl(lo,LOOP_SET_STATUS64,(long)&li)==-22);
  /* ancienne interface */
  {unsigned char o[144];memset(o,0,sizeof o);
   ktest("loop.get_status32",ioctl(lo,LOOP_GET_STATUS,(long)o)==0&&*(int*)(o+16)==4096&&o[32]=='/');}
  ktest("loop.clr_fd",ioctl(lo,LOOP_CLR_FD,0)==0);
  ktest("loop.after_clr_enxio",read(lo,buf,512)==-6&&ioctl(lo,LOOP_GET_STATUS64,(long)&li)==-6);
  ktest("loop.clr_twice",ioctl(lo,LOOP_CLR_FD,0)==-6);
  /* le contenu ecrit est dans le fichier apres CLR_FD */
  fill(buf,4096,200);lseek(bf,5*4096,0);read(bf,buf2,4096);
  ktest("loop.persisted",memcmp_(buf,buf2,4096)==0);
  /* LOOP_CONFIGURE en lecture seule */
  {struct lcfg c;int fd2=open("/tmp/loop.img",O_RDONLY,0),l1=open("/dev/loop1",O_RDWR,0);
   memset(&c,0,sizeof c);c.fd=fd2;c.info.off=512;strcpy_(c.info.name,"ro.img");c.info.flags=1;
   ktest("loop.configure",ioctl(l1,LOOP_CONFIGURE,(long)&c)==0);
   ioctl(l1,BLKGETSIZE64,(long)&sz);
   ktest("loop.configure_size",sz==262144-512);
   lseek(l1,0,0);r=read(l1,buf,512);
   ktest("loop.configure_read",r==512&&buf[0]==0);
   lseek(l1,0,0);
   ktest("loop.readonly_write",write(l1,buf,512)<0);
   memset(&li,0,sizeof li);ioctl(l1,LOOP_GET_STATUS64,(long)&li);
   ktest("loop.readonly_flag",(li.flags&1)&&li.off==512);
   /* LOOP_CHANGE_FD sur un loop en lecture seule */
   {int fd3=open("/tmp/loop.img",O_RDONLY,0);ktest("loop.change_fd",ioctl(l1,LOOP_CHANGE_FD,fd3)==0);close(fd3);}
   ktest("loop.clr_fd1",ioctl(l1,LOOP_CLR_FD,0)==0);
   close(fd2);close(l1);}
  /* acces en lecture seule au peripherique : modifications refusees */
  {int lr=open("/dev/loop2",O_RDONLY,0);
   ktest("loop.rdonly_open_eperm",ioctl(lr,LOOP_SET_FD,bf)==-1);close(lr);}
  /* un fichier qui n'est ni ordinaire ni bloc */
  {int l3=open("/dev/loop3",O_RDWR,0),nul=open("/dev/null",O_RDWR,0);
   ktest("loop.set_fd_char_einval",ioctl(l3,LOOP_SET_FD,nul)==-22);
   ktest("loop.set_fd_ebadf",ioctl(l3,LOOP_SET_FD,99)==-9);close(l3);close(nul);}
  /* loop-control */
  ktest("loop.ctl_add_eexist",ioctl(ctl,LOOP_CTL_ADD,0)==-17);
  ktest("loop.ctl_add_new",ioctl(ctl,LOOP_CTL_ADD,9)==9);
  ktest("loop.ctl_add_node",open("/dev/loop9",O_RDONLY,0)>=0);
  {int l9=open("/dev/loop9",O_RDWR,0);
   ktest("loop.dev9_bind",ioctl(l9,LOOP_SET_FD,bf)==0);
   ktest("loop.ctl_remove_busy",ioctl(ctl,LOOP_CTL_REMOVE,9)==-16);
   ioctl(l9,LOOP_CLR_FD,0);close(l9);}
  ktest("loop.ctl_remove",ioctl(ctl,LOOP_CTL_REMOVE,9)==9);
  ktest("loop.ctl_remove_enodev",ioctl(ctl,LOOP_CTL_REMOVE,9)==-19);
  ktest("loop.ctl_badcmd",ioctl(ctl,0x4C99,0)==-25);
  {char b[4096];int n;int fd=open("/proc/partitions",O_RDONLY,0);n=fd>=0?read(fd,b,4095):0;if(n<0)n=0;b[n]=0;
   close(fd);ktest("loop.partitions_unbound",1);}
  ioctl(lo,LOOP_SET_FD,bf);
  {char b[4096];int n,j,fnd=0;int fd=open("/proc/partitions",O_RDONLY,0);n=fd>=0?read(fd,b,4095):0;if(n<0)n=0;b[n]=0;close(fd);
   for(j=0;j+5<n;j++)if(memcmp_(b+j,"loop0",5)==0)fnd=1;
   ktest("loop.partitions_bound",fnd);}
  ioctl(lo,LOOP_CLR_FD,0);
  close(lo);close(ctl);close(bf);unlink("/tmp/loop.img");
  puts("KTEST: loop DONE\n");
  (void)k;
  return ku_fail?1:0;
}
