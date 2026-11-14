/* ext2test : systeme de fichiers ext2 (lecture, ecriture, repertoires, liens,
   troncature, fichiers creux, renommage...) sur /dev/hda1 monte en /mnt.
   Le disque est fabrique par TESTS/K/RUNEXT2.SH (MKEXT2.SH) : sans ext2 sur
   /dev/hda1 le test est ignore (le banc d'essai RUNK.SH reste inchange). */
#include "ku.h"

#define SYS_truncate 92
#define SYS_fchmod 94
#define SYS_statfs 99
#define SYS_chown 182
#define SYS_utimes 271
#define SYS_umount2 52
#define SYS_pread64 180
#define SYS_pwrite64 181
#define SYS_fsync 118
#define SYS_lchown 16
#define SYS_getdents64 220

static int ftruncate(int fd,long n){return sc2(SYS_ftruncate,fd,n);}
static int truncate(const char*p,long n){return sc2(SYS_truncate,(long)p,n);}
static int fchmod(int fd,int m){return sc2(SYS_fchmod,fd,m);}
static int chown(const char*p,int u,int g){return sc3(SYS_chown,(long)p,u,g);}
static int fsync(int fd){return sc1(SYS_fsync,fd);}
static int statfs(const char*p,unsigned long*b){return sc2(SYS_statfs,(long)p,(long)b);}
static int stat64(const char*p,void*b){return sc2(SYS_stat64,(long)p,(long)b);}
static int lstat64(const char*p,void*b){return sc2(SYS_lstat64,(long)p,(long)b);}
static int fstat64(int fd,void*b){return sc2(SYS_fstat64,fd,(long)b);}
static int utimes(const char*p,long*tv){return sc2(SYS_utimes,(long)p,(long)tv);}

#define ST_MODE(b) (*(unsigned*)((b)+16))
#define ST_NLINK(b) (*(unsigned*)((b)+20))
#define ST_UID(b) (*(unsigned*)((b)+24))
#define ST_GID(b) (*(unsigned*)((b)+28))
#define ST_RDEV(b) (*(unsigned*)((b)+32))
#define ST_SIZE(b) (*(unsigned*)((b)+44))
#define ST_BLOCKS(b) (*(unsigned*)((b)+56))
#define ST_MTIME(b) (*(unsigned*)((b)+72))
#define ST_INO(b) (*(unsigned*)((b)+88))

static unsigned char pat(unsigned i){return (unsigned char)(i*7+(i>>8));}
static unsigned char sb_[96];
static unsigned char wbuf[8192];

static int fillcheck(int fd,unsigned off,unsigned n,unsigned patoff){
  /* lit n octets a partir de off et verifie le motif */
  unsigned done=0;
  unsigned char b[1500];
  if(lseek(fd,off,0)!=(int)off)return 0;
  while(done<n){
    unsigned c=n-done;int r,i;
    if(c>sizeof b)c=sizeof b;
    r=read(fd,b,c);
    if(r<=0)return 0;
    for(i=0;i<r;i++)if(b[i]!=pat(patoff+done+i))return 0;
    done+=r;
  }
  return 1;
}
static int fillwrite(int fd,unsigned n,unsigned patoff,unsigned chunk){
  unsigned done=0;
  while(done<n){
    unsigned c=n-done,i;int r;
    if(c>chunk)c=chunk;
    if(c>sizeof wbuf)c=sizeof wbuf;
    for(i=0;i<c;i++)wbuf[i]=pat(patoff+done+i);
    r=write(fd,wbuf,c);
    if(r!=(int)c)return 0;
    done+=c;
  }
  return 1;
}
static int slurp(const char*p,char*b,int max){
  int fd=open(p,O_RDONLY,0),n;
  if(fd<0)return fd;
  n=read(fd,b,max-1);
  if(n<0)n=0;
  b[n]=0;
  close(fd);
  return n;
}
static int put(const char*p,const char*s){
  int fd=open(p,O_WRONLY|O_CREAT|O_TRUNC,0644),n;
  if(fd<0)return fd;
  n=write(fd,s,strlen(s));
  close(fd);
  return n;
}
static int countdir(const char*d,char*names,int bufsz){
  /* nombre d'entrees (avec . et ..) via getdents64 en petits morceaux */
  char b[160];int fd=open(d,O_RDONLY|O_DIRECTORY,0),n,cnt=0;
  if(fd<0)return fd;
  while((n=getdents64(fd,b,sizeof b))>0){
    int o=0;
    while(o<n){
      struct{unsigned long long i,o;unsigned short l;unsigned char t;char nm[1];}*e=(void*)(b+o);
      cnt++;
      if(names&&bufsz>0){int k=0;while(e->nm[k]&&k<bufsz-1){names[k]=e->nm[k];k++;}}
      o+=e->l;
    }
  }
  close(fd);
  return n<0?n:cnt;
}
static int hasname(const char*d,const char*nm){
  char b[256];int fd=open(d,O_RDONLY|O_DIRECTORY,0),n,found=0;
  if(fd<0)return 0;
  while((n=getdents64(fd,b,sizeof b))>0){
    int o=0;
    while(o<n){
      struct{unsigned long long i,o;unsigned short l;unsigned char t;char nm[1];}*e=(void*)(b+o);
      if(strcmp(e->nm,nm)==0)found=1;
      o+=e->l;
    }
  }
  close(fd);
  return found;
}
static unsigned freeblocks(void){unsigned long s[16];statfs("/mnt",s);return s[3];}
static unsigned freeinodes(void){unsigned long s[16];statfs("/mnt",s);return s[6];}

int main(void){
  int fd,n,i,r;
  char b[512],c[300];
  unsigned fb0,fbs,fis,bsz;
  fd=open("/dev/hda1",O_RDONLY,0);
  if(fd<0){puts("  (pas de /dev/hda1 : tests ext2 ignores)\n");return 0;}
  lseek(fd,1024+56,0);n=read(fd,b,2);close(fd);
  if(n!=2||(unsigned char)b[0]!=0x53||(unsigned char)b[1]!=0xEF){
    puts("  (pas d'ext2 sur /dev/hda1 : tests ext2 ignores)\n");return 0;}
  r=mount("/dev/hda1","/mnt","ext2",0,0);
  ktest("ext2.mount",r==0);
  if(r!=0){putd(r);puts(" <- mount\n");return 1;}
  /* ---- lecture ---- */
  n=slurp("/mnt/hello.txt",b,sizeof b);
  ktest("ext2.read_small",n==16&&strcmp(b,"hello from ext2\n")==0);
  fd=open("/mnt/big.bin",O_RDONLY,0);
  ktest("ext2.big_open",fd>=0);
  ktest("ext2.big_read_seq",fillcheck(fd,0,300000,0));
  ktest("ext2.big_read_off",fillcheck(fd,131071,7000,131071)&&fillcheck(fd,12*1024-5,20,12*1024-5)
        &&fillcheck(fd,268*1024-3,10,268*1024-3));
  fstat64(fd,sb_);
  ktest("ext2.big_stat",ST_SIZE(sb_)==300000&&(ST_MODE(sb_)&0170000)==0100000);
  close(fd);
  n=countdir("/mnt/dir1",0,0);
  ktest("ext2.readdir_count",n==103);
  ktest("ext2.readdir_names",hasname("/mnt/dir1","f1.txt")&&hasname("/mnt/dir1","f100.txt")&&hasname("/mnt/dir1","sub")&&!hasname("/mnt/dir1","f101.txt"));
  n=slurp("/mnt/dir1/f57.txt",b,sizeof b);
  ktest("ext2.read_in_dir",n==8&&strcmp(b,"file 57\n")==0);
  n=readlink("/mnt/fastlink",c,sizeof c);
  ktest("ext2.readlink_fast",n==9&&memcmp_(c,"hello.txt",9)==0);
  n=readlink("/mnt/slowlink",c,sizeof c);
  ktest("ext2.readlink_slow",n==107&&c[0]=='x'&&memcmp_(c+100,"/target",7)==0);
  n=slurp("/mnt/fastlink",b,sizeof b);
  ktest("ext2.follow_symlink",n==16&&strcmp(b,"hello from ext2\n")==0);
  stat64("/mnt/hard.txt",sb_);
  ktest("ext2.hardlink_nlink",ST_NLINK(sb_)==2);
  lstat64("/mnt/fastlink",sb_);
  ktest("ext2.lstat_symlink",(ST_MODE(sb_)&0170000)==0120000&&ST_SIZE(sb_)==9);
  stat64("/mnt/emptydir",sb_);
  ktest("ext2.stat_dir",(ST_MODE(sb_)&0170000)==0040000&&ST_NLINK(sb_)==2);
  ktest("ext2.enoent",open("/mnt/nexiste",O_RDONLY,0)==-2&&open("/mnt/hello.txt/x",O_RDONLY,0)==-20);
  ktest("ext2.read_dir_eisdir",({int f=open("/mnt/dir1",O_RDONLY,0);int rr=read(f,b,10);close(f);rr==-21;}));
  /* ---- ecriture : fichiers ---- */
  {unsigned long s[16];statfs("/mnt",s);bsz=s[1];}
  fbs=freeblocks();fis=freeinodes();
  ktest("ext2.mkdir",mkdir("/mnt/w",0755)==0);
  ktest("ext2.mkdir_exist",mkdir("/mnt/w",0755)==-17);
  fd=open("/mnt/w/a.dat",O_RDWR|O_CREAT|O_EXCL,0644);
  ktest("ext2.create",fd>=0);
  ktest("ext2.write_pattern",fillwrite(fd,100000,0,777));
  ktest("ext2.write_readback",fillcheck(fd,0,100000,0));
  fstat64(fd,sb_);
  ktest("ext2.write_size",ST_SIZE(sb_)==100000&&ST_BLOCKS(sb_)>=196);
  close(fd);
  fd=open("/mnt/w/a.dat",O_WRONLY|O_APPEND,0);
  write(fd,"ENDMARK",7);close(fd);
  stat64("/mnt/w/a.dat",sb_);
  fd=open("/mnt/w/a.dat",O_RDONLY,0);
  lseek(fd,100000,0);n=read(fd,b,20);close(fd);
  ktest("ext2.append",ST_SIZE(sb_)==100007&&n==7&&memcmp_(b,"ENDMARK",7)==0);
  ktest("ext2.truncate_shrink",truncate("/mnt/w/a.dat",12345)==0);
  stat64("/mnt/w/a.dat",sb_);
  fd=open("/mnt/w/a.dat",O_RDWR,0);
  ktest("ext2.truncate_size",ST_SIZE(sb_)==12345&&fillcheck(fd,0,12345,0));
  ktest("ext2.ftruncate_extend",ftruncate(fd,50000)==0);
  lseek(fd,12345,0);
  r=1;
  for(i=0;i<37655;){int k=read(fd,wbuf,sizeof wbuf>37655-i?37655-i:sizeof wbuf),j;if(k<=0){r=0;break;}for(j=0;j<k;j++)if(wbuf[j])r=0;i+=k;}
  ktest("ext2.extend_zeros",r);
  /* la fin du dernier bloc partiel doit etre nulle apres reduction puis extension */
  ftruncate(fd,5000);ftruncate(fd,9000);
  lseek(fd,5000,0);n=read(fd,wbuf,4000);
  r=(n==4000);for(i=0;i<n;i++)if(wbuf[i])r=0;
  ktest("ext2.truncate_tail_zero",r&&fillcheck(fd,0,5000,0));
  close(fd);
  fd=open("/mnt/w/a.dat",O_WRONLY|O_TRUNC,0);
  stat64("/mnt/w/a.dat",sb_);
  ktest("ext2.otrunc",fd>=0&&ST_SIZE(sb_)==0&&ST_BLOCKS(sb_)==0);
  close(fd);
  /* fichier creux : blocs d'indirection simple, double, triple */
  fd=open("/mnt/w/sparse",O_RDWR|O_CREAT,0644);
  r=1;
  lseek(fd,5,0);r&=write(fd,"A",1)==1;
  lseek(fd,20000,0);r&=write(fd,"B",1)==1;
  lseek(fd,5000000,0);r&=write(fd,"C",1)==1;
  lseek(fd,70*1024*1024,0);r&=write(fd,"D",1)==1;
  ktest("ext2.sparse_write",r);
  fstat64(fd,sb_);
  ktest("ext2.sparse_size",ST_SIZE(sb_)==70*1024*1024+1&&ST_BLOCKS(sb_)<200);
  lseek(fd,5,0);read(fd,b,1);r=b[0]=='A';
  lseek(fd,20000,0);read(fd,b,1);r&=b[0]=='B';
  lseek(fd,5000000,0);read(fd,b,1);r&=b[0]=='C';
  lseek(fd,70*1024*1024,0);read(fd,b,1);r&=b[0]=='D';
  lseek(fd,3000000,0);read(fd,b,8);for(i=0;i<8;i++)if(b[i])r=0;
  ktest("ext2.sparse_read",r);
  close(fd);
  ktest("ext2.sparse_free",unlink("/mnt/w/sparse")==0);
  /* ---- repertoires ---- */
  ktest("ext2.mkdir_sub",mkdir("/mnt/w/d",0755)==0&&mkdir("/mnt/w/d/e",0755)==0);
  r=1;
  for(i=0;i<300;i++){
    char nm[80]="/mnt/w/d/un_nom_de_fichier_assez_long_numero_";
    int l=strlen(nm);
    nm[l++]='0'+i/100;nm[l++]='0'+(i/10)%10;nm[l++]='0'+i%10;nm[l]=0;
    fd=open(nm,O_WRONLY|O_CREAT,0644);
    if(fd<0){r=0;break;}
    write(fd,nm,l);close(fd);
  }
  ktest("ext2.dir_grow_300",r&&countdir("/mnt/w/d",0,0)==303);
  stat64("/mnt/w/d",sb_);
  ktest("ext2.dir_size_blocks",ST_SIZE(sb_)>=1024*3&&ST_NLINK(sb_)==3);
  r=1;
  for(i=0;i<300;i+=2){
    char nm[80]="/mnt/w/d/un_nom_de_fichier_assez_long_numero_";
    int l=strlen(nm);
    nm[l++]='0'+i/100;nm[l++]='0'+(i/10)%10;nm[l++]='0'+i%10;nm[l]=0;
    if(unlink(nm)!=0)r=0;
  }
  ktest("ext2.unlink_half",r&&countdir("/mnt/w/d",0,0)==153);
  r=1;
  for(i=0;i<300;i+=2){
    char nm[80]="/mnt/w/d/z";
    int l=strlen(nm);
    nm[l++]='0'+i/100;nm[l++]='0'+(i/10)%10;nm[l++]='0'+i%10;nm[l]=0;
    fd=open(nm,O_WRONLY|O_CREAT,0644);
    if(fd<0)r=0;else close(fd);
  }
  ktest("ext2.dir_reuse_slots",r&&countdir("/mnt/w/d",0,0)==303);
  ktest("ext2.rmdir_notempty",rmdir("/mnt/w/d")==-39);
  ktest("ext2.rmdir_file",rmdir("/mnt/hello.txt")==-20);
  ktest("ext2.rmdir_ok",rmdir("/mnt/w/d/e")==0&&access("/mnt/w/d/e",0)==-2);
  ktest("ext2.unlink_dir",unlink("/mnt/w/d")==-21);
  /* ---- renommages ---- */
  put("/mnt/w/r1","contenu-r1");put("/mnt/w/r2","contenu-r2");
  ktest("ext2.rename_replace",rename("/mnt/w/r1","/mnt/w/r2")==0);
  n=slurp("/mnt/w/r2",b,sizeof b);
  ktest("ext2.rename_content",n==10&&strcmp(b,"contenu-r1")==0&&access("/mnt/w/r1",0)==-2);
  mkdir("/mnt/w/x",0755);mkdir("/mnt/w/y",0755);mkdir("/mnt/w/x/sous",0755);
  put("/mnt/w/x/sous/f","dedans");
  ktest("ext2.rename_dir_move",rename("/mnt/w/x/sous","/mnt/w/y/sous2")==0);
  n=slurp("/mnt/w/y/sous2/f",b,sizeof b);
  ktest("ext2.rename_dir_content",n==6);
  chdir("/mnt/w/y/sous2");chdir("..");getcwd(c,sizeof c);chdir("/");
  ktest("ext2.rename_dotdot",strcmp(c,"/mnt/w/y")==0);
  stat64("/mnt/w/x",sb_);r=ST_NLINK(sb_)==2;stat64("/mnt/w/y",sb_);r&=ST_NLINK(sb_)==3;
  ktest("ext2.rename_nlink",r);
  mkdir("/mnt/w/vide",0755);
  ktest("ext2.rename_dir_over_empty",rename("/mnt/w/y/sous2","/mnt/w/vide")==0&&access("/mnt/w/vide/f",0)==0);
  stat64("/mnt/w/y",sb_);
  ktest("ext2.rename_over_nlink",ST_NLINK(sb_)==2);
  ktest("ext2.rename_into_self",rename("/mnt/w/y","/mnt/w/y/zz")==-22);
  mkdir("/mnt/w/ne",0755);put("/mnt/w/ne/f","x");
  ktest("ext2.rename_over_notempty",rename("/mnt/w/y","/mnt/w/ne")==-39);
  ktest("ext2.rename_file_over_dir",rename("/mnt/w/r2","/mnt/w/vide")==-21);
  ktest("ext2.rename_dir_over_file",rename("/mnt/w/vide","/mnt/w/r2")==-20);
  /* ---- liens ---- */
  put("/mnt/w/l1","lien");
  ktest("ext2.link",link("/mnt/w/l1","/mnt/w/l2")==0);
  stat64("/mnt/w/l1",sb_);r=ST_NLINK(sb_)==2;
  ktest("ext2.link_nlink",r);
  unlink("/mnt/w/l1");
  stat64("/mnt/w/l2",sb_);
  n=slurp("/mnt/w/l2",b,sizeof b);
  ktest("ext2.unlink_one_link",ST_NLINK(sb_)==1&&n==4);
  ktest("ext2.link_exist",link("/mnt/w/l2","/mnt/w/l2")==-17);
  ktest("ext2.link_dir",link("/mnt/w","/mnt/w/dl")==-1);
  /* supprimer un fichier ouvert : les donnees restent lisibles */
  fd=open("/mnt/w/open_unlink",O_RDWR|O_CREAT,0644);
  fillwrite(fd,30000,0,1000);
  unlink("/mnt/w/open_unlink");
  r=fillcheck(fd,0,30000,0);
  fb0=freeblocks();
  close(fd);
  ktest("ext2.unlink_open",r&&freeblocks()>fb0+(30000/bsz)-2);
  ktest("ext2.symlink_fast",symlink("cible","/mnt/w/s1")==0);
  n=readlink("/mnt/w/s1",c,sizeof c);
  ktest("ext2.symlink_fast_read",n==5&&memcmp_(c,"cible",5)==0);
  {char lg[200];for(i=0;i<150;i++)lg[i]='a'+(i%26);lg[150]=0;
   ktest("ext2.symlink_slow",symlink(lg,"/mnt/w/s2")==0);
   n=readlink("/mnt/w/s2",c,sizeof c);
   ktest("ext2.symlink_slow_read",n==150&&memcmp_(c,lg,150)==0);}
  put("/mnt/w/real","reel");symlink("real","/mnt/w/s3");
  n=slurp("/mnt/w/s3",b,sizeof b);
  ktest("ext2.symlink_follow",n==4&&strcmp(b,"reel")==0);
  ktest("ext2.symlink_unlink",unlink("/mnt/w/s2")==0&&unlink("/mnt/w/s1")==0);
  /* ---- fichiers speciaux, permissions, dates ---- */
  ktest("ext2.mknod_fifo",mknod("/mnt/w/ff",0010644,0)==0);
  ktest("ext2.mknod_chr",mknod("/mnt/w/cc",0020600,(5<<8)|1)==0);
  ktest("ext2.mknod_blk",mknod("/mnt/w/bb",0060600,(3<<8)|1)==0);
  stat64("/mnt/w/ff",sb_);r=(ST_MODE(sb_)&0170000)==0010000;
  stat64("/mnt/w/cc",sb_);r&=(ST_MODE(sb_)&0170000)==0020000&&(ST_RDEV(sb_)&0xFFFF)==((5<<8)|1);
  stat64("/mnt/w/bb",sb_);r&=(ST_MODE(sb_)&0170000)==0060000&&(ST_RDEV(sb_)&0xFFFF)==((3<<8)|1);
  ktest("ext2.mknod_stat",r);
  ktest("ext2.chmod",chmod("/mnt/w/real",0600)==0);
  stat64("/mnt/w/real",sb_);
  ktest("ext2.chmod_stat",(ST_MODE(sb_)&07777)==0600);
  ktest("ext2.chown",chown("/mnt/w/real",1234,5678)==0);
  stat64("/mnt/w/real",sb_);
  ktest("ext2.chown_stat",ST_UID(sb_)==1234&&ST_GID(sb_)==5678);
  {long tv[4]={1000000000,0,1100000000,0};
   ktest("ext2.utimes",utimes("/mnt/w/real",tv)==0);
   stat64("/mnt/w/real",sb_);
   ktest("ext2.utimes_stat",ST_MTIME(sb_)==1100000000);}
  /* ---- statfs : les blocs et inodes rendus ---- */
  unlink("/mnt/w/real");unlink("/mnt/w/s3");unlink("/mnt/w/l2");
  unlink("/mnt/w/ff");unlink("/mnt/w/cc");unlink("/mnt/w/bb");unlink("/mnt/w/r2");
  unlink("/mnt/w/vide/f");rmdir("/mnt/w/vide");unlink("/mnt/w/ne/f");rmdir("/mnt/w/ne");rmdir("/mnt/w/x");rmdir("/mnt/w/y");
  unlink("/mnt/w/a.dat");
  for(i=0;i<300;i++){
    char nm[80]="/mnt/w/d/un_nom_de_fichier_assez_long_numero_";
    int l=strlen(nm);
    nm[l++]='0'+i/100;nm[l++]='0'+(i/10)%10;nm[l++]='0'+i%10;nm[l]=0;
    unlink(nm);
  }
  for(i=0;i<300;i+=2){
    char nm[80]="/mnt/w/d/z";
    int l=strlen(nm);
    nm[l++]='0'+i/100;nm[l++]='0'+(i/10)%10;nm[l++]='0'+i%10;nm[l]=0;
    unlink(nm);
  }
  ktest("ext2.rmdir_emptied",rmdir("/mnt/w/d")==0);
  ktest("ext2.rmdir_w",rmdir("/mnt/w")==0);
  ktest("ext2.statfs_restored",freeblocks()==fbs&&freeinodes()==fis);
  /* ---- montage : double montage, lecture seule ---- */
  ktest("ext2.mount_twice",mount("/dev/hda1","/tmp","ext2",0,0)==-16);
  ktest("ext2.umount_busy",({chdir("/mnt/dir1");int rr=umount("/mnt");chdir("/");rr==-16;}));
  put("/mnt/persist.txt","persistant\n");
  mkdir("/mnt/pdir",0755);put("/mnt/pdir/fichier","dans pdir\n");
  symlink("persist.txt","/mnt/plink");
  fd=open("/mnt/pbig",O_WRONLY|O_CREAT,0644);fillwrite(fd,400000,3,4096);close(fd);
  ktest("ext2.umount",umount("/mnt")==0);
  ktest("ext2.remount_ro",mount("/dev/hda1","/mnt","ext2",1,0)==0);
  n=slurp("/mnt/persist.txt",b,sizeof b);
  ktest("ext2.persist_file",n==11&&strcmp(b,"persistant\n")==0);
  n=slurp("/mnt/pdir/fichier",b,sizeof b);
  ktest("ext2.persist_dir",n==10&&strcmp(b,"dans pdir\n")==0);
  fd=open("/mnt/pbig",O_RDONLY,0);
  ktest("ext2.persist_big",fillcheck(fd,0,400000,3));close(fd);
  n=readlink("/mnt/plink",c,sizeof c);
  ktest("ext2.persist_link",n==11);
  ktest("ext2.ro_create",open("/mnt/nouveau",O_WRONLY|O_CREAT,0644)==-30);
  ktest("ext2.ro_write",({int f=open("/mnt/hello.txt",O_WRONLY,0);f==-30;}));
  ktest("ext2.ro_mkdir",mkdir("/mnt/zz",0755)==-30);
  ktest("ext2.ro_unlink",unlink("/mnt/hello.txt")==-30);
  ktest("ext2.ro_rename",rename("/mnt/hello.txt","/mnt/h2")==-30);
  {unsigned long s[16];statfs("/mnt",s);ktest("ext2.statfs_magic",s[0]==0xEF53&&(s[1]==1024||s[1]==2048||s[1]==4096));}
  ktest("ext2.umount_ro",umount("/mnt")==0);
  /* laisser le contenu rw pour la suite de la verification hote */
  r=mount("/dev/hda1","/mnt","ext2",0,0);
  ktest("ext2.mount_rw_again",r==0);
  unlink("/mnt/pbig");
  umount("/mnt");
  puts("KTEST: ext2 DONE\n");
  return ku_fail?1:0;
}
