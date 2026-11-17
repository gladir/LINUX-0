/* mounttest : bind mounts, remontage, MS_MOVE, umount2, pivot_root (tmpfs) */
#include "ku.h"
static int rd(const char*p,char*b,int n){int fd=open(p,O_RDONLY,0),r;if(fd<0)return fd;r=read(fd,b,n-1);if(r<0)r=0;b[r]=0;close(fd);return r;}
static int put(const char*p,const char*s){int fd=open(p,O_WRONLY|O_CREAT|O_TRUNC,0644),n;if(fd<0)return fd;n=write(fd,s,strlen(s));close(fd);return n;}
#define MS_RDONLY 1
#define MS_REMOUNT 32
#define MS_BIND 4096
#define MS_MOVE 8192
int main(void){
  char b[64];int r,st,p;
  mkdir("/tmp/b1",0755);mkdir("/tmp/b2",0755);mkdir("/tmp/m1",0755);mkdir("/tmp/m2",0755);
  put("/tmp/b1/f","X");
  ktest("mount.bind",mount("/tmp/b1","/tmp/b2","none",MS_BIND,0)==0);
  r=rd("/tmp/b2/f",b,64);
  ktest("mount.bind_read",r==1&&b[0]=='X');
  put("/tmp/b2/g","Y");r=rd("/tmp/b1/g",b,64);
  ktest("mount.bind_write",r==1&&b[0]=='Y');
  unlink("/tmp/b1/g");
  ktest("mount.bind_unlink_alias",access("/tmp/b2/g",0)==-2);
  mkdir("/tmp/b2/d",0755);
  ktest("mount.bind_mkdir",access("/tmp/b1/d",0)==0);
  chdir("/tmp/b2/d");chdir("..");chdir("..");getcwd(b,64);chdir("/");
  ktest("mount.bind_dotdot",strcmp(b,"/tmp")==0);
  chdir("/tmp/b2");
  ktest("mount.bind_busy",umount("/tmp/b2")==-16);
  chdir("/");
  ktest("mount.bind_umount",umount("/tmp/b2")==0&&access("/tmp/b2/f",0)==-2);
  /* remontage lecture seule d'un tmpfs */
  ktest("mount.tmpfs",mount("none","/tmp/m1","tmpfs",0,0)==0);
  ktest("mount.write_rw",put("/tmp/m1/a","1")==1);
  ktest("mount.remount_ro",mount("none","/tmp/m1","tmpfs",MS_REMOUNT|MS_RDONLY,0)==0);
  ktest("mount.ro_create",open("/tmp/m1/b",O_WRONLY|O_CREAT,0644)==-30);
  ktest("mount.remount_rw",mount("none","/tmp/m1","tmpfs",MS_REMOUNT,0)==0&&put("/tmp/m1/b","2")==1);
  /* deplacement */
  ktest("mount.move",mount("/tmp/m1","/tmp/m2","none",MS_MOVE,0)==0);
  r=rd("/tmp/m2/a",b,64);
  ktest("mount.move_content",r==1&&b[0]=='1'&&access("/tmp/m1/a",0)==-2);
  ktest("mount.umount_flag",sc2(52,(long)"/tmp/m2",2)==0&&access("/tmp/m2/a",0)==-2);
  /* pivot_root dans un fils (sa racine change, pas celle du banc) */
  p=fork();
  if(p==0){
    mkdir("/tmp/nr",0755);
    if(mount("none","/tmp/nr","tmpfs",0,0)!=0)_exit(10);
    mkdir("/tmp/nr/old",0755);mkdir("/tmp/nr/bin",0755);put("/tmp/nr/bin/x","N");
    chdir("/tmp/nr");
    if(sc2(217,(long)".",(long)"old")!=0)_exit(11);
    if(access("/bin/x",0)!=0)_exit(12);
    if(access("/old/bin/hello",0)!=0&&access("/old/sbin/init",0)!=0)_exit(13);
    if(access("/old/tmp/nr",0)!=0)_exit(14);
    mkdir("/old/tmp/back",0755);
    if(sc2(217,(long)"/old",(long)"/old/tmp/back")!=0)_exit(15);
    if(access("/tmp/b1",0)!=0)_exit(16);
    if(access("/tmp/back/bin/x",0)!=0)_exit(17);
    _exit(0);
  }
  waitpid(p,&st,0);
  ktest("mount.pivot_root",(st>>8)==0);
  ktest("mount.pivot_einval",sc2(217,(long)"/tmp",(long)"/tmp")==-22);
  return ku_fail?1:0;
}
