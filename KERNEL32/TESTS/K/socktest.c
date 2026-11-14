/* socktest : sockets AF_UNIX (flux, datagrammes, socketpair, SCM_RIGHTS),
   AF_INET en bouclage (UDP, TCP), ICMP echo (ping local) */
#include "ku.h"
#include "kusock.h"
static unsigned short hs(unsigned short v){return (v>>8)|(v<<8);}
static void mksun(struct sun*a,const char*p){int i;memset(a,0,sizeof *a);a->fam=1;for(i=0;p[i];i++)a->path[i]=p[i];}
static void mksin(struct sin*a,int port){memset(a,0,sizeof *a);a->fam=2;a->port=hs(port);a->addr=0x0100007f;}
int main(void){
  int sv[2],n,fd,s,c,a,l;char b[256];struct sun su,sa;struct sin si,sb;
  /* ---- socketpair flux ---- */
  ktest("sock.pair_stream",socketpair(1,1,0,sv)==0);
  write(sv[0],"abc",3);n=read(sv[1],b,10);
  ktest("sock.pair_rw",n==3&&memcmp_(b,"abc",3)==0);
  write(sv[1],"xyz",3);n=read(sv[0],b,10);
  ktest("sock.pair_rw_back",n==3&&memcmp_(b,"xyz",3)==0);
  ktest("sock.pair_poll_empty",poll1(sv[0],1,0)==0);
  write(sv[1],"q",1);
  ktest("sock.pair_poll_in",(poll1(sv[0],1,100)&1)==1);
  read(sv[0],b,1);
  shutdown(sv[0],1);
  n=read(sv[1],b,10);
  ktest("sock.shutdown_eof",n==0);
  write(sv[1],"z",1);n=read(sv[0],b,10);
  ktest("sock.shutdown_half",n==1);
  close(sv[0]);
  ktest("sock.close_eof",read(sv[1],b,10)==0);
  ktest("sock.epipe",({signal_set(SIGPIPE,(void(*)(int))1,0);write(sv[1],"x",1)==-32;}));
  close(sv[1]);
  /* ---- socketpair datagrammes ---- */
  socketpair(1,2,0,sv);
  write(sv[0],"one",3);write(sv[0],"three",5);
  ktest("sock.dgram_boundaries",read(sv[1],b,100)==3&&read(sv[1],b,100)==5);
  ktest("sock.dgram_eagain",({int f=fcntl(sv[1],4,0x800);(void)f;read(sv[1],b,10)==-11;}));
  close(sv[0]);close(sv[1]);
  /* ---- AF_UNIX nomme ---- */
  unlink("/tmp/s.sock");
  s=socket(1,1,0);mksun(&su,"/tmp/s.sock");
  ktest("sock.unix_bind",bind(s,&su,14)==0);
  ktest("sock.unix_node",({unsigned char sb2[96];sc2(SYS_stat64,(long)"/tmp/s.sock",(long)sb2)==0&&((*(unsigned*)(sb2+16))&0170000)==0140000;}));
  ktest("sock.unix_bind_inuse",({int s2=socket(1,1,0);int r=bind(s2,&su,14);close(s2);r==-98;}));
  ktest("sock.unix_listen",listen(s,5)==0);
  c=socket(1,1,0);
  ktest("sock.unix_connect",connect(c,&su,14)==0);
  a=accept(s,0,0);
  ktest("sock.unix_accept",a>=0);
  write(c,"ping",4);n=read(a,b,10);
  ktest("sock.unix_c2s",n==4&&memcmp_(b,"ping",4)==0);
  write(a,"pong",4);n=read(c,b,10);
  ktest("sock.unix_s2c",n==4&&memcmp_(b,"pong",4)==0);
  l=sizeof sa;memset(&sa,0,sizeof sa);
  ktest("sock.unix_getsockname",getsockname(s,&sa,&l)==0&&sa.fam==1&&strcmp(sa.path,"/tmp/s.sock")==0);
  l=sizeof sa;memset(&sa,0,sizeof sa);
  ktest("sock.unix_getpeername",getpeername(c,&sa,&l)==0&&strcmp(sa.path,"/tmp/s.sock")==0);
  {int cred[3]={0,0,0};int cl=12;
   ktest("sock.unix_peercred",getsockopt(a,1,17,cred,&cl)==0&&cred[0]==getpid());}
  {int ty=0,tl=4;ktest("sock.getsockopt_type",getsockopt(c,1,3,&ty,&tl)==0&&ty==1);}
  ktest("sock.unix_nb_accept",({fcntl(s,4,0x800);int r=accept(s,0,0);r==-11;}));
  close(a);
  ktest("sock.unix_peer_close",read(c,b,10)==0);
  close(c);close(s);
  ktest("sock.unix_refused",({int c2=socket(1,1,0);int r=connect(c2,&su,14);close(c2);r==-111;}));
  unlink("/tmp/s.sock");
  ktest("sock.unix_noent",({int c2=socket(1,1,0);int r=connect(c2,&su,14);close(c2);r==-2;}));
  /* ---- abstrait ---- */
  {struct sun ab;memset(&ab,0,sizeof ab);ab.fam=1;ab.path[0]=0;ab.path[1]='A';ab.path[2]='B';
   s=socket(1,1,0);c=socket(1,1,0);
   ktest("sock.abstract_bind",bind(s,&ab,2+3)==0&&listen(s,1)==0);
   ktest("sock.abstract_connect",connect(c,&ab,2+3)==0);
   a=accept(s,0,0);write(c,"ab",2);n=read(a,b,10);
   ktest("sock.abstract_data",a>=0&&n==2);
   close(a);close(c);close(s);}
  /* ---- AF_UNIX datagrammes nommes ---- */
  {struct sun d1,d2;unlink("/tmp/d1.sock");unlink("/tmp/d2.sock");mksun(&d1,"/tmp/d1.sock");mksun(&d2,"/tmp/d2.sock");
   s=socket(1,2,0);c=socket(1,2,0);bind(s,&d1,2+14);bind(c,&d2,2+14);
   {int r0=sendto(c,"hello",5,0,&d1,2+14);if(r0!=5){puts("  sendto rc=");putd(r0);puts("\n");}ktest("sock.udgram_sendto",r0==5);}
   l=sizeof sa;memset(&sa,0,sizeof sa);
   n=recvfrom(s,b,100,0x40,&sa,&l);
   ktest("sock.udgram_recvfrom",n==5&&memcmp_(b,"hello",5)==0&&strcmp(sa.path,"/tmp/d2.sock")==0);
   ktest("sock.udgram_connect",connect(c,&d1,2+14)==0&&write(c,"w",1)==1&&recvfrom(s,b,10,0x40,0,0)==1);
   close(s);close(c);unlink("/tmp/d1.sock");unlink("/tmp/d2.sock");}
  /* ---- SCM_RIGHTS ---- */
  {int pp[2],fdr;char cbuf[32];struct iov io;struct msgh m;
   socketpair(1,1,0,sv);pipe(pp);
   io.b="F";io.n=1;memset(&m,0,sizeof m);m.iov=&io;m.iovlen=1;
   memset(cbuf,0,32);((int*)cbuf)[0]=16;((int*)cbuf)[1]=1;((int*)cbuf)[2]=1;((int*)cbuf)[3]=pp[0];
   m.ctl=cbuf;m.ctllen=16;
   ktest("sock.scm_send",sendmsg(sv[0],&m,0)==1);
   close(pp[0]);
   io.b=b;io.n=10;memset(&m,0,sizeof m);m.iov=&io;m.iovlen=1;memset(cbuf,0,32);m.ctl=cbuf;m.ctllen=32;
   n=recvmsg(sv[1],&m,0);
   fdr=((int*)cbuf)[3];
   ktest("sock.scm_recv",n==1&&((int*)cbuf)[1]==1&&((int*)cbuf)[2]==1&&fdr>2);
   write(pp[1],"thru",4);n=read(fdr,b,10);
   ktest("sock.scm_fd_works",n==4&&memcmp_(b,"thru",4)==0);
   close(sv[0]);close(sv[1]);close(pp[1]);close(fdr);}
  /* ---- fork + lecture bloquante ---- */
  socketpair(1,1,0,sv);
  {int p=fork();
   if(p==0){close(sv[0]);n=read(sv[1],b,10);write(sv[1],b,n);_exit(0);}
   close(sv[1]);{long ts[2]={0,50000000};nanosleep(ts,0);}
   write(sv[0],"echo",4);n=read(sv[0],b,10);
   ktest("sock.fork_blocking",n==4&&memcmp_(b,"echo",4)==0);
   {int st;waitpid(p,&st,0);}close(sv[0]);}
  /* ---- UDP en bouclage ---- */
  s=socket(2,2,0);c=socket(2,2,0);
  mksin(&si,4000);
  ktest("sock.udp_bind",bind(s,&si,16)==0);
  ktest("sock.udp_bind_inuse",({int s2=socket(2,2,0);int r=bind(s2,&si,16);close(s2);r==-98;}));
  ktest("sock.udp_sendto",sendto(c,"dgram",5,0,&si,16)==5);
  l=sizeof sb;memset(&sb,0,sizeof sb);
  n=recvfrom(s,b,100,0x40,&sb,&l);
  ktest("sock.udp_recvfrom",n==5&&memcmp_(b,"dgram",5)==0&&sb.fam==2&&sb.addr==0x0100007f&&hs(sb.port)>=32768);
  ktest("sock.udp_reply",sendto(s,"back",4,0,&sb,16)==4&&recvfrom(c,b,10,0x40,0,0)==4);
  ktest("sock.udp_connected",connect(c,&si,16)==0&&write(c,"c",1)==1&&recvfrom(s,b,10,0x40,0,0)==1);
  ktest("sock.udp_unreach",({struct sin ext;mksin(&ext,53);ext.addr=0x08080808;sendto(s,"x",1,0,&ext,16)==-101;}));
  ktest("sock.udp_poll",poll1(s,1,0)==0);
  close(s);close(c);
  /* ---- TCP en bouclage ---- */
  s=socket(2,1,0);mksin(&si,5555);
  {int one=1;setsockopt(s,1,2,&one,4);}
  ktest("sock.tcp_bind",bind(s,&si,16)==0);
  ktest("sock.tcp_listen",listen(s,4)==0);
  c=socket(2,1,0);
  ktest("sock.tcp_connect",connect(c,&si,16)==0);
  l=sizeof sb;a=accept(s,&sb,&l);
  ktest("sock.tcp_accept",a>=0&&sb.fam==2&&sb.addr==0x0100007f);
  write(c,"GET",3);n=read(a,b,10);
  ktest("sock.tcp_data",n==3&&memcmp_(b,"GET",3)==0);
  l=sizeof sb;memset(&sb,0,sizeof sb);
  ktest("sock.tcp_getpeername",getpeername(c,&sb,&l)==0&&hs(sb.port)==5555);
  l=sizeof sb;memset(&sb,0,sizeof sb);
  ktest("sock.tcp_getsockname",getsockname(a,&sb,&l)==0&&hs(sb.port)==5555);
  ktest("sock.tcp_refused",({struct sin x;int c2=socket(2,1,0);mksin(&x,5556);int r=connect(c2,&x,16);close(c2);r==-111;}));
  /* gros transfert entre processus */
  {int p=fork();
   if(p==0){char big[4096];int i,tot=0;close(c);close(s);
     for(i=0;i<4096;i++)big[i]=i*3;
     for(i=0;i<50;i++){int w=write(a,big,4096);if(w!=4096)_exit(1);}
     close(a);_exit(0);}
   close(a);
   {char rb[8192];int tot=0,ok=1,r2,i;
    for(;;){r2=read(c,rb,8192);if(r2<=0)break;for(i=0;i<r2;i++)if(rb[i]!=(char)((tot+i)%4096*3))ok=0;tot+=r2;}
    ktest("sock.tcp_bulk",tot==50*4096&&ok);}
   {int st;waitpid(p,&st,0);}}
  close(c);close(s);
  /* ---- ICMP : ping local ---- */
  {unsigned char pk[16];unsigned char rb[64];int r;
   memset(pk,0,16);pk[0]=8;pk[4]=0x12;pk[5]=0x34;pk[6]=0;pk[7]=1;memcpy(pk+8,"pingdata",8);
   {unsigned sum=0;int i;for(i=0;i<16;i+=2)sum+=(pk[i]<<8)|pk[i+1];while(sum>>16)sum=(sum&0xffff)+(sum>>16);sum=~sum&0xffff;pk[2]=sum>>8;pk[3]=sum&255;}
   s=socket(2,3,1);
   ktest("sock.icmp_raw_open",s>=0);
   mksin(&si,0);
   ktest("sock.icmp_raw_send",sendto(s,pk,16,0,&si,16)==16);
   l=sizeof sb;r=recvfrom(s,rb,64,0x40,&sb,&l);
   ktest("sock.icmp_raw_reply",r==36&&rb[0]==0x45&&rb[9]==1&&rb[20]==0&&rb[24]==0x12&&rb[25]==0x34&&sb.addr==0x0100007f);
   close(s);
   s=socket(2,2,1);
   ktest("sock.icmp_dgram_open",s>=0);
   ktest("sock.icmp_dgram_send",sendto(s,pk,16,0,&si,16)==16);
   r=recvfrom(s,rb,64,0x40,0,0);
   ktest("sock.icmp_dgram_reply",r==16&&rb[0]==0&&rb[4]==0x12);
   close(s);}
  ktest("sock.eafnosupport",socket(10,1,0)==-97);
  ktest("sock.enotsock",({int r=getsockname(0,&sa,&l);r==-88||r==-9;}));
  return ku_fail?1:0;
}
