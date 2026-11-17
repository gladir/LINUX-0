/* pipetest : pipe, FIFO, dup2, SIGPIPE, lectures bloquantes */
#include "ku.h"
static volatile int got_pipe;
static void onpipe(int s){got_pipe=s;}
int main(void){
  int f[2],st,p,n;char b[64];
  ktest("pipe.create",pipe(f)==0);
  p=fork();
  if(p==0){close(f[0]);write(f[1],"salut",5);write(f[1]," tube",5);close(f[1]);_exit(0);}
  close(f[1]);
  n=read(f[0],b,sizeof b);
  int m=0;if(n>0&&n<(int)sizeof b){m=read(f[0],b+n,sizeof b-n);if(m<0)m=0;}
  b[n+(n>0?m:0)]=0;
  ktest("pipe.data",(n+m)==10&&strcmp(b,"salut tube")==0);
  ktest("pipe.eof",read(f[0],b,10)==0);
  waitpid(p,&st,0);
  close(f[0]);
  pipe(f);close(f[0]);
  signal_set(SIGPIPE,onpipe,0);
  n=write(f[1],"x",1);
  ktest("pipe.epipe",n==-32&&got_pipe==SIGPIPE);
  close(f[1]);
  pipe(f);
  p=fork();
  if(p==0){close(f[0]);dup2(f[1],1);close(f[1]);puts("via dup2");_exit(0);}
  close(f[1]);
  n=read(f[0],b,sizeof b);b[n>0?n:0]=0;
  waitpid(p,&st,0);close(f[0]);
  ktest("pipe.dup2",strcmp(b,"via dup2")==0);
  ktest("fifo.mknod",mknod("/tmp/ff",0x1000|0600,0)==0);
  p=fork();
  if(p==0){int w=open("/tmp/ff",O_WRONLY,0);write(w,"fifo!",5);close(w);_exit(0);}
  int r=open("/tmp/ff",O_RDONLY,0);
  n=read(r,b,sizeof b);b[n>0?n:0]=0;close(r);waitpid(p,&st,0);
  ktest("fifo.data",strcmp(b,"fifo!")==0);
  unlink("/tmp/ff");
  pipe(f);fcntl(f[0],4,O_NONBLOCK);
  ktest("pipe.eagain",read(f[0],b,1)==-11);
  return ku_fail?1:0;
}
