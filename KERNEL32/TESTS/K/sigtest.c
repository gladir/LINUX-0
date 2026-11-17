/* sigtest : sigaction, masque, kill, alarm, sigreturn, SIGSEGV, SIGCHLD */
#include "ku.h"
static volatile int cnt,last,alrm,chld,segv;
static void h1(int s){cnt++;last=s;}
static void halrm(int s){alrm++;}
static void hchld(int s){chld++;}
static void hsegv(int s){segv++;_exit(segv==1?0:1);}
int main(void){
  int st,p;
  signal_set(SIGUSR1,h1,0);
  kill(getpid(),SIGUSR1);
  ktest("sig.handler",cnt==1&&last==SIGUSR1);
  sigblock(1UL<<(SIGUSR1-1));
  kill(getpid(),SIGUSR1);
  ktest("sig.blocked",cnt==1);
  sigunblock(1UL<<(SIGUSR1-1));
  ktest("sig.unblock",cnt==2);
  signal_set(SIGALRM,halrm,0);
  alarm(1);
  pause();
  ktest("sig.alarm",alrm==1);
  signal_set(SIGCHLD,hchld,0);
  p=fork();
  if(p==0)_exit(0);
  waitpid(p,&st,0);
  ktest("sig.sigchld",chld>=1);
  signal_set(SIGCHLD,(void(*)(int))0,0);
  signal_set(SIGUSR2,(void(*)(int))1,0);
  kill(getpid(),SIGUSR2);
  ktest("sig.ignore",1);
  p=fork();
  if(p==0){signal_set(SIGUSR2,(void(*)(int))0,0);kill(getpid(),SIGUSR2);for(;;);}
  waitpid(p,&st,0);
  ktest("sig.default_term",(st&0x7f)==SIGUSR2);
  p=fork();
  if(p==0){signal_set(SIGSEGV,hsegv,0);*(volatile int*)0=1;_exit(5);}
  waitpid(p,&st,0);
  ktest("sig.segv_handler",st==0);
  p=fork();
  if(p==0){*(volatile int*)0x10=1;_exit(5);}
  waitpid(p,&st,0);
  ktest("sig.segv_fatal",(st&0x7f)==SIGSEGV);
  ktest("sig.esrch",kill(30000,0)==-3);
  return ku_fail?1:0;
}
