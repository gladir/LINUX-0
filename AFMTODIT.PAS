{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program AFMTODIT(Input,Output);

Uses DOS;

Const
  MaxMappings=128;
  MaxEncodingNames=256;

Type
  TShortName=String[40];
  TMapEntry=Record
    PostScriptName:TShortName;
    GroffName:TShortName;
  End;
  TMapArray=Array[1..MaxMappings]Of TMapEntry;
  TEncodingArray=Array[0..MaxEncodingNames-1]Of TShortName;

Var
  AFMFile,MapFile,DeviceFile,EncodingFile,OutputFile:Text;
  AFMName,MapName,DeviceName,EncodingName,OutputName:String;
  FontName,EncodingScheme,CurrentLine:String;
  Arg,OptionValue:String;
  Mappings:TMapArray;
  EncodedNames:TEncodingArray;
  MappingCount,EncodingCount,Positionals,LineCount:Integer;
  I,ArgumentIndex:Integer;
  MaxAFMCode,UnitWidth,ItalicAngle,UserSlant:LongInt;
  SpaceWidth:Real;
  AFMXHeight:LongInt;
  AngleValue:Real;
  ItalicFactor:LongInt;
  HasUserSlant,HasItalicFactor:Boolean;
  IncludeLigatures,SpecialFont,ShowVersion:Boolean;
  EncodingLoaded:Boolean;

Function TrimText(S:String):String;
Var
  First,Last:Integer;
Begin
  First:=1;
  Last:=Length(S);
  While(First<=Last)and(S[First]in[' ',#9])Do Inc(First);
  While(Last>=First)and(S[Last]in[' ',#9])Do Dec(Last);
  TrimText:=Copy(S,First,Last-First+1);
End;

Function NextWord(Const S:String; Var Index:Integer):String;
Var
  First:Integer;
Begin
  While(Index<=Length(S))and(S[Index]in[' ',#9])Do Inc(Index);
  First:=Index;
  While(Index<=Length(S))and(Not(S[Index]in[' ',#9]))Do Inc(Index);
  NextWord:=Copy(S,First,Index-First);
End;

Function StartsWith(Const S,Prefix:String):Boolean;
Begin
  StartsWith:=Copy(S,1,Length(Prefix))=Prefix;
End;

Function ParseLong(Const S:String; Var Value:LongInt):Boolean;
Var
  ErrorCode:Integer;
Begin
  Val(S,Value,ErrorCode);
  ParseLong:=ErrorCode=0;
End;

Function ParseReal(Const S:String; Var Value:Real):Boolean;
Var
  ErrorCode:Integer;
Begin
  Val(S,Value,ErrorCode);
  ParseReal:=ErrorCode=0;
End;

Function ScaleMetric(Value:LongInt):LongInt;
Begin
  If UnitWidth=0 Then ScaleMetric:=Value
  Else ScaleMetric:=(Value*UnitWidth+500)div 1000;
End;

Function ScaleRealMetric(Value:Real):LongInt;
Begin
  ScaleRealMetric:=Round(Value*UnitWidth/1000);
End;

Function FieldAfter(Const S,Key:String):String;
Var
  P,Start,Last:Integer;
Begin
  FieldAfter:='';
  P:=Pos(Key,S);
  If P=0 Then Exit;
  If(P>1)and Not(S[P-1]in[' ',#9,';'])Then Exit;
  Start:=P+Length(Key);
  While(Start<=Length(S))and(S[Start]in[' ',#9])Do Inc(Start);
  Last:=Start;
  While(Last<=Length(S))and(S[Last]<>';')Do Inc(Last);
  FieldAfter:=TrimText(Copy(S,Start,Last-Start));
End;

Function GetMapName(Const PS:String):String;
Var
  I:Integer;
Begin
  GetMapName:='';
  For I:=1 to MappingCount Do
    If Mappings[I].PostScriptName=PS Then Begin
      GetMapName:=Mappings[I].GroffName;
      Exit;
    End;
End;

Function GetEncodingCode(Const PS:String):Integer;
Var
  I:Integer;
Begin
  GetEncodingCode:=-1;
  If Not EncodingLoaded Then Exit;
  For I:=0 to EncodingCount-1 Do
    If EncodedNames[I]=PS Then Begin
      GetEncodingCode:=I;
      Exit;
    End;
End;

Procedure LoadMap;
Var
  Index:Integer;
  LineValue,MapPS,MapGroff:String;
Begin
  {$I-}Assign(MapFile,MapName);
  Reset(MapFile);{$I+}
  If IOResult<>0 Then Begin
    WriteLn('Erreur : impossible de lire le fichier map ',MapName);
    Halt(1);
  End;
  MappingCount:=0;
  While Not EOF(MapFile)Do Begin
    ReadLn(MapFile,LineValue);
    LineValue:=TrimText(LineValue);
    If(LineValue<>'')and(LineValue[1]<>'#')Then Begin
      Index:=1;
      MapPS:=NextWord(LineValue,Index);
      MapGroff:=NextWord(LineValue,Index);
      If(MapPS<>'')and(MapGroff<>'')Then Begin
        If MappingCount>=MaxMappings Then Begin
          WriteLn('Erreur : trop d''entrees dans le fichier map');
          Halt(1);
        End;
        Inc(MappingCount);
        Mappings[MappingCount].PostScriptName:=MapPS;
        Mappings[MappingCount].GroffName:=MapGroff;
      End;
    End;
  End;
  Close(MapFile);
End;

Procedure LoadEncoding;
Var
  InArray:Boolean;
  I,Start,Finish:Integer;
  Name:String;
Begin
  EncodingLoaded:=False;
  EncodingCount:=0;
  If EncodingName=''Then Exit;
  {$I-}Assign(EncodingFile,EncodingName);
  Reset(EncodingFile);{$I+}
  If IOResult<>0 Then Begin
    WriteLn('Erreur : impossible de lire l''encodage ',EncodingName);
    Halt(1);
  End;
  InArray:=False;
  While Not EOF(EncodingFile)Do Begin
    ReadLn(EncodingFile,CurrentLine);
    I:=1;
    While I<=Length(CurrentLine)Do Begin
      If CurrentLine[I]='['Then Begin
        InArray:=True;
        Inc(I);
      End Else
      If CurrentLine[I]=']'Then Begin
        InArray:=False;
        Inc(I);
      End Else
      If InArray And(CurrentLine[I]='/')Then Begin
        Inc(I);
        Start:=I;
        While(I<=Length(CurrentLine))and
          Not(CurrentLine[I]in[' ',#9,'/','[',']'])Do Inc(I);
        Finish:=I-1;
        If(Finish>=Start)and(EncodingCount<MaxEncodingNames)Then Begin
          Name:=Copy(CurrentLine,Start,Finish-Start+1);
          EncodedNames[EncodingCount]:=Name;
          Inc(EncodingCount);
        End;
      End
       Else Inc(I);
    End;
  End;
  Close(EncodingFile);
  EncodingLoaded:=True;
End;

Procedure ReadDeviceDescription;
Var
  Index:Integer;
  Key,Value:String;
  Number:LongInt;
Begin
  If DeviceName=''Then Exit;
  {$I-}Assign(DeviceFile,DeviceName);
  Reset(DeviceFile);{$I+}
  If IOResult<>0 Then Begin
    WriteLn('Erreur : impossible de lire la description ',DeviceName);
    Halt(1);
  End;
  While Not EOF(DeviceFile)Do Begin
    ReadLn(DeviceFile,CurrentLine);
    Index:=1;
    Key:=NextWord(CurrentLine,Index);
    Value:=NextWord(CurrentLine,Index);
    If(Key='unitwidth')and ParseLong(Value,Number)Then UnitWidth:=Number;
  End;
  Close(DeviceFile);
End;

Procedure ReadAFMHeader;
Var
  Index:Integer;
  Key,Value:String;
  CodeValue:LongInt;
  InMetrics:Boolean;
Begin
  {$I-}Assign(AFMFile,AFMName);
  Reset(AFMFile);{$I+}
  If IOResult<>0Then Begin
    WriteLn('Erreur : impossible de lire le fichier AFM ',AFMName);
    Halt(1);
  End;
  FontName:='';
  ItalicAngle:=0;
  AFMXHeight:=450;
  SpaceWidth:=0;
  MaxAFMCode:=255;
  InMetrics:=False;
  While Not EOF(AFMFile)Do Begin
    ReadLn(AFMFile,CurrentLine);
    If StartsWith(CurrentLine,'StartCharMetrics')Then InMetrics:=True Else
    If StartsWith(CurrentLine,'EndCharMetrics')Then InMetrics:=False;
    Index:=1;
    Key:=NextWord(CurrentLine,Index);
    Value:=NextWord(CurrentLine,Index);
    If Key='FontName'Then FontName:=Value Else
    If Key='ItalicAngle'Then Begin
      If ParseReal(Value,AngleValue)Then ItalicAngle:=Round(AngleValue);
    End Else
    If Key='XHeight'Then ParseLong(Value,AFMXHeight) Else
    If Key='EncodingScheme'Then EncodingScheme:=Value Else
    If InMetrics Then Begin
      If FieldAfter(CurrentLine,'N')='space'Then
        ParseReal(FieldAfter(CurrentLine,'WX'),SpaceWidth);
      If ParseLong(FieldAfter(CurrentLine,'C'),CodeValue)and
        (CodeValue>MaxAFMCode)Then MaxAFMCode:=CodeValue;
    End;
  End;
  Close(AFMFile);
  If FontName=''Then FontName:=OutputName;
  If HasUserSlant Then ItalicAngle:=UserSlant Else ItalicAngle:=-ItalicAngle;
End;

Function FindMapForGlyph(Const GlyphName:String):String;
Var
  MappedName:String;
Begin
  MappedName:=GetMapName(GlyphName);
  If MappedName=''Then Begin
    If Length(GlyphName)=1 Then MappedName:=GlyphName Else
    If(GlyphName='space')or(GlyphName='hyphen')or(GlyphName='minus')or
      (GlyphName='period')or(GlyphName='comma')or(GlyphName='colon')or
      (GlyphName='semicolon')or(GlyphName='exclam')or(GlyphName='question')or
      (GlyphName='parenleft')or(GlyphName='parenright')or
      (GlyphName='bracketleft')or(GlyphName='bracketright')or
      (GlyphName='braceleft')or(GlyphName='braceright')Then
      MappedName:=GlyphName;
  End;
  FindMapForGlyph:=MappedName;
End;

Function OutputFontName:String;
Var
  Directory:DirStr;
  Name:NameStr;
  Extension:ExtStr;
Begin
  FSplit(OutputName,Directory,Name,Extension);
  If(Name+Extension)<>''Then OutputFontName:=Name+Extension
                            Else OutputFontName:=OutputName;
End;

Procedure WriteFontHeader;
Begin
  WriteLn(OutputFile,'name ',OutputFontName);
  WriteLn(OutputFile,'internalname ',FontName);
  WriteLn(OutputFile,'spacewidth ',ScaleRealMetric(SpaceWidth));
  If ItalicAngle<>0 Then WriteLn(OutputFile,'slant ',ItalicAngle);
  If SpecialFont Then WriteLn(OutputFile,'special');
  If IncludeLigatures Then WriteLn(OutputFile,'ligatures fi fl ff ffi ffl 0');
  If(Copy(EncodingScheme,1,6)='FontSpecific')and(Not SpecialFont)Then
    WriteLn(OutputFile,'special');
  WriteLn(OutputFile,'charset');
End;

Function ParseAFMRealList(Const S:String; Position:Integer):Real;
Var
  Index:Integer;
  WordValue:String;
  Value:Real;
Begin
  Index:=1;
  While Position>1 Do Begin
    WordValue:=NextWord(S,Index);
    Dec(Position);
  End;
  WordValue:=NextWord(S,Index);
  If Not ParseReal(WordValue,Value)Then Value:=0;
  ParseAFMRealList:=Value;
End;

Procedure WriteGlyph(Const SourceLine:String);
Var
  PS,Glyph,WidthText,BoxText,CodeText:String;
  WidthUnits,Height,Depth,Code:LongInt;
  WidthValue,XMin,YMin,XMax,YMax:Real;
  ItalicCorrection,LeftCorrection,SubscriptCorrection,Limit:LongInt;
  CodeStr,MetricStr:String;
  GlyphType:Integer;
  AngleRadians,Tangent:Real;
Begin
  PS:=FieldAfter(SourceLine,'N');
  If PS=''Then Exit;
  PS:=Copy(PS,1,Pos(' ',PS+' ')-1);
  Glyph:=FindMapForGlyph(PS);
  If Glyph=''Then Glyph:='---';
  WidthText:=FieldAfter(SourceLine,'WX');
  BoxText:=FieldAfter(SourceLine,'B');
  CodeText:=FieldAfter(SourceLine,'C');
  If Not ParseReal(WidthText,WidthValue)Then Exit;
  WidthUnits:=ScaleRealMetric(WidthValue);
  XMin:=ParseAFMRealList(BoxText,1);
  YMin:=ParseAFMRealList(BoxText,2);
  XMax:=ParseAFMRealList(BoxText,3);
  YMax:=ParseAFMRealList(BoxText,4);
  Height:=ScaleRealMetric(YMax);
  Depth:=ScaleRealMetric(-YMin);
  If Depth<0 Then Depth:=0;
  If Height<0 Then Height:=0;
  GlyphType:=0;
  If YMin<0 Then Inc(GlyphType,1);
  If YMax>0 Then Inc(GlyphType,2);
  If EncodingLoaded Then Code:=GetEncodingCode(PS) Else Begin
    Code:=-1;
    ParseLong(CodeText,Code);
  End;
  If Code<0 Then Begin
    Code:=MaxAFMCode+1+LineCount;
    Inc(LineCount);
  End;
  ItalicCorrection:=0;
  LeftCorrection:=0;
  SubscriptCorrection:=0;
  If HasItalicFactor Then Begin
    ItalicCorrection:=ScaleMetric(ItalicFactor)+ScaleRealMetric(XMax)-WidthUnits;
    If ItalicCorrection<0 Then ItalicCorrection:=0;
    LeftCorrection:=ScaleMetric(ItalicFactor)+ScaleRealMetric(XMin);
    AngleRadians:=Abs(ItalicAngle)*3.14159265/180;
    If Cos(AngleRadians)<>0 Then
      Tangent:=Sin(AngleRadians)/Cos(AngleRadians)
    Else Tangent:=0;
    Limit:=Round(Tangent*0.8*ScaleMetric(AFMXHeight));
    SubscriptCorrection:=Limit;
    If SubscriptCorrection>ItalicCorrection Then
      SubscriptCorrection:=ItalicCorrection;
  End;
  Str(Code,CodeStr);
  Str(WidthUnits,MetricStr);
  Write(OutputFile,Glyph,' ',MetricStr,',',Height,',',Depth,',',
      ItalicCorrection,',',LeftCorrection,',',SubscriptCorrection,' ',
      GlyphType,' ',CodeStr);
  If PS<>Glyph Then Write(OutputFile,' ',PS);
  WriteLn(OutputFile);
End;

Procedure ConvertAFM;
Var
  InMetrics:Boolean;
Begin
  {$I-}Assign(AFMFile,AFMName);
  Reset(AFMFile);{$I+}
  If IOResult<>0Then Begin
    WriteLn('Erreur : impossible de lire le fichier AFM ',AFMName);
    Halt(1);
  End;
  WriteFontHeader;
  InMetrics:=False;
  LineCount:=0;
  While Not EOF(AFMFile)Do Begin
    ReadLn(AFMFile,CurrentLine);
    If StartsWith(CurrentLine,'StartCharMetrics')Then InMetrics:=True Else
    If StartsWith(CurrentLine,'EndCharMetrics')Then InMetrics:=False Else
    If InMetrics Then WriteGlyph(CurrentLine);
  End;
  Close(AFMFile);
End;

Procedure PrintHelp;
Begin
  If Copy(GetEnv('LANGUAGE'),1,2)='EN'Then Begin
    WriteLn('AFMTODIT : Generate a groff font description from an AFM file.');
    WriteLn('Syntax: afmtodit [-nsv] [-d DESC] [-e ENCODING] [-i N] [-a N] AFM MAP FONT');
    WriteLn(' -a N  Set font slant; -d FILE  Read device description');
    WriteLn(' -e FILE  Use the specified PostScript encoding');
    WriteLn(' -i N  Generate italic corrections; -n  Omit ligatures');
    WriteLn(' -s  Mark the font special; -v  Show version');
  End
   Else Begin
    WriteLn('AFMTODIT : Cette commande permet de cr'+#130+#130+'e une description de police groff ',
             'depuis un fichier AFM.');
    WriteLn;
    WriteLn('Syntaxe : afmtodit [-nsv] [-d DESC] [-e ENCODAGE] [-i N] [-a N] AFM MAP POLICE');
    WriteLn;
    WriteLn(' -a N  Definit l''oblique; -d FICHIER  Lit la description du peripherique');
    WriteLn(' -e FICHIER  Utilise l''encodage PostScript indique');
    WriteLn(' -i N  Genere les corrections italiques; -n  Omet les ligatures');
    WriteLn(' -s  Marque la police comme speciale; -v  Affiche la version');
  End;
  WriteLn(' --help  Affiche cette aide');
End;

Procedure ReadOptionValue(Const OptionName:String; Var Index:Integer;
                          Const Current:String; Var Value:String);
Begin
  If Length(Current)>2 Then Value:=Copy(Current,3,255) Else Begin
    Inc(Index);
    If Index>ParamCount Then Begin
      WriteLn('Erreur : valeur manquante pour ',OptionName);
      Halt(2);
    End;
    Value:=ParamStr(Index);
  End;
End;

BEGIN
  MappingCount:=0;
  EncodingCount:=0;
  EncodingLoaded:=False;
  IncludeLigatures:=True;
  SpecialFont:=False;
  ShowVersion:=False;
  HasUserSlant:=False;
  HasItalicFactor:=False;
  UserSlant:=0;
  ItalicFactor:=0;
  UnitWidth:=1000;
  DeviceName:='';
  EncodingName:='';
  Positionals:=0;
  AFMName:='';
  MapName:='';
  OutputName:='';
  ArgumentIndex:=1;
  While ArgumentIndex<=ParamCount Do Begin
    Arg:=ParamStr(ArgumentIndex);
    If(Arg='--help')or(Arg='-h')or(Arg='/?')or(Arg='/h')or(Arg='/H')Then Begin
      PrintHelp;
      Halt(0);
    End Else If(Arg='-v')or(Arg='--version')Then ShowVersion:=True Else
    If Arg='-n'Then IncludeLigatures:=False Else
    If Arg='-s'Then SpecialFont:=True Else
    If(Arg='-d')or(Arg='-e')or(Arg='-i')or(Arg='-a')Then Begin
      ReadOptionValue(Arg,ArgumentIndex,Arg,OptionValue);
      If Arg='-d'Then DeviceName:=OptionValue Else
      If Arg='-e'Then EncodingName:=OptionValue Else Begin
        If Not ParseLong(OptionValue,ItalicFactor)Then Begin
          WriteLn('Erreur : valeur numerique invalide : ',OptionValue);
          Halt(2);
        End;
        If Arg='-a'Then Begin
          UserSlant:=ItalicFactor;
          HasUserSlant:=True;
        End Else HasItalicFactor:=True;
      End;
    End Else If(StartsWith(Arg,'-d'))or(StartsWith(Arg,'-e'))or
      (StartsWith(Arg,'-i'))or(StartsWith(Arg,'-a'))Then Begin
      OptionValue:=Copy(Arg,3,255);
      If Arg[2]='d'Then DeviceName:=OptionValue Else
      If Arg[2]='e'Then EncodingName:=OptionValue Else Begin
        If Not ParseLong(OptionValue,ItalicFactor)Then Begin
          WriteLn('Erreur : valeur numerique invalide : ',OptionValue);
          Halt(2);
        End;
        If Arg[2]='a'Then Begin
          UserSlant:=ItalicFactor;
          HasUserSlant:=True;
        End Else HasItalicFactor:=True;
      End;
    End Else If(Length(Arg)>2)and(Arg[1]='-')Then Begin
        For I:=2 to Length(Arg)Do Begin
          If Arg[I]='n'Then IncludeLigatures:=False Else
          If Arg[I]='s'Then SpecialFont:=True Else
          If Arg[I]='v'Then ShowVersion:=True Else Begin
            WriteLn('Erreur : option inconnue : ',Arg);
            Halt(2);
          End;
        End;
    End Else If(Length(Arg)>1)and(Arg[1]='-')Then Begin
      WriteLn('Erreur : option inconnue : ',Arg);
      Halt(2);
    End Else Begin
      Inc(Positionals);
      Case Positionals Of
        1:AFMName:=Arg;
        2:MapName:=Arg;
        3:OutputName:=Arg;
        Else Begin
          WriteLn('Erreur : trop d''arguments');
          Halt(2);
        End;
      End;
    End;
    Inc(ArgumentIndex);
  End;

  If ShowVersion Then Begin
    WriteLn('afmtodit (LINUX-0) 1.0');
    Halt(0);
  End;
  If Positionals<>3 Then Begin
    WriteLn('Erreur : syntaxe : afmtodit [options] fichier.afm fichier.map police');
    Halt(2);
  End;
  ReadDeviceDescription;
  LoadMap;
  LoadEncoding;
  ReadAFMHeader;
  {$I-}Assign(OutputFile,OutputName);
  Rewrite(OutputFile);{$I+}
  If IOResult<>0Then Begin
    WriteLn('Erreur : impossible de creer le fichier ',OutputName);
    Halt(1);
  End;
  ConvertAFM;
  Close(OutputFile);
END.
