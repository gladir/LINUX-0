{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal)
  @description: Affiche et verifie un executable COFF de LINUX-0 (produit
  par LPC /X) : en-tete de fichier, en-tete a.out, sections et
  relocalisations.

  Syntaxe :
   COFFINFO fichier [...]     (code de sortie 1 si un fichier est incoherent)
}

Program COFFINFO;

{$MODE OBJFPC}{$H+}

Type
 TBytes = Array of Byte;
 TSec = Record
  Name: String;
  VAddr, Size, ScnPtr, RelPtr: Longint;
  NRel: Word;
  Flags: Longint;
 End;

Var
 D: TBytes;
 Errs: Array of String;
 I, K, Bad: Integer;

Function Hex(V: Longint; N: Integer): String;
Const H: String[16] = '0123456789ABCDEF';
Begin
 Result := '';
 While N > 0 Do Begin
  Result := H[(V And 15) + 1] + Result;
  V := V Shr 4;
  Dec(N);
 End;
End;

Function Pad(S: String; N: Integer; Left: Boolean): String;
Begin
 Result := S;
 While Length(Result) < N Do
  If Left Then Result := ' ' + Result Else Result := Result + ' ';
End;

Function IStr(V: Int64): String;
Begin
 Str(V, Result);
End;

Function B8(O: Longint): Byte;     { 0 au-dela de la fin du fichier }
Begin
 If (O >= 0) And (O < Length(D)) Then B8 := D[O] Else B8 := 0;
End;

Function W16(O: Longint): Word;
Begin
 W16 := B8(O) Or (B8(O + 1) Shl 8);
End;

Function L32(O: Longint): Longint;
Begin
 L32 := Longint(Longword(B8(O)) Or (Longword(B8(O + 1)) Shl 8) Or
                (Longword(B8(O + 2)) Shl 16) Or (Longword(B8(O + 3)) Shl 24));
End;

Procedure Err(S: String);
Begin
 SetLength(Errs, Length(Errs) + 1);
 Errs[High(Errs)] := S;
End;

Function LoadFile(Path: String): Boolean;
Var F: File; N: Longint;
Begin
 Assign(F, Path);
 {$I-} Reset(F, 1); {$I+}
 If IOResult <> 0 Then Exit(False);
 N := FileSize(F);
 SetLength(D, N);
 If N > 0 Then BlockRead(F, D[0], N);
 Close(F);
 Result := True;
End;

Procedure Check(Path: String);
Var
 Magic, NScns, OptHdr, Flags, OMagic: Word;
 TSize, DSize, BSize, Entry, DStart: Longint;
 Secs: Array of TSec;
 K, R, O, Rv: Longint;
 Typ: Word;
 S: TSec;
 HasStack: Boolean;
 A, B: Integer;
Begin
 SetLength(Errs, 0);
 If Not LoadFile(Path) Then Begin
  WriteLn(Path, ' : fichier introuvable');
  Err('lecture impossible');
  Exit;
 End;
 If Length(D) < 20 Then Begin
  WriteLn(Path, ' : fichier trop court');
  Err('en-tete COFF incomplet');
  Exit;
 End;
 Magic := W16(0); NScns := W16(2); OptHdr := W16(16); Flags := W16(18);
 WriteLn(Path, ' : f_magic=', Hex(Magic, 4), 'h f_nscns=', NScns,
         ' f_opthdr=', OptHdr, ' f_flags=', Hex(Flags, 4), 'h');
 If Magic <> $0153 Then Begin
  Err('f_magic ' + Hex(Magic, 4) + 'h, attendu 0153h (I286LMAGIC)');
  Exit;
 End;
 If Flags And 2 = 0 Then Err('F_EXEC absent');
 OMagic := W16(20); TSize := L32(24); DSize := L32(28); BSize := L32(32);
 Entry := L32(36); DStart := L32(44);
 WriteLn('  a.out : magic=', Hex(OMagic, 4), 'h tsize=', TSize, ' dsize=', DSize,
         ' bsize=', BSize, ' entry=', Hex(Entry, 5), 'h data_start=', Hex(DStart, 5), 'h');
 SetLength(Secs, NScns);
 For K := 0 To NScns - 1 Do Begin
  O := 20 + OptHdr + K * 40;
  S.Name := '';
  For R := 0 To 7 Do
   If B8(O + R) <> 0 Then S.Name := S.Name + Chr(B8(O + R)) Else Break;
  S.VAddr := L32(O + 12); S.Size := L32(O + 16); S.ScnPtr := L32(O + 20);
  S.RelPtr := L32(O + 24); S.NRel := W16(O + 32); S.Flags := L32(O + 36);
  Secs[K] := S;
  WriteLn('  ', Pad(S.Name, 8, False), ' vaddr=', Hex(S.VAddr, 5), 'h taille=',
          Pad(IStr(S.Size), 6, True), ' fichier=', Pad(IStr(S.ScnPtr), 6, True),
          ' reloc=', Pad(IStr(S.NRel), 4, True), ' flags=', Hex(S.Flags, 2), 'h');
  { .bss prolonge .data dans DS }
  If (S.VAddr Mod 16 <> 0) And (S.Name <> '.bss') Then
   Err(S.Name + ' : s_vaddr non aligne sur un paragraphe');
  If (S.Flags And $80 = 0) And (S.Size <> 0) And (Int64(S.ScnPtr) + S.Size > Length(D)) Then
   Err(S.Name + ' : contenu hors du fichier');
  If (S.NRel > 0) And (Int64(S.RelPtr) + S.NRel * 10 > Length(D)) Then
   Err(S.Name + ' : relocalisations hors du fichier')
  Else For R := 0 To S.NRel - 1 Do Begin
   Rv := L32(S.RelPtr + R * 10);
   Typ := W16(S.RelPtr + R * 10 + 8);
   If Typ <> 9 Then Err(S.Name + ' : r_type ' + IStr(Typ) + ' inconnu');
   If Not ((S.VAddr <= Rv) And (Rv + 2 <= S.VAddr + S.Size)) Then
    Err(S.Name + ' : relocalisation ' + Hex(Rv, 5) + 'h hors section');
  End;
 End;
 HasStack := False;
 For K := 0 To NScns - 1 Do
  If Secs[K].Name = '.stack' Then HasStack := True;
 If Not HasStack Then Err('section .stack absente');
 For A := 0 To NScns - 1 Do
  For B := 0 To NScns - 1 Do
   If (A <> B) And (Secs[A].VAddr < Secs[B].VAddr + Secs[B].Size) And
      (Secs[B].VAddr < Secs[A].VAddr + Secs[A].Size) And
      (Secs[A].Size <> 0) And (Secs[B].Size <> 0) Then
    Err('sections ' + Secs[A].Name + ' et ' + Secs[B].Name + ' se recouvrent');
End;

BEGIN
 If ParamCount = 0 Then Begin
  WriteLn('Syntaxe : COFFINFO fichier [...]');
  Halt(2);
 End;
 Bad := 0;
 For I := 1 To ParamCount Do Begin
  Check(ParamStr(I));
  If Length(Errs) > 0 Then Begin
   For K := 0 To High(Errs) Do WriteLn('  ERREUR ', Errs[K]);
   Bad := 1;
  End;
 End;
 Halt(Bad);
END.
