/* stress : fork/exec/exit repetes, fichiers, tubes : pas de fuite de memoire */
#include "ku.h"
static long memfree(void){char b[512];int fd=open("/proc/meminfo",O_RDONLY,0),n;long v=0;int i;
  if(fd<0)return -1;n=read(fd,b,511);close(fd);b[n>0?n:0]=0;
  for(i=0;b[i];i++)if(b[i]=='F'&&b[i+1]=='r'&&b[i+2]=='e'&&b[i+3]=='e'&&b[i+4]==':'){i+=5;while(b[i]==' ')i++;while(b[i]>='0'&&b[i]<='9')v=v*10+b[i++]-'0';break;}
  return v;}
int main(void){
  long m0,m1;int i,st,p,fd,f[2];char nm[32];
  /* une premiere passe chauffe les caches du noyau (dentries, tampons) */
  for(i=0;i<3;i++){p=fork();if(p==0)_exit(0);waitpid(p,&st,0);}
  m0=memfree();
  for(i=0;i<150;i++){
    p=fork();
    if(p==0){int d=open("/dev/null",O_WRONLY,0);dup2(d,1);char*a[]={"/bin/hello",0};char*e[]={"PATH=/bin",0};execve("/bin/hello",a,e);_exit(1);}
    if(p<0){ktest("stress.fork_fail",0);break;}
    waitpid(p,&st,0);
  }
  ktest("stress.forkexec",i==150);
  for(i=0;i<300;i++){nm[0]='/';nm[1]='t';nm[2]='m';nm[3]='p';nm[4]='/';nm[5]='s';nm[6]='0'+i/100%10;nm[7]='0'+i/10%10;nm[8]='0'+i%10;nm[9]=0;
    fd=open(nm,O_CREAT|O_RDWR,0600);if(fd<0)break;write(fd,"0123456789abcdef",16);close(fd);}
  ktest("stress.create",i==300);
  for(i=0;i<300;i++){nm[0]='/';nm[1]='t';nm[2]='m';nm[3]='p';nm[4]='/';nm[5]='s';nm[6]='0'+i/100%10;nm[7]='0'+i/10%10;nm[8]='0'+i%10;nm[9]=0;unlink(nm);}
  for(i=0;i<100;i++){pipe(f);write(f[1],"x",1);close(f[0]);close(f[1]);}
  m1=memfree();
  puts("  MemFree avant=");putd(m0);puts(" apres=");putd(m1);puts(" kB\n");
  {long sf[16];int ext=sc2(99,(long)"/tmp",(long)sf)==0&&sf[0]==0xEF53;
  ktest("stress.noleak",m0-m1<(ext?4096:256));}
  return ku_fail?1:0;
}
