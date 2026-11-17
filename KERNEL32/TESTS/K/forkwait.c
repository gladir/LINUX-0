/* forkwait : fork, wait4/waitpid, codes de sortie, orphelins, zombies */
#include "ku.h"
int main(void){
  int st=0,p,i;
  p=fork();
  if(p==0)_exit(7);
  ktest("fork.pid",p>0);
  ktest("wait.pid",waitpid(p,&st,0)==p);
  ktest("wait.status",((st>>8)&0xff)==7&&(st&0x7f)==0);
  volatile int x=42;
  p=fork();
  if(p==0){x=99;_exit(x==99?0:1);}
  waitpid(p,&st,0);
  ktest("fork.cow",x==42&&st==0);
  int pids[4];
  for(i=0;i<4;i++){p=fork();if(p==0)_exit(10+i);pids[i]=p;}
  int okk=1;
  for(i=0;i<4;i++){int s2;int r=waitpid(pids[i],&s2,0);if(r!=pids[i]||((s2>>8)&0xff)!=10+i)okk=0;}
  ktest("fork.multi",okk);
  ktest("wait.echild",waitpid(-1,&st,0)==-10);
  p=fork();
  if(p==0){for(;;)pause();}
  kill(p,SIGKILL);
  waitpid(p,&st,0);
  ktest("wait.sigkill",(st&0x7f)==SIGKILL);
  p=fork();
  if(p==0){int q=fork();if(q==0){long ts[2]={0,50000000};nanosleep(ts,0);_exit(0);}_exit(0);}
  waitpid(p,&st,0);
  ktest("fork.orphan",st==0);
  p=fork();
  if(p==0){char*a[]={"/bin/hello","arg1",0};char*e[]={"PATH=/bin",0};execve("/bin/hello",a,e);_exit(99);}
  waitpid(p,&st,0);
  ktest("exec.hello",st==0);
  { char*a[]={"x",0};char*e[]={0};
  ktest("exec.enoent",execve("/bin/nexiste",a,e)==-2); }
  return ku_fail?1:0;
}
