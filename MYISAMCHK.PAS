{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Maintenance du format MALLMYD1/MALLMYI1.
    Le format MyISAM natif de MySQL n'est pas encore pris en charge.
}

Program MYISAMCHK;

{$IFDEF FPC}
 {$MODE TP}
 {$H-}
{$ENDIF}

Uses DOS;

Const
 DataMagic='MALLMYD1';
 IndexMagic='MALLMYI1';
 MaxLong=2147483647;

Type
 TMagic=Array[0..7]of Char;
 TDataHeader=Packed Record
  Magic:TMagic;
  RecSize,RecCount,ActiveCount:Longint;
  Reserved:Array[0..11]of Byte;
 End;
 TIndexHeader=Packed Record
  Magic:TMagic;
  KeySize:Word;
  EntryCount:Longint;
  Reserved:Array[0..17]of Byte;
 End;
 TEntry=Packed Record
  Status:Byte;
  Key:Array[0..15]of Char;
  DataOfs:Longint;
 End;
 TMode=(_Check,_Recover,_Optimize,_Describe);

Var
 Mode:TMode;
 English,Silent,Verbose,EndOptions,AnyTable,AnyError:Boolean;
 Arg,BaseName,DataName,IndexName,TempData,TempIndex,BackupData,BackupIndex:String;
 D,F,TD,TI:File;
 DOpen,FOpen,TDOpen,TIOpen,MadeTD,MadeTI:Boolean;
 IOFailed,CanRepair:Boolean;
 DH:TDataHeader;
 IH:TIndexHeader;
 DataSize,IndexSize,SlotSize,Slots,Entries,Active,Problems:Longint;
 CopyBuffer:Array[0..4095]of Byte;
 ArgIndex:Integer;

Function Upper(S:String):String;
Var J:Integer;
Begin
 For J:=1 to Length(S)Do
  If S[J]in['a'..'z']Then S[J]:=Chr(Ord(S[J])-32);
 Upper:=S;
End;

Function Msg(Const FR,EN:String):String;
Begin
 If English Then Msg:=EN Else Msg:=FR;
End;

Function Number(N:Longint):String;
Var S:String;
Begin
 Str(N,S);
 Number:=S;
End;

Procedure Diagnostic(Const S:String);
{$IFNDEF FPC}
Var R:Registers; Line:String;
{$ENDIF}
Begin
 {$IFDEF FPC}
 WriteLn(StdErr,'myisamchk: ',S);
 {$ELSE}
 Line:='myisamchk: '+S+#13+#10;
 R.AH:=$40;
 R.BX:=2;
 R.CX:=Length(Line);
 R.DS:=Seg(Line[1]);
 R.DX:=Ofs(Line[1]);
 MsDos(R);
 {$ENDIF}
End;

Procedure Error(Const S:String);
Begin
 Diagnostic(S);
 AnyError:=True;
End;

Procedure IOError(Const Operation:String);
Begin
 Error(BaseName+': '+Operation);
 IOFailed:=True;
End;

Procedure Issue(Const S:String;Repairable:Boolean);
Begin
 Inc(Problems);
 Diagnostic(BaseName+': '+S);
 If Not Repairable Then CanRepair:=False;
End;

Function ReadAt(Var H:File;Offset:Longint;Var Buffer;Count:Word):Boolean;
Var Got:Word; Code:Integer;
Begin
 ReadAt:=False;
 {$I-}Seek(H,Offset);{$I+}
 If IOResult<>0Then Begin
  IOError(Msg('erreur de positionnement en lecture','read seek error'));
  Exit;
 End;
 {$I-}BlockRead(H,Buffer,Count,Got);{$I+}
 Code:=IOResult;
 If(Code<>0)Or(Got<>Count)Then Begin
  IOError(Msg('lecture incomplete ou erreur de lecture','short read or read error'));
  Exit;
 End;
 ReadAt:=True;
End;

Function WriteData(Var H:File;Var Buffer;Count:Word):Boolean;
Var Done:Word; Code:Integer;
Begin
 WriteData:=False;
 {$I-}BlockWrite(H,Buffer,Count,Done);{$I+}
 Code:=IOResult;
 If(Code<>0)Or(Done<>Count)Then Begin
  IOError(Msg('ecriture incomplete ou erreur d''ecriture','short write or write error'));
  Exit;
 End;
 WriteData:=True;
End;

Procedure CloseFile(Var H:File;Var Opened:Boolean);
Begin
 If Not Opened Then Exit;
 {$I-}Close(H);{$I+}
 Opened:=False;
 If IOResult<>0Then IOError(Msg('erreur de fermeture','close error'));
End;

Function Exists(Const Name:String):Boolean;
Var SR:SearchRec; Code:Integer;
Begin
 FindFirst(Name,AnyFile,SR);
 Code:=DosError;
 Exists:=Code=0;
 {$IFDEF FPC}
 FindClose(SR);
 {$ENDIF}
 If(Code<>0)And(Code<>2)And(Code<>3)And(Code<>18)Then Begin
  IOError(Msg('impossible de verifier le chemin : ','cannot inspect path: ')+Name);
  Exists:=True;
 End;
End;

Procedure RemoveTemp(Const Name:String;Var Made:Boolean);
Var H:File;
Begin
 If Not Made Then Exit;
 Assign(H,Name);
 {$I-}Erase(H);{$I+}
 If IOResult<>0Then IOError(Msg('impossible de supprimer : ','cannot remove: ')+Name)
 Else Made:=False;
End;

Function MoveFile(Const OldName,NewName:String):Boolean;
Var H:File;
Begin
 MoveFile:=False;
 If Exists(NewName)Then Begin
  IOError(Msg('le chemin existe deja : ','path already exists: ')+NewName);
  Exit;
 End;
 Assign(H,OldName);
 {$I-}Rename(H,NewName);{$I+}
 If IOResult<>0Then Begin
  IOError(Msg('renommage impossible : ','cannot rename: ')+OldName+' -> '+NewName);
  Exit;
 End;
 MoveFile:=True;
End;

Function OpenSource(Var H:File;Const Name:String;Var Opened:Boolean):Boolean;
Begin
 OpenSource:=False;
 Assign(H,Name);
 { Lecture seule, partage interdit : ne jamais travailler sur une table ouverte. }
 FileMode:=16;
 {$I-}Reset(H,1);{$I+}
 If IOResult<>0Then Begin
  IOError(Msg('ouverture exclusive impossible : ','cannot open exclusively: ')+Name);
  Exit;
 End;
 Opened:=True;
 OpenSource:=True;
End;

Function CreateTemp(Var H:File;Const Name:String;
                    Var Opened,Made:Boolean):Boolean;
Begin
 CreateTemp:=False;
 If Exists(Name)Then Begin
  IOError(Msg('le fichier temporaire existe deja : ','temporary path already exists: ')+Name);
  Exit;
 End;
 If IOFailed Then Exit;
 Assign(H,Name);
 FileMode:=18;
 {$I-}Rewrite(H,1);{$I+}
 If IOResult<>0Then Begin
  IOError(Msg('creation impossible : ','cannot create: ')+Name);
  Exit;
 End;
 Opened:=True;
 Made:=True;
 CreateTemp:=True;
End;

Function MagicIs(Const Magic:TMagic;Const S:String):Boolean;
Var J:Integer; OK:Boolean;
Begin
 OK:=True;
 For J:=0 to 7Do If Magic[J]<>S[J+1]Then OK:=False;
 MagicIs:=OK;
End;

Function EntryAt(N:Longint;Var E:TEntry):Boolean;
Begin
 EntryAt:=ReadAt(F,32+N*21,E,21);
End;

Function ValidOffset(Offset:Longint):Boolean;
Begin
 ValidOffset:=False;
 If Offset<32Then Exit;
 If Offset>=DataSize Then Exit;
 ValidOffset:=((Offset-32)Mod SlotSize)=0;
End;

Function StatusAt(Offset:Longint;Var Status:Byte):Boolean;
Begin
 StatusAt:=ReadAt(D,Offset,Status,1);
End;

Function SameKey(Const A,B:TEntry):Boolean;
Var J:Integer; OK:Boolean;
Begin
 OK:=True;
 For J:=0 to 15Do If A.Key[J]<>B.Key[J]Then OK:=False;
 SameKey:=OK;
End;

Function FindForSlot(Offset:Longint;Var Found:TEntry;Var Matches:Longint):Boolean;
Var N:Longint; E:TEntry;
Begin
 FindForSlot:=False;
 Matches:=0;
 For N:=0 to Entries-1Do Begin
  If Not EntryAt(N,E)Then Exit;
  If E.DataOfs=Offset Then Begin
   Found:=E;
   Inc(Matches);
  End;
 End;
 FindForSlot:=True;
End;

Function LoadHeaders:Boolean;
Begin
 LoadHeaders:=False;
 If Not OpenSource(F,IndexName,FOpen)Then Exit;
 {$I-}IndexSize:=FileSize(F);{$I+}
 If(IOResult<>0)Or(IndexSize<0)Then Begin
  IOError(Msg('taille d''index inaccessible ou trop grande','index size unavailable or too large'));
  Exit;
 End;
 If IndexSize<8Then Begin
  Error(BaseName+': '+Msg('en-tete d''index tronque','truncated index header'));
  Exit;
 End;
 If Not ReadAt(F,0,IH.Magic,8)Then Exit;
 If Not MagicIs(IH.Magic,IndexMagic)Then Begin
  If(Ord(IH.Magic[0])=$FE)And(Ord(IH.Magic[1])=$FE)Then
   Error(BaseName+': '+Msg(
    'MyISAM natif MySQL/MariaDB : pas encore pris en charge; aucune modification',
    'native MySQL/MariaDB MyISAM: not yet supported; no changes'))
  Else Error(BaseName+': '+Msg('format d''index inconnu','unknown index format'));
  Exit;
 End;
 If Not OpenSource(D,DataName,DOpen)Then Exit;
 {$I-}DataSize:=FileSize(D);{$I+}
 If(IOResult<>0)Or(DataSize<0)Then Begin
  IOError(Msg('taille des donnees inaccessible ou trop grande','data size unavailable or too large'));
  Exit;
 End;
 If(DataSize<32)Or(IndexSize<32)Then Begin
  Error(BaseName+': '+Msg('en-tete tronque','truncated header'));
  Exit;
 End;
 If Not ReadAt(D,0,DH,32)Then Exit;
 If Not ReadAt(F,0,IH,32)Then Exit;
 If Not MagicIs(DH.Magic,DataMagic)Then Begin
  Error(BaseName+': '+Msg('format de donnees inconnu','unknown data format'));
  Exit;
 End;
 If(DH.RecSize<=0)Or(DH.RecSize>MaxLong-33)Or(IH.KeySize<>16)Then Begin
  Error(BaseName+': '+Msg('taille d''enregistrement ou de cle invalide',
                         'invalid record or key size'));
  Exit;
 End;
 SlotSize:=DH.RecSize+1;
 If((DataSize-32)Mod SlotSize<>0)Or((IndexSize-32)Mod 21<>0)Then Begin
  Error(BaseName+': '+Msg('enregistrement ou entree d''index incomplet',
                         'partial record or index entry'));
  Exit;
 End;
 Slots:=(DataSize-32)Div SlotSize;
 Entries:=(IndexSize-32)Div 21;
 LoadHeaders:=True;
End;

Function Validate:Boolean;
Var N,K,Offset,Matches:Longint; Status,OtherStatus:Byte; E,Other:TEntry;
Begin
 Validate:=False;
 Active:=0;
 For N:=0 to Slots-1Do Begin
  Offset:=32+N*SlotSize;
  If Not StatusAt(Offset,Status)Then Exit;
  If Status>1Then Issue(Msg('statut de donnees invalide au slot ',
                            'invalid data status at slot ')+Number(N),False);
  If Status=0Then Inc(Active);
 End;
 If DH.RecCount<>Slots Then
  Issue(Msg('compteur de slots incorrect','incorrect slot count'),True);
 If DH.ActiveCount<>Active Then
  Issue(Msg('compteur de lignes actives incorrect','incorrect active row count'),True);
 If IH.EntryCount<>Entries Then
  Issue(Msg('compteur d''index incorrect','incorrect index count'),True);
 For N:=0 to Entries-1Do Begin
  If Not EntryAt(N,E)Then Exit;
  If E.Status>1Then Issue(Msg('statut d''index invalide : ',
                             'invalid index status: ')+Number(N),False);
  If Not ValidOffset(E.DataOfs)Then
   Issue(Msg('pointeur d''index invalide : ','invalid index pointer: ')+Number(N),False)
  Else Begin
   If Not StatusAt(E.DataOfs,Status)Then Exit;
   If E.Status<>Status Then
    Issue(Msg('statuts index/donnees differents : ',
              'index/data status mismatch: ')+Number(N),True);
   If Status=0Then
    For K:=0 to N-1Do Begin
     If Not EntryAt(K,Other)Then Exit;
     If ValidOffset(Other.DataOfs)Then Begin
      If Not StatusAt(Other.DataOfs,OtherStatus)Then Exit;
      If(OtherStatus=0)And SameKey(E,Other)Then
       Issue(Msg('cle dupliquee dans les lignes actives',
                 'duplicate key among active rows'),False);
     End;
    End;
  End;
 End;
 For N:=0 to Slots-1Do Begin
  Offset:=32+N*SlotSize;
  If Not StatusAt(Offset,Status)Then Exit;
  If Status=0Then Begin
   If Not FindForSlot(Offset,E,Matches)Then Exit;
   If Matches<>1Then
    Issue(Msg('cle absente ou ambigue au slot ',
              'missing or ambiguous key at slot ')+Number(N),False);
  End;
 End;
 Validate:=True;
End;

Function CopyBytes(Offset,Length:Longint):Boolean;
Var Count:Word;
Begin
 CopyBytes:=False;
 While Length>0Do Begin
  Count:=SizeOf(CopyBuffer);
  If Length<Count Then Count:=Length;
  If Not ReadAt(D,Offset,CopyBuffer,Count)Then Exit;
  If Not WriteData(TD,CopyBuffer,Count)Then Exit;
  Offset:=Offset+Count;
  Length:=Length-Count;
 End;
 CopyBytes:=True;
End;

Function BuildTables:Boolean;
Var N,Offset,Matches,NewOffset:Longint; Status:Byte; E:TEntry;
    NewDH:TDataHeader; NewIH:TIndexHeader;
Begin
 BuildTables:=False;
 If Not CreateTemp(TD,TempData,TDOpen,MadeTD)Then Exit;
 If Not CreateTemp(TI,TempIndex,TIOpen,MadeTI)Then Exit;
 NewDH:=DH;
 NewIH:=IH;
 NewDH.RecCount:=Slots;
 If Mode=_Optimize Then NewDH.RecCount:=Active;
 NewDH.ActiveCount:=Active;
 NewIH.EntryCount:=Active;
 If Not WriteData(TD,NewDH,32)Then Exit;
 If Not WriteData(TI,NewIH,32)Then Exit;
 NewOffset:=32;
 For N:=0 to Slots-1Do Begin
  Offset:=32+N*SlotSize;
  If Not StatusAt(Offset,Status)Then Exit;
  If(Mode<>_Optimize)Or(Status=0)Then Begin
   If Not CopyBytes(Offset,SlotSize)Then Exit;
   If Status=0Then Begin
    If Not FindForSlot(Offset,E,Matches)Then Exit;
    If Matches<>1Then Begin
     IOError(Msg('la table a change pendant la lecture','table changed while reading'));
     Exit;
    End;
    E.Status:=0;
    E.DataOfs:=NewOffset;
    If Not WriteData(TI,E,21)Then Exit;
   End;
   NewOffset:=NewOffset+SlotSize;
  End;
 End;
 CloseFile(TD,TDOpen);
 CloseFile(TI,TIOpen);
 BuildTables:=Not IOFailed;
End;

Function InstallTables:Boolean;
Var SavedD,SavedI,InstalledD,InstalledI,OK:Boolean;
Begin
 InstallTables:=False;
 SavedD:=False;
 SavedI:=False;
 InstalledD:=False;
 InstalledI:=False;
 CloseFile(D,DOpen);
 CloseFile(F,FOpen);
 If IOFailed Then Exit;
 { Les originaux sont conserves; jamais d'ecrasement d'une sauvegarde. }
 SavedD:=MoveFile(DataName,BackupData);
 If SavedD Then SavedI:=MoveFile(IndexName,BackupIndex);
 If SavedI Then Begin
  InstalledD:=MoveFile(TempData,DataName);
  If InstalledD Then Begin
   MadeTD:=False;
   InstalledI:=MoveFile(TempIndex,IndexName);
   If InstalledI Then MadeTI:=False;
  End;
 End;
 If InstalledI Then Begin
  InstallTables:=True;
  Exit;
 End;
 { Annulation des renommages; en cas d'echec, conserver tous les fichiers. }
 OK:=True;
 If InstalledD Then Begin
  OK:=MoveFile(DataName,TempData);
  If OK Then MadeTD:=True;
 End;
 If SavedI Then
  If Not MoveFile(BackupIndex,IndexName)Then OK:=False;
 If SavedD Then
  If Not MoveFile(BackupData,DataName)Then OK:=False;
 If Not OK Then Begin
  MadeTD:=False;
  MadeTI:=False;
  Error(BaseName+': '+Msg(
   'annulation incomplete : conserver .DMB/.IMB/.TMD/.TMI pour restauration manuelle',
   'incomplete rollback: preserve .DMB/.IMB/.TMD/.TMI for manual restoration'));
 End;
End;

Function VerifyBuilt:Boolean;
Var OriginalData,OriginalIndex:String; OK:Boolean;
Begin
 VerifyBuilt:=False;
 CloseFile(D,DOpen);
 CloseFile(F,FOpen);
 If IOFailed Then Exit;
 OriginalData:=DataName;
 OriginalIndex:=IndexName;
 DataName:=TempData;
 IndexName:=TempIndex;
 Problems:=0;
 CanRepair:=True;
 OK:=LoadHeaders;
 If OK Then OK:=Validate;
 If Problems<>0Then OK:=False;
 CloseFile(D,DOpen);
 CloseFile(F,FOpen);
 DataName:=OriginalData;
 IndexName:=OriginalIndex;
 If IOFailed Then OK:=False;
 If Not OK Then Error(BaseName+': '+Msg(
  'verification des temporaires echouee; originaux inchanges',
  'temporary verification failed; originals unchanged'));
 VerifyBuilt:=OK;
End;

Procedure WorkTable;
Begin
 If Not LoadHeaders Then Exit;
 If Not Silent Then
  WriteLn(BaseName,': MALLMYD1/MALLMYI1 (',
   Msg('pas MyISAM natif','not native MyISAM'),')');
 If(Mode=_Describe)Or Verbose Then Begin
  WriteLn('  ',Msg('Taille enregistrement : ','Record size: '),DH.RecSize);
  WriteLn('  ',Msg('Slots physiques : ','Physical slots: '),Slots);
  WriteLn('  ',Msg('Entrees physiques : ','Physical index entries: '),Entries);
  WriteLn('  ',Msg('Compteurs declares : ','Stored counts: '),
          DH.RecCount,' / ',DH.ActiveCount,' / ',IH.EntryCount);
 End;
 If Mode=_Describe Then Exit;
 If Not Validate Then Exit;
 If(Mode=_Check)Then Begin
  If Problems>0Then Error(BaseName+': '+Number(Problems)+' '+
   Msg('anomalie(s); aucune modification','issue(s); no changes'))
  Else If Not Silent Then WriteLn(BaseName,': OK (structure MALL; ',Active,' ',
   Msg('ligne(s) active(s))','active row(s))'));
  Exit;
 End;
 If Not CanRepair Then Begin
  Error(BaseName+': '+Msg(
   'reparation refusee : cle ou structure irrecuperable sans schema; aucune modification',
   'repair refused: key or structure cannot be recovered without schema; no changes'));
  Exit;
 End;
 If Exists(BackupData)Or Exists(BackupIndex)Or
    Exists(TempData)Or Exists(TempIndex)Then Begin
  Error(BaseName+': '+Msg(
   'sauvegarde ou temporaire deja present; deplacer ces fichiers avant de recommencer',
   'backup or temporary path already exists; move these files before retrying'));
  Exit;
 End;
 If IOFailed Then Exit;
 If Not BuildTables Then Exit;
 If Not VerifyBuilt Then Exit;
 If Not InstallTables Then Exit;
 If Not Silent Then Begin
  WriteLn(BaseName,': ',Msg('operation terminee, lignes actives : ',
                           'operation completed, active rows: '),Active);
  WriteLn('  ',Msg('Originaux conserves : ','Originals saved: '),
          BackupData,' ',BackupIndex);
 End;
End;

Procedure ProcessTable(Const Name:String);
Var L:Integer;
Begin
 AnyTable:=True;
 IOFailed:=False;
 CanRepair:=True;
 Problems:=0;
 DOpen:=False;
 FOpen:=False;
 TDOpen:=False;
 TIOpen:=False;
 MadeTD:=False;
 MadeTI:=False;
 BaseName:=Name;
 L:=Length(BaseName);
 If L>=4Then
  If(Upper(Copy(BaseName,L-3,4))='.MYI')Or
    (Upper(Copy(BaseName,L-3,4))='.MYD')Then
   BaseName:=Copy(BaseName,1,L-4);
 If(BaseName='')Or(Length(BaseName)>251)Then Begin
  Error(Msg('nom de table vide ou trop long','empty or too long table name'));
  Exit;
 End;
 DataName:=BaseName+'.MYD';
 IndexName:=BaseName+'.MYI';
 TempData:=BaseName+'.TMD';
 TempIndex:=BaseName+'.TMI';
 BackupData:=BaseName+'.DMB';
 BackupIndex:=BaseName+'.IMB';
 WorkTable;
 CloseFile(D,DOpen);
 CloseFile(F,FOpen);
 CloseFile(TD,TDOpen);
 CloseFile(TI,TIOpen);
 RemoveTemp(TempData,MadeTD);
 RemoveTemp(TempIndex,MadeTI);
End;

Procedure ProcessArgument(Const Name:String);
Var SR:SearchRec; Dir:DirStr; Stem:NameStr; Ext:ExtStr;
    Pattern:String; Code:Integer; Found:Boolean;
Begin
 If(Pos('*',Name)=0)And(Pos('?',Name)=0)Then Begin
  ProcessTable(Name);
  Exit;
 End;
 Pattern:=Name;
 FSplit(Pattern,Dir,Stem,Ext);
 If Ext=''Then Pattern:=Pattern+'.MYI'
 Else If(Upper(Ext)<>'.MYI')And(Upper(Ext)<>'.MYD')Then Begin
  Error(Msg('motif attendu : *.MYI ou *.MYD','expected pattern: *.MYI or *.MYD'));
  Exit;
 End;
 Found:=False;
 FindFirst(Pattern,AnyFile,SR);
 Code:=DosError;
 While Code=0Do Begin
  If(SR.Attr And Directory)=0Then Begin
   Found:=True;
   ProcessTable(Dir+SR.Name);
  End;
  FindNext(SR);
  Code:=DosError;
 End;
 {$IFDEF FPC}
 FindClose(SR);
 {$ENDIF}
 If(Code<>18)And(Code<>2)Then
  Error(Msg('erreur de recherche : ','file search error: ')+Pattern);
 If Not Found Then Error(Msg('aucune table : ','no matching table: ')+Pattern);
End;

Procedure ShowHelp;
Begin
 WriteLn('MYISAMCHK : ',Msg('Cette commande permet de lancer la maintenance de tables MALL.',
                           'MALL table maintenance.'));
 WriteLn('Syntaxe / Usage: myisamchk [options] tbl_name ...');
 WriteLn;
 WriteLn(Msg('ETAPE 1 : MALLMYD1/MALLMYI1 uniquement, PAS MyISAM natif MySQL 8.4.',
             'STAGE 1: MALLMYD1/MALLMYI1 only, NOT native MySQL 8.4 MyISAM.'));
 WriteLn(Msg('Les fichiers MySQL/MariaDB sont refuses sans modification.',
             'MySQL/MariaDB files are rejected without changes.'));
 WriteLn;
 WriteLn(Msg('  -c, --check          Verification complete du format MALL (defaut).',
             '  -c, --check          Full MALL structure check (default).'));
 WriteLn(Msg('  -e, --extend-check   Meme verification, sans raccourci.',
             '  -e, --extend-check   Same check, without shortcuts.'));
 WriteLn(Msg('  -r, --recover        Corrige compteurs et statuts, reconstruit l''index.',
             '  -r, --recover        Fix counts/statuses and rebuild the index.'));
 WriteLn(Msg('  --optimize           Retire aussi les slots supprimes.',
             '  --optimize           Also remove deleted data slots.'));
 WriteLn(Msg('  -d, --description    En-tetes seulement, sans verdict d''integrite.',
             '  -d, --description    Headers only; not an integrity verdict.'));
 WriteLn(Msg('  -s, --silent         Masque les messages ordinaires, pas les erreurs.',
             '  -s, --silent         Hide normal messages, not errors.'));
 WriteLn(Msg('  -v, --verbose        Affiche les compteurs et tailles.',
             '  -v, --verbose        Display counts and sizes.'));
 WriteLn('  --backup             ',Msg('Sauvegarde obligatoire, toujours active.',
                                        'Mandatory backup, always enabled.'));
 WriteLn('  /?, --help, -h, /h, /H');
 WriteLn('  --version');
 WriteLn('  --                   ',Msg('Fin des options.','End of options.'));
 WriteLn;
 WriteLn(Msg('Nom avec ou sans .MYI/.MYD; motifs *.MYI et *.MYD acceptes.',
             'Names with or without .MYI/.MYD; *.MYI and *.MYD patterns accepted.'));
 WriteLn(Msg('ARRETER l''application et le serveur avant toute operation.',
             'STOP the application and server before any operation.'));
 WriteLn(Msg('Reparation prudente : aucune cle inventee ni ligne active supprimee.',
             'Conservative repair: no invented keys or discarded active rows.'));
 WriteLn(Msg('Le statut du slot .MYD fait foi; le contenu des champs reste opaque.',
             'The .MYD slot status is authoritative; field contents remain opaque.'));
 WriteLn(Msg('Cle absente/ambigue, doublon ou structure invalide : refus de reparer.',
             'Missing/ambiguous keys, duplicates or invalid structure: repair refused.'));
 WriteLn(Msg('Originaux : .DMB/.IMB; temporaires : .TMD/.TMI. Aucun ecrasement.',
             'Originals: .DMB/.IMB; temporary files: .TMD/.TMI. Never overwritten.'));
 WriteLn(Msg('Deux fichiers : remplacement non atomique; conserver les sauvegardes.',
             'Two files: replacement is not atomic; retain the backups.'));
 WriteLn(Msg('Verification quadratique, memoire bornee; fichiers < 2 Gio.',
             'Quadratic check, bounded memory; files < 2 GiB.'));
End;

Function Option(Const A:String):Boolean;
Begin
 Option:=True;
 If(A='-c')Or(A='--check')Or(A='-e')Or(A='--extend-check')Then Mode:=_Check
 Else If(A='-r')Or(A='--recover')Then Mode:=_Recover
 Else If A='--optimize'Then Mode:=_Optimize
 Else If(A='-d')Or(A='--description')Then Mode:=_Describe
 Else If(A='-s')Or(A='--silent')Then Silent:=True
 Else If(A='-v')Or(A='--verbose')Then Verbose:=True
 Else If A='--backup'Then
 Else Option:=False;
End;

BEGIN
 English:=Upper(GetEnv('LANGUAGE'))='EN';
 AnyError:=False;
 AnyTable:=False;
 Silent:=False;
 Verbose:=False;
 Mode:=_Check;
 EndOptions:=False;
 { Valider toutes les options avant de permettre une modification de table. }
 For ArgIndex:=1 to ParamCount Do Begin
  Arg:=ParamStr(ArgIndex);
  If Not EndOptions Then Begin
   If Arg='--'Then EndOptions:=True
   Else If(Arg='/?')Or(Arg='--help')Or(Arg='-h')Or
          (Arg='/h')Or(Arg='/H')Then Begin
    ShowHelp;
    Halt(0);
   End
   Else If Arg='--version'Then Begin
    WriteLn('MYISAMCHK 0.1-Pascal - MALL only; native MyISAM unsupported');
    Halt(0);
   End
   Else If(Length(Arg)>0)Then
    If Arg[1]='-'Then
     If Not Option(Arg)Then Begin
      Error(Msg('option inconnue ou non implementee : ',
                'unknown or unimplemented option: ')+Arg);
      Halt(1);
     End;
  End;
 End;
 EndOptions:=False;
 For ArgIndex:=1 to ParamCount Do Begin
  Arg:=ParamStr(ArgIndex);
  If Not EndOptions And(Arg='--')Then EndOptions:=True
  Else If EndOptions Then ProcessArgument(Arg)
  Else If Arg=''Then ProcessArgument(Arg)
  Else If Arg[1]<>'-'Then ProcessArgument(Arg);
 End;
 If Not AnyTable Then Begin
  Error(Msg('aucune table indiquee','no table specified'));
  Halt(1);
 End;
 If AnyError Then Halt(1);
END.
