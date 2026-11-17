/* killtest : kill(-1), kill(0), kill(-pgrp), kill(pid) : le signal n'atteint
   ni init, ni l'appelant, ni les threads du noyau ; apres kill(-1) le systeme
   continue de tourner (nanosleep, sched_yield, waitpid(WNOHANG)). */
#include "ku.h"
#define SYS_nanosleep 162
#define WNOHANG 1
static void nap(int ms){long r[2]={0,ms*1000000L};nanosleep(r,0);}
static int spawn(int newgrp){
  int p=fork();
  if(p==0){if(newgrp)setpgid(0,0);for(;;)pause();}
  if(p>0&&newgrp)setpgid(p,p);
  return p;
}
static int reap(int n){
  int st,got=0,i,r;
  for(i=0;i<200&&got<n;i++){
    r=waitpid(-1,&st,WNOHANG);
    if(r>0){if((st&0x7f)==15)got++;else return -1;}
    else nap(5);
  }
  return got;
}
int main(void){
  int a,b,c,r,me=getpid();
  a=spawn(0);b=spawn(0);c=spawn(1);
  nap(20);
  ktest("kill.sig0",kill(a,0)==0&&kill(-getpgrp(),0)==0);
  ktest("kill.esrch",kill(99999,0)==-3);
  /* kill(-pgrp) : le groupe de c uniquement */
  ktest("kill.pgrp",kill(-c,SIGTERM)==0&&reap(1)==1&&kill(a,0)==0&&kill(b,0)==0);
  /* kill(0) : mon groupe (moi et a, b) : je me protege du signal */
  signal_set(SIGTERM,(void(*)(int))1,0);
  ktest("kill.pgrp0",kill(0,SIGTERM)==0);
  signal_set(SIGTERM,(void(*)(int))0,0);
  ktest("kill.pgrp0_reaped",reap(2)==2);
  a=spawn(0);b=spawn(1);nap(20);
  /* kill(-1) : tous sauf init et moi */
  r=kill(-1,SIGTERM);
  ktest("kill.all",r==0);
  ktest("kill.all_reaped",reap(2)==2);
  ktest("kill.all_alive",kill(me,0)==0&&kill(1,0)==0);
  /* le systeme continue : appels bloquants apres kill(-1) */
  nap(50);sched_yield();nap(50);
  ktest("kill.still_running",getpid()==me);
  { int p=fork(); if(p==0)_exit(7); int st=0; waitpid(p,&st,0);
    ktest("kill.fork_after",(st>>8)==7); }
  puts("kill DONE\n");
  return 0;
}
