/* nettest : reseau reel (RTL8139) : ping, UDP, TCP client et serveur.
   Actif seulement avec k32net sur la ligne de commande : RUNNET.SH lance le
   serveur hote (10.0.2.2:9091 TCP, 9092 UDP) et la redirection
   127.0.0.1:5556 -> invite:7777. */
#include "ku.h"
#include "kusock.h"
static unsigned short hs(unsigned short v){return (v>>8)|(v<<8);}
static void mksin(struct sin*a,unsigned ip,int port){memset(a,0,sizeof *a);a->fam=2;a->port=hs(port);a->addr=ip;}
#define HOST 0x0202000a
int main(void){
  char cl[256];int fdc=open("/proc/cmdline",O_RDONLY,0),m=0,k,found=0;
  int s,n,i,l;char b[4096];struct sin a,f;
  if(fdc>=0){m=read(fdc,cl,sizeof cl-1);close(fdc);}
  for(k=0;k+6<=m;k++)if(memcmp_(cl+k,"k32net",6)==0)found=1;
  if(!found){puts("  (reseau : essai ignore, voir RUNNET.SH)\n");return 0;}
  /* ICMP : ping de la passerelle */
  {unsigned char pk[16],rb[64];memset(pk,0,16);pk[0]=8;pk[4]=0x55;pk[5]=0x66;pk[7]=1;memcpy(pk+8,"pingdata",8);
   {unsigned sum=0;for(i=0;i<16;i+=2)sum+=(pk[i]<<8)|pk[i+1];while(sum>>16)sum=(sum&0xffff)+(sum>>16);sum=~sum&0xffff;pk[2]=sum>>8;pk[3]=sum&255;}
   s=socket(2,3,1);mksin(&a,HOST,0);
   ktest("net.ping_send",sendto(s,pk,16,0,&a,16)==16);
   n=0;for(i=0;i<300&&n<=0;i++){l=sizeof f;n=recvfrom(s,rb,64,0x40,&f,&l);if(n<=0){long ts[2]={0,10000000};nanosleep(ts,0);}}
   ktest("net.ping_reply",n==36&&rb[20]==0&&rb[24]==0x55&&f.addr==HOST);
   close(s);}
  /* UDP */
  s=socket(2,2,0);mksin(&a,HOST,9092);
  ktest("net.udp_send",sendto(s,"udp-hello",9,0,&a,16)==9);
  n=0;for(i=0;i<300&&n<=0;i++){l=sizeof f;n=recvfrom(s,b,100,0x40,&f,&l);if(n<=0){long ts[2]={0,10000000};nanosleep(ts,0);}}
  ktest("net.udp_echo",n==9&&memcmp_(b,"udp-hello",9)==0&&hs(f.port)==9092);
  close(s);
  /* TCP client */
  s=socket(2,1,0);mksin(&a,HOST,9091);
  ktest("net.tcp_connect",connect(s,&a,16)==0);
  write(s,"tcp-hello\n",10);n=read(s,b,sizeof b);
  ktest("net.tcp_echo",n==10&&memcmp_(b,"tcp-hello\n",10)==0);
  {char big[8192];int tot=0,ok=1;unsigned sum=0;
   for(i=0;i<8192;i++)big[i]=i*7;
   write(s,"BULK\n",5);
   for(i=0;i<40;i++){if(write(s,big,8192)!=8192){ok=0;break;}tot+=8192;}
   ktest("net.tcp_bulk_send",ok&&tot==327680);
   n=read(s,b,64);b[n>0?n:0]=0;
   ktest("net.tcp_bulk_ack",n>0&&memcmp_(b,"OK 327680",9)==0);
   write(s,"SEND\n",5);tot=0;
   while(tot<500000){n=read(s,b,sizeof b);if(n<=0)break;for(i=0;i<n;i++)sum+=(unsigned char)b[i]*(unsigned)(tot+i+1);tot+=n;}
   ktest("net.tcp_bulk_recv",tot==500000&&sum==2923836960u);}
  shutdown(s,1);
  ktest("net.tcp_eof",read(s,b,10)==0);
  close(s);
  s=socket(2,1,0);mksin(&a,HOST,9099);
  ktest("net.tcp_refused",connect(s,&a,16)==-111);
  close(s);
  /* TCP serveur : l'hote se connecte par la redirection */
  {int ls=socket(2,1,0),c;mksin(&a,0,7777);
   ktest("net.listen",bind(ls,&a,16)==0&&listen(ls,4)==0);
   puts("NET-LISTENING\n");
   c=-1;for(i=0;i<600&&c<0;i++){c=accept(ls,&f,&l);if(c<0){long ts[2]={0,10000000};nanosleep(ts,0);fcntl(ls,4,0x800);}}
   ktest("net.accept",c>=0);
   if(c>=0){n=read(c,b,sizeof b);
    ktest("net.server_read",n==8&&memcmp_(b,"ping-in\n",8)==0);
    write(c,"pong-in\n",8);
    {long ts[2]={0,300000000};nanosleep(ts,0);}
    close(c);}
   close(ls);}
  puts("NET-DONE\n");
  return ku_fail?1:0;
}
