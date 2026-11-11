{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7)
  @description: Fabrique le fichier IO.SYS (noyau KERNEL16DOS) a partir de
    l'unite K16DOS : ecrit dans le repertoire courant le code compris
    entre BEGIN_KERNEL et END_KERNEL. Doit etre execute sous DOS.
}

Program MAKER;

Uses K16DOS;

Var
 SourceKernel:Pointer;
 KernelFile:File;
 ByteWrited:Word;

BEGIN
 SourceKernel:=@BEGIN_KERNEL;
 {$I-}Assign(KernelFile,'IO.SYS');
 Rewrite(KernelFile,1);{$I+}
 If IOResult<>0 Then Begin
  WriteLn('Impossible d''ecrire IO.SYS');
  Halt(1);
 End;
 BlockWrite(KernelFile,SourceKernel^,Ofs(END_KERNEL)+1,ByteWrited);
 Close(KernelFile);
END.
