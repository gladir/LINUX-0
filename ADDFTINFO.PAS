{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program ADDFTINFO(Input,Output);

Uses DOS;

Type
  TMetric=(AscHeight,BodyHeight,BodyDepth,CapHeight,CommaDepth,
           DescDepth,FigHeight,XHeight);
  TMetricSet=Set Of TMetric;
  TMetricValues=Array[TMetric]Of LongInt;

Var
  FontFile:Text;
  FontName,Arg,OptionName,OptionValue,ResArg,UnitArg:String;
  Line,Token1,Token2,Rest,NewMetrics:String;
  MetricValues:TMetricValues;
  UserMetricValues:TMetricValues;
  GivenMetrics:TMetricSet;
  I,ArgPos,Positionals,Err:Integer;
  UnitWidth,Resolution,MetricValue:LongInt;
  Metric:TMetric;
  InCharset,ShowHelp,ShowVersion:Boolean;

Function StrToLower(S:String):String;
Var
  I:Integer;
Begin
  For I:=1 to Length(S)Do
    If S[I]in['A'..'Z']Then S[I]:=Chr(Ord(S[I])+32);
  StrToLower:=S;
End;

Function NextToken(Const S:String; Var Index:Integer):String;
Var
  Start:Integer;
Begin
  While(Index<=Length(S))and(S[Index]in[' ',#9])Do Inc(Index);
  Start:=Index;
  While(Index<=Length(S))and(Not(S[Index]in[' ',#9]))Do Inc(Index);
  NextToken:=Copy(S,Start,Index-Start);
End;

Function RestOfLine(Const S:String; Index:Integer):String;
Begin
  While(Index<=Length(S))and(S[Index]in[' ',#9])Do Inc(Index);
  RestOfLine:=Copy(S,Index,Length(S));
End;

Function IsDigit(C:Char):Boolean;
Begin
  IsDigit:=C in['0'..'9'];
End;

Function IsUpperLetter(C:Char):Boolean;
Begin
  IsUpperLetter:=C in['A'..'Z'];
End;

Function IsAscender(Const Name:String):Boolean;
Begin
  IsAscender:=((Length(Name)=1)and(Name[1]in['b','d','f','h','k','l','t']))or
    (Name='fi')or(Name='fl')or(Name='ff')or(Name='ffi')or(Name='ffl');
End;

Function IsDescender(Const Name:String):Boolean;
Begin
  IsDescender:=(Length(Name)=1)and(Name[1]in['g','j','p','q','y']);
End;

Function IsBodyCharacter(Const Name:String):Boolean;
Var
  LowerName:String;
Begin
  LowerName:=StrToLower(Name);
  IsBodyCharacter:=(Name='(')or(Name=')')or(Name='[')or(Name=']')or
    (Name='{')or(Name='}')or(Name='|')or
    (Pos('paren',LowerName)>0)or(Pos('bracket',LowerName)>0)or
    (Pos('brace',LowerName)>0);
End;

Function IsFigure(Const Name:String):Boolean;
Begin
  IsFigure:=((Length(Name)=1)and IsDigit(Name[1]))or
    (Name='zero')or(Name='one')or(Name='two')or(Name='three')or
    (Name='four')or(Name='five')or(Name='six')or(Name='seven')or
    (Name='eight')or(Name='nine');
End;

Function IsKnownGlyph(Const Name:String):Boolean;
Begin
  IsKnownGlyph:=IsBodyCharacter(Name)or IsFigure(Name)or
    IsUpperLetter(Name[1])or IsAscender(Name)or IsDescender(Name)or
    ((Length(Name)=1)and(Name[1]in['a'..'z']))or
    (Name='comma')or(Name=',');
End;

Procedure GetDefaultMetrics;
Begin
  MetricValues[AscHeight]:=(UnitWidth*7)div 10;
  MetricValues[BodyHeight]:=(UnitWidth*7)div 10;
  MetricValues[BodyDepth]:=UnitWidth div 5;
  MetricValues[CapHeight]:=(UnitWidth*7)div 10;
  MetricValues[CommaDepth]:=(UnitWidth*15)div 100;
  MetricValues[DescDepth]:=UnitWidth div 5;
  MetricValues[FigHeight]:=(UnitWidth*7)div 10;
  MetricValues[XHeight]:=(UnitWidth*45)div 100;
End;

Function MetricForGlyph(Const GlyphName:String):TMetric;
Var
  Glyph:String;
Begin
  Glyph:=StrToLower(GlyphName);
  If(Glyph='comma')or(Glyph=',')Then
    MetricForGlyph:=CommaDepth
  Else If IsBodyCharacter(Glyph)Then
    MetricForGlyph:=BodyHeight
  Else If IsUpperLetter(GlyphName[1])Then
    MetricForGlyph:=CapHeight
  Else If IsFigure(GlyphName)Then
    MetricForGlyph:=FigHeight
  Else If IsAscender(Glyph)Then
    MetricForGlyph:=AscHeight
  Else
    MetricForGlyph:=XHeight;
End;

Function HeightForGlyph(Const GlyphName:String):LongInt;
Begin
  If(GlyphName='comma')or(GlyphName=',')or(GlyphName='period')or
    (GlyphName='.')or(GlyphName='space')or(GlyphName='hyphen')or
    (GlyphName='minus')Then HeightForGlyph:=0
  Else If IsKnownGlyph(GlyphName)Then
    HeightForGlyph:=MetricValues[MetricForGlyph(GlyphName)]
  Else HeightForGlyph:=0;
End;

Function DepthForGlyph(Const GlyphName:String):LongInt;
Var
  Glyph:String;
Begin
  Glyph:=StrToLower(GlyphName);
  If IsDescender(Glyph)Then DepthForGlyph:=MetricValues[DescDepth] Else
  If(Glyph='comma')or(Glyph='semicolon')or(Glyph=',')Then
    DepthForGlyph:=MetricValues[CommaDepth]
  Else If IsBodyCharacter(Glyph)Then
    DepthForGlyph:=MetricValues[BodyDepth]
  Else DepthForGlyph:=0;
End;

Function ParseMetricOption(Const Name:String; Var Metric:TMetric):Boolean;
Begin
  ParseMetricOption:=True;
  If Name='-asc-height'Then Metric:=AscHeight Else
  If Name='-body-height'Then Metric:=BodyHeight Else
  If Name='-body-depth'Then Metric:=BodyDepth Else
  If Name='-cap-height'Then Metric:=CapHeight Else
  If Name='-comma-depth'Then Metric:=CommaDepth Else
  If Name='-desc-depth'Then Metric:=DescDepth Else
  If Name='-fig-height'Then Metric:=FigHeight Else
  If Name='-x-height'Then Metric:=XHeight Else
    ParseMetricOption:=False;
End;

Procedure PrintHelp;
Begin
  If Copy(StrToLower(GetEnv('LANGUAGE')),1,2)='en'Then Begin
    WriteLn('ADDFTINFO : Add metric information to a troff font file.');
    WriteLn('Syntax: addftinfo [OPTION]... res unitwidth font');
    WriteLn(' -asc-height n  Height of characters with ascenders, such as b or d.');
    WriteLn(' -body-height n Height of characters such as parentheses.');
    WriteLn(' -body-depth n  Depth of characters such as parentheses.');
    WriteLn(' -cap-height n  Height of uppercase letters such as A.');
    WriteLn(' -comma-depth n Depth of a comma.');
    WriteLn(' -desc-depth n  Depth of characters with descenders, such as p or q.');
    WriteLn(' -fig-height n  Height of figures.');
    WriteLn(' -x-height n    Height of lowercase letters without ascenders.');
    WriteLn(' -v, --version  Display the version.');
    WriteLn(' --help         Display this help.');
  End
   Else Begin
    WriteLn('ADDFTINFO : Cette commande permet d''ajouter les metriques a un fichier de police troff.');
    WriteLn;
    WriteLn('Syntaxe : addftinfo [OPTION]... resolution largeur-unite police');
    WriteLn(' -asc-height n  Hauteur des caracteres ascendants comme b ou d.');
    WriteLn(' -body-height n Hauteur des parentheses.');
    WriteLn(' -body-depth n  Profondeur des parentheses.');
    WriteLn(' -cap-height n  Hauteur des lettres majuscules comme A.');
    WriteLn(' -comma-depth n Profondeur d''une virgule.');
    WriteLn(' -desc-depth n  Profondeur des caracteres descendants comme p ou q.');
    WriteLn(' -fig-height n  Hauteur des chiffres.');
    WriteLn(' -x-height n    Hauteur des minuscules sans hampe comme x.');
    WriteLn(' -v, --version  Affiche la version.');
    WriteLn(' --help         Affiche cette aide.');
  End;
End;

Procedure ProcessFontLine(Const SourceLine:String);
Var
  Index:Integer;
  GlyphName,Width,CharType,CharIndex:String;
  Height,Depth:LongInt;
Begin
  Index:=1;
  GlyphName:=NextToken(SourceLine,Index);
  If(GlyphName='')or(GlyphName[1]='#')or(GlyphName='"')Then Begin
    WriteLn(SourceLine);
    Exit;
  End;
  Width:=NextToken(SourceLine,Index);
  CharType:=NextToken(SourceLine,Index);
  CharIndex:=NextToken(SourceLine,Index);
  If(Width='')or(CharType='')or(CharIndex='')or(Pos(',',Width)>0)Then Begin
    WriteLn(SourceLine);
    Exit;
  End;
  Height:=HeightForGlyph(GlyphName);
  Depth:=DepthForGlyph(GlyphName);
  Str(Height,Token1);
  Str(Depth,Token2);
  NewMetrics:=Width+','+Token1+','+Token2;
  Rest:=RestOfLine(SourceLine,Index);
  Write(GlyphName,' ',NewMetrics,' ',CharType,' ',CharIndex);
  If Rest<>''Then Write(' ',Rest);
  WriteLn;
End;

Procedure ReadFont;
Begin
  {$I-}Assign(FontFile,FontName);
  Reset(FontFile);{$I+}
  If IOResult<>0Then Begin
    WriteLn('Erreur : impossible de lire le fichier de police ',FontName);
    Halt(1);
  End;
  InCharset:=False;
  While Not EOF(FontFile)Do Begin
    ReadLn(FontFile,Line);
    If InCharset Then ProcessFontLine(Line) Else Begin
      WriteLn(Line);
      ArgPos:=1;
      If NextToken(Line,ArgPos)='charset'Then InCharset:=True;
    End;
  End;
  Close(FontFile);
End;

BEGIN
  ShowHelp:=False;
  ShowVersion:=False;
  Positionals:=0;
  ResArg:='';
  UnitArg:='';
  FontName:='';
  GivenMetrics:=[];
  If ParamCount=0 Then ShowHelp:=True;
  I:=1;
  While I<=ParamCount Do Begin
    Arg:=ParamStr(I);
    If(Arg='--help')or(Arg='/?')or(Arg='-h')or(Arg='/h')or(Arg='/H')Then
      ShowHelp:=True
    Else If(Arg='-v')or(Arg='--version')Then ShowVersion:=True
    Else Begin
      OptionName:=Arg;
      OptionValue:='';
      ArgPos:=1;
      While(ArgPos<=Length(Arg))and(Arg[ArgPos]<>'=')do Inc(ArgPos);
      If ArgPos<=Length(Arg)Then Begin
        OptionName:=Copy(Arg,1,ArgPos-1);
        OptionValue:=Copy(Arg,ArgPos+1,Length(Arg));
      End;
      If ParseMetricOption(OptionName,Metric)Then Begin
        If OptionValue=''Then Begin
          Inc(I);
          If I>ParamCount Then Begin
            WriteLn('Erreur : valeur manquante pour ',OptionName);
            Halt(2);
          End;
          OptionValue:=ParamStr(I);
        End;
        Val(OptionValue,MetricValue,Err);
        If(Err<>0)or(MetricValue<0)Then Begin
          WriteLn('Erreur : valeur de metrique invalide : ',OptionValue);
          Halt(2);
        End;
        UserMetricValues[Metric]:=MetricValue;
        Include(GivenMetrics,Metric);
      End
       Else If(Length(Arg)>0)and(Arg[1]='-')Then Begin
        WriteLn('Erreur : option inconnue : ',Arg);
        Halt(2);
      End
       Else Begin
        Inc(Positionals);
        Case Positionals Of
          1:ResArg:=Arg;
          2:UnitArg:=Arg;
          3:FontName:=Arg;
          Else Begin
            WriteLn('Erreur : trop d''arguments');
            Halt(2);
          End;
        End;
      End;
    End;
    Inc(I);
  End;
  If ShowHelp Then PrintHelp Else
  If ShowVersion Then WriteLn('addftinfo (LINUX-0) 1.0') Else Begin
    If Positionals<>3 Then Begin
      WriteLn('Erreur : syntaxe : addftinfo [options] resolution largeur-unite police');
      Halt(2);
    End;
    Val(ResArg,Resolution,Err);
    If(Err<>0)or(Resolution<=0)Then Begin
      WriteLn('Erreur : resolution invalide : ',ResArg);
      Halt(2);
    End;
    Val(UnitArg,UnitWidth,Err);
    If(Err<>0)or(UnitWidth<=0)Then Begin
      WriteLn('Erreur : largeur-unite invalide : ',UnitArg);
      Halt(2);
    End;
    GetDefaultMetrics;
    For Metric:=AscHeight to XHeight Do
      If Metric in GivenMetrics Then
        MetricValues[Metric]:=UserMetricValues[Metric];
    ReadFont;
  End;
END.
