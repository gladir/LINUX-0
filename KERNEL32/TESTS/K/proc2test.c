/* proc2test : /proc et /sys de la partie 38 : /proc/net/{tcp,udp,unix,raw,
   arp,snmp,sockstat,protocols}, /proc/PID/{fd,fdinfo,environ,limits,statm,
   comm,io,mountinfo,mounts,cgroup,task}, liens magiques (stat de fd/N, cwd,
   exe, root), /proc/{partitions,diskstats,devices,interrupts,ioports,iomem,
   vmstat,buddyinfo,misc,cgroups,tty/drivers}, /sys/bus/pci/devices. */
#include "ku.h"
#include "kusock.h"

static char big[40000];

static int slurp(const char*p,char*b,int max){
  int fd=open(p,O_RDONLY,0),n,t=0;
  if(fd<0)return fd;
  while(t<max-1&&(n=read(fd,b+t,max-1-t))>0)t+=n;
  b[t]=0;close(fd);return t;
}
static int has(const char*hay,const char*needle){
  int l=strlen(needle),i;
  for(i=0;hay[i];i++)if(memcmp_(hay+i,needle,l)==0)return 1;
  return 0;
}
static int hasname(const char*dir,const char*nm){
  char buf[2048];int fd=open(dir,O_RDONLY|O_DIRECTORY,0),n,found=0;
  if(fd<0)return 0;
  while((n=getdents64(fd,buf,sizeof buf))>0){int o=0;
    while(o<n){struct{unsigned long long i,o;unsigned short l;unsigned char t;char nm[1];}*e=(void*)(buf+o);
      if(strcmp(e->nm,nm)==0)found=1;o+=e->l;}}
  close(fd);return found;
}
static unsigned st_ino(int fd){unsigned char s[96];if(sc2(SYS_fstat64,fd,(long)s))return 0;return *(unsigned*)(s+88);}
static unsigned st_mode(const char*p){unsigned char s[96];if(sc2(SYS_stat64,(long)p,(long)s))return 0;return *(unsigned*)(s+16);}
static unsigned st_inop(const char*p,unsigned*dev){unsigned char s[96];if(sc2(SYS_stat64,(long)p,(long)s))return 0;if(dev)*dev=*(unsigned*)s;return *(unsigned*)(s+88);}
static void hex4(char*o,unsigned v){int i;for(i=0;i<4;i++)o[i]="0123456789ABCDEF"[(v>>(12-4*i))&15];o[4]=0;}
static void dec(char*o,unsigned v){char t[12];int i=0,j=0;if(!v)t[i++]='0';while(v){t[i++]='0'+v%10;v/=10;}while(i)o[j++]=t[--i];o[j]=0;}
static void pad5(char*o,unsigned v){char t[12];int i,l;dec(t,v);l=strlen(t);for(i=0;i<5-l;i++)o[i]=' ';strcpy_(o+(l<5?5-l:0),t);i=l<5?5:l;o[i]=' ';o[i+1]=0;}
/* la ligne de b qui contient needle */
static const char*lineof(const char*b,const char*needle){
  static char ln[300];const char*p=b;
  while(*p){const char*e=p;int n=0;while(*e&&*e!='\n'){e++;n++;}
    if(n<300){int i;for(i=0;i<n;i++)ln[i]=p[i];ln[n]=0;if(has(ln,needle))return ln;}
    p=*e?e+1:e;}
  return 0;
}

int main(){
  int lis,cli,acc,r,i,ud,sv[2];
  struct sin a;int al=sizeof a;
  char key[40],pt[8],ino[16];unsigned lino,pino;
  const char*ln;
  /* ---- /proc/net/tcp ---- */
  lis=socket(2,1,0);
  memset(&a,0,sizeof a);a.fam=2;a.addr=0x0100007f;a.port=0;
  ktest("net.bind",bind(lis,&a,sizeof a)==0);
  listen(lis,4);
  getsockname(lis,&a,&al);
  hex4(pt,((a.port&0xff)<<8)|(a.port>>8));
  lino=st_ino(lis);dec(ino,lino);
  r=slurp("/proc/net/tcp",big,sizeof big);
  ktest("net.tcp_header",r>0&&has(big,"local_address")&&has(big,"inode"));
  strcpy_(key,"0100007F:");strcpy_(key+9,pt);strcpy_(key+13," 00000000:0000 0A");
  ln=lineof(big,key);
  ktest("net.tcp_listen",ln!=0);
  ktest("net.tcp_listen_inode",ln&&has(ln,ino));
  cli=socket(2,1,0);
  r=connect(cli,&a,sizeof a);
  acc=accept(lis,0,0);
  ktest("net.connect",r==0&&acc>=0);
  r=slurp("/proc/net/tcp",big,sizeof big);
  {int n=0;const char*p=big;char kk[40];strcpy_(kk,":");strcpy_(kk+1,pt);strcpy_(kk+5," 01");
    /* connexions etablies : deux extremites, l'une avec le port local du serveur */
    strcpy_(key,"0100007F:");strcpy_(key+9,pt);strcpy_(key+13," 0100007F:");
    while(*p){if(memcmp_(p,key,23)==0)n++;p++;}
    ktest("net.tcp_established",n>=1);
    ktest("net.tcp_established_state",has(big,":")&&lineof(big,"0100007F:")&&has(big," 01 "));}
  dec(ino,st_ino(acc));
  ktest("net.tcp_accepted_inode",has(big,ino));
  /* /proc/PID/fd : lien socket:[ino] */
  {char t[64],nm[32],link[80];strcpy_(nm,"/proc/self/fd/");dec(nm+14,lis);
   r=readlink(nm,link,sizeof link-1);if(r>0)link[r]=0;else link[0]=0;
   strcpy_(t,"socket:[");dec(t+8,lino);{int l=strlen(t);t[l]=']';t[l+1]=0;}
   ktest("fd.readlink_socket",r>0&&strcmp(link,t)==0);
   ktest("fd.stat_socket_mode",(st_mode(nm)&0xF000)==0xC000);
   ktest("fd.stat_socket_ino",st_inop(nm,0)==lino);}
  close(acc);close(cli);close(lis);
  /* ---- udp ---- */
  ud=socket(2,2,0);
  memset(&a,0,sizeof a);a.fam=2;a.addr=0;a.port=0;
  bind(ud,&a,sizeof a);getsockname(ud,&a,&al);
  hex4(pt,((a.port&0xff)<<8)|(a.port>>8));
  r=slurp("/proc/net/udp",big,sizeof big);
  strcpy_(key,"00000000:");strcpy_(key+9,pt);strcpy_(key+13," 00000000:0000 07");
  ln=lineof(big,key);
  ktest("net.udp_bound",r>0&&has(big,"local_address")&&ln!=0);
  dec(ino,st_ino(ud));
  ktest("net.udp_inode",ln&&has(ln,ino));
  close(ud);
  /* ---- unix ---- */
  {struct sun u;int s1,s2,ab;unsigned i1;
   unlink("/tmp/px.sock");
   s1=socket(1,1,0);memset(&u,0,sizeof u);u.fam=1;strcpy_(u.path,"/tmp/px.sock");
   bind(s1,&u,2+strlen("/tmp/px.sock")+1);listen(s1,2);
   i1=st_ino(s1);pad5(ino,i1);
   ab=socket(1,1,0);memset(&u,0,sizeof u);u.fam=1;u.path[0]=0;strcpy_(u.path+1,"pxabs");
   bind(ab,&u,2+6);
   s2=socket(1,2,0);
   r=slurp("/proc/net/unix",big,sizeof big);
   ktest("unix.header",r>0&&has(big,"RefCount")&&has(big,"Inode"));
   ln=lineof(big,"/tmp/px.sock");
   ktest("unix.listen_line",ln!=0&&has(ln,"00010000 0001 01")&&has(ln,ino));
   ln=lineof(big,"@pxabs");
   ktest("unix.abstract",ln!=0);
   socketpair(1,1,0,sv);
   r=slurp("/proc/net/unix",big,sizeof big);
   pad5(ino,st_ino(sv[0]));
   ln=lineof(big,ino);
   ktest("unix.pair_connected",ln!=0&&has(ln,"0001 03"));
   close(sv[0]);close(sv[1]);close(s1);close(s2);close(ab);unlink("/tmp/px.sock");}
  /* ---- fichiers divers de /proc/net ---- */
  slurp("/proc/net/snmp",big,sizeof big);
  ktest("net.snmp",has(big,"Ip: Forwarding")&&has(big,"Tcp: RtoAlgorithm")&&has(big,"Udp: InDatagrams"));
  slurp("/proc/net/sockstat",big,sizeof big);
  ktest("net.sockstat",has(big,"sockets: used")&&has(big,"TCP: inuse"));
  slurp("/proc/net/arp",big,sizeof big);
  ktest("net.arp",has(big,"HW address"));
  slurp("/proc/net/protocols",big,sizeof big);
  ktest("net.protocols",has(big,"protocol")&&has(big,"TCP"));
  ktest("net.raw",slurp("/proc/net/raw",big,sizeof big)>0&&has(big,"local_address"));
  ktest("net.readdir",hasname("/proc/net","tcp")&&hasname("/proc/net","udp")&&hasname("/proc/net","unix")&&hasname("/proc/net","dev")&&hasname("/proc/net","route"));
  /* ---- /proc/self/fd : fichier, tube, cwd, exe, root ---- */
  {int fd,p[2];char link[100],nm[40];unsigned dv1,dv2;
   fd=open("/tmp/fdtest",O_CREAT|O_RDWR,0644);
   write(fd,"0123456789",10);
   strcpy_(nm,"/proc/self/fd/");dec(nm+14,fd);
   r=readlink(nm,link,sizeof link-1);if(r>0)link[r]=0;else link[0]=0;
   ktest("fd.readlink_file",strcmp(link,"/tmp/fdtest")==0);
   ktest("fd.stat_follow",st_inop(nm,&dv1)==st_ino(fd)&&st_inop("/tmp/fdtest",&dv2)==st_ino(fd)&&dv1==dv2);
   pipe(p);
   strcpy_(nm,"/proc/self/fd/");dec(nm+14,p[0]);
   r=readlink(nm,link,sizeof link-1);if(r>0)link[r]=0;else link[0]=0;
   ktest("fd.readlink_pipe",has(link,"pipe:["));
   ktest("fd.stat_pipe",(st_mode(nm)&0xF000)==0x1000);
   /* ouvrir le tube par /proc/self/fd/N : meme tube */
   {int w=open(nm,O_RDONLY|O_NONBLOCK,0);ktest("fd.open_pipe",w>=0);if(w>=0)close(w);}
   close(p[0]);close(p[1]);
   ktest("fd.cwd",st_inop("/proc/self/cwd",&dv1)==st_inop(".",&dv2)&&dv1==dv2);
   ktest("fd.root",st_inop("/proc/self/root",&dv1)==st_inop("/",&dv2)&&dv1==dv2);
   ktest("fd.exe",st_inop("/proc/self/exe",&dv1)==st_inop("/bin/proc2test",&dv2)&&dv1==dv2&&st_inop("/proc/self/exe",0)!=0);
   r=readlink("/proc/self/exe",link,sizeof link-1);if(r>0)link[r]=0;else link[0]=0;
   ktest("fd.exe_readlink",strcmp(link,"/bin/proc2test")==0);
   /* fdinfo */
   strcpy_(nm,"/proc/self/fdinfo/");dec(nm+18,fd);
   slurp(nm,big,sizeof big);
   ktest("fdinfo.pos",has(big,"pos:\t10")&&has(big,"flags:\t0")&&has(big,"mnt_id:"));
   lseek(fd,3,0);slurp(nm,big,sizeof big);
   ktest("fdinfo.pos_seek",has(big,"pos:\t3"));
   ktest("fdinfo.readdir",hasname("/proc/self/fdinfo","0")&&hasname("/proc/self/fd","0")&&!hasname("/proc/self/fdinfo","77"));
   close(fd);unlink("/tmp/fdtest");}
  /* ---- fichiers de /proc/PID ---- */
  r=slurp("/proc/self/environ",big,sizeof big);
  for(i=0;i<r;i++)if(!big[i])big[i]='\n';
  ktest("pid.environ",has(big,"PATH=")&&has(big,"TERM=linux"));
  slurp("/proc/self/limits",big,sizeof big);
  ktest("pid.limits",has(big,"Max open files")&&has(big,"Max file size")&&has(big,"unlimited"));
  slurp("/proc/self/statm",big,sizeof big);
  ktest("pid.statm",big[0]>='0'&&big[0]<='9'&&has(big," "));
  slurp("/proc/self/comm",big,sizeof big);
  ktest("pid.comm",has(big,"proc2test"));
  slurp("/proc/self/io",big,sizeof big);
  ktest("pid.io",has(big,"rchar:")&&has(big,"write_bytes:"));
  slurp("/proc/self/mountinfo",big,sizeof big);
  ktest("pid.mountinfo",has(big," / / ")&&has(big," - tmpfs ")&&has(big," - proc "));
  slurp("/proc/self/mounts",big,sizeof big);
  ktest("pid.mounts",has(big,"proc /proc proc"));
  slurp("/proc/self/cgroup",big,sizeof big);
  ktest("pid.cgroup",has(big,"0::/"));
  ktest("pid.oom_score",slurp("/proc/self/oom_score",big,sizeof big)>0&&slurp("/proc/self/oom_score_adj",big,sizeof big)>0);
  {char t[40],d[12];int tid=getpid();
   dec(d,tid);strcpy_(t,"/proc/self/task");
   ktest("pid.task_dir",hasname("/proc/self/task",d));
   strcpy_(t,"/proc/self/task/");strcpy_(t+16,d);strcpy_(t+16+strlen(d),"/stat");
   slurp(t,big,sizeof big);
   ktest("pid.task_stat",has(big,"proc2test"));
   ktest("pid.task_enoent",open("/proc/self/task/999999/stat",O_RDONLY,0)<0);}
  ktest("pid.readdir",hasname("/proc/self","limits")&&hasname("/proc/self","environ")&&hasname("/proc/self","fdinfo")&&hasname("/proc/self","mountinfo")&&hasname("/proc/self","task")&&hasname("/proc/self","cwd"));
  ktest("pid.status_ext",slurp("/proc/self/status",big,sizeof big)>0&&has(big,"Threads:")&&has(big,"CapEff:"));
  /* ---- fichiers du haut de /proc ---- */
  r=slurp("/proc/partitions",big,sizeof big);
  ktest("proc.partitions",r>0&&has(big,"major minor  #blocks  name")&&has(big,"ram0"));
  r=slurp("/proc/diskstats",big,sizeof big);
  ktest("proc.diskstats",r>0&&has(big," ram0 "));
  r=slurp("/proc/devices",big,sizeof big);
  ktest("proc.devices",has(big,"Character devices:")&&has(big,"Block devices:")&&has(big," loop"));
  r=slurp("/proc/interrupts",big,sizeof big);
  ktest("proc.interrupts",has(big,"CPU0")&&has(big,"timer"));
  {char*p=big;int v=0;while(*p&&*p!=':')p++;if(*p==':'){p++;while(*p==' ')p++;while(*p>='0'&&*p<='9')v=v*10+*p++-'0';}
   ktest("proc.interrupts_timer_counts",v>0);}
  ktest("proc.ioports",slurp("/proc/ioports",big,sizeof big)>0&&has(big,"pic1")&&has(big,"serial"));
  ktest("proc.iomem",slurp("/proc/iomem",big,sizeof big)>0&&has(big,"System RAM"));
  ktest("proc.vmstat",slurp("/proc/vmstat",big,sizeof big)>0&&has(big,"nr_free_pages")&&has(big,"pgfault"));
  ktest("proc.buddyinfo",slurp("/proc/buddyinfo",big,sizeof big)>0&&has(big,"zone   Normal"));
  ktest("proc.misc",slurp("/proc/misc",big,sizeof big)>0&&has(big,"loop-control"));
  ktest("proc.cgroups",slurp("/proc/cgroups",big,sizeof big)>0&&has(big,"subsys_name"));
  ktest("proc.tty_drivers",slurp("/proc/tty/drivers",big,sizeof big)>0&&has(big,"/dev/console"));
  ktest("proc.readdir",hasname("/proc","partitions")&&hasname("/proc","diskstats")&&hasname("/proc","devices")&&hasname("/proc","interrupts")&&hasname("/proc","net")&&hasname("/proc","sys")&&hasname("/proc","kallsyms")&&hasname("/proc","self")&&hasname("/proc","tty"));
  {char d[12];dec(d,getpid());ktest("proc.readdir_pid",hasname("/proc",d));}
  /* ---- /sys/bus/pci ---- */
  ktest("sys.pci_dir",hasname("/sys/bus/pci/devices","0000:00:00.0"));
  r=slurp("/sys/bus/pci/devices/0000:00:00.0/vendor",big,sizeof big);
  if(!has(big,"0x8086")){{char b2[600];int fd=open("/sys/bus/pci/devices/0000:00:00.0",O_RDONLY|O_DIRECTORY,0),n2;puts("  dir:");while((n2=getdents64(fd,b2,sizeof b2))>0){int o=0;while(o<n2){struct{unsigned long long i,o;unsigned short l;unsigned char t;char nm[1];}*e=(void*)(b2+o);puts(" ");puts(e->nm);o+=e->l;}}puts("\n");}puts("  vendor r=");putd(r);puts(" [");puts(big);puts("]\n");}
  ktest("sys.pci_vendor",has(big,"0x8086"));
  slurp("/sys/bus/pci/devices/0000:00:00.0/class",big,sizeof big);
  ktest("sys.pci_class",has(big,"0x0600"));
  {unsigned char cfg[300];int fd=open("/sys/bus/pci/devices/0000:00:00.0/config",O_RDONLY,0);
   int n=fd>=0?read(fd,cfg,300):-1;if(fd>=0)close(fd);
   ktest("sys.pci_config",n==256&&cfg[0]==0x86&&cfg[1]==0x80);}
  ktest("sys.pci_resource",slurp("/sys/bus/pci/devices/0000:00:00.0/resource",big,sizeof big)>0&&has(big,"0x0000000000000000"));
  ktest("sys.pci_irq_uevent",slurp("/sys/bus/pci/devices/0000:00:00.0/uevent",big,sizeof big)>0&&has(big,"PCI_ID=8086:"));
  ktest("sys.usb_dir",(st_mode("/sys/bus/usb/devices")&0xF000)==0x4000);
  /* au moins un autre peripherique PCI avec ses BAR (reseau ou video) */
  {int found=0;char dn[8][32];int k=0;char buf[1024];int fd=open("/sys/bus/pci/devices",O_RDONLY|O_DIRECTORY,0),n;
   if(fd>=0){while((n=getdents64(fd,buf,sizeof buf))>0){int o=0;while(o<n){struct{unsigned long long i,o;unsigned short l;unsigned char t;char nm[1];}*e=(void*)(buf+o);
       if(e->nm[0]=='0'&&k<8){strcpy_(dn[k],e->nm);k++;}o+=e->l;}}close(fd);}
   for(i=0;i<k;i++){char pth[100];strcpy_(pth,"/sys/bus/pci/devices/");strcpy_(pth+21,dn[i]);strcpy_(pth+21+strlen(dn[i]),"/resource");
     slurp(pth,big,sizeof big);if(has(big,"0x0000000000040101")||has(big,"0x0000000000040200")||has(big,"0x0000000000042208"))found++;}
   ktest("sys.pci_bars",k>=2&&found>=1);}
  r=slurp("/sys/block/loop0/dev",big,sizeof big);
  ktest("sys.block_loop0_dev",r>=3&&big[0]=='7'&&big[1]==':'&&big[2]=='0');
  ktest("sys.class_block_loop0",(st_mode("/sys/class/block/loop0")&0xF000)==0x4000);
  r=slurp("/sys/class/mem/null/dev",big,sizeof big);
  ktest("sys.class_mem_null_dev",r>=3&&big[0]=='1'&&big[1]==':'&&big[2]=='3');
  r=slurp("/sys/class/tty/tty1/dev",big,sizeof big);
  ktest("sys.class_tty1_dev",r>=3&&big[0]=='4'&&big[1]==':'&&big[2]=='1');
  puts("KTEST: proc2 DONE\n");
  return ku_fail?1:0;
}
