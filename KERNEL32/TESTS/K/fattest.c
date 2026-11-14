/* fattest : systeme de fichiers FAT12/16/32 (vfat : noms longs) sur /dev/hdb (ou /dev/fd0)
   monte en /mnt (lecture, ecriture, repertoires, renommage, troncature...).
   Le disque est fabrique par TESTS/K/RUNFAT.SH (mkfs.vfat + mtools) : sans
   FAT sur /dev/hdb ni /dev/fd0 le test est ignore (RUNK.SH reste inchange). */
#include "ku.h"

#define SYS_truncate 92
#define SYS_fchmod 94
#define SYS_statfs 99
#define SYS_chown 182
#define SYS_utimes 271
#define SYS_umount2 52
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
static unsigned freeclus(void){unsigned long s[16];statfs("/mnt",s);return s[3];}
static int isz(const char*p,unsigned n){return stat64(p,sb_)==0&&ST_SIZE(sb_)==n;}
static int zerocheck(int fd,unsigned off,unsigned n){
  unsigned done=0;
  if(lseek(fd,off,0)!=(int)off)return 0;
  while(done<n){
    int k=read(fd,wbuf,sizeof wbuf>n-done?n-done:sizeof wbuf),j;
    if(k<=0)return 0;
    for(j=0;j<k;j++)if(wbuf[j])return 0;
    done+=k;
  }
  return 1;
}
static void mkname(char*d,const char*pre,int n){
  int k=0;char t[12];int m=0;
  while(pre[k]){d[k]=pre[k];k++;}
  if(n==0)t[m++]='0';
  while(n>0){t[m++]='0'+n%10;n/=10;}
  while(m>0)d[k++]=t[--m];
  d[k]=0;
}

int main(void){
  int fd,n,i,r;
  char b[512],c[300],nm[300];
  const char*dev="/dev/hdb";
  unsigned fc0,fc1;
  fd=open(dev,O_RDONLY,0);
  if(fd<0){dev="/dev/fd0";fd=open(dev,O_RDONLY,0);}
  if(fd<0){puts("  (pas de /dev/hdb ni de /dev/fd0 : tests FAT ignores)\n");return 0;}
  n=read(fd,b,512);close(fd);
  if(n!=512||((unsigned char)b[0]!=0xEB&&(unsigned char)b[0]!=0xE9)
     ||(unsigned char)b[510]!=0x55||(unsigned char)b[511]!=0xAA){
    puts("  (pas de FAT sur /dev/hdb ni /dev/fd0 : tests FAT ignores)\n");return 0;}
  r=mount(dev,"/mnt","vfat",0,0);
  ktest("fat.mount",r==0);
  if(r!=0){putd(r);puts(" <- mount\n");return 1;}
  /* ---- lecture ---- */
  n=slurp("/mnt/hello.txt",b,sizeof b);
  ktest("fat.read_small",n==15&&strcmp(b,"hello from fat\n")==0);
  n=slurp("/mnt/HELLO.TXT",b,sizeof b);
  ktest("fat.case_insensitive",n==15);
  n=slurp("/mnt/Long File Name Example.txt",b,sizeof b);
  ktest("fat.read_longname",n==15&&strcmp(b,"long name file\n")==0);
  ktest("fat.longname_listed",hasname("/mnt","Long File Name Example.txt")
        &&hasname("/mnt","big.bin")&&hasname("/mnt","dir1"));
  fd=open("/mnt/big.bin",O_RDONLY,0);
  ktest("fat.big_open",fd>=0);
  ktest("fat.big_read_seq",fillcheck(fd,0,300000,0));
  ktest("fat.big_read_off",fillcheck(fd,131071,7000,131071)
        &&fillcheck(fd,4096*20-5,20,4096*20-5)&&fillcheck(fd,299000,1000,299000));
  fstat64(fd,sb_);
  ktest("fat.big_stat",ST_SIZE(sb_)==300000&&(ST_MODE(sb_)&0170000)==0100000);
  close(fd);
  n=countdir("/mnt/dir1",0,0);
  ktest("fat.readdir_count",n==43);
  ktest("fat.readdir_names",hasname("/mnt/dir1","f1.txt")&&hasname("/mnt/dir1","f40.txt")
        &&hasname("/mnt/dir1","sub")&&!hasname("/mnt/dir1","f41.txt"));
  n=slurp("/mnt/dir1/f23.txt",b,sizeof b);
  ktest("fat.read_in_dir",n==8&&strcmp(b,"file 23\n")==0);
  n=slurp("/mnt/dir1/sub/deep.txt",b,sizeof b);
  ktest("fat.read_deep",n==5&&strcmp(b,"deep\n")==0);
  stat64("/mnt/emptydir",sb_);
  ktest("fat.stat_dir",(ST_MODE(sb_)&0170000)==0040000);
  ktest("fat.enoent",open("/mnt/nexiste",O_RDONLY,0)==-2&&open("/mnt/hello.txt/x",O_RDONLY,0)==-20);
  ktest("fat.read_dir_eisdir",({int f=open("/mnt/dir1",O_RDONLY,0);int rr=read(f,b,10);close(f);rr==-21;}));
  {unsigned long s[16];statfs("/mnt",s);ktest("fat.statfs",s[0]==0x4d44&&s[3]>0&&s[1]>=512&&s[2]>s[3]);}
  ktest("fat.dotdot",({stat64("/mnt/dir1/sub/..",sb_);(ST_MODE(sb_)&0170000)==0040000;})
        &&slurp("/mnt/dir1/sub/../f1.txt",b,sizeof b)==7);
  /* ---- ecriture : fichiers ---- */
  fc0=freeclus();
  ktest("fat.mkdir",mkdir("/mnt/w",0755)==0);
  ktest("fat.mkdir_exist",mkdir("/mnt/w",0755)==-17&&mkdir("/mnt/W",0755)==-17);
  fd=open("/mnt/w/a.dat",O_RDWR|O_CREAT|O_EXCL,0644);
  ktest("fat.create",fd>=0);
  ktest("fat.write_pattern",fillwrite(fd,100000,0,777));
  ktest("fat.write_readback",fillcheck(fd,0,100000,0));
  fstat64(fd,sb_);
  ktest("fat.write_size",ST_SIZE(sb_)==100000&&ST_BLOCKS(sb_)>=196);
  close(fd);
  fd=open("/mnt/w/a.dat",O_WRONLY|O_APPEND,0);
  write(fd,"ENDMARK",7);close(fd);
  fd=open("/mnt/w/a.dat",O_RDONLY,0);
  lseek(fd,100000,0);n=read(fd,b,20);close(fd);
  ktest("fat.append",isz("/mnt/w/a.dat",100007)&&n==7&&memcmp_(b,"ENDMARK",7)==0);
  ktest("fat.truncate_shrink",truncate("/mnt/w/a.dat",12345)==0);
  fd=open("/mnt/w/a.dat",O_RDWR,0);
  ktest("fat.truncate_size",isz("/mnt/w/a.dat",12345)&&fillcheck(fd,0,12345,0));
  ktest("fat.ftruncate_extend",ftruncate(fd,50000)==0&&zerocheck(fd,12345,37655));
  ftruncate(fd,5000);ftruncate(fd,9000);
  ktest("fat.truncate_tail_zero",zerocheck(fd,5000,4000)&&fillcheck(fd,0,5000,0));
  /* ecriture au-dela de la fin : trou rempli de zeros */
  lseek(fd,20000,0);write(fd,"TAIL",4);
  ktest("fat.write_past_end",isz("/mnt/w/a.dat",20004)&&zerocheck(fd,9000,11000));
  close(fd);
  fd=open("/mnt/w/a.dat",O_WRONLY|O_TRUNC,0);
  ktest("fat.otrunc",fd>=0&&isz("/mnt/w/a.dat",0));
  close(fd);
  ktest("fat.unlink",unlink("/mnt/w/a.dat")==0&&open("/mnt/w/a.dat",O_RDONLY,0)==-2);
  fc1=freeclus();
  ktest("fat.free_restored",fc1==fc0-1||fc1==fc0);
  ktest("fat.unlink_enoent",unlink("/mnt/w/a.dat")==-2);
  /* ---- noms ---- */
  ktest("fat.put_short",put("/mnt/w/short.txt","SHORT\n")==6);
  ktest("fat.put_lower",put("/mnt/w/lower.txt","lower\n")==6&&slurp("/mnt/w/LOWER.TXT",b,sizeof b)==6);
  ktest("fat.listed_case",hasname("/mnt/w","lower.txt")&&hasname("/mnt/w","short.txt"));
  ktest("fat.put_long",put("/mnt/w/A Very Long File Name With Spaces.data","long\n")==5);
  ktest("fat.long_listed",hasname("/mnt/w","A Very Long File Name With Spaces.data"));
  ktest("fat.long_ci",slurp("/mnt/w/a very long file name with spaces.DATA",b,sizeof b)==5);
  ktest("fat.put_mixed",put("/mnt/w/MixedCase.Txt","m\n")==2&&hasname("/mnt/w","MixedCase.Txt")
        &&!hasname("/mnt/w","mixedcase.txt"));
  ktest("fat.put_utf8",put("/mnt/w/caf\xc3\xa9.txt","cafe\n")==5&&hasname("/mnt/w","caf\xc3\xa9.txt")
        &&slurp("/mnt/w/caf\xc3\xa9.txt",b,sizeof b)==5);
  ktest("fat.put_dots",put("/mnt/w/two.dots.in.name.txt","d\n")==2&&hasname("/mnt/w","two.dots.in.name.txt"));
  ktest("fat.bad_name",open("/mnt/w/bad?name",O_WRONLY|O_CREAT,0644)==-22
        &&open("/mnt/w/bad:name",O_WRONLY|O_CREAT,0644)==-22);
  /* deux noms longs qui partagent le meme debut : noms courts ~1, ~2 */
  ktest("fat.tilde_names",put("/mnt/w/longname_number_one.txt","1\n")==2&&put("/mnt/w/longname_number_two.txt","2\n")==2
        &&slurp("/mnt/w/longname_number_one.txt",b,sizeof b)==2&&b[0]=='1'
        &&slurp("/mnt/w/longname_number_two.txt",b,sizeof b)==2&&b[0]=='2');
  ktest("fat.create_exist",open("/mnt/w/short.txt",O_WRONLY|O_CREAT|O_EXCL,0644)==-17
        &&open("/mnt/w/SHORT.TXT",O_WRONLY|O_CREAT|O_EXCL,0644)==-17);
  /* ---- renommage ---- */
  ktest("fat.rename",rename("/mnt/w/short.txt","/mnt/w/renamed.txt")==0
        &&open("/mnt/w/short.txt",O_RDONLY,0)==-2&&slurp("/mnt/w/renamed.txt",b,sizeof b)==6);
  ktest("fat.rename_to_long",rename("/mnt/w/renamed.txt","/mnt/w/now a much longer name.txt")==0
        &&slurp("/mnt/w/now a much longer name.txt",b,sizeof b)==6);
  ktest("fat.rename_case",rename("/mnt/w/lower.txt","/mnt/w/LOWER.txt")==0
        &&hasname("/mnt/w","LOWER.txt")&&!hasname("/mnt/w","lower.txt"));
  mkdir("/mnt/w/sub1",0755);mkdir("/mnt/w/sub2",0755);
  put("/mnt/w/sub1/m.txt","move\n");
  ktest("fat.rename_xdir",rename("/mnt/w/sub1/m.txt","/mnt/w/sub2/moved.txt")==0
        &&slurp("/mnt/w/sub2/moved.txt",b,sizeof b)==5);
  put("/mnt/w/sub2/target.txt","old target\n");
  ktest("fat.rename_over",rename("/mnt/w/sub2/moved.txt","/mnt/w/sub2/target.txt")==0
        &&slurp("/mnt/w/sub2/target.txt",b,sizeof b)==5&&b[0]=='m'&&countdir("/mnt/w/sub2",0,0)==3);
  ktest("fat.rename_dir",rename("/mnt/w/sub1","/mnt/w/sub2/sub1moved")==0
        &&hasname("/mnt/w/sub2","sub1moved")&&!hasname("/mnt/w","sub1"));
  put("/mnt/w/sub2/sub1moved/in.txt","inside\n");
  ktest("fat.rename_dir_content",slurp("/mnt/w/sub2/sub1moved/in.txt",b,sizeof b)==7
        &&({stat64("/mnt/w/sub2/sub1moved/..",sb_);(ST_MODE(sb_)&0170000)==0040000;})
        &&slurp("/mnt/w/sub2/sub1moved/../target.txt",b,sizeof b)==5);
  ktest("fat.rename_dir_dst_notempty",rename("/mnt/w/sub2","/mnt/w/sub2x")==0&&mkdir("/mnt/w/e1",0755)==0
        &&rename("/mnt/w/e1","/mnt/w/sub2x")==-39);
  ktest("fat.rename_file_over_dir",rename("/mnt/w/LOWER.txt","/mnt/w/e1")==-21);
  ktest("fat.rename_dir_over_file",rename("/mnt/w/e1","/mnt/w/LOWER.txt")==-20);
  ktest("fat.rename_same",rename("/mnt/w/LOWER.txt","/mnt/w/lower.TXT")==0&&hasname("/mnt/w","lower.TXT"));
  /* ---- rmdir ---- */
  ktest("fat.rmdir_notempty",rmdir("/mnt/w/sub2x")==-39);
  ktest("fat.rmdir_empty",rmdir("/mnt/w/e1")==0&&open("/mnt/w/e1",O_RDONLY,0)==-2);
  ktest("fat.rmdir_file",rmdir("/mnt/w/lower.TXT")==-20);
  ktest("fat.unlink_dir",unlink("/mnt/w/sub2x")==-21);
  /* ---- repertoire qui grandit : 120 fichiers a nom long ---- */
  mkdir("/mnt/w/many",0755);
  r=1;
  for(i=0;i<120;i++){
    mkname(nm,"/mnt/w/many/file_with_a_long_name_",i);
    if(put(nm,"x\n")!=2){r=0;break;}
  }
  ktest("fat.many_create",r);
  ktest("fat.many_count",countdir("/mnt/w/many",0,0)==122);
  r=1;
  for(i=0;i<120;i+=2){mkname(nm,"/mnt/w/many/file_with_a_long_name_",i);if(unlink(nm)!=0)r=0;}
  ktest("fat.many_unlink_half",r&&countdir("/mnt/w/many",0,0)==62);
  r=1;
  for(i=0;i<60;i++){mkname(nm,"/mnt/w/many/another_long_file_name_",i);if(put(nm,"y\n")!=2)r=0;}
  ktest("fat.many_refill",r&&countdir("/mnt/w/many",0,0)==122);
  r=1;
  for(i=1;i<120;i+=2){mkname(nm,"/mnt/w/many/file_with_a_long_name_",i);if(slurp(nm,b,sizeof b)!=2)r=0;}
  ktest("fat.many_still_there",r);
  /* ---- gros fichier + relecture apres demontage ---- */
  fd=open("/mnt/w/big2.bin",O_RDWR|O_CREAT|O_TRUNC,0644);
  ktest("fat.big_write",fillwrite(fd,700000,0,3000));
  close(fd);
  ktest("fat.big_readback",({int f=open("/mnt/w/big2.bin",O_RDONLY,0);int ok=isz("/mnt/w/big2.bin",700000)&&fillcheck(f,0,700000,0);close(f);ok;}));
  /* ---- attributs ---- */
  ktest("fat.chmod_ro",chmod("/mnt/w/short2.txt",0444)==-2&&put("/mnt/w/short2.txt","s\n")==2
        &&chmod("/mnt/w/short2.txt",0444)==0&&({stat64("/mnt/w/short2.txt",sb_);(ST_MODE(sb_)&0222)==0;}));
  ktest("fat.chmod_rw",chmod("/mnt/w/short2.txt",0644)==0&&({stat64("/mnt/w/short2.txt",sb_);(ST_MODE(sb_)&0200)!=0;}));
  { long tv[4]={1000000000,0,1000000000,0};
    ktest("fat.utimes",utimes("/mnt/w/short2.txt",tv)==0&&({stat64("/mnt/w/short2.txt",sb_);
        ST_MTIME(sb_)>=999999990&&ST_MTIME(sb_)<=1000000010;})); }
  ktest("fat.mtime_now",({stat64("/mnt/w/big2.bin",sb_);ST_MTIME(sb_)>1700000000;}));
  /* ---- demontage / remontage : tout doit etre relu depuis le disque ---- */
  ktest("fat.umount_busy",({int f=open("/mnt/w/big2.bin",O_RDONLY,0);int rr=umount("/mnt");close(f);rr==-16;}));
  ktest("fat.umount",umount("/mnt")==0);
  r=mount(dev,"/mnt","vfat",0,0);
  ktest("fat.remount_fs",r==0);
  ktest("fat.persist_big",({int f=open("/mnt/w/big2.bin",O_RDONLY,0);int ok=isz("/mnt/w/big2.bin",700000)&&fillcheck(f,0,700000,0);close(f);ok;}));
  ktest("fat.persist_names",hasname("/mnt/w","A Very Long File Name With Spaces.data")
        &&hasname("/mnt/w","MixedCase.Txt")&&hasname("/mnt/w","caf\xc3\xa9.txt")
        &&hasname("/mnt/w","now a much longer name.txt")&&hasname("/mnt/w/sub2x/sub1moved","in.txt"));
  ktest("fat.persist_many",countdir("/mnt/w/many",0,0)==122);
  ktest("fat.persist_orig",slurp("/mnt/dir1/f23.txt",b,sizeof b)==8&&({int f=open("/mnt/big.bin",O_RDONLY,0);int ok=fillcheck(f,0,300000,0);close(f);ok;}));
  /* ---- lecture seule ---- */
  ktest("fat.remount_ro",mount(dev,"/mnt","vfat",1|32,0)==0);
  ktest("fat.ro_write",open("/mnt/w/ro.txt",O_WRONLY|O_CREAT,0644)==-30&&mkdir("/mnt/w/rod",0755)==-30
        &&unlink("/mnt/w/lower.TXT")==-30);
  ktest("fat.ro_read",slurp("/mnt/hello.txt",b,sizeof b)==15);
  ktest("fat.remount_rw",mount(dev,"/mnt","vfat",32,0)==0&&put("/mnt/w/rw.txt","rw\n")==3);
  /* ---- nettoyage partiel : espace libere ---- */
  fc0=freeclus();
  unlink("/mnt/w/big2.bin");
  fc1=freeclus();
  ktest("fat.free_after_unlink",fc1>fc0+100);
  put("/mnt/final.txt","final\n");
  ktest("fat.umount_final",umount("/mnt")==0);
  puts("fat DONE\n");
  (void)c;
  return 0;
}
