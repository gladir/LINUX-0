{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal)
  @description: Liste, extrait et verifie le contenu d'une image disque
                FAT12 ou FAT16 (disquette, ou disque dur avec MBR) creee
                par MAKEDISK.
}

Program LSIMG;

{ Programme autonome (unite DOS seulement). Il detecte une disquette (secteur
  de boot FAT au secteur 0) ou un disque dur (MBR : premiere partition FAT),
  liste tous les fichiers (/Q = sans liste), les extrait (/X:dossier) et
  verifie la coherence (/C) : copies de la FAT identiques, chaines de clusters
  valides, aucun cluster partage ou perdu, IO.SYS et MSDOS.SYS en tete de la
  racine et IO.SYS contigu (condition pour que le secteur de boot MS-DOS
  charge le noyau). Code de retour : 0 = bon, 1 = erreur de coherence ou de
  parametre, 2 = image illisible. }

{$M 16384,0,655360}
{$R-,S-,I-,V-}

Uses DOS;

Const
 {$IFDEF UNIX}
 HSep='/';
 {$ELSE}
 HSep='\';
 {$ENDIF}

Const
 M_h00=0;
 M_h01=1;
 M_h02=2;
 M_h03=3;
 M_h04=4;
 M_h05=5;
 M_h06=6;
 M_h07=7;
 M_h08=8;
 M_h09=9;
 M_eUnkOpt=10;
 M_eOpen=11;
 M_eNotFat=12;
 M_eRead=13;
 M_eCreate=14;
 M_iVol=15;
 M_iTotal=16;
 M_cOk=17;
 M_cBad=18;
 M_cChain=19;
 M_cCross=20;
 M_cLost=21;
 M_cFat=22;
 M_cBoot=23;
 M_cContig=24;
 M_cSys=25;
 M_iExtr=26;
 MsgCount=27;

{ Table des messages : FR, EN, GR, SP, IT }
Const
 MsgTab:Array[0..MsgCount-1,0..4]of String[74]=(
  (
   'LSIMG : liste, extrait et verifie une image disque FAT12/FAT16.',
   'LSIMG: lists, extracts and checks a FAT12/FAT16 disk image.',
   'LSIMG: listet, extrahiert und prueft ein FAT12/FAT16-Disk-Image.',
   'LSIMG: lista, extrae y verifica una imagen de disco FAT12/FAT16.',
   'LSIMG: elenca, estrae e verifica un''immagine disco FAT12/FAT16.'
  ),
  (
   '',
   '',
   '',
   '',
   ''
  ),
  (
   'Syntaxe : LSIMG image [/C] [/X:dossier] [/P:secteur] [/Q]',
   'Syntax: LSIMG image [/C] [/X:folder] [/P:sector] [/Q]',
   'Syntax: LSIMG image [/C] [/X:ordner] [/P:sektor] [/Q]',
   'Sintaxis: LSIMG imagen [/C] [/X:carpeta] [/P:sector] [/Q]',
   'Sintassi: LSIMG immagine [/C] [/X:cartella] [/P:settore] [/Q]'
  ),
  (
   '',
   '',
   '',
   '',
   ''
  ),
  (
   ' /C            Controle FAT, chaines, IO.SYS contigu (code 1 = erreur).',
   ' /C            Checks FAT, chains, contiguous IO.SYS (code 1 = error).',
   ' /C            Prueft FAT, Ketten, IO.SYS-Lage (Code 1 = Fehler).',
   ' /C            Verifica FAT, cadenas, IO.SYS contiguo (codigo 1 = error).',
   ' /C            Verifica FAT, catene, IO.SYS contiguo (codice 1 = errore).'
  ),
  (
   ' /X:dossier    Extrait tous les fichiers dans le dossier.',
   ' /X:folder     Extracts all the files into the folder.',
   ' /X:ordner     Extrahiert alle Dateien in den Ordner.',
   ' /X:carpeta    Extrae todos los archivos en la carpeta.',
   ' /X:cartella   Estrae tutti i file nella cartella.'
  ),
  (
   ' /P:secteur    Debut du volume en secteurs (defaut : detecte, MBR ou 0).',
   ' /P:sector     Volume start in sectors (default: detected, MBR or 0).',
   ' /P:sektor     Volumenanfang in Sektoren (Standard: erkannt, MBR oder 0).',
   ' /P:sector     Inicio del volumen en sectores (defecto: detectado o 0).',
   ' /P:settore    Inizio del volume in settori (predef.: rilevato o 0).'
  ),
  (
   ' /Q            Ne liste pas les fichiers (avec /C ou /X).',
   ' /Q            Does not list the files (with /C or /X).',
   ' /Q            Listet die Dateien nicht auf (mit /C oder /X).',
   ' /Q            No lista los archivos (con /C o /X).',
   ' /Q            Non elenca i file (con /C o /X).'
  ),
  (
   '',
   '',
   '',
   '',
   ''
  ),
  (
   'Langue : variable LANGUAGE = FR (defaut), EN, GR, SP ou IT.',
   'Language: variable LANGUAGE = FR (default), EN, GR, SP or IT.',
   'Sprache: Variable LANGUAGE = FR (Standard), EN, GR, SP oder IT.',
   'Idioma: variable LANGUAGE = FR (defecto), EN, GR, SP o IT.',
   'Lingua: variabile LANGUAGE = FR (predef.), EN, GR, SP o IT.'
  ),
  (
   'Option inconnue : %1',
   'Unknown option: %1',
   'Unbekannte Option: %1',
   'Opcion desconocida: %1',
   'Opzione sconosciuta: %1'
  ),
  (
   'Image introuvable : %1',
   'Image not found: %1',
   'Image nicht gefunden: %1',
   'Imagen no encontrada: %1',
   'Immagine non trovata: %1'
  ),
  (
   'Systeme de fichiers FAT12/FAT16 non reconnu',
   'FAT12/FAT16 file system not recognized',
   'FAT12/FAT16-Dateisystem nicht erkannt',
   'Sistema de archivos FAT12/FAT16 no reconocido',
   'File system FAT12/FAT16 non riconosciuto'
  ),
  (
   'Erreur de lecture (secteur %1)',
   'Read error (sector %1)',
   'Lesefehler (Sektor %1)',
   'Error de lectura (sector %1)',
   'Errore di lettura (settore %1)'
  ),
  (
   'Creation impossible : %1',
   'Cannot create: %1',
   'Erstellen unmoeglich: %1',
   'No se puede crear: %1',
   'Impossibile creare: %1'
  ),
  (
   'Volume : %1  FAT%2, %3 clusters de %4 octets',
   'Volume: %1  FAT%2, %3 clusters of %4 bytes',
   'Datentraeger: %1  FAT%2, %3 Cluster zu %4 Bytes',
   'Volumen: %1  FAT%2, %3 clusteres de %4 bytes',
   'Volume: %1  FAT%2, %3 cluster da %4 byte'
  ),
  (
   '%1 fichier(s), %2 dossier(s), %3 octets, %4 cluster(s) libre(s)',
   '%1 file(s), %2 folder(s), %3 bytes, %4 free cluster(s)',
   '%1 Datei(en), %2 Ordner, %3 Bytes, %4 freie Cluster',
   '%1 archivo(s), %2 carpeta(s), %3 bytes, %4 cluster(es) libre(s)',
   '%1 file, %2 cartella/e, %3 byte, %4 cluster libero/i'
  ),
  (
   'Controle : aucune erreur',
   'Check: no error',
   'Pruefung: kein Fehler',
   'Verificacion: ningun error',
   'Verifica: nessun errore'
  ),
  (
   'Controle : %1 erreur(s)',
   'Check: %1 error(s)',
   'Pruefung: %1 Fehler',
   'Verificacion: %1 error(es)',
   'Verifica: %1 errore/i'
  ),
  (
   'Erreur : chaine incorrecte : %1',
   'Error: bad chain: %1',
   'Fehler: falsche Kette: %1',
   'Error: cadena incorrecta: %1',
   'Errore: catena errata: %1'
  ),
  (
   'Erreur : cluster partage : %1',
   'Error: cross-linked cluster: %1',
   'Fehler: gemeinsamer Cluster: %1',
   'Error: cluster compartido: %1',
   'Errore: cluster condiviso: %1'
  ),
  (
   'Erreur : %1 cluster(s) perdu(s)',
   'Error: %1 lost cluster(s)',
   'Fehler: %1 verlorene Cluster',
   'Error: %1 cluster(es) perdido(s)',
   'Errore: %1 cluster perso/i'
  ),
  (
   'Erreur : les deux FAT sont differentes',
   'Error: the two FAT copies differ',
   'Fehler: die zwei FAT sind verschieden',
   'Error: las dos FAT son distintas',
   'Errore: le due FAT sono diverse'
  ),
  (
   'Erreur : IO.SYS et MSDOS.SYS ne sont pas les 2 premieres entrees',
   'Error: IO.SYS and MSDOS.SYS are not the first 2 entries',
   'Fehler: IO.SYS und MSDOS.SYS sind nicht die ersten 2 Eintraege',
   'Error: IO.SYS y MSDOS.SYS no son las 2 primeras entradas',
   'Errore: IO.SYS e MSDOS.SYS non sono le prime 2 voci'
  ),
  (
   'Erreur : IO.SYS n''est pas contigu',
   'Error: IO.SYS is not contiguous',
   'Fehler: IO.SYS ist nicht zusammenhaengend',
   'Error: IO.SYS no es contiguo',
   'Errore: IO.SYS non e contiguo'
  ),
  (
   'Disque amorcable : IO.SYS contigu, cluster %1',
   'Bootable disk: contiguous IO.SYS, cluster %1',
   'Bootfaehige Diskette: IO.SYS zusammenhaengend, Cluster %1',
   'Disco arrancable: IO.SYS contiguo, cluster %1',
   'Disco avviabile: IO.SYS contiguo, cluster %1'
  ),
  (
   'Extrait : %1',
   'Extracted: %1',
   'Extrahiert: %1',
   'Extraido: %1',
   'Estratto: %1'
  )
 );


Type
 TSec=Array[0..511]of Byte;

Var
 Lang:Integer;
 Img:File;
 ImgName,XDir:String;
 DoCheck,DoExtract,Quiet:Boolean;
 PartSec:LongInt;
 Spc,Nfat:Word;
 Rsv,RootN,Spf:Word;
 Tot,Clusters,FatStart,RootStart,DataStart,RootSecs:LongInt;
 Bits:Integer;
 FatBuf:TSec;
 FatCached:LongInt;
 Bitmap:Array[0..8191]of Byte;
 Errs,NFiles,NDirs,TotBytes:LongInt;
 RootIdx:Integer;
 IoClu:Word;
 IoSeen:Boolean;
 Eoc:Word;
 VolName:String;

{ ---- Messages ---- }

Function UpStr(S:String):String;
Var
 I:Integer;
Begin
 For I:=1 to Length(S)do
  If S[I]in['a'..'z']Then S[I]:=Chr(Ord(S[I])-32);
 UpStr:=S;
End;

Function NumStr(N:LongInt):String;
Var
 S:String;
Begin
 Str(N,S);
 NumStr:=S;
End;

Procedure InitLang;
Var
 S:String;
Begin
 Lang:=0;
 S:=Copy(UpStr(GetEnv('LANGUAGE')),1,2);
 If S='EN'Then Lang:=1
  Else If(S='GR')or(S='DE')Then Lang:=2
  Else If(S='SP')or(S='ES')Then Lang:=3
  Else If S='IT'Then Lang:=4;
End;

Function Msg(Id:Integer):String;
Begin
 Msg:=MsgTab[Id,Lang];
End;

Function Fmt(Id:Integer;Const A,B,C,D:String):String;
Var
 S,R:String;
 I:Integer;
Begin
 S:=Msg(Id);
 R:='';
 I:=1;
 While I<=Length(S)do Begin
  If(S[I]='%')and(I<Length(S))and(S[I+1]in['1'..'4'])Then Begin
   Case S[I+1]of
    '1':R:=R+A;
    '2':R:=R+B;
    '3':R:=R+C;
    '4':R:=R+D;
   End;
   Inc(I,2);
  End
  Else Begin
   R:=R+S[I];
   Inc(I);
  End;
 End;
 Fmt:=R;
End;

Procedure Say(Id:Integer;Const A,B,C,D:String);Begin
 WriteLn(Fmt(Id,A,B,C,D));
End;

Procedure Die(Code:Integer;Id:Integer;Const A:String);Begin
 WriteLn(Fmt(Id,A,'','',''));
 Halt(Code);
End;

Procedure Help;
Var
 I:Integer;
Begin
 For I:=M_H00 to M_H00+10-1 do WriteLn(Msg(I));
End;

Procedure Bad(Id:Integer;Const S:String);Begin
 Say(Id,S,'','','');
 Inc(Errs);
End;

{ ---- Acces a l'image ---- }

Function ReadSec(Lba:LongInt;Var B):Boolean;
Var
 W:Word;
Begin
 ReadSec:=False;
 Seek(Img,(PartSec+Lba)*512);
 If IOResult<>0 Then Exit;
 BlockRead(Img,B,512,W);
 ReadSec:=(IOResult=0)and(W=512);
End;

Function GetW(Var B;O:Word):Word;Begin
 GetW:=Word(TSec(B)[O])or(Word(TSec(B)[O+1])shl 8);
End;

Function GetL(Var B;O:Word):LongInt;Begin
 GetL:=LongInt(GetW(B,O))or(LongInt(GetW(B,O+2))shl 16);
End;

Function FatByte(O:LongInt):Byte;
Var
 S:LongInt;
Begin
 S:=O div 512;
 If S<>FatCached Then Begin
  If Not ReadSec(FatStart+S,FatBuf)Then Die(2,M_eRead,NumStr(FatStart+S));
  FatCached:=S;
 End;
 FatByte:=FatBuf[O mod 512];
End;

Function FatGet(N:Word):Word;
Var
 O:LongInt;
 V:Word;
Begin
 If Bits=12 Then Begin
  O:=LongInt(N)+LongInt(N)div 2;
  V:=Word(FatByte(O))or(Word(FatByte(O+1))shl 8);
  If(N and 1)<>0 Then FatGet:=V shr 4 Else FatGet:=V and $FFF;
 End
 Else Begin
  O:=LongInt(N)*2;
  FatGet:=Word(FatByte(O))or(Word(FatByte(O+1))shl 8);
 End;
End;

{ Detecte la disquette ou la partition et lit le BPB }
Procedure OpenVolume;
Var
 B:TSec;
 I:Integer;
 Ty:Byte;
 Bps:Word;
 Found:Boolean;
Begin
 Assign(Img,ImgName);
 FileMode:=0;
 Reset(Img,1);
 If IOResult<>0 Then Die(2,M_eOpen,ImgName);
 If PartSec<0 Then Begin
  PartSec:=0;
  If Not ReadSec(0,B)Then Die(2,M_eRead,'0');
  If(B[510]=$55)and(B[511]=$AA)and(GetW(B,11)<>512)Then Begin
   { MBR : premiere partition FAT, active de preference }
   Found:=False;
   For I:=0 to 3 do Begin
    Ty:=B[$1BE+I*16+4];
    If(Not Found)and(B[$1BE+I*16]=$80)and
      (Ty in[1,4,6,$0B,$0C,$0E])Then Begin
     PartSec:=GetL(B,$1BE+I*16+8);
     Found:=True;
    End;
   End;
   For I:=0 to 3 do Begin
    Ty:=B[$1BE+I*16+4];
    If(Not Found)and(Ty in[1,4,6,$0E])Then Begin
     PartSec:=GetL(B,$1BE+I*16+8);
     Found:=True;
    End;
   End;
  End;
 End;
 If Not ReadSec(0,B)Then Die(2,M_eRead,NumStr(PartSec));
 Bps:=GetW(B,11);
 Spc:=B[13];
 Rsv:=GetW(B,14);
 Nfat:=B[16];
 RootN:=GetW(B,17);
 Tot:=GetW(B,19);
 If Tot=0 Then Tot:=GetL(B,32);
 Spf:=GetW(B,22);
 If(Bps<>512)or(Spc=0)or(Nfat=0)or(Spf=0)or(RootN=0)or(Tot=0)or
   (B[510]<>$55)or(B[511]<>$AA)Then Die(2,M_eNotFat,'');
 RootSecs:=(LongInt(RootN)*32+511)div 512;
 FatStart:=Rsv;
 RootStart:=LongInt(Rsv)+LongInt(Nfat)*Spf;
 DataStart:=RootStart+RootSecs;
 Clusters:=(Tot-DataStart)div Spc;
 If Clusters<4085 Then Begin
  Bits:=12;
  Eoc:=$FF8;
 End
 Else Begin
  Bits:=16;
  Eoc:=$FFF8;
 End;
 FatCached:=-1;
 VolName:='';
End;

{ ---- Verification d'une chaine ---- }

Function Marked(C:Word):Boolean;Begin
 Marked:=(Bitmap[C shr 3]and(1 shl(C and 7)))<>0;
End;

Procedure Mark(C:Word);Begin
 Bitmap[C shr 3]:=Bitmap[C shr 3]or(1 shl(C and 7));
End;

{ Marque la chaine de Clu ; retourne le nombre de clusters ; Contig = tous
  consecutifs }
Function CheckChain(Clu:Word;Const Nm:String;Var Contig:Boolean):LongInt;
Var
 C,Prev,Nx:Word;
 N:LongInt;
 Stop:Boolean;
Begin
 N:=0;
 Contig:=True;
 Prev:=0;
 C:=Clu;
 Stop:=False;
 While(Not Stop)and(C>=2)and(C<Eoc)do Begin
  If LongInt(C)>Clusters+1 Then Begin
   Bad(M_cChain,Nm);
   Stop:=True;
  End
  Else If Marked(C)Then Begin
   Bad(M_cCross,Nm);
   Stop:=True;
  End
  Else Begin
   Mark(C);
   Inc(N);
   If(Prev<>0)and(C<>Prev+1)Then Contig:=False;
   Prev:=C;
   Nx:=FatGet(C);
   If(Nx<2)or((Nx>=$FF0)and(Nx<Eoc)and(Bits=12))or
     ((Nx>=$FFF0)and(Nx<Eoc)and(Bits=16))Then Begin
    Bad(M_cChain,Nm);
    Stop:=True;
   End;
   C:=Nx;
  End;
 End;
 CheckChain:=N;
End;

{ ---- Parcours des repertoires ---- }

Function Pad(S:String;N:Integer):String;Begin
 While Length(S)<N do S:=S+' ';
 Pad:=S;
End;

Function PadL(S:String;N:Integer):String;Begin
 While Length(S)<N do S:=' '+S;
 PadL:=S;
End;

Function Two(N:Word):String;
Var
 S:String;
Begin
 S:=NumStr(N);
 If Length(S)<2 Then S:='0'+S;
 Two:=S;
End;

Function HostPath(Const P:String):String;
Var
 S:String;
 I:Integer;
Begin
 S:=P;
 For I:=1 to Length(S)do
  If S[I]='\' Then S[I]:=HSep;
 HostPath:=XDir+S;
End;

Procedure Walk(Clu:Word;Const Path:String);Forward;

Procedure Extract(Clu:Word;Size:LongInt;Const Full:String);
Var
 F:File;
 B:TSec;
 C:Word;
 S:Integer;
 Left:LongInt;
 N,W:Word;
 Ok:Boolean;
Begin
 Assign(F,HostPath(Full));
 Rewrite(F,1);
 If IOResult<>0 Then Begin
  Say(M_eCreate,HostPath(Full),'','','');
  Inc(Errs);
  Exit;
 End;
 Left:=Size;
 C:=Clu;
 Ok:=True;
 While Ok and(Left>0)and(C>=2)and(C<Eoc)do Begin
  For S:=0 to Spc-1 do
   If Ok and(Left>0)Then Begin
    If Not ReadSec(DataStart+(LongInt(C)-2)*Spc+S,B)Then Ok:=False
    Else Begin
     If Left>512 Then N:=512 Else N:=Word(Left);
     BlockWrite(F,B,N,W);
     If(IOResult<>0)or(W<>N)Then Ok:=False;
     Left:=Left-N;
    End;
   End;
  C:=FatGet(C);
 End;
 Close(F);
 If IOResult<>0 Then Ok:=False;
 If Not Ok Then Begin
  Say(M_eCreate,HostPath(Full),'','','');
  Inc(Errs);
 End;
End;

Procedure DoSector(Lba:LongInt;Const Path:String;Var Stop:Boolean);
Var
 B:TSec;
 I,J:Integer;
 O:Word;
 Nm,Ex,Full:String;
 Attr:Byte;
 Clu,Dt,Tm:Word;
 Size,Cnt:LongInt;
 Contig:Boolean;
Begin
 If Not ReadSec(Lba,B)Then Die(2,M_eRead,NumStr(Lba));
 For I:=0 to 15 do
  If Not Stop Then Begin
   O:=I*32;
   If B[O]=0 Then Stop:=True
   Else If B[O]<>$E5 Then Begin
    Attr:=B[O+11];
    Nm:='';
    For J:=0 to 7 do
     If B[O+J]<>32 Then Nm:=Nm+Chr(B[O+J]);
    Ex:='';
    For J:=8 to 10 do
     If B[O+J]<>32 Then Ex:=Ex+Chr(B[O+J]);
    If Ex<>'' Then Nm:=Nm+'.'+Ex;
    Tm:=GetW(B,O+22);
    Dt:=GetW(B,O+24);
    Clu:=GetW(B,O+26);
    Size:=GetL(B,O+28);
    If Path='' Then Begin
     { IO.SYS et MSDOS.SYS : les deux premieres entrees de la racine }
     If(RootIdx=0)and(Nm='IO.SYS')Then IoSeen:=True;
     If(Nm='IO.SYS')and(RootIdx<>0)Then Bad(M_cBoot,'');
     If IoSeen and(RootIdx=1)and(Nm<>'MSDOS.SYS')Then Bad(M_cBoot,'');
     Inc(RootIdx);
    End;
    If Attr=$0F Then Begin
     { entree de nom long : ignoree }
    End
    Else If(Attr and 8)<>0 Then Begin
     If Path='' Then VolName:=Nm;
    End
    Else If(Nm<>'.')and(Nm<>'..')Then Begin
     Full:=Path+Nm;
     If Not Quiet Then
      Write(Pad(Full,28),' ');
     If(Attr and $10)<>0 Then Begin
      Inc(NDirs);
      If Not Quiet Then WriteLn('<DIR>');
      If DoCheck Then Cnt:=CheckChain(Clu,Full,Contig);
      If DoExtract Then Begin
       MkDir(HostPath(Full));
       If IOResult<>0 Then;
      End;
      If Clu>=2 Then Walk(Clu,Full+'\');
     End
     Else Begin
      Inc(NFiles);
      TotBytes:=TotBytes+Size;
      If Not Quiet Then
       WriteLn(PadL(NumStr(Size),9),' ',NumStr(1980+(Dt shr 9)),'-',
               Two((Dt shr 5)and 15),'-',Two(Dt and 31),' ',
               Two(Tm shr 11),':',Two((Tm shr 5)and 63),'  ',Clu);
      If DoCheck Then Begin
       If Size>0 Then Begin
        Cnt:=CheckChain(Clu,Full,Contig);
        If Cnt<>(Size+LongInt(Spc)*512-1)div(LongInt(Spc)*512)Then
         Bad(M_cChain,Full);
        If(Path='')and(Nm='IO.SYS')Then Begin
         If Contig Then IoClu:=Clu Else Bad(M_cContig,'');
        End;
       End;
      End;
      If DoExtract Then Begin
       Extract(Clu,Size,Full);
       If Quiet Then Say(M_iExtr,Full,'','','');
      End;
     End;
    End;
   End;
  End;
End;

Procedure Walk(Clu:Word;Const Path:String);
Var
 C:Word;
 S:Integer;
 Stop:Boolean;
 Guard:LongInt;
Begin
 Stop:=False;
 If Clu=0 Then Begin
  For S:=0 to RootSecs-1 do
   If Not Stop Then DoSector(RootStart+S,Path,Stop);
 End
 Else Begin
  C:=Clu;
  Guard:=0;
  While(Not Stop)and(C>=2)and(C<Eoc)and(Guard<=Clusters)do Begin
   For S:=0 to Spc-1 do
    If Not Stop Then DoSector(DataStart+(LongInt(C)-2)*Spc+S,Path,Stop);
   C:=FatGet(C);
   Inc(Guard);
  End;
 End;
End;

Function SameSec(Var A,B:TSec):Boolean;
Var
 I:Integer;
 Same:Boolean;
Begin
 Same:=True;
 For I:=0 to 511 do
  If A[I]<>B[I]Then Same:=False;
 SameSec:=Same;
End;

{ Les deux copies de la FAT sont-elles identiques ? }
Procedure CheckFats;
Var
 A,B:TSec;
 I,K,J:LongInt;
 Diff:Boolean;
Begin
 Diff:=False;
 For K:=1 to Nfat-1 do
  For I:=0 to Spf-1 do
   If Not Diff Then Begin
    If Not ReadSec(FatStart+I,A)Then Die(2,M_eRead,NumStr(FatStart+I));
    J:=FatStart+K*LongInt(Spf)+I;
    If Not ReadSec(J,B)Then Die(2,M_eRead,NumStr(J));
    If Not SameSec(A,B)Then Diff:=True;
   End;
 If Diff Then Bad(M_cFat,'');
End;

Procedure Options;
Var
 I:Integer;
 S,U:String;
 Code:Integer;
Begin
 ImgName:='';
 XDir:='';
 DoCheck:=False;
 DoExtract:=False;
 Quiet:=False;
 PartSec:=-1;
 For I:=1 to ParamCount do Begin
  S:=ParamStr(I);
  U:=UpStr(S);
  If U='/C' Then DoCheck:=True
  Else If U='/Q' Then Quiet:=True
  Else If Copy(U,1,3)='/X:' Then Begin
   DoExtract:=True;
   XDir:=Copy(S,4,255);
  End
  Else If Copy(U,1,3)='/P:' Then Begin
   Val(Copy(S,4,255),PartSec,Code);
   If(Code<>0)or(PartSec<0)Then Die(1,M_eUnkOpt,S);
  End
  Else If(S<>'')and(S[1]<>'/')and(ImgName='')Then ImgName:=S
  Else Die(1,M_eUnkOpt,S);
 End;
 If ImgName='' Then Begin
  Help;
  Halt(1);
 End;
End;

Var
 Free:LongInt;
 Cnt:LongInt;
BEGIN
 InitLang;
 If(ParamCount=0)or(ParamStr(1)='/?')or(ParamStr(1)='-?')or
   (ParamStr(1)='--help')Then Begin
  Help;
  Halt(0);
 End;
 Errs:=0;
 NFiles:=0;
 NDirs:=0;
 TotBytes:=0;
 RootIdx:=0;
 IoSeen:=False;
 IoClu:=0;
 FillChar(Bitmap,SizeOf(Bitmap),0);
 Options;
 OpenVolume;
 If DoExtract Then Begin
  XDir:=HostPath('');
  If(XDir<>'')and(XDir[Length(XDir)]<>HSep)Then XDir:=XDir+HSep;
  MkDir(Copy(XDir,1,Length(XDir)-1));
  If IOResult<>0 Then;
 End;
 Walk(0,'');
 Free:=0;
 Cnt:=0;
 While Cnt<Clusters do Begin
  If FatGet(Word(Cnt+2))=0 Then Inc(Free);
  Inc(Cnt);
 End;
 If Not Quiet Then Begin
  WriteLn;
  Say(M_iVol,VolName,NumStr(Bits),NumStr(Clusters),
      NumStr(LongInt(Spc)*512));
 End;
 Say(M_iTotal,NumStr(NFiles),NumStr(NDirs),NumStr(TotBytes),NumStr(Free));
 If DoCheck Then Begin
  CheckFats;
  { clusters utilises mais non rattaches a un fichier }
  Cnt:=0;
  Free:=0;
  While Cnt<Clusters do Begin
   If(FatGet(Word(Cnt+2))<>0)and(Not Marked(Word(Cnt+2)))Then Inc(Free);
   Inc(Cnt);
  End;
  If Free>0 Then Begin
   Say(M_cLost,NumStr(Free),'','','');
   Inc(Errs);
  End;
  If IoClu<>0 Then Say(M_cSys,NumStr(IoClu),'','','');
  If Errs=0 Then Say(M_cOk,'','','','')
   Else Say(M_cBad,NumStr(Errs),'','','');
 End;
 Close(Img);
 If Errs>0 Then Halt(1);
END.
