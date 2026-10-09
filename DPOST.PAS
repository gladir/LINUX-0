{ @author: Sylvain Maltais (support@gladir.com)
 @created: 2026
 @website(https://www.gladir.com/linux-0)
 @abstract(Target: Turbo Pascal 7, Free Pascal 3.2) }

Program DPOST;


Uses DOS;

Const
 MaxFiles=16;
 MaxPages=256;
 MaxFonts=32;
 MaxLine=255;

Type
 TFileNames=Array[1..MaxFiles]Of String[127];
 TPageSet=Array[1..MaxPages]Of Boolean;
 TFontNames=Array[0..MaxFonts]Of String[63];

Var
 SourceFile,LogFile:Text;
 FileNames:TFileNames;
 SelectedPages:TPageSet;
 FontNames:TFontNames;
 FileCount,ArgumentIndex,PageCount,CurrentPage,OptionIndex,FileIndex:Integer;
 NumberValue:LongInt;
 CopyCount,FontSize,PageWidth,PageHeight,DeviceResolution:Integer;
 XOffset,YOffset,CurrentX,CurrentY,ScalePercent:LongInt;
 Argument,InputName,LogName,LanguageCode,OptionValue:String;
 CurrentFontName:String;
 HasPageList,LandscapeMode,PageOpen,ErrorFound:Boolean;
 LogOpened:Boolean;

Procedure ReportError(Const MessageText:String);Begin
 If LogOpened Then WriteLn(LogFile,'dpost: ',InputName,': ',MessageText)
              Else WriteLn('dpost: ',InputName,': ',MessageText);
 ErrorFound:=True;
End;

Procedure OptionError(Const MessageText:String);Begin
 WriteLn('dpost: ',MessageText);
 Halt(2);
End;

Function TrimText(Value:String):String;Begin
 While(Length(Value)>0)And(Value[1]In[' ',#9])Do Delete(Value,1,1);
 While(Length(Value)>0)And(Value[Length(Value)]In[' ',#9,#13])Do    Delete(Value,Length(
 Value),1);
 TrimText:=Value;
End;

Function LowerText(Value:String):String;
Var
 Index:Integer;
Begin
 For Index:=1 To Length(Value)Do    If Value[Index]In['A'..'Z']Then Value[Index]:=Chr(Ord(
 Value[Index])+32);
 LowerText:=Value;
End;

Procedure PrintHelp;Begin
 If Copy(LanguageCode,1,2)='EN'Then Begin
  WriteLn('DPOST : Convert ditroff/troff output to PostScript.');
  WriteLn('Syntax: dpost [-c num] [-e num] [-m num] [-n num] [-o list]');
  WriteLn('             [-p mode] [-w num] [-x num] [-y num] [-F dir]');
  WriteLn('             [-H dir] [-L file] [-O] [-T name] [file]');
  WriteLn(' -c N  Number of copies; -o LIST selects page numbers');
  WriteLn(' -p    Portrait or landscape; -w N sets page width');
  WriteLn(' -x/-y N set page offsets; -T NAME selects a device label');
  WriteLn('Reads ditroff commands and a basic subset of raw troff requests.');
  WriteLn('PostScript is written to standard output.');
 End Else
 Begin
  WriteLn(
  'DPOST : Cette commande permet de convertir les sorties ditroff/troff en PostScript.');
  WriteLn;
  WriteLn('Syntaxe : dpost [-c num] [-e num] [-m num] [-n num] [-o liste]');
  WriteLn('          [-p mode] [-w num] [-x num] [-y num] [-F rep]');
  WriteLn('          [-H rep] [-L fichier] [-O] [-T nom] [fichier]');
  WriteLn(' -c N  Nombre de copies; -o LISTE selectionne les pages');
  WriteLn(' -p    Portrait ou paysage; -w N definit la largeur');
  WriteLn(' -x/-y N definissent les decalages; -T NOM choisit un peripherique');
  WriteLn;
  WriteLn('Lit ditroff et un sous-ensemble de requetes troff brutes.');
  WriteLn('Le PostScript est ecrit sur la sortie standard.');
 End;
End;

Function ParseLong(Const Value:String; Var Number:LongInt):Boolean;
Var
 Code:Integer;
Begin
 Val(Value,Number,Code);
 ParseLong:=Code=0;
End;

Procedure ReadOptionValue(Const OptionName:String; Var Index:Integer;
                          Var Value:String);Begin
 Inc(Index);
 If Index>ParamCount Then OptionError('valeur manquante pour '+OptionName);
 Value:=ParamStr(Index);
End;

Procedure SelectPages(Const PageList:String);
Var
 Position,StartPosition,RangeEnd,PageNumber,Code:Integer;
 Token:String;
Begin
 For PageNumber:=1 To MaxPages Do SelectedPages[PageNumber]:=False;
 HasPageList:=True;
 Position:=1;
 While Position<=Length(PageList)Do Begin
  While(Position<=Length(PageList))And(PageList[Position]In[' ',#9,','])Do Inc(Position);
  If Position>Length(PageList)Then Break;
  StartPosition:=Position;
  While(Position<=Length(PageList))And Not(PageList[Position]In[' ',#9,','])Do Inc(
  Position);
  Token:=Copy(PageList,StartPosition,Position-StartPosition);
  Code:=Pos('-',Token);
  If Code=0 Then Begin
   Val(Token,PageNumber,Code);
   If(Code<>0)Or(PageNumber<1)Or(PageNumber>MaxPages)Then        OptionError(
   'liste de pages invalide');
   SelectedPages[PageNumber]:=True;
  End Else
  Begin
   Val(Copy(Token,1,Code-1),PageNumber,Code);
   If(Code<>0)Then OptionError('intervalle de pages invalide');
   Val(Copy(Token,Pos('-',Token)+1,255),RangeEnd,Code);
   If(Code<>0)Or(PageNumber<1)Or(RangeEnd>MaxPages)Or(RangeEnd<PageNumber)
   Then        OptionError('intervalle de pages invalide');
   While PageNumber<=RangeEnd Do Begin
    SelectedPages[PageNumber]:=True;Inc(PageNumber);
   End;
  End;
 End;
End;

Function PageIsSelected(Number:Integer):Boolean;Begin
 If Not HasPageList Then PageIsSelected:=True
                    Else If(Number>=1)And(Number<=MaxPages)Then PageIsSelected:=SelectedPages[Number]
 Else PageIsSelected:=False;
End;

Function EscapePostScript(Const Value:String):String;
Var
 Index:Integer;
 Escaped:String;
Begin
 Escaped:='';
 For Index:=1 To Length(Value)Do Begin
  If(Value[Index]='(')Or(Value[Index]=')')Or(Value[Index]=#92)Then      Escaped:=Escaped+
  #92;
  If Value[Index]In[#9,#13]Then Escaped:=Escaped+' '
  Else Escaped:=Escaped+Value[Index];
 End;
 EscapePostScript:=Escaped;
End;

Procedure StartPage(Number:Integer);Begin
 If PageOpen Then WriteLn('showpage');
 CurrentPage:=Number;
 Inc(PageCount);
 PageOpen:=True;
 CurrentX:=0;
 CurrentY:=0;
 If PageIsSelected(Number)Then Begin
  WriteLn('%%Page: ',Number,' ',PageCount);
  WriteLn('gsave');
  If LandscapeMode Then WriteLn('90 rotate 0 -',PageHeight,' translate');
  If(XOffset<>0)Or(YOffset<>0)Then WriteLn(XOffset,' ',YOffset,' translate');
  If ScalePercent<>100 Then WriteLn(ScalePercent/100:0:2,' ',ScalePercent/100:0:2,
  ' scale');
 End;
End;

Procedure EndPage;Begin
 If PageOpen Then Begin
  If PageIsSelected(CurrentPage)Then Begin
   WriteLn('grestore');WriteLn('showpage');
  End;
  PageOpen:=False;
 End;
End;

Procedure SelectFont(FontNumber:Integer);
Var
 FontName:String;
Begin
 If(FontNumber>=0)And(FontNumber<=MaxFonts)And(FontNames[FontNumber]<>'')
 Then    FontName:=FontNames[FontNumber]
 Else Case FontNumber Of
 1:FontName:='Times-Roman';
 2:FontName:='Times-Italic';
 3:FontName:='Times-Bold';
 4:FontName:='Times-BoldItalic';
 5:FontName:='Helvetica';
 6:FontName:='Courier';
 Else FontName:='Times-Roman';
End;
CurrentFontName:=FontName;
End;

Procedure SetPointSize(Value:Integer);Begin
 If Value<1 Then Value:=1;
 If Value>144 Then Value:=144;
 FontSize:=Value;
 If PageOpen And PageIsSelected(CurrentPage)Then Begin
  WriteLn('/',CurrentFontName,' findfont ',FontSize,' scalefont setfont');
 End;
End;

Procedure EmitText(Const Value:String);
Var
 YPosition,XPosition:LongInt;
Begin
 If Not PageOpen Then StartPage(1);
 If PageIsSelected(CurrentPage)Then Begin
  If DeviceResolution<1 Then DeviceResolution:=720;
  XPosition:=CurrentX*72 Div DeviceResolution;
  YPosition:=PageHeight-(CurrentY*72 Div DeviceResolution);
  WriteLn(XPosition,' ',YPosition,' moveto (',EscapePostScript(Value),') show');
 End;
End;

Function ReadInteger(Const Value:String; Var Number:LongInt):Boolean;
Var
 Code:Integer;
Begin
 Val(Value,Number,Code);
 ReadInteger:=Code=0;
End;

Function PostScriptFontName(Const Name:String):String;Begin
 If Name='R'Then PostScriptFontName:='Times-Roman'Else
 If Name='I'Then PostScriptFontName:='Times-Italic'Else
 If Name='B'Then PostScriptFontName:='Times-Bold'Else
 If Name='BI'Then PostScriptFontName:='Times-BoldItalic'Else
 If Name='H'Then PostScriptFontName:='Helvetica'Else
 If Name='C'Then PostScriptFontName:='Courier'Else
 PostScriptFontName:=Name;
End;

Function FirstToken(Const Value:String; Var Remainder:String):String;
Var
 Position:Integer;
 Token:String;
Begin
 Position:=1;
 While(Position<=Length(Value))And(Value[Position]In[' ',#9])Do Inc(Position);
 Token:='';
 While(Position<=Length(Value))And Not(Value[Position]In[' ',#9])Do Begin
  Token:=Token+Value[Position];
  Inc(Position);
 End;
 While(Position<=Length(Value))And(Value[Position]In[' ',#9])Do Inc(Position);
 Remainder:=Copy(Value,Position,255);
 FirstToken:=Token;
End;

Procedure ProcessDitroffLine(Const Line:String);
Var
 Command:Char;
 Rest,Token,FontName:String;
 Number,Index,FontNumber:LongInt;
Begin
 If Line=''Then Exit;
 Command:=Line[1];
 Rest:=Copy(Line,2,255);
 Case Command Of
 'p':
 Begin
  If Not ReadInteger(TrimText(Rest),Number)Then Begin
   ReportError('numero de page invalide');Exit;
  End;
  If PageOpen Then EndPage;
  StartPage(Number);
 End;
 's':
 Begin
  If ReadInteger(TrimText(Rest),Number)Then SetPointSize(Number)
  Else ReportError('taille de police invalide');
 End;
 'f':
 Begin
  If ReadInteger(TrimText(Rest),Number)Then SelectFont(Number)
  Else ReportError('numero de police invalide');
 End;
 'H':If ReadInteger(TrimText(Rest),Number)Then CurrentX:=Number;
 'V':If ReadInteger(TrimText(Rest),Number)Then CurrentY:=Number;
 'h':If ReadInteger(TrimText(Rest),Number)Then Inc(CurrentX,Number);
 'v':If ReadInteger(TrimText(Rest),Number)Then Inc(CurrentY,Number);
 'c':
 Begin
  EmitText(Copy(Line,2,1));Inc(CurrentX,FontSize*6);
 End;
 'C':
 Begin
  Token:=TrimText(Rest);
  If Token='em'Then EmitText('-')
  Else If Token='en'Then EmitText('-')
  Else If Token='bu'Then EmitText('*')
  Else If Token='sq'Then EmitText('[]')
  Else If Token='hy'Then EmitText('-')
  Else If Token='co'Then EmitText(':')
  Else If Length(Token)=1 Then EmitText(Token);
  Inc(CurrentX,FontSize*6);
 End;
 'N':
 Begin
  If ReadInteger(TrimText(Rest),Number)And(Number>=0)And(Number<=255)Then Begin
   EmitText(Chr(Number));Inc(CurrentX,FontSize*6);
  End;
 End;
 't':
 Begin
  EmitText(Rest);Inc(CurrentX,Length(Rest)*FontSize*6);
 End;
 'u':
 Begin
  Rest:=TrimText(Rest);
  Index:=1;
  Token:=FirstToken(Rest,FontName);
  If ReadInteger(Token,Number)Then Begin
   Rest:=FontName;
   While Index<=Length(Rest)Do Begin
    If Rest[Index]<>#9 Then Begin
     EmitText(Rest[Index]);Inc(CurrentX,FontSize*6);
    End;
    Inc(Index);
   End;
  End;
 End;
 'n':If PageOpen Then Inc(CurrentY,FontSize*12);
 'w':;
 'x':
 Begin
  Token:=FirstToken(Rest,FontName);
  If Token='res'Then Begin
   Token:=FirstToken(FontName,Rest);
   If ReadInteger(Token,Number)And(Number>0)Then DeviceResolution:=Number;
  End Else If Token='font'Then Begin
   Token:=FirstToken(FontName,Rest);
   If ReadInteger(Token,FontNumber)Then Begin
    Token:=FirstToken(Rest,FontName);
    If FontNumber<=MaxFonts Then FontNames[FontNumber]:=PostScriptFontName(Token);
   End;
  End;
 End;
 'D':;
  Else
 Begin
  If Copy(Line,1,2)='# 'Then Exit;
  If Length(Line)>0 Then Begin
   EmitText(Line);Inc(CurrentY,FontSize*12);
  End;
 End;
End;
End;

Procedure ProcessRoffLine(Const Line:String);
Var
 Request,Arguments,Remainder:String;
 Number:LongInt;
Begin
 If(Length(Line)>0)And(Line[1]In['.',''''])Then Begin
  Request:=FirstToken(Copy(Line,2,255),Arguments);
  If(Request='br')Or(Request='sp')Then Begin
   If Request='sp'Then Begin
    Request:=FirstToken(Arguments,Remainder);
    If ReadInteger(Request,Number)Then Inc(CurrentY,Number*FontSize*12)
    Else Inc(CurrentY,FontSize*12);
   End Else Inc(CurrentY,FontSize*12);
  End Else If Request='bp'Then Begin
   EndPage;StartPage(CurrentPage+1);
  End
  Else If Request='ps'Then Begin
   If ReadInteger(TrimText(Arguments),Number)Then SetPointSize(Number);
  End Else If Request='ft'Then Begin
   Request:=TrimText(Arguments);
   If Request='R'Then SelectFont(1)Else If Request='I'Then SelectFont(2)
   Else If Request='B'Then SelectFont(3)Else If Request='BI'Then SelectFont(4);
  End Else If Request='ce'Then Begin
   Request:=FirstToken(Arguments,Remainder);
  End Else If Request='nf'Then Begin
  End
  Else If Request='fi'Then Begin
  End;
 End Else
 Begin
  EmitText(Line);
  Inc(CurrentY,FontSize*12);
 End;
End;

Procedure ProcessInput(Var Source:Text);
Var
 Line:String;
 DitroffDetected,FirstContent:Boolean;
Begin
 DitroffDetected:=False;FirstContent:=True;
 While Not EOF(Source)Do Begin
  ReadLn(Source,Line);
  If FirstContent Then Begin
   FirstContent:=False;
   If Copy(Line,1,3)='x T'Then DitroffDetected:=True;
  End;
  If DitroffDetected Then ProcessDitroffLine(Line)
                     Else ProcessRoffLine(Line);
 End;
End;

Procedure ProcessFile(Const FileName:String);Begin
 InputName:=FileName;
 Assign(SourceFile,FileName);
  {$I-}Reset(SourceFile);{$I+}
 If IOResult<>0 Then Begin
  ReportError('impossible de lire '+FileName);Exit;
 End;
 ProcessInput(SourceFile);
 Close(SourceFile);
End;

BEGIN
 LanguageCode:=GetEnv('LANGUAGE');
 FileCount:=0;CopyCount:=1;PageWidth:=612;PageHeight:=792;
 PageCount:=0;CurrentPage:=0;PageOpen:=False;LandscapeMode:=False;
 ErrorFound:=False;XOffset:=0;YOffset:=0;ScalePercent:=100;
 DeviceResolution:=720;CurrentX:=0;CurrentY:=0;FontSize:=10;
 HasPageList:=False;LogOpened:=False;InputName:='stdin';
 For FileIndex:=0 To MaxFonts Do FontNames[FileIndex]:='';
 FontNames[1]:='Times-Roman';FontNames[2]:='Times-Italic';
 FontNames[3]:='Times-Bold';FontNames[4]:='Times-BoldItalic';
 FontNames[5]:='Helvetica';FontNames[6]:='Courier';
 SelectFont(1);
 ArgumentIndex:=1;
 While ArgumentIndex<=ParamCount Do Begin
  Argument:=ParamStr(ArgumentIndex);
  If(Argument='--help')Or(Argument='-h')Or(Argument='/?')Then Begin
   PrintHelp;Halt(0);
  End
  Else If(Argument='--version')Or(Argument='-V')Then Begin
   WriteLn('dpost (LINUX-0) 1.0');Halt(0);
  End
  Else If(Argument='-O')Then Begin
  End
  Else If(Argument='-B')Then Begin
  End
  Else If(Argument='-F')Or(Argument='-H')Or(Argument='-L')Or
  (Argument='-c')Or(Argument='-e')Or(Argument='-m')Or(Argument='-n')Or
  (Argument='-o')Or(Argument='-p')Or(Argument='-T')Or(Argument='-w')Or
  (Argument='-x')Or(Argument='-y')Then Begin
   ReadOptionValue(Argument,ArgumentIndex,OptionValue);
   If Argument='-c'Then Begin
    If Not ReadInteger(OptionValue,NumberValue)Or(NumberValue<1)Then OptionError(
    'nombre de copies invalide');
    CopyCount:=NumberValue;
   End Else If Argument='-m'Then Begin
    If Not ReadInteger(OptionValue,NumberValue)Or(NumberValue<1)Or(NumberValue>1000)
    Then          OptionError('echelle invalide');
    ScalePercent:=NumberValue;
   End Else If Argument='-o'Then SelectPages(OptionValue)
   Else If Argument='-p'Then LandscapeMode:=LowerText(OptionValue)='landscape'
   Else If Argument='-w'Then Begin
    If Not ReadInteger(OptionValue,NumberValue)Then OptionError('largeur invalide');
    PageWidth:=NumberValue;
   End
   Else If Argument='-x'Then Begin
    If Not ReadInteger(OptionValue,NumberValue)Then OptionError('decalage x invalide');
    XOffset:=NumberValue;
   End
   Else If Argument='-y'Then Begin
    If Not ReadInteger(OptionValue,NumberValue)Then OptionError('decalage y invalide');
    YOffset:=NumberValue;
   End
   Else If Argument='-L'Then LogName:=OptionValue;
  End Else If(Length(Argument)>1)And(Argument[1]='-')Then Begin
   If Argument[2]='-'Then OptionError('option inconnue: '+Argument);
   For OptionIndex:=2 To Length(Argument)Do Begin
    If Argument[OptionIndex]='O'Then Begin
    End
    Else If Argument[OptionIndex]='B'Then Begin
    End
    Else OptionError('option inconnue: -'+Argument[OptionIndex]);
   End;
  End Else
  Begin
   If FileCount>=MaxFiles Then OptionError('trop de fichiers');
   Inc(FileCount);FileNames[FileCount]:=Argument;
  End;
  Inc(ArgumentIndex);
 End;
 If LogName<>''Then Begin
  Assign(LogFile,LogName);{$I-}Rewrite(LogFile);{$I+}
  If IOResult=0Then LogOpened:=True;
 End;
 WriteLn('%!PS-Adobe-3.0');
 WriteLn('%%Creator: dpost (LINUX-0)');
 WriteLn('%%Pages: (atend)');
 If LandscapeMode Then WriteLn('%%BoundingBox: 0 0 ',PageHeight,' ',PageWidth)
                  Else WriteLn('%%BoundingBox: 0 0 ',PageWidth,' ',PageHeight);
 WriteLn('/#copies ',CopyCount,' def');
 WriteLn('%%EndComments');
 WriteLn('/F { findfont exch scalefont setfont } bind def');
 WriteLn('10 /Times-Roman F');
 WriteLn('/S { show } bind def');
 If FileCount=0Then ProcessInput(Input)
  Else
 For FileIndex:=1 To FileCount Do ProcessFile(FileNames[FileIndex]);
 If PageOpen Then EndPage;
 WriteLn('%%Trailer');
 WriteLn('%%Pages: ',PageCount);
 WriteLn('%%EOF');
 If LogOpened Then Close(LogFile);
 If ErrorFound Then Halt(1);
END.
