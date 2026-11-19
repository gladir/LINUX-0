/* aperf : debit du disque AHCI/SATA (RUNAHCIPERF.SH). Ecrit puis relit
   MB megaoctets (ligne de commande aperf=MB) sur le disque brut /dev/sdb
   (octets de motif, un marqueur unique par secteur) et un fichier de
   EXTMB megaoctets (aperfext=MB) sur l'ext4 de /dev/sda1 ; verifie tout ;
   imprime le debit et les compteurs /proc/k32perf. Le motif est recalcule et
   reverifie par l'hote (RUNAHCIPERF.SH). Sans aperf= sur la ligne de
   commande le programme ne fait rien. */
#include "ku.h"
static unsigned buf[262144];          /* 1 Mo */
static unsigned base[262144];
static int pnum(const char*s){int n=0;while(*s>='0'&&*s<='9')n=n*10+*s++-'0';return n;}
static int cmdnum(const char*key){static char cl[512];int n=0,fd=open("/proc/cmdline",O_RDONLY,0),i,l=strlen(key);
  if(fd>=0){n=read(fd,cl,sizeof cl-1);close(fd);}if(n<0)n=0;cl[n]=0;
  for(i=0;i+l<n;i++)if(memcmp_(cl+i,key,l)==0&&cl[i+l]=='='&&(i==0||cl[i-1]==' '))return pnum(cl+i+l+1);return 0;}
static long now_ms(void){long tv[2];sc2(SYS_gettimeofday,(long)tv,0);return tv[0]*1000+tv[1]/1000;}
static long perf(const char*key){static char b[4096];int n=0,fd=open("/proc/k32perf",O_RDONLY,0),i,l=strlen(key);
  if(fd>=0){n=read(fd,b,sizeof b-1);close(fd);}if(n<0)n=0;b[n]=0;
  for(i=0;i+l<n;i++)if(memcmp_(b+i,key,l)==0&&b[i+l]==' '&&(i==0||b[i-1]=='\n'))return pnum(b+i+l+1);return -1;}
static inline void fcopy(void*d,const void*s,int nw){__asm__ volatile("cld;rep movsl":"+D"(d),"+S"(s),"+c"(nw)::"memory");}
static inline int fcmp(const void*a,const void*b,int nw){int r;__asm__ volatile("cld;xorl %%eax,%%eax;repe cmpsl;setne %%al":"+D"(a),"+S"(b),"+c"(nw),"=a"(r)::"memory");return r==0;}
static int fsync(int fd){return sc1(118,fd);}
static void fillblk(int k){int j;fcopy(buf,base,262144);
  for(j=0;j<2048;j++)buf[j*128]=((unsigned)k<<11|j)^0xA5A50000u;}
static int chkblk(int k){int j;
  for(j=0;j<2048;j++){if(buf[j*128]!=(((unsigned)k<<11|j)^0xA5A50000u))return 0;buf[j*128]=base[j*128];}
  return fcmp(buf,base,262144);}
static long tacc;
static void rep(const char*what,long ms,int mb,long c0,long c1,long k0,long k1,long r0,long r1,long i0,long i1){
  long mbps=ms>0?(long)mb*1000/ms:0;ms=ms;
  puts("APERF ");puts(what);puts(" : ");putd(mb);puts(" Mo en ");putd(ms);puts(" ms = ");putd(mbps);
  puts(" Mo/s ; commandes ");putd(c1-c0);puts(", Ko ");putd(k1-k0);puts(", acces registres ");putd(r1-r0);
  puts(", IRQ ");putd(i1-i0);puts("\n");}
int main(void){
  int mb=cmdnum("aperf"),emb=cmdnum("aperfext"),fd,k,bad=0;long t0,t1,c0,c1,k0,k1,r0,r1,i0,i1;
  if(mb==0&&emb==0){puts("  (aperf : ignore, voir RUNAHCIPERF.SH)\n");return 0;}
  for(k=0;k<262144;k++)base[k]=(unsigned)k*0x9E3779B1u^((unsigned)k>>5);
  if(mb>0){
    fd=open("/dev/sdb",O_RDWR,0);
    ktest("aperf.raw_open",fd>=0);
    if(fd<0)return 1;
    c0=perf("ahci_commands");k0=perf("ahci_kb");r0=perf("ahci_reg_access");i0=perf("ahci_irq");t0=now_ms();
    for(k=0;k<mb;k++){long a;fillblk(k);a=now_ms();if(write(fd,buf,sizeof buf)!=(int)sizeof buf){bad=1;break;}tacc+=now_ms()-a;}
    {long a=now_ms();sync();tacc+=now_ms()-a;}
    t1=t0+tacc;tacc=0;c1=perf("ahci_commands");k1=perf("ahci_kb");r1=perf("ahci_reg_access");i1=perf("ahci_irq");
    ktest("aperf.raw_write",!bad);
    rep("brut ecriture",t1-t0,mb,c0,c1,k0,k1,r0,r1,i0,i1);
    close(fd);
    fd=open("/dev/sdb",O_RDONLY,0);bad=0;
    c0=perf("ahci_commands");k0=perf("ahci_kb");r0=perf("ahci_reg_access");i0=perf("ahci_irq");t0=now_ms();
    for(k=0;k<mb;k++){long a=now_ms();int rr=read(fd,buf,sizeof buf);tacc+=now_ms()-a;if(rr!=(int)sizeof buf||!chkblk(k)){bad=1;break;}}
    t1=t0+tacc;tacc=0;c1=perf("ahci_commands");k1=perf("ahci_kb");r1=perf("ahci_reg_access");i1=perf("ahci_irq");
    ktest("aperf.raw_read_verify",!bad);
    rep("brut lecture",t1-t0,mb,c0,c1,k0,k1,r0,r1,i0,i1);
    close(fd);
  }
  if(emb>0){
    int r=mount("/dev/sda1","/mnt","ext4",0,0);
    ktest("aperf.ext4_mount",r==0);
    if(r==0){
      fd=open("/mnt/aperf.bin",O_WRONLY|O_CREAT|O_TRUNC,0644);bad=fd<0;
      c0=perf("ahci_commands");k0=perf("ahci_kb");r0=perf("ahci_reg_access");i0=perf("ahci_irq");t0=now_ms();
      for(k=0;k<emb&&!bad;k++){long a;fillblk(k);a=now_ms();if(write(fd,buf,sizeof buf)!=(int)sizeof buf)bad=1;tacc+=now_ms()-a;}
      {long a=now_ms();if(!bad)fsync(fd);close(fd);sync();tacc+=now_ms()-a;}
      t1=t0+tacc;tacc=0;c1=perf("ahci_commands");k1=perf("ahci_kb");r1=perf("ahci_reg_access");i1=perf("ahci_irq");
      ktest("aperf.ext4_write",!bad);
      rep("ext4 ecriture",t1-t0,emb,c0,c1,k0,k1,r0,r1,i0,i1);
      umount("/mnt");
      mount("/dev/sda1","/mnt","ext4",0,0);     /* relecture depuis le disque */
      fd=open("/mnt/aperf.bin",O_RDONLY,0);bad=fd<0;
      c0=perf("ahci_commands");k0=perf("ahci_kb");r0=perf("ahci_reg_access");i0=perf("ahci_irq");t0=now_ms();
      for(k=0;k<emb&&!bad;k++){long a=now_ms();int rr=read(fd,buf,sizeof buf);tacc+=now_ms()-a;if(rr!=(int)sizeof buf||!chkblk(k))bad=1;}
      t1=t0+tacc;tacc=0;c1=perf("ahci_commands");k1=perf("ahci_kb");r1=perf("ahci_reg_access");i1=perf("ahci_irq");
      ktest("aperf.ext4_read_verify",!bad);
      rep("ext4 lecture",t1-t0,emb,c0,c1,k0,k1,r0,r1,i0,i1);
      close(fd);
      umount("/mnt");
    }
  }
  puts("KTEST: aperf DONE\n");
  return ku_fail?1:0;
}
