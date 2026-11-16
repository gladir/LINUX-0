/* parttest : partitionnement cote noyau (partie 39) : disque /dev/hda (MKEXT2.SH :
   MBR + ext2 en partition 1 a partir du secteur 2048) ou GPT (gpt sur la ligne
   de commande). BLKRRPART (EBUSY si monte), BLKPG (ADD/DEL, chevauchement),
   HDIO_GETGEO, BLKGETSIZE, ecriture du MBR par /dev/hda, noeuds /dev,
   /proc/partitions, /sys/block/hda/hda1/{start,size}. Sans /dev/hda : ignore. */
#include "ku.h"
static char b[2048];
static int slurp(const char*p,char*s,int max){int fd=open(p,O_RDONLY,0),n;if(fd<0)return fd;n=read(fd,s,max-1);if(n<0)n=0;s[n]=0;close(fd);return n;}
static int has(const char*h,const char*n){int i,l=strlen(n),m=strlen(h);for(i=0;i+l<=m;i++)if(memcmp_(h+i,n,l)==0)return 1;return 0;}
static int mounted_ok(void){char r[32];int fd,n;
  if(mount("/dev/hda1","/mnt","ext2",0,0)!=0)return 0;
  fd=open("/mnt/hello.txt",O_RDONLY,0);n=fd<0?-1:read(fd,r,sizeof r);if(fd>=0)close(fd);
  umount("/mnt");return n==16&&memcmp_(r,"hello from ext2\n",16)==0;}
static int hda1_listed(void){slurp("/proc/partitions",b,sizeof b);return has(b," hda1\n");}
struct pa{int op,flags,datalen;void*data;};
struct pp{long long start,length;int pno;char dev[64],vol[64];};
static int blkpg(int fd,int op,int pno,long long st,long long ln){struct pa a;struct pp p;
  memset(&p,0,sizeof p);p.start=st;p.length=ln;p.pno=pno;a.op=op;a.flags=0;a.datalen=sizeof p;a.data=&p;
  return ioctl(fd,0x1269,(long)&a);}
int main(void){
  int fd=open("/dev/hda",O_RDWR,0),r,gpt=ku_cmdline_has("gpt");
  unsigned char mbr[512],z[512];unsigned geo[2];unsigned long psz=0;
  if(fd<0||ku_cmdline_has("bigtest")||ku_cmdline_has("k32net")){puts("  (pas de /dev/hda : tests de partitionnement ignores)\n");return 0;}
  mkdir("/mnt",0755);
  ktest("part.getgeo",ioctl(fd,0x0301,(long)geo)==0&&(geo[0]&0xFF)==255&&((geo[0]>>8)&0xFF)==63&&geo[1]==0);
  {int f1=open("/dev/hda1",O_RDONLY,0);ktest("part.hda1_present",f1>=0&&hda1_listed());
   if(f1>=0){ktest("part.getgeo_start",ioctl(f1,0x0301,(long)geo)==0&&geo[1]==2048);
     ioctl(f1,0x1260,(long)&psz);ktest("part.getsize",psz>1000);close(f1);}}
  slurp("/sys/block/hda/hda1/start",b,sizeof b);ktest("part.sys_start",b[0]=='2'&&b[1]=='0'&&b[2]=='4'&&b[3]=='8');
  ktest("part.mount",mounted_ok());
  if(gpt){puts("KTEST: part DONE gpt\n");return ku_fail?1:0;}
  /* BLKRRPART refuse tant qu'une partition est montee */
  ktest("part.mount2",mount("/dev/hda1","/mnt","ext2",0,0)==0);
  ktest("part.rrpart_busy",ioctl(fd,0x125F,0)==-16);
  umount("/mnt");
  ktest("part.rrpart_on_partition_einval",({int f1=open("/dev/hda1",O_RDONLY,0);int q=ioctl(f1,0x125F,0);close(f1);q==-22;}));
  /* ecriture de la table (secteur 0 par /dev/hda), relecture, partition disparue */
  lseek(fd,0,0);read(fd,mbr,512);memcpy(z,mbr,512);memset(z+446,0,64);
  lseek(fd,0,0);ktest("part.write_mbr",write(fd,z,512)==512);
  sync();
  ktest("part.rrpart_empty",ioctl(fd,0x125F,0)==0);
  ktest("part.hda1_gone",open("/dev/hda1",O_RDONLY,0)<0&&!hda1_listed()&&open("/sys/block/hda/hda1/size",O_RDONLY,0)<0);
  /* BLKPG */
  ktest("part.blkpg_add",blkpg(fd,1,1,2048LL*512,(long long)psz*512)==0);
  ktest("part.blkpg_add_visible",hda1_listed()&&open("/dev/hda1",O_RDONLY,0)>=0&&mounted_ok());
  ktest("part.blkpg_add_busy",blkpg(fd,1,1,2048LL*512,(long long)psz*512)==-16);
  ktest("part.blkpg_overlap",blkpg(fd,1,2,4096LL*512,512LL*512)==-16);
  ktest("part.blkpg_range",blkpg(fd,1,3,(1LL<<40),512LL*512)==-22);
  ktest("part.blkpg_badpno",blkpg(fd,1,0,2048LL*512,512LL*512)==-22);
  ktest("part.blkpg_del",blkpg(fd,2,1,0,0)==0&&!hda1_listed()&&open("/dev/hda1",O_RDONLY,0)<0);
  ktest("part.blkpg_del_absent",blkpg(fd,2,1,0,0)==-6);
  /* retour de la table d'origine */
  lseek(fd,0,0);ktest("part.restore_mbr",write(fd,mbr,512)==512);sync();
  ktest("part.rrpart_restore",ioctl(fd,0x125F,0)==0);
  ktest("part.restored",hda1_listed()&&mounted_ok());
  slurp("/sys/block/hda/hda1/size",b,sizeof b);ktest("part.sys_size",b[0]>='0'&&b[0]<='9');
  {int p=fork(),st=0;if(p==0){int f2=open("/dev/hda",O_RDWR,0);sc1(23,1000);_exit(ioctl(f2,0x125F,0)==-13?0:1);}
   waitpid(p,&st,0);ktest("part.eperm_nonroot",st==0);}
  puts("KTEST: part DONE\n");
  return ku_fail?1:0;
}
