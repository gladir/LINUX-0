{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal)
  @description: MKAPI : integre L32API.PAS (couche systeme Linux des
    programmes -3X) dans LPC32.PAS sous forme d'un tableau de constantes
    chaines, entre les reperes "BEGIN L32API" et "END L32API". A relancer
    apres chaque modification de L32API.PAS :
      fpc -Mtp MKAPI.PAS ; ./MKAPI
}

Program MKAPI;

Const
  LpcName  = 'LPC32.PAS';
  TmpName  = 'LPC32.TMP';
  Anchor   = 'Function D16EmbCount(Sel : Integer) : LongInt;';

Var
  Src, Lpc, Dst : Text;
  Lines : Array[1..8000] Of String;
  N, I, J : LongInt;
  S, T : String;
  InBlock, Done : Boolean;
  ApiName, Tag, Marker1, Marker2 : String;

Procedure Fail(Const Msg : String);
Begin
  WriteLn('MKAPI : ', Msg);
  Halt(1);
End;

{ ligne de L32API.PAS -> ligne de constante (apostrophes doublees) }
Function Quote(Const L : String) : String;
Var K : Integer; R : String;
Begin
  R := '';
  For K := 1 To Length(L) Do
    If L[K] = '''' Then R := R + '''''' Else R := R + L[K];
  Quote := R;
End;

Procedure WriteBlock;
Var K : LongInt;
Begin
  WriteLn(Dst, '{ BEGIN ', Tag, ' : genere par MKAPI.PAS depuis ' +
          ApiName + ' (ne pas editer) }');
  WriteLn(Dst, 'Const');
  WriteLn(Dst, '  ', Tag, '_N = ', N, ';');
  WriteLn(Dst, '  ', Tag, ' : Array[1..', Tag, '_N] Of String[120] = (');
  For K := 1 To N Do
  Begin
    Write(Dst, '    ''', Quote(Lines[K]), '''');
    If K < N Then WriteLn(Dst, ',') Else WriteLn(Dst);
  End;
  WriteLn(Dst, '  );');
  WriteLn(Dst, '{ END ', Tag, ' }');
End;

Procedure Process(AName, ATag : String);
Begin
  ApiName := AName; Tag := ATag;
  Marker1 := '{ BEGIN ' + Tag;
  Marker2 := '{ END ' + Tag + ' }';
  Assign(Src, ApiName);
  {$I-} Reset(Src); {$I+}
  If IOResult <> 0 Then Fail('lecture impossible : ' + ApiName);
  N := 0;
  While Not Eof(Src) Do
  Begin
    ReadLn(Src, S);
    While (Length(S) > 0) And (S[Length(S)] = ' ') Do Dec(S[0]);
    If N >= 8000 Then Fail(ApiName + ' trop long');
    Inc(N);
    Lines[N] := S;
  End;
  Close(Src);
  Assign(Lpc, LpcName);
  {$I-} Reset(Lpc); {$I+}
  If IOResult <> 0 Then Fail('lecture impossible : ' + LpcName);
  Assign(Dst, TmpName);
  Rewrite(Dst);
  InBlock := False;
  Done := False;
  While Not Eof(Lpc) Do
  Begin
    ReadLn(Lpc, S);
    If InBlock Then
    Begin
      If Copy(S, 1, Length(Marker2)) = Marker2 Then InBlock := False;
    End
    Else If (Not Done) And (Copy(S, 1, Length(Marker1)) = Marker1) Then
    Begin
      WriteBlock;
      InBlock := True;
      Done := True;
    End
    Else If (Not Done) And (S = Anchor) Then
    Begin
      WriteBlock;
      WriteLn(Dst);
      WriteLn(Dst, S);
      Done := True;
    End
    Else WriteLn(Dst, S);
  End;
  Close(Lpc);
  Close(Dst);
  If Not Done Then Fail('repere introuvable dans ' + LpcName);
  Erase(Lpc);
  Rename(Dst, LpcName);
  WriteLn('MKAPI : ', N, ' lignes (', ApiName, ') integrees dans ',
          LpcName);
End;

Begin
  Process('L32API.PAS', 'L32API');
  Process('L32GFX.PAS', 'L32GFX');
End.
