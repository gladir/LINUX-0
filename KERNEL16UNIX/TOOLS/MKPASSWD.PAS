{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal)
  @description: Calcule, sur la machine hote, le champ mot de passe d'une
  ligne de /etc/passwd de LINUX-0 (13 caracteres : sel de 2 caracteres puis
  11 caracteres de l'alphabet ./0-9A-Za-z), avec le meme hachage que login
  et passwd (KERNEL16UNIX/USR/CRYPT.INC). Utilise par KERNEL16UNIX/BUILD.SH pour le
  compte invite.

  Syntaxe :
   MKPASSWD mot_de_passe [sel]      (sel par defaut : "..")
}

Program MKPASSWD;

{$MODE OBJFPC}{$H+}

Const
 CryptChars: String[64] = './0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

Function Crypt(Pw, Salt: String): String;
Var A, B, C, D, X: Word; R, K, Bit, V: Integer; S: String;

 Function GetBit(N: Integer): Integer;
 Var W: Word;
 Begin
  Case N Div 16 Of 0: W := A; 1: W := B; 2: W := C; Else W := D End;
  If N >= 64 Then GetBit := 0
  Else GetBit := (W Shr (15 - N Mod 16)) And 1;
 End;

Begin
 Salt := Copy(Salt + '..', 1, 2);
 S := Salt + Pw;
 A := $6A09; B := $BB67; C := $3C6E; D := $A54F;
 For R := 1 To 32 Do
  For K := 1 To Length(S) Do Begin
   X := Ord(S[K]);
   A := Word(((Longint(A Xor X) * 31421) + 1) And $FFFF);
   B := Word(((Longint(B Xor A) * 31421) + X) And $FFFF);
   C := Word(((Longint(C Xor B) * 31421) + 7) And $FFFF);
   D := Word(((Longint(D Xor C) * 31421) + A) And $FFFF);
  End;
 Result := Salt; Bit := 0;
 For K := 1 To 11 Do Begin
  V := 0;
  For R := 1 To 6 Do Begin V := V * 2 + GetBit(Bit); Inc(Bit) End;
  Result := Result + CryptChars[V + 1];
 End;
End;

BEGIN
 If ParamCount < 1 Then Begin
  WriteLn('Syntaxe : MKPASSWD mot_de_passe [sel]');
  Halt(2);
 End;
 WriteLn(Crypt(ParamStr(1), ParamStr(2)));
END.
