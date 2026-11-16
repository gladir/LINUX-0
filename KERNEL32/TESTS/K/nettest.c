/* nettest : reseau reel (RTL8139) : ping, UDP, TCP client et serveur.
   Actif seulement avec k32net sur la ligne de commande : RUNNET.SH lance le
   serveur hote (10.0.2.2:9091 TCP, 9092 UDP) et la redirection
   127.0.0.1:5556 -> invite:7777. */
#include "ku.h"
#include "kusock.h"
static unsigned short hs(unsigned short v){return (v>>8)|(v<<8);}
static void mksin(struct sin*a,unsigned ip,int port){memset(a,0,sizeof *a);a->fam=2;a->port=hs(port);a->addr=ip;}
#define HOST 0x0202000a
static unsigned short ipcs(const unsigned char*p,int n){unsigned s=0;while(n>1){s+=(p[0]<<8)|p[1];p+=2;n-=2;}if(n)s+=p[0]<<8;while(s>>16)s=(s&0xffff)+(s>>16);return (unsigned short)~s;}
/* paquet IPv4 : proto, source, destination (octets), charge utile */
static int mkip(unsigned char*pk,int proto,const unsigned char*src,const unsigned char*dst,const unsigned char*pl,int plen){
  int c;memset(pk,0,20);pk[0]=0x45;pk[2]=(20+plen)>>8;pk[3]=(20+plen)&255;pk[6]=0x40;pk[8]=64;pk[9]=proto;
  memcpy(pk+12,src,4);memcpy(pk+16,dst,4);c=ipcs(pk,20);pk[10]=c>>8;pk[11]=c&255;memcpy(pk+20,pl,plen);return 20+plen;}
/* ifreq pour ioctl d'interface : nom, adresse IPv4 en octets */
static void mkifr(unsigned char*r,const char*nm,const unsigned char*ad){
  memset(r,0,40);memcpy(r,nm,5);if(ad){r[16]=2;memcpy(r+20,ad,4);}}
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
  /* netfilter : table filter par setsockopt(SOL_IP) sur une socket brute IPPROTO_RAW */
  {
    static unsigned char tb[4096];
    int rs=socket(2,3,255),nt,off,rl;
    #define PUT16(o,v) (*(unsigned short*)(tb+(o))=(v))
    #define PUT32(o,v) (*(unsigned*)(tb+(o))=(v))
    /* regle UDP (udp match 40 octets) + cible standard 40 */
    #define RULE(base,sport0,sport1,dport0,dport1,verd) do{ \
      memset(tb+(base),0,192);PUT16((base)+80,17);PUT16((base)+88,112+40);PUT16((base)+90,192); \
      PUT16((base)+112,40);memcpy(tb+(base)+114,"udp",4); \
      PUT16((base)+144,sport0);PUT16((base)+146,sport1);PUT16((base)+148,dport0);PUT16((base)+150,dport1); \
      PUT16((base)+152,40);PUT32((base)+184,(unsigned)(verd));}while(0)
    #define POLICY(base) do{memset(tb+(base),0,152);PUT16((base)+88,112);PUT16((base)+90,152);PUT16((base)+112,40);PUT32((base)+144,(unsigned)-2);}while(0)
    /* tb[0..91] : en-tete ipt_replace ; entrees a partir de 92 */
    #define BUILD(inrule,outrule,sp0,sp1,dp0,dp1) do{ int o=92,hin,hfw,hou,uin,ufw,uou; \
      memset(tb,0,92);memcpy(tb,"filter",7); \
      hin=0;if(inrule){RULE(o,sp0,sp1,dp0,dp1,-1);o+=192;}uin=o-92;POLICY(o);o+=152; \
      hfw=o-92;ufw=hfw;POLICY(o);o+=152; \
      hou=o-92;if(outrule){RULE(o,sp0,sp1,dp0,dp1,-1);o+=192;}uou=o-92;POLICY(o);o+=152; \
      memset(tb+o,0,176);PUT16(o+88,112);PUT16(o+90,176);PUT16(o+112,64);memcpy(tb+o+114,"ERROR",6);o+=176; \
      PUT32(32,0xE);PUT32(36,2+(inrule?1:0)+(outrule?1:0)+1+1);PUT32(40,o-92); \
      PUT32(44+4,hin);PUT32(44+8,hfw);PUT32(44+12,hou);PUT32(64+4,uin);PUT32(64+8,ufw);PUT32(64+12,uou); \
      off=o;}while(0)
    ktest("nf.socket",rs>=0);
    {unsigned char gi[84];int gl=84;memset(gi,0,84);memcpy(gi,"filter",7);
     nt=getsockopt(rs,0,64,gi,&gl);
     ktest("nf.get_info_default",nt==0&&*(unsigned*)(gi+32)==0xE&&*(unsigned*)(gi+76)==3);}
    BUILD(0,1,0,65535,9092,9092);
    ktest("nf.replace_output_drop",setsockopt(rs,0,64,tb,off)==0);
    {long ts[2]={0,0};(void)ts;}
    sendto(s=socket(2,2,0),"nf-out",6,0,&a,16);
    n=0;for(i=0;i<60&&n<=0;i++){l=sizeof f;n=recvfrom(s,b,100,0x40,&f,&l);if(n<=0){long ts[2]={0,10000000};nanosleep(ts,0);}}
    ktest("nf.output_dropped",n<=0);
    {static unsigned char ge[8192];int gl=36+2000;memset(ge,0,sizeof ge);memcpy(ge,"filter",7);
     {unsigned char gi[84];int gl2=84;memset(gi,0,84);memcpy(gi,"filter",7);getsockopt(rs,0,64,gi,&gl2);*(unsigned*)(ge+32)=*(unsigned*)(gi+80);gl=36+*(unsigned*)(gi+80);}
     nt=getsockopt(rs,0,65,ge,&gl);
     {unsigned long long pc=0;int po=36+ *(unsigned*)(tb+44+12)+ 0;pc=*(unsigned*)(ge+po+96);
      ktest("nf.get_entries_counter",nt==0&&pc>=1);}}
    close(s);
    BUILD(1,0,9092,9092,0,65535);
    ktest("nf.replace_input_drop",setsockopt(rs,0,64,tb,off)==0);
    sendto(s=socket(2,2,0),"nf-in",5,0,&a,16);
    n=0;for(i=0;i<60&&n<=0;i++){l=sizeof f;n=recvfrom(s,b,100,0x40,&f,&l);if(n<=0){long ts[2]={0,10000000};nanosleep(ts,0);}}
    ktest("nf.input_dropped",n<=0);close(s);
    BUILD(0,0,0,0,0,0);
    ktest("nf.replace_default",setsockopt(rs,0,64,tb,off)==0);
    sendto(s=socket(2,2,0),"nf-ok",5,0,&a,16);
    n=0;for(i=0;i<300&&n<=0;i++){l=sizeof f;n=recvfrom(s,b,100,0x40,&f,&l);if(n<=0){long ts[2]={0,10000000};nanosleep(ts,0);}}
    ktest("nf.accept_after_flush",n==5&&memcmp_(b,"nf-ok",5)==0);close(s);
    memcpy(tb,"nat",4);
    ktest("nf.nat_unsupported",setsockopt(rs,0,64,tb,off)==-2);
    BUILD(0,0,0,0,0,0);tb[92+112+2]='x';  /* correspondance inconnue : sur la 1re entree (politique) cible nommee */
    ktest("nf.bad_target",setsockopt(rs,0,64,tb,off)==-2);
    ktest("nf.nonroot_eperm",({int pp=fork(),st=0;if(pp==0){int r2;sc1(23,1000);r2=socket(2,3,255);_exit(r2==-1?0:1);}waitpid(pp,&st,0);st==0;}));
    (void)rl;
    close(rs);
  }
  /* tun/tap : interface tun0 en 192.168.77.1/24 ; un "hote" 192.168.77.2
     ecrit et lit par /dev/net/tun */
  {
    int tf=open("/dev/net/tun",O_RDWR|0x800,0),sk=socket(2,2,0),r,t,got;
    static unsigned char ifr[40],pk[256],rb[2048],pl[64],tb[4096];
    unsigned char me[4]={192,168,77,1},lan[4]={192,168,77,2},mk[4]={255,255,255,0},hostip[4]={10,0,2,2};
    int rs=socket(2,3,255),off;
    memset(ifr,0,40);*(unsigned short*)(ifr+16)=0x1001;     /* IFF_TUN | IFF_NO_PI */
    r=ioctl(tf,0x400454CA,(long)ifr);
    ktest("tun.setiff",tf>=0&&r==0&&memcmp_(ifr,"tun0",5)==0);
    mkifr(ifr,"tun0",me);r=ioctl(sk,0x8916,(long)ifr);
    mkifr(ifr,"tun0",mk);r|=ioctl(sk,0x891C,(long)ifr);
    mkifr(ifr,"tun0",0);*(unsigned short*)(ifr+16)=1;r|=ioctl(sk,0x8914,(long)ifr);
    ktest("tun.configure",r==0);
    mkifr(ifr,"tun0",0);ioctl(sk,0x8915,(long)ifr);
    ktest("tun.getaddr",memcmp_(ifr+20,me,4)==0);
    mkifr(ifr,"tun0",0);ioctl(sk,0x8933,(long)ifr);
    ktest("tun.ifindex",*(int*)(ifr+16)==3);
    mkifr(ifr,"tun0",0);ioctl(sk,0x8913,(long)ifr);
    ktest("tun.flags_up",(*(unsigned short*)(ifr+16)&1)!=0);
    /* ping de l'hote LAN vers 192.168.77.1 : reponse lue sur tun0 */
    memset(pl,0,16);pl[0]=8;pl[4]=0x12;pl[5]=0x34;pl[7]=1;memcpy(pl+8,"tunping!",8);
    {int c=ipcs(pl,16);pl[2]=c>>8;pl[3]=c&255;}
    r=mkip(pk,1,lan,me,pl,16);
    ktest("tun.write",write(tf,pk,r)==r);
    got=-1;for(t=0;t<100&&got<0;t++){int n=read(tf,rb,sizeof rb);
      if(n>0)got=n;else{long ts[2]={0,10000000};nanosleep(ts,0);}}
    ktest("tun.icmp_reply",got==36&&rb[9]==1&&rb[20]==0&&rb[24]==0x12&&memcmp_(rb+12,me,4)==0&&memcmp_(rb+16,lan,4)==0&&ipcs(rb,20)==0);
    /* paquet UDP vers l'hote 10.0.2.2:9092 a travers eth0, sans retransmission */
    {unsigned char u[8+7];memset(u,0,sizeof u);u[0]=0x0f;u[1]=0xa0;u[2]=9092>>8;u[3]=9092&255;u[5]=15;memcpy(u+8,"tun-fwd",7);
     r=mkip(pk,17,lan,hostip,u,15);
     {int fd=open("/proc/sys/net/ipv4/ip_forward",O_RDWR,0),n;char v[4];
      n=read(fd,v,1);ktest("tun.ip_forward_default_off",n==1&&v[0]=='0');close(fd);}
     write(tf,pk,r);
     got=-1;for(t=0;t<40&&got<0;t++){int n=read(tf,rb,sizeof rb);
       if(n>0)got=n;else{long ts[2]={0,10000000};nanosleep(ts,0);}}
     ktest("tun.no_forward_when_off",got<0);
     {int fd=open("/proc/sys/net/ipv4/ip_forward",O_RDWR,0);write(fd,"1\n",2);close(fd);}
     /* FORWARD en DROP : rien ne repart */
     BUILD(0,0,0,0,0,0);PUT32(92+152+144,(unsigned)-1);
     ktest("tun.forward_drop_rule",setsockopt(rs,0,64,tb,off)==0);
     write(tf,pk,r);
     got=-1;for(t=0;t<60&&got<0;t++){int n=read(tf,rb,sizeof rb);
       if(n>0)got=n;else{long ts[2]={0,10000000};nanosleep(ts,0);}}
     ktest("tun.forward_dropped",got<0);
     BUILD(0,0,0,0,0,0);
     ktest("tun.forward_accept_rule",setsockopt(rs,0,64,tb,off)==0);
     write(tf,pk,r);
     /* l'echo de l'hote revient vers 192.168.77.2 : retransmis sur tun0 */
     got=-1;for(t=0;t<300&&got<0;t++){int n=read(tf,rb,sizeof rb);
       if(n>0)got=n;else{long ts[2]={0,10000000};nanosleep(ts,0);}}
     ktest("tun.forward_roundtrip",got==35&&rb[9]==17&&memcmp_(rb+12,hostip,4)==0&&memcmp_(rb+16,lan,4)==0&&memcmp_(rb+28,"tun-fwd",7)==0&&ipcs(rb,20)==0);
    }
    {int fd=open("/proc/sys/net/ipv4/ip_forward",O_RDWR,0);write(fd,"0\n",2);close(fd);}
    close(rs);close(tf);close(sk);
  }
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
