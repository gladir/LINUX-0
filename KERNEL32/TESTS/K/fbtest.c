/* fbtest : framebuffer /dev/fb0 (carte Bochs VGA, noyau lance avec
   fb=1024x768) : ioctl d'information, lseek, write, read, limites. Dessine
   trois bandes (rouge, vert, bleu) et un pixel 123456h que RUNFB.SH verifie
   par une capture de l'ecran QEMU. Sans /dev/fb0 le test est ignore. */
#include "ku.h"
#define SYS_nanosleep 162
#define PROT_READ 1
#define PROT_WRITE 2
#define MAP_SHARED 1
static unsigned row[2560];
static unsigned char vi[160],fi[68];
int main(void){
  int fd,n,i,y,w,h;
  unsigned px;
  fd=open("/dev/fb0",O_RDWR,0);
  if(fd<0){puts("  (pas de /dev/fb0 : tests framebuffer ignores)\n");return 0;}
  ktest("fb.vscreeninfo",ioctl(fd,0x4600,(long)vi)==0);
  w=*(int*)vi;h=*(int*)(vi+4);
  ktest("fb.geometry",w>=320&&h>=200&&*(int*)(vi+24)==32&&*(int*)(vi+8)==w);
  ktest("fb.fscreeninfo",ioctl(fd,0x4602,(long)fi)==0&&*(unsigned*)(fi+48)==(unsigned)w*4
        &&*(unsigned*)(fi+20)==(unsigned)w*h*4&&memcmp_(fi,"BOCHS",5)==0);
  ktest("fb.ioctl_bad",ioctl(fd,0x1234,(long)vi)==-25);
  for(y=0;y<100;y++){
    for(i=0;i<w;i++)row[i]=i<w/3?0xFF0000:i<2*w/3?0x00FF00:0x0000FF;
    if(lseek(fd,y*w*4,0)!=y*w*4)break;
    if(write(fd,row,w*4)!=w*4)break;
  }
  ktest("fb.write_rows",y==100);
  px=0x123456;
  ktest("fb.lseek_pixel",lseek(fd,(200*w+100)*4,0)==(200*w+100)*4);
  ktest("fb.write_pixel",write(fd,&px,4)==4);
  lseek(fd,(200*w+100)*4,0);px=0;n=read(fd,&px,4);
  ktest("fb.read_back",n==4&&px==0x123456);
  lseek(fd,5*w*4,0);read(fd,row,w*4);
  ktest("fb.read_row",row[5]==0xFF0000&&row[w/2]==0x00FF00&&row[w-5]==0x0000FF);
  ktest("fb.seek_end",lseek(fd,0,2)==w*h*4&&write(fd,&px,4)==-28&&read(fd,&px,4)==0);
  ktest("fb.seek_bad",lseek(fd,-1,0)==-22);
  /* mmap : pixels visibles par le pointeur, ecriture par pointeur visible par read */
  {
    unsigned*m=(unsigned*)mmap2(0,w*h*4,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
    ktest("fb.mmap",(long)m>0&&(long)m!=-1);
    if((long)m>0){
      ktest("fb.mmap_read",m[5]==0xFF0000&&m[w/2]==0x00FF00&&m[200*w+100]==0x123456);
      m[300*w+50]=0xABCDEF;
      lseek(fd,(300*w+50)*4,0);px=0;read(fd,&px,4);
      ktest("fb.mmap_write",px==0xABCDEF);
      { int p=fork();
        if(p==0){m[301*w+50]=0x778899;_exit(0);}
        waitpid(p,0,0);
        ktest("fb.mmap_fork_shared",m[301*w+50]==0x778899); }
      for(i=0;i<w;i++)m[400*w+i]=0xFFFFFF;
      ktest("fb.munmap",munmap(m,w*h*4)==0);
    }
    ktest("fb.mmap_bad_range",(long)mmap2(0,w*h*4+8192,PROT_READ,MAP_SHARED,fd,0)<0);
    
  }
  puts("fb DRAWN\n");
  {long req[2]={4,0};nanosleep(req,0);}
  close(fd);
  return 0;
}
