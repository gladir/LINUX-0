{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: VTDRV : banc d'essai de VTCORE.INC. Lit des octets sur
   l'entree standard, les envoie a l'emulateur VT100 (80x24 par defaut,
   VTDRV colonnes lignes) et affiche l'ecran final : une ligne "R<n>:" par
   ligne non vide, puis "CUR x y", "SB n", "OUT hexa" (reponses). }

Program VtDrv;

{$I VTCORE.INC}

Function HexB(V : LongInt) : String;
Const H : String[16] = '0123456789ABCDEF';
Begin
  HexB := H[(V Shr 4) + 1] + H[(V And 15) + 1];
End;

Var
  C, R, Y, N, K : LongInt;
  B : Byte;
  Buf : Array[0..4095] Of Byte;
  A : String;
Begin
  C := 80;
  R := 24;
  If SysArgCount > 2 Then
  Begin
    Val(SysArgStr(1), C, K);
    Val(SysArgStr(2), R, K);
  End;
  VtInit(C, R);
  While True Do
  Begin
    N := SysRead(0, Buf[0], 4096);
    If N <= 0 Then Break;
    For K := 0 To N - 1 Do VtPut(Buf[K]);
  End;
  For Y := 0 To VtRows - 1 Do
    If VtRowText(Y) <> '' Then SysPut(1, 'R' + NumStr(Y) + ':' + VtRowText(Y) +
                                      #10);
  SysPut(1, 'CUR ' + NumStr(VtCx) + ' ' + NumStr(VtCy) + #10);
  SysPut(1, 'SB ' + NumStr(SbN) + #10);
  For Y := 0 To SbN - 1 Do
    If Y < 3 Then SysPut(1, 'S' + NumStr(Y) + ':' + VtSbText(Y) + #10);
  A := '';
  For K := 1 To Length(VtOut) Do A := A + HexB(Ord(VtOut[K]));
  SysPut(1, 'OUT ' + A + #10);
  SysPut(1, 'AT ' + NumStr(VtAt[VtIdx(0, 0)]) + ' ' + NumStr(VtFl[VtIdx(0, 0)])
         + #10);
End.
