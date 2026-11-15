/* idetest : les quatre disques IDE (hda..hdd : canaux 1F0/IRQ14 et 170/IRQ15,
   maitre et esclave). Pour chaque /dev/hdX1 portant un ext2 : montage, lecture
   de hello.txt, ecriture d'un fichier de 100 Ko et d'un repertoire, relecture,
   demontage. RUNIDE.SH verifie ensuite chaque image avec e2fsck et debugfs.
   Les disques absents sont ignores (RUNK.SH reste inchange). */
#include "ku.h"
static unsigned char pat(unsigned i){return (unsigned char)(i*13+(i>>7)+1);}
static unsigned char wb[4096];
int main(void){
  if(ku_cmdline_has("bigtest"))return 0;
  static const char*devs[4]={"/dev/hda1","/dev/hdb1","/dev/hdc1","/dev/hdd1"};
  int d,n=0;
  for(d=0;d<4;d++){
    int fd=open(devs[d],O_RDONLY,0),r,i,ok;
    char b[64],nm[32];
    if(fd<0)continue;
    lseek(fd,1024+56,0);r=read(fd,b,2);close(fd);
    if(r!=2||(unsigned char)b[0]!=0x53||(unsigned char)b[1]!=0xEF)continue;
    n++;
    nm[0]='i';nm[1]='d';nm[2]='e';nm[3]='.';nm[4]='h';nm[5]='d';nm[6]='a'+d;nm[7]=0;
    {char t[40];int k;
     for(k=0;nm[k];k++)t[k]=nm[k];
     strcpy_(t+k,".mount");ktest(t,mount(devs[d],"/mnt","ext2",0,0)==0);
     fd=open("/mnt/hello.txt",O_RDONLY,0);
     r=fd<0?-1:read(fd,b,sizeof b);if(fd>=0)close(fd);
     strcpy_(t+k,".read");ktest(t,r==16&&memcmp_(b,"hello from ext2\n",16)==0);
     fd=open("/mnt/big.bin",O_RDONLY,0);ok=fd>=0;
     for(i=0;ok&&i<300;i++){int q,j;q=read(fd,wb,1000);if(q!=1000){ok=0;break;}
       for(j=0;j<q;j++)if(wb[j]!=(unsigned char)((i*1000+j)*7+((i*1000+j)>>8)))ok=0;}
     if(fd>=0)close(fd);
     strcpy_(t+k,".readbig");ktest(t,ok);
     mkdir("/mnt/fromk32",0755);
     {char path[40];strcpy_(path,"/mnt/fromk32/w_hd");path[17]='a'+d;path[18]=0;strcpy_(path+18,".dat");
      fd=open(path,O_RDWR|O_CREAT|O_TRUNC,0644);ok=fd>=0;
      for(i=0;ok&&i<100;i++){int j;for(j=0;j<1024;j++)wb[j]=pat(i*1024+j+d);if(write(fd,wb,1024)!=1024)ok=0;}
      if(ok){lseek(fd,0,0);for(i=0;ok&&i<100;i++){int j;if(read(fd,wb,1024)!=1024){ok=0;break;}
        for(j=0;j<1024;j++)if(wb[j]!=pat(i*1024+j+d))ok=0;}}
      if(fd>=0)close(fd);}
     strcpy_(t+k,".write");ktest(t,ok);
     sync();
     strcpy_(t+k,".umount");ktest(t,umount("/mnt")==0);}
  }
  if(n==0){puts("  (aucun ext2 sur hda1..hdd1 : tests IDE ignores)\n");return 0;}
  puts("ide DONE ");putd(n);puts("\n");
  return 0;
}
