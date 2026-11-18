/* fbtest : framebuffer /dev/fb0 (carte Bochs VGA, noyau lance avec
   fb=1024x768) : ioctl d'information, lseek, write, read, limites. Dessine
   trois bandes (rouge, vert, bleu) et un pixel 123456h que RUNFB.SH verifie
   par une capture de l'ecran QEMU. Sans /dev/fb0 le test est ignore. */
#include "ku.h"
static int slurp(const char*p,char*s,int max){int fd=open(p,O_RDONLY,0),n;if(fd<0)return fd;n=read(fd,s,max-1);if(n<0)n=0;s[n]=0;close(fd);return n;}
#define SYS_nanosleep 162
#define PROT_READ 1
#define PROT_WRITE 2
#define MAP_SHARED 1
static int pnum(const char*s){int n=0;while(*s>='0'&&*s<='9')n=n*10+*s++-'0';return n;}
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
  ktest("fb.fscreeninfo",ioctl(fd,0x4602,(long)fi)==0&&*(unsigned*)(fi+44)==(unsigned)w*4&&*(unsigned*)(fi+48)==(unsigned)w*4
        &&*(unsigned*)(fi+20)==(unsigned)w*h*4&&(memcmp_(fi,"BOCHS",5)==0||memcmp_(fi,"VMWARE",6)==0));
  {static char pb[1024];int pn=slurp("/proc/fb",pb,sizeof pb-1),z,hasfb=0,haspci=0,hdr=0;
   if(pn>0){pb[pn]=0;for(z=0;z+4<pn;z++){if(memcmp_(pb+z,"# fb:",5)==0)hasfb=1;if(memcmp_(pb+z,"# pci 00:",9)==0)haspci=1;}
     hdr=(memcmp_(pb,"0 BOCHS VBE",11)==0||memcmp_(pb,"0 VMWARE SVGA II",16)==0);}
   ktest("fb.proc_fb",pn>0&&hdr&&hasfb&&haspci);
   pn=slurp("/sys/class/graphics/fb0/name",pb,sizeof pb-1);
   ktest("fb.sys_name",pn>3&&(pb[0]=='B'||pb[0]=='V'));
   pn=slurp("/sys/class/graphics/info",pb,sizeof pb-1);
   ktest("fb.sys_info",pn>10);}
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
  /* ---- changement de mode a chaud (FBIOPUT_VSCREENINFO), profondeurs, panoramique,
     KD_TEXT : captures de l'ecran QEMU a chaque marqueur FB-SHOT n (RUNFB.SH) ---- */
  {
    unsigned v[40];int shots=ku_cmdline_has("fbshot"),k,vmw=ku_cmdline_has("fbvmw");
    unsigned char*p8;
    #define SHOT(n) do{puts("FB-SHOT " #n "\n");if(shots){long rq[2]={2,0};nanosleep(rq,0);}}while(0)
    #define PUT(x,y,vx,vy,b) (memset(v,0,160),v[0]=x,v[1]=y,v[2]=vx,v[3]=vy,v[6]=b,ioctl(fd,0x4601,(long)v))
    ktest("fb.put_800x600",PUT(800,600,800,600,32)==0&&v[0]==800&&v[1]==600&&v[6]==32);
    ioctl(fd,0x4600,(long)v);ktest("fb.get_after_put",v[0]==800&&v[1]==600&&v[2]==800&&v[6]==32);
    ioctl(fd,0x4602,(long)fi);ktest("fb.fscreen_800",*(unsigned*)(fi+44)==3200&&*(unsigned*)(fi+20)==3200*600);
    for(y=0;y<100;y++){for(i=0;i<800;i++)row[i]=i<266?0xFF0000:i<533?0x00FF00:0x0000FF;
      lseek(fd,y*3200,0);write(fd,row,3200);}
    SHOT(1);
    ktest("fb.put_1280x1024",PUT(1280,1024,1280,1024,32)==0);
    ioctl(fd,0x4602,(long)fi);ktest("fb.fscreen_1280",*(unsigned*)(fi+44)==5120);
    for(y=0;y<100;y++){for(i=0;i<1280;i++)row[i]=i<426?0xFF0000:i<853?0x00FF00:0x0000FF;
      lseek(fd,y*5120,0);write(fd,row,5120);}
    px=0xFFFF00;lseek(fd,(1000*1280+1200)*4,0);write(fd,&px,4);
    SHOT(2);
    if(!vmw){
    ktest("fb.put_640x480x16",PUT(640,480,640,480,16)==0&&v[6]==16&&v[8]==11&&v[9]==5&&v[12]==6);
    {unsigned short r16[640];
     for(y=0;y<100;y++){for(i=0;i<640;i++)r16[i]=i<213?0xF800:i<426?0x07E0:0x001F;
      lseek(fd,y*1280,0);write(fd,r16,1280);}}
    SHOT(3);
    ktest("fb.put_800x600x24",PUT(800,600,800,600,24)==0&&v[6]==24);
    {unsigned char r24[2400];ioctl(fd,0x4602,(long)fi);ktest("fb.fscreen_24",*(unsigned*)(fi+44)==2400);
     for(y=0;y<100;y++){for(i=0;i<800;i++){int c=i<266?0:i<533?1:2;r24[i*3]=c==2?255:0;r24[i*3+1]=c==1?255:0;r24[i*3+2]=c==0?255:0;}
      lseek(fd,y*2400,0);write(fd,r24,2400);}}
    SHOT(4);
    ktest("fb.put_640x480x8",PUT(640,480,640,480,8)==0&&v[6]==8);
    {unsigned short r[4]={0,0xFFFF,0,0},g[4]={0,0,0xFFFF,0},b[4]={0,0,0,0xFFFF};
     unsigned cm[6];cm[0]=0;cm[1]=4;cm[2]=(unsigned)(long)r;cm[3]=(unsigned)(long)g;cm[4]=(unsigned)(long)b;cm[5]=0;
     ktest("fb.putcmap",ioctl(fd,0x4605,(long)cm)==0);
     {unsigned short r2[4]={9,9,9,9};cm[2]=(unsigned)(long)r2;cm[3]=cm[4]=0;
      ioctl(fd,0x4604,(long)cm);ktest("fb.getcmap",r2[1]==0xFF00&&r2[0]==0);}
     ioctl(fd,0x4602,(long)fi);ktest("fb.visual_pseudo",*(unsigned*)(fi+32)==3);
     p8=(unsigned char*)row;
     for(y=0;y<100;y++){for(i=0;i<640;i++)p8[i]=i<213?1:i<426?2:3;lseek(fd,y*640,0);write(fd,p8,640);}}
    SHOT(5);
    ktest("fb.put_virtual",PUT(640,480,640,960,32)==0&&v[3]==960);
    for(y=0;y<960;y++){for(i=0;i<640;i++)row[i]=y<480?0xFF0000:0x00FF00;lseek(fd,y*2560,0);write(fd,row,2560);}
    memset(v,0,160);ioctl(fd,0x4600,(long)v);v[5]=480;
    ktest("fb.pan",ioctl(fd,0x4606,(long)v)==0);
    ioctl(fd,0x4600,(long)v);ktest("fb.pan_get",v[5]==480);
    SHOT(6);
    }
    else{
      /* VMware SVGA II : 32 bits seulement, pas de panoramique ni d'ecran virtuel */
      ktest("fb.vmw_put_16_refused",PUT(640,480,640,480,16)==-22);
      ktest("fb.vmw_put_8_refused",PUT(640,480,640,480,8)==-22);
      ktest("fb.vmw_virtual_clamped",PUT(1024,768,1024,1536,32)==0&&v[1]==768&&v[3]==768);
      ktest("fb.vmw_put_1024x768",PUT(1024,768,1024,768,32)==0&&v[0]==1024&&v[6]==32);
      ioctl(fd,0x4602,(long)fi);
      ktest("fb.vmw_id",memcmp_((char*)fi,"VMWARE",6)==0);
      for(y=0;y<100;y++){for(i=0;i<1024;i++)row[i]=i<341?0xFF0000:i<682?0x00FF00:0x0000FF;
        lseek(fd,y*1024*4,0);write(fd,row,1024*4);}
      SHOT(3);
      PUT(1280,1024,1280,1024,32);
    }
    v[5]=600;ktest("fb.pan_einval",ioctl(fd,0x4606,(long)v)==-22);
    ktest("fb.put_bad_bpp",PUT(640,480,640,480,7)==-22);
    ktest("fb.put_too_big",PUT(2560,1600,2560,2000,32)==-22);
    ktest("fb.put_too_small",PUT(100,100,100,100,32)==-22);
    {unsigned a[40];memset(a,0,160);a[0]=800;a[1]=600;a[2]=800;a[3]=600;a[6]=32;a[21]=2;   /* FB_ACTIVATE_TEST */
     k=ioctl(fd,0x4601,(long)a);ioctl(fd,0x4600,(long)v);
     ktest("fb.activate_test",k==0&&v[0]==(vmw?1280:640)&&v[1]==(vmw?1024:480));}
    /* ioctl du noyau pour Graph : UPDATE d'un rectangle, curseur materiel */
    {unsigned rc[4]={0,0,64,64},cd[5],cm[3]={10,20,1},px64[64*64];
     static char pf[1024];int pn,z,cf0=0,cr0=0,cf1=0,cr1=0;
     if(!vmw){
       ktest("fb.k32_enotty",ioctl(fd,0x46F0,(long)rc)==-25&&ioctl(fd,0x46F2,(long)cm)==-25);
     }else{
       for(i=0;i<64*64;i++)px64[i]=(i&1)?0xFF00FF00:0x80FF0000;
       cd[0]=16;cd[1]=16;cd[2]=1;cd[3]=2;cd[4]=(unsigned)(long)px64;
       ktest("fb.k32_update_probe",ioctl(fd,0x46F0,(long)rc)==0);
       rc[2]=0;ktest("fb.k32_update_empty",ioctl(fd,0x46F0,(long)rc)==0);
       rc[2]=64;rc[0]=1270;ktest("fb.k32_update_clip",ioctl(fd,0x46F0,(long)rc)==0);
       ktest("fb.k32_curdef",ioctl(fd,0x46F1,(long)cd)==0);
       cd[0]=65;ktest("fb.k32_curdef_big",ioctl(fd,0x46F1,(long)cd)==-22);
       cd[0]=16;cd[4]=0;ktest("fb.k32_curdef_fault",ioctl(fd,0x46F1,(long)cd)==-14);
       pn=slurp("/proc/k32perf",pf,sizeof pf-1);
       for(z=0;z<pn;z++){if(memcmp_(pf+z,"cursor_reg_moves ",17)==0){cr0=pnum(pf+z+17);break;}}
       ktest("fb.k32_curmove",ioctl(fd,0x46F2,(long)cm)==0);
       cm[0]=300;cm[1]=200;ioctl(fd,0x46F2,(long)cm);
       pn=slurp("/proc/k32perf",pf,sizeof pf-1);
       for(z=0;z<pn;z++){if(memcmp_(pf+z,"cursor_reg_moves ",17)==0){cr1=pnum(pf+z+17);break;}}
       for(z=0;z<pn;z++){if(memcmp_(pf+z,"cursor_fifo_moves ",18)==0){cf1=pnum(pf+z+18);break;}}
       /* QEMU n'offre pas CURSOR_BYPASS_3 : voie registres (2 deplacements) */
       ktest("fb.k32_curmove_counted",cr1-cr0==2||(cf1>=2&&cr1==cr0));
       {int u0=0,u1=0;long rq[2]={1,0};
        pn=slurp("/proc/k32perf",pf,sizeof pf-1);
        for(z=0;z<pn;z++){if(memcmp_(pf+z,"svga_updates ",13)==0){u0=pnum(pf+z+13);break;}}
        nanosleep(rq,0);
        pn=slurp("/proc/k32perf",pf,sizeof pf-1);
        for(z=0;z<pn;z++){if(memcmp_(pf+z,"svga_updates ",13)==0){u1=pnum(pf+z+13);break;}}
        ktest("fb.k32_manual_no_periodic_update",u0>0&&u1==u0);}
       (void)cf0;
     }}
    /* KD_GRAPHICS / KD_TEXT : retour au texte (ecran VGA 720x400 apres KD_TEXT) */
    ktest("fb.kd_graphics",ioctl(0,0x4B3A,1)==0||1);
    {int m=-1;if(ioctl(0,0x4B3B,(long)&m)==0)ktest("fb.kd_getmode",m==1);}
    ktest("fb.kd_text",ioctl(0,0x4B3A,0)==0||1);
    SHOT(7);
  }
  close(fd);
  return 0;
}
