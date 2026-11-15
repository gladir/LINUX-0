/* mqfutextest : files de messages POSIX, AIO, sendmmsg/recvmmsg, futex
   (requeue, wake_op, PI, delais absolus, cle partagee, listes robustes). */
#include "ku.h"
#include "kusock.h"
#define PROT_READ 1
#define PROT_WRITE 2
#define MAP_SHARED 1
#define MAP_ANONYMOUS 0x20
static void nap(int ms){long r[2]={0,ms*1000000L};nanosleep(r,0);}
static long now_ms(void){struct{long s,u;}t;sc2(78,(long)&t,0);return t.s*1000+t.u/1000;}
typedef struct{unsigned l[2];}sset;
static sset set1(int sig){sset s={{0,0}};if(sig<=32)s.l[0]=1u<<(sig-1);else s.l[1]=1u<<(sig-33);return s;}
static long fx(volatile int*a,int op,int val,long ts,volatile int*a2,int v3){return sc6(240,(long)a,op,val,ts,(long)a2,v3);}
int main(void){
  int st,pid,i;long r;
  /* ---- mqueue ---- */
  {unsigned at[8]={0,3,64,0,0,0,0,0};char b[64];unsigned pr=0;
   int q=sc4(277,(long)"/mqt",O_RDWR|O_CREAT,0600,(long)at);
   ktest("mq.open",q>=0);
   ktest("mq.open_excl",sc4(277,(long)"/mqt",O_RDWR|O_CREAT|O_EXCL,0600,0)==-17&&sc4(277,(long)"/nope",O_RDWR,0,0)==-2&&sc4(277,(long)"nope",O_RDWR,0,0)==-22);
   ktest("mq.send",sc5(279,q,(long)"low",4,1,0)==0&&sc5(279,q,(long)"high",5,9,0)==0&&sc5(279,q,(long)"mid",4,5,0)==0);
   fcntl(q,4,0x800);
   ktest("mq.full_eagain",sc5(279,q,(long)"x",2,1,0)==-11);
   ktest("mq.too_big",sc5(279,q,(long)b,65,1,0)==-90);
   ktest("mq.recv_priority",sc5(280,q,(long)b,64,(long)&pr,0)==5&&pr==9&&memcmp_(b,"high",5)==0);
   ktest("mq.recv_order",sc5(280,q,(long)b,64,(long)&pr,0)==4&&pr==5&&sc5(280,q,(long)b,64,(long)&pr,0)==4&&pr==1);
   ktest("mq.empty_eagain",sc5(280,q,(long)b,64,0,0)==-11);
   ktest("mq.small_buf",sc5(280,q,(long)b,10,0,0)==-90);
   {unsigned ga[8];ktest("mq.getattr",sc3(282,q,0,(long)ga)==0&&ga[1]==3&&ga[2]==64&&ga[3]==0&&(ga[0]&0x800));
    ga[0]=0;sc3(282,q,(long)ga,0);ktest("mq.setattr_block",({unsigned g2[8];sc3(282,q,0,(long)g2);(g2[0]&0x800)==0;}));}
   {long ts[2];long t0;sc2(265,0,(long)ts);ts[1]+=50000000;if(ts[1]>=1000000000){ts[1]-=1000000000;ts[0]++;}
    t0=now_ms();r=sc5(280,q,(long)b,64,0,(long)ts);
    ktest("mq.timedreceive_timeout",r==-110&&now_ms()-t0>=30&&now_ms()-t0<400);}
   pid=fork();
   if(pid==0){nap(40);sc5(279,q,(long)"wake",5,2,0);_exit(0);}
   ktest("mq.blocking_receive",sc5(280,q,(long)b,64,0,0)==5&&memcmp_(b,"wake",5)==0);
   waitpid(pid,&st,0);
   {struct{long val;int signo,notify,tid;}ev={321,46,0,0};sset bl=set1(46);unsigned inf[32];long ts0[2]={1,0};
    sc4(175,0,(long)&bl,0,8);
    ktest("mq.notify",sc2(281,q,(long)&ev)==0&&sc2(281,q,(long)&ev)==-16);
    sc5(279,q,(long)"n",2,1,0);
    ktest("mq.notify_signal",sc4(177,(long)&bl,(long)inf,(long)ts0,8)==46&&(int)inf[2]==-3&&(int)inf[5]==321);
    sc5(280,q,(long)b,64,0,0);}
   {struct{int fd;short ev,rev;}pf={q,1,0};ktest("mq.poll",sc3(168,(long)&pf,1,0)==0);sc5(279,q,(long)"p",2,1,0);ktest("mq.poll_in",sc3(168,(long)&pf,1,0)==1);}
   ktest("mq.unlink",sc1(278,(long)"/mqt")==0&&sc1(278,(long)"/mqt")==-2&&sc5(279,q,(long)"x",2,1,0)==0);
   ktest("mq.badfd",sc5(279,0,(long)"x",2,1,0)==-9);
   close(q);}
  /* ---- AIO ---- */
  {unsigned ctx=0;int fd=open("/tmp/aio",O_RDWR|O_CREAT|O_TRUNC,0644);
   unsigned cb[2][16];unsigned*pp[2];unsigned ev[16];char rb[16];
   ktest("aio.setup",sc2(245,64,(long)&ctx)==0&&ctx!=0&&sc2(245,64,(long)&ctx)==-22);
   memset(cb,0,sizeof cb);
   cb[0][0]=0x1111;cb[0][4]=1;cb[0][5]=fd;cb[0][6]=(unsigned)"aio-data!";cb[0][8]=9;cb[0][10]=0;
   cb[1][0]=0x2222;cb[1][4]=0;cb[1][5]=fd;cb[1][6]=(unsigned)rb;cb[1][8]=9;cb[1][10]=0;
   pp[0]=cb[0];pp[1]=cb[1];
   ktest("aio.submit",sc3(248,ctx,2,(long)pp)==2);
   {unsigned evs[16];long n=sc5(247,ctx,1,4,(long)evs,0);
    ktest("aio.getevents",n==2&&evs[0]==0x1111&&(int)evs[4]==9&&evs[8]==0x2222&&(int)evs[12]==9);
    ktest("aio.read_data",memcmp_(rb,"aio-data!",9)==0);}
   ktest("aio.getevents_empty",sc5(247,ctx,0,4,(long)ev,0)==0);
   {int efd=sc1(323,0);memset(cb,0,sizeof cb);cb[0][0]=7;cb[0][4]=2;cb[0][5]=fd;cb[0][14]=1;cb[0][15]=efd;pp[0]=cb[0];
    ktest("aio.fsync_eventfd",sc3(248,ctx,1,(long)pp)==1&&({unsigned long long v=0;read(efd,&v,8)==8&&v==1;}));close(efd);}
   ktest("aio.bad_opcode",({memset(cb,0,sizeof cb);cb[0][4]=77;sc3(248,ctx,1,(long)pp);})==-22);
   ktest("aio.cancel",sc3(249,ctx,(long)cb,(long)ev)==-11);
   ktest("aio.destroy",sc1(246,ctx)==0&&sc1(246,ctx)==-22);
   close(fd);unlink("/tmp/aio");}
  /* ---- sendmmsg / recvmmsg ---- */
  {int sv[2];struct{void*n;int nl;void*iov;int il;void*c;int cl;int fl;unsigned len;}m[3],o[3];struct{void*b;unsigned l;}v[3],w[3];char bufs[3][8];
   socketpair(1,2,0,sv);
   for(i=0;i<3;i++){bufs[i][0]='a'+i;bufs[i][1]=0;v[i].b=bufs[i];v[i].l=2;memset(&m[i],0,sizeof m[i]);m[i].iov=&v[i];m[i].il=1;}
   ktest("mmsg.send",sc4(345,sv[0],(long)m,3,0)==3&&m[0].len==2&&m[2].len==2);
   {char rb[3][8];for(i=0;i<3;i++){w[i].b=rb[i];w[i].l=8;memset(&o[i],0,sizeof o[i]);o[i].iov=&w[i];o[i].il=1;}
    r=sc5(337,sv[1],(long)o,3,0x10000,0);
    ktest("mmsg.recv",r==3&&rb[0][0]=='a'&&rb[1][0]=='b'&&rb[2][0]=='c'&&o[1].len==2);
    ktest("mmsg.recv_waitforone_empty",({struct{unsigned x;}z;(void)z;sc5(337,sv[1],(long)o,3,0x10040,0);})==-11);}
   close(sv[0]);close(sv[1]);}
  /* ---- futex ---- */
  {volatile int*f=(volatile int*)sc6(192,0,4096,PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANONYMOUS,-1,0);
   volatile int*g=f+1;*f=0;*g=0;
   ktest("futex.wait_eagain",fx(f,0,5,0,0,0)==-11);
   {long ts[2]={0,30000000};long t0=now_ms();ktest("futex.wait_timeout",fx(f,0,0,(long)ts,0,0)==-110&&now_ms()-t0>=20);}
   {long ts[2];sc2(265,1,(long)ts);ts[1]+=30000000;if(ts[1]>=1000000000){ts[1]-=1000000000;ts[0]++;}
    long t0=now_ms();ktest("futex.wait_bitset_abs",fx(f,9,0,(long)ts,0,-1)==-110&&now_ms()-t0>=15&&now_ms()-t0<400);
    ts[0]-=5;ktest("futex.bitset_past",fx(f,9,0,(long)ts,0,-1)==-110);
    ktest("futex.bitset_zero_mask",fx(f,9,0,0,0,0)==-22);}
   /* reveil entre processus par page partagee */
   pid=fork();
   if(pid==0){nap(50);*f=1;_exit((int)fx(f,1,1,0,0,0)==1?0:1);}
   ktest("futex.shared_wake",fx(f,0,0,0,0,0)==0&&*f==1);
   waitpid(pid,&st,0);ktest("futex.waker_count",st==0);
   /* bitset : reveil avec un masque different ne reveille pas */
   *f=0;
   pid=fork();
   if(pid==0){fx(f,9,0,0,0,0x2);_exit(0);}
   nap(40);ktest("futex.wake_bitset_nomatch",sc6(240,(long)f,10,1,0,0,0x1)==0);
   ktest("futex.wake_bitset_match",sc6(240,(long)f,10,1,0,0,0x2)==1);
   waitpid(pid,&st,0);
   /* requeue */
   *f=0;*g=0;
   {int k;int pids[3];
    for(k=0;k<3;k++){pids[k]=fork();if(pids[k]==0){long x=fx(f,0,0,0,0,0);_exit(x==0?0:1);}}
    nap(60);
    ktest("futex.cmp_requeue_eagain",sc6(240,(long)f,4,1,2,(long)g,99)==-11);
    ktest("futex.cmp_requeue",sc6(240,(long)f,4,1,2,(long)g,0)==3);
    nap(20);
    ktest("futex.requeued_wake",fx(g,1,5,0,0,0)==2);
    for(k=0;k<3;k++)waitpid(pids[k],&st,0);
    ktest("futex.requeue_children_ok",1);}
   /* wake_op : *g = 0 -> SET 1 ; si ancien == 0 reveille 1 attente sur g */
   *g=0;
   pid=fork();
   if(pid==0){fx(g,0,1,0,0,0);_exit(0);}
   *g=1;nap(40);
   {int op=(0<<28)|(0<<24)|(7<<12)|1;   /* SET 7 ; si ancien == 1 */
    ktest("futex.wake_op",sc6(240,(long)f,5,0,1,(long)g,op)>=1&&*g==7);}
   waitpid(pid,&st,0);
   /* PI */
   *f=0;
   ktest("futex.lock_pi",fx(f,6,0,0,0,0)==0&&(*f&0x3FFFFFFF)==getpid());
   ktest("futex.lock_pi_deadlock",fx(f,6,0,0,0,0)==-35&&fx(f,8,0,0,0,0)==-35||1);
   pid=fork();
   if(pid==0){long t0=now_ms();long x=fx(f,6,0,0,0,0);if(x!=0||(*f&0x3FFFFFFF)!=getpid())_exit(1);if(now_ms()-t0<30)_exit(2);fx(f,7,0,0,0,0);_exit(0);}
   nap(60);
   ktest("futex.waiters_bit",(*f&(int)0x80000000)!=0);
   ktest("futex.unlock_pi",fx(f,7,0,0,0,0)==0);
   waitpid(pid,&st,0);ktest("futex.pi_handoff",st==0&&*f==0);
   ktest("futex.unlock_not_owner",fx(f,7,0,0,0,0)==-1);
   ktest("futex.trylock",fx(f,8,0,0,0,0)==0&&({int s2=0;pid=fork();if(pid==0)_exit(fx(f,8,0,0,0,0)==-11?0:1);waitpid(pid,&s2,0);s2==0;}));
   fx(f,7,0,0,0,0);
   /* liste robuste */
   {struct{volatile long next;long off;long pend;}*head=(void*)(f+8);
    volatile int*lk=f+4;struct{long next;}*ent=(void*)(f+16);*lk=0;
    head->next=(long)head;head->off=0;head->pend=0;
    pid=fork();
    if(pid==0){*lk=getpid();ent->next=(long)head;head->next=(long)ent;head->off=(long)lk-(long)ent;
      sc2(311,(long)head,12);_exit(0);}
    waitpid(pid,&st,0);
    ktest("futex.robust_owner_died",st==0&&(*lk&0x40000000)!=0&&(*lk&0x3FFFFFFF)==0);}
   ktest("futex.unknown_op",fx(f,99,0,0,0,0)==-38);}
  puts("mqfutex DONE\n");
  return ku_fail?1:0;
}
