/* limtest : RLIMIT_FSIZE, RLIMIT_AS, RLIMIT_CPU */
#include "ku.h"
static int setrl(int r,long cur,long max){long l[2]={cur,max};return sc2(75,r,(long)l);}
int main(void){
  int fd,n,p,st;char b[4096];
  memset(b,'x',4096);
  p=fork();
  if(p==0){
    signal_set(25,(void(*)(int))1,0);
    setrl(1,1000,1000);
    fd=open("/tmp/lim1",O_RDWR|O_CREAT|O_TRUNC,0644);
    n=write(fd,b,2000);
    if(n!=1000)_exit(1);
    n=write(fd,b,10);
    if(n!=-27)_exit(2);
    unlink("/tmp/lim1");
    _exit(0);
  }
  waitpid(p,&st,0);
  ktest("limit.fsize",st==0);
  p=fork();
  if(p==0){
    char*m;
    setrl(1,500,500);
    fd=open("/tmp/lim2",O_RDWR|O_CREAT|O_TRUNC,0644);
    write(fd,b,2000);
    write(fd,b,10);
    _exit(0);
  }
  waitpid(p,&st,0);
  ktest("limit.fsize_sigxfsz",(st&0x7f)==25);
  unlink("/tmp/lim2");
  p=fork();
  if(p==0){
    long l[2];
    void*m;
    setrl(9,32*1024*1024,32*1024*1024);
    m=mmap2(0,64*1024*1024,3,0x22,-1,0);
    if((long)m>0||(long)m<-4096)_exit(1);
    m=mmap2(0,1*1024*1024,3,0x22,-1,0);
    if((long)m<0&&(long)m>-4096)_exit(2);
    _exit(0);
  }
  waitpid(p,&st,0);
  ktest("limit.as",st==0);
  p=fork();
  if(p==0){
    volatile unsigned long i;
    setrl(0,1,2);
    for(i=0;;i++);
  }
  waitpid(p,&st,0);
  ktest("limit.cpu_sigxcpu",(st&0x7f)==24);
  return ku_fail?1:0;
}
