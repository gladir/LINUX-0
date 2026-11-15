/* rotest : systemes de fichiers minix, cramfs et romfs (lecture seule,
   partie 38). /init d'un initramfs (RUNRO.SH) : les images sont des fichiers
   de la racine en memoire, montes par /dev/loopN. Argument de la ligne de
   commande du noyau : rofs=type:fichier,... */
#include "ku.h"
#define LOOP_SET_FD 0x4C00
#define LOOP_CLR_FD 0x4C01
static char b[8192],cl[512];
static int slurp(const char*p,char*s,int max){int fd=open(p,O_RDONLY,0),n,t=0;if(fd<0)return fd;while(t<max-1&&(n=read(fd,s+t,max-1-t))>0)t+=n;s[t]=0;close(fd);return t;}
static unsigned fld(const char*p,int off){unsigned char s[96];if(sc2(SYS_stat64,(long)p,(long)s))return 0xdeadbeef;return *(unsigned*)(s+off);}
static unsigned lfld(const char*p,int off){unsigned char s[96];if(sc2(SYS_lstat64,(long)p,(long)s))return 0xdeadbeef;return *(unsigned*)(s+off);}
static unsigned long long sz(const char*p){unsigned char s[96];if(sc2(SYS_stat64,(long)p,(long)s))return ~0ULL;return *(unsigned long long*)(s+44);}
static void cat(char*o,const char*a,const char*b2){strcpy_(o,a);strcpy_(o+strlen(a),b2);}
static int countdir(const char*d,int*hasf1,int*hasdot){
  char buf[1024];int fd=open(d,O_RDONLY|O_DIRECTORY,0),n,c=0;*hasf1=0;*hasdot=0;
  if(fd<0)return -1;
  while((n=getdents64(fd,buf,sizeof buf))>0){int o=0;while(o<n){struct{unsigned long long i,o;unsigned short l;unsigned char t;char nm[1];}*e=(void*)(buf+o);
      if(strcmp(e->nm,"f17.txt")==0)*hasf1=1;if(strcmp(e->nm,".")==0||strcmp(e->nm,"..")==0)(*hasdot)++;c++;o+=e->l;}}
  close(fd);return c;}
static void check(const char*fs,const char*img,int dev){
  char pre[40],n[80],l[64];int lo,bf,r,ok,i,tot,a,b2;
  char devp[16];strcpy_(devp,"/dev/loop0");devp[9]='0'+dev;
  cat(pre,"ro.",fs);{int l=strlen(pre);pre[l]='0'+dev;pre[l+1]=0;}
  bf=open(img,O_RDONLY,0);lo=open(devp,O_RDWR,0);
  cat(n,pre,".loop");ktest(n,bf>=0&&lo>=0&&ioctl(lo,LOOP_SET_FD,bf)==0);
  close(bf);
  mkdir("/mnt",0755);
  r=mount(devp,"/mnt",fs,1,0);
  cat(n,pre,".mount");ktest(n,r==0);
  if(r!=0){close(lo);return;}
  cat(n,pre,".hello");r=slurp("/mnt/hello.txt",b,sizeof b);ktest(n,r==16&&memcmp_(b,"hello from rofs\n",16)==0);
  cat(n,pre,".deep");r=slurp("/mnt/dir1/sub/deep.txt",b,sizeof b);ktest(n,r==5&&strcmp(b,"deep\n")==0);
  cat(n,pre,".size");ktest(n,sz("/mnt/big.bin")==300000&&sz("/mnt/empty")==0&&sz("/mnt/rand.bin")==20000&&sz("/mnt/zeros.bin")==10000);
  /* gros fichier compressible */
  {int fd=open("/mnt/big.bin",O_RDONLY,0),k=0;ok=fd>=0;tot=0;
   if(ok){while((r=read(fd,b,sizeof b))>0){for(i=0;i<r;i++){k=tot+i;if((unsigned char)b[i]!=(unsigned char)((k*7+(k>>8))&255)){ok=0;break;}}tot+=r;if(!ok)break;}if(tot!=300000)ok=0;close(fd);}
   cat(n,pre,".big");ktest(n,ok);}
  /* lecture a un decalage non aligne */
  {int fd=open("/mnt/big.bin",O_RDONLY,0);ok=0;if(fd>=0){lseek(fd,123457,0);r=read(fd,b,100);ok=r==100;for(i=0;ok&&i<100;i++){int k=123457+i;if((unsigned char)b[i]!=(unsigned char)((k*7+(k>>8))&255))ok=0;}
    lseek(fd,299990,0);r=read(fd,b,100);ok=ok&&r==10;close(fd);}
   cat(n,pre,".seek");ktest(n,ok);}
  /* donnees pseudo-aleatoires incompressibles : LCG */
  {int fd=open("/mnt/rand.bin",O_RDONLY,0);unsigned x=12345;ok=fd>=0;tot=0;
   if(ok){while((r=read(fd,b,sizeof b))>0){for(i=0;i<r;i++){x=x*1103515245u+12345u;if((unsigned char)b[i]!=(unsigned char)(x>>16)){ok=0;break;}}tot+=r;if(!ok)break;}if(tot!=20000)ok=0;close(fd);}
   cat(n,pre,".random");ktest(n,ok);}
  {int fd=open("/mnt/zeros.bin",O_RDONLY,0);ok=fd>=0;tot=0;
   if(ok){while((r=read(fd,b,sizeof b))>0){for(i=0;i<r;i++)if(b[i]){ok=0;break;}tot+=r;}if(tot!=10000)ok=0;close(fd);}
   cat(n,pre,".zeros");ktest(n,ok);}
  {int r2=readlink("/mnt/lnk",l,63);if(r2>0)l[r2]=0;cat(n,pre,".symlink");ktest(n,r2==9&&strcmp(l,"hello.txt")==0);}
  cat(n,pre,".follow");ktest(n,slurp("/mnt/lnk",b,sizeof b)==16);
  cat(n,pre,".mode");ktest(n,(fld("/mnt/hello.txt",16)&0xF000)==0x8000&&(fld("/mnt/dir1",16)&0xF000)==0x4000&&(lfld("/mnt/lnk",16)&0xF000)==0xA000);
  cat(n,pre,".exec");ktest(n,(fld("/mnt/tool",16)&0111)==0111&&(fld("/mnt/hello.txt",16)&0111)==(fld("/mnt/hello.txt",16)&0111));
  cat(n,pre,".enoent");ktest(n,open("/mnt/nope",O_RDONLY,0)==-2&&open("/mnt/dir1/nope",O_RDONLY,0)==-2&&open("/mnt/hello.txt/x",O_RDONLY,0)==-20);
  a=countdir("/mnt/dir1",&b2,&r);
  cat(n,pre,".readdir");ktest(n,a>=41&&b2==1&&r==2);
  {int hf,hd;a=countdir("/mnt",&hf,&hd);cat(n,pre,".readdir_root");ktest(n,a>=9&&hd==2);}
  cat(n,pre,".rofs_write");ktest(n,open("/mnt/new",O_CREAT|O_WRONLY,0644)==-30&&open("/mnt/hello.txt",O_WRONLY,0)==-30&&unlink("/mnt/hello.txt")==-30);
  cat(n,pre,".busy");ktest(n,({chdir("/mnt/dir1");int rr=umount("/mnt");chdir("/");rr==-16;}));
  cat(n,pre,".umount");ktest(n,umount("/mnt")==0);
  cat(n,pre,".clr");ktest(n,ioctl(lo,LOOP_CLR_FD,0)==0);
  close(lo);
}
int main(int argc,char**argv){
  int m=slurp("/proc/cmdline",cl,sizeof cl),i,k=0;
  char*p=0;
  ktest("rofs.pid1",getpid()==1);
  for(i=0;i+5<m;i++)if(memcmp_(cl+i,"rofs=",5)==0)p=cl+i+5;
  if(p){while(*p&&*p!=' '&&*p!='\n'){char fs[16],img[64];int a=0,c=0;
      while(*p&&*p!=':')fs[a++]=*p++;fs[a]=0;if(*p==':')p++;
      while(*p&&*p!=','&&*p!=' '&&*p!='\n')img[c++]=*p++;img[c]=0;if(*p==',')p++;
      check(fs,img,k++);}}
  puts("KTEST: rofs DONE\n");
  sync();reboot_off();
  return ku_fail?1:0;
}
