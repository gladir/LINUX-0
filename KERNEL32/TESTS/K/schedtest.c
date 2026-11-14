/* schedtest : ordonnanceur, nice, nanosleep, times, gettimeofday */
#include "ku.h"
static volatile unsigned long spin;
int main(void){
  long tv0[2],tv1[2];int st;
  sc2(SYS_gettimeofday,(long)tv0,0);
  long ts[2]={0,200000000};
  nanosleep(ts,0);
  sc2(SYS_gettimeofday,(long)tv1,0);
  long ms=(tv1[0]-tv0[0])*1000+(tv1[1]-tv0[1])/1000;
  ktest("time.nanosleep",ms>=190&&ms<400);
  puts("  dormi ");putd(ms);puts(" ms\n");
  int p1=fork();
  if(p1==0){unsigned long i;for(i=0;i<20000000UL;i++)spin++;_exit(0);}
  int p2=fork();
  if(p2==0){unsigned long i;for(i=0;i<20000000UL;i++)spin++;_exit(0);}
  waitpid(p1,&st,0);waitpid(p2,&st,0);
  ktest("sched.cpu",1);
  ktest("nice",nice(5)==0);
  ktest("time.times",sc1(43,0)>0);
  long t=sc1(SYS_time,0);
  ktest("time.time",t>1700000000);
  return ku_fail?1:0;
}
