{$A+,B-,D+,E-,F+,I-,L+,N-,O+,R-,S+,V-}

UNIT Archive;

INTERFACE

USES
  Common;

PROCEDURE ArcDeComp(VAR Ok: Boolean; AType: Byte; CONST FileName,FSpec: AStr);
PROCEDURE ArcComp(VAR Ok: Boolean; AType: Byte; CONST FileName,FSpec: AStr);
PROCEDURE ArcComment(VAR Ok: Boolean; AType: Byte; CommentNum: Byte; CONST FileName: AStr);
PROCEDURE ArcIntegrityTest(VAR Ok: Boolean; AType: Byte; CONST FileName: AStr);
PROCEDURE ConvA(VAR Ok: Boolean; OldAType,NewAType: Byte; CONST OldFN,NewFN: AStr);
FUNCTION ArcType(FileName: AStr): Byte;
PROCEDURE ListArcTypes;
PROCEDURE InvArc;
PROCEDURE ExtractToTemp;
PROCEDURE UserArchive;
PROCEDURE DOArcCommand(Cmd: Char);
PROCEDURE ReZipStuff;

IMPLEMENTATION

USES
  Dos,
  ArcView,
  ExecBat,
  File0,
  File11,
  TimeFunc;

{ Archive1 implementation }
PROCEDURE ArcDeComp(VAR Ok: Boolean; AType: Byte; CONST FileName,FSpec: AStr);
VAR
  ResultCode: Integer;
BEGIN
  PurgeDir(TempDir+'ARC\',FALSE);
  ExecBatch(Ok,TempDir+'ARC\',General.ArcsPath+
            FunctionalMCI(General.FileArcInfo[AType].UnArcLine,FileName,FSpec),
            General.FileArcInfo[AType].SuccLevel,ResultCode,FALSE);
  IF (NOT Ok) AND (Pos('.DIZ',FSpec) = 0) THEN
    SysOpLog(FileName+': errors during de-compression');
END;

PROCEDURE ArcComp(VAR Ok: Boolean; AType: Byte; CONST FileName,FSpec: AStr);
VAR
  ResultCode: Integer;
BEGIN
  IF (General.FileArcInfo[AType].ArcLine = '') THEN
    Ok := TRUE
  ELSE
    ExecBatch(Ok,TempDir+'ARC\',General.ArcsPath+
              FunctionalMCI(General.FileArcInfo[AType].ArcLine,FileName,FSpec),
              General.FileArcInfo[AType].SuccLevel,ResultCode,FALSE);
  IF (NOT Ok) THEN
    SysOpLog(FileName+': errors during compression');
END;

PROCEDURE ArcComment(VAR Ok: Boolean; AType: Byte; CommentNum: Byte; CONST FileName: AStr);
VAR
  TempStr: AStr;
  ResultCode: Integer;
  SaveSwapShell: Boolean;
BEGIN
  IF (CommentNum > 0) AND (General.FileArcComment[CommentNum] <> '') THEN
  BEGIN
    SaveSwapShell := General.SwapShell;
    General.SwapShell := FALSE;
    TempStr := Substitute(General.FileArcInfo[AType].CmtLine,'%C',General.FileArcComment[CommentNum]);
    TempStr := Substitute(TempStr,'%C',General.FileArcComment[CommentNum]);
    ExecBatch(Ok,TempDir+'ARC\',General.ArcsPath+FunctionalMCI(TempStr,FileName,''),
              General.FileArcInfo[AType].SuccLevel,ResultCode,FALSE);
    General.SwapShell := SaveSwapShell;
  END;
END;

PROCEDURE ArcIntegrityTest(VAR Ok: Boolean; AType: Byte; CONST FileName: AStr);
VAR
  ResultCode: Integer;
BEGIN
  IF (General.FileArcInfo[AType].TestLine <> '') THEN
    ExecBatch(Ok,TempDir+'ARC\',General.ArcsPath+
              FunctionalMCI(General.FileArcInfo[AType].TestLine,FileName,''),
              General.FileArcInfo[AType].SuccLevel,ResultCode,FALSE);
END;

PROCEDURE ConvA(VAR Ok: Boolean; OldAType,NewAType: Byte; CONST OldFN,NewFN: AStr);
VAR
  NoFN: AStr;
  PS: PathStr;
  NS: NameStr;
  ES: ExtStr;
  FileTime: LongInt;
  Match: Boolean;
BEGIN
  Star('Converting archive - stage one.');

  Match := (OldAType = NewAType);
  IF (Match) THEN
  BEGIN
    FSplit(OldFN,PS,NS,ES);
    NoFN := PS+NS+'.#$%';
  END;

  GetFileDateTime(OldFN,FileTime);

  ArcDeComp(Ok,OldAType,OldFN,'*.*');
  IF (NOT Ok) THEN
    Star('Errors in decompression!')
  ELSE
  BEGIN
    Star('Converting archive - stage two.');

    IF (Match) THEN
      RenameFile('',OldFN,NoFN,Ok);

    ArcComp(Ok,NewAType,NewFN,'*.*');
    IF (NOT Ok) THEN
    BEGIN
      Star('Errors in compression!');
      IF (Match) THEN
        RenameFile('',NoFN,OldFN,Ok);
    END
    ELSE

      SetFileDateTime(NewFN,FileTime);

    IF (NOT Exist(SQOutSp(NewFN))) THEN
      Ok := FALSE;
  END;
  IF (Exist(NoFN)) THEN
    Kill(NoFN);
END;

FUNCTION ArcType(FileName: AStr): Byte;
VAR
  AType,
  Counter: Byte;
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
  ArcType := AType;
END;

PROCEDURE ListArcTypes;
VAR
  RecNum,
  RecNum1: Byte;
BEGIN
  RecNum1 := 0;
  RecNum := 1;
  WHILE (RecNum <= MaxArcs) AND (General.FileArcInfo[RecNum].Ext <> '') DO
  BEGIN
    IF (General.FileArcInfo[RecNum].Active) THEN
    BEGIN
      Inc(RecNum1);
      IF (RecNum1 = 1) THEN
        Prompt('^0Available archive formats: ')
      ELSE
        Prompt('^0,');
      Prompt('^1'+General.FileArcInfo[RecNum].Ext+'^0');
    END;
    Inc(RecNum);
  END;
  IF (RecNum1 = 0) THEN
    Messages(4,0,'archive formats'); { "No archive formats exist!" }(*Prompt('* No archive formats available *');*)
  NL;
END;

PROCEDURE InvArc;
BEGIN
  NL;
  Print('Unsupported archive format.');
  NL;
  ListArcTypes;
END;

PROCEDURE ExtractToTemp;
TYPE
  TotalsRecordType = RECORD
    TotalFiles: Integer;
    TotalSize: LongInt;
  END;
VAR
  Totals: TotalsRecordType;
  FileName,
  ArcFileName: AStr;
  (*
  DirInfo: SearchRec;
  *)
  DS: DirStr;
  NS: NameStr;
  ES: ExtStr;
  Cmd: Char;
  AType: Byte;
  ReturnCode,
  DirFileRecNum: Integer;
  DidSomething,
  Ok: Boolean;
BEGIN
  NL;
  Print('Extract to temporary directory -');
  NL;
  Prompt('^0Already in TEMP: ');

  FillChar(Totals,SizeOf(Totals),0);
  FindFirst(TempDir+'ARC\*.*',AnyFile - Directory - VolumeID - Hidden - SysFile,DirInfo);
  WHILE (DOSError = 0) DO
  BEGIN
    Inc(Totals.TotalFiles);
    Inc(Totals.TotalSize,DirInfo.Size);
    FindNext(DirInfo);
  END;

  IF (Totals.TotalFiles = 0) THEN
    Print('^1Nothing.^0')
  ELSE
    Print('^1'+FormatNumber(Totals.TotalFiles)+
          ' '+Plural('file',Totals.TotalFiles)+
          ', '+ConvertBytes(Totals.TotalSize,FALSE)+'.^0');

  IF (NOT FileSysOp) THEN
  BEGIN
    NL;
    Print('The limit is '+FormatNumber(General.MaxInTemp)+'k bytes.');
    IF (Totals.TotalSize > (General.MaxInTemp * 1024)) THEN
    BEGIN
      NL;
      Print('You have exceeded this limit.');
      NL;
      Print('Please remove some files with the user-archive command.');
      Exit;
    END;
  END;

  NL;
  Prt('File name: ');
  IF (FileSysOp) THEN
    BEGIN
      InputMain(FileName,52,[CapAll]);
    END
  ELSE
    BEGIN
      InputMain(FileName,12,[CapAll]);
    END;
  FileName := SQOutSp(FileName);
  IF (FileName = '') THEN
    BEGIN
      NL;
      Print('Aborted!');
      Exit;
    END;
  IF (IsUL(FileName)) AND (NOT FileSysOp) THEN
    BEGIN
      NL;
      Print('^8Invalid file name!^0');
      Exit;
    END;
  IF (Pos('.',FileName) = 0) THEN
    FileName := FileName + '*.*';

  Ok := TRUE;

  IF (NOT IsUL(FileName)) THEN
  BEGIN
    RecNo(FileInfo,FileName,DirFileRecNum);
    IF (BadDownloadPath) THEN
      Exit;
    IF (NOT AACS(MemFileArea.DLACS)) THEN
    BEGIN
      NL;
      Print('^8You do not have access to manipulate that file!^0');
      Exit;
    END
    ELSE IF (DirFileRecNum = -1) THEN
    BEGIN
      NL;
      Print('^8File not found!^0');
      Exit;
    END
    ELSE
    BEGIN
      Seek(FileInfoFile,DirFileRecNum);
      Read(FileInfoFile,FileInfo);
      IF Exist(MemFileArea.DLPath+FileInfo.FileName) THEN
        ArcFileName := MemFileArea.DLPath+SQOutSp(FileInfo.FileName)
      ELSE
        ArcFileName := MemFileArea.ULPath+SQOutSp(FileInfo.FileName);
    END;

  END
  ELSE
  BEGIN
    ArcFileName := FExpand(FileName);
    IF (NOT Exist(ArcFileName)) THEN
    BEGIN
      NL;
      Print('^8File not found!^0');
      Exit;
    END
    ELSE
    BEGIN
      FillChar(FileInfo,SizeOf(FileInfo),0);
      WITH FileInfo DO
      BEGIN
        FileName := Align(StripName(ArcFileName));
        Description := 'Unlisted file';
        FilePoints := 0;
        Downloaded := 0;
        FileSize := GetFileSize(ArcFileName);
        OwnerNum := UserNum;
        OwnerName := Caps(ThisUser.Name);
        FileDate := Date2PD(DateStr);
        VPointer := -1;
        VTextSize := 0;
        FIFlags := [];
      END;
    END;
  END;
  IF (Ok) THEN
  BEGIN
    DidSomething := FALSE;
    Abort := FALSE;
    Next := FALSE;
    AType := ArcType(ArcFileName);
    IF (AType = 0) THEN
      InvArc;
    NL;
    Print('You can (^1C^0)opy this file into the TEMP Directory,');
    IF (AType <> 0) THEN
      Print('or (^1E^0)xtract files from it into the TEMP Directory.')
    ELSE
      Print('but you can''t extract files from it.');
    NL;
    InputChar('Which? (^1C^2=^1Copy'+AOnOff((AType <> 0),'^2,^1E^2=^1Extract','')+'^2,^1Q^2=^1Quit^2): ',Cmd,
          'QC'+AOnOff((AType <> 0),'E',''),[CapAll]);
    CASE Cmd OF
      'C' : BEGIN
              FSplit(ArcFileName,DS,NS,ES);
              NL;
              IF CopyMoveFile(TRUE,'^1Progress: ',ArcFileName,TempDir+'ARC\'+NS+ES,TRUE) THEN
                DidSomething := TRUE;
            END;
      'E' : BEGIN
              NL;
              DisplayFileInfo(FileInfo,TRUE);
              REPEAT
                NL;
                InputChar('Extract files (^1E^2=^1Extract^2,^1V^2=^1View^2,^1Q^2=^1Quit^2): ',Cmd,'QEV',[CapAll]);
                CASE Cmd OF
                  'E' : BEGIN
                          NL;
                          IF PYNQ('Extract all files? ',0,FALSE) THEN
                            FileName := '*.*'
                          ELSE
                          BEGIN
                            NL;
                            Prt('File name: ');
                            InputMain(FileName,12,[CapAll]);
                            FileName := SQOutSp(FileName);
                            IF (FileName = '') THEN
                            BEGIN
                              NL;
                              Print('Aborted!');
                            END
                            ELSE IF IsUL(FileName) THEN
                            BEGIN
                              NL;
                              Print('^8Illegal filespec!^0');
                              FileName := '';
                            END;
                          END;
                          IF (FileName <> '') THEN
                          BEGIN
                            Ok := FALSE;
                            ExecBatch(Ok,TempDir+'ARC\',General.ArcsPath+
                                      FunctionalMCI(General.FileArcInfo[AType].UnArcLine,ArcFileName,FileName),
                                      General.FileArcInfo[AType].SuccLevel,ReturnCode,FALSE);
                            IF (Ok) THEN
                            BEGIN
                              NL;
                              Star('Decompressed '+FileName+' into TEMP from '+StripName(ArcFileName));
                              SysOpLog('Decompressed '+FileName+' into '+TempDir+'ARC\ from '+StripName(ArcFileName));
                              DidSomething := TRUE;
                            END
                            ELSE
                            BEGIN
                              NL;
                              Star('Error decompressing '+FileName+' into TEMP from '+StripName(ArcFileName));
                              SysOpLog('Error decompressing '+FileName+' into '+TempDir+'ARC\ from '+StripName(ArcFileName));
                            END;
                          END;
                        END;
                  'V' : IF (IsUL(ArcFileName)) THEN
                          ViewInternalArchive(ArcFileName)
                        ELSE
                        BEGIN
                          IF Exist(MemFileArea.DLPath+FileInfo.FileName) THEN
                            ViewInternalArchive(MemFileArea.DLPath+FileInfo.FileName)
                          ELSE
                            ViewInternalArchive(MemFileArea.ULPath+FileInfo.FileName);
                        END;
                END;
              UNTIL (Cmd = 'Q') OR (HangUp);
           END;
    END;
    IF (DidSomething) THEN
    BEGIN
      NL;
      Print('^1NOTE: ^0Use the user archive menu command to access');
      Print('        files in the TEMP directory.^0');
    END;
  END;
  LastError := IOResult;
END;

PROCEDURE UserArchive;
VAR
  User: UserRecordType;
  (*
  DirInfo: SearchRec;
  *)
  TransferFlags: TransferFlagSet;
  ArcFileName,
  FName: Str12;
  Cmd: Char;
  AType,
  SaveNumBatchDLFiles: Byte;
  ReturnCode,
  GotPts,
  SaveFileArea: Integer;
  Ok,
  SaveFileCreditRatio: Boolean;

  FUNCTION OkName(FileName1: AStr): Boolean;
  BEGIN
    OkName := TRUE;
    OkName := NOT IsWildCard(FileName1);
    IF (IsUL(FileName1)) THEN
      OkName := FALSE;
  END;

BEGIN
  REPEAT
    NL;
    InputChar('Temp archive menu [^1?^2=^1Help^2]: ',Cmd,'QADLRVT?',[CapAll]);
    CASE Cmd OF
      'A' : BEGIN
              NL;
              Prt('Archive name: ');
              InputMain(ArcFileName,SizeOf(ArcFileName)-1,[CapAll]);
              IF (ArcFileName = '') THEN
              BEGIN
                NL;
                Print('Aborted!');
              END
              ELSE
              BEGIN

                LoadFileArea(FileArea);

                IF (Pos('.',ArcFileName) = 0) AND (MemFileArea.ArcType <> 0) THEN
                  ArcFileName := ArcFileName+'.'+General.FileArcInfo[MemFileArea.ArcType].Ext;

                AType := ArcType(ArcFileName);
                IF (AType = 0) THEN
                  InvArc
                ELSE
                BEGIN
                  NL;
                  Prt('File name: ');
                  InputMain(FName,SizeOf(FName)-1,[CapAll]);
                  IF (FName = '') THEN
                  BEGIN
                    NL;
                    Print('Aborted!');
                  END
                  ELSE IF (IsUL(FName)) OR (Pos('@',FName) > 0) THEN
                  BEGIN
                    NL;
                    Print('^8Illegal file name!^0');
                  END
                  ELSE IF (NOT Exist(TempDir+'ARC\'+FName)) THEN
                  BEGIN
                    NL;
                    Print('^8File not found!^0');
                  END
                  ELSE
                  BEGIN
                    Ok := FALSE;
                    ExecBatch(Ok,TempDir+'ARC\',General.ArcsPath+
                              FunctionalMCI(General.FileArcInfo[AType].ArcLine,TempDir+'ARC\'+ArcFileName,FName),
                              General.FileArcInfo[AType].SuccLevel,ReturnCode,FALSE);
                    IF (Ok) THEN
                    BEGIN
                      NL;
                      Star('Compressed "^1'+FName+'^1" into "^1'+ArcFileName+'^1"');
                      SysOpLog('Compressed "^1'+FName+'^0" into "^1'+TempDir+'ARC\'+ArcFileName+'^0"')
                    END
                    ELSE
                    BEGIN
                      NL;
                      Star('Error compressing "^1'+FName+'^1" into "^1'+ArcFileName+'^1"');
                      SysOpLog('Error compressing "^1'+FName+'^0" into "^1'+TempDir+'ARC\'+ArcFileName+'^0"');
                    END;
                  END;
                END;
              END;
            END;
      'D' : BEGIN
              NL;
              Prt('File name: ');
              InputMain(FName,SizeOf(FName)-1,[CapAll]);
              IF (FName = '') THEN
              BEGIN
                NL;
                Print('Aborted!');
              END
              ELSE IF (NOT OkName(FName)) THEN
              BEGIN
                NL;
                Print('^8Illegal file name!^0');
              END
              ELSE
              BEGIN
                FindFirst(TempDir+'ARC\'+FName,AnyFile - Directory - VolumeID - Hidden - SysFile,DirInfo);
                IF (DOSError <> 0) THEN
                BEGIN
                  NL;
                  Print('^8File not found!^0');
                END
                ELSE
                BEGIN
                  SaveFileArea := FileArea;
                  FileArea := -1;
                  WITH MemFileArea DO
                  BEGIN
                    AreaName := 'Temp Archive';
                    DLPath := TempDir+'ARC\';
                    ULPath := TempDir+'ARC\';
                    FAFlags := [];
                  END;
                  (* Consider charging points, ext. *)
                  LoadURec(User,1);
                  WITH FileInfo DO
                  BEGIN
                    FileName := Align(FName);
                    Description := 'Temporary Archive';
                    FilePoints := 0;
                    Downloaded := 0;
                    FileSize := GetFileSize(TempDir+'ARC\'+FileName);;
                    OwnerNum := 1;
                    OwnerName := Caps(User.Name);
                    FileDate := Date2PD(DateStr);
                    VPointer := -1;
                    VTextSize := 0;
                    FIFlags := [];
                  END;
                  TransferFlags := [IsTempArc,IsCheckRatio];
                  SaveNumBatchDLFiles := NumBatchDLFiles;
                  DLX(FileInfo,-1,TransferFlags);
                  FileArea := SaveFileArea;
                  LoadFileArea(FileArea);
                  IF (NumBatchDLFiles <> SaveNumBatchDLFiles) THEN
                  BEGIN
                    NL;
                    Print('^1REMEMBER: ^0If you delete this file from the temporary directory,');
                    Print('            you will not be able to download it in your batch queue.');
                  END;
                END;
              END;
            END;
      'L' : BEGIN
              AllowContinue := TRUE;
              NL;
              DosDir(TempDir+'ARC\','*.*',TRUE);
              AllowContinue := FALSE;
              SysOpLog('Listed temporary directory: "^1'+TempDir+'ARC\*.*^0"');
            END;
      'R' : BEGIN
              NL;
              Prt('File mask: ');
              InputMain(FName,SizeOf(FName)-1,[CapAll]);
              IF (FName = '') THEN
              BEGIN
                NL;
                Print('Aborted!');
              END
              ELSE IF (IsUL(FName)) THEN
              BEGIN
                NL;
                Print('^8Illegal file name!^0');
              END
              ELSE
              BEGIN
                FindFirst(TempDir+'ARC\'+FName,AnyFile - Directory - VolumeID - Hidden - SysFile,DirInfo);
                IF (DOSError <> 0) THEN
                BEGIN
                  NL;
                  Print('^8File not found!^0');
                END
                ELSE
                BEGIN
                  NL;
                  REPEAT
                    Kill(TempDir+'ARC\'+DirInfo.Name);
                    Star('Removed temporary archive file: "^1'+DirInfo.Name+'^1"');
                    SysOpLog('^0Removed temp arc file: "^1'+TempDir+'ARC\'+DirInfo.Name+'^0"');
                    FindNext(DirInfo);
                  UNTIL (DOSError <> 0) OR (HangUp);
                END;
              END;
            END;
      'T' : BEGIN
              NL;
              Prt('File name: ');
              InputMain(FName,SizeOf(FName)-1,[CapAll]);
              IF (FName = '') THEN
              BEGIN
                NL;
                Print('Aborted!');
              END
              ELSE IF (NOT OkName(FName)) THEN
              BEGIN
                NL;
                Print('^8Illegal file name!^0');
              END
              ELSE
              BEGIN
                FindFirst(TempDir+'ARC\'+FName,AnyFile - Directory - VolumeID - Hidden - SysFile,DirInfo);
                IF (DOSError <> 0) THEN
                BEGIN
                  NL;
                  Print('^8File not found!^0');
                END
                ELSE
                BEGIN
                  NL;
                  PrintF(TempDir+'ARC\'+DirInfo.Name);
                  SysOpLog('Displayed temp arc file: "^1'+TempDir+'ARC\'+DirInfo.Name+'^0"');
                END;
              END;
            END;
      'V' : BEGIN
              NL;
              Prt('File mask: ');
              InputMain(FName,SizeOf(FName)-1,[CapAll]);
              IF (FName = '') THEN
              BEGIN
                NL;
                Print('Aborted!');
              END
              ELSE IF (NOT ValidIntArcType(FName)) THEN
              BEGIN
                NL;
                Print('^8Not a valid archive type or not supported!^0')
              END
              ELSE
              BEGIN
                FindFirst(TempDir+'ARC\'+FName,AnyFile - Directory - VolumeID - Hidden - SysFile,DirInfo);
                IF (DOSError <> 0) THEN
                BEGIN
                  NL;
                  Print('^8File not found!^0');
                END
                ELSE
                BEGIN
                  Abort := FALSE;
                  Next := FALSE;
                  REPEAT
                    ViewInternalArchive(TempDir+'ARC\'+DirInfo.Name);
                    SysOpLog('Viewed temp arc file: "^1'+TempDir+'ARC\'+DirInfo.Name+'^0"');
                    FindNext(DirInfo);
                  UNTIL (DOSError <> 0) OR (Abort) OR (HangUp);
                END;
              END;
            END;
      '?' : BEGIN
              NL;
              ListArcTypes;
              NL;
              LCmds(30,1,'Add to archive','');
              LCmds(30,1,'Download files','');
              LCmds(30,1,'List files in directory','');
              LCmds(30,1,'Remove files','');
              LCmds(30,1,'Text view file','');
              LCmds(30,1,'View archive','');
              LCmds(30,1,'Quit','');
            END;
    END;
  UNTIL (Cmd = 'Q') OR (HangUp);
  LastCommandOvr := TRUE;
  LastError := IOResult;
END;

{ Archive3 implementation }
PROCEDURE CvtFiles(FArea: Integer; FileName,ReZipCmd: AStr; VAR TotalFiles: Integer; VAR TotalOldSize,TotalNewSize: LongInt);
VAR
  S: AStr;
  DS: DirStr;
  NS: NameStr;
  ES: ExtStr;
  AType: Byte;
  ReturnCode,
  DirFileRecNum: Integer;
  OldSiz,
  NewSiz: LongInt;
  Ok: Boolean;
BEGIN
  IF (FileArea <> FArea) THEN
    ChangeFileArea(FArea);
  IF (FileArea = FArea) AND (NOT (FACDROM IN MemFileArea.FAFlags)) THEN
  BEGIN
    RecNo(FileInfo,FileName,DirFileRecNum);
    IF (BadDownloadPath) THEN
      Exit;
    WHILE (DirFileRecNum <> -1) AND (NOT Abort) AND (NOT HangUp) DO
    BEGIN
      Seek(FileInfoFile,DirFileRecNum);
      Read(FileInfoFile,FileInfo);

      IF Exist(MemFileArea.DLPath+FileInfo.FileName) THEN
        FileName := MemFileArea.DLPath+FileInfo.FileName
      ELSE
        FileName := MemFileArea.ULPath+FileInfo.FileName;

      AType := ArcType(FileName);
      IF (AType <> 0) THEN
      BEGIN
        DisplayFileAreaHeader;
        NL;
        Star('Converting "'+SQOutSp(FileName)+'"');
        Ok := FALSE;
        IF (NOT Exist(FileName)) THEN
          Star('File "'+SQOutSp(FileName)+'" doesn''t exist.')
        ELSE
        BEGIN

          IF (ReZipCmd <> '') THEN
          BEGIN
            OldSiz := GetFileSize(FileName);

            ExecBatch(Ok,TempDir+'ARC\',ReZipCmd+' '+SQOutSp(FileName),-1,ReturnCode,FALSE);

            NewSiz := GetFileSize(FileName);

            FileInfo.FileSize := NewSiz;

            Seek(FileInfoFile,DirFileRecNum);
            Write(FileInfoFile,FileInfo);

          END
          ELSE
          BEGIN
            Ok := TRUE;
            S := FileName;

            OldSiz := GetFileSize(FileName);

            ConvA(Ok,AType,AType,SQOutSp(FileName),SQOutSp(S));

            IF (Ok) THEN
              IF (NOT Exist(SQOutSp(S))) THEN
              BEGIN
                Star('Unable to access "'+SQOutSp(S)+'"');
                SysOpLog('Unable to access '+SQOutSp(S));
                Ok := FALSE;
              END;

            IF (Ok) THEN
            BEGIN

              FileInfo.FileName := Align(StripName(SQOutSp(S)));
              Seek(FileInfoFile,DirFileRecNum);
              Write(FileInfoFile,FileInfo);

              FSplit(FileName,DS,NS,ES);
              FileName := DS+NS+'.#$%';
              Kill(FileName);
              IF (IOResult <> 0) THEN
              BEGIN
                Star('Unable to erase '+SQOutSp(FileName));
                SysOpLog('Unable to erase '+SQOutSp(FileName));
              END;

              Ok := Exist(SQOutSp(S));
              IF (NOT Ok) THEN
              BEGIN
                Star('Unable to access '+SQOutSp(S));
                SysOpLog('Unable to access '+SQOutSp(S));
              END
              ELSE
              BEGIN
                NewSiz := GetFileSize(S);

                FileInfo.FileSize := NewSiz;

                Seek(FileInfoFile,DirFileRecNum);
                Write(FileInfoFile,FileInfo);
                ArcComment(Ok,AType,MemFileArea.CmtType,SQOutSp(S));
              END;
            END
            ELSE
            BEGIN
              SysOpLog('Unable to convert '+SQOutSp(FileName));
              Star('Unable to convert '+SQOutSp(FileName));
            END;
          END;

          IF (Ok) THEN
          BEGIN
            Inc(TotalOldSize,OldSiz);
            Inc(TotalNewSize,NewSiz);
            Inc(TotalFiles);
            Star('Old total space took up  : '+ConvertBytes(OldSiz,FALSE));
            Star('New total space taken up : '+ConvertBytes(NewSiz,FALSE));
            IF ((OldSiz - NewSiz) > 0) THEN
              Star('Space saved              : '+ConvertBytes(OldSiz - NewSiz,FALSE))
            ELSE
              Star('Space wasted             : '+ConvertBytes(NewSiz - OldSiz,FALSE));
          END;

        END;
      END;
      WKey;
      NRecNo(FileInfo,DirFileRecNum);
    END;
    Close(FileInfoFile);
    Close(ExtInfoFile);
  END;
  LastError := IOResult;
END;

PROCEDURE ReZipStuff;
TYPE
  TotalsRecordType = RECORD
    TotalFiles: Integer;
    TotalOldSize,
    TotalNewSize: LongInt
  END;
VAR
  TotalsRecord: TotalsRecordType;
  FileName: Str12;
  ReZipCmd: Str78;
  FArea,
  SaveFileArea: Integer;
BEGIN
  FillChar(TotalsRecord,SizeOf(TotalsRecord),0);
  NL;
  Print('Re-compress archives -');
  NL;
  Print('Filespec:');
  Prt(':');
  InputMain(FileName,SizeOf(FileName)-1,[CapAll]);
  IF (FileName = '') THEN
  BEGIN
    NL;
    Print('Aborted!');
    Exit;
  END;
  ReZipCmd := '';
  NL;
  Print('^8Do you wish to use a REZIP external utility?');
  IF PYNQ('(such as REZIP.EXE)? (Y/N): ',0,FALSE) THEN
  BEGIN
    NL;
    Print('Enter commandline (example: "REZIP"): ');
    Prt(':');
    InputMain(ReZipCmd,SizeOf(ReZipCmd)-1,[CapAll]);
    IF (ReZipCmd = '') THEN
    BEGIN
      NL;
      Print('Aborted.');
      Exit;
    END;
  END;
  NL;
  Print('Conversion process initiated: '+DateStr+' '+TimeStr+'.');
  SysOpLog('Conversion process initiated: '+DateStr+' '+TimeStr+'.');
  NL;
  Abort := FALSE;
  Next := FALSE;
  IF NOT PYNQ('Search all file areas? ',0,FALSE) THEN
    CvtFiles(FileArea,FileName,ReZipCmd,TotalsRecord.TotalFiles,TotalsRecord.TotalOldSize,TotalsRecord.TotalNewSize)
  ELSE
  BEGIN
    SaveFileArea := FileArea;
    FArea := 1;
    WHILE (FArea >= 1) AND (FArea <= NumFileAreas) AND (NOT Abort) AND (NOT HangUp) DO
    BEGIN
      CvtFiles(FArea,FileName,ReZipCmd,TotalsRecord.TotalFiles,TotalsRecord.TotalOldSize,TotalsRecord.TotalNewSize);
      WKey;
      Inc(FArea);
    END;
    FileArea := SaveFileArea;
    LoadFileArea(FileArea);
  END;
  NL;
  Print('Conversion process complete at '+DateStr+' '+TimeStr+'.');
  SysOpLog('Conversion process complete at '+DateStr+' '+TimeStr+'.');
  NL;
  Star('Total archives converted : '+IntToStr(TotalsRecord.TotalFiles));
  Star('Old total space took up  : '+ConvertBytes(TotalsRecord.TotalOldSize,FALSE));
  Star('New total space taken up : '+ConvertBytes(TotalsRecord.TotalNewSize,FALSE));

  IF ((TotalsRecord.TotalOldSize - TotalsRecord.TotalNewSize) > 0) THEN
    Star('Space saved              : '+ConvertBytes(TotalsRecord.TotalOldSize - TotalsRecord.TotalNewSize,FALSE))
  ELSE
    Star('Space wasted             : '+ConvertBytes(TotalsRecord.TotalNewSize - TotalsRecord.TotalOldSize,FALSE));


  SysOpLog('Converted '+IntToStr(TotalsRecord.TotalFiles)+' archives; old size='+
           ConvertBytes(TotalsRecord.TotalOldSize,FALSE)+' , new size='+ConvertBytes(TotalsRecord.TotalNewSize,FALSE));
END;

{ Archive2 implementation }
CONST
  MaxDOSChrLine = 127;

PROCEDURE DOArcCommand(Cmd: Char);
CONST
  MaxFiles = 100;
VAR
  FI: FILE OF Byte;
  FileListArray: ARRAY [1..MaxFiles] OF AStr;
  F: FileInfoRecordType;
  (*
  DirInfo: SearchRec;
  *)
  FileName,
  S,
  S1,
  S2,
  OS1: AStr;
  DS: DirStr;
  NS: NameStr;
  ES: ExtStr;
  AType,
  BB,
  NumExtDesc,
  NumFiles,
  RecNum,
  Counter: Byte;
  Junk,
  RN,
  FArea,
  SaveFileArea,
  C_Files: Integer;
  C_OldSiz,
  C_NewSiz,
  OldSiz,
  NewSiz: LongInt;
  Ok,
  Ok1,
  FNX,
  WentToSysOp,
  DelBad: Boolean;

  PROCEDURE AddFL(F1: FileInfoRecordType; FN1: AStr; VAR NumFiles1: Byte; b: Boolean);
  VAR
    DirInfo1: SearchRec;
    DS1: DirStr;
    NS1: NameStr;
    ES1: ExtStr;
    SaveNumFiles: Byte;
    RN1: Integer;
  BEGIN
    SaveNumFiles := NumFiles1;
    IF (NOT b) THEN
    BEGIN
      RecNo(F1,FN1,RN1);
      IF (BadDownloadPath) THEN
        Exit;
      WHILE (RN1 <> -1) AND (NumFiles1 < MaxFiles) DO
      BEGIN
        Seek(FileInfoFile,RN1);
        Read(FileInfoFile,F1);
        Inc(NumFiles1);
        FileListArray[NumFiles1] := F1.FileName;
        NRecNo(F1,RN1);
      END;
    END
    ELSE
    BEGIN
      FSplit(FN1,DS1,NS1,ES1);
      ChDir(BSlash(DS1,FALSE));
      IF (IOResult <> 0) THEN
        Print('Path not found.')
      ELSE
      BEGIN
        FindFirst(FN1,AnyFile - Directory - VolumeID - Dos.Hidden - SysFile,DirInfo1);
        WHILE (DOSError = 0) AND (NumFiles1 < MaxFiles) DO
        BEGIN
          Inc(NumFiles1);
          FileListArray[NumFiles1] := FExpand(DS1+DirInfo1.Name);
          FindNext(DirInfo1);
        END;
      END;
      ChDir(StartDir);
    END;
    IF (NumFiles1 = SaveNumFiles) THEN
      Print('No matching files.')
    ELSE IF (NumFiles1 >= MaxFiles) THEN
      Print('File records filled.');
  END;

  PROCEDURE TestFiles(F1: FileInfoRecordType; FArea1: Integer; FN1: AStr; DelBad1: Boolean);
  VAR
    AType1: Byte;
    RN1: Integer;
    Ok2: Boolean;
  BEGIN
    IF (FileArea <> FArea1) THEN
      ChangeFileArea(FArea1);
    IF (FileArea = FArea1) THEN
    BEGIN
      RecNo(F1,FN1,RN1);
      IF (BadDownloadPath) THEN
        Exit;
      WHILE (RN1 <> -1) AND (NOT Abort) AND (NOT HangUp) DO
      BEGIN
        Seek(FileInfoFile,RN1);
        Read(FileInfoFile,F1);
        IF Exist(MemFileArea.DLPath+F1.FileName) THEN
          FN1 := MemFileArea.DLPath+F1.FileName
        ELSE
          FN1 := MemFileArea.ULPath+F1.FileName;
        AType1 := ArcType(FN1);
        IF (AType1 <> 0) THEN
        BEGIN
          DisplayFileAreaHeader;
          Star('Testing "'+SQOutSP(FN1)+'"');
          IF (NOT Exist(FN1)) THEN
            Star('File "'+SQOutSP(FN1)+'" does not exist.')
          ELSE
          BEGIN
            Ok2 := TRUE;
            ArcIntegrityTest(Ok2,AType1,SQOutSP(FN1));
            IF (NOT Ok2) THEN
            BEGIN
              Star('File "'+SQOutSP(FN1)+'" did not pass integrity test.');
              IF (DelBad1) THEN
              BEGIN
                DeleteFF(F1,RN1);
                Kill(FN1);
              END;
            END;
          END;
        END;
        WKey;
        NRecNo(F1,RN1);
      END;
      Close(FileInfoFile);
      Close(ExtInfoFile);
    END;
    LastError := IOResult;
  END;

  PROCEDURE CmtFiles(F1: FileInfoRecordType; FArea1: Integer; FN1: AStr);
  VAR
    AType1: Byte;
    RN1: Integer;
    Ok2: Boolean;
  BEGIN
    IF (FileArea <> FArea1) THEN
      ChangeFileArea(FArea1);
    IF (FileArea = FArea1) THEN
    BEGIN
      RecNo(F1,FN1,RN1);
      IF (BadDownloadPath) THEN
        Exit;
      WHILE (RN1 <> -1) AND (NOT Abort) AND (NOT HangUp) DO
      BEGIN
        Seek(FileInfoFile,RN1);
        Read(FileInfoFile,F1);
        IF Exist(MemFileArea.DLPath+F1.FileName) THEN
          FN1 := MemFileArea.DLPath+F1.FileName
        ELSE
          FN1 := MemFileArea.ULPath+F1.FileName;
        AType1 := ArcType(FN1);
        IF (AType1 <> 0) THEN
        BEGIN
          DisplayFileAreaHeader;
          NL;
          Star('Commenting "'+SQOutSP(FN1)+'"');
          IF (NOT Exist(FN1)) THEN
            Star('File "'+SQOutSP(FN1)+'" does not exist.')
          ELSE
          BEGIN
            Ok2 := TRUE;
            ArcComment(Ok2,AType1,MemFileArea.CmtType,SQOutSP(FN1));
            (* If NOT Ok *)

          END;
        END;
        WKey;
        NRecNo(F1,RN1);
      END;
      Close(FileInfoFile);
      Close(ExtInfoFile);
    END;
    LastError := IOResult;
  END;

  PROCEDURE CvtFiles(F1: FileInfoRecordType;
                     FArea1: Integer;
                     FN1: AStr;
                     Toa: Integer;
                     VAR C_Files1: Integer;
                     VAR C_OldSiz1,
                     C_NewSiz1: LongInt);
  VAR
    FI: FILE OF Byte;
    S3: AStr;
    AType1: Byte;
    RN1: Integer;
    Ok2: Boolean;
  BEGIN
    IF (FileArea <> FArea1) THEN
      ChangeFileArea(FArea1);
    IF (FileArea = FArea1) THEN
    BEGIN
      RecNo(F1,FN1,RN1);
      IF (BadDownloadPath) THEN
        Exit;
      WHILE (RN1 <> -1) AND (NOT Abort) AND (NOT HangUp) DO
      BEGIN
        Seek(FileInfoFile,RN1);
        Read(FileInfoFile,F1);
        IF Exist(MemFileArea.DLPath+F1.FileName) THEN
          FN1 := MemFileArea.DLPath+F1.FileName
        ELSE
          FN1 := MemFileArea.ULPath+F1.FileName;
        AType1 := ArcType(FN1);
        IF (AType1 <> 0) AND (AType1 <> Toa) THEN
        BEGIN
          DisplayFileAreaHeader;
          NL;
          Star('Converting "'+SQOutSP(FN1)+'"');
          Ok2 := FALSE;
          IF (NOT Exist(FN1)) THEN
          BEGIN
            Star('File "'+SQOutSP(FN1)+'" does not exist - changing extension.');
            S3 := Copy(FN1,1,Pos('.',FN1))+General.FileArcInfo[Toa].Ext;
            F1.FileName := Align(StripName(SQOutSP(S3)));
            Seek(FileInfoFile,RN1);
            Write(FileInfoFile,F1);
          END
          ELSE
          BEGIN
            Ok2 := TRUE;
            S3 := Copy(FN1,1,Pos('.',FN1))+General.FileArcInfo[Toa].Ext;
            ConvA(Ok2,AType1,BB,SQOutSP(FN1),SQOutSP(S3));
            IF (Ok2) THEN
            BEGIN

              Assign(FI,SQOutSP(FN1));
              Reset(FI);
              Ok2 := (IOResult = 0);
              IF (Ok2) THEN
              BEGIN
                OldSiz := FileSize(FI);
                Close(FI);
              END
              ELSE
                Star('Unable to access "'+SQOutSP(FN1)+'"');

              IF (Ok2) THEN
                IF (NOT Exist(SQOutSP(S3))) THEN
                BEGIN
                  Star('Unable to access "'+SQOutSP(S3)+'"');
                  SysOpLog('Unable to access '+SQOutSP(S3));
                  Ok2 := FALSE;
                END;
            END;

            IF (Ok2) THEN
            BEGIN
              F1.FileName := Align(StripName(SQOutSP(S3)));
              Seek(FileInfoFile,RN1);
              Write(FileInfoFile,F1);

              Kill(SQOutSP(FN1));

              Assign(FI,SQOutSP(S3));
              Reset(FI);
              Ok2 := (IOResult = 0);
              IF (NOT Ok2) THEN
              BEGIN
                Star('Unable to access '+SQOutSP(S3));
                SysOpLog('Unable to access '+SQOutSP(S3));
              END
              ELSE
              BEGIN
                NewSiz := FileSize(FI);
                F1.FileSize := NewSiz;
                Close(FI);
                Seek(FileInfoFile,RN1);
                Write(FileInfoFile,F1);
              END;

              IF (Ok2) THEN
              BEGIN
                Inc(C_OldSiz1,OldSiz);
                Inc(C_NewSiz1,NewSiz);
                Inc(C_Files1);
                Star('Old total space took up  : '+ConvertBytes(OldSiz,FALSE));
                Star('New total space taken up : '+ConvertBytes(NewSiz,FALSE));
                IF (OldSiz - NewSiz > 0) THEN
                  Star('Space saved              : '+ConvertBytes(OldSiz-NewSiz,FALSE))
                ELSE
                  Star('Space wasted             : '+ConvertBytes(NewSiz-OldSiz,FALSE));
              END;
            END
            ELSE
            BEGIN
              SysOpLog('Unable to convert '+SQOutSP(FN1));
              Star('Unable to convert '+SQOutSP(FN1));
            END;
          END;
        END;
        WKey;
        NRecNo(F,RN1);
      END;
      Close(FileInfoFile);
      Close(ExtInfoFile);
    END;
    LastError := IOResult;
  END;

BEGIN
  TempPause := FALSE;
  SaveFileArea := FileArea;
  InitFileArea(FileArea);
  IF (BadDownloadPath) THEN
    Exit;
  CASE Cmd OF
    'A' : BEGIN
            NL;
            Print('Add file(s) to archive (up to '+IntToStr(MaxFiles)+') -');
            NL;
            Print('Archive file name: ');
            Prt(':');
            InputMain(FileName,78,[CapAll]);

            IF IsUL(FileName) AND (NOT FileSysOp) THEN
              FileName := '';

            IF (FileName = '') THEN
            BEGIN
              NL;
              Print('Aborted!');
            END
            ELSE
            BEGIN
              NumFiles := 0;
              IF (Pos('.',FileName) = 0) AND (MemFileArea.ArcType <> 0) THEN
                FileName := FileName+'.'+General.FileArcInfo[MemFileArea.ArcType].Ext;
              FNX := ISUL(FileName);
              IF (NOT FNX) THEN
              BEGIN
                IF Exist(MemFileArea.DLPath+FileName) THEN
                  FileName := MemFileArea.DLPath+FileName
                ELSE
                  FileName := MemFileArea.ULPath+FileName
              END;
              FileName := FExpand(FileName);
              AType := ArcType(FileName);
              IF (AType = 0) THEN
                InvArc
              ELSE
              BEGIN
                Cmd := 'A';
                REPEAT
                  IF (Cmd = 'A') THEN
                    REPEAT
                      NL;
                      Print('Add files to list - <CR> to end');
                      Prt(IntToStr(NumFiles + 1)+':');
                      InputMain(S,70,[CapAll]);
                      IF (S <> '') AND (NOT IsUL(S) OR FileSysOp) THEN
                      BEGIN
                        IF (Pos('.',S) = 0) THEN
                          S := S + '*.*';
                        AddFL(F,S,NumFiles,IsUL(S));
                      END;
                    UNTIL (S = '') OR (NumFiles >= MaxFiles) OR (HangUp);
                  NL;
                  InputChar('Add files to list [^1?^2=^1Help^2]: ',Cmd,'QADLR?',[CapAll]);
                  NL;
                  CASE Cmd OF
                    '?' : BEGIN
                            LCmds(19,1,'Add more to list','Do it!');
                            LCmds(19,1,'List files in list','Remove files from list');
                            LCmds(19,1,'Quit','');
                          END;
                    'D' : BEGIN
                            RecNum := 0;
                            REPEAT
                              Inc(RecNum);
                              Counter := 1;
                              S2 := SQOutSP(FileListArray[RecNum]);
                              IF (NOT IsUL(S2)) THEN
                                S2 := MemFileArea.DLPath+S2;
                              S1 := FunctionalMCI(General.FileArcInfo[AType].ArcLine,FileName,S2);
                              OS1 := S1;
                              WHILE (Length(S1) <= MaxDOSChrLine) AND (RecNum < NumFiles) DO
                              BEGIN
                                Inc(RecNum);
                                Inc(Counter);
                                S2 := SQOutSP(FileListArray[RecNum]);
                                IF (NOT IsUL(S2)) THEN
                                  S2 := MemFileArea.DLPath+S2;
                                OS1 := S1;
                                S1 := S1+' '+S2;
                              END;
                              IF (Length(S1) > MaxDOSChrLine) THEN
                              BEGIN
                                Dec(RecNum);
                                Dec(Counter);
                                S1 := OS1;
                              END;
                              Ok := TRUE;
                              Star('Adding '+IntToStr(Counter)+' files to archive...');
                              ExecBatch(Ok,
                                        TempDir+'UP\',General.ArcsPath+S1,
                                        General.FileArcInfo[AType].SuccLevel,Junk,FALSE);
                              IF (NOT Ok) THEN
                              BEGIN
                                Star('errors in adding files');
                                Ok := PYNQ('Continue anyway? ',0,FALSE);
                                IF (HangUp) THEN
                                  Ok := FALSE;
                              END;
                            UNTIL (RecNum >= NumFiles) OR (NOT Ok);
                            ArcComment(Ok,AType,MemFileArea.CmtType,FileName);
                            NL;
                            IF (NOT FNX) THEN
                            BEGIN
                              S1 := StripName(FileName);
                              RecNo(F,S1,RN);
                              IF (BadDownloadPath) THEN
                                Exit;
                              IF (RN <> -1) THEN
                                Print('^1NOTE: File already exists in listing!');
                              IF PYNQ('Add archive to listing? ',0,FALSE) THEN
                              BEGIN

                                Assign(FI,FileName);
                                Reset(FI);
                                IF (IOResult = 0) THEN
                                BEGIN
                                  F.fileSize := FileSize(FI);
                                  Close(FI);
                                END;

                                F.FileName := Align(S1);
                                Ok1 := TRUE;
                                IF PYNQ('Replace a file in directory? ',0,FALSE) THEN
                                BEGIN
                                  REPEAT
                                    NL;
                                    Prt('Enter file name: ');
                                    InputMain(S2,12,[CapAll]);
                                    IF (S2 = '') THEN
                                    BEGIN
                                      NL;
                                      Print('Aborted!');
                                    END
                                    ELSE
                                    BEGIN
                                      RecNo(F,S2,RN);
                                      IF (BadDownloadPath) THEN
                                        Exit;
                                      IF (RN = -1) THEN
                                        Print('File not found!');
                                    END;
                                  UNTIL (RN <> -1) OR (S2 = '') OR (HangUp);
                                  IF (S2 <> '') THEN
                                  BEGIN
                                    Seek(FileInfoFile,RN);
                                    Read(FileInfoFile,F);
                                    Kill(MemFileArea.ULPath+SQOutSP(F.FileName));
                                    F.FileName := Align(S1);
                                    Seek(FileInfoFile,RN);
                                    Write(FileInfoFile,F);
                                  END
                                  ELSE
                                    Ok1 := FALSE;
                                END
                                ELSE
                                  Ok1 := FALSE;
                                IF (NOT Ok1) THEN
                                BEGIN
                                  WentToSysOp := FALSE;
                                  GetFileDescription(F,ExtendedArray,NumExtDesc,WentToSysOp);
                                  F.FilePoints := 0;
                                  F.Downloaded := 0;
                                  F.OwnerNum := UserNum;
                                  F.OwnerName := AllCaps(ThisUser.Name);
                                  F.FileDate := Date2PD(DateStr);
                                  F.VPointer := -1;
                                  F.VTextSize := 0;
                                END;
                                F.FIFlags := [];

                                IF (NOT AACS(General.ULValReq)) AND (NOT General.ValidateAllFiles) THEN
                                  Include(F.FIFlags,FINotVal);

                                IF (NOT General.FileCreditRatio) THEN
                                  F.FilePoints := 0
                                ELSE
                                  F.FilePoints := ((F.FileSize DIV 1024) DIV General.FileCreditCompBaseSize);

                                IF (RN = -1) THEN
                                  WriteFV(F,FileSize(FileInfoFile),ExtendedArray)
                                ELSE
                                  WriteFV(F,RN,ExtendedArray);
                              END;
                            END;
                            IF PYNQ('Delete original files? ',0,FALSE) THEN
                              FOR RecNum := 1 TO NumFiles DO
                              BEGIN
                                S2 := SQOutSP(FileListArray[RecNum]);
                                IF (NOT IsUL(FileListArray[RecNum])) THEN
                                BEGIN
                                  RecNo(F,S2,RN);
                                  IF (BadDownloadPath) THEN
                                    Exit;
                                  IF (RN <> -1) THEN
                                    DeleteFF(F,RN);
                                  S2 := MemFileArea.DLPath+S2;
                                END;
                                Kill(S2);
                              END;
                            IF (Ok) THEN
                             Cmd := 'Q';
                          END;
                    'L' : IF (NumFiles = 0) THEN
                            Print('No files in list!')
                          ELSE
                          BEGIN
                            Abort := FALSE;
                            Next := FALSE;
                            S := '';
                            Counter := 0;
                            RecNum := 0;
                            REPEAT
                              Inc(RecNum);
                              IF IsUL(FileListArray[RecNum]) THEN
                                S := S + '^1'
                              ELSE
                                S := S + '^0';
                              S := S + Align(StripName(FileListArray[RecNum]));
                              Inc(Counter);
                              IF (Counter < 5) THEN
                                S := S + '    '
                              ELSE
                              BEGIN
                                PrintACR(S);
                                S := '';
                                Counter := 0;
                              END;
                            UNTIL (RecNum = NumFiles) OR (Abort) OR (HangUp);
                            IF (Counter in [1..4]) AND (NOT Abort) THEN
                              PrintACR(S);
                          END;
                    'R' : IF (NumFiles = 0) THEN
                            Print('No files in list!')
                          ELSE
                          BEGIN
                            Prt('Remove file name: ');
                            InputMain(S,12,[CapAll]);
                            IF (S = '') THEN
                            BEGIN
                              NL;
                              Print('Aborted!');
                            END
                            ELSE
                            BEGIN
                              RecNum := 0;
                              REPEAT
                                Inc(RecNum);
                                IF Align(StripName(FileListArray[RecNum])) = Align(S) THEN
                                BEGIN
                                  Prompt('^1'+SQOutSP(FileListArray[RecNum]));
                                  IF PYNQ('   Remove it? ',0,FALSE) THEN
                                  BEGIN
                                    FOR Counter := RecNum TO (NumFiles - 1) DO
                                      FileListArray[Counter] := FileListArray[Counter + 1];
                                    Dec(NumFiles);
                                    Dec(RecNum);
                                  END;
                                END;
                              UNTIL (RecNum >= NumFiles);
                            END;
                          END;
                  END;
                UNTIL (Cmd = 'Q') OR (HangUp);
                Cmd := #0;
              END;
            END;
          END;
    'C' : BEGIN
            NL;
            Print('Convert archive formats -');
            NL;
            Print('Filespec:');
            Prt(':');
            InputMain(FileName,78,[CapAll]);
            IF (FileName = '') THEN
            BEGIN
              NL;
              Print('Aborted!');
            END
            ELSE
            BEGIN

              NL;
              REPEAT
                Prt('Archive type to use? (?=List): ');
                InputMain(S,3,[CapAll]);
                IF (S = '?') THEN
                BEGIN
                  NL;
                  ListArcTypes;
                  NL;
                END;
              UNTIL (S <> '?');

              IF (StrToInt(S) <> 0) THEN
                BB := StrToInt(S)
              ELSE
                BB := ArcType('F.'+S);

              IF (BB <> 0) THEN
              BEGIN
                C_Files := 0;
                C_OldSiz := 0;
                C_NewSiz := 0;
                Abort := FALSE;
                Next := FALSE;
                SysOpLog('Conversion process initiated at '+DateStr+' '+TimeStr+'.');
                IF (IsUL(FileName)) THEN
                BEGIN
                  FSplit(FileName,DS,NS,ES);
                  FindFirst(FileName,AnyFile - Directory - VolumeID - Dos.Hidden - SysFile,DirInfo);
                  WHILE (DOSError = 0) AND (NOT Abort) AND (NOT HangUp) DO
                  BEGIN
                    FileName := FExpand(SQOutSP(DS+DirInfo.Name));
                    AType := ArcType(FileName);
                    IF (AType <> 0) AND (AType <> BB) THEN
                    BEGIN
                      Star('Converting "'+FileName+'"');
                      Ok := TRUE;
                      S := Copy(FileName,1,Pos('.',FileName))+General.FileArcInfo[BB].Ext;
                      ConvA(Ok,AType,BB,FileName,S);
                      IF (Ok) THEN
                      BEGIN

                        Assign(FI,SQOutSP(FileName));
                        Reset(FI);
                        Ok := (IOResult = 0);
                        IF (Ok) THEN
                        BEGIN
                          OldSiz := FileSize(FI);
                          Close(FI);
                        END
                        ELSE
                          Star('Unable to access '+SQOutSP(FileName));

                        IF (Ok) THEN
                          IF (NOT Exist(SQOutSP(S))) THEN
                          BEGIN
                            Star('Unable to access '+SQOutSP(S));
                            SysOpLog('Unable to access '+SQOutSP(S));
                            Ok := FALSE;
                          END;
                      END;
                      IF (Ok) THEN
                      BEGIN
                        Kill(SQOutSP(FileName));

                        Assign(FI,SQOutSP(S));
                        Reset(FI);
                        Ok := (IOResult = 0);
                        IF (Ok) THEN
                        BEGIN
                          NewSiz := FileSize(FI);
                          Close(FI);
                        END
                        ELSE
                          Star('Unable to access "'+SQOutSP(S)+'"');

                        IF (Ok) THEN
                        BEGIN
                          Inc(C_OldSiz,OldSiz);
                          Inc(C_NewSiz,NewSiz);
                          Inc(C_Files);
                          Star('Old total space took up  : '+ConvertBytes(OldSiz,FALSE));
                          Star('New total space taken up : '+ConvertBytes(NewSiz,FALSE));
                          IF (OldSiz - NewSiz > 0) THEN
                            Star('Space saved              : '+ConvertBytes(OldSiz-NewSiz,FALSE))
                          ELSE
                            Star('Space wasted             : '+ConvertBytes(NewSiz-OldSiz,FALSE));
                        END;
                      END
                      ELSE
                      BEGIN
                        SysOpLog('Unable to convert '+SQOutSP(FileName));
                        Star('Unable to convert '+SQOutSP(FileName));
                      END;
                    END;
                    WKey;
                    FindNext(DirInfo);
                  END;
                END
                ELSE
                BEGIN
                  NL;
                  IF (NOT PYNQ('Search all file areas? ',0,FALSE)) THEN
                    CvtFiles(F,FileArea,FileName,BB,C_Files,C_OldSiz,C_NewSiz)
                  ELSE
                  BEGIN
                    FArea := 1;
                    WHILE (FArea >= 1) AND (FArea <= NumFileAreas) AND (NOT Abort) AND (NOT HangUp) DO
                    BEGIN
                      CvtFiles(F,FArea,FileName,BB,C_Files,C_OldSiz,C_NewSiz);
                      WKey;
                      Inc(FArea);
                    END;
                  END;
                END;
                SysOpLog('Conversion process completed at '+DateStr+' '+TimeStr+'.');
                NL;
                Star('Total archives converted : '+IntToStr(C_Files));
                Star('Old total space took up  : '+ConvertBytes(C_OldSiz,FALSE));
                Star('New total space taken up : '+ConvertBytes(C_NewSiz,FALSE));
                IF ((C_OldSiz - C_NewSiz) > 0) THEN
                  Star('Space saved              : '+ConvertBytes((C_OldSiz - C_NewSiz),FALSE))
                ELSE
                  Star('Space wasted             : '+ConvertBytes((C_NewSiz - C_OldSiz),FALSE));
                SysOpLog('Converted '+IntToStr(C_Files)+' archives; old size='+
                         ConvertBytes(C_OldSiz,FALSE)+' , new size='+ConvertBytes(C_NewSiz,FALSE));
              END;
            END;
          END;
    'M' : BEGIN
            Ok := FALSE;
            FOR Counter := 1 TO 3 DO
              IF (General.FileArcComment[Counter] <> '') THEN
                Ok := TRUE;

            IF (NOT Ok) THEN
            BEGIN
              NL;
              Print('No comment''s are available.');
              PauseScr(FALSE);
              Exit;
            END;

            NL;
            Print('Comment field update -');
            NL;
            Print('Filespec:');
            Prt(':');
            InputMain(FileName,78,[CapAll]);
            IF (FileName = '') THEN
            BEGIN
              NL;
              Print('Aborted!');
            END
            ELSE
            BEGIN
              Abort := FALSE;
              Next := FALSE;
              IF (IsUL(FileName)) THEN
              BEGIN

                S := '';
                NL;
                FOR Counter := 1 TO 3 DO
                  IF (General.FileArcComment[Counter] <> '') THEN
                  BEGIN
                    S := S + IntToStr(Counter);
                    Print('^0'+IntToStr(Counter)+'. Archive comment file: ^1'+General.FileArcComment[Counter]);
                  END;
                NL;
                InputChar('Comment to use [0=Quit]: ',Cmd,'0'+S,[CapAll]);

                IF (Cmd IN ['1'..'3']) THEN
                BEGIN
                  FSplit(FileName,DS,NS,ES);
                  FindFirst(FileName,AnyFile - Directory - VolumeID - Dos.Hidden - SysFile,DirInfo);
                  WHILE (DOSError = 0) AND (NOT Abort) AND (NOT HangUp) DO
                  BEGIN
                    FileName := FExpand(SQOutSP(DS+DirInfo.Name));
                    AType := ArcType(FileName);
                    IF (AType <> 0) THEN
                    BEGIN
                      Star('Commenting "'+FileName+'"');
                      Ok := TRUE;
                      ArcComment(Ok,AType,(Ord(Cmd) - 48),FileName);
                    END;
                    WKey;
                    FindNext(DirInfo);
                  END;
                END;
              END
              ELSE
              BEGIN
                NL;
                IF (NOT PYNQ('Search all file areas? ',0,FALSE)) THEN
                  CmtFiles(F,FileArea,FileName)
                ELSE
                BEGIN
                  FArea := 1;
                  WHILE (FArea >= 1) AND (FArea <= NumFileAreas) AND (NOT Abort) AND (NOT HangUp) DO
                  BEGIN
                    CmtFiles(F,FArea,FileName);
                    WKey;
                    Inc(FArea);
                  END;
                END;
              END;
            END;
            Cmd := #0;
          END;
    'T' : BEGIN
            NL;
            Print('File integrity testing -');
            NL;
            Print('Filespec:');
            Prt(':');
            InputMain(FileName,78,[CapAll]);
            IF (FileName = '') THEN
            BEGIN
              NL;
              Print('Aborted!');
            END
            ELSE
            BEGIN
              NL;
              DelBad := PYNQ('Delete files that don''t pass the test? ',0,FALSE);
              NL;
              Abort := FALSE;
              Next := FALSE;
              IF (IsUL(FileName)) THEN
              BEGIN
                FSplit(FileName,DS,NS,ES);
                FindFirst(FileName,AnyFile - Directory - VolumeID - DOS.Hidden - SysFile,DirInfo);
                WHILE (DOSError = 0) AND (NOT Abort) AND (NOT HangUp) DO
                BEGIN
                  FileName := FExpand(SQOutSP(DS+DirInfo.Name));
                  AType := ArcType(FileName);
                  IF (AType <> 0) THEN
                  BEGIN
                    Star('Testing "'+FileName+'"');
                    Ok := TRUE;
                    ArcIntegrityTest(Ok,AType,FileName);
                    IF (Ok) THEN
                      Star('Passed integrity test.')
                    ELSE
                    BEGIN
                      Star('File "'+FileName+'" didn''t pass integrity test.');
                      IF (DelBad) THEN
                        Kill(FileName);
                    END;
                  END;
                  WKey;
                  FindNext(DirInfo);
                END;
              END
              ELSE
              BEGIN
                NL;
                IF (NOT PYNQ('Search all file areas? ',0,FALSE)) THEN
                  TestFiles(F,FileArea,FileName,DelBad)
                ELSE
                BEGIN
                  FArea := 1;
                  WHILE (FArea >= 1) AND (FArea <= NumFileAreas) AND (NOT Abort) AND (NOT HangUp) DO
                  BEGIN
                    TestFiles(F,FArea,FileName,DelBad);
                    WKey;
                    Inc(FArea);
                  END;
                END;
              END;
            END;
          END;
  END;
  FileArea := SaveFileArea;
  LoadFileArea(FileArea);
  LastError := IOResult;
END;

END.