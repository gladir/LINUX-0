{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program ASCIITOPGM(Input,Output);

Uses DOS;

Const
  MaxWidth=4096;
  PGMMaxValue=127;
  GrayMap:Array[0..127]Of Byte=(
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    $00,$21,$1B,$7F,$70,$25,$20,$0A,
    $11,$11,$2A,$2B,$0B,$13,$04,$10,
    $30,$28,$32,$68,$39,$35,$39,$16,
    $38,$39,$14,$15,$11,$1C,$11,$3F,
    $40,$49,$52,$18,$44,$3C,$38,$38,
    $55,$28,$2A,$70,$16,$7F,$70,$14,
    $60,$20,$62,$53,$1A,$55,$36,$57,
    $50,$4C,$5A,$24,$10,$24,$5E,$13,
    $60,$61,$62,$63,$64,$65,$66,$67,
    $68,$69,$6A,$6B,$6C,$6D,$6E,$2A,
    $70,$71,$72,$73,$74,$75,$76,$77,
    $78,$79,$7A,$7B,$7C,$7D,$7E,$7F
  );

Type
  TGrayRow=Array[1..MaxWidth]Of LongInt;

Var
  InputFile:Text;
  InputStream:^Text;
  GrayRow:TGrayRow;
  InputName,CurrentArg,NumberText:String;
  Width,Height,Divisor,OutputRow,Column:LongInt;
  ArgumentIndex,ErrorCode:Integer;
  UseInputFile,AtLineStart,PendingBreak,RowExists:Boolean;
  C:Char;

Function ParsePositive(Const S:String; Var Value:LongInt):Boolean;
Begin
  Val(S,Value,ErrorCode);
  ParsePositive:=(ErrorCode=0)and(Value>0);
End;

Function StrToUpper(S:String):String;
Var
  I:Integer;
Begin
  For I:=1 to Length(S)Do
    If S[I]in['a'..'z']Then S[I]:=Chr(Ord(S[I])-32);
  StrToUpper:=S;
End;

Function Darkness(C:Char):LongInt;
Var
  Code:Byte;
Begin
  Code:=Byte(C)and $7F;
  Darkness:=GrayMap[Code]div Divisor;
End;

Procedure ClearRow;
Var
  I:LongInt;
Begin
  For I:=1 to Width Do GrayRow[I]:=0;
End;

Procedure WriteRasterByte(Value:Byte);
Begin
  Write(Output,Chr(Value));
End;

Procedure FlushRow;
Var
  I:LongInt;
  GrayValue:LongInt;
Begin
  If OutputRow<Height Then Begin
    For I:=1 to Width Do Begin
      GrayValue:=PGMMaxValue-GrayRow[I];
      If GrayValue<0 Then GrayValue:=0;
      WriteRasterByte(Byte(GrayValue));
    End;
    Inc(OutputRow);
  End;
  ClearRow;
End;

Function ReadInputChar(Var Ch:Char):Boolean;
Begin
  If EOF(InputStream^)Then Begin
    ReadInputChar:=False;
    Exit;
  End;
  Read(InputStream^,Ch);
  ReadInputChar:=True;
End;

Procedure ConvertInput;
Var
  HasChar:Boolean;
  Blackness:LongInt;
Begin
  OutputRow:=0;
  Column:=0;
  AtLineStart:=True;
  PendingBreak:=False;
  RowExists:=False;
  ClearRow;
  WriteLn(Output,'P5');
  WriteLn(Output,Width,' ',Height);
  WriteLn(Output,PGMMaxValue);
  HasChar:=ReadInputChar(C);
  While HasChar Do Begin
    If C=#10 Then Begin
      If PendingBreak Then FlushRow;
      PendingBreak:=True;
      AtLineStart:=True;
      RowExists:=True;
    End
     Else Begin
      If AtLineStart Then Begin
        If C='+'Then Begin
          AtLineStart:=False;
          PendingBreak:=False;
          RowExists:=True;
          Column:=0;
          HasChar:=ReadInputChar(C);
          Continue;
        End
         Else Begin
          If PendingBreak Then FlushRow;
          AtLineStart:=False;
          PendingBreak:=False;
          RowExists:=True;
          Column:=0;
        End;
      End;
      If C<>#0 Then Begin
        Blackness:=Darkness(C);
        If Column<Width Then Begin
          GrayRow[Column+1]:=GrayRow[Column+1]+Blackness;
          If GrayRow[Column+1]>PGMMaxValue Then
            GrayRow[Column+1]:=PGMMaxValue;
        End;
        Inc(Column);
      End;
    End;
    HasChar:=ReadInputChar(C);
  End;
  If RowExists Then FlushRow;
  While OutputRow<Height Do FlushRow;
End;

Procedure PrintHelp;
Begin
  If Copy(StrToUpper(GetEnv('LANGUAGE')),1,2)='EN'Then Begin
    WriteLn('ASCIITOPGM : Convert ASCII graphics to a PGM image.');
    WriteLn('Syntax: asciitopgm [-d divisor] height width [asciifile]');
    WriteLn('Each character is a pixel; a leading + overstrikes the previous row.');
    WriteLn('Output is raw PGM P5 with maxval 127.');
  End Else Begin
    WriteLn('ASCIITOPGM : Cette commande permet de convertir un dessin ASCII en image PGM.');
    WriteLn;
    WriteLn('Syntaxe : asciitopgm [-d diviseur] hauteur largeur [fichier]');
    WriteLn;
    WriteLn('Chaque caractere est un pixel; un + initial superpose la ligne precedente.');
    WriteLn('La sortie est un PGM brut P5 de valeur maximale 127.');
  End;
End;

BEGIN
  Divisor:=1;
  Width:=0;
  Height:=0;
  InputName:='';
  UseInputFile:=False;
  ArgumentIndex:=1;
  If ParamCount=0 Then Begin
    PrintHelp;
    Halt(2);
  End;
  While ArgumentIndex<=ParamCount Do Begin
    CurrentArg:=ParamStr(ArgumentIndex);
    If(CurrentArg='--help')or(CurrentArg='-h')or(CurrentArg='/?')or
      (CurrentArg='/h')or(CurrentArg='/H')Then Begin
      PrintHelp;
      Halt(0);
    End Else If(CurrentArg='--version')or(CurrentArg='-v')Then Begin
      WriteLn('asciitopgm (LINUX-0) 1.0');
      Halt(0);
    End Else If(CurrentArg='-d')or(CurrentArg='--divisor')Then Begin
      Inc(ArgumentIndex);
      If ArgumentIndex>ParamCount Then Begin
        WriteLn('Erreur : diviseur manquant');
        Halt(2);
      End;
      If Not ParsePositive(ParamStr(ArgumentIndex),Divisor)Then Begin
        WriteLn('Erreur : le diviseur doit etre un entier positif');
        Halt(2);
      End;
    End Else If Copy(CurrentArg,1,9)='-divisor='Then Begin
      NumberText:=Copy(CurrentArg,10,246);
      If Not ParsePositive(NumberText,Divisor)Then Begin
        WriteLn('Erreur : le diviseur doit etre un entier positif');
        Halt(2);
      End;
    End Else If(Length(CurrentArg)>2)and(Copy(CurrentArg,1,2)='-d')Then Begin
      NumberText:=Copy(CurrentArg,3,254);
      If Not ParsePositive(NumberText,Divisor)Then Begin
        WriteLn('Erreur : le diviseur doit etre un entier positif');
        Halt(2);
      End;
    End Else If(Length(CurrentArg)>0)and(CurrentArg[1]='-')Then Begin
      WriteLn('Erreur : option inconnue : ',CurrentArg);
      Halt(2);
    End Else If Not ParsePositive(CurrentArg,Height)Then Begin
      WriteLn('Erreur : hauteur invalide : ',CurrentArg);
      Halt(2);
    End Else Begin
      Inc(ArgumentIndex);
      If ArgumentIndex>ParamCount Then Begin
        WriteLn('Erreur : largeur manquante');
        Halt(2);
      End;
      CurrentArg:=ParamStr(ArgumentIndex);
      If Not ParsePositive(CurrentArg,Width)Then Begin
        WriteLn('Erreur : largeur invalide : ',CurrentArg);
        Halt(2);
      End;
      Inc(ArgumentIndex);
      If ArgumentIndex<=ParamCount Then Begin
        InputName:=ParamStr(ArgumentIndex);
        UseInputFile:=True;
        Inc(ArgumentIndex);
      End;
      If ArgumentIndex<=ParamCount Then Begin
        WriteLn('Erreur : trop d''arguments');
        Halt(2);
      End;
    End;
    Inc(ArgumentIndex);
  End;

  If(Width<=0)or(Width>MaxWidth)Then Begin
    WriteLn('Erreur : la largeur doit etre entre 1 et ',MaxWidth);
    Halt(2);
  End;
  If Height<=0 Then Begin
    WriteLn('Erreur : hauteur invalide');
    Halt(2);
  End;
  If UseInputFile Then Begin
    {$I-}Assign(InputFile,InputName);
    Reset(InputFile);{$I+}
    If IOResult<>0 Then Begin
      WriteLn('Erreur : impossible de lire ',InputName);
      Halt(1);
    End;
    InputStream:=@InputFile;
  End Else InputStream:=@Input;
  ConvertInput;
  If UseInputFile Then Close(InputFile);
END.
