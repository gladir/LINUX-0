/* xattrtest : attributs etendus (user./trusted./security.), appels
   setxattr/getxattr/listxattr/removexattr et leurs variantes l* et f*, ACL
   POSIX (system.posix_acl_access / default) : verification des droits,
   chmod et heritage a la creation. Usage : xattrtest [repertoire] (defaut :
   /xa sur le tmpfs racine ; ext2test l'execute sur /mnt/xa). */
#include "ku.h"
#define SYS_setxattr 226
#define SYS_lsetxattr 227
#define SYS_fsetxattr 228
#define SYS_getxattr 229
#define SYS_lgetxattr 230
#define SYS_fgetxattr 231
#define SYS_listxattr 232
#define SYS_llistxattr 233
#define SYS_flistxattr 234
#define SYS_removexattr 235
#define SYS_lremovexattr 236
#define SYS_fremovexattr 237
#define SYS_stat64 195
#define XCREATE 1
#define XREPLACE 2
static long setx(const char*p,const char*n,const void*v,long s,int f){return sc5(SYS_setxattr,(long)p,(long)n,(long)v,s,f);}
static long getx(const char*p,const char*n,void*v,long s){return sc4(SYS_getxattr,(long)p,(long)n,(long)v,s);}
static long listx(const char*p,void*v,long s){return sc3(SYS_listxattr,(long)p,(long)v,s);}
static long remx(const char*p,const char*n){return sc2(SYS_removexattr,(long)p,(long)n);}
static long fsetx(int fd,const char*n,const void*v,long s,int f){return sc5(SYS_fsetxattr,fd,(long)n,(long)v,s,f);}
static long fgetx(int fd,const char*n,void*v,long s){return sc4(SYS_fgetxattr,fd,(long)n,(long)v,s);}
static long flistx(int fd,void*v,long s){return sc3(SYS_flistxattr,fd,(long)v,s);}
static long fremx(int fd,const char*n){return sc2(SYS_fremovexattr,fd,(long)n);}
static long lsetx(const char*p,const char*n,const void*v,long s,int f){return sc5(SYS_lsetxattr,(long)p,(long)n,(long)v,s,f);}
static long lgetx(const char*p,const char*n,void*v,long s){return sc4(SYS_lgetxattr,(long)p,(long)n,(long)v,s);}
static int stmode(const char*p){unsigned char b[144];if(sc2(SYS_stat64,(long)p,(long)b)<0)return -1;return *(unsigned*)(b+16)&07777;}
static void cat3(char*d,const char*a,const char*b,const char*c){char*o=d;while(*a)*o++=*a++;while(*b)*o++=*b++;while(*c)*o++=*c++;*o=0;}

struct ae{unsigned short tag,perm;unsigned id;};
struct acl{unsigned ver;struct ae e[8];};
static long acl_len(int n){return 4+8*n;}
static void ace(struct acl*a,int i,int tag,int perm,unsigned id){a->e[i].tag=tag;a->e[i].perm=perm;a->e[i].id=id;}
#define UO 1
#define UU 2
#define GO 4
#define GG 8
#define MK 0x10
#define OT 0x20
#define NOID 0xffffffffu

static int try_open(const char*p,int fl,int uid){
  int pid=fork(),st;
  if(pid==0){sc1(46,uid);if(sc1(SYS_setuid,uid)!=0)_exit(100);{int r=open(p,fl,0);_exit(r>=0?0:(-r));}}
  waitpid(pid,&st,0);
  return (st>>8)&0xff;
}

int main(int argc,char**argv){
  const char*dir=argc>1?argv[1]:"/xa";
  char f[128],f2[128],ln[128],d1[128],nf[128],nd[128];
  char buf[4096],big[2048];int fd,i;long r;
  umask(022);
  mkdir(dir,0777);
  cat3(f,dir,"/f","");cat3(f2,dir,"/f2","");cat3(ln,dir,"/ln","");cat3(d1,dir,"/d1","");
  fd=open(f,O_CREAT|O_RDWR,0644);close(fd);
  /* ---- base ---- */
  ktest("xattr.set",setx(f,"user.a","hello",5,0)==0);
  memset(buf,0,sizeof buf);
  ktest("xattr.get",getx(f,"user.a",buf,sizeof buf)==5&&memcmp_(buf,"hello",5)==0);
  ktest("xattr.get_size_query",getx(f,"user.a",0,0)==5);
  ktest("xattr.get_erange",getx(f,"user.a",buf,2)==-34);
  ktest("xattr.get_enodata",getx(f,"user.zzz",buf,sizeof buf)==-61);
  ktest("xattr.create_eexist",setx(f,"user.a","x",1,XCREATE)==-17);
  ktest("xattr.replace_enodata",setx(f,"user.nope","x",1,XREPLACE)==-61);
  ktest("xattr.replace_ok",setx(f,"user.a","HELLO!",6,XREPLACE)==0&&getx(f,"user.a",buf,sizeof buf)==6&&memcmp_(buf,"HELLO!",6)==0);
  ktest("xattr.eopnotsupp",setx(f,"foo.bar","x",1,0)==-95&&getx(f,"nosuch.x",buf,10)==-95);
  ktest("xattr.empty_value",setx(f,"user.empty","",0,0)==0&&getx(f,"user.empty",buf,sizeof buf)==0);
  ktest("xattr.set_bad_flags",setx(f,"user.a","x",1,8)==-22);
  /* ---- liste ---- */
  ktest("xattr.set_more",setx(f,"user.b","B",1,0)==0&&setx(f,"security.sel","S",1,0)==0&&setx(f,"trusted.t","T",1,0)==0);
  { long n=listx(f,0,0);
    memset(buf,0,sizeof buf);
    ktest("xattr.list_size",n>0);
    r=listx(f,buf,sizeof buf);
    { int found_a=0,found_b=0,found_s=0,found_t=0,found_e=0;char*p=buf;
      while(p<buf+r){if(!strcmp(p,"user.a"))found_a=1;if(!strcmp(p,"user.b"))found_b=1;if(!strcmp(p,"security.sel"))found_s=1;if(!strcmp(p,"trusted.t"))found_t=1;if(!strcmp(p,"user.empty"))found_e=1;p+=strlen(p)+1;}
      ktest("xattr.list_names",r==n&&found_a&&found_b&&found_s&&found_t&&found_e); }
    ktest("xattr.list_erange",listx(f,buf,3)==-34); }
  /* ---- suppression ---- */
  ktest("xattr.remove",remx(f,"user.b")==0&&getx(f,"user.b",buf,10)==-61);
  ktest("xattr.remove_enodata",remx(f,"user.b")==-61);
  /* ---- variantes fd et lien symbolique ---- */
  fd=open(f,O_RDWR,0);
  ktest("xattr.fset_fget",fsetx(fd,"user.fd","FD",2,0)==0&&fgetx(fd,"user.fd",buf,10)==2&&buf[0]=='F');
  ktest("xattr.flist",flistx(fd,0,0)>0);
  ktest("xattr.fremove",fremx(fd,"user.fd")==0&&fgetx(fd,"user.fd",buf,10)==-61);
  close(fd);
  symlink("f",ln);
  ktest("xattr.symlink_user_eperm",lsetx(ln,"user.a","x",1,0)==-1&&lgetx(ln,"user.a",buf,10)==-61);
  ktest("xattr.symlink_security",lsetx(ln,"security.k","K",1,0)==0&&lgetx(ln,"security.k",buf,10)==1&&getx(ln,"user.a",buf,10)==6);
  /* ---- droits d'un utilisateur ordinaire ---- */
  { int pid=fork(),st;
    if(pid==0){
      int ok=1;
      sc1(46,1000);sc1(SYS_setuid,1000);
      if(getx(f,"user.a",buf,10)!=6)ok=0;                 /* 0644 : lecture permise */
      if(setx(f,"user.u","x",1,0)!=-13)ok=0;              /* ecriture : EACCES */
      if(getx(f,"trusted.t",buf,10)!=-61)ok=0;            /* trusted. invisible */
      if(setx(f,"trusted.u","x",1,0)!=-1)ok=0;            /* trusted. : EPERM */
      { long n=listx(f,buf,sizeof buf);char*p=buf;int tr=0;while(p<buf+n){if(!memcmp_(p,"trusted.",8))tr=1;p+=strlen(p)+1;}if(tr)ok=0; }
      _exit(ok?0:1);
    }
    waitpid(pid,&st,0);
    ktest("xattr.permissions_user",((st>>8)&0xff)==0); }
  /* ---- gros attribut ---- */
  for(i=0;i<600;i++)big[i]=(char)('a'+i%26);
  ktest("xattr.value_600",setx(f,"user.big",big,600,0)==0&&getx(f,"user.big",buf,sizeof buf)==600&&memcmp_(buf,big,600)==0);
  ktest("xattr.value_too_big",setx(f,"user.huge",buf,70000,0)==-7);
  /* ---- vie d'un inode : la suppression efface les attributs ---- */
  fd=open(f2,O_CREAT|O_RDWR,0644);close(fd);
  setx(f2,"user.x","1",1,0);
  unlink(f2);
  fd=open(f2,O_CREAT|O_RDWR,0644);close(fd);
  ktest("xattr.unlink_clears",listx(f2,0,0)==0);
  /* lien dur : memes attributs */
  { char hl[128];cat3(hl,dir,"/hl","");link(f,hl);
    ktest("xattr.hardlink_shared",getx(hl,"user.a",buf,10)==6);unlink(hl); }
  /* ---- ACL d'acces ---- */
  { struct acl a;int m;
    chmod(f,0640);
    ace(&a,0,UO,6,NOID);ace(&a,1,UU,4,1001);ace(&a,2,GO,0,NOID);ace(&a,3,MK,4,NOID);ace(&a,4,OT,0,NOID);a.ver=2;
    ktest("acl.set_access",setx(f,"system.posix_acl_access",&a,acl_len(5),0)==0);
    ktest("acl.mode_from_mask",stmode(f)==0640);
    memset(buf,0,sizeof buf);
    ktest("acl.get_access",getx(f,"system.posix_acl_access",buf,sizeof buf)==acl_len(5)&&memcmp_(buf,&a,acl_len(5))==0);
    ktest("acl.user_read_allowed",try_open(f,O_RDONLY,1001)==0);
    ktest("acl.user_write_denied",try_open(f,O_WRONLY,1001)==13);
    ktest("acl.other_denied",try_open(f,O_RDONLY,1002)==13);
    a.e[1].perm=6;a.e[3].perm=6;
    ktest("acl.update",setx(f,"system.posix_acl_access",&a,acl_len(5),0)==0&&stmode(f)==0660);
    ktest("acl.user_write_allowed",try_open(f,O_WRONLY,1001)==0);
    chmod(f,0640);
    memset(buf,0,sizeof buf);m=getx(f,"system.posix_acl_access",buf,sizeof buf);
    ktest("acl.chmod_updates_mask",m==acl_len(5)&&((struct acl*)buf)->e[3].perm==4&&try_open(f,O_WRONLY,1001)==13);
    { struct acl bad;memcpy(&bad,&a,sizeof a);bad.ver=1;
      ktest("acl.bad_version",setx(f,"system.posix_acl_access",&bad,acl_len(5),0)==-22);
      memcpy(&bad,&a,sizeof a);ace(&bad,1,GO,4,NOID);ace(&bad,2,UU,4,1001);
      ktest("acl.bad_order",setx(f,"system.posix_acl_access",&bad,acl_len(5),0)==-22);
      memcpy(&bad,&a,sizeof a);ace(&bad,3,OT,0,NOID);
      ktest("acl.bad_nomask",setx(f,"system.posix_acl_access",&bad,acl_len(4),0)==-22); }
    { struct acl mn;mn.ver=2;ace(&mn,0,UO,7,NOID);ace(&mn,1,GO,5,NOID);ace(&mn,2,OT,0,NOID);
      ktest("acl.minimal_is_mode",setx(f,"system.posix_acl_access",&mn,acl_len(3),0)==0&&stmode(f)==0750&&getx(f,"system.posix_acl_access",buf,sizeof buf)==-61); }
    ktest("acl.remove_when_absent",remx(f,"system.posix_acl_access")==-61);
  }
  /* ---- ACL par defaut et heritage ---- */
  mkdir(d1,0755);
  { struct acl a;int m;
    ace(&a,0,UO,7,NOID);ace(&a,1,UU,6,1001);ace(&a,2,GO,5,NOID);ace(&a,3,MK,6,NOID);ace(&a,4,OT,0,NOID);a.ver=2;
    ktest("acl.default_on_file_eacces",setx(f,"system.posix_acl_default",&a,acl_len(5),0)==-13);
    ktest("acl.set_default",setx(d1,"system.posix_acl_default",&a,acl_len(5),0)==0);
    memset(buf,0,sizeof buf);
    ktest("acl.get_default",getx(d1,"system.posix_acl_default",buf,sizeof buf)==acl_len(5)&&memcmp_(buf,&a,acl_len(5))==0);
    cat3(nf,d1,"/newf","");cat3(nd,d1,"/newd","");
    fd=open(nf,O_CREAT|O_RDWR,0666);close(fd);
    ktest("acl.inherit_mode_no_umask",stmode(nf)==0660);
    memset(buf,0,sizeof buf);m=getx(nf,"system.posix_acl_access",buf,sizeof buf);
    ktest("acl.inherit_access_acl",m==acl_len(5)&&((struct acl*)buf)->e[1].id==1001&&((struct acl*)buf)->e[3].perm==6);
    mkdir(nd,0777);
    memset(buf,0,sizeof buf);
    ktest("acl.inherit_dir_default",getx(nd,"system.posix_acl_default",buf,sizeof buf)==acl_len(5));
    ktest("acl.inherit_dir_mode",stmode(nd)==0760);
    ktest("acl.inherited_perm_user",try_open(nf,O_RDWR,1001)==0&&try_open(nf,O_RDONLY,1002)==13);
    ktest("acl.remove_default",remx(d1,"system.posix_acl_default")==0&&getx(d1,"system.posix_acl_default",buf,sizeof buf)==-61);
    { char nf2[128];cat3(nf2,d1,"/newf2","");fd=open(nf2,O_CREAT|O_RDWR,0666);close(fd);
      ktest("acl.no_default_umask_applies",stmode(nf2)==0644);unlink(nf2); }
    unlink(nf);
    { char sub[128];cat3(sub,nd,"/x","");unlink(sub);}
  }
  puts("xattr DONE\n");
  return ku_fail?1:0;
}
