/* nltest : AF_NETLINK / NETLINK_ROUTE (partie 39) : RTM_GETLINK, RTM_GETADDR,
   RTM_GETROUTE (listes completes et lien unique), acquittements, erreurs,
   RTM_NEWADDR / RTM_DELADDR / RTM_NEWROUTE / RTM_DELROUTE sur eth0 s'il y
   a une carte reseau, getsockname / bind. */
#include "ku.h"
#include "kusock.h"
struct nlh{unsigned len;unsigned short type,flags;unsigned seq,pid;};
struct snl{unsigned short fam,pad;unsigned pid,groups;};
static char buf[8192];
static int seq=100;
/* envoie un message (en-tete + charge) et rassemble la reponse jusqu'a DONE/ERROR */
static int nlreq(int fd,int type,int flags,const void*pay,int plen,char*out,int max){
  static char rq[512];struct nlh*h=(struct nlh*)rq;struct snl k={16,0,0,0};
  int n=0,r;
  h->len=16+plen;h->type=type;h->flags=flags;h->seq=++seq;h->pid=0;
  memcpy(rq+16,pay,plen);
  if(sendto(fd,rq,16+plen,0,&k,sizeof k)<0)return -1000;
  for(;;){
    int off=0,done=0;
    r=recvfrom(fd,buf,sizeof buf,0,0,0);
    if(r<=0)return -1001;
    while(off+16<=r){struct nlh*m=(struct nlh*)(buf+off);
      if(m->type==3||m->type==2)done=1;
      if(n+m->len<=max){memcpy(out+n,buf+off,(m->len+3)&~3u);n+=(m->len+3)&~3u;}
      off+=(m->len+3)&~3;}
    if(done||!(flags&0x300))break;
  }
  return n;
}
/* cherche un attribut */
static const unsigned char*attr(const unsigned char*p,const unsigned char*e,int t,int*l){
  while(p+4<=e){int al=p[0]|(p[1]<<8),at=p[2]|(p[3]<<8);if(al<4||p+al>e)return 0;
    if(at==t){*l=al-4;return p+4;}p+=(al+3)&~3;}
  return 0;}
static int nmsg(const char*o,int n,int type){int off=0,c=0;while(off+16<=n){const struct nlh*m=(const struct nlh*)(o+off);if(m->type==type)c++;off+=(m->len+3)&~3;}return c;}
static const struct nlh*nth(const char*o,int n,int type,int k){int off=0;while(off+16<=n){const struct nlh*m=(const struct nlh*)(o+off);if(m->type==type&&k--==0)return m;off+=(m->len+3)&~3;}return 0;}
int main(){
  static char out[6000];
  int fd,n,l,i;struct snl a,b;int al;
  fd=socket(16,3,0);
  ktest("nl.socket",fd>=0);
  ktest("nl.socket_proto_einval",socket(16,3,15)==-93);
  ktest("nl.socket_type_esocktnosupport",socket(16,1,0)==-94);
  if(fd<0){puts("KTEST: nl DONE\n");return 1;}
  memset(&a,0,sizeof a);a.fam=16;
  ktest("nl.bind",bind(fd,&a,sizeof a)==0);
  al=sizeof b;memset(&b,0,sizeof b);
  ktest("nl.getsockname",getsockname(fd,&b,&al)==0&&b.fam==16&&b.pid!=0&&al==12);
  {struct{unsigned char fam,pad;unsigned short typ;int idx;unsigned fl,ch;}ifi;
   memset(&ifi,0,sizeof ifi);
   n=nlreq(fd,18,0x301,&ifi,sizeof ifi,out,sizeof out);
   ktest("nl.getlink_dump",n>0&&nmsg(out,n,16)>=1&&nmsg(out,n,3)==1);
   {const struct nlh*m=nth(out,n,16,0);int ok=0;
    if(m){const unsigned char*p=(const unsigned char*)m+32,*e=(const unsigned char*)m+m->len;
      int nl2;const unsigned char*nm=attr(p,e,3,&nl2);const unsigned char*mt=attr(p,e,4,&l);
      ok=nm&&nm[0]=='l'&&nm[1]=='o'&&nl2==3&&mt&&*(unsigned*)mt==65536;
      {int ty=((const unsigned short*)((const char*)m+18))[0];int fl=*(const unsigned*)((const char*)m+24);
       ok=ok&&ty==772&&(fl&0x9)==9&&m->flags==2&&m->seq==(unsigned)seq;}}
    ktest("nl.link_lo_attrs",ok);}
   ifi.idx=1;
   n=nlreq(fd,18,1,&ifi,sizeof ifi,out,sizeof out);
   ktest("nl.getlink_by_index",n>0&&nmsg(out,n,16)==1&&nmsg(out,n,3)==0);
   ifi.idx=99;
   n=nlreq(fd,18,1,&ifi,sizeof ifi,out,sizeof out);
   {const struct nlh*m=nth(out,n,2,0);ktest("nl.getlink_enodev",m&&*(const int*)((const char*)m+16)==-19);}
   {char pl[64];memset(pl,0,sizeof pl);pl[16]=4;pl[17]=0;pl[18]='l';pl[19]='o';pl[20]=0;
    /* IFLA_IFNAME "lo" : attribut len 7, type 3 */
    pl[16]=7;pl[17]=0;pl[18]=3;pl[19]=0;pl[20]='l';pl[21]='o';pl[22]=0;
    n=nlreq(fd,18,1,pl,24,out,sizeof out);
    ktest("nl.getlink_by_name",n>0&&nmsg(out,n,16)==1);}
  }
  {struct{unsigned char fam,pl,fl,sc;int idx;}am;memset(&am,0,sizeof am);
   n=nlreq(fd,22,0x301,&am,sizeof am,out,sizeof out);
   {int found=0,k;for(k=0;k<8;k++){const struct nlh*m=nth(out,n,20,k);if(!m)break;
     {const unsigned char*p=(const unsigned char*)m+24,*e=(const unsigned char*)m+m->len;const unsigned char*ip=attr(p,e,2,&l);
      const unsigned char*lb=attr(p,e,3,&l);
      if(ip&&ip[0]==127&&ip[1]==0&&ip[2]==0&&ip[3]==1&&((const unsigned char*)m)[17]==8&&((const unsigned char*)m)[19]==254&&lb&&lb[0]=='l')found=1;}}
    ktest("nl.getaddr_lo",found&&nmsg(out,n,3)==1);}}
  {struct{unsigned char fam,dl,sl,tos,tb,pr,sc,ty;unsigned fl;}rm;memset(&rm,0,sizeof rm);
   n=nlreq(fd,26,0x301,&rm,sizeof rm,out,sizeof out);
   ktest("nl.getroute_dump",n>=20&&nmsg(out,n,3)==1);}
  /* requete inconnue : erreur EOPNOTSUPP */
  {char z[8]={0};n=nlreq(fd,77,1,z,8,out,sizeof out);
   {const struct nlh*m=nth(out,n,2,0);ktest("nl.unknown_type",m&&*(const int*)((const char*)m+16)==-95);}}
  /* acquittement NLM_F_ACK d'une requete correcte */
  {struct{unsigned char fam,pad;unsigned short typ;int idx;unsigned fl,ch;}ifi;memset(&ifi,0,sizeof ifi);ifi.idx=1;
   n=nlreq(fd,18,5,&ifi,sizeof ifi,out,sizeof out);
   {const struct nlh*m=nth(out,n,2,0);ktest("nl.ack",m&&*(const int*)((const char*)m+16)==0&&nmsg(out,n,16)==1);}}
  /* lo : interdit d'ajouter une adresse */
  {unsigned char am[24];memset(am,0,sizeof am);am[0]=2;am[1]=24;*(int*)(am+4)=1;am[8]=8;am[9]=0;am[10]=2;am[11]=0;am[12]=10;am[13]=0;am[14]=0;am[15]=1;
   n=nlreq(fd,20,5,am,16,out,sizeof out);
   {const struct nlh*m=nth(out,n,2,0);ktest("nl.newaddr_lo_refused",m&&*(const int*)((const char*)m+16)==-95);}}
  /* eth0 : ajout et suppression d'adresse, route par defaut */
  {struct{unsigned char fam,pad;unsigned short typ;int idx;unsigned fl,ch;}ifi;
   memset(&ifi,0,sizeof ifi);ifi.idx=2;
   n=nlreq(fd,18,1,&ifi,sizeof ifi,out,sizeof out);
   if(nmsg(out,n,16)==1){
     unsigned char am[16];const struct nlh*m;int found=0,k;
     memset(am,0,sizeof am);am[0]=2;am[1]=24;*(int*)(am+4)=2;
     am[8]=8;am[9]=0;am[10]=2;am[11]=0;am[12]=10;am[13]=9;am[14]=8;am[15]=7;
     n=nlreq(fd,20,5,am,16,out,sizeof out);
     m=nth(out,n,2,0);ktest("nl.eth0_newaddr",m&&*(const int*)((const char*)m+16)==0);
     {unsigned char z[8]={0};n=nlreq(fd,22,0x301,z,8,out,sizeof out);
      for(k=0;k<8;k++){m=nth(out,n,20,k);if(!m)break;
       {const unsigned char*ip=attr((const unsigned char*)m+24,(const unsigned char*)m+m->len,2,&l);
        if(ip&&ip[0]==10&&ip[1]==9&&ip[2]==8&&ip[3]==7&&((const unsigned char*)m)[17]==24)found=1;}}
      ktest("nl.eth0_getaddr_sees_it",found);}
     {unsigned char rt[40];memset(rt,0,sizeof rt);rt[0]=2;rt[4]=254;rt[5]=3;rt[7]=1;
      rt[12]=8;rt[13]=0;rt[14]=5;rt[15]=0;rt[16]=10;rt[17]=9;rt[18]=8;rt[19]=1;
      n=nlreq(fd,25,5,rt,20,out,sizeof out);   /* retire une route par defaut existante */
      n=nlreq(fd,24,5,rt,20,out,sizeof out);
      m=nth(out,n,2,0);ktest("nl.eth0_newroute_default",m&&*(const int*)((const char*)m+16)==0);
      {unsigned char z[12]={0};int gw=0;n=nlreq(fd,26,0x301,z,12,out,sizeof out);
       for(k=0;k<8;k++){m=nth(out,n,24,k);if(!m)break;
        {const unsigned char*g=attr((const unsigned char*)m+28,(const unsigned char*)m+m->len,5,&l);
         if(g&&g[0]==10&&g[3]==1&&((const unsigned char*)m)[17]==0)gw=1;}}
       ktest("nl.eth0_route_listed",gw);}
      n=nlreq(fd,24,5,rt,20,out,sizeof out);
      m=nth(out,n,2,0);ktest("nl.eth0_newroute_eexist",m&&*(const int*)((const char*)m+16)==-17);
      n=nlreq(fd,25,5,rt,20,out,sizeof out);
      m=nth(out,n,2,0);ktest("nl.eth0_delroute",m&&*(const int*)((const char*)m+16)==0);}
     n=nlreq(fd,21,5,am,16,out,sizeof out);
     m=nth(out,n,2,0);ktest("nl.eth0_deladdr",m&&*(const int*)((const char*)m+16)==0);
     n=nlreq(fd,21,5,am,16,out,sizeof out);
     m=nth(out,n,2,0);ktest("nl.eth0_deladdr_again",m&&*(const int*)((const char*)m+16)==-99);
   }
  }
  /* poll : rien a lire */
  ktest("nl.poll_empty",poll1(fd,1,0)==0);
  /* socket non privilegiee : pas de modification */
  {int p=fork(),st=0;
   if(p==0){int f2=socket(16,3,0);unsigned char am[16];struct snl k={16,0,0,0};char rq[64],rb[256];struct nlh*h=(struct nlh*)rq;
     if(f2<0)_exit(2);
     sc1(23,1000);
     memset(am,0,sizeof am);am[0]=2;am[1]=24;*(int*)(am+4)=1;
     h->len=32;h->type=20;h->flags=5;h->seq=1;h->pid=0;memcpy(rq+16,am,16);
     sendto(f2,rq,32,0,&k,sizeof k);
     if(recvfrom(f2,rb,sizeof rb,0,0,0)<20)_exit(3);
     _exit(*(int*)(rb+16)==-1?0:1);}
   waitpid(p,&st,0);ktest("nl.eperm_nonroot",st==0);}
  /* tap dans netlink et /proc ; pont de trois ports */
  {
    int tf[3],tn,sk=socket(2,2,0),j,r;static unsigned char ifr[40];char nb[3][8]={"nlta","nltb","nltc"};
    unsigned char hostmac[3][6]={{2,0,0,0,0,0x0a},{2,0,0,0,0,0x0b},{2,0,0,0,0,0x0c}},fr[128],rb[256];
    unsigned char me[4]={192,168,66,1};
    for(j=0;j<3;j++){tf[j]=open("/dev/net/tun",O_RDWR|0x800,0);
      memset(ifr,0,40);memcpy(ifr,nb[j],5);*(unsigned short*)(ifr+16)=0x1002;
      r=ioctl(tf[j],0x400454CA,(long)ifr);if(r!=0)break;}
    ktest("nl.tap_create",j==3);
    if(j==3){
      /* netlink : adresse puis activation du premier tap */
      {unsigned char am[16+8];int idx;memset(ifr,0,40);memcpy(ifr,"nlta",5);ioctl(sk,0x8933,(long)ifr);idx=*(int*)(ifr+16);
       memset(am,0,sizeof am);am[0]=2;am[1]=24;*(int*)(am+4)=idx;
       am[8]=8;am[9]=0;am[10]=2;am[11]=0;memcpy(am+12,me,4);
       n=nlreq(fd,20,5,am,16,out,sizeof out);{const struct nlh*m=nth(out,n,2,0);ktest("nl.tap_newaddr",m&&*(const int*)((const char*)m+16)==0);}
       {unsigned char lm[16];memset(lm,0,16);*(int*)(lm+4)=idx;*(unsigned*)(lm+8)=1;*(unsigned*)(lm+12)=1;
        n=nlreq(fd,16,5,lm,16,out,sizeof out);{const struct nlh*m=nth(out,n,2,0);ktest("nl.tap_setup",m&&*(const int*)((const char*)m+16)==0);}}
       memset(ifr,0,40);memcpy(ifr,"nlta",5);ioctl(sk,0x8915,(long)ifr);
       ktest("nl.tap_addr_ioctl",memcmp_(ifr+20,me,4)==0);
       {unsigned char gm[16];memset(gm,0,16);n=nlreq(fd,18,0x301,gm,16,out,sizeof out);
        {int k2,found=0;for(k2=0;k2+5<n;k2++)if(memcmp_(out+k2,"nlta",5)==0)found=1;ktest("nl.tap_in_link_dump",found);}
        n=nlreq(fd,22,0x301,gm,8,out,sizeof out);
        {int k2,found=0;for(k2=0;k2+4<n;k2++)if(memcmp_((unsigned char*)out+k2,me,4)==0)found=1;ktest("nl.tap_in_addr_dump",found);}
        n=nlreq(fd,26,0x301,gm,12,out,sizeof out);
        {int k2,found=0;for(k2=0;k2+5<n;k2++)if(memcmp_(out+k2,"\xc0\xa8\x42\x00",4)==0)found=1;ktest("nl.tap_in_route_dump",found);}}
       {static char pb[2048];int pn=0,z,f1=0,f2=0,fd2=open("/proc/net/dev",O_RDONLY,0),fr2=open("/proc/net/route",O_RDONLY,0);
        if(fd2>=0){pn=read(fd2,pb,sizeof pb-1);close(fd2);}
        for(z=0;z+5<pn;z++)if(memcmp_(pb+z,"nlta:",5)==0)f1=1;
        ktest("nl.tap_proc_net_dev",f1);
        pn=0;if(fr2>=0){pn=read(fr2,pb,sizeof pb-1);close(fr2);}
        for(z=0;z+4<pn;z++)if(memcmp_(pb+z,"nlta",4)==0)f2=1;
        ktest("nl.tap_proc_net_route",f2);}
      }
      /* pont br0 : nlta, nltb, nltc ; commutation et apprentissage des adresses */
      {static unsigned char brn[16]="nlbr",rq[40];int got[3],k2;
       r=ioctl(sk,0x89A0,(long)brn);ktest("br.addbr",r==0);
       ktest("br.addbr_exists",ioctl(sk,0x89A0,(long)brn)==-17);
       for(k2=0;k2<3;k2++){memset(rq,0,40);memcpy(rq,"nlbr",5);
         {unsigned char q2[40];memset(q2,0,40);memcpy(q2,nb[k2],5);ioctl(sk,0x8933,(long)q2);*(int*)(rq+16)=*(int*)(q2+16);}
         r=ioctl(sk,0x89A2,(long)rq);if(r!=0)break;
         {unsigned char q3[40];memset(q3,0,40);memcpy(q3,nb[k2],5);*(unsigned short*)(q3+16)=1;ioctl(sk,0x8914,(long)q3);}}
       ktest("br.addif_3",k2==3);
       /* trame de a (adresse 0a) vers une adresse inconnue : diffusee sur b et c */
       memset(fr,0,60);memcpy(fr,hostmac[1],6);memcpy(fr+6,hostmac[0],6);fr[12]=0x88;fr[13]=0xb5;memcpy(fr+14,"br-flood",8);
       write(tf[0],fr,60);
       for(k2=0;k2<3;k2++){got[k2]=read(tf[k2],rb,sizeof rb);}
       ktest("br.flood_unknown",got[0]<=0&&got[1]==60&&got[2]==60&&memcmp_(rb+14,"br-flood",8)==0);
       /* b repond : adresse 0b apprise sur le port b ; c ne voit rien d'une trame de a vers 0b */
       memset(fr,0,60);memcpy(fr,hostmac[0],6);memcpy(fr+6,hostmac[1],6);fr[12]=0x88;fr[13]=0xb5;memcpy(fr+14,"br-reply",8);
       write(tf[1],fr,60);
       for(k2=0;k2<3;k2++)got[k2]=read(tf[k2],rb,sizeof rb);
       ktest("br.unicast_learned_a",got[0]==60&&got[1]<=0&&got[2]<=0);
       memset(fr,0,60);memcpy(fr,hostmac[1],6);memcpy(fr+6,hostmac[0],6);fr[12]=0x88;fr[13]=0xb5;memcpy(fr+14,"br-uni-b",8);
       write(tf[0],fr,60);
       for(k2=0;k2<3;k2++)got[k2]=read(tf[k2],rb,sizeof rb);
       ktest("br.unicast_learned_b",got[0]<=0&&got[1]==60&&got[2]<=0&&memcmp_(rb+14,"br-uni-b",8)==0);
       /* diffusion */
       memset(fr,0,60);memset(fr,255,6);memcpy(fr+6,hostmac[2],6);fr[12]=0x88;fr[13]=0xb5;
       write(tf[2],fr,60);
       for(k2=0;k2<3;k2++)got[k2]=read(tf[k2],rb,sizeof rb);
       ktest("br.broadcast",got[0]==60&&got[1]==60&&got[2]<=0);
       /* adresse IP sur le pont : l'hote a envoie un ICMP echo vers le pont, la reponse revient sur le port a */
       {unsigned char q4[40];static unsigned char pk[128],ic[16];unsigned char bi[4]={192,168,77,1},lanh[4]={192,168,77,9};int c,k3;
        memset(q4,0,40);memcpy(q4,"nlbr",5);q4[16]=2;memcpy(q4+20,bi,4);ioctl(sk,0x8916,(long)q4);
        memset(q4,0,40);memcpy(q4,"nlbr",5);q4[16]=2;q4[20]=255;q4[21]=255;q4[22]=255;ioctl(sk,0x891C,(long)q4);
        memset(q4,0,40);memcpy(q4,"nlbr",5);*(unsigned short*)(q4+16)=1;ioctl(sk,0x8914,(long)q4);
        memset(q4,0,40);memcpy(q4,"nlbr",5);ioctl(sk,0x8927,(long)q4);
        memset(ic,0,16);ic[0]=8;ic[4]=0x31;ic[7]=1;memcpy(ic+8,"bridged!",8);{c=0;for(k3=0;k3<16;k3+=2)c+=(ic[k3]<<8)|ic[k3+1];while(c>>16)c=(c&0xffff)+(c>>16);c=~c&0xffff;ic[2]=c>>8;ic[3]=c&255;}
        memset(pk,0,sizeof pk);memcpy(pk,q4+18,6);memcpy(pk+6,hostmac[0],6);pk[12]=8;pk[13]=0;
        pk[14]=0x45;pk[16]=0;pk[17]=36;pk[20]=0x40;pk[22]=64;pk[23]=1;memcpy(pk+26,lanh,4);memcpy(pk+30,bi,4);
        {int s2=0;for(k3=0;k3<20;k3+=2)s2+=(pk[14+k3]<<8)|pk[15+k3];while(s2>>16)s2=(s2&0xffff)+(s2>>16);s2=~s2&0xffff;pk[24]=s2>>8;pk[25]=s2&255;}
        memcpy(pk+34,ic,16);
        write(tf[0],pk,14+36);
        for(k3=0;k3<3;k3++)got[k3]=read(tf[k3],rb,sizeof rb);
        ktest("br.local_icmp_reply",got[0]==14+36&&rb[12]==8&&rb[13]==0&&rb[14+9]==1&&rb[14+20]==0&&memcmp_(rb+14+12,bi,4)==0&&memcmp_(rb,hostmac[0],6)==0);
        ktest("br.reply_only_on_learned_port",got[1]<=0&&got[2]<=0);}
       memset(rq,0,40);memcpy(rq,"nlbr",5);*(int*)(rq+16)=0;
       ktest("br.delbr_busy",ioctl(sk,0x89A1,(long)brn)==-16);
       {unsigned char q5[40];memset(q5,0,40);memcpy(q5,"nlbr",5);*(unsigned short*)(q5+16)=0;ioctl(sk,0x8914,(long)q5);}
       ktest("br.delbr",ioctl(sk,0x89A1,(long)brn)==0);
       ktest("br.delbr_gone",ioctl(sk,0x89A1,(long)brn)==-19);}
    }
    for(j=0;j<3;j++)if(tf[j]>=0)close(tf[j]);
    close(sk);
  }
  close(fd);
  puts("KTEST: nl DONE\n");
  return ku_fail?1:0;
}
