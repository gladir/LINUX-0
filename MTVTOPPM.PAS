{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Convertit une image MTV ou PRT en PPM couleur
}

Program MTVTOPPM;

{$IFDEF FPC}
 {$MODE TP}
 {$H-}
{$ENDIF}

Uses DOS;

Const
 BufferSize=4096;
 MaxLong=2147483647;

Var
 InFile,OutFile:File;
 InBuffer:Array[0..BufferSize-1]of Byte;
 InPos,InLen:Word;
 InputName,Argument,Header,S:String;
 Width,Height,Remaining:Longint;
 I,B:Integer;
 Count:Word;
 English,UseStdin,InputOpen,OutputOpen,EndOptions,HaveFile:Boolean;

Function StrToUpper(Value:String):String;
Var
 J:Integer;
Begin
 For J:=1 to Length(Value)Do
  If Value[J]in['a'..'z']Then Value[J]:=Chr(Ord(Value[J])-32);
 StrToUpper:=Value;
End;

Function Message(Const French,Eng:String):String;
Begin
 If English Then Message:=Eng Else Message:=French;
End;

Procedure Fail(Const Text:String);
{$IFNDEF FPC}
Var
 R:Registers;
 Line:String;
{$ENDIF}
Begin
 {$IFDEF FPC}
 WriteLn(StdErr,'mtvtoppm: ',Text);
 {$ELSE}
 Line:='mtvtoppm: '+Text+#13+#10;
 R.AH:=$40;
 R.BX:=2;
 R.CX:=Length(Line);
 R.DS:=Seg(Line[1]);
 R.DX:=Ofs(Line[1]);
 MsDos(R);
 {$ENDIF}
 Halt(1);
End;

Procedure ShowHelp;
Begin
 WriteLn('MTVTOPPM : ',Message(
  'Cette commande permet de convertir une image du traceur MTV ou PRT en PPM couleur.',
  'Converts an MTV or PRT ray tracer image to a color PPM.'));
 WriteLn;
 WriteLn(Message(
  'Syntaxe: mtvtoppm [mtvfile]',
  'Usage: mtvtoppm [mtvfile]'));
 WriteLn;
 WriteLn(Message(
  '  mtvfile     Fichier MTV; absent ou - : entree standard.',
  '  mtvfile     MTV file; omitted or -: standard input.'));
 WriteLn(Message(
  '  /?, --help, -h, /h, /H   Affiche cette aide.',
  '  /?, --help, -h, /h, /H   Show this help.'));
 WriteLn('  --version');
 WriteLn(Message(
  '  --          Fin des options.',
  '  --          End of options.'));
 WriteLn;
 WriteLn(Message(
  'Entree : largeur hauteur sur une ligne, puis 3 octets RVB par pixel.',
  'Input: width height on one line, then 3 RGB bytes per pixel.'));
 WriteLn(Message(
  'Sortie standard : PPM binaire P6, valeur maximale 255.',
  'Standard output: binary PPM P6, maximum value 255.'));
 WriteLn(Message(
  'Dimensions positives; taille RVB limitee a 2147483647 octets.',
  'Positive dimensions; RGB size limited to 2147483647 bytes.'));
 WriteLn;
 WriteLn('  mtvtoppm image.mtv > image.ppm');
 WriteLn('  mtvtoppm < image.mtv > image.ppm');
End;

Procedure ReadBuffer;
Var
 Code:Integer;
 {$IFNDEF FPC}
 R:Registers;
 {$ENDIF}
Begin
 InPos:=0;
 {$IFNDEF FPC}
 If UseStdin Then Begin
  R.AH:=$3F;
  R.BX:=0;
  R.CX:=BufferSize;
  R.DS:=Seg(InBuffer);
  R.DX:=Ofs(InBuffer);
  MsDos(R);
  If(R.Flags And FCarry)<>0Then
   Fail(Message('erreur de lecture de l''entree standard',
                'error reading standard input'));
  InLen:=R.AX;
 End
 Else
 {$ENDIF}
 Begin
  {$I-}BlockRead(InFile,InBuffer,BufferSize,InLen);{$I+}
  Code:=IOResult;
  If Code<>0Then Fail(Message('erreur de lecture','read error'));
 End;
End;

Function GetByte:Integer;
Begin
 If InPos=InLen Then ReadBuffer;
 If InLen=0Then GetByte:=-1
 Else Begin
  GetByte:=InBuffer[InPos];
  Inc(InPos);
 End;
End;

Procedure WriteBytes(Var Data;Size:Word);
Var
 Written:Word;
 {$IFDEF FPC}
 Code:Integer;
 {$ELSE}
 R:Registers;
 {$ENDIF}
Begin
 {$IFDEF FPC}
 {$I-}BlockWrite(OutFile,Data,Size,Written);{$I+}
 Code:=IOResult;
 If Code<>0Then Fail(Message(
  'erreur d''ecriture sur la sortie standard','error writing standard output'));
 {$ELSE}
 R.AH:=$40;
 R.BX:=1;
 R.CX:=Size;
 R.DS:=Seg(Data);
 R.DX:=Ofs(Data);
 MsDos(R);
 If(R.Flags And FCarry)<>0Then Fail(Message(
  'erreur d''ecriture sur la sortie standard','error writing standard output'));
 Written:=R.AX;
 {$ENDIF}
 If Written<>Size Then Fail(Message(
  'ecriture incomplete sur la sortie standard','short write on standard output'));
End;

Function ReadDimension:Longint;
Var
 Value:Longint;
 Digit:Integer;
Begin
 While(B=9)Or(B=13)Or(B=32)Do B:=GetByte;
 If(B<Ord('0'))Or(B>Ord('9'))Then
  Fail(Message('en-tete MTV invalide : dimension attendue',
               'invalid MTV header: expected a dimension'));
 Value:=0;
 While(B>=Ord('0'))And(B<=Ord('9'))Do Begin
  Digit:=B-Ord('0');
  If Value>(MaxLong-Digit)Div 10Then
   Fail(Message('dimension trop grande','dimension too large'));
  Value:=Value*10+Digit;
  B:=GetByte;
 End;
 If Value=0Then Fail(Message('les dimensions doivent etre positives',
                            'dimensions must be positive'));
 ReadDimension:=Value;
End;

BEGIN
 English:=StrToUpper(GetEnv('LANGUAGE'))='EN';
 InputOpen:=False;
 OutputOpen:=False;
 InputName:='';
 HaveFile:=False;
 EndOptions:=False;
 For I:=1 to ParamCount Do Begin
  Argument:=ParamStr(I);
  If Not EndOptions And(Argument='--')Then EndOptions:=True
  Else If Not EndOptions And
    ((Argument='/?')Or(Argument='--help')Or(Argument='-h')Or
     (Argument='/h')Or(Argument='/H'))Then Begin
   ShowHelp;
   Halt(0);
  End
  Else If Not EndOptions And(Argument='--version')Then Begin
   WriteLn('MTVTOPPM - Version 1.0-Pascal');
   Halt(0);
  End
  Else Begin
   If Not EndOptions And(Length(Argument)>1)Then
    If Argument[1]='-'Then
     Fail(Message('option inconnue : ','unknown option: ')+Argument);
   If HaveFile Then Fail(Message('un seul fichier est accepte',
                                 'only one input file is accepted'));
   If Argument=''Then Fail(Message('nom de fichier vide','empty file name'));
   InputName:=Argument;
   HaveFile:=True;
  End;
 End;
 UseStdin:=(Not HaveFile)Or(InputName='-');
 If UseStdin Then InputName:='';
 {$IFDEF FPC}
 Assign(InFile,InputName);
 {$ELSE}
 If Not UseStdin Then Begin
 Assign(InFile,InputName);
 {$ENDIF}
 FileMode:=0;
 {$I-}Reset(InFile,1);{$I+}
 If IOResult<>0Then Fail(Message('impossible d''ouvrir l''entree : ',
                                 'cannot open input: ')+InputName);
 {$IFDEF FPC}
 { Sous Windows, les handles standard ne sont pas les descripteurs DOS 0 et 1. }
 If UseStdin Then FileRec(InFile).Handle:=StdInputHandle;
 {$ENDIF}
 InputOpen:=True;
 {$IFNDEF FPC}
 End;
 {$ENDIF}
 InPos:=0;
 InLen:=0;
 B:=GetByte;
 Width:=ReadDimension;
 If(B<>9)And(B<>13)And(B<>32)Then
  Fail(Message('en-tete MTV invalide : separateur attendu',
               'invalid MTV header: expected a separator'));
 Height:=ReadDimension;
 While(B=9)Or(B=13)Or(B=32)Do B:=GetByte;
 If B<>10Then Fail(Message('en-tete MTV invalide : fin de ligne attendue',
                           'invalid MTV header: expected end of line'));
 If Width>MaxLong Div 3Then
  Fail(Message('image trop grande','image too large'));
 Remaining:=Width*3;
 If Height>MaxLong Div Remaining Then
  Fail(Message('image trop grande','image too large'));
 Remaining:=Remaining*Height;
 {$IFDEF FPC}
 Assign(OutFile,'');
 {$I-}Rewrite(OutFile,1);{$I+}
 If IOResult<>0Then Fail(Message('impossible d''ouvrir la sortie standard',
                                 'cannot open standard output'));
 FileRec(OutFile).Handle:=StdOutputHandle;
 OutputOpen:=True;
 {$ENDIF}
 Str(Width,S);
 Header:='P6'+#10+S+' ';
 Str(Height,S);
 Header:=Header+S+#10+'255'+#10;
 WriteBytes(Header[1],Length(Header));
 While Remaining>0Do Begin
  If InPos=InLen Then ReadBuffer;
  If InLen=0Then Fail(Message('donnees RVB tronquees','truncated RGB data'));
  Count:=InLen-InPos;
  If Remaining<Count Then Count:=Remaining;
  WriteBytes(InBuffer[InPos],Count);
  Inc(InPos,Count);
  Remaining:=Remaining-Count;
 End;
 If InputOpen Then Begin
  {$I-}Close(InFile);{$I+}
  InputOpen:=False;
  If IOResult<>0Then Fail(Message('erreur de fermeture de l''entree',
                                  'error closing input'));
 End;
 If OutputOpen Then Begin
  {$I-}Close(OutFile);{$I+}
  OutputOpen:=False;
  If IOResult<>0Then Fail(Message('erreur de fermeture de la sortie',
                                  'error closing output'));
 End;
END.
