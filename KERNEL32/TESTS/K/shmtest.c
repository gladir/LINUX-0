/* shmtest : mmap MAP_SHARED de fichiers (cache de pages), msync */
#include "ku.h"
#define SYS_msync 144
static int mkfile(const char*p,int n,char c){char b[4096];int fd=open(p,O_RDWR|O_CREAT|O_TRUNC,0644),i;memset(b,c,4096);
  for(i=0;i<n;i+=4096)write(fd,b,4096);return fd;}
int main(void){
  int fd,fd2,n,st,p;char b[16];volatile char*m,*m2;
  fd=mkfile("/tmp/shm1",8192,'A');
  m=mmap2(0,8192,3,1,fd,0);
  ktest("shm.mmap",(long)m>0||(long)m<-4096);
  ktest("shm.read_initial",m[0]=='A'&&m[8191]=='A');
  m[10]='B';
  lseek(fd,10,0);n=read(fd,b,1);
  ktest("shm.mmap_to_read",n==1&&b[0]=='B');
  lseek(fd,100,0);write(fd,"C",1);
  ktest("shm.write_to_mmap",m[100]=='C');
  ktest("shm.msync",sc3(SYS_msync,(long)m,8192,4)==0);
  p=fork();
  if(p==0){fd2=open("/tmp/shm1",O_RDWR,0);m2=mmap2(0,8192,3,1,fd2,0);m2[5000]='D';m2[0]='Z';_exit(0);}
  waitpid(p,&st,0);
  ktest("shm.shared_between_processes",m[5000]=='D'&&m[0]=='Z');
  lseek(fd,5000,0);n=read(fd,b,1);
  ktest("shm.child_write_visible_read",n==1&&b[0]=='D');
  munmap((void*)m,8192);
  close(fd);
  fd=open("/tmp/shm1",O_RDONLY,0);lseek(fd,10,0);read(fd,b,1);
  ktest("shm.persist_after_munmap",b[0]=='B');
  close(fd);
  /* mappage prive : le fichier ne change pas */
  fd=open("/tmp/shm1",O_RDWR,0);
  m=mmap2(0,4096,3,2,fd,0);
  m[20]='P';
  lseek(fd,20,0);read(fd,b,1);
  ktest("shm.private_not_written",b[0]=='A'&&m[20]=='P');
  munmap((void*)m,4096);
  /* mappage partage en lecture seule voit les ecritures */
  m=mmap2(0,4096,1,1,fd,0);
  lseek(fd,30,0);write(fd,"R",1);
  ktest("shm.readonly_sees_write",m[30]=='R');
  munmap((void*)m,4096);
  /* ecriture dans un mappage partage d'un fichier ouvert en lecture seule : refuse */
  close(fd);fd=open("/tmp/shm1",O_RDONLY,0);
  m=mmap2(0,4096,3,1,fd,0);
  ktest("shm.rw_on_ro_fd",(long)m<0&&(long)m>-4096);
  close(fd);
  unlink("/tmp/shm1");
  return ku_fail?1:0;
}
