/* jrntest : journal ext3/ext4 et arret brutal. Ne fait rien sans "jrntest"
   sur la ligne de commande du noyau. Pilote par TESTS/K/RUNJRN.SH :
     jrnwrite  : monte /dev/hda1, cree/supprime/renomme/tronque, sync()
                 (avec jcrash=N le noyau s'arrete brutalement pendant la
                 validation du journal)
     jrnpresent: monte (le journal est rejoue) et verifie que tout est la
     jrnabsent : monte et verifie que rien de la transaction n'est visible */
#include "ku.h"

#define SYS_truncate 92
#define SYS_fsync 118
static int truncate(const char*p,long n){return sc2(SYS_truncate,(long)p,n);}
static int stat64(const char*p,void*b){return sc2(SYS_stat64,(long)p,(long)b);}
#define ST_SIZE(b) (*(unsigned*)((b)+44))
static unsigned char sb_[96];
static unsigned char wb[8192];
static unsigned char pat(unsigned i,unsigned s){return (unsigned char)(i*11+(i>>6)+s);}
static void num(char*d,const char*p,int v){
  int l=strlen(p);
  while(*p){*d++=*p++;}
  d[0]='0'+(v/10)%10;d[1]='0'+v%10;d[2]=0;(void)l;
}
static int check(const char*p,unsigned n,unsigned s){
  int fd=open(p,O_RDONLY,0);unsigned done=0;
  if(fd<0)return 0;
  while(done<n){
    unsigned c=n-done,i;int r;
    if(c>sizeof wb)c=sizeof wb;
    r=read(fd,wb,c);
    if(r<=0){close(fd);return 0;}
    for(i=0;i<(unsigned)r;i++)if(wb[i]!=pat(done+i,s)){close(fd);return 0;}
    done+=r;
  }
  close(fd);
  return 1;
}

int main(void){
  int fd,i,r;
  char nm[64];
  if(!ku_cmdline_has("jrntest"))return 0;
  r=mount("/dev/hda1","/mnt","ext4",0,(long)(ku_cmdline_has("jrnwb")?"data=writeback":0));
  ktest("jrn.mount",r==0);
  if(r!=0)return 1;
  if(ku_cmdline_has("jrnorphan")){
    if(ku_cmdline_has("jrnwrite")){
      /* fichier supprime mais encore ouvert au moment de l'arret : inode orphelin */
      unsigned k,done=0;
      fd=open("/mnt/orph",O_RDWR|O_CREAT|O_TRUNC,0644);
      while(done<300000){for(k=0;k<sizeof wb;k++)wb[k]=pat(done+k,3);write(fd,wb,sizeof wb);done+=sizeof wb;}
      unlink("/mnt/orph");
      write(fd,wb,1000);
      sync();
      puts("KTEST: jrn.write_done\n");
      ktest("jrn.write_survived",1);
      close(fd);
      umount("/mnt");
      return 0;
    }
    ktest("jrn.orph_gone",access("/mnt/orph",0)==-2);
    umount("/mnt");
    puts("KTEST: jrn DONE\n");
    return ku_fail?1:0;
  }
  if(ku_cmdline_has("jrnwrite")){
    mkdir("/mnt/jw",0755);
    mkdir("/mnt/jw/sub",0755);
    for(i=0;i<30;i++){
      unsigned n=i*997+100,k,done=0;
      num(nm,"/mnt/jw/f",i);
      fd=open(nm,O_WRONLY|O_CREAT|O_TRUNC,0644);
      while(done<n){
        unsigned c=n-done;
        if(c>sizeof wb)c=sizeof wb;
        for(k=0;k<c;k++)wb[k]=pat(done+k,i);
        write(fd,wb,c);done+=c;
      }
      close(fd);
    }
    symlink("f05","/mnt/jw/lien");
    rename("/mnt/jw/f07","/mnt/jw/sub/f07");
    unlink("/mnt/jw/f08");
    unlink("/mnt/hello.txt");
    truncate("/mnt/big.bin",1000);
    sync();
    puts("KTEST: jrn.write_done\n");
    ktest("jrn.write_survived",1);
    umount("/mnt");
    return 0;
  }
  if(ku_cmdline_has("jrnpresent")){
    int ok=1;
    for(i=0;i<30;i++){
      unsigned n=i*997+100;
      if(i==8)continue;
      if(i==7)strcpy_(nm,"/mnt/jw/sub/f07");else num(nm,"/mnt/jw/f",i);
      if(ku_cmdline_has("jrnwb")){      /* writeback : taille seulement, pas le contenu */
        stat64(nm,sb_);
        if(ST_SIZE(sb_)!=n)ok=0;
      } else if(!check(nm,n,i))ok=0;
    }
    ktest("jrn.present_files",ok);
    ktest("jrn.present_unlinked",access("/mnt/jw/f08",0)==-2&&access("/mnt/hello.txt",0)==-2&&access("/mnt/jw/f07",0)==-2);
    stat64("/mnt/big.bin",sb_);
    ktest("jrn.present_truncated",ST_SIZE(sb_)==1000);
    ktest("jrn.present_symlink",({char c[16];readlink("/mnt/jw/lien",c,16)==3;}));
  } else {
    stat64("/mnt/big.bin",sb_);
    ktest("jrn.absent_dir",access("/mnt/jw",0)==-2);
    ktest("jrn.absent_old_state",access("/mnt/hello.txt",0)==0&&ST_SIZE(sb_)==300000);
  }
  umount("/mnt");
  puts("KTEST: jrn DONE\n");
  return ku_fail?1:0;
}
