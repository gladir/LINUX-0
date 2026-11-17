/* kusock.h : appels systeme de sockets pour les programmes de test */
#ifndef KUSOCK_H
#define KUSOCK_H
#define SYS_socket 359
#define SYS_socketpair 360
#define SYS_bind 361
#define SYS_connect 362
#define SYS_listen 363
#define SYS_accept4 364
#define SYS_getsockopt 365
#define SYS_setsockopt 366
#define SYS_getsockname 367
#define SYS_getpeername 368
#define SYS_sendto 369
#define SYS_sendmsg 370
#define SYS_recvfrom 371
#define SYS_recvmsg 372
#define SYS_shutdown 373
static int socket(int d,int t,int p){return sc3(SYS_socket,d,t,p);}
static int socketpair(int d,int t,int p,int*sv){return sc4(SYS_socketpair,d,t,p,(long)sv);}
static int bind(int s,const void*a,int l){return sc3(SYS_bind,s,(long)a,l);}
static int connect(int s,const void*a,int l){return sc3(SYS_connect,s,(long)a,l);}
static int listen(int s,int b){return sc2(SYS_listen,s,b);}
static int accept(int s,void*a,int*l){return sc4(SYS_accept4,s,(long)a,(long)l,0);}
static int getsockname(int s,void*a,int*l){return sc3(SYS_getsockname,s,(long)a,(long)l);}
static int getpeername(int s,void*a,int*l){return sc3(SYS_getpeername,s,(long)a,(long)l);}
static int sendto(int s,const void*b,int n,int f,const void*a,int l){return sc6(SYS_sendto,s,(long)b,n,f,(long)a,l);}
static int recvfrom(int s,void*b,int n,int f,void*a,int*l){return sc6(SYS_recvfrom,s,(long)b,n,f,(long)a,(long)l);}
static int shutdown(int s,int h){return sc2(SYS_shutdown,s,h);}
static int getsockopt(int s,int lv,int o,void*v,int*l){return sc5(SYS_getsockopt,s,lv,o,(long)v,(long)l);}
static int setsockopt(int s,int lv,int o,const void*v,int l){return sc5(SYS_setsockopt,s,lv,o,(long)v,l);}
struct iov{void*b;int n;};
struct msgh{void*name;int namelen;struct iov*iov;int iovlen;void*ctl;int ctllen;int flags;};
static int sendmsg(int s,struct msgh*m,int f){return sc3(SYS_sendmsg,s,(long)m,f);}
static int recvmsg(int s,struct msgh*m,int f){return sc3(SYS_recvmsg,s,(long)m,f);}
struct pfd{int fd;short ev,rev;};
static int poll1(int fd,int ev,int tmo){struct pfd p={fd,ev,0};int r=sc3(SYS_poll,(long)&p,1,tmo);return r<=0?r:p.rev;}
struct sun{unsigned short fam;char path[108];};
struct sin{unsigned short fam;unsigned short port;unsigned addr;char z[8];};
#endif
