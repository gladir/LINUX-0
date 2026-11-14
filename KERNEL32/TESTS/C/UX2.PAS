{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: Programme de test UX2 : fichiers, repertoires, recherche,
    ligne de commande, environnement, temps (runtime Pascal et unite Dos
    au-dessus des appels systeme Linux i386).
}

Program UX2;

Uses Dos;

Var
  F : Text;
  G : File;
  S : String;
  Buf : Array[1..64] Of Byte;
  N : Word;
  Info : SearchRec;
  Cnt : Integer;
  Y, M, D, DW, H, Mi, Sc, Cs : Word;

Begin
  WriteLn('args=', ParamCount, ' ', ParamStr(1), ' ', ParamStr(2));
  S := GetEnv('LINUX0TEST');
  WriteLn('env=', S);
  Assign(F, 'ux2.tmp');
  Rewrite(F);
  WriteLn(F, 'ligne un');
  WriteLn(F, 'ligne deux');
  Close(F);
  Assign(F, 'ux2.tmp');
  Reset(F);
  While Not Eof(F) Do
  Begin
    ReadLn(F, S);
    WriteLn('lu: ', S);
  End;
  Close(F);
  Assign(G, 'ux2.tmp');
  Reset(G, 1);
  WriteLn('taille=', FileSize(G));
  Seek(G, 6);
  BlockRead(G, Buf, 3, N);
  WriteLn('apres seek: ', Chr(Buf[1]), Chr(Buf[2]), Chr(Buf[3]), ' n=', N);
  Close(G);
  MkDir('ux2.dir');
  Assign(F, 'ux2.dir/a.txt'); Rewrite(F); Close(F);
  Assign(F, 'ux2.dir/b.txt'); Rewrite(F); Close(F);
  Cnt := 0;
  FindFirst('ux2.dir/*.txt', AnyFile, Info);
  While DosError = 0 Do
  Begin
    Inc(Cnt);
    FindNext(Info);
  End;
  WriteLn('fichiers=', Cnt);
  Assign(F, 'ux2.dir/a.txt'); Erase(F);
  Assign(F, 'ux2.dir/b.txt'); Erase(F);
  RmDir('ux2.dir');
  Assign(F, 'ux2.tmp'); Erase(F);
  GetDate(Y, M, D, DW);
  GetTime(H, Mi, Sc, Cs);
  If (Y >= 2024) And (M >= 1) And (M <= 12) And (D >= 1) And (D <= 31) Then
    WriteLn('date ok')
  Else WriteLn('date mauvaise ', Y);
  If DiskFree(0) > 0 Then WriteLn('disque ok');
  WriteLn(FExpand('/tmp/../tmp/./x'));
  Halt(3);
End.
