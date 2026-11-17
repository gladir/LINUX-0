/* blktest : couche bloc : ramdisk, disque IDE (hda), partitions, cache de tampons */
#include "ku.h"
int main(void){
  char b[1024],c[1024];int fd,n,i;
  fd=open("/dev/ram0",O_RDWR,0);
  ktest("blk.ram_open",fd>=0);
  for(i=0;i<1024;i++)b[i]=i*7;
  lseek(fd,5000,0);
  ktest("blk.ram_write",write(fd,b,1024)==1024);
  lseek(fd,5000,0);
  memset(c,0,1024);n=read(fd,c,1024);
  ktest("blk.ram_read",n==1024&&memcmp_(b,c,1024)==0);
  close(fd);
  fd=open("/dev/hda",O_RDONLY,0);
  if(fd<0){puts("  (pas de disque hda : tests IDE ignores)\n");return ku_fail?1:0;}
  n=read(fd,b,512);
  ktest("blk.hda_mbr",n==512&&(unsigned char)b[510]==0x55&&(unsigned char)b[511]==0xAA);
  close(fd);
  fd=open("/dev/hda1",O_RDWR,0);
  ktest("blk.hda1_open",fd>=0);
  n=read(fd,b,16);b[n>0?n:0]=0;
  if(n!=16||memcmp_(b,"PARTITION-ONE...",16)!=0){puts("  (partition de test absente : ecriture ignoree)\n");close(fd);return ku_fail?1:0;}
  ktest("blk.hda1_read",1);
  lseek(fd,4096,0);
  for(i=0;i<1024;i++)b[i]=(i*3)^0x5a;
  ktest("blk.hda1_write",write(fd,b,1024)==1024);
  sync();
  close(fd);
  fd=open("/dev/hda1",O_RDONLY,0);
  lseek(fd,4096,0);memset(c,0,1024);n=read(fd,c,1024);
  ktest("blk.hda1_readback",n==1024&&memcmp_(b,c,1024)==0);
  close(fd);
  fd=open("/dev/hda2",O_RDONLY,0);
  n=read(fd,b,16);b[n>0?n:0]=0;
  ktest("blk.hda2_read",n==16&&memcmp_(b,"PARTITION-TWO...",16)==0);
  close(fd);
  return ku_fail?1:0;
}
