/* bdtest : peripherique bloc de plus de 2 Gio (disque AHCI creux de 8 Go,
   RUNBIG8G.SH) : _llseek, ecriture et relecture a 2 Gio, 4 Gio et en fin de
   disque, lseek sur un octet au-dela de 2 Gio */
#include "ku.h"
static long long llseek_(int fd,unsigned long long off,int wh){unsigned long long res=0;long r=sc5(140,fd,(unsigned)(off>>32),(unsigned)off,(long)&res,wh);return r<0?r:(long long)res;}
int main(void){
  int fd=open(ku_cmdline_has("k32nvme")?"/dev/nvme0n1":"/dev/sda",O_RDWR,0),i,ok;static unsigned char b[4096],c[4096];
  unsigned long long offs[4]={0x7FFFF000ULL,0x80000000ULL,0x100000000ULL,0};
  long long sz;
  if(fd<0){puts("  (pas de /dev/sda)\n");return 0;}
  sz=llseek_(fd,0,2);
  ktest("bd.llseek_end",sz>=4000000000LL);
  offs[3]=(unsigned long long)sz-4096;
  for(i=0;i<4;i++){int k;ok=1;
    for(k=0;k<4096;k++)b[k]=(unsigned char)(i*37+k*7+1);
    if(llseek_(fd,offs[i],0)!=(long long)offs[i])ok=0;
    if(write(fd,b,4096)!=4096)ok=0;
    memset(c,0,4096);
    if(llseek_(fd,offs[i],0)!=(long long)offs[i])ok=0;
    if(read(fd,c,4096)!=4096)ok=0;
    if(memcmp_(b,c,4096)!=0)ok=0;
    ktest(i==0?"bd.rw_2g_minus_4k":i==1?"bd.rw_2g":i==2?"bd.rw_4g":"bd.rw_end",ok);}
  /* lseek 32 bits au-dela de 2 Gio : doit rendre -EOVERFLOW ou la bonne valeur, jamais une valeur fausse */
  {long r=sc3(19,fd,0x7FFFFFFF,0);long r2=sc3(19,fd,1,1);ktest("bd.lseek32",r==0x7FFFFFFF&&(r2<0||r2==0x80000000L));}
  /* erreur d'E/S injectee (RUNAHCIERR.SH : blkdebug, une fois, secteur 100000) :
     le pilote doit remettre le port en etat et reessayer */
  if(ku_cmdline_has("aherr")){int k;ok=1;
    for(k=0;k<4096;k++)b[k]=(unsigned char)(k*11+5);
    if(llseek_(fd,100000ULL*512,0)!=100000LL*512)ok=0;
    if(write(fd,b,4096)!=4096)ok=0;
    memset(c,0,4096);
    if(llseek_(fd,100000ULL*512,0)!=100000LL*512)ok=0;
    if(read(fd,c,4096)!=4096)ok=0;
    ktest("bd.err_retry_data",ok&&memcmp_(b,c,4096)==0);
    sync();
    ktest("bd.after_error_io",ok&&llseek_(fd,0,0)==0&&read(fd,c,512)==512);}
  close(fd);
  puts("KTEST: bd DONE\n");
  return ku_fail?1:0;
}
