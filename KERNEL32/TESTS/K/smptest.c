/* smptest : processeurs detectes (ACPI MADT / tables MP, partie 38) : les
   processeurs secondaires sont demarres a l'arret ; seul le CPU 0 execute
   des taches. Verifie la coherence de /sys/devices/system/cpu et /proc. */
#include "ku.h"
static char b[2048];
static int slurp(const char*p,char*s,int max){int fd=open(p,O_RDONLY,0),n;if(fd<0)return fd;n=read(fd,s,max-1);if(n<0)n=0;s[n]=0;close(fd);return n;}
int main(){
  int n=0,i,present=1;
  slurp("/sys/devices/system/cpu/present",b,sizeof b);
  /* "0" ou "0-N" */
  if(b[0]=='0'&&b[1]=='-'){for(i=2;b[i]>='0'&&b[i]<='9';i++)n=n*10+b[i]-'0';present=n+1;}
  ktest("smp.present_format",b[0]=='0'&&present>=1&&present<=16);
  slurp("/sys/devices/system/cpu/online",b,sizeof b);
  ktest("smp.online_only_bsp",b[0]=='0'&&b[1]=='\n');
  slurp("/sys/devices/system/cpu/offline",b,sizeof b);
  if(present>1){int m=0;for(i=2;b[i]>='0'&&b[i]<='9';i++)m=m*10+b[i]-'0';
    ktest("smp.offline_range",b[0]=='1'&&m==present-1);}
  else ktest("smp.offline_range",b[0]=='\n'||b[0]==0);
  {int ok=1;char p[64];for(i=0;i<present;i++){
     char d[4];d[0]='0'+i/10;d[1]='0'+i%10;d[2]=0;
     strcpy_(p,"/sys/devices/system/cpu/cpu");strcpy_(p+27,i<10?d+1:d);
     {int l=strlen(p);strcpy_(p+l,i?"/online":"");}
     if(i==0){int fd=open("/sys/devices/system/cpu/cpu0",O_RDONLY|O_DIRECTORY,0);if(fd<0)ok=0;else close(fd);}
     else{int r=slurp(p,b,sizeof b);if(r<1||b[0]!='0')ok=0;}}
   ktest("smp.cpu_dirs",ok);}
  {int cnt=0;int r=slurp("/proc/cpuinfo",b,sizeof b);for(i=0;i<r;i++)if(b[i]=='p'&&memcmp_(b+i,"processor",9)==0)cnt++;
   ktest("smp.cpuinfo_online_only",cnt==1);
   {int k;int has=0;for(k=0;k<r;k++)if(memcmp_(b+k,"apicid",6)==0)has=1;ktest("smp.cpuinfo_apicid",has);}}
  {unsigned long m[4]={0,0,0,0};long r=sc3(242,0,16,(long)m);
   ktest("smp.affinity_one_cpu",r>=4&&m[0]==1);
   m[0]=2;ktest("smp.setaffinity_offline_cpu",sc3(241,0,4,(long)m)==-22);
   m[0]=1;ktest("smp.setaffinity_cpu0",sc3(241,0,4,(long)m)==0);}
  puts("KTEST: smp DONE\n");
  return ku_fail?1:0;
}
