/* modtest : modules du noyau (init_module/delete_module/finit_module, partie
   36) et /proc/sys (sysctl), /proc/swaps, /proc/modules, /proc/kallsyms.
   Les modules (hello.ko, hello2.ko, badinit.ko, unkmod.ko) sont compiles par
   lpc -3M (TESTS/K/*.pas) et embarques dans /bin. */
#include "ku.h"

#define SYS_init_module 128
#define SYS_delete_module 129
#define SYS_finit_module 350
#define SYS_uname 122
#define SYS_setuid 23
#define O_NONBLOCK 0x800

static char img[65536];
static char tmp[4096];

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
  int fd=open(p,O_WRONLY|O_TRUNC,0),n;
  if(fd<0)return fd;
  n=write(fd,s,strlen(s));
  close(fd);
  return n;
}
static int has(const char*hay,const char*needle){
  int l=strlen(needle),i;
  for(i=0;hay[i];i++)if(memcmp_(hay+i,needle,l)==0)return 1;
  return 0;
}
static int load(const char*path,const char*args){
  int n=slurp(path,img,sizeof img);
  if(n<=0)return -1000;
  return sc3(SYS_init_module,(long)img,n,(long)args);
}
static int rmmod(const char*name){return sc2(SYS_delete_module,(long)name,O_NONBLOCK);}
static int count_of(const char*name){
  /* utilisation (3e champ) du module name dans /proc/modules, -1 si absent */
  char b[2048];int n=slurp("/proc/modules",b,sizeof b),i,l=strlen(name);
  for(i=0;i<n;i++)
    if((i==0||b[i-1]=='\n')&&memcmp_(b+i,name,l)==0&&b[i+l]==' '){
      int j=i+l+1,v=0;
      while(b[j]!=' ')j++;
      j++;
      while(b[j]>='0'&&b[j]<='9')v=v*10+(b[j++]-'0');
      return v;}
  return -1;
}
static int stat64(const char*p,void*b){return sc2(SYS_stat64,(long)p,(long)b);}
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
static int sysint(const char*p){
  char b[64];int n=slurp(p,b,sizeof b),i,v=0,neg=0;
  if(n<=0)return -99999;
  i=0;if(b[0]=='-'){neg=1;i=1;}
  while(b[i]>='0'&&b[i]<='9')v=v*10+(b[i++]-'0');
  return neg?-v:v;
}

int main(void){
  int fd,r,i,n;
  char b[256];
  puts("  (modtest)\n");
  /* ---- erreurs de chargement ---- */
  ktest("mod.load_missing_dep",load("/bin/hello2.ko","")==-2);
  ktest("mod.load_unknown_symbol",load("/bin/unkmod.ko","")==-2);
  ktest("mod.load_badinit",load("/bin/badinit.ko","")==-5);
  ktest("mod.badinit_not_listed",count_of("badinit")==-1);
  memset(img,0x41,64);
  ktest("mod.load_garbage",sc3(SYS_init_module,(long)img,64,0)==-8);
  n=slurp("/bin/hello.ko",img,sizeof img);
  ktest("mod.load_truncated",sc3(SYS_init_module,(long)img,n/2,0)==-8);
  ktest("mod.load_len_zero",sc3(SYS_init_module,(long)img,0,0)==-8);
  ktest("mod.delete_unknown",rmmod("nexistepas")==-2);
  {
    int p=fork();
    if(p==0){
      sc1(SYS_setuid,1000);
      _exit(load("/bin/hello.ko","")==-1&&rmmod("hello")==-1?0:1);
    }
    {int st=0;waitpid(p,&st,0);ktest("mod.eperm_nonroot",st==0);}
  }
  /* ---- chargement de hello avec parametre ---- */
  ktest("mod.load_hello",load("/bin/hello.ko","count=7")==0);
  ktest("mod.listed",count_of("hello")==0);
  slurp("/proc/modules",tmp,sizeof tmp);
  ktest("mod.proc_modules",has(tmp,"hello ")&&has(tmp," Live 0x"));
  slurp("/proc/kallsyms",tmp,sizeof tmp);
  ktest("mod.kallsyms_kernel",has(tmp," T printk")&&has(tmp," T kmalloc"));
  ktest("mod.kallsyms_module",has(tmp," T hello_add\t[hello]")&&has(tmp," t init_module\t[hello]"));
  ktest("mod.dup_load",load("/bin/hello.ko","")==-17);
  ktest("mod.tainted",sysint("/proc/sys/kernel/tainted")==4096);
  /* ---- le peripherique du module ---- */
  unlink("/dev/hello");
  ktest("mod.mknod",mknod("/dev/hello",0020666,240<<8)==0);
  fd=open("/dev/hello",O_RDWR,0);
  ktest("mod.open",fd>=0);
  ktest("mod.refcount_open",count_of("hello")==1);
  ktest("mod.write",write(fd,"ping-module",10)==10);
  lseek(fd,0,0);
  n=read(fd,b,64);
  ktest("mod.read",n==10&&memcmp_(b,"ping-module",10)==0);
  {long v=0;
   ktest("mod.ioctl_writes",ioctl(fd,1,(long)&v)==0&&v==1);
   v=0;
   ktest("mod.param",ioctl(fd,2,(long)&v)==0&&v==7);
   ktest("mod.ioctl_enotty",ioctl(fd,99,(long)&v)==-25);}
  ktest("mod.rmmod_busy",rmmod("hello")==-11);
  {int fd2=dup(fd);close(fd);ktest("mod.dup_keeps_ref",count_of("hello")==1);close(fd2);}
  ktest("mod.refcount_closed",count_of("hello")==0);
  {long v=0;fd=open("/dev/hello",O_RDWR,0);ioctl(fd,3,(long)&v);close(fd);
   ktest("mod.open_release_counts",v>=2000+1);}
  /* ---- dependance entre modules ---- */
  ktest("mod.load_hello2",load("/bin/hello2.ko","")==0);
  slurp("/proc/modules",tmp,sizeof tmp);
  ktest("mod.dependents_listed",has(tmp,"hello2,")&&count_of("hello")==1);
  ktest("mod.rmmod_has_dependents",rmmod("hello")==-11);
  slurp("/proc/kallsyms",tmp,sizeof tmp);
  ktest("mod.kallsyms_hello2",has(tmp," T hello2_twice\t[hello2]"));
  ktest("mod.rmmod_hello2",rmmod("hello2")==0);
  ktest("mod.hello2_gone",count_of("hello2")==-1&&count_of("hello")==0);
  ktest("mod.rmmod_hello",rmmod("hello")==0);
  ktest("mod.rmmod_again",rmmod("hello")==-2);
  ktest("mod.open_after_unload",open("/dev/hello",O_RDWR,0)==-6);
  slurp("/proc/kallsyms",tmp,sizeof tmp);
  ktest("mod.kallsyms_cleaned",!has(tmp,"hello_add"));
  /* ---- finit_module ---- */
  fd=open("/bin/hello.ko",O_RDONLY,0);
  ktest("mod.finit",sc3(SYS_finit_module,fd,(long)"count=2",0)==0);
  ktest("mod.finit_bad_flags",sc3(SYS_finit_module,fd,0,0x100)==-22);
  ktest("mod.finit_badfd",sc3(SYS_finit_module,99,0,0)==-9);
  close(fd);
  fd=open("/dev/hello",O_RDWR,0);
  {long v=0;ioctl(fd,2,(long)&v);ktest("mod.finit_param",v==2);}
  close(fd);
  ktest("mod.rmmod_finit",rmmod("hello")==0);
  /* un module recharge apres dechargement */
  ktest("mod.reload",load("/bin/hello.ko","count=9")==0&&rmmod("hello")==0);

  /* ---- request_irq : IRQ 8 (horloge CMOS, 1024 Hz) comptee dans le module ---- */
  ktest("irq.load",load("/bin/irqmod.ko","")==0);
  unlink("/dev/irqmod");
  mknod("/dev/irqmod",0020666,241<<8);
  fd=open("/dev/irqmod",O_RDWR,0);
  {long c0=0,c1=0;long ts[2]={0,150000000};
   ioctl(fd,1,(long)&c0);
   nanosleep(ts,0);
   ioctl(fd,1,(long)&c1);
   ktest("irq.counting",fd>=0&&c1-c0>=20);}
  close(fd);
  ktest("irq.second_load_busy",load("/bin/irqmod.ko","")==-17);
  ktest("irq.unload",rmmod("irqmod")==0);
  ktest("irq.reload_after_free",load("/bin/irqmod.ko","")==0&&rmmod("irqmod")==0);

  /* ---- sysctl ---- */
  slurp("/proc/sys/kernel/ostype",b,sizeof b);
  ktest("sysctl.ostype",strcmp(b,"LINUX-0\n")==0);
  n=slurp("/proc/sys/kernel/osrelease",b,sizeof b);
  ktest("sysctl.osrelease",n>1);
  ktest("sysctl.hostname_default",slurp("/proc/sys/kernel/hostname",b,sizeof b)>1);
  ktest("sysctl.hostname_write",put("/proc/sys/kernel/hostname","k32host\n")==8);
  slurp("/proc/sys/kernel/hostname",b,sizeof b);
  {char u[390];sc1(SYS_uname,(long)u);
   ktest("sysctl.hostname_uname",strcmp(b,"k32host\n")==0&&strcmp(u+65,"k32host")==0);}
  ktest("sysctl.hostname_empty_einval",put("/proc/sys/kernel/hostname","\n")==-22);
  ktest("sysctl.pid_max_default",sysint("/proc/sys/kernel/pid_max")==32768);
  ktest("sysctl.pid_max_write",put("/proc/sys/kernel/pid_max","400\n")>0&&sysint("/proc/sys/kernel/pid_max")==400);
  {int p=fork();if(p==0)_exit(getpid()<400?0:1);
   {int st=0;waitpid(p,&st,0);ktest("sysctl.pid_max_applied",st==0);}}
  ktest("sysctl.pid_max_range",put("/proc/sys/kernel/pid_max","100")==-22&&put("/proc/sys/kernel/pid_max","99999999")==-22);
  ktest("sysctl.pid_max_text",put("/proc/sys/kernel/pid_max","abc")==-22&&put("/proc/sys/kernel/pid_max","12x")==-22);
  put("/proc/sys/kernel/pid_max","32768");
  ktest("sysctl.pid_max_restored",sysint("/proc/sys/kernel/pid_max")==32768);
  ktest("sysctl.readonly_refused",put("/proc/sys/kernel/ostype","x")<0);
  ktest("sysctl.randomize",put("/proc/sys/kernel/randomize_va_space","1")>0&&sysint("/proc/sys/kernel/randomize_va_space")==1);
  put("/proc/sys/kernel/randomize_va_space","0");
  ktest("sysctl.swappiness",put("/proc/sys/vm/swappiness","10")>0&&sysint("/proc/sys/vm/swappiness")==10);
  put("/proc/sys/vm/swappiness","60");
  ktest("sysctl.overcommit",put("/proc/sys/vm/overcommit_memory","2")>0&&sysint("/proc/sys/vm/overcommit_memory")==2);
  put("/proc/sys/vm/overcommit_memory","0");
  ktest("sysctl.ip_forward",put("/proc/sys/net/ipv4/ip_forward","1")>0&&sysint("/proc/sys/net/ipv4/ip_forward")==1);
  put("/proc/sys/net/ipv4/ip_forward","0");
  ktest("sysctl.ip_ttl",sysint("/proc/sys/net/ipv4/ip_default_ttl")==64&&put("/proc/sys/net/ipv4/ip_default_ttl","0")==-22);
  ktest("sysctl.port_range",has((slurp("/proc/sys/net/ipv4/ip_local_port_range",b,sizeof b),b),"32768\t60999"));
  ktest("sysctl.drop_caches",put("/proc/sys/vm/drop_caches","3")>0&&put("/proc/sys/vm/drop_caches","9")==-22);
  ktest("sysctl.uuid_changes",({char a[64],c[64];slurp("/proc/sys/kernel/random/uuid",a,64);slurp("/proc/sys/kernel/random/uuid",c,64);strlen(a)==37&&strcmp(a,c)!=0;}));
  ktest("sysctl.boot_id_stable",({char a[64],c[64];slurp("/proc/sys/kernel/random/boot_id",a,64);slurp("/proc/sys/kernel/random/boot_id",c,64);strlen(a)==37&&strcmp(a,c)==0;}));
  /* fs.file-max : applique par le noyau */
  {
    char f[64];int nr,k,fds[8],opened=0;
    slurp("/proc/sys/fs/file-nr",f,sizeof f);
    nr=0;for(i=0;f[i]>='0'&&f[i]<='9';i++)nr=nr*10+(f[i]-'0');
    ktest("sysctl.file_nr",nr>0&&has(f,"\t0\t"));
    {char v[16];int q=0,t=nr+3;char d[12];int dl=0;
     if(t==0)d[dl++]='0';while(t){d[dl++]='0'+t%10;t/=10;}
     while(dl)v[q++]=d[--dl];v[q]=0;
     put("/proc/sys/fs/file-max",v);}
    for(k=0;k<8;k++){fds[k]=open("/dev/null",O_RDONLY,0);if(fds[k]>=0)opened++;}
    ktest("sysctl.file_max_enfile",opened>=1&&opened<8&&fds[7]==-23);
    for(k=0;k<8;k++)if(fds[k]>=0)close(fds[k]);
    put("/proc/sys/fs/file-max","65536");
    ktest("sysctl.file_max_restored",sysint("/proc/sys/fs/file-max")==65536&&open("/dev/null",O_RDONLY,0)>=0);
  }
  /* parcours de /proc/sys */
  ktest("sysctl.readdir_top",hasname("/proc/sys","kernel")&&hasname("/proc/sys","vm")&&hasname("/proc/sys","net")&&hasname("/proc/sys","fs"));
  ktest("sysctl.readdir_sub",hasname("/proc/sys/kernel","hostname")&&hasname("/proc/sys/kernel/random","uuid")&&hasname("/proc/sys/net/ipv4","ip_forward")&&hasname("/proc/sys/fs/inotify","max_user_watches"));
  ktest("sysctl.proc_toplevel",hasname("/proc","sys")&&hasname("/proc","swaps")&&hasname("/proc","modules")&&hasname("/proc","kallsyms"));
  ktest("sysctl.enoent",open("/proc/sys/kernel/inexistant",O_RDONLY,0)==-2&&open("/proc/sys/inexistant/x",O_RDONLY,0)==-2);
  ktest("sysctl.stat_dir",({unsigned char s[96];stat64("/proc/sys/kernel",s)==0&&((*(unsigned*)(s+16))&0xF000)==0x4000;}));
  ktest("sysctl.write_nonroot",({int p=fork();int ok=0;if(p==0){sc1(SYS_setuid,1000);_exit(open("/proc/sys/kernel/hostname",O_WRONLY,0)<0?0:1);}{int st=0;waitpid(p,&st,0);ok=st==0;}ok;}));
  /* /proc/swaps : en-tete */
  slurp("/proc/swaps",tmp,sizeof tmp);
  ktest("swaps.header",has(tmp,"Filename")&&has(tmp,"Priority"));
  /* modules_disabled : verrou irreversible, en dernier */
  put("/proc/sys/kernel/hostname","linux0\n");
  ktest("sysctl.modules_disabled",put("/proc/sys/kernel/modules_disabled","1")>0&&sysint("/proc/sys/kernel/modules_disabled")==1);
  ktest("sysctl.modules_disabled_irreversible",put("/proc/sys/kernel/modules_disabled","0")==-1);
  ktest("mod.disabled_init",load("/bin/hello.ko","")==-1);
  ktest("mod.disabled_delete",rmmod("hello")==-1);
  puts("KTEST: mod DONE\n");
  (void)r;
  return ku_fail?1:0;
}
