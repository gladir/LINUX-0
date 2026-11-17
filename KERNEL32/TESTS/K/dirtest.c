/* dirtest : systeme de fichiers (tmpfs) : creation, lecture, repertoires, liens */
#include "ku.h"
struct stat64 { unsigned long long st_dev; unsigned char pad0[4]; unsigned long st_ino; unsigned int st_mode,st_nlink,st_uid,st_gid;
  unsigned long long st_rdev; unsigned char pad3[4]; long long st_size; unsigned long st_blksize; unsigned long long st_blocks;
  unsigned long at,atn,mt,mtn,ct,ctn; unsigned long long ino; };
struct dirent64 { unsigned long long ino,off; unsigned short len; unsigned char type; char name[1]; };
static int has_entry(const char*dir,const char*name){
  char buf[1024];int fd=open(dir,O_RDONLY|O_DIRECTORY,0),n,found=0;
  if(fd<0)return -1;
  while((n=getdents64(fd,buf,sizeof buf))>0){int o=0;while(o<n){struct dirent64*d=(void*)(buf+o);if(strcmp(d->name,name)==0)found=1;o+=d->len;}}
  close(fd);return found;
}
int main(void){
  char b[300];int fd,n,i;struct stat64 st;
  ktest("mkdir",mkdir("/tmp/d1",0755)==0);
  ktest("mkdir.exist",mkdir("/tmp/d1",0755)==-17);
  fd=open("/tmp/d1/f.txt",O_CREAT|O_RDWR|O_TRUNC,0644);
  ktest("creat",fd>=0);
  ktest("write",write(fd,"0123456789",10)==10);
  ktest("lseek",lseek(fd,3,0)==3);
  n=read(fd,b,4);b[n>0?n:0]=0;
  ktest("read",n==4&&strcmp(b,"3456")==0);
  close(fd);
  ktest("stat64",sc2(SYS_stat64,(long)"/tmp/d1/f.txt",(long)&st)==0&&st.st_size==10&&(st.st_mode&0xf000)==0x8000&&(st.st_mode&0777)==0644);
  fd=open("/tmp/big",O_CREAT|O_RDWR,0600);
  for(i=0;i<300;i++){memset(b,i&0xff,sizeof b);write(fd,b,sizeof b);}
  lseek(fd,0,0);int ok=1;
  for(i=0;i<300;i++){n=read(fd,b,sizeof b);if(n!=sizeof b||b[0]!=(char)i||b[299]!=(char)i)ok=0;}
  ktest("bigfile",ok);
  ktest("ftruncate",sc2(SYS_ftruncate,fd,100)==0);
  sc2(SYS_fstat64,fd,(long)&st);
  ktest("ftruncate.size",st.st_size==100);
  close(fd);unlink("/tmp/big");
  ktest("getdents",has_entry("/tmp/d1","f.txt")==1&&has_entry("/tmp/d1",".")==1&&has_entry("/tmp/d1","..")==1);
  ktest("rename",rename("/tmp/d1/f.txt","/tmp/d1/g.txt")==0&&has_entry("/tmp/d1","g.txt")==1&&has_entry("/tmp/d1","f.txt")==0);
  ktest("link",link("/tmp/d1/g.txt","/tmp/d1/h.txt")==0);
  sc2(SYS_stat64,(long)"/tmp/d1/h.txt",(long)&st);
  ktest("link.nlink",st.st_nlink==2);
  ktest("unlink",unlink("/tmp/d1/g.txt")==0&&access("/tmp/d1/h.txt",0)==0);
  ktest("symlink",symlink("h.txt","/tmp/d1/s")==0);
  n=readlink("/tmp/d1/s",b,sizeof b);if(n>0)b[n]=0;
  ktest("readlink",n==5&&strcmp(b,"h.txt")==0);
  fd=open("/tmp/d1/s",O_RDONLY,0);
  n=read(fd,b,10);b[n>0?n:0]=0;close(fd);
  ktest("symlink.follow",n==10&&strcmp(b,"0123456789")==0);
  sc2(SYS_lstat64,(long)"/tmp/d1/s",(long)&st);
  ktest("lstat.symlink",(st.st_mode&0xf000)==0xa000);
  ktest("rmdir.notempty",rmdir("/tmp/d1")==-39);
  unlink("/tmp/d1/h.txt");unlink("/tmp/d1/s");
  ktest("rmdir",rmdir("/tmp/d1")==0&&access("/tmp/d1",0)==-2);
  mkdir("/tmp/cw",0755);chdir("/tmp/cw");
  n=getcwd(b,sizeof b);
  ktest("getcwd",n==8&&strcmp(b,"/tmp/cw")==0);
  fd=open("rel.txt",O_CREAT|O_WRONLY,0600);close(fd);
  ktest("relative",access("/tmp/cw/rel.txt",0)==0);
  chdir("/");unlink("/tmp/cw/rel.txt");rmdir("/tmp/cw");
  mkdir("/tmp/a",0755);mkdir("/tmp/a/b",0755);
  ktest("dotdot",access("/tmp/a/b/../../a/./b",0)==0);
  rmdir("/tmp/a/b");rmdir("/tmp/a");
  fd=open("/dev/zero",O_RDONLY,0);memset(b,1,16);n=read(fd,b,16);close(fd);
  ktest("dev.zero",n==16&&b[0]==0&&b[15]==0);
  fd=open("/dev/null",O_WRONLY,0);ktest("dev.null",write(fd,"abc",3)==3);close(fd);
  fd=open("/dev/urandom",O_RDONLY,0);n=read(fd,b,16);close(fd);ktest("dev.urandom",n==16);
  ktest("dev.nodes",has_entry("/dev","console")==1&&has_entry("/dev","tty1")==1&&has_entry("/dev","ttyS0")==1);
  fd=open("/tmp/perm",O_CREAT|O_WRONLY,0000);close(fd);
  ktest("perm.root_open",open("/tmp/perm",O_RDONLY,0)>=0);
  int p=fork();
  if(p==0){sc1(SYS_setuid,1000);_exit(open("/tmp/perm",O_RDONLY,0)==-13?0:1);}
  int stt;waitpid(p,&stt,0);
  ktest("perm.user_denied",stt==0);
  unlink("/tmp/perm");
  ktest("enoent",open("/nonexistent",O_RDONLY,0)==-2);
  ktest("enotdir",open("/bin/hello/x",O_RDONLY,0)==-20);
  ktest("eisdir",open("/tmp",O_WRONLY,0)==-21);
  return ku_fail?1:0;
}
