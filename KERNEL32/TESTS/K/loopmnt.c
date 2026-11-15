/* loopmnt : montage d'un systeme de fichiers ext2 contenu dans un fichier
   (peripherique loop, partie 38). Disque : RUNLOOP.SH (/dev/hda1 ext2 avec
   /inner.img = ext2 de 4 Mo et /inner2.img = 8192 octets + ext2). Sans
   /dev/hda1 le test est ignore. */
#include "ku.h"
#define LOOP_SET_FD 0x4C00
#define LOOP_CLR_FD 0x4C01
#define LOOP_SET_STATUS64 0x4C04
struct li64{unsigned long long dev,ino,rdev,off,lim;unsigned num,enc,keysz,flags;char name[64],cname[64];unsigned char key[32];unsigned long long init[2];};
static char buf[4096];
static int slurp(const char*p,char*b,int max){int fd=open(p,O_RDONLY,0),n;if(fd<0)return fd;n=read(fd,b,max-1);if(n<0)n=0;b[n]=0;close(fd);return n;}
int main(){
  int fd,bf,lo,r;struct li64 li;
  fd=open("/dev/hda1",O_RDONLY,0);
  if(fd<0){puts("  (pas de /dev/hda1 : tests loop ignores)\n");return 0;}
  close(fd);
  if(mount("/dev/hda1","/mnt","ext2",0,0)!=0){puts("  (montage ext2 impossible)\n");return 0;}
  if(open("/mnt/inner.img",O_RDONLY,0)<0){umount("/mnt");puts("  (pas de inner.img : tests loop ignores)\n");return 0;}
  {int rr=slurp("/sys/block/hda/dev",buf,sizeof buf);ktest("loopmnt.sys_hda_dev",rr>=3&&buf[0]=='3'&&buf[1]==':'&&buf[2]=='0');
   rr=slurp("/sys/block/hda/hda1/start",buf,sizeof buf);ktest("loopmnt.sys_hda1_start",rr>=4&&buf[0]=='2'&&buf[1]=='0'&&buf[2]=='4'&&buf[3]=='8');
   ktest("loopmnt.sys_class_hda1",({unsigned char s[96];sc2(SYS_stat64,(long)"/sys/class/block/hda1",(long)s)==0&&((*(unsigned*)(s+16))&0xF000)==0x4000;}));}
  bf=open("/mnt/inner.img",O_RDWR,0);
  lo=open("/dev/loop0",O_RDWR,0);
  ktest("loopmnt.set_fd",ioctl(lo,LOOP_SET_FD,bf)==0);
  close(bf);
  mkdir("/tmp/lm",0755);
  r=mount("/dev/loop0","/tmp/lm","ext2",0,0);
  ktest("loopmnt.mount",r==0);
  if(r==0){
    int n;
    n=slurp("/tmp/lm/hello.txt",buf,sizeof buf);
    ktest("loopmnt.read",n>0&&memcmp_(buf,"hello from inner",16)==0);
    n=slurp("/tmp/lm/big.bin",buf,sizeof buf);
    ktest("loopmnt.read_big",n==4095&&(unsigned char)buf[300]==(unsigned char)((300*7)&255));
    fd=open("/tmp/lm/new.txt",O_CREAT|O_WRONLY|O_TRUNC,0644);
    n=write(fd,"written through loop\n",21);close(fd);
    ktest("loopmnt.write",n==21);
    ktest("loopmnt.mkdir",mkdir("/tmp/lm/d1",0755)==0);
    ktest("loopmnt.clr_busy",ioctl(lo,LOOP_CLR_FD,0)==-16);
    ktest("loopmnt.umount",umount("/tmp/lm")==0);
  }
  ktest("loopmnt.clr_fd",ioctl(lo,LOOP_CLR_FD,0)==0);
  close(lo);
  /* avec un decalage de 8192 octets */
  bf=open("/mnt/inner2.img",O_RDWR,0);
  lo=open("/dev/loop1",O_RDWR,0);
  ktest("loopmnt.off_set_fd",bf>=0&&ioctl(lo,LOOP_SET_FD,bf)==0);
  memset(&li,0,sizeof li);li.off=8192;
  ktest("loopmnt.off_status",ioctl(lo,LOOP_SET_STATUS64,(long)&li)==0);
  r=mount("/dev/loop1","/tmp/lm","ext2",1,0);
  ktest("loopmnt.off_mount_ro",r==0);
  if(r==0){
    int n=slurp("/tmp/lm/hello.txt",buf,sizeof buf);
    ktest("loopmnt.off_read",n>0&&memcmp_(buf,"hello from inner",16)==0);
    ktest("loopmnt.off_umount",umount("/tmp/lm")==0);
  }
  ioctl(lo,LOOP_CLR_FD,0);close(lo);close(bf);
  /* le montage d'un loop sans fichier echoue */
  ktest("loopmnt.unbound_mount",mount("/dev/loop2","/tmp/lm","ext2",0,0)<0);
  sync();
  umount("/mnt");
  puts("KTEST: loopmnt DONE\n");
  return ku_fail?1:0;
}
