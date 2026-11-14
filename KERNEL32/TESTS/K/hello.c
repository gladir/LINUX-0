/* hello : ecrit un message et verifie argc/argv/envp et uname */
#include "ku.h"
int main(int argc,char**argv,char**envp){
  char u[390];
  puts("Bonjour de LINUX-0 KERNEL32 (programme ELF i386 statique)\n");
  ktest("hello.argv",argc>=1&&argv[0]!=0);
  puts("  argv[0]=");puts(argv[0]);puts("\n");
  if(argc>1){puts("  argv[1]=");puts(argv[1]);puts("\n");}
  ktest("hello.envp",envp[0]!=0&&envp[0][0]=='P');
  uname(u);
  puts("  uname: ");puts(u);puts(" ");puts(u+65);puts(" ");puts(u+130);puts(" ");puts(u+195);puts(" ");puts(u+260);puts("\n");
  ktest("hello.uname",strcmp(u,"LINUX-0")==0&&strcmp(u+130,"KERNEL32")==0&&strcmp(u+260,"i386")==0);
  ktest("hello.getpid",getpid()>1);
  return 0;
}
