/* mmaptest : brk, mmap anonyme, munmap, mprotect, pile, copy-on-write */
#include "ku.h"
static void hs(int s){_exit(0);}
int main(void){
  long b0=brk(0),b1;
  b1=brk((void*)(b0+3*4096));
  ktest("brk.grow",b1==b0+3*4096);
  volatile char*h=(char*)b0;
  h[0]=1;h[3*4096-1]=2;
  ktest("brk.rw",h[0]==1&&h[3*4096-1]==2);
  b1=brk((void*)b0);
  ktest("brk.shrink",b1==b0);
  char*m=mmap2(0,8*4096,3,0x22,-1,0);
  ktest("mmap.anon",(long)m>0&&(long)m<0x80000000);
  int i,ok=1;
  for(i=0;i<8*4096;i++)if(m[i]!=0)ok=0;
  ktest("mmap.zero",ok);
  for(i=0;i<8*4096;i+=4096)m[i]=i/4096+1;
  ok=1;for(i=0;i<8;i++)if(m[i*4096]!=i+1)ok=0;
  ktest("mmap.rw",ok);
  ktest("munmap",munmap(m+2*4096,2*4096)==0);
  int st,p=fork();
  if(p==0){signal_set(SIGSEGV,hs,0);m[2*4096]=1;_exit(3);}
  waitpid(p,&st,0);
  ktest("munmap.hole",st==0);
  ktest("mprotect",mprotect(m,4096,1)==0);
  p=fork();
  if(p==0){signal_set(SIGSEGV,hs,0);m[0]=9;_exit(3);}
  waitpid(p,&st,0);
  ktest("mprotect.ro",st==0);
  mprotect(m,4096,3);
  m[0]=11;
  p=fork();
  if(p==0){m[0]=22;_exit(m[0]==22?0:1);}
  waitpid(p,&st,0);
  ktest("mmap.cow",m[0]==11&&st==0);
  volatile char big[200*1024];
  big[0]=1;big[sizeof big-1]=2;
  ktest("stack.grow",big[0]==1&&big[sizeof big-1]==2);
  char*mm=mmap2(0,4*1024*1024,3,0x22,-1,0);
  mm[0]=1;mm[4*1024*1024-1]=2;
  ktest("mmap.4mb",mm[0]==1&&mm[4*1024*1024-1]==2);
  munmap(mm,4*1024*1024);
  int fd=open("/bin/mmaptest",O_RDONLY,0);
  char*f=mmap2(0,4096,1,2,fd,0);
  ktest("mmap.file",(long)f>0&&f[1]=='E'&&f[2]=='L'&&f[3]=='F');
  return ku_fail?1:0;
}
