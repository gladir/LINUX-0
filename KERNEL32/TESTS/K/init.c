/* init : lance la suite de tests (banc d'essai) puis un petit interpreteur de
   commandes sur /dev/console. */
#include "ku.h"
static const char*tests[]={"/bin/hello","/bin/forkwait","/bin/pipetest","/bin/sigtest","/bin/mmaptest","/bin/dirtest","/bin/ttytest","/bin/schedtest","/bin/blktest","/bin/misctest","/bin/proctest","/bin/stress",0};
static int run(const char*prog,char*const argv[]){
  int p=fork(),st;
  if(p==0){char*e[]={"PATH=/bin:/sbin:/usr/bin","HOME=/root","TERM=linux",0};execve(prog,argv,e);puts_fd(2,"execve: ");puts_fd(2,prog);puts_fd(2," : echec\n");_exit(127);}
  if(p<0)return -1;
  waitpid(p,&st,0);
  return st;
}
static int split(char*l,char**v){int n=0;while(*l){while(*l==' ')*l++=0;if(*l){v[n++]=l;while(*l&&*l!=' ')l++;}}v[n]=0;return n;}
static void ls(const char*d){char buf[1024];int fd=open(d,O_RDONLY|O_DIRECTORY,0),n;
  if(fd<0){puts("ls: erreur\n");return;}
  while((n=getdents64(fd,buf,sizeof buf))>0){int o=0;while(o<n){struct{unsigned long long i,o;unsigned short l;unsigned char t;char nm[1];}*e=(void*)(buf+o);puts(e->nm);puts(e->t==4?"/\n":"\n");o+=e->l;}}
  close(fd);}
static void cat(const char*f){char b[512];int fd=open(f,O_RDONLY,0),n;if(fd<0){puts("cat: erreur\n");return;}while((n=read(fd,b,sizeof b))>0)write(1,b,n);close(fd);}
int main(int argc,char**argv){
  int i,total=0,bad=0;char line[256];char*v[32];
  if(getpid()!=1){puts("init: doit etre le processus 1\n");return 1;}
  setsid();
  puts("\n=== LINUX-0 KERNEL32 : init (banc d'essai) ===\n");
  for(i=0;tests[i];i++){
    char*a[]={(char*)tests[i],0};
    int st=run(tests[i],a);
    total++;
    puts("KPROG: ");puts(tests[i]);
    if(st==0)puts(" OK\n");else{bad++;puts(" FAIL status=");putd(st);puts("\n");}
  }
  puts("KTEST: DONE progs=");putd(total);puts(" fail=");putd(bad);puts("\n");
  if(argc>1&&strcmp(argv[1],"poweroff")==0){sync();reboot_off();}
  puts("Interpreteur de commandes (halt pour arreter) :\n");
  for(;;){
    puts("# ");
    int n=read(0,line,sizeof line-1);
    if(n<=0){if(n==0)break;continue;}
    line[n]=0;if(n>0&&line[n-1]=='\n')line[n-1]=0;
    int c=split(line,v);if(c==0)continue;
    if(strcmp(v[0],"halt")==0||strcmp(v[0],"poweroff")==0){sync();reboot_off();}
    else if(strcmp(v[0],"exit")==0)break;
    else if(strcmp(v[0],"cd")==0){if(c>1&&chdir(v[1])<0)puts("cd: erreur\n");}
    else if(strcmp(v[0],"pwd")==0){char b[200];getcwd(b,sizeof b);puts(b);puts("\n");}
    else if(strcmp(v[0],"ls")==0)ls(c>1?v[1]:".");
    else if(strcmp(v[0],"cat")==0&&c>1)cat(v[1]);
    else if(strcmp(v[0],"echo")==0){for(i=1;i<c;i++){puts(v[i]);puts(i+1<c?" ":"");}puts("\n");}
    else if(strcmp(v[0],"mkdir")==0&&c>1){if(mkdir(v[1],0755)<0)puts("mkdir: erreur\n");}
    else if(strcmp(v[0],"rm")==0&&c>1){if(unlink(v[1])<0)puts("rm: erreur\n");}
    else{int st=run(v[0],v);if(st!=0){puts("[statut ");putd(st);puts("]\n");}}
  }
  return 0;
}
