{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7)
  @description: Test du noyau KERNEL16DOS : affiche l'environnement recu,
    la liste de la racine par un chemin '/' et lit un fichier par '/'.
    Copier sous le nom \BIN\SH.EXE d'une image pour l'essayer.
}

Program TKENV;

Uses DOS;

Var
 I:Integer;
 Info:SearchRec;
 F:File;
 Buf:Array[0..15] of Char;
 Got:Word;

BEGIN
 WriteLn('--- TKENV : environnement ---');
 For I:=1 to EnvCount do WriteLn(EnvStr(I));
 WriteLn('--- FindFirst(/*.*) ---');
 FindFirst('/*.*',AnyFile,Info);
 While DosError=0 do Begin
  Write(Info.Name,' ');
  FindNext(Info);
 End;
 WriteLn;
 WriteLn('--- lecture de /IO.SYS ---');
 Assign(F,'/IO.SYS');
 {$I-}Reset(F,1);{$I+}
 If IOResult<>0 Then WriteLn('Echec ouverture /IO.SYS')
  Else Begin
   BlockRead(F,Buf,4,Got);
   WriteLn('Octets lus : ',Got,' taille=',FileSize(F));
   Close(F);
  End;
 WriteLn('LANGUAGE=',GetEnv('LANGUAGE'));
 WriteLn('--- fin ---');
 ReadLn;
END.
