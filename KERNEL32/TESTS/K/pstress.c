/* pstress : charge parallele (noyau preemptible) : NW processus font en meme
   temps des E/S de fichiers avec sommes de controle (ext2 sur /dev/hda1
   monte en /mnt, sinon /tmp), des tubes avec fork, des mmap anonymes, des
   paires de sockets AF_UNIX et une connexion TCP en bouclage. Chaque
   processus verifie ses donnees ; le pere compte les echecs. Les fichiers
   ecrits sur ext2 sont verifies ensuite par e2fsck (RUNPREEMPT.SH). */
#include "ku.h"
#include "kusock.h"
#define SYS_gettimeofday 78
#define MAP_PRIVATE 2
#define MAP_ANONYMOUS 0x20
#define PROT_READ 1
#define PROT_WRITE 2
#define NW 6
#define SECS 4
static long us(void){long tv[2];sc2(SYS_gettimeofday,(long)tv,0);return tv[0]*1000000+tv[1];}
static unsigned sum(const unsigned char*b,int n,unsigned s){int i;for(i=0;i<n;i++)s=s*31+b[i];return s;}
static void fill(unsigned char*b,int n,unsigned seed){int i;for(i=0;i<n;i++){seed=seed*1103515245u+12345u;b[i]=seed>>16;}}
static unsigned char buf[8192],buf2[8192];
static void num(char*d,const char*pre,int n,const char*post){
  int k=0,m=0;char t[12];
  while(pre[k]){d[k]=pre[k];k++;}
  if(!n)t[m++]='0';
  while(n>0){t[m++]='0'+n%10;n/=10;}
  while(m>0)d[k++]=t[--m];
  strcpy_(d+k,post);
}
static int worker(int w,const char*dir){
  long t0=us();
  int iter=0,bad=0;
  char fn[64];
  num(fn,dir,w,".dat");
  while(us()-t0<SECS*1000000L){
    int phase=iter%5,i;
    unsigned seed=w*1000+iter;
    if(phase==0){          /* fichier : ecriture, relecture, somme */
      int fd=open(fn,O_RDWR|O_CREAT|O_TRUNC,0644),k;unsigned s1=0,s2=0;
      if(fd<0){bad++;continue;}
      for(k=0;k<24;k++){fill(buf,sizeof buf,seed+k);s1=sum(buf,sizeof buf,s1);if(write(fd,buf,sizeof buf)!=sizeof buf)bad++;}
      lseek(fd,0,0);
      for(k=0;k<24;k++){if(read(fd,buf2,sizeof buf2)!=sizeof buf2){bad++;break;}s2=sum(buf2,sizeof buf2,s2);}
      close(fd);
      if(s1!=s2)bad++;
    }else if(phase==1){    /* fork + tube */
      int q[2],p;unsigned s1=0,s2=0;
      pipe(q);
      p=fork();
      if(p==0){
        int k;close(q[0]);
        for(k=0;k<8;k++){fill(buf,4096,seed+k);write(q[1],buf,4096);}
        _exit(0);
      }
      close(q[1]);
      for(i=0;i<8;i++){fill(buf,4096,seed+i);s1=sum(buf,4096,s1);}
      {int got=0,n;while(got<8*4096&&(n=read(q[0],buf2,4096))>0){s2=sum(buf2,n,s2);got+=n;}
       if(got!=8*4096)bad++;}
      close(q[0]);
      {int st;waitpid(p,&st,0);if(st!=0)bad++;}
      if(s1!=s2)bad++;
    }else if(phase==2){    /* mmap anonyme */
      unsigned char*m=(unsigned char*)mmap2(0,64*4096,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
      if((long)m<=0){bad++;continue;}
      for(i=0;i<64;i++){m[i*4096]=(unsigned char)(seed+i);m[i*4096+4095]=(unsigned char)(i^w);}
      for(i=0;i<64;i++)if(m[i*4096]!=(unsigned char)(seed+i)||m[i*4096+4095]!=(unsigned char)(i^w))bad++;
      munmap(m,64*4096);
    }else if(phase==3){    /* socketpair AF_UNIX */
      int sv[2],p;unsigned s1=0,s2=0;
      if(socketpair(1,1,0,sv)!=0){bad++;continue;}
      p=fork();
      if(p==0){int n;close(sv[0]);while((n=read(sv[1],buf2,sizeof buf2))>0)write(sv[1],buf2,n);_exit(0);}
      close(sv[1]);
      for(i=0;i<6;i++){
        int got=0,n;fill(buf,2000,seed+i);s1=sum(buf,2000,s1);
        write(sv[0],buf,2000);
        while(got<2000&&(n=read(sv[0],buf2+got,2000-got))>0)got+=n;
        if(got!=2000)bad++;else s2=sum(buf2,2000,s2);
      }
      close(sv[0]);{int st;waitpid(p,&st,0);}
      if(s1!=s2)bad++;
    }else{                 /* TCP en bouclage */
      struct{short f;unsigned short p;unsigned a;char z[8];}sa;
      int ls=socket(2,1,0),al=16,port=20000+w*7+(iter%5),p;
      unsigned s1=0,s2=0;
      memset(&sa,0,sizeof sa);sa.f=2;sa.p=(port>>8)|((port&255)<<8);sa.a=0x0100007f;
      if(ls<0||bind(ls,&sa,16)!=0||listen(ls,2)!=0){bad++;if(ls>=0)close(ls);continue;}
      p=fork();
      if(p==0){
        int c=accept(ls,0,0),n;close(ls);
        if(c<0)_exit(1);
        while((n=read(c,buf2,sizeof buf2))>0)write(c,buf2,n);
        _exit(0);
      }
      close(ls);
      {int c=socket(2,1,0),k;
       if(c<0||connect(c,&sa,16)!=0){bad++;if(c>=0)close(c);}
       else{
        for(k=0;k<4;k++){int got=0,n;fill(buf,3000,seed+k);s1=sum(buf,3000,s1);write(c,buf,3000);
          while(got<3000&&(n=read(c,buf2+got,3000-got))>0)got+=n;
          if(got!=3000)bad++;else s2=sum(buf2,3000,s2);}
        close(c);
        if(s1!=s2)bad++;}}
      {int st;waitpid(p,&st,0);}
      (void)al;
    }
    iter++;
  }
  return bad;
}
int main(void){
  int w,fd,ext=0,bad=0,st,pids[NW];
  char b[8];
  const char*dir="/tmp/ps_";
  fd=open("/dev/hda1",O_RDONLY,0);
  if(fd>=0){lseek(fd,1024+56,0);if(read(fd,b,2)==2&&(unsigned char)b[0]==0x53&&(unsigned char)b[1]==0xEF)ext=1;close(fd);}
  if(ext&&mount("/dev/hda1","/mnt","ext2",0,0)==0){mkdir("/mnt/ps",0755);dir="/mnt/ps/w";}else ext=0;
  for(w=0;w<NW;w++){
    pids[w]=fork();
    if(pids[w]==0){int r=worker(w,dir);_exit(r>0?1:0);}
  }
  for(w=0;w<NW;w++){waitpid(pids[w],&st,0);if(st!=0)bad++;}
  ktest("pstress.workers_ok",bad==0);
  if(ext){sync();ktest("pstress.umount",umount("/mnt")==0);}
  {char sb[2048];int f=open("/proc/stat",O_RDONLY,0),n,i;
   if(f>=0){n=read(f,sb,sizeof sb-1);close(f);if(n>0){sb[n]=0;
     for(i=0;i<n;i++)if(sb[i]=='k'&&memcmp_(sb+i,"kpreempt ",9)==0){int j=i;while(sb[j]&&sb[j]!='\n')j++;sb[j]=0;puts("pstress ");puts(sb+i);puts("\n");break;}}}}
  puts("pstress DONE\n");
  return 0;
}
