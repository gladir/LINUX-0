{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Standalone basic spell checker with built-in word lists)
}

Program ISPELL(Input,Output);

Uses DOS;

Const
  MaxWordLength=63;
  MaxLineLength=255;
  MaxFiles=32;
  DictEnglish1='ABOUT ABOVE AFTER AGAIN AIR ALL ALSO ALWAYS AM AND AN ANY ARE AS ASK';
  DictEnglish2='BACK BE BEEN BEFORE BEGIN BOTH BUT BY CALL CAN CHANGE CHILD CITY COME';
  DictEnglish3='DAY DID DIFFERENT DO DOES DOWN EACH EARLY END ENOUGH EVERY EXAMPLE';
  DictEnglish4='FACE FACT FAMILY FAR FAST FEW FIND FIRST FOR FORM FOUND FROM GET GOOD';
  DictEnglish5='HAND HAVE HE HEAD HELP HER HERE HIGH HIM HIS HOME HOUSE HOW IDEA';
  DictEnglish6='IMPORTANT IN INTO IS IT ITS JUST KEEP KIND KNOW LARGE LAST LEARN LEFT';
  DictEnglish7='LESS LIFE LIGHT LIKE LINE LIST LITTLE LONG LOOK MADE MAKE MAN MANY MAP THIS TEST';
  DictFrench1='ABORD ABSENT ACCES ACCORD ACTION ADRESSE AIDER AIME AINSI AJOUTER ALLER';
  DictFrench2='AMI AMOUR ANCIEN ANNEE APRES ARBRE ARGENT ARRET ARTICLE ASSEZ ATTENDRE';
  DictFrench3='AUTRE AUTOUR AVEC AVOIR BAS BEAU BEAUCOUP BESOIN BIEN BON BONJOUR';
  DictFrench4='BONNE BRAS BRUIT CA CELA CENT CERTAIN CES CETTE CHACUN CHANGER CHOSE';
  DictFrench5='CIEL CINQ CITE CLAIR CLASSE COEUR COMME COMMENT COMPTE CONNAITRE COUR';
  DictFrench6='DANS DE DEUX DEVANT DEVOIR DIRE DONC DONNER DROIT DU EAU ECOLE ECRIRE';
  DictFrench7='EN ENCORE ENFANT ENTRE ET ETRE EXEMPLE FACE FACILE FAIRE FAMILLE FEMME';
  DictFrench8='FILLE FILS FIN FOIS FORCE FORME FRANCE GRAND GRANDE GROUPE GUERRE HAUT';
  DictFrench9='HEURE HISTOIRE HOMME ICI IMAGE IMPORTANT JAMAIS JE JEU JEUNE JOIE JOUR';
  DictFrench10='LIRE LIVRE LONG MAIN MAISON MAIS MATIN MER MERCI METTRE MOI MONDE MOT';

Type
  TWord=String[MaxWordLength];
  TLine=String[MaxLineLength];
  TFileName=String[127];
  TFileArray=Array[1..MaxFiles]Of TFileName;

Var
  FileNames:TFileArray;
  FileCount:Integer;
  ExtraCharacters:String[63];
  DictionaryName:TFileName;
  ListMode,PipeMode,ExpandMode,QuietMode:Boolean;
  English,ErrorFound:Boolean;
  LanguageCode:String[20];
  LineNumber:LongInt;

Function UpperText(Const Value:TWord):TWord;
Var
  Index:Integer;
  ResultWord:TWord;
Begin
  ResultWord:=Value;
  For Index:=1 to Length(ResultWord)Do
    If ResultWord[Index]in['a'..'z']Then ResultWord[Index]:=Chr(Ord(ResultWord[Index])-32);
  UpperText:=ResultWord;
End;

Function TrimLineText(Value:TLine):TLine;
Begin
  While(Length(Value)>0)and(Value[1]in[' ',#9])Do Delete(Value,1,1);
  While(Length(Value)>0)and(Value[Length(Value)]in[' ',#9])Do
    Delete(Value,Length(Value),1);
  TrimLineText:=Value;
End;

Function ContainsWord(Const DictionaryText:String; Const WordText:TWord):Boolean;
Var
  Position,StartPosition:Integer;
  Candidate:TWord;
Begin
  ContainsWord:=False;
  Position:=1;
  While Position<=Length(DictionaryText)Do Begin
    While(Position<=Length(DictionaryText))and(DictionaryText[Position]=' ')Do Inc(Position);
    StartPosition:=Position;
    While(Position<=Length(DictionaryText))and(DictionaryText[Position]<>' ')Do Inc(Position);
    If Position>StartPosition Then Begin
      Candidate:=Copy(DictionaryText,StartPosition,Position-StartPosition);
      If Candidate=WordText Then Begin ContainsWord:=True;Exit;End;
    End;
  End;
End;

Function InEnglishWords(Const WordText:TWord):Boolean;
Var
  Found:Boolean;
Begin
  Found:=ContainsWord(DictEnglish1,WordText);
  If Found Then Begin InEnglishWords:=True;Exit;End;
  Found:=ContainsWord(DictEnglish2,WordText);
  If Found Then Begin InEnglishWords:=True;Exit;End;
  Found:=ContainsWord(DictEnglish3,WordText);
  If Found Then Begin InEnglishWords:=True;Exit;End;
  Found:=ContainsWord(DictEnglish4,WordText);
  If Found Then Begin InEnglishWords:=True;Exit;End;
  Found:=ContainsWord(DictEnglish5,WordText);
  If Found Then Begin InEnglishWords:=True;Exit;End;
  Found:=ContainsWord(DictEnglish6,WordText);
  If Found Then Begin InEnglishWords:=True;Exit;End;
  InEnglishWords:=ContainsWord(DictEnglish7,WordText);
End;

Function InFrenchWords(Const WordText:TWord):Boolean;
Var
  Found:Boolean;
Begin
  Found:=ContainsWord(DictFrench1,WordText);
  If Found Then Begin InFrenchWords:=True;Exit;End;
  Found:=ContainsWord(DictFrench2,WordText);
  If Found Then Begin InFrenchWords:=True;Exit;End;
  Found:=ContainsWord(DictFrench3,WordText);
  If Found Then Begin InFrenchWords:=True;Exit;End;
  Found:=ContainsWord(DictFrench4,WordText);
  If Found Then Begin InFrenchWords:=True;Exit;End;
  Found:=ContainsWord(DictFrench5,WordText);
  If Found Then Begin InFrenchWords:=True;Exit;End;
  Found:=ContainsWord(DictFrench6,WordText);
  If Found Then Begin InFrenchWords:=True;Exit;End;
  Found:=ContainsWord(DictFrench7,WordText);
  If Found Then Begin InFrenchWords:=True;Exit;End;
  Found:=ContainsWord(DictFrench8,WordText);
  If Found Then Begin InFrenchWords:=True;Exit;End;
  Found:=ContainsWord(DictFrench9,WordText);
  If Found Then Begin InFrenchWords:=True;Exit;End;
  InFrenchWords:=ContainsWord(DictFrench10,WordText);
End;

Function InBuiltDictionary(Const WordText:TWord):Boolean;
Var
  UpperWord:TWord;
  RootWord:TWord;
  SuffixLength:Integer;
  WordFound:Boolean;
Begin
  UpperWord:=UpperText(WordText);
  If English Then WordFound:=InEnglishWords(UpperWord)
  Else WordFound:=InFrenchWords(UpperWord);
  If WordFound Then Begin InBuiltDictionary:=True;Exit;End;
  WordFound:=False;
  SuffixLength:=Length(UpperWord);
  If English Then Begin
    If(SuffixLength>3)and(Copy(UpperWord,SuffixLength-2,3)='ING')Then Begin
      RootWord:=Copy(UpperWord,1,SuffixLength-3);
      WordFound:=InEnglishWords(RootWord);
    End Else If(SuffixLength>2)and(Copy(UpperWord,SuffixLength-1,2)='ED')Then Begin
      RootWord:=Copy(UpperWord,1,SuffixLength-2);
      WordFound:=InEnglishWords(RootWord);
    End Else If(SuffixLength>2)and(Copy(UpperWord,SuffixLength-1,2)='LY')Then Begin
      RootWord:=Copy(UpperWord,1,SuffixLength-2);
      WordFound:=InEnglishWords(RootWord);
    End Else If(SuffixLength>1)and(UpperWord[SuffixLength]='S')Then Begin
      RootWord:=Copy(UpperWord,1,SuffixLength-1);
      WordFound:=InEnglishWords(RootWord);
    End;
  End Else If(SuffixLength>1)and(UpperWord[SuffixLength]='S')Then Begin
    RootWord:=Copy(UpperWord,1,SuffixLength-1);
    WordFound:=InFrenchWords(RootWord);
  End;
  InBuiltDictionary:=WordFound;
End;

Function InUserDictionary(Const WordText:TWord):Boolean;
Var
  DictFile:Text;
  DictionaryLine:TLine;
  ErrorCode:Integer;
Begin
  InUserDictionary:=False;
  If DictionaryName=''Then Exit;
  Assign(DictFile,DictionaryName);
  {$I-}Reset(DictFile);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then Exit;
  While Not EOF(DictFile)Do Begin
    ReadLn(DictFile,DictionaryLine);
    If UpperText(TrimLineText(DictionaryLine))=UpperText(WordText)Then Begin
      InUserDictionary:=True;
      Break;
    End;
  End;
  Close(DictFile);
End;

Function IsWordCharacter(Character:Char):Boolean;
Begin
  IsWordCharacter:=((Character>='A')and(Character<='Z'))or
    ((Character>='a')and(Character<='z'))or(Character in[#128..#255])or
    (Pos(Character,ExtraCharacters)>0)or(Character='''');
End;

Function IsCorrect(Const WordText:TWord):Boolean;
Begin
  If Length(WordText)<=1 Then IsCorrect:=True
  Else IsCorrect:=InBuiltDictionary(WordText)or InUserDictionary(WordText);
End;

Procedure ReportMisspelling(Const WordText:TWord; WordPosition:Integer);
Begin
  If PipeMode Then Begin
    Write('& ',WordText,' 0 ',WordPosition,':');
    WriteLn;
  End Else If ListMode Then WriteLn(WordText)
  Else If Not QuietMode Then WriteLn(WordText);
End;

Procedure WriteExpansion(Const WordText:TWord);
Var
  UpperWord,RootWord:TWord;
  WordLength:Integer;
Begin
  UpperWord:=UpperText(WordText);
  WordLength:=Length(UpperWord);
  If(WordLength>1)and(UpperWord[WordLength]='S')Then Begin
    RootWord:=Copy(UpperWord,1,WordLength-1);
    If InBuiltDictionary(RootWord)or InUserDictionary(RootWord)Then Begin
      WriteLn(RootWord,'/S');
      Exit;
    End;
  End;
  If(WordLength>2)and(Copy(UpperWord,WordLength-1,2)='ED')Then Begin
    RootWord:=Copy(UpperWord,1,WordLength-2);
    If InBuiltDictionary(RootWord)or InUserDictionary(RootWord)Then Begin
      WriteLn(RootWord,'/D');
      Exit;
    End;
  End;
  If(WordLength>3)and(Copy(UpperWord,WordLength-2,3)='ING')Then Begin
    RootWord:=Copy(UpperWord,1,WordLength-3);
    If InBuiltDictionary(RootWord)or InUserDictionary(RootWord)Then Begin
      WriteLn(RootWord,'/G');
      Exit;
    End;
  End;
  If InBuiltDictionary(UpperWord)or InUserDictionary(UpperWord)Then Begin
    WriteLn(UpperWord);
    Exit;
  End;
  WriteLn(UpperWord);
End;

Procedure ProcessLine(Const LineText:TLine);
Var
  Position,StartPosition,WordPosition:Integer;
  WordText:TWord;
Begin
  Position:=1;
  While Position<=Length(LineText)Do Begin
    If IsWordCharacter(LineText[Position])Then Begin
      StartPosition:=Position;
      While(Position<=Length(LineText))and IsWordCharacter(LineText[Position])Do Inc(Position);
      WordText:=Copy(LineText,StartPosition,Position-StartPosition);
      WordPosition:=StartPosition-1;
      If ExpandMode Then WriteExpansion(WordText)
      Else If IsCorrect(WordText)Then Begin
        If PipeMode Then WriteLn('*');
      End Else ReportMisspelling(WordText,WordPosition);
    End Else Inc(Position);
  End;
  If PipeMode Then WriteLn;
End;

Procedure ProcessInput(Var Source:Text);
Var
  LineText:TLine;
Begin
  LineNumber:=0;
  While Not EOF(Source)Do Begin
    ReadLn(Source,LineText);
    Inc(LineNumber);
    ProcessLine(LineText);
  End;
End;

Procedure PrintHelp;
Begin
  If English Then Begin
    WriteLn('ispell - check spelling using the built-in word list');
    WriteLn('Usage: ispell [-l|-c|-a|-e|-D] [-d dictionary] [-w chars] [file ...]');
    WriteLn('Without files, reads standard input.');
  End Else Begin
    WriteLn('ISPELL - Cette commande permet de v'+#130+'rifier l''orthographe avec un lexique int'+#130+'gr'+#130);
    WriteLn;
    WriteLn('Syntaxe : ispell [-l|-c|-a|-e|-D] [-d dictionnaire] [-w caracteres] [fichier ...]');
    WriteLn;
    WriteLn(' -l       Liste les mots incorrects');
    WriteLn(' -c       Vérifie l''orthographe');
    WriteLn(' -a       Mode pipe');
    WriteLn(' -e       Mode expansion');
    WriteLn(' -D       Affiche le dictionnaire intégré');
    WriteLn;
    WriteLn('Sans fichier, lit l''entree standard.');
  End;
End;

Procedure UsageError(Const MessageText:TLine);
Begin
  If English Then WriteLn('ispell: ',MessageText)
  Else WriteLn('ispell : ',MessageText);
  Halt(2);
End;

Procedure ParseArguments;
Var
  Argument:TFileName;
  Index,CharacterIndex:Integer;
Begin
  FileCount:=0;Index:=1;
  While Index<=ParamCount Do Begin
    Argument:=ParamStr(Index);
    If(Argument='--help')or(Argument='-?')or(Argument='/?')Then Begin PrintHelp;Halt(0);End
    Else If(Argument='--version')or(Argument='-V')or(Argument='-v')or
      (Argument='-vv')Then Begin
      WriteLn('ispell (LINUX-0) 1.0');Halt(0);
    End Else If Argument='-l'Then ListMode:=True
    Else If Argument='-c'Then ListMode:=True
    Else If(Argument='-a')or(Argument='-A')Then PipeMode:=True
    Else If(Argument='-n')Then Begin End
    Else If(Argument='-M')or(Argument='-N')or(Argument='-V')Then Begin End
    Else If Argument='-s'Then QuietMode:=True
    Else If Argument='-D'Then Begin
      If English Then WriteLn('Built-in dictionary: English and French core words')
      Else WriteLn('Dictionnaire integre : vocabulaire anglais et francais de base');
      Halt(0);
    End Else If Argument='-e'Then ExpandMode:=True
    Else If Argument='-ee'Then ExpandMode:=True
    Else If Argument='-d'Then Begin
      Inc(Index);If Index>ParamCount Then UsageError('-d attend un fichier dictionnaire');
      DictionaryName:=ParamStr(Index);
    End Else If Argument='-w'Then Begin
      Inc(Index);If Index>ParamCount Then UsageError('-w attend des caracteres');
      ExtraCharacters:=ParamStr(Index);
    End Else If(Copy(Argument,1,2)='-L')and(Length(Argument)>2)Then Begin End
    Else If(Length(Argument)>1)and(Argument[1]='-')Then Begin
      For CharacterIndex:=2 to Length(Argument)Do Begin
        Case Argument[CharacterIndex]Of
          'M','N','s','V':Begin End;
          'a','A':PipeMode:=True;
          'l','c':ListMode:=True;
          'n':Begin End;
          'e':ExpandMode:=True;
        Else UsageError('option inconnue '+Argument);End;
      End;
    End Else Begin
      If FileCount>=MaxFiles Then UsageError('trop de fichiers');
      Inc(FileCount);FileNames[FileCount]:=Argument;
    End;
    Inc(Index);
  End;
End;

Var
  Index:Integer;
  SourceFile:Text;
  ErrorCode:Integer;
Begin
  LanguageCode:=GetEnv('LANGUAGE');
  English:=Copy(LanguageCode,1,2)='EN';
  FileCount:=0;ListMode:=False;PipeMode:=False;QuietMode:=False;
  ExpandMode:=False;ErrorFound:=False;
  DictionaryName:='';ExtraCharacters:='';
  ParseArguments;
  If PipeMode Then WriteLn('@(#) ispell 1.0 (LINUX-0)');
  If FileCount=0 Then ProcessInput(Input)
  Else For Index:=1 to FileCount Do Begin
    Assign(SourceFile,FileNames[Index]);
    {$I-}Reset(SourceFile);{$I+}
    ErrorCode:=IOResult;
    If ErrorCode<>0 Then Begin
      If English Then WriteLn('ispell: cannot open ',FileNames[Index])
      Else WriteLn('ispell : impossible d''ouvrir ',FileNames[Index]);
      ErrorFound:=True;
    End Else Begin
      ProcessInput(SourceFile);
      Close(SourceFile);
    End;
  End;
  If ErrorFound Then Halt(1);
END.
