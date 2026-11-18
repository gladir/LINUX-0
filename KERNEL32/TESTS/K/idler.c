/* idler : dort N secondes (mesure des acces E/S au repos, RUNPERF.SH) */
#include "ku.h"
int main(void){
  int n=ku_cmdline_has("idle16")?16:ku_cmdline_has("idle6")?6:3,i;
  puts("IDLE-START\n");
  for(i=0;i<n;i++){long ts[2]={1,0};nanosleep(ts,0);}
  puts("IDLE-END\n");
  return 0;
}
