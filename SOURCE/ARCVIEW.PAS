{$A+,B-,D+,E-,F+,I-,L+,N-,O+,R-,S+,V-}

UNIT ArcView;

INTERFACE

USES
  Common;

FUNCTION ValidIntArcType(FileName: Str12): Boolean;
PROCEDURE ViewInternalArchive(FileName: AStr);
PROCEDURE ViewDirInternalArchive;

implementation

uses Dos, Crt,
  ExecBat,
  SysOp4,
  Ansipage,
    File0,
  File14,
  TimeFunc;



FUNCTION ParseAnsiAfterEsc: Word;
VAR
  K2, K3, K4: Word;
BEGIN
  { Default: plain ESC }
  ParseAnsiAfterEsc := 27;

  { Only attempt if more chars already buffered (prevents blocking on real ESC) }
  IF NOT KeyPressed THEN EXIT;

  K2 := GetKey;
  IF (K2 = 0) OR (K2 = 224) THEN
  BEGIN
    { Unexpected, treat as ESC }
    EXIT;
  END;

  IF K2 <> Ord('[') THEN
    EXIT;

  IF NOT KeyPressed THEN EXIT;
  K3 := GetKey;

  CASE K3 OF
    Ord('A'): ParseAnsiAfterEsc := 72*256; { Up }
    Ord('B'): ParseAnsiAfterEsc := 80*256; { Down }
    Ord('C'): ParseAnsiAfterEsc := 77*256; { Right }
    Ord('D'): ParseAnsiAfterEsc := 75*256; { Left }
    Ord('H'): ParseAnsiAfterEsc := 71*256; { Home }
    Ord('F'): ParseAnsiAfterEsc := 79*256; { End }
    Ord('5'): BEGIN
               IF NOT KeyPressed THEN EXIT;
               K4 := GetKey;
               IF K4 = Ord('~') THEN ParseAnsiAfterEsc := 73*256; { PgUp }
             END;
    Ord('6'): BEGIN
               IF NOT KeyPressed THEN EXIT;
               K4 := GetKey;
               IF K4 = Ord('~') THEN ParseAnsiAfterEsc := 81*256; { PgDn }
             END;
  END;
END;

CONST
  MethodType: ARRAY [0..21] OF STRING[10] =
   ('Directory ',  {* Directory marker *}
    'Unknown!  ',  {* Unknown compression type *}
    'Stored    ',  {* No compression *}
    'Packed    ',  {* Repeat-Byte compression *}
    'Squeezed  ',  {* Huffman with repeat-Byte compression *}
    'crunched  ',  {* Obsolete LZW compression *}
    'Crunched  ',  {* LZW 9-12 bit with repeat-Byte compression *}
    'Squashed  ',  {* LZW 9-13 bit compression *}
    'Crushed   ',  {* LZW 2-13 bit compression *}
    'Shrunk    ',  {* LZW 9-13 bit compression *}
    'Reduced 1 ',  {* Probabilistic factor 1 compression *}
    'Reduced 2 ',  {* Probabilistic factor 2 compression *}
    'Reduced 3 ',  {* Probabilistic factor 3 compression *}
    'Reduced 4 ',  {* Probabilistic factor 4 compression *}
    'Frozen    ',  {* Modified LZW/Huffman compression *}
    'Imploded  ',  {* Shannon-Fano tree compression *}
    'Compressed',
    'Method 1  ',
    'Method 2  ',
    'Method 3  ',
    'Method 4  ',
    'Deflated  ');

TYPE
  ArcRecordType = RECORD   {* structure of ARC archive file header *}
    FileName: ARRAY [0..12] OF Char; {* FileName *}
    C_Size: LongInt;     {* compressed size *}
    Mod_Date: Integer;   {* last mod file Date *}
    Mod_Time: Integer;   {* last mod file Time *}
    CRC: Integer;        {* CRC *}
    U_Size: LongInt;     {* uncompressed size *}
  END;

  ZipRecordType = RECORD   {* structure of ZIP archive file header *}
    Version: Integer;    {* Version needed to extract *}
    Bit_Flag: Integer;   {* General purpose bit flag *}
    Method: Integer;     {* compression Method *}
    Mod_Time: Integer;   {* last mod file Time *}
    Mod_Date: Integer;   {* last mod file Date *}
    CRC: LongInt;        {* CRC-32 *}
    C_Size: LongInt;     {* compressed size *}
    U_Size: LongInt;     {* uncompressed size *}
    F_Length: Integer;   {* FileName Length *}
    E_Length: Integer;   {* extra field Length *}
  END;

  ZooRecordType = RECORD   {* structure of ZOO archive file header *}
    Tag: LongInt;     {* Tag -- redundancy check *}
    Typ: Byte;        {* TYPE of directory entry (always 1 for now) *}
    Method: Byte;     {* 0 = Stored, 1 = Crunched *}
    Next: LongInt;    {* position of Next directory entry *}
    Offset: LongInt;  {* position of this file *}
    Mod_Date: Word;   {* modification Date (DOS format) *}
    Mod_Time: Word;   {* modification Time (DOS format) *}
    CRC: Word;        {* CRC *}
    U_Size: LongInt;  {* uncompressed size *}
    C_Size: LongInt;  {* compressed size *}
    Major_V: Char;    {* major Version number *}
    Minor_V: Char;    {* minor Version number *}
    Deleted: Byte;    {* 0 = active, 1 = Deleted *}
    Struc: Char;      {* file structure if any *}
    Comment: LongInt; {* location of file Comment (0 = none) *}
    Cmt_Size: Word;   {* Length of Comment (0 = none) *}
    FName: ARRAY [0..12] OF Char; {* FileName *}
    Var_DirLen: Integer; {* Length of variable part of dir entry *}
    TZ: Char;         {* timezone where file was archived *}
    Dir_Crc: Word;    {* CRC of directory entry *}
  END;

  LZHRecordType = RECORD   {* structure of LZH archive file header *}
    H_Length: Byte;   {* Length of header *}
    H_Cksum: Byte;    {* checksum of header bytes *}
    Method: ARRAY [1..5] OF Char; {* compression TYPE "-lh#-" *}
    C_Size: LongInt;  {* compressed size *}
    U_Size: LongInt;  {* uncompressed size *}
    Mod_Time: Integer;{* last mod file Time *}
    Mod_Date: Integer;{* last mod file Date *}
    Attrib: Integer;  {* file attributes *}
    F_Length: Byte;   {* Length of FileName *}
    CRC: Integer;     {* CRC *}
  END;

  ARJRecordType = RECORD
    FirstHdrSize: Byte;
    ARJVersion: Byte;
    ARJRequired: Byte;
    HostOS: Byte;
    Flags: Byte;
    Method: Byte;
    FileType: Byte;
    GarbleMod: Byte;
    Time,
    Date: Integer;
    CompSize: LongInt;
    OrigSize: LongInt;
    OrigCRC: ARRAY[1..4] OF Byte;
    EntryName: Word;
    AccessMode: Word;
    HostData: Word;
  END;

  OutRec = RECORD      {* output information structure *}
    FileName: AStr;    {* output file name *}
    Date,              {* output Date *}
    Time,              {* output Time *}
    Method: Integer;   {* output storage type *}
    CSize,             {* output compressed size *}
    USize: LongInt;    {* output uncompressed size *}

  END;

CONST
  MaxArcItems = 600; { Enough for typical archives; TP7 memory friendly }

TYPE
  ArcItemRec = RECORD
    Name: AStr;
    Date: Integer;
    Time: Integer;
    Method: Integer;
    CSize: LongInt;
    USize: LongInt;
    IsDir: Boolean;
  END;
  PArcItemRec = ^ArcItemRec;

  TSavedPtrArray = ARRAY [1..MaxArcItems] OF PArcItemRec;
  PSavedPtrArray = ^TSavedPtrArray;

VAR
  CollectingList: Boolean;
  ArcItemCount: Integer;
  ArcItems: ARRAY [1..MaxArcItems] OF PArcItemRec;

  ArcNestLevel: Integer; { for nested archives; 0 = top }


PROCEDURE FreeArcItems;
VAR
  I: Integer;
BEGIN
  FOR I := 1 TO MaxArcItems DO
    IF (ArcItems[I] <> NIL) THEN
    BEGIN
      Dispose(ArcItems[I]);
      ArcItems[I] := NIL;
    END;
  ArcItemCount := 0;
END;
PROCEDURE SaveArcList(VAR SP: PSavedPtrArray; VAR SC: Integer);
VAR I: Integer;
BEGIN
  GetMem(SP, SizeOf(TSavedPtrArray));
  FillChar(SP^, SizeOf(TSavedPtrArray), 0);
  SC := ArcItemCount;
  FOR I := 1 TO ArcItemCount DO
    SP^[I] := ArcItems[I];
  { Detach current list so nested listing can reuse globals without freeing outer }
  FOR I := 1 TO ArcItemCount DO ArcItems[I] := NIL;
  ArcItemCount := 0;
END;

PROCEDURE RestoreArcList(SP: PSavedPtrArray; SC: Integer);
VAR I: Integer;
BEGIN
  { Nested viewer may have left a temporary list; ensure it is cleared }
  FreeArcItems;
  ArcItemCount := SC;
  FOR I := 1 TO SC DO
    ArcItems[I] := SP^[I];
  FOR I := SC+1 TO MaxArcItems DO
    ArcItems[I] := NIL;
  FreeMem(SP, SizeOf(TSavedPtrArray));
END;


PROCEDURE AbEnd(VAR Aborted: Boolean);
BEGIN
  NL;
  Print('^8** ^1Error processing archive^8 **');
  Aborted := TRUE;
  Abort := TRUE;
  Next := TRUE;
END;

PROCEDURE Details(Out: OutRec;
                  VAR Level,
                  NumFiles: Integer;
                  VAR TotalCompSize,
                  TotalUnCompSize: LongInt);
VAR
  OutP: AStr;
  AMPM: Str2;
  DT: DateTime;
  Ratio: LongInt;
BEGIN
  { Out.FileName preserved as stored in archive (case/path) }
  IF (CollectingList) THEN
BEGIN
  IF (ArcItemCount < MaxArcItems) THEN
  BEGIN
    Inc(ArcItemCount);
    New(ArcItems[ArcItemCount]);
    ArcItems[ArcItemCount]^.Name := Out.FileName;
    ArcItems[ArcItemCount]^.Date := Out.Date;
    ArcItems[ArcItemCount]^.Time := Out.Time;
    ArcItems[ArcItemCount]^.Method := Out.Method;
    ArcItems[ArcItemCount]^.CSize := Out.CSize;
    ArcItems[ArcItemCount]^.USize := Out.USize;
    ArcItems[ArcItemCount]^.IsDir := (Out.Method = 0);
  END;
END;

  DT.Day := Out.Date AND $1f;                 {* Day = bits 4-0 *}
  DT.Month := (Out.Date SHR 5) AND $0f;       {* Month = bits 8-5 *}
  DT.Year := ((Out.Date SHR 9) AND $7f) + 80; {* Year = bits 15-9 *}
  DT.Min := (Out.Time SHR 5) AND $3f;      {* Minute = bits 10-5 *}
  DT.Hour := (Out.Time SHR 11) AND $1f;       {* Hour = bits 15-11 *}

  IF (DT.Month > 12) THEN
    Dec(DT.Month,12);     {* adjust for Month > 12 *}
  IF (DT.Year > 99) THEN
    Dec(DT.Year,100);      {* adjust for Year > 1999 *}
  IF (DT.Hour > 23) THEN
    Dec(DT.Hour,24);       {* adjust for Hour > 23 *}
  IF (DT.Min > 59) THEN
    Dec(DT.Min,60);   {* adjust for Minute > 59 *}

  ConvertAmPm(DT.Hour,AmPm);

  IF (Out.USize = 0) THEN
    Ratio := 0
  ELSE   {* Ratio is 0% for null-Length file *}
    Ratio := (100 - ((Out.CSize * 100) DIV Out.USize));
  IF (Ratio > 99) THEN
     Ratio := 99;

  OutP := '^2'+PadRightStr(FormatNumber(Out.USize),13)+
          ' '+PadRightStr(FormatNumber(Out.CSize),13)+
          ' '+PadRightInt(Ratio,2)+'%'+
          ' ^9'+MethodType[Out.Method]+
          ' ^8'+ZeroPad(IntToStr(DT.Month))+
          '/'+ZeroPad(IntToStr(DT.Day))+
          '/'+ZeroPad(IntToStr(DT.Year))+
          ' '+ZeroPad(IntToStr(DT.Hour))+
          ':'+ZeroPad(IntToStr(DT.Min))+
          AMPM[1]+' ^1';

  IF (Level > 0) THEN
    OutP := OutP + PadRightStr('',Level); {* spaces for dirs (ARC only)*}

  OutP := OutP + Out.FileName;

  IF (NOT CollectingList) THEN
    PrintACR(OutP);

  IF (Out.Method = 0) THEN
    Inc(Level)    {* bump dir Level (ARC only) *}
  ELSE
  BEGIN
    Inc(TotalCompSize,Out.CSize);  {* adjust accumulators and counter *}
    Inc(TotalUnCompSize,Out.USize);
    Inc(NumFiles);
  END;
END;

PROCEDURE Final(NumFiles: Integer;
                TotalCompSize,
                TotalUnCompSize: LongInt);
VAR
  OutP: AStr;
  Ratio: LongInt;
BEGIN
  IF (TotalUnCompSize = 0) THEN
    Ratio := 0
  ELSE
    Ratio := (100 - ((TotalCompSize * 100) DIV TotalUnCompSize));
  IF (Ratio > 99) THEN
    Ratio := 99;

  OutP := '^2'+PadRightStr(FormatNumber(TotalUnCompSize),13)+
          ' '+PadRightStr(FormatNumber(TotalCompSize),13)+
          ' '+PadRightInt(Ratio,2)+
          '%                            ^1'+IntToStr(NumFiles)+' '+Plural('file',NumFiles);
  PrintACR('|01컴컴컴컴컴컴� 컴컴컴컴컴컴� 컴�                            컴컴컴컴컴컴');
           
  PrintACR(OutP);
END;

FUNCTION GetByte(VAR F: FILE; VAR Aborted: Boolean): Char;
VAR
  C: Char;
  NumRead: Word;
BEGIN
  IF (NOT Aborted) THEN
  BEGIN
    BlockRead(F,C,1,NumRead);
    IF (NumRead = 0) THEN
    BEGIN
      Close(F);
      AbEnd(Aborted);
    END;
    GetByte := C;
  END;
END;

PROCEDURE ZIP_Proc(VAR F: FILE;
                   VAR Out: OutRec;
                   VAR Level,
                   NumFiles: Integer;
                   VAR TotalCompSize,
                   TotalUnCompSize: LongInt;
                   VAR Aborted: Boolean);
VAR
  ZIP: ZipRecordType;
  C: Char;
  Counter: Integer;
  NumRead: Word;
  Signature: LongInt;
BEGIN
  WHILE (NOT Aborted) DO
  BEGIN
    BlockRead(F,Signature,4,NumRead);
    IF (Signature = $02014b50) OR (Signature = $06054b50) THEN
      Exit;
    IF (NumRead <> 4) OR (Signature <> $04034b50) THEN
    BEGIN
      AbEnd(Aborted);
      Exit;
    END;
    BlockRead(F,ZIP,26,NumRead);
    IF (NumRead <> 26) THEN
    BEGIN
      AbEnd(Aborted);
      Exit;
    END;
    FOR Counter := 1 TO ZIP.F_Length DO
      Out.FileName[Counter] := GetByte(F,Aborted);
    Out.FileName[0] := Chr(ZIP.F_Length);
    FOR Counter := 1 TO ZIP.E_Length DO
      C := GetByte(F,Aborted);
    Out.Date := ZIP.Mod_Date;
    Out.Time := ZIP.Mod_Time;
    Out.CSize := ZIP.C_Size;
    Out.USize := ZIP.U_Size;
    CASE ZIP.Method OF
      0 : Out.Method := 2;
      1 : Out.Method := 9;
      2,3,4,5 :
          Out.Method := (ZIP.Method + 8);
      6 : Out.Method := 15;
      8 : Out.Method := 21;
    ELSE
      Out.Method := 1;
    END;
    Details(Out,Level,NumFiles,TotalCompSize,TotalUnCompSize);
    IF (Abort) THEN
      Exit;
    Seek(F,(FilePos(F) + ZIP.C_Size));
    IF (IOResult <> 0) THEN
      AbEnd(Aborted);
    IF (Abort) THEN
      Exit;
  END;
END;

PROCEDURE ARJ_Proc(VAR ArjFile: FILE;
                   VAR Out: OutRec;
                   VAR Level,
                   NumFiles: Integer;
                   VAR TotalCompSize,
                   TotalUnCompSize: LongInt;
                   VAR Aborted: Boolean);
TYPE
  ARJSignature = RECORD
    MagicNumber: Word;
    BasicHdrSiz: Word;
  END;
VAR
  Hdr: ARJRecordType;
  Sig: ARJSignature;
  FileName,
  FileTitle: AStr;
  JunkByte: Byte;
  Counter: Integer;
  NumRead,
  ExtSize: Word;
  HeaderCrc: LongInt;
BEGIN
  BlockRead(ArjFile,Sig,SizeOf(Sig));
  IF (IOResult <> 0) OR (Sig.MagicNumber <> $EA60) THEN
    Exit
  ELSE
  BEGIN
    BlockRead(ArjFile,Hdr,SizeOf(Hdr),NumRead);
    Counter := 0;
    REPEAT
      Inc(Counter);
      BlockRead(ArjFile,FileName[Counter],1);
    UNTIL (FileName[Counter] = #0);
    FileName[0] := Chr(Counter - 1);
    REPEAT
      BlockRead(ArjFile,JunkByte,1);
    UNTIL (JunkByte = 0);
    BlockRead(ArjFile,HeaderCRC,4);
    BlockRead(ArjFile,ExtSize,2);
    IF (ExtSize > 0) THEN
      Seek(ArjFile,FilePos(ArjFile) + ExtSize + 4);
    BlockRead(ArjFile,Sig,SizeOf(Sig));
    WHILE (Sig.BasicHdrSiz > 0) AND (NOT Abort) AND (IOResult = 0) DO
    BEGIN
      BlockRead(ArjFile,Hdr,SizeOf(Hdr),NumRead);
      Counter := 0;
      REPEAT
        Inc(Counter);
        BlockRead(ArjFile,FileName[Counter],1);
      UNTIL (FileName[Counter] = #0);
      FileName[0] := Chr(Counter - 1);
      Out.FileName := FileName;
      Out.Date := Hdr.Date;
      Out.Time := Hdr.Time;
      IF (Hdr.Method = 0) THEN
        Out.Method := 2
      ELSE
        Out.Method := (Hdr.Method + 16);
      Out.CSize := Hdr.CompSize;
      Out.USize := Hdr.OrigSize;
      Details(Out,Level,NumFiles,TotalCompSize,TotalUnCompSize);
      IF (Abort) THEN
        Exit;
      REPEAT
        BlockRead(ArjFile,JunkByte,1);
      UNTIL (JunkByte = 0);
      BlockRead(ArjFile,HeaderCRC,4);
      BlockRead(ArjFile,ExtSize,2);
      Seek(ArjFile,(FilePos(ArjFile) + Hdr.CompSize));
      BlockRead(ArjFile,Sig,SizeOf(Sig));
    END;
  END;
END;

PROCEDURE ARC_Proc(VAR F: FILE;
                   VAR Out: OutRec;
                   VAR Level,
                   NumFiles: Integer;
                   VAR TotalCompSize,
                   TotalUnCompSize: LongInt;
                   VAR Aborted: Boolean);
VAR
  Arc: ArcRecordType;
  C: Char;
  Counter,
  Method: Integer;
  NumRead: Word;
BEGIN
  REPEAT
    C := GetByte(F,Aborted);
    Method := Ord(GetByte(F,Aborted));
    CASE Method OF
      0 : Exit;
      1,2 :
          Out.Method := 2;
      3,4,5,6,7 :
          Out.Method := Method;
      8,9,10 :
           Out.Method := (Method - 2);
      30 : Out.Method := 0;
      31 : Dec(Level);
    ELSE
      Out.Method := 1;
    END;
    IF (Method <> 31) THEN
    BEGIN
      BlockRead(F,Arc,23,NumRead);
      IF (NumRead <> 23) THEN
      BEGIN
        AbEnd(Aborted);
        Exit;
      END;
      IF (Method = 1) THEN
        Arc.U_Size := Arc.C_Size
      ELSE
      BEGIN
        BlockRead(F,Arc.U_Size,4,NumRead);
        IF (NumRead <> 4) THEN
        BEGIN
          AbEnd(Aborted);
          Exit;
        END;
      END;
      Counter := 0;
      REPEAT
        Inc(Counter);
        Out.FileName[Counter] := Arc.FileName[Counter - 1];
      UNTIL (Arc.FileName[Counter] = #0) OR (Counter = 13);
      Out.FileName[0] := Chr(Counter);
      Out.Date := Arc.Mod_Date;
      Out.Time := Arc.Mod_Time;
      IF (Method = 30) THEN
      BEGIN
        Arc.C_Size := 0;
        Arc.U_Size := 0;
      END;
      Out.CSize := Arc.C_Size;
      Out.USize := Arc.U_Size;
      Details(Out,Level,NumFiles,TotalCompSize,TotalUnCompSize);
      IF (Abort) THEN
        Exit;
      IF (Method <> 30) THEN
      BEGIN
        Seek(F,(FilePos(F) + Arc.C_Size));
        IF (IOResult <> 0) THEN
        BEGIN
          AbEnd(Aborted);
          Exit;
        END;
      END;
    END;
  UNTIL (C <> #$1a) OR (Aborted);
  IF (NOT Aborted) THEN
    AbEnd(Aborted);
END;

PROCEDURE ZOO_Proc(VAR F: FILE;
                   VAR Out: OutRec;
                   VAR Level,
                   NumFiles: Integer;
                   VAR TotalCompSize,
                   TotalUnCompSize: LongInt;
                   VAR Aborted: Boolean);
VAR
  ZOO: ZooRecordType;
  ZOO_LongName,
  ZOO_DirName: AStr;
  C: Char;
  NamLen,
  DirLen: Byte;
  Counter,
  Method: Integer;
  NumRead: Word;
  ZOO_Temp,
  ZOO_Tag: LongInt;
BEGIN

  FOR Counter := 0 TO 19 DO
    C := GetByte(F,Aborted);
  BlockRead(F,ZOO_Tag,4,NumRead);
  IF (NumRead <> 4) THEN
    AbEnd(Aborted);
  IF (ZOO_Tag <> $fdc4a7dc) THEN
    AbEnd(Aborted);
  BlockRead(F,ZOO_Temp,4,NumRead);
  IF (NumRead <> 4) THEN
    AbEnd(Aborted);
  Seek(F,ZOO_Temp);
  IF (IOResult <> 0) THEN
    AbEnd(Aborted);

  WHILE (NOT Aborted) DO
  BEGIN
    BlockRead(F,ZOO,56,NumRead);
    IF (NumRead <> 56) THEN
    BEGIN
      AbEnd(Aborted);
      Exit;
    END;
    IF (ZOO.Tag <> $fdc4a7dc) THEN
      AbEnd(Aborted);
    IF (Abort) OR (ZOO.Next = 0) THEN
      Exit;
    NamLen := Ord(GetByte(F,Aborted));
    DirLen := Ord(GetByte(F,Aborted));
    ZOO_LongName := '';
    ZOO_DirName := '';

    IF (NamLen > 0) THEN
      FOR Counter := 1 TO NamLen DO
        ZOO_LongName := ZOO_LongName + GetByte(F,Aborted);

    IF (DirLen > 0) THEN
    BEGIN
      FOR Counter := 1 TO DirLen DO
        ZOO_DirName := ZOO_DirName + GetByte(F,Aborted);
      IF (ZOO_DirName[Length(ZOO_DirName)] <> '/') THEN
        ZOO_DirName := ZOO_DirName + '/';
    END;
    IF (ZOO_LongName <> '') THEN
      Out.FileName := ZOO_LongName
    ELSE
    BEGIN
      Counter := 0;
      REPEAT
        Inc(Counter);
        Out.FileName[Counter] := ZOO.FName[Counter - 1];
      UNTIL (ZOO.FName[Counter] = #0) OR (Counter = 13);
      Out.FileName[0] := Chr(Counter);
      Out.FileName := ZOO_DirName+Out.FileName;
    END;
    Out.Date := ZOO.Mod_Date;
    Out.Time := ZOO.Mod_Time;
    Out.CSize := ZOO.C_Size;
    Out.USize := ZOO.U_Size;
    Method := ZOO.Method;
    CASE Method OF
      0 : Out.Method := 2;
      1 : Out.Method := 6;
    ELSE
      Out.Method := 1;
    END;
    IF NOT (ZOO.Deleted = 1) THEN
      Details(Out,Level,NumFiles,TotalCompSize,TotalUnCompSize);
    IF (Abort) THEN
      Exit;
    Seek(F,ZOO.Next);
    IF (IOResult <> 0) THEN
    BEGIN
      AbEnd(Aborted);
      Exit;
    END;
  END;
END;

PROCEDURE LZH_Proc(VAR F: FILE;
                   VAR Out: OutRec;
                   VAR Level,
                   NumFiles: Integer;
                   VAR TotalCompSize,
                   TotalUnCompSize: LongInt;
                   VAR Aborted: Boolean);
VAR
  LZH: LZHRecordType;
  C,
  Method: Char;
  Counter: Integer;
  NumRead: Word;
BEGIN
  WHILE (NOT Aborted) DO
  BEGIN
    C := GetByte(F,Aborted);
    IF (C = #0) THEN
      Exit
    ELSE
      LZH.H_Length := Ord(C);
    C := GetByte(F,Aborted);
    LZH.H_Cksum := Ord(C);
    BlockRead(F,LZH.Method,5,NumRead);
    IF (NumRead <> 5) THEN
    BEGIN
      AbEnd(Aborted);
      Exit;
    END;
    IF ((LZH.Method[1] <> '-') OR (LZH.Method[2] <> 'l') OR (LZH.Method[3] <> 'h')) THEN
    BEGIN
      AbEnd(Aborted);
      Exit;
    END;
    BlockRead(F,LZH.C_Size,15,NumRead);
    IF (NumRead <> 15) THEN
    BEGIN
      AbEnd(Aborted);
      Exit;
    END;
    FOR Counter := 1 TO LZH.F_Length DO
      Out.FileName[Counter] := GetByte(F,Aborted);
    Out.FileName[0] := Chr(LZH.F_Length);
    IF ((LZH.H_Length - LZH.F_Length) = 22) THEN
    BEGIN
      BlockRead(F,LZH.CRC,2,NumRead);
      IF (NumRead <> 2) THEN
      BEGIN
        AbEnd(Aborted);
        Exit;
      END;
    END;
    Out.Date := LZH.Mod_Date;
    Out.Time := LZH.Mod_Time;
    Out.CSize := LZH.C_Size;
    Out.USize := LZH.U_Size;
    Method := LZH.Method[4];
    CASE Method OF
      '0' : Out.Method := 2;
      '1' : Out.Method := 14;
    ELSE
      Out.Method := 1;
    END;
    Details(Out,Level,NumFiles,TotalCompSize,TotalUnCompSize);
    Seek(F,(FilePos(F) + LZH.C_Size));
    IF (IOResult <> 0) THEN
      AbEnd(Aborted);
    IF (Abort) THEN
      Exit;
  END;
END;

FUNCTION ValidIntArcType(FileName: Str12): Boolean;
CONST
  ArcTypes: ARRAY [1..7] OF Str3 = ('ZIP','ARC','PAK','ZOO','LZH','ARK','ARJ');
VAR
  Counter: Byte;
BEGIN
  ValidIntArcType := FALSE;
  FOR Counter := 1 TO 7 DO
    IF (ArcTypes[Counter] = AllCaps(Copy(FileName,(Pos('.',FileName) + 1),3))) THEN
      ValidIntArcType := TRUE;
END;


FUNCTION ArcTypeByExt(FileName: AStr): Byte;
VAR
  AType, Counter: Byte;
BEGIN
  AType := 0;
  Counter := 1;
  WHILE (Counter <= MaxArcs) AND (AType = 0) DO
  BEGIN
    IF (General.FileArcInfo[Counter].Active) THEN
      IF (General.FileArcInfo[Counter].Ext <> '') THEN
        IF (General.FileArcInfo[Counter].Ext = Copy(FileName,(Length(FileName) - 2),3)) THEN
          AType := Counter;
    Inc(Counter);
  END;
  ArcTypeByExt := AType;
END;

FUNCTION HasAnsiExt(CONST FN: AStr): Boolean;
VAR
  U: AStr;
BEGIN
  U := AllCaps(StripName(FN));
  HasAnsiExt := (Copy(U,Length(U)-2,3) = 'ANS') OR (Copy(U,Length(U)-3,4) = 'ANSI') OR
                (Copy(U,Length(U)-2,3) = 'ASC') OR (Copy(U,Length(U)-2,3) = 'NFO');
END;

PROCEDURE ConvertAnsiToPipe(CONST InFN, OutFN: AStr);
VAR
  InF: FILE;
  OutF: Text;
  B: Byte;
  NumRead: Word;
  FG, BG: Byte;
  Bright: Boolean;
  ESCMode: Boolean;
  CSI: Boolean;
  ParamStr: AStr;
  Ch: Char;

  PROCEDURE EmitColor;
  VAR
    PipeFG, PipeBG: Integer;
  BEGIN
    PipeFG := FG;
    IF (Bright) AND (PipeFG <= 7) THEN
      PipeFG := PipeFG + 8;
    PipeBG := 16 + BG;
    Write(OutF,'|'+ZeroPad(IntToStr(PipeFG))+'|'+ZeroPad(IntToStr(PipeBG)));
  END;

  PROCEDURE ApplySGR(CONST Params: AStr);
  VAR
    I, J: Integer;
    Tok: AStr;
    V: Integer;
    Err: Integer;
  BEGIN
    IF (Params = '') THEN
      Tok := '0'
    ELSE
      Tok := Params + ';';
    I := 1;
    J := 1;
    WHILE (J <= Length(Tok)) DO
    BEGIN
      IF (Tok[J] = ';') THEN
      BEGIN
        ParamStr := Copy(Tok,I,J-I);
        IF (ParamStr = '') THEN
          V := 0
        ELSE
          Val(ParamStr,V,Err);
        IF (Err <> 0) THEN
          V := 0;

        CASE V OF
          0: BEGIN FG := 7; BG := 0; Bright := FALSE; END;
          1: Bright := TRUE;
          22: Bright := FALSE;
          30..37: FG := (V - 30);
          40..47: BG := (V - 40);
          90..97: BEGIN FG := (V - 90); Bright := TRUE; END;
          100..107: BG := (V - 100);
          39: BEGIN FG := 7; Bright := FALSE; END;
          49: BG := 0;
        END;

        EmitColor;
        I := J + 1;
      END;
      Inc(J);
    END;
  END;

BEGIN
  FG := 7; BG := 0; Bright := FALSE;
  ESCMode := FALSE; CSI := FALSE; ParamStr := '';

  Assign(InF, InFN);
  Reset(InF,1);
  IF (IOResult <> 0) THEN
    Exit;

  Assign(OutF, OutFN);
  Rewrite(OutF);

  EmitColor;

  REPEAT
    BlockRead(InF,B,1,NumRead);
    IF (NumRead = 0) THEN
      Break;
    Ch := Char(B);

    IF (NOT ESCMode) THEN
    BEGIN
      IF (Ch = #27) THEN
      BEGIN
        ESCMode := TRUE;
        CSI := FALSE;
        ParamStr := '';
      END
      ELSE IF (Ch = #13) THEN
        Write(OutF,#13)
      ELSE IF (Ch = #10) THEN
        Write(OutF,#10)
      ELSE IF (Ch = #9) THEN
        Write(OutF,'     ')
      ELSE IF (Ch >= #32) OR (Ch = #8) THEN
        Write(OutF,Ch);
    END
    ELSE
    BEGIN
      { ESC sequence }
      IF (NOT CSI) THEN
      BEGIN
        IF (Ch = '[') THEN
          CSI := TRUE
        ELSE
        BEGIN
          { Ignore non-CSI escape sequences }
          ESCMode := FALSE;
        END;
      END
      ELSE
      BEGIN
        { CSI parsing: collect until a final letter }
        IF (Ch IN ['0'..'9',';','?']) THEN
          ParamStr := ParamStr + Ch
        ELSE
        BEGIN
          IF (Ch = 'm') THEN
            ApplySGR(ParamStr);
          { Ignore all other CSI commands (cursor moves, clear screen, etc.) }
          ESCMode := FALSE;
          CSI := FALSE;
          ParamStr := '';
        END;
      END;
    END;

  UNTIL FALSE;

  Close(InF);
  Close(OutF);
END;


TYPE
  TLineOffset = LongInt;
  { Large fixed arrays can exceed TP7 structure limits; use small allocated blocks instead. }
  CONST
    MaxViewLines      = 20000;
    OffsetBlockSize   = 1024;
    MaxOffsetBlocks   = (MaxViewLines + OffsetBlockSize - 1) DIV OffsetBlockSize;
  TYPE
    POffsetBlock = ^TOffsetBlock;
    TOffsetBlock = ARRAY[0..OffsetBlockSize-1] OF TLineOffset;
    TOffsetBlockPtrArray = ARRAY[0..MaxOffsetBlocks-1] OF POffsetBlock;

PROCEDURE ViewFileScroll(CONST FN, Title: AStr);
CONST
  MaxLines = 20000;
  WinTop   = 4;
  WinH     = 20;
  WinW     = 79;
VAR
  F: FILE;
    Blocks: TOffsetBlockPtrArray;
  LineCnt: Integer;
  TopLine: Integer;
  CurLine: Integer;
  FollowMode: Boolean; { TRUE=smooth cursor-follow, FALSE=jump scroll }
  Done: Boolean;
  Key: Word;


  PROCEDURE InitBlocks;
  VAR
    I: Integer;
  BEGIN
    FOR I := 0 TO MaxOffsetBlocks-1 DO
      Blocks[I] := NIL;
  END;

  PROCEDURE FreeBlocks;
  VAR
    I: Integer;
  BEGIN
    FOR I := 0 TO MaxOffsetBlocks-1 DO
      IF (Blocks[I] <> NIL) THEN
      BEGIN
        FreeMem(Blocks[I], SizeOf(TOffsetBlock));
        Blocks[I] := NIL;
      END;
  END;

  PROCEDURE SetOffset(Line: Integer; Value: TLineOffset);
  VAR
    BI, OI: Integer;
  BEGIN
    IF (Line < 1) OR (Line > MaxViewLines) THEN
      Exit;
    BI := (Line - 1) DIV OffsetBlockSize;
    OI := (Line - 1) MOD OffsetBlockSize;
    IF (Blocks[BI] = NIL) THEN
      GetMem(Blocks[BI], SizeOf(TOffsetBlock));
    Blocks[BI]^[OI] := Value;
  END;

  FUNCTION GetOffset(Line: Integer): TLineOffset;
  VAR
    BI, OI: Integer;
  BEGIN
    GetOffset := 0;
    IF (Line < 1) OR (Line > MaxViewLines) THEN
      Exit;
    BI := (Line - 1) DIV OffsetBlockSize;
    OI := (Line - 1) MOD OffsetBlockSize;
    IF (Blocks[BI] = NIL) THEN
      Exit;
    GetOffset := Blocks[BI]^[OI];
  END;
  FUNCTION IsPipeCode(CONST S: AStr; P: Integer): Boolean;
  BEGIN
    IsPipeCode := (P <= Length(S)-2) AND (S[P] = '|') AND
                  (S[P+1] IN ['0'..'9']) AND (S[P+2] IN ['0'..'9']);
  END;

  FUNCTION ClipVisible(CONST S: AStr; MaxVis: Integer): AStr;
  VAR
    I, V: Integer;
    R: AStr;
  BEGIN
    R := '';
    V := 0;
    I := 1;
    WHILE (I <= Length(S)) DO
    BEGIN
      IF IsPipeCode(S,I) THEN
      BEGIN
        R := R + Copy(S,I,3);
        Inc(I,3);
      END
      ELSE
      BEGIN
        Inc(V);
        IF (V > MaxVis) THEN
          Break;
        R := R + S[I];
        Inc(I);
      END;
    END;
    ClipVisible := R;
  END;


  FUNCTION StripAnsiEscapes(CONST S: AStr): AStr;
  VAR
    I, J: Integer;
    R: AStr;
  BEGIN
    R := '';
    I := 1;
    WHILE (I <= Length(S)) DO
    BEGIN
      IF (S[I] = #27) THEN
      BEGIN
        { Skip ANSI escape sequences like ESC[...m or ESC[...H etc }
        Inc(I);
        IF (I <= Length(S)) AND (S[I] = '[') THEN
        BEGIN
          Inc(I);
          J := I;
          WHILE (J <= Length(S)) AND NOT (S[J] IN ['@'..'~']) DO
            Inc(J);
          IF (J <= Length(S)) THEN
            I := J + 1
          ELSE
            Break;
        END
        ELSE
        BEGIN
          { Non-CSI ESC: drop next char too }
          Inc(I);
        END;
      END
      ELSE
      BEGIN
        IF (Length(R) < 255) THEN
          R := R + S[I];
        Inc(I);
      END;
    END;
    StripAnsiEscapes := R;
  END;
  FUNCTION SanitizeTextLine(S: AStr): AStr;
  { Remove control chars that can move cursor/clear screen (FF, etc).
    Convert TAB to spaces. Keep extended ASCII (>=32) intact. }
  VAR
    I, Col, TabW: Integer;
    Ch: Char;
    R: AStr;
  BEGIN
    R := '';
    Col := 0;
    TabW := 8;
    FOR I := 1 TO Length(S) DO
    BEGIN
      Ch := S[I];
      IF (Ch = #9) THEN
      BEGIN
        { tabs -> spaces to next tab stop }
        REPEAT
          IF (Length(R) < 255) THEN R := R + ' ';
          Inc(Col);
        UNTIL ((Col MOD TabW) = 0) OR (Length(R) >= 255);
      END
      ELSE IF (Ord(Ch) < 32) THEN
      BEGIN
        { drop other control chars }
      END
      ELSE
      BEGIN
        IF (Length(R) < 255) THEN R := R + Ch;
        Inc(Col);
      END;
    END;
    SanitizeTextLine := R;
  END;


  PROCEDURE GotoRC(R,C: Integer);
  BEGIN
    ANSIG(C,R);
  END;

  PROCEDURE ClearWin;
  VAR
    R: Integer;
  BEGIN
    { Always clear using normal (dark gray) attribute to prevent color bleed }
    TextColor(8);
    TextBackground(0);
    FOR R := WinTop TO WinTop+WinH-1 DO
    BEGIN
      GotoRC(R,1);
      Prt('|08|16'+PadRightStr('',79));
    END;
    TextColor(8);
    TextBackground(0);
  END;

  PROCEDURE DrawFrame;
  BEGIN
    CLS;
    Print('|15Archive File View: |11'+Title);
    Print('|09Up/Down  Home/End  ESC=Back');
    Print('|09'+ '컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴�');
                  
  END;

  FUNCTION ReadLineAt(VAR S: AStr; L: Integer): Boolean;
  VAR
    B: Byte;
    Num: Word;
    Ch: Char;
  BEGIN
    S := '';
    IF (L < 1) OR (L > LineCnt) THEN
    BEGIN
      ReadLineAt := FALSE;
      Exit;
    END;

    Seek(F, GetOffset(L));
    REPEAT
      BlockRead(F,B,1,Num);
      IF (Num = 0) THEN
        Break;
      Ch := Char(B);
      IF (Ch = #13) THEN
      BEGIN
        { consume optional LF }
        BlockRead(F,B,1,Num);
        IF (Num <> 0) AND (Char(B) <> #10) THEN
          Seek(F, FilePos(F)-1);
        Break;
      END
      ELSE IF (Ch = #10) THEN
        Break
      ELSE
      BEGIN
        IF (Length(S) < 255) THEN
          S := S + Ch;
      END;
    UNTIL FALSE;

    ReadLineAt := TRUE;
  END;

  PROCEDURE DrawPage;
  VAR
    R, L: Integer;
    S, Plain: AStr;
    Col: Integer;
  BEGIN
    { Clear window in normal color first }
    ClearWin;

    FOR R := 0 TO WinH-1 DO
    BEGIN
      L := TopLine + R;
      GotoRC(WinTop+R,1);
      TextColor(8);
    TextBackground(0);
      Prt('|08|16'+PadRightStr('',79));

      IF ReadLineAt(S,L) THEN
      BEGIN
        S := StripAnsiEscapes(S);
        S := SanitizeTextLine(S);
        GotoRC(WinTop+R,1);
        Prt(ClipVisible(S,WinW));
      END;
    END;

    { status }
    TextColor(8);
    TextBackground(0);
    GotoRC(WinTop+WinH,1);
    Prt('|08|16'+PadRightStr('',79));
    Plain := 'Line '+IntToStr(CurLine)+'/'+IntToStr(LineCnt);
    Col := 80 - Length(Plain) + 1;
    IF Col < 1 THEN Col := 1;
    GotoRC(WinTop+WinH,Col);
    Prt('|08Line |15'+IntToStr(CurLine)+'|08/|15'+IntToStr(LineCnt));
    TextColor(8);
    TextBackground(0);
  END;

  PROCEDURE BuildIndex;
  VAR
    B: Byte;
    Num: Word;
    Ch, Prev: Char;
    P: LongInt;
  BEGIN
    LineCnt := 0;
    Prev := #0;
    P := 0;
    Seek(F,0);
    Inc(LineCnt);
    SetOffset(LineCnt, 0);

    REPEAT
      BlockRead(F,B,1,Num);
      IF (Num = 0) THEN
        Break;
      Ch := Char(B);
      Inc(P);

      IF (Ch = #10) THEN
      BEGIN
        IF (LineCnt < MaxLines) THEN
        BEGIN
          Inc(LineCnt);
          SetOffset(LineCnt, P);
        END;
      END
      ELSE IF (Ch = #13) THEN
      BEGIN
        { if CR without LF, still new line }
        IF (LineCnt < MaxLines) THEN
        BEGIN
          { peek next; if it's LF, let LF handler add line start }
          BlockRead(F,B,1,Num);
          IF (Num <> 0) THEN
          BEGIN
            IF (Char(B) = #10) THEN
            BEGIN
              Inc(P);
              IF (LineCnt < MaxLines) THEN
              BEGIN
                Inc(LineCnt);
                SetOffset(LineCnt, P);
              END;
            END
            ELSE
              Seek(F, FilePos(F)-1);
          END;
        END;
      END;

      Prev := Ch;
    UNTIL FALSE;

    IF (LineCnt < 1) THEN
      LineCnt := 1;
  END;

BEGIN
  Assign(F,FN);
  {$I-} Reset(F,1); {$I+}
  IF (IOResult <> 0) THEN
  BEGIN
    NL;
    Print('^8Unable to open file for viewing:^0 '+FN);
        Print('^7Press any key...^0');
    GetKey;
Exit;
  END;

  InitBlocks;
  BuildIndex;

  TopLine := 1;
  CurLine := 1;
  FollowMode := FALSE;
  Done := FALSE;

  DrawFrame;
  DrawPage;

  REPEAT
    Key := GetKey;

    { Convert ANSI terminal ESC sequences for PgUp/PgDn (and arrows) when present }
    IF (Key = 27) THEN
      Key := ParseAnsiAfterEsc;

{ TP ReadKey-style extended keys: 0 or 224 followed by scan code }
    IF (Key = 0) OR (Key = 224) THEN
      Key := GetKey;

    { Normalize raw extended scan codes some environments return remotely }
    IF (Key < 256) THEN
      CASE Key OF
        71,72,73,75,77,79,80,81: Key := Key * 256; { Home,Up,PgUp,Left,Right,End,Down,PgDn }
      ELSE
        { leave as-is }
      END;

    { Toggle smooth (cursor-follow) vs jump scrolling }
    IF (Key = Ord('s')) OR (Key = Ord('S')) THEN
    BEGIN
      FollowMode := NOT FollowMode;
      DrawFrame;
      DrawPage;
      Continue;
    END;

    CASE Key OF
      27: Done := TRUE;

      72*256, F_UP:
        BEGIN
          IF (CurLine > 1) THEN Dec(CurLine);
          IF FollowMode THEN
          BEGIN
            IF (CurLine < TopLine) THEN TopLine := CurLine;
          END
          ELSE
            TopLine := CurLine;
          DrawPage;
        END;

      80*256, F_DOWN:
        BEGIN
          IF (CurLine < LineCnt) THEN Inc(CurLine);
          IF FollowMode THEN
          BEGIN
            IF (CurLine > TopLine + (WinH-1)) THEN TopLine := CurLine - (WinH-1);
          END
          ELSE
            TopLine := CurLine;
          IF (TopLine < 1) THEN TopLine := 1;
          DrawPage;
        END;

      73*256, F_PGUP:
        BEGIN
          CurLine := CurLine - WinH;
          IF (CurLine < 1) THEN CurLine := 1;
          IF FollowMode THEN
            TopLine := CurLine
          ELSE
            TopLine := CurLine;
          IF (TopLine < 1) THEN TopLine := 1;
          DrawPage;
        END;

      81*256, F_PGDN:
        BEGIN
          CurLine := CurLine + WinH;
          IF (CurLine > LineCnt) THEN CurLine := LineCnt;
          IF FollowMode THEN
            TopLine := CurLine - (WinH-1)
          ELSE
            TopLine := CurLine;
          IF (TopLine < 1) THEN TopLine := 1;
          DrawPage;
        END;

      71*256, F_HOME:
        BEGIN
          CurLine := 1;
          TopLine := 1;
          DrawPage;
        END;

      79*256, F_END:
        BEGIN
          CurLine := LineCnt;
          TopLine := LineCnt - (WinH-1);
          IF (TopLine < 1) THEN TopLine := 1;
          DrawPage;
        END;
    END;
  UNTIL Done;

  FreeBlocks;
  Close(F);
END;



FUNCTION AddBS(S: AStr): AStr;
BEGIN
  IF (S <> '') AND (S[Length(S)] <> Chr(92)) THEN
    S := S + Chr(92);
  AddBS := S;
END;

FUNCTION ArcLevelDir(Level: Integer): AStr;
VAR S: AStr;
BEGIN
  IF (Level <= 0) THEN S := 'ARC' ELSE S := 'ARC'+IntToStr(Level);
  ArcLevelDir := AddBS(TempDir) + S + Chr(92);
END;


FUNCTION NormArcName(S: AStr): AStr;
VAR I: Integer;
BEGIN
  FOR I := 1 TO Length(S) DO
    IF (S[I] = '/') THEN S[I] := Chr(92);
  NormArcName := S;
END;

FUNCTION UpStr(S: AStr): AStr;
VAR I: Integer;
BEGIN
  FOR I := 1 TO Length(S) DO
    S[I] := UpCase(S[I]);
  UpStr := S;
END;

FUNCTION FindExtractedFile(CONST BaseDir, TargetName: AStr): AStr;
VAR SR: SearchRec;
    R: AStr;
BEGIN
  FindExtractedFile := '';
  { search files in BaseDir }
  FindFirst(BaseDir+'*.*',AnyFile,SR);
  WHILE (DosError = 0) DO
  BEGIN
    IF (SR.Name <> '.') AND (SR.Name <> '..') THEN
    BEGIN
      IF ((SR.Attr AND Directory) = 0) THEN
      BEGIN
        IF (UpStr(SR.Name) = UpStr(TargetName)) THEN
        BEGIN
          FindExtractedFile := BaseDir+SR.Name;
          Exit;
        END;
      END
      ELSE
      BEGIN
        R := FindExtractedFile(BaseDir+SR.Name+Chr(92),TargetName);
        IF (R <> '') THEN BEGIN FindExtractedFile := R; Exit; END;
      END;
    END;
    FindNext(SR);
  END;
END;

PROCEDURE EnsureDir(CONST D: AStr);
VAR P: AStr;
BEGIN
  P := D;
  IF (P <> '') AND (P[Length(P)] = Chr(92)) THEN Dec(P[0]);
  {$I-} MkDir(P); {$I+}
END;

PROCEDURE ExtractAndViewFromArchive(CONST ArcFN: AStr; ArcType: Byte; CONST InnerName: AStr);
VAR
  Ok: Boolean;
  ResultCode: Integer;
  SavedPtrs: PSavedPtrArray;
  SavedCnt: Integer;
  ExtractFN, TryFN, ViewFN, NormName: AStr;
BEGIN
  { Extract into a per-level temp folder so nested archives can be browsed }
  EnsureDir(ArcLevelDir(ArcNestLevel+1));
  PurgeDir(ArcLevelDir(ArcNestLevel+1),FALSE);

  Ok := TRUE;
  ExecBatch(Ok,ArcLevelDir(ArcNestLevel+1),General.ArcsPath+
            FunctionalMCI(General.FileArcInfo[ArcType].UnArcLine,ArcFN,InnerName),
            General.FileArcInfo[ArcType].SuccLevel,ResultCode,FALSE);

  IF (NOT Ok) THEN
  BEGIN
    NL;
    Print('^8Error extracting file from archive.^0');
    Print('^7Press any key...^0');
    GetKey;
    Exit;
  END;

  NormName := NormArcName(InnerName);
  ExtractFN := ArcLevelDir(ArcNestLevel+1)+NormName;
  IF (NOT Exist(ExtractFN)) THEN
  BEGIN
    TryFN := ArcLevelDir(ArcNestLevel+1)+StripName(NormName);
    IF (Exist(TryFN)) THEN
      ExtractFN := TryFN;
  END;

  { If the archiver created subdirectories (common for ZIP), search for the file by name }
  IF (NOT Exist(ExtractFN)) THEN
  BEGIN
    TryFN := FindExtractedFile(ArcLevelDir(ArcNestLevel+1),StripName(NormName));
    IF (TryFN <> '') THEN ExtractFN := TryFN;
  END;


  IF (NOT Exist(ExtractFN)) THEN
  BEGIN
    NL;
    Print('^8Extracted file not found in temp directory.^0');
    Print('^7Press any key...^0');
    GetKey;
    Exit;
  END;

  IF HasAnsiExt(ExtractFN) THEN
  BEGIN
    ViewAnsiFile(ExtractFN, InnerName);
    { PurgeDir expects (DirName, RemoveDir). Keep the temp folder. }
    PurgeDir(ArcLevelDir(ArcNestLevel+1), FALSE);
    EXIT;
  END;


  ViewFN := ExtractFN;

  { If the extracted file is itself an archive, browse it interactively (nested archives) }
  IF (ArcTypeByExt(ViewFN) <> 0) THEN
  BEGIN
    { Save current (outer) listing so returning from nested archive is not blank }
    SaveArcList(SavedPtrs,SavedCnt);
    Inc(ArcNestLevel);
    ViewInternalArchive(ViewFN);
    Dec(ArcNestLevel);
    { Clean inner temp folder }
    PurgeDir(ArcLevelDir(ArcNestLevel+1),FALSE);
    RestoreArcList(SavedPtrs,SavedCnt);
    Exit;
  END;


  ViewFileScroll(ViewFN,InnerName);
  PurgeDir(ArcLevelDir(ArcNestLevel+1),FALSE);
END;

PROCEDURE BrowseArchiveUI(CONST ArcFN: AStr; ArcType: Byte);
VAR
  TopIdx, CurIdx, PerPage: Integer;
  Key: Word;
  Done, Redraw: Boolean;
  I, Row, Idx: Integer;
  Line: AStr;

  FUNCTION DispName(CONST N: AStr): AStr;
  BEGIN
    DispName := PadRightStr(StripName(AllCaps(N)),12);
  END;

  FUNCTION DispDate(D: Integer): AStr;
  VAR
    DT: DateTime;
  BEGIN
    DT.Day := D AND $1f;
    DT.Month := (D SHR 5) AND $0f;
    DT.Year := ((D SHR 9) AND $7f) + 80;
    IF (DT.Month > 12) THEN Dec(DT.Month,12);
    IF (DT.Year > 99) THEN Dec(DT.Year,100);
    DispDate := ZeroPad(IntToStr(DT.Month))+'/'+ZeroPad(IntToStr(DT.Day))+'/'+ZeroPad(IntToStr(DT.Year));
  END;

BEGIN
  IF (ArcItemCount = 0) THEN
  BEGIN
    NL;
    Print('^8No files found inside archive.^0');
    Exit;
  END;

  PerPage := 18;
  TopIdx := 1;
  CurIdx := 1;
  Done := FALSE;
  Redraw := TRUE;

  WHILE (NOT Done) AND (NOT HangUp) DO
  BEGIN
    IF Redraw THEN
    BEGIN
      CLS;
      PrintACR('^1Archive Browser: ^2'+StripName(ArcFN));
      PrintACR('^2Up/Down PgUp/PgDn  ^1ENTER^2=View  ^1ESC^2=Exit');
      PrintACR('|01컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴�');
      { Header (absolute columns to keep alignment perfect) }
      ANSIG(1,4); Prt('|08|16'+PadRightStr('',79));
      Prt('|07|16' + PadRightStr('',79));
      ANSIG(1,4);  Prt('|09|16##');
      ANSIG(7,4);  Prt('|09|16Filename');
      ANSIG(20,4); Prt('|09|16Size');
      ANSIG(34,4); Prt('|09|16Date');
      ANSIG(41,4); Prt('|09|16Full Name');

      ANSIG(1,5); Prt('|08|16'+PadRightStr('',79));
      Prt('|01컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴�');

	  
      FOR I := 0 TO PerPage-1 DO
      BEGIN
        Idx := TopIdx + I;
        Row := 5 + I;

        { Choose row color (highlight only for real items) }
        IF (Idx <= ArcItemCount) AND (Idx = CurIdx) THEN
          Line := '|15|17'
        ELSE
          Line := '|08|16';

        { Paint entire row to prevent color bleed into empty lines }
        ANSIG(1,Row);
        Prt(Line + PadRightStr('',79));

        IF (Idx <= ArcItemCount) THEN
        BEGIN
          ANSIG(1,Row);  Prt(Line + PadLeftStr(IntToStr(Idx),3));
          ANSIG(6,Row);  Prt(Line + PadRightStr(DispName(ArcItems[Idx]^.Name),12));
          ANSIG(19,Row); Prt(Line + PadLeftStr(FormatNumber(ArcItems[Idx]^.USize),10));
          ANSIG(30,Row); Prt(Line + PadRightStr(DispDate(ArcItems[Idx]^.Date),10));
          ANSIG(41,Row); Prt(Line + Copy(AllCaps(ArcItems[Idx]^.Name),1,38));
        END;
      END;

      { Ensure subsequent output uses normal colors }
      ANSIG(1,5+PerPage);
      Prt('|08|16');
      Redraw := FALSE;
    END;

    Key := GetKey;

    { Convert ANSI terminal ESC sequences for PgUp/PgDn (and arrows) when present }
    IF (Key = 27) THEN
      Key := ParseAnsiAfterEsc;

{ TP ReadKey-style extended keys: 0 or 224 followed by scan code }
    IF (Key = 0) OR (Key = 224) THEN
      Key := GetKey;

    { Some environments return raw scan codes (72/80/73/81) instead of
      the MSB-shifted Word constants (e.g. F_UP=18432). Normalize. }
    IF (Key > 0) AND (Key < 256) THEN
      CASE Key OF
        71,72,73,75,77,79,80,81,82,83: Key := Key * 256;
      END;


    CASE Key OF
      F_UP: BEGIN
             IF (CurIdx > 1) THEN Dec(CurIdx);
             Redraw := TRUE;
           END;
      F_DOWN: BEGIN
             IF (CurIdx < ArcItemCount) THEN Inc(CurIdx);
             Redraw := TRUE;
           END;
      73*256, F_PGUP: BEGIN
                Redraw := TRUE;
                CurIdx := CurIdx - PerPage;
                IF (CurIdx < 1) THEN CurIdx := 1;
              END;
      81*256, F_PGDN: BEGIN
                Redraw := TRUE;
                CurIdx := CurIdx + PerPage;
                IF (CurIdx > ArcItemCount) THEN CurIdx := ArcItemCount;
              END;
      13: BEGIN
            ExtractAndViewFromArchive(ArcFN,ArcType,ArcItems[CurIdx]^.Name);
            Redraw := TRUE;
          END;
      27: Done := TRUE;
    END;

    IF (CurIdx < TopIdx) THEN
    BEGIN
      TopIdx := CurIdx;
      Redraw := TRUE;
    END
    ELSE IF (CurIdx > TopIdx + (PerPage-1)) THEN
    BEGIN
      TopIdx := CurIdx - (PerPage-1);
      Redraw := TRUE;
    END;
  END;
END;



PROCEDURE ViewInternalArchive(FileName: AStr);
VAR
  LZH_Method: ARRAY [1..5] OF Char;
  F: FILE;
  (*
  DirInfo: SearchRec;
  *)
  Out: OutRec;
  C: Char;
  LZH_H_Length,
  Counter,
  ArcType: Byte;
  RCode,
  FileType,
  Level,
  NumFiles: Integer;
  NumRead: Word;
  TotalUnCompSize,
  TotalCompSize: LongInt;
  Aborted: Boolean;
BEGIN
  FileName := SQOutSp(FileName);
  CollectingList := FALSE;
  ArcItemCount := 0;

  IF (Pos('*',FileName) <> 0) OR (Pos('?',FileName) <> 0) THEN
  BEGIN
    FindFirst(FileName,AnyFile - Directory - VolumeID - Hidden - SysFile,DirInfo);
    IF (DOSError = 0) THEN
      FileName := DirInfo.Name;
  END;

  IF ((Exist(FileName)) AND (NOT Abort) AND (NOT HangUp)) THEN
  BEGIN

    ArcType := ArcTypeByExt(FileName);
    IF (ArcType = 0) THEN ArcType := 1;
    WHILE (General.FileArcInfo[ArcType].Ext <> '') AND
          (General.FileArcInfo[ArcType].Ext <> Copy(FileName,(Length(FileName) - 2),3)) AND
          (ArcType < MaxArcs + 1) DO
      Inc(ArcType);

    IF NOT ((General.FileArcInfo[ArcType].Ext = '') OR (ArcType = 7)) THEN
    BEGIN
      IF (General.FileArcInfo[ArcType].ListLine[1] = '/') AND
         (General.FileArcInfo[ArcType].ListLine[2] IN ['1'..'5']) AND
         (Length(General.FileArcInfo[ArcType].ListLine) = 2) THEN
      BEGIN
        Aborted := FALSE;
        Abort := FALSE;
        Next := FALSE;
        NL;
        PrintACR('^1'+StripName(FileName)+':');
        NL;
        IF (NOT Abort) THEN
        BEGIN
          Assign(F,FileName);
          Reset(F,1);
          C := GetByte(F,Aborted);
          CASE C OF
            #$1a : FileType := 1;
             'P' : BEGIN
                     IF (GetByte(F,Aborted) <> 'K') THEN
                       AbEnd(Aborted);
                     FileType := 2;
                   END;
             'Z' : BEGIN
                     FOR Counter := 0 TO 1 DO
                       IF (GetByte(F,Aborted) <> 'O') THEN
                         AbEnd(Aborted);
                     FileType := 3;
                   END;
             #96 : BEGIN
                     IF (GetByte(F,Aborted) <> #234) THEN
                       AbEnd(Aborted);
                     FileType := 5;
                   END;
          ELSE
          BEGIN
            LZH_H_Length := Ord(C);
            C := GetByte(F,Aborted);
            FOR Counter := 1 TO 5 DO
              LZH_Method[Counter] := GetByte(F,Aborted);
            IF ((LZH_Method[1] = '-') AND (LZH_Method[2] = 'l') AND (LZH_Method[3] = 'h')) THEN
              FileType := 4
            ELSE
              AbEnd(Aborted);
          END;
        END;
        Reset(F,1);
        Level := 0;
        NumFiles := 0;
        TotalCompSize := 0;
        TotalUnCompSize := 0;

        { Collect listing for interactive browser }
        FreeArcItems;
        CollectingList := TRUE;
        CASE FileType OF
          1 : ARC_Proc(F,Out,Level,NumFiles,TotalCompSize,TotalUnCompSize,Aborted);
          2 : ZIP_Proc(F,Out,Level,NumFiles,TotalCompSize,TotalUnCompSize,Aborted);
          3 : ZOO_Proc(F,Out,Level,NumFiles,TotalCompSize,TotalUnCompSize,Aborted);
          4 : LZH_Proc(F,Out,Level,NumFiles,TotalCompSize,TotalUnCompSize,Aborted);
          5 : ARJ_Proc(F,Out,Level,NumFiles,TotalCompSize,TotalUnCompSize,Aborted);
        END;
        CollectingList := FALSE;
        Close(F);

        { Browse and view files inside the archive }
        BrowseArchiveUI(FileName,ArcType);
        FreeArcItems;
END;
    END
    ELSE
    BEGIN
      NL;
      Prompt('^1Archive '+FileName+':  ^2Please wait....');
      ShellDOS(FALSE,FunctionalMCI(General.FileArcInfo[ArcType].ListLine,FileName,'')+' >shell.$$$',RCode);
      BackErase(15);
      PFL('SHELL.$$$');
      Kill('SHELL.$$$');
    END;
  END;
  END;
END;

PROCEDURE ViewDirInternalArchive;
VAR
  FileName: Str12;
  DirFileRecNum: Integer;
  Found,
  LastArc,
  LastGif: Boolean;
BEGIN
  {
  NL;
  Print('^9Enter the name of the archive(s) you would like to view:');
  }
  lRGLngStr(25,FALSE);
  FileName := '';
  { Print(FString.lGFNLine1); }
  lRGLngStr(28,FALSE);
  { Prt(FString.GFNLine2); }
  lRGLngStr(29,FALSE);
  GetFileName(FileName);
  LastArc := FALSE;
  LastGif := FALSE;
  AllowContinue := TRUE;
  Found := FALSE;
  Abort := FALSE;
  Next := FALSE;
  RecNo(FileInfo,FileName,DirFileRecNum);
  IF (BadDownloadPath) THEN
    Exit;
  WHILE (DirFileRecNum <> -1) AND (NOT Abort) AND (NOT HangUp) DO
  BEGIN
    Seek(FileInfoFile,DirFileRecNum);
    Read(FileInfoFile,FileInfo);
    IF IsGIFExt(FileInfo.FileName) THEN
    BEGIN
      LastArc := FALSE;
      IF (NOT LastGif) THEN
      BEGIN
        LastGif := TRUE;
        NL;
        PrintACR('^1Filename.Ext^2:^1Resolution ^2:^1Num Colors^2:^1Signature');
        PrintACR('^2============:===========:==========:===============');
      END;
      IF Exist(MemFileArea.DLPath+FileInfo.FileName) THEN
      BEGIN
        PrintACR(GetGIFSpecs(MemFileArea.DLPath+SQOutSp(FileInfo.FileName),FileInfo.Description,1));
        Found := TRUE;
      END
      ELSE
      BEGIN
        PrintACR(GetGIFSpecs(MemFileArea.ULPath+SQOutSp(FileInfo.FileName),FileInfo.Description,1));
        Found := TRUE;
      END;
    END
    ELSE IF ValidIntArcType(FileInfo.FileName) THEN
    BEGIN
      LastGif := FALSE;
      IF (NOT LastArc) THEN
        LastArc := TRUE;
      IF Exist(MemFileArea.DLPath+FileInfo.FileName) THEN
      BEGIN
        ViewInternalArchive(MemFileArea.DLPath+FileInfo.FileName);
        Found := TRUE;
      END
      ELSE
      BEGIN
        ViewInternalArchive(MemFileArea.ULPath+FileInfo.FileName);
        Found := TRUE;
      END;
    END;
    WKey;
    NRecNo(FileInfo,DirFileRecNum);
  END;
  Close(FileInfoFile);
  Close(ExtInfoFile);
  AllowContinue := FALSE;
  IF (NOT Found) THEN
  BEGIN
    NL;
    Print('File not found.');
  END;
  LastError := IOResult;
END;

END.
