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
  /* AF_PACKET : requete ARP brute vers la passerelle (raw, dgram, ecoute) */
  {struct sll{unsigned short fam,proto;int idx;unsigned short hat;unsigned char pk,hl,ad[8];};
   struct sll ll,fr;unsigned char arp[28],fm[64],rb[128],mac[6],ifr[40];
   int ps,pd,pa,sx,got=0,gotd=0,out_seen=0,rep_seen=0,own_out=0,k2,ok=1,r2;
   sx=socket(2,2,0);memset(ifr,0,40);memcpy(ifr,"eth0",4);
   ktest("pkt.hwaddr",ioctl(sx,0x8927,(long)ifr)==0);memcpy(mac,ifr+18,6);close(sx);
   ps=socket(17,3,hs(0x0806));pd=socket(17,2,hs(0x0806));pa=socket(17,3,hs(3));
   ktest("pkt.sockets",ps>=0&&pd>=0&&pa>=0);
   ktest("pkt.type_einval",socket(17,1,hs(3))==-94);
   memset(&ll,0,sizeof ll);ll.fam=17;ll.proto=hs(0x0806);ll.idx=2;
   ktest("pkt.bind",bind(ps,&ll,sizeof ll)==0);
   { int al=sizeof fr;memset(&fr,0,sizeof fr);
     ktest("pkt.getsockname",getsockname(ps,&fr,&al)==0&&fr.fam==17&&fr.idx==2&&al==20&&fr.proto==hs(0x0806)); }
   memset(arp,0,28);arp[1]=1;arp[2]=8;arp[4]=6;arp[5]=4;arp[7]=1;memcpy(arp+8,mac,6);
   arp[14]=10;arp[15]=0;arp[16]=2;arp[17]=15;arp[24]=10;arp[25]=0;arp[26]=2;arp[27]=2;
   memset(fm,0xff,6);memcpy(fm+6,mac,6);fm[12]=8;fm[13]=6;memcpy(fm+14,arp,28);
   memset(&ll,0,sizeof ll);ll.fam=17;ll.idx=2;ll.hl=6;memset(ll.ad,0xff,6);
   ktest("pkt.raw_send",sendto(ps,fm,42,0,&ll,sizeof ll)==42);
   for(k2=0;k2<300&&!got;k2++){int al=sizeof fr;r2=recvfrom(ps,rb,sizeof rb,0x40,&fr,&al);
     if(r2>=42&&rb[12]==8&&rb[13]==6&&rb[21]==2&&rb[28]==10&&rb[31]==2){got=1;
       ktest("pkt.raw_reply_src",fr.fam==17&&fr.pk==0&&fr.hl==6&&fr.idx==2&&memcmp_(fr.ad,rb+6,6)==0&&memcmp_(rb,mac,6)==0);}
     else if(r2>0&&fr.pk==4)own_out=1;
     else if(r2<=0){long ts[2]={0,10000000};nanosleep(ts,0);}}
   ktest("pkt.raw_reply",got);
   ktest("pkt.no_own_copy",!own_out);
   for(k2=0;k2<100;k2++){int al=sizeof fr;r2=recvfrom(pa,rb,sizeof rb,0x40,&fr,&al);
     if(r2<=0)break;
     if(fr.pk==4&&r2>=42&&rb[12]==8&&rb[13]==6&&rb[21]==1&&memcmp_(rb+6,mac,6)==0)out_seen=1;
     if(fr.pk==0&&r2>=42&&rb[12]==8&&rb[13]==6&&rb[21]==2)rep_seen=1;}
   ktest("pkt.tap_outgoing",out_seen);
   ktest("pkt.tap_incoming",rep_seen);
   ll.proto=hs(0x0806);
   ktest("pkt.dgram_send",sendto(pd,arp,28,0,&ll,sizeof ll)==28);
   for(k2=0;k2<300&&!gotd;k2++){int al=sizeof fr;r2=recvfrom(pd,rb,sizeof rb,0x40,&fr,&al);
     if(r2>=28&&rb[7]==2&&rb[14]==10&&rb[17]==2)gotd=1;
     else if(r2<=0){long ts[2]={0,10000000};nanosleep(ts,0);}}
   ktest("pkt.dgram_reply",gotd);
   ktest("pkt.raw_short_emsgsize",sendto(ps,fm,5,0,&ll,sizeof ll)==-90);
   {int p=fork(),st=0;if(p==0){int x;sc1(23,1000);x=socket(17,3,hs(3));_exit(x==-1?0:1);}
    waitpid(p,&st,0);ktest("pkt.eperm_nonroot",st==0);}
   close(ps);close(pd);close(pa);(void)ok;(void)got;}
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
