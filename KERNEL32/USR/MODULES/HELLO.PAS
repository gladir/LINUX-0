{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3M)
  @description: module d'exemple : ecrit des messages dans le journal du
      noyau au chargement (insmod) et au dechargement (rmmod). Compile par
      BUILD.SH (lpc -3M) et installe dans /lib/modules/hello.ko.
}

Program HELLO;

Procedure printk(Const S : String); External;

Procedure InitHello; ModuleInit;
Begin
  printk('hello: module charge');
End;

Procedure ExitHello; ModuleExit;
Begin
  printk('hello: module decharge');
End;

Begin
End.
