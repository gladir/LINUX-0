/* ext4test : ext3/ext4 (extents, repertoires indexes, extensions non
   initialisees, ENOSPC, arbre d'extents profond...) sur /dev/hda1 monte en
   /mnt. Le disque est fabrique par TESTS/K/RUNEXT4.SH (MKEXT4.SH : /falloc.bin
   a extensions non initialisees, /hdir indexe par e2fsck -D). Sans ext4 sur
   /dev/hda1 (pas d'extents) le test est ignore. */
#include "ku.h"

#define SYS_truncate 92
#define SYS_statfs 99
#define SYS_umount2 52
#define SYS_fsync 118
#define SYS_getdents64 220

static int truncate(const char*p,long n){return sc2(SYS_truncate,(long)p,n);}
static int ftruncate(int fd,long n){return sc2(SYS_ftruncate,fd,n);}
static int fsync(int fd){return sc1(SYS_fsync,fd);}
static int statfs(const char*p,unsigned long*b){return sc2(SYS_statfs,(long)p,(long)b);}
static int stat64(const char*p,void*b){return sc2(SYS_stat64,(long)p,(long)b);}
static int fstat64(int fd,void*b){return sc2(SYS_fstat64,fd,(long)b);}
#define ST_SIZE(b) (*(unsigned*)((b)+44))
#define ST_BLOCKS(b) (*(unsigned*)((b)+56))
static int statx(const char*p,void*b){return sc5(383,-100,(long)p,0,0xFFF,(long)b);}
static unsigned char sb_[96];
static unsigned char sx_[256];
static unsigned char wb[4096];

static unsigned freeblocks(void){unsigned long s[16];statfs("/mnt",s);return s[3];}
static unsigned freeinodes(void){unsigned long s[16];statfs("/mnt",s);return s[6];}
static int countdir(const char*d){
  char b[1024];int fd=open(d,O_RDONLY|O_DIRECTORY,0),n,cnt=0;
  if(fd<0)return fd;
  while((n=getdents64(fd,b,sizeof b))>0){
    int o=0;
    while(o<n){
      struct{unsigned long long i,o;unsigned short l;unsigned char t;char nm[1];}*e=(void*)(b+o);
      cnt++;o+=e->l;
    }
  }
  close(fd);
  return n<0?n:cnt;
}
static void num(char*d,const char*p,int v,int w){
  int l=strlen(p),i;
  for(i=0;i<l;i++)d[i]=p[i];
  for(i=w-1;i>=0;i--){d[l+i]='0'+v%10;v/=10;}
  d[l+w]=0;
}
static unsigned char pat(unsigned i){return (unsigned char)(i*13+(i>>7)+5);}

int main(void){
  int fd,n,i,r,bs,hasext;
  char b[600],nm[96];
  if(ku_cmdline_has("bigtest"))return 0;
  if(ku_cmdline_has("jrntest"))return 0;
  fd=open("/dev/hda1",O_RDONLY,0);
  if(fd<0){puts("  (pas de /dev/hda1 : tests ext4 ignores)\n");return 0;}
  lseek(fd,1024+92,0);n=read(fd,b,12);close(fd);
  /* compat (journal : 4), incompat (extents : 0x40) */
  if(n!=12||!((b[0]&4)||(b[4]&0x40))){puts("  (pas d'ext3/ext4 : tests ext4 ignores)\n");return 0;}
  hasext=(b[4]&0x40)!=0;
  r=mount("/dev/hda1","/mnt","ext4",0,0);
  ktest("ext4.mount",r==0);
  if(r!=0){putd(r);puts(" <- mount\n");return 1;}
  {unsigned long s[16];statfs("/mnt",s);bs=s[1];ktest("ext4.statfs_magic",s[0]==0xEF53);}
  /* ---- journal sale fabrique par l'hote (debugfs jo/jw/jc) : rejoue au
     montage ; /jblk.txt = "N1 N2 N3" : N1 = B (2e transaction), N2 = revoque
     (reste nul), N3 = A (apres la revocation) ---- */
  fd=open("/mnt/jblk.txt",O_RDONLY,0);
  if(fd>=0){
    long nb[3]={0,0,0};int k=0,j;
    n=read(fd,b,sizeof b-1);close(fd);
    for(j=0;j<n&&k<3;j++){
      if(b[j]>='0'&&b[j]<='9')nb[k]=nb[k]*10+(b[j]-'0');
      else if(nb[k]>0)k++;
    }
    fd=open("/dev/hda1",O_RDONLY,0);
    if(fd>=0&&nb[0]>0){
      static unsigned char blk[65536];
      long off;
      off=nb[0]*bs;lseek(fd,off,0);r=read(fd,blk,bs)==bs&&memcmp_(blk,"JRNLTEST-B-",11)==0&&blk[bs-1]!=0;
      ktest("ext4.jrn_replay_tx2",r);
      off=nb[1]*bs;lseek(fd,off,0);r=read(fd,blk,bs)==bs;
      for(j=0;j<bs;j++)if(blk[j])r=0;
      ktest("ext4.jrn_revoked_zero",r);
      off=nb[2]*bs;lseek(fd,off,0);r=read(fd,blk,bs)==bs&&memcmp_(blk,"JRNLTEST-A-",11)==0;
      ktest("ext4.jrn_replay_tx4",r);
      close(fd);
    }
  }
  /* ---- date de creation (i_crtime des inodes de 256 octets) ---- */
  {
    unsigned long long idx=0;int isz;
    fd=open("/dev/hda1",O_RDONLY,0);lseek(fd,1024+88,0);read(fd,b,2);close(fd);
    isz=(unsigned char)b[0]|((unsigned char)b[1]<<8);
    (void)idx;
    fd=open("/mnt/btime.f",O_WRONLY|O_CREAT|O_TRUNC,0644);write(fd,"x",1);close(fd);
    r=statx("/mnt/btime.f",sx_);
    if(isz>128){
      unsigned bt=*(unsigned*)(sx_+80),mt=*(unsigned*)(sx_+112);
      ktest("ext4.statx_btime",r==0&&(*(unsigned*)sx_&0x800)&&bt>1000000000u&&bt<=mt);
    }
    unlink("/mnt/btime.f");
  }
  /* ---- extensions non initialisees (fallocate de l'hote) ---- */
  fd=hasext?open("/mnt/falloc.bin",O_RDWR,0):-1;
  if(fd>=0){
    fstat64(fd,sb_);
    ktest("ext4.uninit_size",ST_SIZE(sb_)==102400&&ST_BLOCKS(sb_)>=200);
    n=read(fd,wb,sizeof wb);r=n==(int)sizeof wb;
    for(i=0;i<n;i++)if(wb[i])r=0;
    ktest("ext4.uninit_reads_zero",r);
    lseek(fd,50000,0);
    for(i=0;i<3000;i++)wb[i]=pat(i);
    ktest("ext4.uninit_write",write(fd,wb,3000)==3000);
    lseek(fd,49990,0);n=read(fd,wb,3020);
    r=n==3020;
    for(i=0;i<10;i++)if(wb[i])r=0;
    for(i=10;i<3010;i++)if(wb[i]!=pat(i-10))r=0;
    for(i=3010;i<3020;i++)if(wb[i])r=0;
    ktest("ext4.uninit_convert",r);
    lseek(fd,0,0);n=read(fd,wb,4096);r=n==4096;
    for(i=0;i<n;i++)if(wb[i])r=0;
    lseek(fd,102000,0);n=read(fd,wb,400);r&=n==400;
    for(i=0;i<n;i++)if(wb[i])r=0;
    ktest("ext4.uninit_rest_zero",r);
    close(fd);
  }
  /* ---- arbre d'extents profond : un bloc sur deux ---- */
  if(hasext){
    unsigned f0=freeblocks();
    int nb=700;
    fd=open("/mnt/frag",O_RDWR|O_CREAT|O_TRUNC,0644);
    ktest("ext4.frag_create",fd>=0);
    r=1;
    for(i=0;i<nb;i++){
      int k;
      for(k=0;k<bs&&k<(int)sizeof wb;k++)wb[k]=pat(i*7+k);
      lseek(fd,(long)i*2*bs,0);
      if(write(fd,wb,bs>(int)sizeof wb?sizeof wb:bs)<=0){r=0;break;}
    }
    ktest("ext4.frag_write",r);
    fstat64(fd,sb_);
    ktest("ext4.frag_size",ST_SIZE(sb_)==(unsigned)((nb*2-2)*bs+(bs>(int)sizeof wb?sizeof wb:bs)));
    r=1;
    for(i=0;i<nb;i++){
      int k,m=bs>(int)sizeof wb?(int)sizeof wb:bs;
      lseek(fd,(long)i*2*bs,0);
      if(read(fd,wb,m)!=m){r=0;break;}
      for(k=0;k<m;k++)if(wb[k]!=pat(i*7+k))r=0;
      if(i<nb-1){
        lseek(fd,(long)(i*2+1)*bs,0);
        if(read(fd,wb,16)!=16){r=0;break;}
        for(k=0;k<16;k++)if(wb[k])r=0;
      }
    }
    ktest("ext4.frag_readback",r);
    /* troncature au milieu de l'arbre, puis nouvelle ecriture */
    ktest("ext4.frag_truncate",ftruncate(fd,(long)300*2*bs+bs/2)==0);
    r=1;
    for(i=0;i<300;i++){
      int k,m=bs>(int)sizeof wb?(int)sizeof wb:bs;
      lseek(fd,(long)i*2*bs,0);
      if(read(fd,wb,m)!=m){r=0;break;}
      for(k=0;k<m;k++)if(wb[k]!=pat(i*7+k))r=0;
    }
    ktest("ext4.frag_trunc_data",r);
    lseek(fd,(long)310*2*bs,0);for(i=0;i<64;i++)wb[i]=0x5A;
    write(fd,wb,64);
    lseek(fd,(long)310*2*bs,0);read(fd,wb,64);r=1;
    for(i=0;i<64;i++)if(wb[i]!=0x5A)r=0;
    ktest("ext4.frag_regrow",r);
    fsync(fd);
    close(fd);
    ktest("ext4.frag_unlink",unlink("/mnt/frag")==0);
    ktest("ext4.frag_free_restored",freeblocks()==f0);
  }
  /* ---- repertoire indexe (htree) ---- */
  n=countdir("/mnt/hdir");
  if(n>0){
    int nf=n-2;
    ktest("ext4.htree_count",nf>=300);
    num(nm,"/mnt/hdir/h",nf/2,4);
    stat64(nm,sb_);
    ktest("ext4.htree_lookup",ST_SIZE(sb_)>=0&&access(nm,0)==0);
    ktest("ext4.htree_enoent",access("/mnt/hdir/zzzz",0)==-2);
    ktest("ext4.htree_create",({int f=open("/mnt/hdir/nouveau",O_WRONLY|O_CREAT,0644);int rr=f>=0;if(f>=0)close(f);rr;})&&countdir("/mnt/hdir")==n+1);
    r=1;
    for(i=0;i<nf;i+=3){num(nm,"/mnt/hdir/h",i,4);if(unlink(nm)!=0)r=0;}
    ktest("ext4.htree_unlink",r&&countdir("/mnt/hdir")==n+1-(nf+2)/3);
    ktest("ext4.htree_lookup_after",access("/mnt/hdir/nouveau",0)==0&&access("/mnt/hdir/h0001",0)==0);
    r=1;
    for(i=0;i<400;i++){num(nm,"/mnt/hdir/n",i,4);fd=open(nm,O_WRONLY|O_CREAT,0644);if(fd<0)r=0;else close(fd);}
    ktest("ext4.htree_grow",r);
  }
  /* ---- liens symboliques longs (extents) ---- */
  {
    char t[200],c[300];
    for(i=0;i<150;i++)t[i]='a'+(i%26);
    t[150]=0;
    ktest("ext4.symlink_slow",symlink(t,"/mnt/slow4")==0);
    n=readlink("/mnt/slow4",c,sizeof c);
    ktest("ext4.symlink_slow_read",n==150&&memcmp_(c,t,150)==0);
    ktest("ext4.symlink_fast",symlink("cible","/mnt/fast4")==0&&readlink("/mnt/fast4",c,sizeof c)==5);
    unlink("/mnt/slow4");unlink("/mnt/fast4");
  }
  /* ---- fichier de plusieurs mega-octets et ENOSPC ---- */
  {
    unsigned f0=freeblocks(),i0=freeinodes();
    long total=0;
    int e=0;
    fd=open("/mnt/plein",O_RDWR|O_CREAT|O_TRUNC,0644);
    for(i=0;i<4096;i++)wb[i]=pat(i);
    while(1){
      int w=write(fd,wb,4096);
      if(w<0){e=w;break;}
      total+=w;
      if(w<4096){break;}
    }
    ktest("ext4.enospc",e==-28||total>0);
    n=write(fd,wb,4096);
    ktest("ext4.enospc_again",n==-28);
    if(n!=-28){puts("  enospc_again: n=");putd(n);puts(" e=");putd(e);puts(" total=");putd(total);puts("\n");}
    fstat64(fd,sb_);
    ktest("ext4.enospc_size",ST_SIZE(sb_)==(unsigned)total);
    lseek(fd,0,0);
    r=1;
    for(i=0;i<(total/4096<64?total/4096:64);i++){
      int k;
      if(read(fd,wb,4096)!=4096){r=0;break;}
      for(k=0;k<4096;k++)if(wb[k]!=pat(k))r=0;
    }
    ktest("ext4.enospc_data",r);
    close(fd);
    ktest("ext4.enospc_unlink",unlink("/mnt/plein")==0);
    ktest("ext4.enospc_restored",freeblocks()==f0&&freeinodes()==i0);
    r=open("/mnt/apres",O_WRONLY|O_CREAT,0644);
    ktest("ext4.after_enospc_create",r>=0&&write(r,"ok",2)==2);
    if(r>=0)close(r);
    unlink("/mnt/apres");
  }
  sync();
  ktest("ext4.umount",umount("/mnt")==0);
  r=mount("/dev/hda1","/mnt","ext4",0,0);
  ktest("ext4.remount_rw",r==0);
  if(countdir("/mnt/hdir")>0){
    ktest("ext4.persist_htree",access("/mnt/hdir/nouveau",0)==0&&access("/mnt/hdir/n0399",0)==0);
  }
  umount("/mnt");
  puts("KTEST: ext4 DONE\n");
  return ku_fail?1:0;
}
