/* bigtest : fichiers de plus de 2 Go (partie 35) : positions et tailles
   64 bits sur ext2 (fichiers creux jusqu'a plus de 5 Go, disque de plus de
   4 Go) et sur FAT32 (fichier de 2,3 Go ecrit par l'hote).
   Ne s'execute que si la ligne de commande du noyau contient "bigtest"
   (TESTS/K/RUNBIG.SH fabrique le disque : MKBIG.SH). */
#include "ku.h"

#define SYS_llseek 140
#define SYS_pread64 180
#define SYS_pwrite64 181
#define SYS_ftruncate64 194
#define SYS_truncate64 193
#define SYS_fcntl64 221
#define SYS_sendfile64 239
#define SYS_fallocate 324
#define SYS_setrlimit 75
#define SYS_stat 106
#define SYS_fstat 108
#define SYS_statx 383
#define SYS_statfs 99
#define O_LARGEFILE 0x8000
typedef long long ll;
typedef unsigned long long ull;

static long llseek_(int fd,ll off,int wh,ull*res){
  return sc5(SYS_llseek,fd,(long)(off>>32),(long)off,(long)res,wh);}
static long pread64_(int fd,void*b,long n,ll off){
  return sc5(SYS_pread64,fd,(long)b,n,(long)off,(long)(off>>32));}
static long pwrite64_(int fd,const void*b,long n,ll off){
  return sc5(SYS_pwrite64,fd,(long)b,n,(long)off,(long)(off>>32));}
static long ftruncate64_(int fd,ll n){return sc3(SYS_ftruncate64,fd,(long)n,(long)(n>>32));}
static long truncate64_(const char*p,ll n){return sc3(SYS_truncate64,(long)p,(long)n,(long)(n>>32));}
static long fallocate_(int fd,int mode,ll off,ll len){
  return sc6(SYS_fallocate,fd,mode,(long)off,(long)(off>>32),(long)len,(long)(len>>32));}
static long sendfile64_(int out,int in,ll*off,long n){return sc4(SYS_sendfile64,out,in,(long)off,n);}
static long fstat64_(int fd,void*b){return sc2(SYS_fstat64,fd,(long)b);}
static long stat64_(const char*p,void*b){return sc2(SYS_stat64,(long)p,(long)b);}
static long statold_(const char*p,void*b){return sc2(SYS_stat,(long)p,(long)b);}
static long fstatold_(int fd,void*b){return sc2(SYS_fstat,fd,(long)b);}
static long statx_(int fd,const char*p,int fl,void*b){return sc5(SYS_statx,fd,(long)p,fl,0xfff,(long)b);}
static int ftruncate_(int fd,long n){return sc2(SYS_ftruncate,fd,n);}
static long setrlimit_(int r,unsigned long*v){return sc2(SYS_setrlimit,r,(long)v);}

#define ST_SIZE64(b) (*(ull*)((b)+44))
#define ST_BLOCKS64(b) (*(ull*)((b)+56))
#define G ((ll)1<<30)

static unsigned char sb[96], sx[1024];
static unsigned char buf[8192];

static ull fsize(int fd){fstat64_(fd,sb);return ST_SIZE64(sb);}
static void xfsz(int s){(void)s;}

static int cmdline_has(const char*w){
  char cl[256];int fd=open("/proc/cmdline",O_RDONLY,0),m=0,k,l=strlen(w);
  if(fd>=0){m=read(fd,cl,sizeof cl-1);close(fd);}
  for(k=0;k+l<=m;k++)if(memcmp_(cl+k,w,l)==0)return 1;
  return 0;
}

static int fillbuf(unsigned char*b,int n,ull seed){int i;for(i=0;i<n;i++)b[i]=(unsigned char)(seed*131+i*7+(i>>8));return 1;}

/* ---- ext2 ---- */
static int test_ext2(void){
  int fd,fd2,i,r;ull pos,sz;ll o;
  long rc;
  /* disque : plus de 4 Go, lecture/ecriture aux grands decalages */
  fd=open("/dev/hda",O_RDWR,0);
  if(fd>=0){
    ull dsz=0;ioctl(fd,(int)0x80081272,(long)&dsz);
    ktest("big.blkgetsize64",dsz>=(ull)5*G);
    r=llseek_(fd,(ll)dsz-512,0,&pos);
    ktest("big.disk_seek_end",r==0&&pos==dsz-512);
    r=read(fd,buf,512);
    ktest("big.disk_read_last",r==512&&memcmp_(buf,"BIGDISK-MARK",12)==0);
    r=llseek_(fd,-512,2,&pos);
    ktest("big.disk_seek_end_rel",r==0&&pos==dsz-512);
    r=llseek_(fd,(ll)4*G+4096,0,&pos);
    fillbuf(buf,512,7);
    ktest("big.disk_write_4g",r==0&&write(fd,buf,512)==512);
    r=pread64_(fd,sx,512,(ll)4*G+4096);
    ktest("big.disk_pread_4g",r==512&&memcmp_(sx,buf,512)==0);
    r=llseek_(fd,(ll)dsz,0,&pos);
    ktest("big.disk_eof",r==0&&read(fd,sx,16)==0);
    close(fd);
  }
  if(mount("/dev/hda1","/mnt","ext2",0,0)!=0){ktest("big.mount",0);return 1;}
  ktest("big.mount",1);
  /* fichier creux a 3 Go */
  fd=open("/mnt/sp",O_RDWR|O_CREAT|O_LARGEFILE,0644);
  ktest("big.create",fd>=0);
  ktest("big.pwrite_3g",pwrite64_(fd,"HELLO-3G",8,(ll)3*G)==8);
  fstat64_(fd,sb);
  ktest("big.size_3g",ST_SIZE64(sb)==(ull)3*G+8&&ST_BLOCKS64(sb)<100);
  fillbuf(buf,300,3);
  ktest("big.pread_3g",pread64_(fd,sx,8,(ll)3*G)==8&&memcmp_(sx,"HELLO-3G",8)==0);
  memset(sx,0xAA,64);
  ktest("big.hole_read",pread64_(fd,sx,64,(ll)G)==64&&sx[0]==0&&sx[63]==0);
  /* llseek 64 bits */
  r=llseek_(fd,(ll)3*G,0,&pos);
  ktest("big.llseek_set",r==0&&pos==(ull)3*G);
  ktest("big.read_after_llseek",read(fd,sx,8)==8&&memcmp_(sx,"HELLO-3G",8)==0);
  r=llseek_(fd,(ll)G,1,&pos);
  ktest("big.llseek_cur",r==0&&pos==(ull)4*G+8);
  r=llseek_(fd,-8,2,&pos);
  ktest("big.llseek_end",r==0&&pos==(ull)3*G);
  r=llseek_(fd,-1,0,&pos);
  ktest("big.llseek_neg",r==-22);
  r=llseek_(fd,(ll)5*G,0,&pos);
  ktest("big.llseek_past_end",r==0&&pos==(ull)5*G&&read(fd,sx,4)==0);
  /* lseek 32 bits : EOVERFLOW au-dela de 2 Go */
  ktest("big.lseek32_overflow",lseek(fd,0,2)==-75);
  ktest("big.lseek32_small",lseek(fd,100,0)==100);
  /* SEEK_DATA / SEEK_HOLE */
  r=llseek_(fd,0,3,&pos);
  ktest("big.seek_data",r==0&&pos==0);
  r=llseek_(fd,0,4,&pos);
  ktest("big.seek_hole",r==0&&pos==(ull)3*G+8);
  r=llseek_(fd,(ll)4*G,3,&pos);
  ktest("big.seek_data_enxio",r==-6);
  /* ecriture sequentielle vers 5 Go, croisement de la limite des 4 Go */
  llseek_(fd,(ll)4*G-4,0,&pos);
  fillbuf(buf,8,9);
  ktest("big.write_cross4g",write(fd,buf,8)==8);
  ktest("big.size_cross4g",fsize(fd)==(ull)4*G+4);
  ktest("big.read_cross4g",pread64_(fd,sx,8,(ll)4*G-4)==8&&memcmp_(sx,buf,8)==0);
  ktest("big.pwrite_5g",pwrite64_(fd,"FIVE-G",6,(ll)5*G+1)==6&&fsize(fd)==(ull)5*G+7);
  /* compatibilite : stat/open 32 bits */
  ktest("big.stat32_overflow",statold_("/mnt/sp",sb)==-75);
  ktest("big.fstat32_overflow",fstatold_(fd,sb)==-75);
  ktest("big.stat64_ok",stat64_("/mnt/sp",sb)==0&&ST_SIZE64(sb)==(ull)5*G+7);
  ktest("big.open_no_lfs",open("/mnt/sp",O_RDONLY,0)==-75);
  ktest("big.open_lfs",({int f=open("/mnt/sp",O_RDONLY|O_LARGEFILE,0);int ok=f>=0;if(ok)close(f);ok;}));
  r=statx_(-100,"/mnt/sp",0,sx);
  ktest("big.statx",r==0&&*(ull*)(sx+40)==(ull)5*G+7);
  /* mmap : decalage de fichier au-dela de 2 Go non gere */
  ktest("big.mmap_far",(long)mmap2(0,4096,1,2,fd,(long)(3*G/4096))==-75);
  /* verrous 64 bits */
  {
    struct {short t,w;ll s,l;int pid;} fl={1,0,(ll)3*G,100,0};
    int p;
    ktest("big.lock_set",sc3(SYS_fcntl64,fd,13,(long)&fl)==0);
    p=fork();
    if(p==0){
      struct {short t,w;ll s,l;int pid;} q={1,0,(ll)3*G+50,10,0};
      int rr=sc3(SYS_fcntl64,fd,12,(long)&q);
      _exit(rr==0&&q.t==1&&q.s==(ll)3*G&&q.l==100&&q.pid>0?0:1);
    }
    {int st=0;waitpid(p,&st,0);ktest("big.lock_getlk",st==0);}
    p=fork();
    if(p==0){
      struct {short t,w;ll s,l;int pid;} q={1,0,(ll)3*G+100,10,0};
      int rr=sc3(SYS_fcntl64,fd,12,(long)&q);
      _exit(rr==0&&q.t==2?0:1);
    }
    {int st=0;waitpid(p,&st,0);ktest("big.lock_nonoverlap",st==0);}
  }
  /* troncature */
  ktest("big.ftruncate_shrink",ftruncate64_(fd,(ll)4*G)==0&&fsize(fd)==(ull)4*G);
  ktest("big.after_shrink",pread64_(fd,sx,8,(ll)3*G)==8&&memcmp_(sx,"HELLO-3G",8)==0
        &&pread64_(fd,sx,6,(ll)5*G+1)==0);
  ktest("big.ftruncate_grow",ftruncate64_(fd,(ll)6*G)==0&&fsize(fd)==(ull)6*G);
  ktest("big.grow_zero",pread64_(fd,sx,6,(ll)5*G+1)==6&&sx[0]==0&&sx[5]==0);
  ktest("big.ftruncate32_neg",ftruncate_(fd,-1)==-22);
  ktest("big.truncate64",truncate64_("/mnt/sp",(ll)3*G+16)==0&&fsize(fd)==(ull)3*G+16);
  ktest("big.ftruncate_efbig",ftruncate64_(fd,(ll)9000*G)==-27&&fsize(fd)==(ull)3*G+16);
  /* fallocate */
  ktest("big.fallocate",fallocate_(fd,0,(ll)3*G,8192)==0&&fsize(fd)==(ull)3*G+8192);
  ktest("big.fallocate_keep",fallocate_(fd,1,(ll)8*G,4096)==0&&fsize(fd)==(ull)3*G+8192);
  /* sendfile64 depuis un decalage au-dela de 2 Go */
  fd2=open("/mnt/cp",O_RDWR|O_CREAT|O_TRUNC|O_LARGEFILE,0644);
  o=(ll)3*G;
  rc=sendfile64_(fd2,fd,&o,8);
  ktest("big.sendfile64",rc==8&&o==(ll)3*G+8&&pread64_(fd2,sx,8,0)==8&&memcmp_(sx,"HELLO-3G",8)==0);
  if(rc!=8){puts("  sendfile64 rc=");putd(rc);puts(" off=");putx((long)(o>>32));puts(":");putx((long)o);puts("\n");}
  close(fd2);
  /* RLIMIT_FSIZE a 3 Go + 100 */
  {
    unsigned long lim[2]={(unsigned long)(3*G+100),(unsigned long)-1};
    signal_set(25,xfsz,0);
    ktest("big.rlimit_set",setrlimit_(1,lim)==0);
    ktest("big.rlimit_ok",pwrite64_(fd,"x",1,(ll)3*G+99)==1);
    ktest("big.rlimit_efbig",pwrite64_(fd,"x",1,(ll)3*G+100)==-27);
    ktest("big.rlimit_trunc",ftruncate64_(fd,(ll)3*G+200)==-27);
    lim[0]=lim[1]=(unsigned long)-1;
    setrlimit_(1,lim);
  }
  /* ecriture sans O_LARGEFILE au-dela de 2 Go : EFBIG */
  fd2=open("/mnt/small",O_RDWR|O_CREAT,0644);
  ktest("big.nolfs_write",pwrite64_(fd2,"x",1,(ll)2*G)==-27);
  close(fd2);
  /* donnees reelles loin sur le disque : fichier de 3 Mo suivi de relecture */
  fd2=open("/mnt/far",O_RDWR|O_CREAT|O_LARGEFILE,0644);
  r=1;
  for(i=0;i<3072;i++){fillbuf(buf,1024,i);if(write(fd2,buf,1024)!=1024)r=0;}
  ktest("big.far_write",r&&fsize(fd2)==3072*1024);
  r=1;
  for(i=0;i<3072;i+=97){
    fillbuf(buf,1024,i);
    if(pread64_(fd2,sx,1024,(ll)i*1024)!=1024||memcmp_(sx,buf,1024)!=0)r=0;
  }
  ktest("big.far_read",r);
  close(fd2);
  close(fd);
  /* demontage et remontage : les tailles persistent (i_size_high) */
  sync();
  ktest("big.umount",umount("/mnt")==0);
  ktest("big.remount",mount("/dev/hda1","/mnt","ext2",0,0)==0);
  r=stat64_("/mnt/sp",sb);
  sz=ST_SIZE64(sb);
  ktest("big.size_persists",r==0&&sz==(ull)3*G+8192);
  if(sz!=(ull)3*G+8192){puts("  size=");putx((long)(sz>>32));puts(":");putx((long)sz);puts(" r=");putd(r);puts("\n");}
  fd=open("/mnt/sp",O_RDONLY|O_LARGEFILE,0);
  ktest("big.data_persists",fd>=0&&pread64_(fd,sx,8,(ll)3*G)==8&&memcmp_(sx,"HELLO-3G",8)==0);
  close(fd);
  fd2=open("/mnt/far",O_RDONLY|O_LARGEFILE,0);
  r=1;
  for(i=0;i<3072;i+=211){
    fillbuf(buf,1024,i);
    if(pread64_(fd2,sx,1024,(ll)i*1024)!=1024||memcmp_(sx,buf,1024)!=0)r=0;
  }
  ktest("big.far_persists",r);
  close(fd2);
  /* gros fichier cree par l'hote (marqueur a 2,5 Go) */
  fd=open("/mnt/host.big",O_RDONLY|O_LARGEFILE,0);
  if(fd>=0){
    ktest("big.host_size",fsize(fd)==(ull)3*G);
    ktest("big.host_marker",pread64_(fd,sx,12,(ll)G*5/2)==12&&memcmp_(sx,"HOST-MARK-25",12)==0);
    close(fd);
  }
  /* suppression : les blocs sont liberes */
  ktest("big.unlink",unlink("/mnt/sp")==0&&unlink("/mnt/cp")==0&&unlink("/mnt/far")==0&&unlink("/mnt/small")==0);
  sync();
  ktest("big.umount2",umount("/mnt")==0);
  return 0;
}

/* ---- FAT32 : fichier de 2,3 Go ecrit par l'hote ---- */
static int test_fat(void){
  int fd,r;
  if(mount("/dev/hda1","/mnt","vfat",0,0)!=0){ktest("bigfat.mount",0);return 1;}
  ktest("bigfat.mount",1);
  fd=open("/mnt/BIG.BIN",O_RDWR|O_LARGEFILE,0);
  ktest("bigfat.open",fd>=0);
  ktest("bigfat.size",fsize(fd)==(ull)2300*1024*1024);
  ktest("bigfat.marker_low",pread64_(fd,sx,10,100)==10&&memcmp_(sx,"FAT-MARK-A",10)==0);
  ktest("bigfat.marker_2g",pread64_(fd,sx,10,(ll)2100*1024*1024)==10&&memcmp_(sx,"FAT-MARK-B",10)==0);
  ktest("bigfat.marker_end",pread64_(fd,sx,10,(ll)2300*1024*1024-10)==10&&memcmp_(sx,"FAT-MARK-Z",10)==0);
  ktest("bigfat.open_no_lfs",open("/mnt/BIG.BIN",O_RDONLY,0)==-75);
  ktest("bigfat.stat32",statold_("/mnt/BIG.BIN",sb)==-75);
  ktest("bigfat.statx",statx_(-100,"/mnt/BIG.BIN",0,sx)==0&&*(ull*)(sx+40)==(ull)2300*1024*1024);
  {ull pos;r=llseek_(fd,0,2,&pos);ktest("bigfat.llseek_end",r==0&&pos==(ull)2300*1024*1024);}
  ktest("bigfat.append",pwrite64_(fd,"APPENDED-FAT",12,(ll)2300*1024*1024)==12&&fsize(fd)==(ull)2300*1024*1024+12);
  ktest("bigfat.append_read",pread64_(fd,sx,12,(ll)2300*1024*1024)==12&&memcmp_(sx,"APPENDED-FAT",12)==0);
  ktest("bigfat.write_2g",pwrite64_(fd,"OVER-2G-FAT",11,(ll)2200*1024*1024)==11&&pread64_(fd,sx,11,(ll)2200*1024*1024)==11&&memcmp_(sx,"OVER-2G-FAT",11)==0);
  ktest("bigfat.shrink",ftruncate64_(fd,(ll)2150*1024*1024)==0&&fsize(fd)==(ull)2150*1024*1024);
  ktest("bigfat.shrink_data",pread64_(fd,sx,10,(ll)2100*1024*1024)==10&&memcmp_(sx,"FAT-MARK-B",10)==0);
  ktest("bigfat.efbig_4g",pwrite64_(fd,"x",1,(ll)4*G)==-27);
  ktest("bigfat.ftruncate_efbig",ftruncate64_(fd,(ll)4*G+1)==-27);
  close(fd);
  sync();
  ktest("bigfat.umount",umount("/mnt")==0);
  return 0;
}

int main(void){
  int fd,n;char b[8];
  if(!cmdline_has("bigtest")){puts("  (bigtest : ignore sans 'bigtest' sur la ligne de commande)\n");return 0;}
  fd=open("/dev/hda1",O_RDONLY,0);
  if(fd<0){puts("  (pas de /dev/hda1 : bigtest ignore)\n");return 0;}
  lseek(fd,1024+56,0);n=read(fd,b,2);
  if(n==2&&(unsigned char)b[0]==0x53&&(unsigned char)b[1]==0xEF){close(fd);test_ext2();}
  else{close(fd);test_fat();}
  puts("KTEST: big DONE pass=");putd(ku_pass);puts(" fail=");putd(ku_fail);puts("\n");
  return ku_fail?1:0;
}
