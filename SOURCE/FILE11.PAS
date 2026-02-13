{$A+,B-,D+,E-,F+,I-,L+,N-,O+,R-,S+,V-}

UNIT File11;

INTERFACE

USES
  Common, Crt;

TYPE
  FileRecType = RECORD
    FArrayFileArea,
    FArrayDirFileRecNum: Integer;
  END;

  FileArrayType = ARRAY [0..99] OF FileRecType;

VAR
  FArray: FileArrayType;

FUNCTION CanSee(CONST FileInfo: FileInfoRecordType): Boolean;
FUNCTION GetFileStats(FileInfo: FileInfoRecordType): AStr;
PROCEDURE InitFArray(VAR F: FileArrayType);
PROCEDURE DisplayFileAreaHeader;
PROCEDURE lDisplay_File(FileInfo: FileInfoRecordType; FArrayRecNum: Byte; SearchString: Str20;
                        NormalPause: Boolean);
PROCEDURE SearchFileSpec;
PROCEDURE ListFileSpec(FName: Str12);
PROCEDURE SearchFileDescriptions;
PROCEDURE GlobalNewFileScan(VAR FArrayRecNum: Byte);
PROCEDURE NewFilesScanSearchType(CONST MenuOption: Str50); {LeeW: FN menu cmd >> calls newfilescan}
PROCEDURE FileAreaChange(VAR Done: Boolean; CONST MenuOption: Str50);
PROCEDURE CreateTempDir;

IMPLEMENTATION

USES
  DOS,
  ArcView,
  Common5,
  File0,
  File1,
  File6,
  File8,
  File10,
  Menus,
  TimeFunc;

VAR
  { Lightbar support flags for NewScan (F+N) }
  LB_NewScanMode: Boolean;
  LB_AdvanceNextArea: Boolean;
  LB_QuitNewScan: Boolean;



{ Returns the exact batch-key used by File6.CheckBatchDL / RemoveBatchDLByKey }
FUNCTION BatchKeyForFI(CONST FI: FileInfoRecordType): Str52;
BEGIN
  IF (Common.Exist(MemFileArea.DLPath + FI.FileName)) THEN
    BatchKeyForFI := Common.SQOutSp(MemFileArea.DLPath + FI.FileName)
  ELSE
    BatchKeyForFI := Common.SQOutSp(MemFileArea.ULPath + FI.FileName);
END;

PROCEDURE LoadVerbArray11(F: FileInfoRecordType; VAR ExtArray: ExtendedDescriptionArray;
  VAR NumExtDesc: Byte);
VAR
  VerbStr: AStr;
  TotLoad: Integer;
  VFO: Boolean;
BEGIN
  FillChar(ExtArray,SizeOf(ExtArray),0);
  NumExtDesc := 1;
  VFO := (FileRec(ExtInfoFile).Mode <> FMClosed);
  IF (NOT VFO) THEN
    Reset(ExtInfoFile,1);
  IF (IOResult = 0) THEN
  BEGIN
    TotLoad := 0;
    Seek(ExtInfoFile,(F.VPointer - 1));
    REPEAT
      BlockRead(ExtInfoFile,VerbStr[0],1);
      BlockRead(ExtInfoFile,VerbStr[1],Ord(VerbStr[0]));
      Inc(TotLoad,(Length(VerbStr) + 1));
      ExtArray[NumExtDesc] := VerbStr;
      Inc(NumExtDesc);
    UNTIL (TotLoad >= F.VTextSize);
    IF (NOT VFO) THEN
      Close(ExtInfoFile);
  END;
  Dec(NumExtDesc);
  LastError := IOResult;
END;



{ Local wrapper - avoids missing PrintACR in mismatched TPUs }
PROCEDURE PrintACR(CONST S: AStr);
BEGIN
  Print(S);
END;

TYPE
  DownLoadArrayType = ARRAY [0..99] OF Integer;

VAR
  DLArray: DownloadArrayType;
  Lines,
  FileRedisplayLines: Byte;

PROCEDURE InitFArray(VAR F: FileArrayType);
VAR
  Counter: Byte;
BEGIN
  FOR Counter := 0 TO 99 DO
    WITH F[Counter] DO
    BEGIN
      FArrayFileArea := -1;
      FArrayDirFileRecNum := -1;
    END;
END;

FUNCTION GetDlArray(VAR DLArray: DownLoadArrayType; CmdLen: Byte): Boolean;
VAR
  s,
  s1,
  s2: Str160;
  Counter,
  Counter1,
  Counter2,
  Counter3: Byte;
  Ok: Boolean;
BEGIN
  Ok := TRUE;
  FOR Counter := 1 TO (((LennMCI(MemMenu.MenuPrompt) + CmdLen) + 1)) DO
    BackSpace;
  FOR Counter := 0 TO 99 DO
    DLArray[Counter] := -1;
  Prt('Enter file number or range (##,##-##): ');
  s := '';
  InputMain(s,20,[NoLineFeed]);
  IF (SqOutSp(S) = '') THEN
    OK := FALSE
  ELSE
  BEGIN
    FOR Counter := 1 TO Length(S) DO
      IF (NOT (S[Counter] IN ['0'..'9','-'])) THEN
        Ok := FALSE;
    IF (S = '-') OR (S[1] = '-') OR (S[Length(s)] = '-') THEN
      OK := FALSE;
    IF (Ok) THEN
    BEGIN
      NL;
      s1 := '';
      s2 := '';
      Counter1 := 0;
      FOR Counter := 1 TO Length(s) DO
      BEGIN
        IF s[Counter] IN ['0'..'9'] THEN
          s1 := s1 + s[Counter]
        ELSE
        BEGIN
          IF (s[Counter] = '-') THEN
          BEGIN
            s2 := '';
            FOR Counter2 := (Counter + 1) TO Length(s) DO
            BEGIN
              IF (s[counter2] IN ['0'..'9']) THEN
                s2 := s2 + s[counter2]
              ELSE
              BEGIN
                IF (s1 <> '') AND (StrToInt(s1) >= 0) AND (StrToInt(s1) <= 99) AND
                   (S2 <> '') AND (StrToInt(s2) >= 0) AND (StrToInt(s2) <= 99) THEN
                  FOR Counter3 := StrToInt(s1) TO StrToInt(s2) DO
                  BEGIN
                    DLArray[Counter1] := Counter3;
                    Inc(Counter1);
                  END;
                s1 := '';
                Counter := Counter + Length(s2);
                s2 := '';
                Counter2 := Length(s);
              END;
            END;
            Counter := Counter + Length(s2);
          END
          ELSE IF (StrToInt(s1) >= 0) AND (StrToInt(s1) <= 99) THEN
          BEGIN
            DLArray[Counter1] := StrToInt(s1);
            Inc(Counter1);
            s1 := '';
            s2 := '';
          END;
        END;
      END;
      IF (Length(s1) <> 0) AND (StrToInt(s1) >= 0) AND (StrToInt(s1) <= 99) THEN
        DLArray[Counter1] := StrToInt(s1);
      IF (s1 <> '') AND (StrToInt(s1) >= 0) AND (StrToInt(s1) <= 99) AND
         (S2 <> '') AND (StrToInt(s2) >= 0) AND (StrToInt(s2) <= 99) THEN
        FOR Counter3 := StrToInt(s1) TO StrToInt(s2) DO
        BEGIN
          DLArray[Counter1] := Counter3;
          Inc(Counter1)
        END;
    END;
  END;
  IF (NOT OK) THEN
  BEGIN
    FOR Counter := 1 TO 20 DO
      OutKey(' ');
    UserColor(0);
    FOR Counter := 1 TO (LennMCI(MemMenu.MenuPrompt) + 21) DO
      BackSpace;
  END;

  GetDLArray := OK;
END;

PROCEDURE Pause_Files;
VAR
  TransferFlags: TransferFlagSet;
  CmdStr,
  NewMenuCmd: AStr;
  SaveLastDirFileName: Str12;
  Cmd: Char;
  SaveMenu,
  Counter,
  CmdToExec: Byte;
  Counter1,
  SaveFileArea,
  SaveLastDirFileRecNum: Integer;
  Done,
  CmdNotHid,
  CmdExists,
  FO: Boolean;
BEGIN
  LIL := 0;
  IF (Lines < PageLength) OR (HangUp) THEN
    Exit;
  Lines := 0;
  FileRedisplayLines := 0;
  FileAreaNameDisplayed := FALSE;

  SaveMenu := CurMenu;
  CurMenu := General.FileListingMenu;
  IF (NOT NewMenuToLoad) THEN
    LoadMenuPW;
  AutoExecCmd('FIRSTCMD');
  REPEAT
    MainMenuHandle(CmdStr);
    NewMenuCmd := '';
    CmdToExec := 0;
    TFilePrompt := 0;
    Done := FALSE;
    REPEAT
      FCmd(CmdStr,CmdToExec,CmdExists,CmdNotHid);
      IF (CmdToExec <> 0) AND (MemCmd^[CmdToExec].CmdKeys <> '-^') AND
         (MemCmd^[CmdToExec].CmdKeys <> '-/') AND (MemCmd^[CmdToExec].CmdKeys <> '-\') THEN
      BEGIN
        IF (CmdStr <> '') AND (CmdStr <> 'ENTER') AND (MemCmd^[CmdToExec].CmdKeys <> 'L5') AND
           (MemCmd^[CmdToExec].CmdKeys <> 'L6') AND (MemCmd^[CmdToExec].CmdKeys <> 'L7') AND
           (MemCmd^[CmdToExec].CmdKeys <> 'L8') THEN
          NL;
        DoMenuCommand(Done,
                      MemCmd^[CmdToExec].CmdKeys,
                      MemCmd^[CmdToExec].Options,
                      NewMenuCmd,
                      MemCmd^[CmdToExec].NodeActivityDesc);
      END;
    UNTIL (CmdToExec = 0) OR (Done) OR (HangUp);
    Abort := FALSE;
    Next := FALSE;
    CASE TFilePrompt OF
      1 : ;
      2 : BEGIN
            Print('%LFListing aborted.');
            Abort := TRUE;
          END;
      3 : BEGIN
            Print('%LFFile area skipped.');
            Next  := TRUE;
          END;
      4 : BEGIN
            Print('%LF^1'+MemFileArea.AreaName+'^1 '+AOnOff(NewScanFileArea,'will NOT','WILL')+
                  ' be scanned.');
            LoadNewScanFile(NewScanFileArea);
            NewScanFileArea := (NOT NewScanFileArea);
            SaveNewScanFile(NewScanFileArea);
          END;
      5 : BEGIN
            IF GetDLArray(DLArray,Length(CmdStr)) THEN
              IF (DLInTime) THEN
                IF (NOT BatchDLQueuedFiles([])) THEN
                BEGIN
                  Counter := 0;
                  WHILE (Counter <= 99) AND (NOT Abort) AND (NOT HangUp) DO
                  BEGIN
                    IF (DLArray[Counter] <> -1) THEN
                      IF (FArray[DLArray[Counter]].FArrayDirFileRecNum = -1) THEN
                        Print('%LF^8Invalid file number selected: "^9'+IntToStr(DLArray[Counter])+'^8".')
                      ELSE
                      BEGIN
                        SaveLastDirFileRecNum := LastDIRRecNum;
                        SaveLastDirFileName := LastDIRFileName;
                        FO := (FileRec(FileInfoFile).Mode <> FMClosed);
                        IF (FO) THEN
                        BEGIN
                          Close(FileInfoFile);
                          Close(ExtInfoFile);
                        END;
                        SaveFileArea := FileArea;
                        FileArea := FArray[DLArray[Counter]].FArrayFileArea;
                        InitFileArea(FileArea);
                        Seek(FileInfoFile,FArray[DLArray[Counter]].FArrayDirFileRecNum);
                        Read(FileInfoFile,FileInfo);
                        TransferFlags := [IsCheckRatio,lIsAddDLBatch];
                        DLX(FileInfo,FArray[DLArray[Counter]].FArrayDirFileRecNum,TransferFlags);
                        IF (IsKeyboardAbort IN TransferFlags) THEN
                          Abort := TRUE;
                        Close(FileInfoFile);
                        Close(ExtInfoFile);
                        FileArea := SaveFileArea;
                        IF (FO) THEN
                          InitFileArea(FileArea);
                        LastDIRRecNum := SaveLastDirFileRecNum;
                        LastDIRFileName := SaveLastDirFileName;
                      END;
                    Inc(Counter);
                  END;
                  IF (Abort) THEN
                    Abort := FALSE;
                  NL;
                END;
          END;
      6 : BEGIN
            IF GetDLArray(DLArray,Length(CmdStr)) THEN
              IF (DLInTime) THEN
              BEGIN
                Counter := 0;
                WHILE (Counter <= 99) AND (NOT Abort) AND (NOT HangUp) DO
                BEGIN
                  IF (DLArray[Counter] <> -1) THEN
                    IF (FArray[DLArray[Counter]].FArrayDirFileRecNum = -1) THEN
                      Print('%LF^8Invalid file number selected: "^9'+IntToStr(DLArray[Counter])+'^8".')
                    ELSE
                    BEGIN
                      SaveLastDirFileRecNum := LastDIRRecNum;
                      SaveLastDirFileName := LastDIRFileName;
                      FO := (FileRec(FileInfoFile).Mode <> FMClosed);
                      IF (FO) THEN
                      BEGIN
                        Close(FileInfoFile);
                        Close(ExtInfoFile);
                      END;
                      SaveFileArea := FileArea;
                      FileArea := FArray[DLArray[Counter]].FArrayFileArea;
                      InitFileArea(FileArea);
                      Seek(FileInfoFile,FArray[DLArray[Counter]].FArrayDirFileRecNum);
                      Read(FileInfoFile,FileInfo);
                      TransferFlags := [IsCheckRatio,lIsAddDLBatch];
                      DLX(FileInfo,FArray[DLArray[Counter]].FArrayDirFileRecNum,TransferFlags);
                      IF (IsKeyboardAbort IN TransferFlags) THEN
                        Abort := TRUE;
                      Close(FileInfoFile);
                      Close(ExtInfoFile);
                      FileArea := SaveFileArea;
                      IF (FO) THEN
                        InitFileArea(FileArea);
                      LastDIRRecNum := SaveLastDirFileRecNum;
                      LastDIRFileName := SaveLastDirFileName;
                    END;
                  Inc(Counter);
                END;
                IF (Abort) THEN
                  Abort := FALSE;
                NL;
              END;
          END;
      7 : BEGIN
            IF GetDLArray(DLArray,Length(CmdStr)) THEN
            BEGIN
              Counter := 0;
              WHILE (Counter <= 99) AND (NOT Abort) AND (NOT HangUp) DO
              BEGIN
                IF (DLArray[Counter] <> -1) THEN
                  IF (FArray[DLArray[Counter]].FArrayDirFileRecNum = -1) THEN
                    Print('%LF^8Invalid file number selected: "^9'+IntToStr(DLArray[Counter])+'^8".')
                  ELSE
                  BEGIN
                    SaveLastDirFileRecNum := LastDIRRecNum;
                    SaveLastDirFileName := LastDIRFileName;
                    FO := (FileRec(FileInfoFile).Mode <> FMClosed);
                    IF (FO) THEN
                    BEGIN
                      Close(FileInfoFile);
                      Close(ExtInfoFile);
                    END;
                    SaveFileArea := FileArea;
                    FileArea := FArray[DLArray[Counter]].FArrayFileArea;
                    InitFileArea(FileArea);
                    Seek(FileInfoFile,FArray[DLArray[Counter]].FArrayDirFileRecNum);
                    Read(FileInfoFile,FileInfo);
                    IF (NOT ValidIntArcType(FileInfo.FileName)) THEN
                      Print('%LF'+Common.SQOutSp(FileInfo.FileName)+' is not a valid archive type or not supported.')
                    ELSE
                    BEGIN
                      IF Common.Exist(MemFileArea.DLPath+FileInfo.FileName) THEN
                        ViewInternalArchive(MemFileArea.DLPath+Common.SQOutSp(FileInfo.FileName))
                      ELSE IF Common.Exist(MemFileArea.ULPath+FileInfo.FileName) THEN
                        ViewInternalArchive(MemFileArea.ULPath+Common.SQOutSp(FileInfo.FileName));
                    END;
                    Close(FileInfoFile);
                    Close(ExtInfoFile);
                    FileArea := SaveFileArea;
                    IF (FO) THEN
                      InitFileArea(FileArea);
                    LastDIRRecNum := SaveLastDirFileRecNum;
                    LastDIRFileName := SaveLastDirFileName;
                  END;
                Inc(Counter);
              END;
              IF (Abort) THEN
                Abort := FALSE;
              NL;
            END;
          END;
      8 : IF (NOT FileSysop) THEN
          BEGIN
            NL;
            Print('%LFYou do not have the required access level for this option.');
            NL;
          END
          ELSE
          BEGIN
            IF GetDLArray(DLArray,Length(CmdStr)) THEN
            BEGIN
              Counter := 0;
              WHILE (Counter <= 99) AND (NOT Abort) AND (NOT HangUp) DO
              BEGIN
                IF (DLArray[Counter] <> -1) THEN
                  IF (FArray[DLArray[Counter]].FArrayDirFileRecNum = -1) THEN
                    Print('%LF^8Invalid file number selected: "^9'+IntToStr(DLArray[Counter])+'^8".')
                  ELSE
                  BEGIN
                    SaveLastDirFileRecNum := LastDIRRecNum;
                    SaveLastDirFileName := LastDIRFileName;
                    FO := (FileRec(FileInfoFile).Mode <> FMClosed);
                    IF (FO) THEN
                    BEGIN
                      Close(FileInfoFile);
                      Close(ExtInfoFile);
                    END;
                    SaveFileArea := FileArea;
                    FileArea := FArray[DLArray[Counter]].FArrayFileArea;
                    InitFileArea(FileArea);
                    Seek(FileInfoFile,FArray[DLArray[Counter]].FArrayDirFileRecNum);
                    Read(FileInfoFile,FileInfo);
                    EditFile(FArray[DLArray[Counter]].FArrayDirFileRecNum,Cmd,FALSE,FALSE);
                    IF (Cmd = 'Q') THEN
                      Abort := TRUE
                    ELSE IF (Cmd = 'P') THEN
                    BEGIN
                      Counter1 := Counter;
                      IF (Counter1 > 0) THEN
                      BEGIN
                        IF (DLArray[Counter1] <> -1) THEN
                          IF (FArray[DLArray[Counter1]].FArrayDirFileRecNum <> -1) THEN
                            Counter := (Counter1 - 1);
                        Dec(Counter1);
                      END;
                      Dec(Counter);
                    END;
                    Close(FileInfoFile);
                    Close(ExtInfoFile);
                    FileArea := SaveFileArea;
                    IF (FO) THEN
                      InitFileArea(FileArea);
                    LastDIRRecNum := SaveLastDirFileRecNum;
                    LastDIRFileName := SaveLastDirFileName;
                  END;
                Inc(Counter);
              END;
              IF (Abort) THEN
                Abort := FALSE;
              IF (Next) THEN
                Next := FALSE;
              IF (Cmd <> 'Q') THEN
                NL;
            END;
          END;
    END;
  UNTIL (TFilePrompt = 1) OR (Abort) OR (Next) OR (HangUp);
  IF (TFilePrompt = 1) AND (NOT Abort) AND (NOT Next) AND (NOT HangUp) THEN
    NL;
  CurMenu := SaveMenu;
  NewMenuToLoad := TRUE;
END;

FUNCTION CanSee(CONST FileInfo: FileInfoRecordType): Boolean;
BEGIN
  CanSee := (NOT (FINotVal IN FileInfo.FIFlags)) OR (UserNum = FileInfo.OwnerNum) OR (AACS(General.SeeUnVal));
END;

PROCEDURE Output_File_Stuff(CONST s: AStr);
BEGIN
  IF (TextRec(NewFilesF).Mode = FMOutPut)THEN
  BEGIN
    WriteLn(NewFilesF,StripColor(s));
    Lines := 0;
  END
  ELSE
    PrintACR(s+'^0');
END;

PROCEDURE DisplayFileAreaHeader;
BEGIN
  IF (FileAreaNameDisplayed) THEN
    Exit;
  Lil := 0;
  Lines := 0;
  FileRedisplayLines := 0;

  IF (NOT General.FileCreditRatio) THEN
    lRGLngStr(63,FALSE)
  ELSE
    lRGLngStr(64,FALSE);
  Inc(Lines,LIL);
  Inc(FileRedisplayLines,LIL);

  FileAreaNameDisplayed := TRUE;
END;

FUNCTION GetFileStats(FileInfo: FileInfoRecordType): AStr;
BEGIN
  IF (FIIsRequest IN FileInfo.FIFlags) THEN
    GetFileStats := '   Offline'
  ELSE IF (FIResumeLater IN FileInfo.FIFlags) THEN
    GetFileStats := '   ResLatr'
  ELSE IF (FINotVal IN FileInfo.FIFlags) THEN
    GetFileStats := '   Unvalid'
  ELSE IF (NOT General.FileCreditRatio) THEN
    GetFileStats := ''+PadRightStr(ConvertBytes(FileInfo.FileSize,TRUE),10)
  ELSE
    GetFileStats := ''+PadRightInt(FileInfo.FilePoints,3)+' '+PadRightStr(ConvertKB(FileInfo.FileSize DIV 1024,TRUE),6);
END;

PROCEDURE lDisplay_File(FileInfo: FileInfoRecordType; FArrayRecNum: Byte; SearchString: Str20;
                        NormalPause: Boolean);
VAR
  TempStr,
  TempStr1,
  TempStr2: AStr;
  LineNum,
  NumExtDesc: Byte;
  BK: Str52;

  FUNCTION SubStone(SrcStr,OldStr,NewStr: AStr; IsCaps: Boolean): AStr;
  VAR
    StrPos: Byte;
  BEGIN
    IF (OldStr <> '') THEN
    BEGIN
      IF (IsCaps) THEN
        NewStr := AllCaps(NewStr);
      StrPos := Pos(AllCaps(OldStr),AllCaps(SrcStr));
      IF (StrPos > 0)  THEN
      BEGIN
        Insert(NewStr,SrcStr,(StrPos + Length(OldStr)));
        Delete(SrcStr,StrPos,Length(OldStr));
      END;
    END;
    SubStone := SrcStr;
  END;

BEGIN
  TempStr := AOnOff(DayNum(PD2Date(FileInfo.FileDate)) >= DayNum(PD2Date(NewFileDate)),'*',' ')+
                    ''+PadRightInt(FArrayRecNum,2);

  TempStr1 := FileInfo.FileName;
  IF (SearchString <> '') THEN
    TempStr1 := SubStone(TempStr1,SearchString,''+AllCaps(SearchString)+'',TRUE);
  TempStr := TempStr + ' '+TempStr1+' '+GetFileStats(FileInfo)+'';

  TempStr2 := TempStr;

  TempStr1 := FileInfo.Description;
  IF (SearchString <> '') THEN
    TempStr1 := SubStone(TempStr1,SearchString,''+AllCaps(SearchString)+'',TRUE);
  IF (LennMCI(TempStr1) > 50) THEN
    TempStr1 := Copy(TempStr1,1,Length(TempStr1) - (LennMCI(TempStr1) - 50));
  TempStr := TempStr + ' '+TempStr1;


  IF (NOT NormalPause) AND (NOT Next) AND (NOT Abort) AND (NOT HangUp) THEN
    DisplayFileAreaHeader;

  Inc(Lines);

  IF (NOT Next) AND (NOT Abort) AND (NOT HangUp) THEN
    Output_File_Stuff(TempStr);
  IF (NOT NormalPause) AND (NOT Next) AND (NOT Abort) AND (NOT HangUp) THEN
    Pause_Files;

  IF (FileInfo.VPointer <> -1) THEN
  BEGIN
    LoadVerbArray11(FileInfo,ExtendedArray,NumExtDesc);
    LineNum := 1;
    WHILE (LineNum <= NumExtDesc) AND (NOT Next) AND (NOT Abort) AND (NOT HangUp) DO
    BEGIN
      TempStr1 := ExtendedArray[LineNum];
      IF (SearchString <> '') THEN
        TempStr1 := SubStone(TempStr1,SearchString,''+AllCaps(SearchString)+'',TRUE);

      IF (Lines = FileRedisplayLines) THEN
        TempStr := TempStr2 + ' '+TempStr1+''
      ELSE
        TempStr := PadLeftStr('',28)+''+TempStr1+'';

      IF (NOT NormalPause) AND (NOT Next) AND (NOT Abort) AND (NOT HangUp) THEN
        DisplayFileAreaHeader;

      Inc(Lines);

      IF (NOT Next) AND (NOT Abort) AND (NOT HangUp) THEN
        Output_File_Stuff(TempStr);

      IF (NOT NormalPause) AND (NOT Next) AND (NOT Abort) AND (NOT HangUp) THEN
        Pause_Files;
      Inc(LineNum);
    END;
  END;

  TempStr := '';
  IF (FAShowName IN MemFileArea.FAFlags) THEN
    IF (Lines = FileRedisplayLines) THEN
      TempStr := TempStr2 + ' Uploaded by '+Caps(FileInfo.OwnerName)
    ELSE
      TempStr := TempStr + PadLeftStr('',28)+'Uploaded by '+Caps(FileInfo.OwnerName);

  IF (FAShowDate IN MemFileArea.FAFlags) THEN
  BEGIN
    IF (TempStr = '') THEN
      IF (Lines = FileRedisplayLines) THEN
        TempStr := TempStr2 + ' Uploaded'
      ELSE
        TempStr := PadLeftStr('',28)+'Uploaded';
    TempStr := TempStr +' on '+PD2Date(FileInfo.FileDate);
    IF (Length(TempStr) > 78) THEN
      TempStr := Copy(TempStr,1,78);
  END;

  IF (FAShowName IN MemFileArea.FAFlags) OR (FAShowDate IN MemFileArea.FAFlags) THEN
  BEGIN

    IF (NOT NormalPause) AND (NOT Next) AND (NOT Abort) AND (NOT HangUp) THEN
      DisplayFileAreaHeader;

    Inc(Lines);

    IF (NOT Next) AND (NOT Abort) AND (NOT HangUp) THEN
      Output_File_Stuff(TempStr);
    IF (NOT NormalPause) AND (NOT Next) AND (NOT Abort) AND (NOT HangUp) THEN
      Pause_Files;
  END;

  IF (FIResumeLater IN FileInfo.FIFlags) AND (FileInfo.OwnerNum = UserNum) AND NOT (TextRec(NewFilesF).Mode = FMOutPut) THEN
  BEGIN
    IF (Lines = FileRedisplayLines) THEN
      TempStr := TempStr2 + ' ^8>^8'+'>> ^1'+'You ^1'+'MUST RESUME^1'+' this file to receive credit'
    ELSE
      TempStr := PadLeftStr('',28)+'^8>^8'+'>> ^1'+'You ^1'+'MUST RESUME^1'+' this file to receive credit';

    IF (NOT NormalPause) AND (NOT Next) AND (NOT Abort) AND (NOT HangUp) THEN
      DisplayFileAreaHeader;

    Inc(Lines);

    IF (NOT Next) AND (NOT Abort) AND (NOT HangUp) THEN
      Output_File_Stuff(TempStr);
    IF (NOT NormalPause) AND (NOT Next) AND (NOT Abort) AND (NOT HangUp) THEN
      Pause_Files;
  END;
END;

PROCEDURE SearchFileAreaSpec(FArea: Integer; FName: Str12; VAR FArrayRecNum: Byte);
VAR
  DirFileRecNum: Integer;
  Found: Boolean;
BEGIN
  IF (FileArea <> FArea) THEN
    ChangeFileArea(FArea);
  IF (FileArea = FArea) THEN
  BEGIN
    RecNo(FileInfo,FName,DirFileRecNum);
    IF (BadDownloadPath) THEN
      Exit;
    Found := FALSE;
    LIL := 0;
    CLS;
    Prompt('^0Scanning ^1'+MemFileArea.AreaName+' #'+IntToStr(CompFileArea(FArea,0))+'^0 ...');
    WHILE (DirFileRecNum <> -1) AND (NOT Abort) AND (NOT HangUp) DO
    BEGIN
      Seek(FileInfoFile,DirFileRecNum);
      Read(FileInfoFile,FileInfo);
      IF (CanSee(FileInfo)) THEN
      BEGIN

        WITH FArray[FArrayRecNum] DO
        BEGIN
          FArrayFileArea := FileArea;
          FArrayDirFileRecNum := DirFileRecNum;
        END;

        DisplayFileAreaHeader;
        lDisplay_File(FileInfo,FArrayRecNum,'',FALSE);

        Inc(FArrayRecNum);
        IF (FArrayRecNum = 100) THEN
          FArrayRecNum := 0;

        Found := TRUE;
      END;
      NRecNo(FileInfo,DirFileRecNum);
      IF (DirFileRecNum = -1) AND (Found) AND (Lines > FileRedisplayLines) AND (NOT Abort) AND (NOT HangUp) THEN
      BEGIN
        Lines := PageLength;
        Pause_Files;
      END;
    END;
    IF (NOT Found) THEN
    BEGIN
      LIL := 0;
      BackErase(15 + LennMCI(MemFileArea.AreaName) + Length(IntToStr(CompFileArea(FArea,0))));
    END;
    Close(FileInfoFile);
    Close(ExtInfoFile);
  END;
END;

PROCEDURE SearchFileSpec;
VAR
  FName: Str12;
  FArrayRecNum: Byte;
  FArea,
  SaveFileArea: Integer;
  SaveConfSystem: Boolean;
BEGIN
  NL;
  lRGLngStr(20,FALSE); { Print(FString.SearchLine); }
  lRGLngStr(28,FALSE); { Print(FString.lGFNLine1); }
  lRGLngStr(29,FALSE); { Prt(FString.GFNLine2); }
  FName := '';
  GetFileName(FName);
  IF (FName = '') THEN
  BEGIN
    Print('%LFAborted.');
    Exit;
  END;
  SaveFileArea := FileArea;
  Abort := FALSE;
  Next := FALSE;
  InitFArray(FArray);
  FArrayRecNum := 0;
  SaveConfSystem := ConfSystem;
  ConfSystem := NOT PYNQ('%LFSearch all conferences? ',0,TRUE);
  IF (ConfSystem <> SaveConfSystem) THEN
    NewCompTables;
  FArea := 1;
  WHILE (FArea >= 1) AND (FArea <= NumFileAreas) AND (NOT Abort) AND (NOT HangUp) DO
  BEGIN
    SearchFileAreaSpec(FArea,FName,FArrayRecNum);
    WKey;
    Inc(FArea);
  END;
  IF (ConfSystem <> SaveConfSystem) THEN
  BEGIN
    ConfSystem := SaveConfSystem;
    NewCompTables;
  END;
  FileArea := SaveFileArea;
  LoadFileArea(FileArea);
END;

PROCEDURE ListFileSpec(FName: Str12);
VAR
  FArrayRecNum: Byte;

  PROCEDURE ListFileSpec_LB(CONST Spec: Str12);
  CONST
    MAX_LB_FILES = 6000;
  TYPE
    TRecArr = ARRAY [1..MAX_LB_FILES] OF Integer;
    TYArr   = ARRAY [1..MAX_LB_FILES] OF Integer;
    PRecArr = ^TRecArr;
    PYArr   = ^TYArr;
  VAR
    Recs: PRecArr;
    YPos: PYArr;
    DirFileRecNum: Integer;
    Total: Integer;
    StartIdx: Integer;
    Sel: Integer;
    LastSel: Integer;
    EndIdx: Integer;
    Idx: Integer;
     PageSize: Integer;
    W: Word;
    TransferFlags: TransferFlagSet;
    NeedRedraw: Boolean;
    SaveTempPause: Boolean;
    SaveFRL: Byte;
    SaveAllowContinue: Boolean;
    StartExt: Integer;
    EndExt: Integer;
    ContFile: Integer;
    PageExtShown: Integer;
    NextContFile: Integer;
    NextStartExt: Integer;
    StackTop: Integer;
    ContStack: ARRAY[0..40] OF Integer;
    ExtStack: ARRAY[0..40] OF Integer;
    FI: FileInfoRecordType;
    BK: Str52;

    WinTop: Integer;
    WinBot: Integer;
    ListTop: Integer;
    ListBot: Integer;
    MaxLines: Integer;
  FUNCTION BatchKeyForFI(CONST FI: FileInfoRecordType): Str52;
BEGIN
  IF Common.Exist(MemFileArea.DLPath+FI.FileName) THEN
    BatchKeyForFI := Common.SQOutSp(MemFileArea.DLPath+FI.FileName)
  ELSE
    BatchKeyForFI := Common.SQOutSp(MemFileArea.ULPath+FI.FileName);
END;

FUNCTION BatchKeyForFI11(CONST FI: FileInfoRecordType): Str52;
BEGIN
  BatchKeyForFI11 := BatchKeyForFI(FI);
END;


PROCEDURE AddBatchDLByKey(CONST FI: FileInfoRecordType; CONST BKey: AStr);
VAR
  BD: BatchDLRecordType;
  Exists: Boolean;
BEGIN
  Exists := FALSE;

  Assign(BatchDLFile, General.DataPath + 'BATCHDL.DAT');
  {$I-} Reset(BatchDLFile); {$I+}
  IF (IOResult <> 0) THEN
  BEGIN
    {$I-} Rewrite(BatchDLFile); {$I+}
  END;
  IF (IOResult <> 0) THEN
    EXIT;

  Seek(BatchDLFile, 0);
  WHILE (NOT EOF(BatchDLFile)) AND (NOT Exists) DO
  BEGIN
    Read(BatchDLFile, BD);
    IF (BD.BDLUserNum = UserNum) AND (BD.BDLFileName = BKey) THEN
      Exists := TRUE;
  END;

  IF NOT Exists THEN
  BEGIN
    FillChar(BD, SizeOf(BD), 0);
    BD.BDLUserNum := UserNum;
    BD.BDLTime := 0;
    BD.BDLFSize := FI.FileSize;
    BD.BDLPoints := FI.FilePoints;
    BD.BDLFileName := BKey;
    Seek(BatchDLFile, FileSize(BatchDLFile));
    Write(BatchDLFile, BD);
  END;

  Close(BatchDLFile);
END;


PROCEDURE RecalcBatchDLStats;
VAR
  R: LongInt;
BEGIN
  { Recalculate batch counters from disk to keep NumBatchDLFiles/size/time/points in sync.
    This prevents the batch remove prompt from showing the wrong range (e.g. 1-3) when
    more files exist in BATCHDL.DAT, and properly detects an empty queue. }
  NumBatchDLFiles := 0;
  BatchDLTime := 0;
  BatchDLSize := 0;
  BatchDLPoints := 0;

  Assign(BatchDLFile,General.DataPath+'BATCHDL.DAT');
  Reset(BatchDLFile);
  IF (IOResult <> 0) THEN
    Exit;

  IF (FileSize(BatchDLFile) > 0) THEN
    FOR R := 0 TO (FileSize(BatchDLFile) - 1) DO
    BEGIN
      Seek(BatchDLFile,R);
      Read(BatchDLFile,BatchDL);
      IF (BatchDL.BDLUserNum = UserNum) THEN
      BEGIN
        Inc(NumBatchDLFiles);
        Inc(BatchDLTime,BatchDL.BDLTime);
        Inc(BatchDLSize,BatchDL.BDLFSize);
        Inc(BatchDLPoints,BatchDL.BDLPoints);
      END;
    END;

  Close(BatchDLFile);
  LastError := IOResult;
END;

PROCEDURE RemoveBatchDLByKey(CONST BK: Str52);
VAR
  R, R1: LongInt;
BEGIN
  { Always resync first in case counters were off. }
  RecalcBatchDLStats;
  IF (NumBatchDLFiles = 0) THEN
    Exit;

  Assign(BatchDLFile,General.DataPath+'BATCHDL.DAT');
  Reset(BatchDLFile);
  IF (IOResult <> 0) THEN
    Exit;

  R := 0;
  WHILE (R < FileSize(BatchDLFile)) DO
  BEGIN
    Seek(BatchDLFile,R);
    Read(BatchDLFile,BatchDL);

    IF (BatchDL.BDLUserNum = UserNum) AND (BatchDL.BDLFileName = BK) THEN
    BEGIN
      { Update counters for this removed record. }
      Dec(NumBatchDLFiles);
      Dec(BatchDLTime,BatchDL.BDLTime);
      Dec(BatchDLSize,BatchDL.BDLFSize);
      Dec(BatchDLPoints,BatchDL.BDLPoints);
      { Shift records down to remove the entry at index R. }
      FOR R1 := R TO (FileSize(BatchDLFile)-2) DO
      BEGIN
        Seek(BatchDLFile,R1+1);
        Read(BatchDLFile,BatchDL);
        Seek(BatchDLFile,R1);
        Write(BatchDLFile,BatchDL);
      END;

      { Remove last (now duplicated) record. }
      Seek(BatchDLFile,FileSize(BatchDLFile)-1);
      Truncate(BatchDLFile);

      { Do NOT increment R here; keep it to catch duplicates that shifted into this slot. }
    END
    ELSE
      Inc(R);
  END;

  Close(BatchDLFile);
  LastError := IOResult;

  { Final authoritative resync from disk for safety. }
  RecalcBatchDLStats;
END;

PROCEDURE DrawName(I: Integer; Hi: Boolean);
VAR
  Y: Integer;
BEGIN
  { Redraw ONLY the filename field on the file's MAIN line.
    IMPORTANT: Do NOT draw on YPos+1, or we will overwrite the next entry
    (and its red blinking NEW marker) when each file is a single-line entry. }
  IF (I < 1) OR (I > Total) THEN
    Exit;
  IF (YPos^[I] < 1) THEN
    Exit;

  Y := YPos^[I]+1;
  IF (Y < ListTop) OR (Y > ListBot) THEN
    Exit;

  Seek(FileInfoFile,Recs^[I]);
  Read(FileInfoFile,FI);

  { filename starts at column 5 }
  ANSIG(5,Y);
  IF (Hi) THEN
    UserColor(7)
  ELSE
    UserColor(1);
  PrintACR(PadRightStr(FI.FileName,12));
  UserColor(1);
END;

FUNCTION FileRecNumStr(N: Integer): AStr;
VAR
  S: AStr;
BEGIN
  S := IntToStr(N);
  IF (N < 10) THEN
    S := ' ' + S;
  FileRecNumStr := S;
END;

PROCEDURE DisplayFileNoPause(VAR FI: FileInfoRecordType; RecNum: Integer);
VAR
  S, S1, S2, NumStr: AStr;
  L, NumExt: Byte;
  Batched: Boolean;
BEGIN
  IF ((RecNum MOD 100) < 10) THEN
    NumStr := ' ' + IntToStr(RecNum MOD 100)
  ELSE
    NumStr := IntToStr(RecNum MOD 100);
  Batched := File6.CheckBatchDL(BatchKeyForFI(FI));
  { first line }
  IF Batched THEN
    S := '^1*^0'
  ELSE
    S := ' ';
  S := S + '' + NumStr + ' ';
  PrintACR(S);

  UserColor(1);
  PrintACR(PadRightStr(FI.FileName,12));
  UserColor(1);

  S := ' ' + GetFileStats(FI) + '';
  S2 := FI.Description;
  IF (LennMCI(S2) > 50) THEN
    S2 := Copy(S2,1,Length(S2) - (LennMCI(S2) - 50));
  S := S + ' ' + S2;

  Inc(Lines);
  PrintACR(S);

  { extended .ext description lines }
  IF (FI.VPointer <> -1) THEN
  BEGIN
    LoadVerbArray11(FI,ExtendedArray,NumExt);
    L := 1;
    WHILE (L <= NumExt) AND (NOT Abort) AND (NOT HangUp) DO
    BEGIN
      S1 := ExtendedArray[L];
      S := PadLeftStr('',28) + '' + S1 + '';
      Inc(Lines);
      PrintACR(S);
      Inc(L);
    END;
  END;
END;

PROCEDURE DisplayFileChunk(VAR FI: FileInfoRecordType; RecNum: Integer;
                           ExtStart: Integer; MaxLines: Integer;
                           VAR UsedLines, NewExt: Integer);
VAR
  S, S1, S2, NumStr: AStr;
  L, NumExt: Byte;
  Batched: Boolean;
BEGIN
  {UsedLines is an counter for the page; do not reset it here - EVER!}
  NewExt := ExtStart;

  { always print the main file line }
  IF ((RecNum MOD 100) < 10) THEN
    NumStr := ' ' + IntToStr(RecNum MOD 100)
  ELSE
    NumStr := IntToStr(RecNum MOD 100);
    Batched := File6.CheckBatchDL(BatchKeyForFI(FI));
    IF Batched THEN
      S := '^1*^0'
    ELSE
      S := AOnOff(DayNum(PD2Date(FI.FileDate)) >= DayNum(PD2Date(NewFileDate)),'*',' ');
    S := S + '' + NumStr + ' ';


  S1 := FI.FileName;
  S := S + '' + S1 + ' ' + GetFileStats(FI) + '';
  S2 := FI.Description;
  IF (LennMCI(S2) > 50) THEN
    S2 := Copy(S2,1,Length(S2) - (LennMCI(S2) - 50));
  S := S + ' ' + S2;

  Inc(Lines);
  Inc(UsedLines);
  PrintACR(S);

  { extended .ext description lines, starting at ExtStart+1 }
  IF (FI.VPointer <> -1) AND (UsedLines < MaxLines) THEN
  BEGIN
    LoadVerbArray11(FI,ExtendedArray,NumExt);
    L := ExtStart + 1;
    WHILE (L <= NumExt) AND (UsedLines < MaxLines) AND (NOT Abort) AND (NOT HangUp) DO
    BEGIN
      S1 := ExtendedArray[L];
      S := PadLeftStr('',28) + '' + S1 + '';
      Inc(Lines);
      Inc(UsedLines);
      PrintACR(S);
      NewExt := L;
      Inc(L);
    END;
  END;
END;

FUNCTION FileHeight(VAR FI: FileInfoRecordType): Integer;
VAR
  N: Byte;
BEGIN
  FileHeight := 1;
  IF (FI.VPointer <> -1) THEN
  BEGIN
    LoadVerbArray11(FI,ExtendedArray,N);
    FileHeight := 1 + N;
  END;
END;

PROCEDURE PrintFull(I: Integer);
VAR
  H: Integer;
BEGIN
  Seek(FileInfoFile,Recs^[I]);
  Read(FileInfoFile,FileInfo);
  H := FileHeight(FileInfo);
  { if it won't fit, caller stops; still use record header Y }
  DisplayFileNoPause(FileInfo,I);
END;


  FUNCTION TwoDigit(N: LongInt): Str2;
  VAR S: String[3];
  BEGIN
    IF (N > 99) THEN
      N := 99;
    S := IntToStr(N);
    IF (Length(S) = 1) THEN
      S := '0' + S;
    TwoDigit := S;
  END;

  FUNCTION FormatHMS(Secs: LongInt): Str8;
  VAR
    H, M, S: LongInt;
  BEGIN
    IF (Secs < 0) THEN
      Secs := 0;
    H := Secs DIV 3600;
    Secs := Secs MOD 3600;
    M := Secs DIV 60;
    S := Secs MOD 60;
    FormatHMS := TwoDigit(H) + ':' + TwoDigit(M) + ':' + TwoDigit(S);
  END;

  PROCEDURE DrawLBFooter;
VAR
  FooterY1, FooterY2, FooterY3: Integer;
BEGIN
   {Uses bottom-of-window coordinates so it follows status-line on/off. }

  FooterY2 := Hi(WindMax);
  FooterY1 := FooterY2 - 1;
  FooterY3 := FooterY2 - 2;

  { Set/reset ANSI attributes safely (no bleed) }
  Prompt(#27'[0m');
  Prompt(#27'[37;40m');

  { Line 1 (new): filebase/batch help }
  ANSIG(1, FooterY3);
  Prompt(#27'[0K');
  lRGLngStr(290,FALSE);
  {Prompt('SPACE=Tag  ENTER=DL  D=Batch DL  Q/ESC=Quit');}
  Prompt(#27'[0K');

  { Line 2 (from MAIL2) }
  ANSIG(1, FooterY1);
  Prompt(#27'[0K');
  lRGLngStr(291,FALSE);
  Prompt(#27'[0K');

  { Line 3 (from MAIL2) }
  ANSIG(1, FooterY2);
  Prompt(#27'[0K');
  lRGLngStr(292,FALSE);
  Prompt(#27'[0K');

  { Restore Renegade normal colors for anything after this }
  { stripped for remote ANSI safety }
  Prompt(Chr(19)+Chr(7));

  { Safety: leave cursor in the list region so any un-positioned output
    cannot bleed into the footer area. }
  ANSIG(1, Hi(WindMin) + 1);
END;


    PROCEDURE DrawPage;
VAR
  UsedLines: Integer;
  NumExt: Byte;
  NewExt: Integer;
  CurExtStart: Integer;
  CurIdx: Integer;
  BK: Str52;
BEGIN
  FileAreaNameDisplayed := FALSE;
  CLS;
  WinTop := Hi(WindMin) + 1;
  WinBot := Hi(WindMax) + 1;
  ListTop := WinTop + 2;
  { IMPORTANT:
    Each entry can draw a second "name" line via DrawName(YPos+1).
    If the last usable list row is too close to the footer, that +1 can
    land on the footer's top line, causing the "random filename in footer"
    garbage.  To prevent that, reserve ONE extra row above the 3-line
    footer.
  }
  ListBot := WinBot - 4;  { footer starts at row 22 (4 lines: 22-25); allow highlight on row 21 }
  MaxLines := (ListBot - ListTop) + 1;
  FillChar(YPos^, SizeOf(TYArr), 0);
  DisplayFileAreaHeader;
  UsedLines := 0;
  Lines := 0;
  SaveFRL := FileRedisplayLines;
  FileRedisplayLines := 255;
  TempPause := FALSE;
  EndIdx := StartIdx;
  EndExt := 0;
  NextContFile := 0;
  NextStartExt := 0;

  IF (ContFile > 0) THEN
  BEGIN
    CurIdx := ContFile;
    CurExtStart := StartExt;
  END
  ELSE
  BEGIN
    CurIdx := StartIdx;
    CurExtStart := 0;
  END;

  WHILE (CurIdx <= Total) AND (UsedLines < MaxLines) DO
  BEGIN
    Seek(FileInfoFile, Recs^[CurIdx]);
    Read(FileInfoFile, FileInfo);
    NumExt := 0;
    IF (FileInfo.VPointer <> -1) THEN
      LoadVerbArray11(FileInfo, ExtendedArray, NumExt);

    YPos^[CurIdx] := (ListTop + UsedLines);
    NewExt := 0;
    DisplayFileChunk(FileInfo, CurIdx, CurExtStart, MaxLines, UsedLines, NewExt);
    EndIdx := CurIdx;

    IF (NumExt > 0) AND (NewExt < NumExt) THEN
    BEGIN
      NextContFile := CurIdx;
      NextStartExt := NewExt;
      Break;
    END;

    Inc(CurIdx);
    CurExtStart := 0;
  END;

  FileRedisplayLines := SaveFRL;
  IF (ContFile > 0) THEN
    PageSize := 1
  ELSE
    PageSize := (EndIdx - StartIdx + 1);
  DrawName(Sel, TRUE);
  LastSel := Sel;
  DrawLBFooter;
  NeedRedraw := FALSE;
END;

  BEGIN
    Abort := FALSE;
    Next := FALSE;
    SaveTempPause := TempPause;
    SaveAllowContinue := AllowContinue;
    AllowContinue := FALSE;
    TempPause := FALSE;
    Total := 0;
    RecNo(FileInfo,Spec,DirFileRecNum);
    IF (BadDownloadPath) THEN
      Exit;
    New(Recs);
    New(YPos);
    FillChar(YPos^, SizeOf(TYArr), 0);
    WHILE (DirFileRecNum <> -1) AND (Total < MAX_LB_FILES) AND (NOT HangUp) DO
    BEGIN
      Seek(FileInfoFile,DirFileRecNum);
      Read(FileInfoFile,FileInfo);
            IF (CanSee(FileInfo)) AND
         ((NOT LB_NewScanMode) OR
          (DayNum(PD2Date(FileInfo.FileDate)) >= DayNum(PD2Date(NewFileDate))) OR
          (FINotVal IN FileInfo.FIFlags)) THEN
      BEGIN
        Inc(Total);
        Recs^[Total] := DirFileRecNum;
      END;
      NRecNo(FileInfo,DirFileRecNum);
    END;

    IF (Total < 1) THEN
    BEGIN
      NL;
      Print('^8No files found.^0');
      Dispose(YPos);
      Dispose(Recs);
      Exit;
    END;

    StartIdx := 1;
    ContFile := 0;
    StartExt := 0;
    StackTop := 0;
    Sel := 1;
    LastSel := 1;
    EndIdx := 1;
    NeedRedraw := TRUE;

    REPEAT
      IF (NeedRedraw) THEN
        DrawPage;
      {WKey removed for LB key handling}
      W := InKey;

      IF (W = F_UP) THEN
      BEGIN
        IF (StackTop > 0) THEN
        BEGIN
          Dec(StackTop);
          ContFile := ContStack[StackTop];
          StartExt := ExtStack[StackTop];
          StartIdx := ContFile;
          Sel := ContFile;
          NeedRedraw := TRUE;
        END
        ELSE IF (ContFile > 0) AND (StartExt > 0) THEN
        BEGIN
          StartExt := 0;
          StartIdx := ContFile;
          Sel := ContFile;
          NeedRedraw := TRUE;
        END
        ELSE IF (Sel > 1) THEN
        BEGIN
          Dec(Sel);
          ContFile := 0;
          StartExt := 0;
          StackTop := 0;
        END;
      END
      ELSE IF (W = F_DOWN) THEN
      BEGIN
        IF (NextContFile = Sel) AND (NextStartExt > 0) THEN
        BEGIN
          IF (StackTop < 40) THEN
          BEGIN
            ContStack[StackTop] := Sel;
            ExtStack[StackTop] := StartExt;
            Inc(StackTop);
          END;
          ContFile := Sel;
          StartExt := NextStartExt;
          StartIdx := ContFile;
          Sel := ContFile;
          NeedRedraw := TRUE;
        END
        ELSE IF (Sel < Total) THEN
        BEGIN
          Inc(Sel);
          ContFile := 0;
          StartExt := 0;
          StackTop := 0;
        END;
      END
      ELSE IF (W = Ord('V')) OR (W = Ord('v')) THEN
      BEGIN
        Seek(FileInfoFile,Recs^[Sel]);
        Read(FileInfoFile,FI);
        IF (ValidIntArcType(FI.FileName)) THEN
        BEGIN
          IF Common.Exist(MemFileArea.DLPath+FI.FileName) THEN
            ViewInternalArchive(MemFileArea.DLPath+FI.FileName)
          ELSE
            ViewInternalArchive(MemFileArea.ULPath+FI.FileName);
          NeedRedraw := TRUE;
        END
        ELSE
        BEGIN
          NL;
          Print('^8Not a supported archive.^0');
        END;
      
      END

      ELSE IF (W = Ord('D')) OR (W = Ord('d')) THEN
      BEGIN
        RecalcBatchDLStats;
        IF (NumBatchDLFiles = 0) THEN
        BEGIN
          NL;
          Print('^8Batch queue is empty.^0');
        END
        ELSE
        BEGIN
          CLS;
          File6.BatchDownload;
          NeedRedraw := TRUE;
        END;
      END

      ELSE IF (W = 32) THEN
      BEGIN
                SaveAllowContinue := AllowContinue;
        TempPause := TRUE;
        AllowContinue := FALSE;
        ANSIG(1, Hi(WindMax));
        Prompt(#27+'[2K');
        Seek(FileInfoFile,Recs^[Sel]);
        Read(FileInfoFile,FI);
        BK := BatchKeyForFI11(FI);
        IF File6.CheckBatchDL(BK) THEN
        BEGIN
          RemoveBatchDLByKey(BK);
          { ensure batch counters/empty-state are correct immediately }
          RecalcBatchDLStats;
        END
        ELSE
        BEGIN
          TransferFlags := [IsCheckRatio,lIsAddDLBatch];
          IF (FACDROM IN MemFileArea.FAFlags) THEN
            Include(TransferFlags,IsCDRom);
          IF Common.Exist(MemFileArea.DLPath+FI.FileName) THEN
            File8.Send(FI,Recs^[Sel],MemFileArea.DLPath,TransferFlags)
          ELSE
            File8.Send(FI,Recs^[Sel],MemFileArea.ULPath,TransferFlags);
          { resync counters after add }
          RecalcBatchDLStats;
        END;

                { restore output flags and redraw footer to wipe any stray output }
        AllowContinue := SaveAllowContinue;
        TempPause := SaveTempPause;
        DrawLBFooter;
        ANSIG(1, YPos^[Sel]);
NeedRedraw := TRUE;
      END
      ELSE IF (W = Ord('T')) OR (W = Ord('t')) THEN
      BEGIN
        Seek(FileInfoFile,Recs^[Sel]);
        Read(FileInfoFile,FI);
        TransferFlags := [IsCheckRatio];
        CLS;
        DLX(FI,Recs^[Sel],TransferFlags);
        IF (IsKeyboardAbort IN TransferFlags) THEN
          Break;
        NeedRedraw := TRUE;
      END
      ELSE IF (W = 13) OR (W = 10) THEN
      BEGIN
        { ENTER = next page; at end of NewScan list, continue to next area }
        IF (Sel < Total) THEN
        BEGIN
          Sel := EndIdx + 1;
          IF (Sel > Total) THEN
            Sel := Total;
          ContFile := 0;
          StartExt := 0;
          StackTop := 0;
          NeedRedraw := TRUE;
        END
        ELSE IF (LB_NewScanMode) THEN
        BEGIN
          LB_AdvanceNextArea := TRUE;
          Break;
        END;
      END
      ELSE IF (W = 27) THEN
      BEGIN
        IF (LB_NewScanMode) THEN
          LB_QuitNewScan := TRUE;
        Break;
      END
      ELSE IF (W = Ord('Q')) OR (W = Ord('q')) THEN
      BEGIN
        IF (LB_NewScanMode) THEN
          LB_QuitNewScan := TRUE;
        Break;
      END;

IF (Sel < StartIdx) THEN
      BEGIN
        { Page up: jump to bottom of previous page (unless already at very top) }
        StartIdx := StartIdx - PageSize;
        IF (StartIdx < 1) THEN
        BEGIN
          StartIdx := 1;
          Sel := 1;
        END
        ELSE
        BEGIN
          Sel := StartIdx + PageSize - 1;
          IF (Sel > Total) THEN
            Sel := Total;
        END;
        ContFile := 0;
        StartExt := 0;
        StackTop := 0;
        NeedRedraw := TRUE;
      END
      ELSE IF (Sel > EndIdx) THEN
      BEGIN
        StartIdx := EndIdx + 1;
        IF (StartIdx > Total) THEN
          StartIdx := Total - PageSize + 1;
        IF (StartIdx < 1) THEN
          StartIdx := 1;
        Sel := StartIdx;
        ContFile := 0;
        StartExt := 0;
        StackTop := 0;
        NeedRedraw := TRUE;
      END
      ELSE IF (Sel <> LastSel) THEN
      BEGIN
        DrawName(LastSel,FALSE);
        FileRedisplayLines := SaveFRL;
        DrawName(Sel,TRUE);
        LastSel := Sel;
      END;
    UNTIL (HangUp);
    Dispose(YPos);
    Dispose(Recs);
    AllowContinue := SaveAllowContinue;
    TempPause := SaveTempPause;
  END;



BEGIN
  Abort := FALSE;
  Next := FALSE;
  InitFArray(FArray);
  FArrayRecNum := 0;
  IF (FName = '') THEN
  BEGIN
    NL;
    { Print(FString.ListLine); }
    lRGLngStr(18,FALSE);
    { Print(FString.lGFNLine1); }
    lRGLngStr(28,FALSE);
    { Prt(FString.GFNLine2); }
    lRGLngStr(29,FALSE);
    GetFileName(FName);
  END
  ELSE
    FName := Align(FName);
  IF (OkANSI) AND (General.UseLightBars) AND (LightBars IN ThisUser.SFlags) THEN
    ListFileSpec_LB(FName)
  ELSE
    SearchFileAreaSpec(FileArea,FName,FArrayRecNum);
END;

PROCEDURE SearchFileAreaDescription(FArea: Integer; SearchString: Str20; VAR FArrayRecNum: Byte);
VAR
  LineNum,
  NumExtDesc: Byte;
  BK: Str52;
  DirFileRecNum: Integer;
  SearchStringFound,
  Found: Boolean;
BEGIN
  IF (FileArea <> FArea) THEN
    ChangeFileArea(FArea);
  IF (FileArea = FArea) THEN
  BEGIN
    RecNo(FileInfo,'*.*',DirFileRecNum);
    IF (BadDownloadPath) THEN
      Exit;
    Found := FALSE;
    LIL := 0;
    CLS;
    Prompt('^0Scanning ^1'+MemFileArea.AreaName+' #'+IntToStr(CompFileArea(FArea,0))+'^0 ...');
    WHILE (DirFileRecNum <> -1) AND (NOT Abort) AND (NOT HangUp) DO
    BEGIN
      Seek(FileInfoFile,DirFileRecNum);
      Read(FileInfoFile,FileInfo);
      IF (CanSee(FileInfo)) THEN
      BEGIN
        SearchStringFound := ((Pos(SearchString,AllCaps(FileInfo.Description)) <> 0) OR
                             (Pos(SearchString,AllCaps(FileInfo.FileName)) <> 0));
        IF (NOT SearchStringFound) AND (FileInfo.VPointer <> -1) THEN
        BEGIN
          LoadVerbArray11(FileInfo,ExtendedArray,NumExtDesc);
          LineNum := 1;
          WHILE (LineNum <= NumExtDesc) AND (NOT SearchStringFound) AND (NOT Abort) AND (NOT HangUp) DO
          BEGIN
            IF (Pos(SearchString,AllCaps(ExtendedArray[LineNum])) <> 0) THEN
              SearchStringFound := TRUE;
            Inc(LineNum);
          END;
        END;
        IF (SearchStringFound) THEN
        BEGIN

          WITH FArray[FArrayRecNum] DO
          BEGIN
            FArrayFileArea := FileArea;
            FArrayDirFileRecNum := DirFileRecNum;
          END;

          DisplayFileAreaHeader;

          lDisplay_File(FileInfo,FArrayRecNum,SearchString,FALSE);

          Inc(FArrayRecNum);
          IF (FArrayRecNum = 100) THEN
            FArrayRecNum := 0;

          Found := TRUE;
        END;
      END;
      NRecNo(FileInfo,DirFileRecNum);
      IF (DirFileRecNum = -1) AND (Found) AND (Lines > FileRedisplayLines) AND (NOT Abort) AND (NOT HangUp) THEN
      BEGIN
        Lines := PageLength;
        Pause_Files;
      END;
    END;
    IF (NOT Found) THEN
    BEGIN
      LIL := 0;
      BackErase(15 + LennMCI(MemFileArea.AreaName) + Length(IntToStr(CompFileArea(FArea,0))));
    END;
    Close(FileInfoFile);
    Close(ExtInfoFile);
  END;
END;

PROCEDURE SearchFileDescriptions;
VAR
  SearchString: Str20;
  FArrayRecNum: Byte;
  FArea,
  SaveFileArea: Integer;
  SaveConfSystem: Boolean;
BEGIN
  NL;
  lRGLngStr(21,FALSE); { Print(FString.FindLine1); }
  NL;
  lRGLngStr(22,FALSE); { Print(FString.FindLine2); }
  Prt(': ');
  InputMain(SearchString,SizeOf(SearchString)-1,[CapAll]);
  IF (SearchString = '') THEN
  BEGIN
    Print('%LFAborted.');
    Exit;
  END;
  SYSOPLOG('Searched For: '+SearchString); (*Exo 4/27/24*)
  Abort := FALSE;
  Next := FALSE;
  InitFArray(FArray);
  FArrayRecNum := 0;
  Print('%LFSearching for "'+SearchString+'"');
  IF (NOT PYNQ('%LFSearch all file areas? ',0,FALSE)) THEN
    SearchFileAreaDescription(FileArea,SearchString,FArrayRecNum)
  ELSE
  BEGIN
    SaveFileArea := FileArea;
    SaveConfSystem := ConfSystem;
    ConfSystem := NOT PYNQ('%LFSearch all conferences? ',0,TRUE);
    IF (ConfSystem <> SaveConfSystem) THEN
      NewCompTables;
    FArea := 1;
    WHILE (FArea >= 1) AND (FArea <= NumFileAreas) AND (NOT Abort) AND (NOT HangUp) DO
    BEGIN
      SearchFileAreaDescription(FArea,SearchString,FArrayRecNum);
      WKey;
      Inc(FArea);
    END;
    IF (ConfSystem <> SaveConfSystem) THEN
    BEGIN
      ConfSystem := SaveConfSystem;
      NewCompTables;
    END;
    FileArea := SaveFileArea;
    LoadFileArea(FileArea);
  END;
END;

PROCEDURE NewFileScan(FArea: Integer; Global: Boolean; VAR FArrayRecNum: Byte);
VAR
counter,
  DirFileRecNum: Integer;
  Found: Boolean;
BEGIN
  IF (FileArea <> FArea) THEN
    ChangeFileArea(FArea);
  IF (FileArea = FArea) THEN
    BEGIN
      RecNo(FileInfo,'*.*',DirFileRecNum);
      IF (BadDownloadPath) THEN
        EXIT;
      IF (NOT Global) OR (NewScanFileArea) THEN
        BEGIN
          Found := FALSE;
          LIL := 0;
          {CLS;}
          lRGLngStr(95,FALSE); {Prompt('^0Scanning ^1'+MemFileArea.AreaName+' #'+IntToStr(CompFileArea(FileArea,0))+'^0 ...');}
                    IF (OkANSI) AND (General.UseLightBars) AND (LightBars IN ThisUser.SFlags) THEN
            BEGIN
          { Quick pre-scan: only show a lightbar list if this area has any new files }
          WHILE (DirFileRecNum <> -1) AND (NOT Abort) AND (NOT HangUp) DO
          BEGIN
            Seek(FileInfoFile,DirFileRecNum);
            Read(FileInfoFile,FileInfo);
            IF ((CanSee(FileInfo)) AND (DayNum(PD2Date(FileInfo.FileDate)) >= DayNum(PD2Date(NewFileDate))))
               OR (CanSee(FileInfo) AND (FINotVal IN FileInfo.FIFlags)) THEN
            BEGIN
              Found := TRUE;
              Break;
            END;
            NRecNo(FileInfo,DirFileRecNum);
          END;

          IF (Found) AND (NOT Abort) AND (NOT HangUp) THEN
          BEGIN
            { Lightbar NewScan view for this area }
            LB_NewScanMode := TRUE;
            LB_AdvanceNextArea := FALSE;
            LB_QuitNewScan := FALSE;
            ListFileSpec('*.*');
            LB_NewScanMode := FALSE;
          END;
            END
          ELSE
            BEGIN
WHILE (DirFileRecNum <> -1) AND (NOT Abort) AND (NOT HangUp) DO
            BEGIN
              Seek(FileInfoFile,DirFileRecNum);
              Read(FileInfoFile,FileInfo);
              IF ((CanSee(FileInfo)) AND (DayNum(PD2Date(FileInfo.FileDate)) >= DayNum(PD2Date(NewFileDate))))
                 OR (CanSee(FileInfo) AND (FINotVal IN FileInfo.FIFlags)) THEN
                BEGIN
                  WITH FArray[FArrayRecNum] DO
                    BEGIN
                      FArrayFileArea := FileArea;
                      FArrayDirFileRecNum := DirFileRecNum;
                    END;
                  DisplayFileAreaHeader;
                  lDisplay_File(FileInfo,FArrayRecNum,'',FALSE);

                  Inc(FArrayRecNum);
                  IF (FArrayRecNum = 100) THEN
                    FArrayRecNum := 0;
                  Found := TRUE;
                END;
              NRecNo(FileInfo,DirFileRecNum);
              IF (DirFileRecNum = -1) AND (Found) AND (Lines > FileRedisplayLines) AND (NOT Abort) AND (NOT HangUp) THEN
                BEGIN
                  Lines := PageLength;
                  Pause_Files;
                END;
            END;
          
            END;
IF (NOT Found) THEN
            BEGIN
              LIL := 0;
              {BackErase(15 + LennMCI(MemFileArea.AreaName) + Length(IntToStr(CompFileArea(FArea,0))));}
              FOR Counter := 1 TO LennMCI(lRGLngStr(95,TRUE)) DO
                BackSpace;
               
            END;
        END;
      Close(FileInfoFile);
      Close(ExtInfoFile);
    END;
END;

PROCEDURE GlobalNewFileScan(VAR FArrayRecNum: Byte);
VAR
  FArea: Integer;
BEGIN
  FArea := 1;
  WHILE (FArea >= 1) AND (FArea <= NumFileAreas) AND (NOT Abort) AND (NOT HangUp) DO
  BEGIN
    LB_AdvanceNextArea := FALSE;
    LB_QuitNewScan := FALSE;
    NewFileScan(FArea,TRUE,FArrayRecNum);
    IF (LB_QuitNewScan) THEN
      Break;
    IF (TextRec(NewFilesF).Mode = FMOutPut) THEN
      Output_File_Stuff('');
    Inc(FArea);
  END;
END;



PROCEDURE NewFilesScanSearchType(CONST MenuOption: Str50);
VAR
  FArrayRecNum: Byte;
  SaveFileArea: Integer;
BEGIN
  SaveFileArea := FileArea;
  Abort := FALSE;
  Next := FALSE;
  InitFArray(FArray);
  FArrayRecNum := 0;
  IF (UpCase(MenuOption[1]) = 'C') THEN
    NewFileScan(FileArea,FALSE,FArrayRecNum)
  ELSE IF (UpCase(MenuOption[1]) = 'G') THEN
    GlobalNewFileScan(FArrayRecNum)
  ELSE IF (StrToInt(MenuOption) <> 0) THEN
    NewFileScan(StrToInt(MenuOption),FALSE,FArrayRecNum)
  ELSE
    BEGIN
      lRGLngStr(19,FALSE); {"List Files - P to Pause"}
      IF PYNQ('%LFSearch all file areas? ',0,FALSE) THEN
        GlobalNewFileScan(FArrayRecNum)
      ELSE
        NewFileScan(FileArea,FALSE,FArrayRecNum);
    END;
  FileArea := SaveFileArea;
  LoadFileArea(FileArea);
END;

PROCEDURE FileAreaChange(VAR Done: Boolean; CONST MenuOption: Str50);
VAR
  InputStr: Str5;
  Cmd: Char;
  FArea,
  SaveFArea,
  NumFAreas: Integer;
  SaveTempPause: Boolean;
  SaveAllowContinue: Boolean;
BEGIN
  IF (MenuOption <> '') THEN
    CASE Upcase(MenuOption[1]) OF
      '+' : BEGIN
              FArea := FileArea;
              IF (FileArea >= NumFileAreas) THEN
                FArea := 0
              ELSE
                REPEAT
                  Inc(FArea);
                  ChangeFileArea(FArea);
                UNTIL ((FileArea = FArea) OR (FArea >= NumFileAreas));
              IF (FileArea <> FArea) THEN
              BEGIN
                {
                %LFHighest accessible file area.
                %PA
                }
                LRGLngStr(83,FALSE);
              END
              ELSE
                LastCommandOvr := TRUE;
            END;
      '-' : BEGIN
              FArea := FileArea;
              IF (FileArea <= 0) THEN
                FArea := 0
              ELSE
                REPEAT
                  Dec(FArea);
                  ChangeFileArea(FArea);
                UNTIL ((FileArea = FArea) OR (FArea <= 0));
              IF (FileArea <> FArea) THEN
              BEGIN
                {
                %LFLowest accessible file area.
                %PA
                }
                LRGLngStr(82,FALSE);
              END
              ELSE
                LastCommandOvr := TRUE;
            END;
      'L' : BEGIN
              Abort := FALSE;
    Next := FALSE;
    SaveTempPause := TempPause;
    SaveAllowContinue := AllowContinue;
    AllowContinue := FALSE;
              TempPause := FALSE;
              FArea := 1;
              NumFAreas := 0;
              IF (OkANSI) AND (General.UseLightBars) AND
                 (LightBars IN ThisUser.SFlags) THEN
              BEGIN
                LightBarCmd := 1;
                LightBarFirstCmd := TRUE;
                InputStr := '?';
                REPEAT
                  SaveFArea := FArea;
                  IF (InputStr = '?') THEN
                    LFileAreaList(FArea,NumFAreas,6,FALSE);
                  FileAreaScanInput(LRGLngStr(72,TRUE),
                    Length(IntToStr(HighFileArea)),InputStr,'Q[]?',
                    LowFileArea,HighFileArea);
                  IF (InputStr <> 'Q') THEN
                  BEGIN
                    IF (InputStr = '[') THEN
                    BEGIN
                      FArea := SaveFArea - ((PageLength - 5) * 2);
                      IF (FArea < 1) THEN
                        FArea := 1;
                      InputStr := '?';
                    END
                    ELSE IF (InputStr = ']') THEN
                    BEGIN
                      IF (FArea > NumFileAreas) THEN
                        FArea := SaveFArea;
                      InputStr := '?';
                    END
                    ELSE IF (InputStr = '?') THEN
                    BEGIN
                      LRGLngStr(71,FALSE);
                      FArea := SaveFArea;
                    END
                    ELSE IF (StrToInt(InputStr) > 0) THEN
                    BEGIN
                      FArea := StrToInt(InputStr);
                      IF (FArea <> FileArea) THEN
                        ChangeFileArea(FArea);
                      LastCommandOvr := TRUE;
                    END;
                  END;
                UNTIL (InputStr = 'Q') OR (HangUp);
              END
              ELSE
              BEGIN
                Cmd := '?';
                REPEAT
                  SaveFArea := FArea;
                  IF (Cmd = '?') THEN
                    LFileAreaList(FArea,NumFAreas,6,FALSE);
                  InputChar(LRGLngStr(70,TRUE),Cmd,'Q[]?',[CapAll]);
                  TempPause := FALSE;
                IF (Cmd <> 'Q') THEN
                BEGIN
                  IF (Cmd = '[') THEN
                  BEGIN
                    Farea := (SaveFArea - ((PageLength - 5) * 2));
                    IF (FArea < 1) THEN
                      FArea := 1;
                    Cmd := '?';
                  END
                  ELSE IF (Cmd = ']') THEN
                  BEGIN
                    IF (FArea > NumFileAreas) THEN
                      FArea := SaveFArea;
                    Cmd := '?';
                  END
                  ELSE IF (Cmd = '?') THEN
                  BEGIN
                    {
                    $File_Message_Area_List_Help
                    %LF^0(^1###^0)Manual entry selection  ^0(^1<CR>^0)Select current entry
                    ^0(^1<Home>^0)First entry on page  ^0(^1<End>^0)Last entry on page
                    ^0(^1Left Arrow^0)Previous entry   ^0(^1Right Arrow^0)Next entry
                    ^0(^1Up Arrow^0)Move up            ^0(^1Down Arrow^0)Move down
                    ^0(^1[^0)Previous page             ^0(^1]^0)Next page
                    %PA
                    }
                    LRGLngStr(71,FALSE);
                    FArea := SaveFArea;
                  END
                END;
                UNTIL (Cmd = 'Q') OR (HangUp);
              END;
              AllowContinue := SaveAllowContinue;
    TempPause := SaveTempPause;
              LastCommandOvr := TRUE;
            END;
    ELSE
    BEGIN
      IF (StrToInt(MenuOption) > 0) THEN
      BEGIN
        FArea := StrToInt(MenuOption);
        IF (FArea <> FileArea) THEN
          ChangeFileArea(FArea);
        IF (Pos(';',MenuOption) > 0) THEN
        BEGIN
          CurMenu := StrToInt(Copy(MenuOption,(Pos(';',MenuOption) + 1),Length(MenuOption)));
          NewMenuToLoad := TRUE;
          Done := TRUE;
        END;
        LastCommandOvr := TRUE;
      END;
    END;
  END
  ELSE
  BEGIN
    Abort := FALSE;
    Next := FALSE;
    SaveTempPause := TempPause;
    TempPause := FALSE;
    FArea := 1;
    NumFAreas := 0;

    LightBarCmd := 1;
    LightBarFirstCmd := TRUE;

    InputStr := '?';
    REPEAT
      SaveFArea := FArea;
      IF (InputStr = '?') THEN
        lFileAreaList(FArea,NumFAreas,6,FALSE);
      {%LFChange file area? [^1#^2,^1?^2=^1Help^2,^1Q^2=^1Quit^2]: @}
      FileAreaScanInput(LRGLngStr(72,TRUE),Length(IntToStr(HighFileArea)),InputStr,'Q[]?',LowFileArea,HighFileArea);
      IF (InputStr <> 'Q') THEN
      BEGIN
        IF (InputStr = '[') THEN
        BEGIN
          Farea := (SaveFArea - ((PageLength - 5) * 2));
          IF (FArea < 1) THEN
            FArea := 1;
          InputStr := '?';
        END
        ELSE IF (InputStr = ']') THEN
        BEGIN
          IF (FArea > NumFileAreas) THEN
            FArea := SaveFArea;
          InputStr := '?';
        END
        ELSE IF (InputStr = '?') THEN
        BEGIN
          {
          $File_Message_Area_List_Help
          %LF^0(^1###^0)Manual entry selection  ^0(^1<CR>^0)Select current entry
          ^0(^1<Home>^0)First entry on page  ^0(^1<End>^0)Last entry on page
          ^0(^1Left Arrow^0)Previous entry   ^0(^1Right Arrow^0)Next entry
          ^0(^1Up Arrow^0)Move up            ^0(^1Down Arrow^0)Move down
          ^0(^1[^0)Previous page             ^0(^1]^0)Next page
          %PA
          }
          LRGLngStr(71,FALSE);
          FArea := SaveFArea;
        END
        ELSE IF (StrToInt(InputStr) < LowFileArea) OR (StrToInt(InputStr) > HighFileArea) THEN
        BEGIN
          {
          %LF^8The range must be from %A1 to %A2!^0
          }
          LRGLngStr(78,FALSE);
          FArea := SaveFArea;
          InputStr := '?';
        END
        ELSE
        BEGIN
          FArea := CompFileArea(StrToInt(InputStr),1);
          IF (FArea <> FileArea) THEN
            ChangeFileArea(FArea);
          IF (FArea = FileArea) THEN
            InputStr := 'Q'
          ELSE
          BEGIN
            {
            %LF^8You do not have access to this file area!^0
            }
            LRGLngStr(80,FALSE);
            FArea := SaveFArea;
            InputStr := '?';
          END;
        END;
      END;
    UNTIL (InputStr = 'Q') OR (HangUp);
    AllowContinue := SaveAllowContinue;
    TempPause := SaveTempPause;
    LastCommandOvr := TRUE;
  END;
END;

PROCEDURE CreateTempDir;
VAR
  TempPath: Str40;
  Changed: Boolean;
BEGIN
  TempPath := '';
  InputPath('%LF^2Enter file path for temporary directory:%LF^2:',TempPath,TRUE,TRUE,Changed);
  IF (TempPath = '') THEN
  BEGIN
    Print('%LFAborted.');
    Exit;
  END;
  IF (NOT ExistDir(TempPath)) THEN
  BEGIN
    Print('%LFThat directory does not exist.');
    Exit;
  END;
  FillChar(TempMemFileArea,SizeOf(TempMemFileArea),0);
  WITH TempMemFileArea DO
  BEGIN
    AreaName := '<< Temporary >>';
    FileName := 'TEMPFILE';
    DLPath := TempPath;
    ULPath := TempPath;
    MaxFiles := 32767; 
    Password := '';
    ArcType := 1;
    CmtType := 1;
    ACS := 's'+IntToStr(ThisUser.SL)+'d'+IntToStr(ThisUser.DSL);
    ULACS := ACS;
    DLACS := ACS;
    FAFlags := [];
  END;
  FileArea := (NumFileAreas + 1);
  LoadFileArea(FileArea);
  SysOpLog('Created temporary directory #'+IntToStr(FileArea)+' in "'+TempPath+'"');
END;

END.
