/* ipctest : IPC SysV (memoire partagee, semaphores, files de messages), appels
   directs et ipc(2). */
#include "ku.h"
#define IPC_CREAT 01000
#define IPC_EXCL 02000
#define IPC_NOWAIT 04000
#define IPC_RMID 0
#define IPC_SET 1
#define IPC_STAT 2
#define SEM_UNDO 0x1000
static long shmget(long k,long s,long f){return sc3(395,k,s,f);}
static long shmat(long id,long a,long f){return sc3(397,id,a,f);}
static long shmdt(long a){return sc1(398,a);}
static long shmctl(long id,long c,long b){return sc3(396,id,c,b);}
static long semget(long k,long n,long f){return sc3(393,k,n,f);}
static long semctl(long id,long n,long c,long a){return sc4(394,id,n,c,a);}
static long msgget(long k,long f){return sc2(399,k,f);}
static long msgsnd(long id,void*p,long s,long f){return sc4(400,id,(long)p,s,f);}
static long msgrcv(long id,void*p,long s,long t,long f){return sc5(401,id,(long)p,s,t,f);}
static long msgctl(long id,long c,void*b){return sc3(402,id,c,(long)b);}
struct sembuf{unsigned short n;short op;short fl;};
static long semop2(long id,struct sembuf*o,long n){long r;__asm__ volatile("int $0x80":"=a"(r):"0"(117),"b"(1),"c"(id),"d"(n),"S"(0),"D"(o):"memory");return r;}
static void nap(int ms){long r[2]={0,ms*1000000L};nanosleep(r,0);}
struct mb{long t;char d[64];};
int main(void){
  long id,r;int pid,st,i;unsigned ds[32];
  /* ---- memoire partagee ---- */
  id=shmget(0,8192,IPC_CREAT|0600);
  ktest("shm.get",id>=0);
  {char*a=(char*)shmat(id,0,0);ktest("shm.attach",(long)a>0&&(long)a!=-1);
   a[0]='P';a[5000]='Q';
   pid=fork();
   if(pid==0){char*b=(char*)shmat(id,0,0);if(a[0]!='P'||b[5000]!='Q')_exit(1);b[1]='C';a[2]='D';shmdt((long)b);_exit(0);}
   waitpid(pid,&st,0);
   ktest("shm.fork_shared",st==0&&a[1]=='C'&&a[2]=='D');
   ktest("shm.stat",shmctl(id,IPC_STAT,(long)ds)==0&&ds[9]==8192&&ds[16]==getpid()&&ds[18]==1);
   ktest("shm.einval",shmat(99999,0,0)==-22&&shmctl(99999,IPC_STAT,(long)ds)==-22&&shmdt(0x1234000)==-22);
   ktest("shm.rmid_keeps_attached",shmctl(id,IPC_RMID,0)==0&&a[0]=='P');
   ktest("shm.detach",shmdt((long)a)==0);}
  /* cle, EXCL, droits */
  id=shmget(0x1234,4096,IPC_CREAT|0644);
  ktest("shm.key",id>=0&&shmget(0x1234,4096,0)==id&&shmget(0x1234,4096,IPC_CREAT|IPC_EXCL)==-17&&shmget(0x4321,4096,0)==-2);
  ktest("shm.too_big",shmget(0x1235,1<<26,IPC_CREAT|0600)==-22);
  {char*a=(char*)shmat(id,0,0x1000);
   pid=fork();
   if(pid==0){*(volatile char*)a=1;_exit(0);}
   waitpid(pid,&st,0);ktest("shm.rdonly_write_faults",(st&0x7f)==11);
   shmdt((long)a);}
  {char*a=(char*)shmat(id,0x50000000,0);ktest("shm.fixed_addr",(long)a==0x50000000);shmdt((long)a);
   ktest("shm.misaligned",shmat(id,0x50000001,0)==-22);}
  /* nattch retombe a 0 a la sortie du processus */
  pid=fork();
  if(pid==0){shmat(id,0,0);_exit(0);}
  waitpid(pid,&st,0);
  ktest("shm.nattch_after_exit",shmctl(id,IPC_STAT,(long)ds)==0&&ds[18]==0);
  shmctl(id,IPC_RMID,0);
  /* ---- semaphores ---- */
  id=semget(0,3,IPC_CREAT|0600);
  ktest("sem.get",id>=0&&semctl(id,0,16,5)==0&&semctl(id,0,12,0)==5&&semctl(id,0,14,0)==0);
  {unsigned short all[3]={1,2,3},got[3];
   ktest("sem.setall_getall",semctl(id,0,17,(long)all)==0&&semctl(id,0,13,(long)got)==0&&got[0]==1&&got[1]==2&&got[2]==3);}
  ktest("sem.erange",semctl(id,0,16,40000)==-34&&semctl(id,9,12,0)==-22);
  {struct sembuf o={0,-1,IPC_NOWAIT};semctl(id,0,16,0);
   ktest("sem.nowait_eagain",semop2(id,&o,1)==-11);
   o.op=3;o.fl=0;ktest("sem.add",semop2(id,&o,1)==0&&semctl(id,0,12,0)==3);
   o.op=-2;ktest("sem.sub",semop2(id,&o,1)==0&&semctl(id,0,12,0)==1);
   o.n=5;ktest("sem.efbig",semop2(id,&o,1)==-27);}
  {struct sembuf o={0,-2,0};
   pid=fork();
   if(pid==0){nap(60);struct sembuf p={0,5,0};semop2(id,&p,1);_exit(0);}
   {long t0,t1;struct{long s,u;}a,b;sc2(78,(long)&a,0);r=semop2(id,&o,1);sc2(78,(long)&b,0);t0=a.s*1000+a.u/1000;t1=b.s*1000+b.u/1000;
    ktest("sem.blocking_decrement",r==0&&t1-t0>=40&&semctl(id,0,12,0)==4);}
   waitpid(pid,&st,0);}
  {struct sembuf z={0,0,IPC_NOWAIT};ktest("sem.zero_wait",semop2(id,&z,1)==-11&&({semctl(id,0,16,0);semop2(id,&z,1)==0;}));}
  {struct sembuf o={0,-1,0};long ts[2]={0,40000000};
      r=sc4(392,id,(long)&o,1,(long)ts);
   ktest("sem.semtimedop",r==-11);}
  /* SEM_UNDO */
  {struct sembuf u={1,4,SEM_UNDO};semctl(id,1,16,0);
   pid=fork();
   if(pid==0){semop2(id,&u,1);_exit(0);}
   waitpid(pid,&st,0);
   ktest("sem.undo_on_exit",semctl(id,1,12,0)==0);}
  /* RMID reveille un attendeur */
  {struct sembuf o={2,-1,0};semctl(id,2,16,0);
   pid=fork();
   if(pid==0){_exit(semop2(id,&o,1)==-43?0:1);}
   nap(50);semctl(id,0,0,0);
   waitpid(pid,&st,0);ktest("sem.rmid_eidrm",st==0&&semctl(id,0,12,0)==-22);}
  /* ---- messages ---- */
  id=msgget(0,IPC_CREAT|0600);
  ktest("msg.get",id>=0);
  {struct mb m,o;
   m.t=2;strcpy_(m.d,"deux");msgsnd(id,&m,5,0);
   m.t=1;strcpy_(m.d,"un");msgsnd(id,&m,3,0);
   m.t=3;strcpy_(m.d,"trois");msgsnd(id,&m,6,0);
   m.t=2;strcpy_(m.d,"bis");msgsnd(id,&m,4,0);
   ktest("msg.stat",msgctl(id,IPC_STAT,ds)==0&&ds[17]==4&&ds[16]==18);
   ktest("msg.recv_fifo",msgrcv(id,&o,64,0,0)==5&&o.t==2&&memcmp_(o.d,"deux",5)==0);
   ktest("msg.recv_type",msgrcv(id,&o,64,3,0)==6&&o.t==3);
   ktest("msg.recv_lowest",msgrcv(id,&o,64,-2,0)==3&&o.t==1);
   ktest("msg.recv_except",({m.t=7;msgsnd(id,&m,1,0);msgrcv(id,&o,64,2,0x2000);})==1&&o.t==7);
   ktest("msg.recv_remaining",msgrcv(id,&o,64,0,0)==4&&memcmp_(o.d,"bis",4)==0);
   ktest("msg.nowait_enomsg",msgrcv(id,&o,64,0,IPC_NOWAIT)==-42);
   m.t=9;memset(m.d,'x',40);msgsnd(id,&m,40,0);
   ktest("msg.e2big",msgrcv(id,&o,10,0,0)==-7);
   ktest("msg.noerror",msgrcv(id,&o,10,0,0x1000)==10&&o.t==9);
   ktest("msg.einval",msgsnd(id,&m,-1,0)==-22&&({m.t=0;msgsnd(id,&m,1,0);})==-22&&msgrcv(9999,&o,1,0,0)==-22);
   pid=fork();
   if(pid==0){nap(50);m.t=5;strcpy_(m.d,"wake");msgsnd(id,&m,5,0);_exit(0);}
   ktest("msg.blocking_recv",msgrcv(id,&o,64,5,0)==5&&memcmp_(o.d,"wake",5)==0);
   waitpid(pid,&st,0);
   { unsigned qb[23];msgctl(id,IPC_STAT,qb);qb[18]=100;
     ktest("msg.set_qbytes",msgctl(id,IPC_SET,qb)==0);
     m.t=1;memset(m.d,'y',60);
     ktest("msg.full_nowait",msgsnd(id,&m,60,IPC_NOWAIT)==0&&msgsnd(id,&m,60,IPC_NOWAIT)==-11);}
   msgrcv(id,&o,64,0,0);
   pid=fork();
   if(pid==0){_exit(msgrcv(id,&o,64,0,0)==-43?0:1);}
   nap(50);msgctl(id,IPC_RMID,0);waitpid(pid,&st,0);
   ktest("msg.rmid_eidrm",st==0&&msgsnd(id,&m,1,0)==-22);}
  /* ---- ipc(2) multiplexeur ---- */
  {long sid=sc6(117,23,0,4096,IPC_CREAT|0600,0,0);long ad=0;
   ktest("ipc2.shmget",sid>=0);
   ktest("ipc2.shmat",sc6(117,21,sid,0,(long)&ad,0,0)==0&&ad>0);
   ktest("ipc2.shmdt",sc6(117,22,0,0,0,ad,0)==0);
   ktest("ipc2.shmctl_rmid",sc6(117,24,sid,0,0,0,0)==0);
   {long q=sc6(117,13,0,IPC_CREAT|0600,0,0,0);ktest("ipc2.msgget",q>=0&&sc6(117,14,q,IPC_RMID,0,0,0)==0);}
   {long s=sc6(117,2,0,2,IPC_CREAT|0600,0,0);long arg=7;ktest("ipc2.semget_ctl",s>=0&&sc6(117,3,s,0,16,(long)&arg,0)==0&&sc6(117,3,s,0,12,0,0)==7&&sc6(117,3,s,0,0,0,0)==0);}
   ktest("ipc2.bad_call",sc6(117,77,0,0,0,0,0)==-38);}
  (void)i;(void)msgctl;
  puts("ipc DONE\n");
  return ku_fail?1:0;
}
