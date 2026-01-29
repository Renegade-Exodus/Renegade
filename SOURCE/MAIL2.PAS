{$A+,B-,D+,E-,F+,I-,L+,N-,O+,R-,S+,V-}
UNIT Mail2;

INTERFACE

USES
  Common;

PROCEDURE Post(ReplyTo: LongInt; VAR TToI: FromToInfo; PvtMsg: Boolean);


{---------------------------------------------------------------------------}
{ Lightbar message selector (READP prompt #13)                              }
{ Allows arrow-key selection + ENTER, or typing a message # directly.       }
{---------------------------------------------------------------------------}
PROCEDURE SelectMsgLightBar(VAR MsgNum: Word; HiMsg: Word; Pub: Boolean);

PROCEDURE ReadAllMessages(MenuOption: Str50);
PROCEDURE ScanMessages(MArea: Integer; AskUpDate: Boolean; MenuOption: Str50);
PROCEDURE StartNewScan(MenuOption: Str50);
PROCEDURE ScanYours;
FUNCTION FirstNew: Word;

IMPLEMENTATION

USES
  Crt,
  Dos,
  Common5,
  Mail0,
  Mail1,
  EMail,
  Mail3,
  Menus,
  ShortMsg,
  SysOp2G,
  SysOp3,
  TimeFunc;

{ TP7 helper: Delphi-style StrToInt replacement }
FUNCTION StrToInt(SS: STRING): LongInt;
VAR
  V: LongInt;
  Code: Integer;
BEGIN
  Val(SS, V, Code);
  IF (Code <> 0) THEN
    V := 0;
  StrToInt := V;
END;


PROCEDURE RL_FlushKeys;
BEGIN
  { Flush any pending keystrokes so ENTER used to select a message }
  { does not get consumed by ReadMsg's page-break prompt (Y/N/C). }
  WHILE KeyPressed DO
    ReadKey;

  { Drain Renegade's unified input queue (keyboard + remote).      }
  { InKey returns 0 when no key is pending; GetKey consumes keys.  }
  WHILE (InKey <> 0) DO
    GetKey;
END;

VAR
  TempLastRead: LongInt;

  RL_EscPressed: Boolean; { TRUE if user hit ESC in RL lightbar }
  RL_IgnoreRemaining: Boolean; { TRUE if user hit I in RL lightbar (Ignore Remaining) }
  MsgSel_EscPressed: Boolean; { TRUE if user cancelled SelectMsgLightBar (ESC/Q) }
  MsgSel_IgnoreRemaining: Boolean; { TRUE if user hit I in SelectMsgLightBar (Ignore Remaining) }
  JumpMode: Boolean; { Numeric jump active only after J }
{---------------------------------------------------------------------------}
{ Lightbar message selector (READP prompt #13)                               }
{ Allows arrow-key selection + ENTER, or typing a message # directly.        }
{---------------------------------------------------------------------------}
PROCEDURE SelectMsgLightBar(VAR MsgNum: Word; HiMsg: Word; Pub: Boolean);
VAR
  MHeader: MHeaderRec;
  ADate: DateTime;
  PerPage: Byte;
  StartMsg: Word;
  CurIdx: Byte;
  Count: Byte;
  MsgList: ARRAY[1..25] OF Word;
  LineY: ARRAY[1..25] OF Byte;
  BaseY: Byte;
  W: Word;
  C: Char;
  S, S1, InStr: AStr;
  Changed: Boolean;
  V: Integer;
  Code: Integer;

  PROCEDURE BuildLine(MN: Word; VAR OutS: AStr);
  VAR
    StatusCh: Char;
    FromS, ToS, SubjS: AStr;
  JumpMode: Boolean;
  BEGIN
    LoadHeader(MN,MHeader);

    IF (MDeleted IN MHeader.Status) THEN
      StatusCh := 'D'
    ELSE IF (UnValidated IN MHeader.Status) THEN
      StatusCh := 'U'
    ELSE IF (ToYou(MHeader) OR FromYou(MHeader)) THEN
      StatusCh := '>'
    ELSE IF (Pub) AND (TempLastRead < MHeader.Date) THEN
      StatusCh := '*'
    ELSE
      StatusCh := ' ';

    IF (MARealName IN MemMsgArea.MAFlags) THEN
      FromS := UseName(MHeader.From.Anon,MHeader.From.Real)
    ELSE
      FromS := UseName(MHeader.From.Anon,MHeader.From.A1S);

    IF ((MARealName IN MemMsgArea.MAFlags) AND (MHeader.MTo.Real <> '')) THEN
      ToS := UseName(MHeader.MTo.Anon,MHeader.MTo.Real)
    ELSE
      ToS := UseName(MHeader.MTo.Anon,MHeader.MTo.A1S);

    IF (MHeader.FileAttached = 0) THEN
      SubjS := MHeader.Subject
    ELSE
      SubjS := StripName(MHeader.Subject);

    PackToDate(ADate,MHeader.Date);

    OutS := StatusCh+' '+PadLeftInt(MN,5)+' '+
            PadLeftStr(FromS,18)+' '+
            PadLeftStr(ToS,18)+' '+
            PadLeftStr(SubjS,18)+' '+
            ZeroPad(IntToStr(ADate.Month))+'/'+ZeroPad(IntToStr(ADate.Day))+'/'+ZeroPad(IntToStr(ADate.Year));
  END;

  PROCEDURE PadRight(VAR SS: AStr; N: Byte); FORWARD;

  PROCEDURE DrawLine(I: Byte; Selected: Boolean);
  VAR
    L: AStr;
    S2: AStr;
    S3: AStr;
  BEGIN
    BuildLine(MsgList[I],L);

    { hard guard }
    IF (Length(L) < 2) THEN
      L := L + '  ';

    { Never paint columns 1-2: do not clear or print there. }
    { Clear from column 3 to end-of-line only (ANSI safe) }
    ANSIG(3,LineY[I]);
    Prompt(#27'[0m');
    Prompt(#27'[0K');
    ANSIG(3,LineY[I]);

    { Lightbar starts at column 3 and ends at column 79 }
    S2 := Copy(L,3,255);
    IF Selected THEN
    BEGIN
      ANSIG(3,LineY[I]);
      Prompt(#27'[1;37;44m');    { white on blue }
      S3 := S2; PadRight(S3,77); Prompt(S3);
      Prompt(#27'[0m');
    END
    ELSE
    BEGIN
      ANSIG(3,LineY[I]);
      Prompt(#27'[0m');
{ stripped for remote ANSI safety }
      S3 := S2; PadRight(S3,77); Prompt(S3);
      Prompt(#27'[0m');
    END;
  END;

  PROCEDURE PadRight(VAR SS: AStr; N: Byte);
  BEGIN
    IF (N = 0) THEN
      EXIT;
    IF (Length(SS) > N) THEN
      SS := Copy(SS,1,N)
    ELSE
      WHILE (Length(SS) < N) DO
        SS := SS + ' ';
  END;


  PROCEDURE DrawScreen;
  VAR
    I: Byte;
    SaveAttr: Byte;
  BEGIN
    Cls;
    { Header }
    lRGLngStr(238,FALSE);
    NL;
    Print('Use arrow keys to select, ENTER to read, or type a message #.');
    Print('ESC quits. PgUp/PgDn scroll. Home/End jump.');
    NL;

    PerPage := PageLength - 9;
    IF (PerPage < 5) THEN
      PerPage := 5;
    IF (PerPage > 20) THEN
      PerPage := 20;

    { Start list immediately under the header }
    { NOTE: CRT.WhereY is not reliable with ANSI/remote output; use a fixed baseline }
    BaseY := 6;
    IF (BaseY < 2) THEN BaseY := 2;
Count := 0;
    FOR I := 1 TO PerPage DO
    BEGIN
      IF (StartMsg + (I - 1) <= HiMsg) THEN
      BEGIN
        Inc(Count);
        MsgList[Count] := StartMsg + (I - 1);
        LineY[Count] := BaseY + (Count - 1);
      END;
    END;

    FOR I := 1 TO Count DO
      DrawLine(I, I = CurIdx);
    { Draw numeric-jump prompt line cleanly (no CRT.WhereY dependence) }
    SaveAttr := TextAttr;
    TextColor(LightBlue);
    TextBackground(Black);

    ANSIG(1,22);
    FOR I := 1 TO 80 DO
      Prompt(' ');
    ANSIG(1,22);
    Prompt('|09Select Message |09[|14%CM-|14%HM|09] (|14Q|09=|14Quit|09): ');
    Prompt(Chr(19)+Chr(9));
    Prompt(InStr);
    ANSIG(17 + Length(InStr),22);
    GotoXY(17 + Length(InStr),22);
{ leave cursor on numeric input field }
    GotoXY(17 + Length(InStr), 22);
    ANSIG(17 + Length(InStr), 22);
  TextAttr := SaveAttr;
  END;

          PROCEDURE UpdatePrompt;
CONST
  PromptY = 22; { fixed: line above command bar in this screen }
VAR
  I: Integer;
  X: Integer;
  SaveAttr: Byte;
BEGIN
  SaveAttr := TextAttr;
  TextColor(LightBlue);
  TextBackground(Black);

  IF OkAnsi THEN
    Prompt(#27+'[0m'+#27+'[94;40m');
  { Force visible local/remote attribute for the Jump/Msg# prompt }
  Prompt(Chr(19)+Chr(9));
  { Hard-clear the whole line first so no prior footer/path text bleeds through }
  ANSIG(1, PromptY);
  GotoXY(1, PromptY);
  FOR I := 1 TO 80 DO
    Prompt(' ');

  { Redraw prompt + current digits }
  ANSIG(1, PromptY);
  GotoXY(1, PromptY);
  Prompt('|09Select Message |09[|14%CM-|14%HM|09] (|14Q|09=|14Quit|09): ');
    Prompt(Chr(19)+Chr(9));
    Prompt(InStr);

  { Keep BOTH remote and local cursor at end of input (prevents first-digit echo scribble) }
  X := 17 + Length(InStr);
  ANSIG(X, PromptY);
  GotoXY(X, PromptY);
  TextAttr := SaveAttr;
END;
PROCEDURE ClearPrompt;
CONST
  PromptY = 22;
VAR
  I: Integer;
  SaveAttr: Byte;
BEGIN
  SaveAttr := TextAttr;
  TextColor(LightBlue);
  TextBackground(Black);
  IF OkAnsi THEN
    Prompt(#27+'[0m'+#27+'[94;40m');
  { Force visible local/remote attribute for the Jump/Msg# prompt }
  Prompt(Chr(19)+Chr(9));
  ANSIG(1, PromptY);
  GotoXY(1, PromptY);
  FOR I := 1 TO 80 DO
    Prompt(' ');
  TextAttr := SaveAttr;
END;

BEGIN
  IF (HiMsg = 0) THEN
    Exit;

  IF (MsgNum < 1) THEN
    MsgNum := 1;
  IF (MsgNum > HiMsg) THEN
    MsgNum := HiMsg;

  { If lightbars are off, fall back to direct numeric entry }
  IF (NOT OkANSI) OR (NOT General.UseLightBars) OR (NOT (LightBars IN ThisUser.SFlags)) THEN
  BEGIN
  
  NL;
InStr := '';
    UpdatePrompt;
InputString(
  'Message number (1-'+IntToStr(HiMsg)+') [Q=Quit]: ',
  InStr,
  5,
  [AllowEscape],
  Changed
);

IF (InStr <> '') AND (UpCase(InStr[1]) <> 'Q') THEN
BEGIN
  Val(InStr, V, Code);
  IF Code = 0 THEN
    MsgNum := V;
  IF MsgNum < 1 THEN MsgNum := 1;
  IF MsgNum > HiMsg THEN MsgNum := HiMsg;
END;
Exit;
  END;

  MsgSel_EscPressed := FALSE;
  MsgSel_IgnoreRemaining := FALSE;

  StartMsg := MsgNum;
  CurIdx := 1;
  InStr := '';
  JumpMode := FALSE;
  S := '';
  DrawScreen;
  ClearPrompt;
  REPEAT
    { Keep cursor in the right place for remote echo }
    ANSIG(17 + Length(InStr), 22);
    W := GetKey;
    { Message # prompt mode: ONLY allow 0-9, ENTER, BACKSPACE. ESC/Q cancels entry. }
    IF JumpMode THEN
    BEGIN
      IF (W = 27) OR ((W < 256) AND (UpCase(Chr(W)) = 'Q')) THEN
      BEGIN
        JumpMode := FALSE;
        InStr := '';
        ClearPrompt;
        Continue;
      END;
      IF (W = 13) THEN
      BEGIN
        IF (InStr <> '') THEN
        BEGIN
          MsgNum := StrToInt(InStr);
          IF (MsgNum < 1) THEN MsgNum := 1;
          IF (MsgNum > HiMsg) THEN MsgNum := HiMsg;
          StartMsg := MsgNum;
          CurIdx := 1;
        END;
        InStr := '';
        JumpMode := FALSE;
        ClearPrompt;
        DrawScreen;
        Continue;
      END;
      IF (W = 8) THEN
      BEGIN
        IF (Length(InStr) > 0) THEN
        BEGIN
          Delete(InStr,Length(InStr),1);
          UpdatePrompt;
        END;
        Continue;
      END;
      IF (W < 256) AND (Chr(W) IN ['0'..'9']) THEN
      BEGIN
        IF (Length(InStr) < 5) THEN
        BEGIN
          InStr := InStr + Chr(W);
          UpdatePrompt;
        END;
        Continue;
      END;
      Continue;
    END;

    { Q quits like ESC }
    { I ignores / aborts this list }
    IF (W < 256) THEN
    BEGIN
      IF (UpCase(Chr(W)) = 'I') THEN
      BEGIN
        IF JumpMode THEN
        BEGIN
          JumpMode := FALSE;
          InStr := '';
          ClearPrompt;
          Continue;
        END;
        MsgSel_IgnoreRemaining := TRUE;
        Prompt(Chr(19)+Chr(7));
{ stripped for remote ANSI safety }
        { TextBackground removed for remote ANSI safety }
        { TextColor removed for remote ANSI safety }
        Exit;
      END;
    END;


    IF (W < 256) THEN
    BEGIN
      IF (UpCase(Chr(W)) = 'Q') THEN
      BEGIN
        { Q quits like ESC }
        MsgSel_EscPressed := TRUE;
        Prompt(Chr(19)+Chr(7));
{ stripped for remote ANSI safety }
        { TextBackground removed for remote ANSI safety }
        { TextColor removed for remote ANSI safety }
        Exit;
      END;
    END;

    { ESC }
    IF (W = 27) THEN
    BEGIN
      IF JumpMode THEN
      BEGIN
        JumpMode := FALSE;
        InStr := '';
        ClearPrompt;
        Continue;
      END;

      MsgSel_EscPressed := TRUE;

      Prompt(Chr(19)+Chr(7));
{ stripped for remote ANSI safety }
      { TextBackground removed for remote ANSI safety }
      { TextColor removed for remote ANSI safety }
      Exit;
    END;

        { ENTER }
    IF (W = 13) THEN
    BEGIN
      IF JumpMode THEN
      BEGIN
        IF (InStr <> '') THEN
        BEGIN
          MsgNum := StrToInt(InStr);
          IF (MsgNum < 1) THEN MsgNum := 1;
          IF (MsgNum > HiMsg) THEN MsgNum := HiMsg;
          StartMsg := MsgNum;
          CurIdx := 1;
        END;
        InStr := '';
        JumpMode := FALSE;
        ClearPrompt;
        DrawScreen;
        Continue;
      END
      ELSE
      BEGIN
        MsgNum := MsgList[CurIdx];
        Prompt(Chr(19)+Chr(7));
{ stripped for remote ANSI safety }
        { TextBackground removed for remote ANSI safety }
        { TextColor removed for remote ANSI safety }
        Exit;
      END;
    END;


    { Navigation keys }
    IF (W = F_Up) THEN
    BEGIN
      { Move within current page }
      IF (CurIdx > 1) THEN
      BEGIN
        DrawLine(CurIdx,FALSE);
        Dec(CurIdx);
        DrawLine(CurIdx,TRUE);
      END
      ELSE
      { Page up when we hit the top }
      IF (StartMsg > 1) THEN
      BEGIN
        IF (StartMsg > PerPage) THEN
          Dec(StartMsg,PerPage)
        ELSE
          StartMsg := 1;

        CurIdx := PerPage;
        DrawScreen;

        IF (CurIdx > Count) THEN
          CurIdx := Count;

        DrawLine(CurIdx,TRUE);
      END;
    END;

IF (W = F_Down) THEN
    BEGIN
      { Move within current page }
      IF (CurIdx < Count) THEN
      BEGIN
        DrawLine(CurIdx,FALSE);
        Inc(CurIdx);
        DrawLine(CurIdx,TRUE);
      END
      ELSE
      { Page down when we hit the bottom }
      IF ((StartMsg + Count - 1) < HiMsg) THEN
      BEGIN
        Inc(StartMsg,PerPage);
        IF (StartMsg > (HiMsg - PerPage + 1)) THEN
          StartMsg := HiMsg - PerPage + 1;

        CurIdx := 1;
        DrawScreen;
      END;
    END;

IF (W = F_Home) THEN
    BEGIN
      StartMsg := 1;
      CurIdx := 1;
      DrawScreen;
      Continue;
    END;

    IF (W = F_End) THEN
    BEGIN
      IF (HiMsg > PerPage) THEN
        StartMsg := HiMsg - (PerPage - 1)
      ELSE
        StartMsg := 1;
      CurIdx := 1;
      DrawScreen;
      IF (Count > 1) THEN
        DrawLine(CurIdx,FALSE);
      CurIdx := Count;
      DrawLine(CurIdx,TRUE);
      Continue;
    END;

    { Typed input: ONLY when JumpMode is active (press J to start) }
IF (W < 256) THEN
BEGIN
  C := Chr(W);

  IF (UpCase(C) = 'J') THEN
  BEGIN
    JumpMode := TRUE;
    InStr := '';
    UpdatePrompt;
    Continue;
  END;

  IF (NOT JumpMode) AND (C IN ['0'..'9']) THEN
  BEGIN
    JumpMode := TRUE;
    InStr := C;
    UpdatePrompt;
    Continue;
  END;

  IF JumpMode AND (C IN ['0'..'9']) THEN
  BEGIN
    IF (Length(InStr) < 5) THEN
    BEGIN
      InStr := InStr + C;
      UpdatePrompt;
    END;
    Continue;
  END;

  IF JumpMode AND (W = 8) THEN
  BEGIN
    IF (Length(InStr) > 0) THEN
    BEGIN
      Delete(InStr,Length(InStr),1);
      UpdatePrompt;
    END
    ELSE
    BEGIN
      { backspace on empty cancels }
      JumpMode := FALSE;
      ClearPrompt;
    END;
    Continue;
  END;
END;

UNTIL (HangUp);
END;

PROCEDURE Post(ReplyTo: LongInt; VAR TToI: FromToInfo; PvtMsg: Boolean);
VAR
  MHeader: MHeaderRec;
  PostOk: Boolean;
BEGIN

  LoadMsgArea(MsgArea);

  PostOk := TRUE;

  IF (NOT AACS(MemMsgArea.PostACS)) THEN
  BEGIN
    NL;
    Print('^8Your access level does not permit you to post in this message area!^0');
    PostOk := FALSE;
  END
  ELSE IF (AccountBalance < General.CreditPost) AND (NOT (FNoCredits IN ThisUser.ACFlags)) THEN
  BEGIN
    NL;
    Print('^8Insufficient account balance to post a public message!^0');
    PostOk := FALSE;
  END
  ELSE IF (RPost IN ThisUser.ACFlags) OR (NOT AACS(General.NormPubPost)) THEN
  BEGIN
    NL;
    Print('^8Your access priviledges do not include posting a public messages!^0');
    PostOk := FALSE;
  END
  ELSE IF (PublicPostsToday >= General.MaxPubPost) AND (NOT MsgSysOp) THEN
  BEGIN
    NL;
    Print('^8You have already sent the maximum public messages allowed per day!^0');
    PostOk := FALSE;
  END;

  IF (NOT PostOk) THEN
    Exit;

  InitMsgArea(MsgArea);

  MHeader.Status := [];

  MHeader.FileAttached := 0;

  IF (ReplyTo <> -1) THEN
  BEGIN
    MHeader.MTo := TToI;
    IF (MHeader.MTo.Anon > 0) THEN
      MHeader.MTo.A1S := UseName(MHeader.MTo.Anon,MHeader.MTo.A1S);
  END
  ELSE
  BEGIN
    FillChar(MHeader.MTo,SizeOf(MHeader.MTo),0);
    InResponseTo := '';
  END;

  IF (MemMsgArea.PrePostFile <> '') THEN
  BEGIN
    PrintF(MemMsgArea.PrePostFile);
    PauseScr(FALSE);
  END;

  IF (InputMessage(TRUE,(ReplyTo <> -1),'',MHeader,'',78,500)) THEN
  BEGIN

    IF (ReplyTo <> -1) THEN
      MHeader.ReplyTo := ((HiMsg + 1) - ReplyTo);

    IF (PvtMsg) THEN
      Include(MHeader.Status,Prvt);

    SaveHeader((HiMsg + 1),MHeader);

    Print('^0Message posted on ^1'+MemMsgArea.Name+'^0.');

    SysOpLog(MHeader.Subject+' posted on ^1'+MemMsgArea.Name);

    IF (MHeader.MTo.A1S <> '') THEN
      SysOpLog('  To: "'+MHeader.MTo.A1S+'"');

    IF (ReplyTo <> -1) THEN
    BEGIN
      LoadHeader(ReplyTo,MHeader);
      Inc(MHeader.Replies);
      SaveHeader(ReplyTo,MHeader);
    END;

    IF (ThisUser.MsgPost < 2147483647) THEN
      Inc(ThisUser.MsgPost);

    IF (PublicPostsToday < 255) THEN
      Inc(PublicPostsToday);

    IF (NOT (FNoCredits IN ThisUser.ACFlags)) THEN
      AdjustBalance(General.CreditPost);

    SaveURec(ThisUser,UserNum);

    Update_Screen;

  END;
END;

PROCEDURE ListMessages(Pub: Boolean);
VAR
  MHeader: MHeaderRec;
  S,
  S1: STRING;
  TempHiMsg: Word;
  ADate: DateTime;
  NumDone: Byte;
BEGIN
  TempHiMsg := HiMsg;
  IF ((Msg_On < 1) OR (Msg_On > TempHiMsg)) THEN
    Exit;
  Abort := FALSE;
  Next := FALSE;
  {
  CLS;
  PrintACR('
????????????????????????????????????????????????????????????????????????????');
  PrintACR('
?
 Msg# 
?
 Sender            
? Receiver           
?  '+'Subject           
?! Posted 
?');
  PrintACR('
??????????????????????????????????????????????????????????????????????????????');
  }
  lRGLngStr(238,FALSE); { Public messages list header }
  Dec(Msg_On);
  NumDone := 0;
  WHILE ((NumDone < (PageLength - 7)) AND (Msg_On >= 0) AND (Msg_On < TempHiMsg) AND (NOT Abort) AND (NOT HangUp)) DO
  BEGIN
    Inc(Msg_On);

    LoadHeader(Msg_On,MHeader);

    IF ((NOT (UnValidated IN MHeader.Status)) AND (NOT (MDeleted IN MHeader.Status))) OR (MsgSysOp) THEN
    BEGIN

      IF (MDeleted IN MHeader.Status) THEN
        S := '''D'
      ELSE IF (UnValidated IN MHeader.Status) THEN
        S := '''U'
      ELSE IF ToYou(MHeader) OR FromYou(MHeader) THEN
        S := '''>'
      ELSE IF (Pub) AND (TempLastRead < MHeader.Date) THEN
        S := '''*'
      ELSE
        S := ' ';

      S := S + ' "'+PadLeftInt(Msg_On,5)+'  #';

      IF (MARealName IN MemMsgArea.MAFlags) THEN
        S1 := UseName(MHeader.From.Anon,MHeader.From.Real)
      ELSE
        S1 := UseName(MHeader.From.Anon,MHeader.From.A1S);

      S := S + PadLeftStr(S1,18)+'  $';

      IF ((MARealName IN MemMsgArea.MAFlags) AND (MHeader.MTo.Real <> '')) THEN
        S1 := UseName(MHeader.MTo.Anon,MHeader.MTo.Real)
      ELSE
        S1 := UseName(MHeader.MTo.Anon,MHeader.MTo.A1S);

      S := S + PadLeftStr(S1,19)+' % ';

      IF (MHeader.FileAttached = 0) THEN
        S := S + PadLeftStr(MHeader.Subject,18)
      ELSE
        S := S + PadLeftStr(Stripname(MHeader.Subject),18);

      PackToDate(ADate,MHeader.Date);

      S := S + ' &'+ZeroPad(IntToStr(ADate.Month))+'/'+ ZeroPad(IntToStr(ADate.Day))+'/'+ZeroPad(IntToStr(ADate.Year));

      IF (AllowMCI IN MHeader.Status) THEN
        PrintACR(S)
      ELSE
        Print(S);

      Inc(NumDone);
    END;
    Wkey;
  END;
END;

PROCEDURE RL_ListLightBarSelect(VAR MsgNum: Word; Pub: Boolean);
VAR
  MHeader: MHeaderRec;
  ADate: DateTime;
  PerPage: Byte;
  StartMsg: Word;
  CurIdx: Byte;
  Count: Byte;
  MsgList: ARRAY[1..25] OF Word;
  LineY: ARRAY[1..25] OF Byte;
  BaseY: Byte;
  W: Word;
  C: Char;
  S, S1: AStr;

  PROCEDURE BuildColorLine(MN: Word; VAR OutS: AStr);
  VAR
    FromS, ToS, SubjS: AStr;

  PROCEDURE PurgeKbd;
  BEGIN
    WHILE KeyPressed DO
      ReadKey;
  END;

  BEGIN
    LoadHeader(MN,MHeader);

    { Status marker (colored, exactly like ListMessages) }
    IF (MDeleted IN MHeader.Status) THEN
      OutS := Chr(19)+''''+'D'
    ELSE IF (UnValidated IN MHeader.Status) THEN
      OutS := Chr(19)+''''+'U'
    ELSE IF ToYou(MHeader) OR FromYou(MHeader) THEN
      OutS := Chr(19)+''''+'>'
    ELSE IF (Pub) AND (TempLastRead < MHeader.Date) THEN
      OutS := Chr(19)+''''+'*'
    ELSE
      OutS := ' ';

    { NOTE: no extra "  " gap after status marker (shifts 2 cols left) }
    OutS := OutS + ' ' + Chr(19)+'"'+PadLeftInt(MN,5)+' ' +Chr(19)+'#';

    IF (MARealName IN MemMsgArea.MAFlags) THEN
      FromS := UseName(MHeader.From.Anon,MHeader.From.Real)
    ELSE
      FromS := UseName(MHeader.From.Anon,MHeader.From.A1S);

    OutS := OutS + PadLeftStr(FromS,18)+'  '+Chr(19)+'$';

    IF ((MARealName IN MemMsgArea.MAFlags) AND (MHeader.MTo.Real <> '')) THEN
      ToS := UseName(MHeader.MTo.Anon,MHeader.MTo.Real)
    ELSE
      ToS := UseName(MHeader.MTo.Anon,MHeader.MTo.A1S);

    OutS := OutS + PadLeftStr(ToS,19)+' '+Chr(19)+'% ';

    IF (MHeader.FileAttached = 0) THEN
      SubjS := MHeader.Subject
    ELSE
      SubjS := StripName(MHeader.Subject);

    OutS := OutS + PadLeftStr(SubjS,18);

    PackToDate(ADate,MHeader.Date);
    OutS := OutS + '  '+Chr(19)+'&'+ZeroPad(IntToStr(ADate.Month))+'/'+
                   ZeroPad(IntToStr(ADate.Day))+'/'+ZeroPad(IntToStr(ADate.Year));
  END;

  PROCEDURE BuildPlainLine(MN: Word; VAR OutS: AStr);
  VAR
    StatusCh: Char;
    FromS, ToS, SubjS: AStr;
  BEGIN
    LoadHeader(MN,MHeader);

    IF (MDeleted IN MHeader.Status) THEN
      StatusCh := 'D'
    ELSE IF (UnValidated IN MHeader.Status) THEN
      StatusCh := 'U'
    ELSE IF ToYou(MHeader) OR FromYou(MHeader) THEN
      StatusCh := '>'
    ELSE IF (Pub) AND (TempLastRead < MHeader.Date) THEN
      StatusCh := '*'
    ELSE
      StatusCh := ' ';

    IF (MARealName IN MemMsgArea.MAFlags) THEN
      FromS := UseName(MHeader.From.Anon,MHeader.From.Real)
    ELSE
      FromS := UseName(MHeader.From.Anon,MHeader.From.A1S);

    IF ((MARealName IN MemMsgArea.MAFlags) AND (MHeader.MTo.Real <> '')) THEN
      ToS := UseName(MHeader.MTo.Anon,MHeader.MTo.Real)
    ELSE
      ToS := UseName(MHeader.MTo.Anon,MHeader.MTo.A1S);

    IF (MHeader.FileAttached = 0) THEN
      SubjS := MHeader.Subject
    ELSE
      SubjS := StripName(MHeader.Subject);

    PackToDate(ADate,MHeader.Date);

    { same column widths as ListMessages, but no color codes and no 2-space gap }
    OutS := StatusCh+' '+PadLeftInt(MN,5)+' '+
            PadLeftStr(FromS,18)+'  '+
            PadLeftStr(ToS,19)+'  '+
            PadLeftStr(SubjS,18)+'  '+
            ZeroPad(IntToStr(ADate.Month))+'/'+ZeroPad(IntToStr(ADate.Day))+'/'+ZeroPad(IntToStr(ADate.Year));
  END;

  PROCEDURE PadRight(VAR SS: AStr; N: Byte);
  BEGIN
    WHILE (Length(SS) < N) DO
      SS := SS + ' ';
    IF (Length(SS) > N) THEN
      SS := Copy(SS,1,N);
  END;




  PROCEDURE DrawRow(I2: Byte; Hilite: Boolean); FORWARD;
  PROCEDURE DrawScreen;
  VAR
    FooterY1, FooterY2: Byte;
    ListBottom: Byte;
    I2: Byte;
    MN: Word;

  BEGIN
    CLS;
    { Reserve 2 footer lines at bottom (prevents lightbar overlap) }
    FooterY2 := Hi(WindMax);
    FooterY1 := FooterY2 - 1;
    ListBottom := FooterY1 - 2;

    lRGLngStr(238,FALSE);

    PerPage := PageLength - 8;
    IF (PerPage < 5) THEN PerPage := 5;
    IF (PerPage > 20) THEN PerPage := 20;

    { Start list directly under the header }
    BaseY := WhereY + 1;

    { Clamp list height so it does not draw into footer }
    IF (BaseY <= ListBottom) THEN
    BEGIN
      IF (BaseY + PerPage - 1 > ListBottom) THEN
        PerPage := (ListBottom - BaseY + 1);
    END
    ELSE
      PerPage := 0;

    Count := 0;
    FOR I2 := 1 TO PerPage DO
    BEGIN
      MN := StartMsg + (I2 - 1);
      IF (MN <= HiMsg) THEN
      BEGIN
        Inc(Count);
        MsgList[Count] := MN;
        LineY[Count] := BaseY + (Count - 1);
      END;
    END;

    { clamp selection }
    IF Count < 1 THEN
      CurIdx := 1
    ELSE
    BEGIN
      IF CurIdx < 1 THEN
        CurIdx := 1;
      IF CurIdx > Count THEN
        CurIdx := Count;
    END;

    FOR I2 := 1 TO Count DO
      DrawRow(I2, (I2 = CurIdx));

        { Footer help lines (2-line footer) }
    Prompt(#27'[0m');
    Prompt(#27'[37;40m');
    Prompt(#27'[0K');

    ANSIG(1, Hi(WindMax)-1);
    lRGLngStr(288,FALSE);
{    Prompt('ENTER=Read  I=Ignore  Q/ESC=Quit');}
    Prompt(#27'[0K');

    ANSIG(1, FooterY2);
    lRGLngStr(289,FALSE);
{    Prompt('Up/Down=Move  PgUp/PgDn=Page  Home/End=Jump');}
    Prompt(#27'[0K');
{ Restore Renegade normal colors for anything after this }
{ stripped for remote ANSI safety }
    Prompt(Chr(19)+Chr(7));
  END;


  
  FUNCTION VisLen(S: AStr): Byte;
    VAR
      I: Integer;
      C: Byte;
  BEGIN
    C := 0;
    I := 1;
    WHILE I <= Length(S) DO
    BEGIN
      IF (S[I] = Chr(19)) AND (I < Length(S)) THEN
        Inc(I, 2)
      ELSE
      BEGIN
        Inc(C);
        Inc(I);
      END;
    END;
    VisLen := C;
  END;

  FUNCTION CutVis(S: AStr; W: Byte): AStr;
    VAR
      I: Integer;
      C: Byte;
      T: AStr;
  BEGIN
    T := '';
    C := 0;
    I := 1;
    WHILE (I <= Length(S)) AND (C < W) DO
    BEGIN
      IF (S[I] = Chr(19)) AND (I < Length(S)) THEN
      BEGIN
        { keep Renegade color codes as-is (2 bytes) }
        T := T + S[I] + S[I+1];
        Inc(I, 2);
      END
      ELSE
      BEGIN
        T := T + S[I];
        Inc(C);
        Inc(I);
      END;
    END;
    CutVis := T;
  END;

  FUNCTION SkipVis(S: AStr; N: Byte): AStr;
    VAR
      I: Integer;
      V: Byte;
      OutS: AStr;
  BEGIN
    I := 1;
    V := 0;
    OutS := '';

    { Skip N visible characters, preserving any Renegade color codes encountered }
    WHILE (I <= Length(S)) AND (V < N) DO
    BEGIN
      IF (S[I] = Chr(19)) AND (I < Length(S)) THEN
      BEGIN
        OutS := OutS + S[I] + S[I+1];
        Inc(I, 2);
      END
      ELSE
      BEGIN
        Inc(V);
        Inc(I);
      END;
    END;

    IF I <= Length(S) THEN
      OutS := OutS + Copy(S, I, Length(S) - I + 1);

    SkipVis := OutS;
  END;
  PROCEDURE PadVis(VAR S: AStr; W: Byte);
    VAR
      V: Byte;
  BEGIN
    V := VisLen(S);
    WHILE V < W DO
    BEGIN
      S := S + ' ';
      Inc(V);
    END;
  END;

PROCEDURE DrawRow(I2: Byte; Hilite: Boolean);
  VAR
    L: AStr;
    P: AStr;
    P2: AStr;
    LRest: AStr;
  BEGIN
    { Fixed visible width: 79 columns in the message list area.
      We avoid painting the highlight over columns 1-2 (the status flag area)
      to reduce ANSI client "smear" issues. }

    IF (I2 < 1) OR (I2 > Count) THEN
      Exit;

    { Hard-clear the entire line to black before repainting }
    ANSIG(1, LineY[I2]);
    Prompt(#27'[0m');
    Prompt(#27'[37;40m');
    Prompt(#27'[0K');
{ stripped ClrEol for remote safety }

    IF Hilite THEN
    BEGIN
    Prompt(#27'[0m');
    Prompt(#27'[1;37;44m'); { bright white on blue }
      BuildPlainLine(MsgList[I2], P);
      P := CutVis(P, 79);
      PadVis(P, 79);

      { Cols 1-2 normal (status), cols 3-79 highlighted }
      ANSIG(1, LineY[I2]);
{ stripped for remote ANSI safety }
      { TextBackground removed for remote ANSI safety }
      { TextColor removed for remote ANSI safety }
      P2 := Copy(P, 1, 2);
      IF Length(P2) < 2 THEN P2 := P2 + '  ';
      Prompt(P2);

      ANSIG(3, LineY[I2]);
{ stripped for remote ANSI safety }
      { TextBackground removed for remote ANSI safety }
      { TextColor removed for remote ANSI safety }
      P2 := Copy(P, 3, 77);
      IF Length(P2) < 77 THEN
        P2 := P2 + Copy('                                                                             ', 1, 77 - Length(P2));
      Prompt(P2);
    END
    ELSE
    BEGIN
      { Normal line: keep color codes, but start painting at col 3 }
      BuildPlainLine(MsgList[I2], P);
      BuildColorLine(MsgList[I2], L);
      P := CutVis(P, 79);
      PadVis(P, 79);

      ANSIG(1, LineY[I2]);
{ stripped for remote ANSI safety }
      { TextBackground removed for remote ANSI safety }
      { TextColor removed for remote ANSI safety }
      Prompt(Copy(P, 1, 2));

      ANSIG(3, LineY[I2]);
      LRest := SkipVis(L, 2);
      LRest := CutVis(LRest, 77);
      PadVis(LRest, 77);
      Prompt(LRest);
    END;

    { Ensure the remainder of the line is black }
    Prompt(#27'[0m');
    Prompt(#27'[37;40m');
    Prompt(#27'[K');
{ stripped for remote ANSI safety }
      { TextBackground removed for remote ANSI safety }
      { TextColor removed for remote ANSI safety }
  END;
BEGIN
  { initialize TempLastRead so '*' flags are correct on first entry }
  LoadLastReadRecord(LastReadRecord);
  TempLastRead := LastReadRecord.LastRead;


  { reset selector state each entry }
  RL_EscPressed := FALSE;
  RL_IgnoreRemaining := FALSE;
  JumpMode := FALSE;
  S := '';
  { reduce remote flicker } 
  IF (ComPortSpeed > 0) THEN
    Prompt(#27'[?25l');

  IF (HiMsg < 1) THEN
  BEGIN
    NL;
    Print('No messages to list.');
    IF (ComPortSpeed > 0) THEN
    Prompt(#27'[?25h');
    Exit;
  END;

  IF (MsgNum < 1) THEN MsgNum := 1;
  IF (MsgNum > HiMsg) THEN MsgNum := HiMsg;

  StartMsg := MsgNum;
  CurIdx := 1;

  DrawScreen;

  REPEAT
    W := GetKey;

    { Message # prompt mode: ONLY allow 0-9, ENTER, BACKSPACE. ESC/Q cancels entry. }
    IF JumpMode THEN
    BEGIN
      IF (W = 27) OR ((W < 256) AND (UpCase(Chr(W)) = 'Q')) THEN
      BEGIN
        JumpMode := FALSE;
        S := '';
        ANSIG(1, Hi(WindMax)-1);
        Prompt(#27'[0K');
        lRGLngStr(288, FALSE);
        Continue;
      END;

      IF (W = 13) THEN
      BEGIN
        IF (Length(S) > 0) THEN
        BEGIN
          MsgNum := StrToInt(S);
          IF (MsgNum < 1) THEN MsgNum := 1;
          IF (MsgNum > HiMsg) THEN MsgNum := HiMsg;
          StartMsg := MsgNum;
          CurIdx := 1;
          DrawScreen;
        END;
        JumpMode := FALSE;
        S := '';
        ANSIG(1, Hi(WindMax)-1);
        Prompt(#27'[0K');
        lRGLngStr(288, FALSE);
        Continue;
      END;

      IF (W = 8) THEN
      BEGIN
        IF (Length(S) > 0) THEN
          Delete(S, Length(S), 1);
        ANSIG(1, Hi(WindMax)-1);
        Prompt(#27'[0m'); Prompt(#27'[1;34;40m'); Prompt(#27'[0K');
        Prompt('|09Select Message |09[|14%CM-|14%HM|09] (|14Q|09=|14Quit|09): ');
        Prompt(S);
        Continue;
      END;

      IF (W < 256) AND (Chr(W) IN ['0'..'9']) THEN
      BEGIN
        IF (Length(S) < 5) THEN
          S := S + Chr(W);
        ANSIG(1, Hi(WindMax)-1);
        Prompt(#27'[0m'); Prompt(#27'[1;34;40m'); Prompt(#27'[0K');
        Prompt('|09Select Message |09[|14%CM-|14%HM|09] (|14Q|09=|14Quit|09): ');
        Prompt(S);
        Continue;
      END;

      { ignore everything else in JumpMode }
      Continue;
    END;

    { Normal navigation: allow [ and ] as PageUp/PageDn (but NOT while entering Msg#) }
    IF (W < 256) THEN
    BEGIN
      IF (UpCase(Chr(W)) = '[') OR (UpCase(Chr(W)) = 'P') THEN
      BEGIN
        { PageUp }
        IF (StartMsg > 1) THEN
        BEGIN
          IF (StartMsg > PerPage) THEN
            Dec(StartMsg, PerPage)
          ELSE
            StartMsg := 1;
          CurIdx := 1;
          DrawScreen;
        END;
        Continue;
      END
      ELSE IF (UpCase(Chr(W)) = ']') OR (UpCase(Chr(W)) = 'L') THEN
      BEGIN
        { PageDn }
        IF (StartMsg + PerPage <= HiMsg) THEN
        BEGIN
          Inc(StartMsg, PerPage);
          IF (StartMsg + PerPage - 1 > HiMsg) THEN
            StartMsg := HiMsg - PerPage + 1;
          IF (StartMsg < 1) THEN
            StartMsg := 1;
          CurIdx := 1;
          DrawScreen;
        END;
        Continue;
      END;
    END;

{ Q = Quit like ESC, I = Ignore Remaining (same as R+I in ReadP) }
    IF (W < 256) THEN
    BEGIN
      C := UpCase(Chr(W));
      { Numeric jump is ONLY via 'J' mode to avoid garbage from stray digits }
      IF (NOT JumpMode) AND (C = 'J') THEN
      BEGIN
        JumpMode := TRUE;
        S := '';
        ANSIG(1, Hi(WindMax)-1);
        Prompt(#27'[0m');
         Prompt(#27'[1;34;40m');
         Prompt(#27'[0K');
         Prompt('|09Select Message |09[|14%CM-|14%HM|09] (|14Q|09=|14Quit|09): ');
        Continue;
      END;

      { Digit starts numeric entry }
      IF (NOT JumpMode) AND (C IN ['0'..'9']) THEN
      BEGIN
        JumpMode := TRUE;
        S := C;
        ANSIG(1, Hi(WindMax)-1);
        Prompt(#27'[0m');
         Prompt(#27'[1;34;40m');
         Prompt(#27'[0K');
         Prompt('|09Select Message |09[|14%CM-|14%HM|09] (|14Q|09=|14Quit|09): ');
        Prompt(S);
        Continue;
      END;

      IF (JumpMode) THEN
      BEGIN
        { Cancel jump mode }
        IF (W = 27) THEN
        BEGIN
          JumpMode := FALSE;
          ANSIG(1, Hi(WindMax)-1);
          Prompt('');
          lRGLngStr(288, FALSE);
          Continue;
        END;

        { Backspace }
        IF (W = 8) THEN
        BEGIN
          IF (Length(S) > 0) THEN
            Delete(S, Length(S), 1)
          ELSE
          BEGIN
            JumpMode := FALSE;
            ANSIG(1, Hi(WindMax)-1);
            Prompt('');
            lRGLngStr(288, FALSE);
            Continue;
          END;

          ANSIG(1, Hi(WindMax)-1);
          Prompt(#27'[0m');
         Prompt(#27'[1;34;40m');
         Prompt(#27'[0K');
         Prompt('|09Select Message |09[|14%CM-|14%HM|09] (|14Q|09=|14Quit|09): ');
          Prompt(S);
          Continue;
        END;

        { Digits }
        IF (C IN ['0'..'9']) THEN
        BEGIN
          S := S + C;
          ANSIG(1, Hi(WindMax)-1);
          Prompt(#27'[0m');
         Prompt(#27'[1;34;40m');
         Prompt(#27'[0K');
         Prompt('|09Select Message |09[|14%CM-|14%HM|09] (|14Q|09=|14Quit|09): ');
          Prompt(S);
          Continue;
        END;

        { ENTER confirms jump }
        IF (W = 13) THEN
        BEGIN
          IF (Length(S) > 0) THEN
          BEGIN
            MsgNum := StrToInt(S);
            IF (MsgNum < 1) THEN MsgNum := 1;
            IF (MsgNum > HiMsg) THEN MsgNum := HiMsg;

            StartMsg := MsgNum;
            CurIdx := 1;
            DrawScreen;
          END;

          JumpMode := FALSE;
          S := '';
          ANSIG(1, Hi(WindMax)-1);
          Prompt('');
          lRGLngStr(288, FALSE);
          Continue;
        END;
      END;

      IF (C = 'Q') THEN
      BEGIN
        RL_EscPressed := TRUE;
        Break;
      END;
      IF (C = 'I') THEN
      BEGIN
        RL_IgnoreRemaining := TRUE;
        Break;
      END;
    END;

    IF (W = 27) THEN
    BEGIN
      RL_EscPressed := TRUE;
      Break;
    END;

    IF (W = 13) THEN
    BEGIN
      MsgNum := MsgList[CurIdx];
        { eat any key repeats so ReadMsg does not auto-advance }
      IF (ComPortSpeed > 0) THEN
    Prompt(#27'[?25h');
      Exit;
    END;

    IF (W = F_Up) THEN
    BEGIN
      IF (CurIdx > 1) THEN
      BEGIN
        W := CurIdx;
        Dec(CurIdx);
        DrawRow(W, FALSE);
        DrawRow(CurIdx, TRUE);
      END
      ELSE IF (StartMsg > 1) THEN
      BEGIN
        { Page up: jump a full page and put bar on LAST line so it feels
          like continuous scrolling }
        IF (StartMsg > PerPage) THEN
          Dec(StartMsg, PerPage)
        ELSE
          StartMsg := 1;
        CurIdx := PerPage;
        DrawScreen;
      END;
      Continue;
    END;

    IF (W = F_Down) THEN
    BEGIN
      IF (CurIdx < Count) THEN
      BEGIN
        W := CurIdx;
        Inc(CurIdx);
        DrawRow(W, FALSE);
        DrawRow(CurIdx, TRUE);
      END
      ELSE IF (StartMsg + PerPage <= HiMsg) THEN
      BEGIN
        { Page down like area listing: jump a full page and keep bar at top }
        Inc(StartMsg, PerPage);
        IF (StartMsg + PerPage - 1 > HiMsg) THEN
          StartMsg := HiMsg - PerPage + 1;
        IF (StartMsg < 1) THEN
          StartMsg := 1;
        CurIdx := 1;
        DrawScreen;
      END;
      Continue;
    END;
{ numeric jump handled above (J-only); stray digits ignored }
  UNTIL FALSE;

  { ensure cursor is visible on exit }
  IF (ComPortSpeed > 0) THEN
    Prompt(#27'[?25h');
END;

PROCEDURE MainRead(OncOnly,AskUpdate,Pub: Boolean);
VAR
  User: UserRecordType;
  MHeader: MHeaderRec;
  Cmd,
  NewMenuCmd: AStr;
  Junk: Str36;
  Cmd1: Char;
  SaveMenu,
  CmdToExec,
  Counter: Byte;
  MsgNum,
  ThreadStart: Word;
  Done,
  CmdNotHid,
  CmdExists,
  AskPost,
  Contlist,
  DoneScan,
  HadUnVal: Boolean;

  FUNCTION CantBeSeen: Boolean;
  BEGIN
    CantBeSeen := (NOT MsgSysOp) AND ((UnValidated IN MHeader.Status) OR (MDeleted IN MHeader.Status) OR
                  ((Prvt IN MHeader.Status) AND NOT (ToYou(MHeader) OR FromYou(MHeader))));
  END;

BEGIN
  AskPost := FALSE;
  Contlist := FALSE;
  DoneScan := FALSE;
  HadUnVal := FALSE;
  AllowContinue := TRUE;
  ThreadStart := 0;
  TReadPrompt := 0;
  Abort := FALSE;
  Next := FALSE;
  SaveMenu := CurMenu;

  IF (MemMsgArea.MessageReadMenu <> 0) THEN
    CurMenu := MemMsgArea.MessageReadMenu
  ELSE
    CurMenu := General.MessageReadMenu;

  IF (NOT NewMenuToLoad) THEN
    LoadMenuPW;

  AutoExecCmd('FIRSTCMD');

  REPEAT

    IF (Contlist) AND (Abort) THEN
    BEGIN
      Contlist := FALSE;
      NL;
      Print('Continuous message listing off.');
      TReadPrompt := 255;
    END;

    IF (Msg_On < 1) OR (Msg_On > HiMsg) THEN
    BEGIN
      IF (NOT Contlist) THEN
      BEGIN
        DoneScan := TRUE;
        IF (Pub) THEN
          AskPost := TRUE;
      END
      ELSE
      BEGIN
        Contlist := FALSE;
        Msg_On := HiMsg;
        NL;
        Print('Continuous message listing off.');
        TReadPrompt := 255;
      END;
    END;

    IF (NOT DoneScan) AND (TReadPrompt IN [0..2,8..10,18]) THEN
    BEGIN
      IF (Contlist) THEN
        Next := TRUE;
      LoadHeader(Msg_On,MHeader);
      IF (Pub) AND (UnValidated IN MHeader.Status) THEN
        HadUnVal := TRUE;
      WHILE (((Msg_On < HiMsg) AND (TReadPrompt <> 2)) OR ((Msg_On > 1) AND (TReadPrompt = 2))) AND
            (CantBeSeen) DO
      BEGIN
        IF (TReadPrompt = 2) THEN
          Dec(Msg_On)
        ELSE
          Inc(Msg_On);
        LoadHeader(Msg_On,MHeader);
      END;
      IF ((Msg_On = 1) OR (Msg_On = HiMsg)) AND (CantBeSeen) THEN
      BEGIN
        DoneScan := TRUE;
        IF (Pub) THEN
          AskPost := TRUE;
      END
      ELSE
      BEGIN
        IF ((CLSMsg IN ThisUser.SFlags) AND (NOT Contlist)) THEN
          Cls
        ELSE
          NL;
                { Fix: reset COMMON pager/output state so Continue prompt works after lightbar selection }

                DOSANSIOn := FALSE;

                CtrlJOff := FALSE;

                CROff := FALSE;

                LIL := 0;

                ReadMsg(Msg_On,Msg_On,HiMsg);
        IF (Pub) AND (TempLastRead < MHeader.Date) AND (MHeader.Date <= GetPackDateTime) THEN
          TempLastRead := MHeader.Date;
        IF (Pub) THEN
          IF (PublicReadThisCall < 32767) THEN
            Inc(PublicReadThisCall);
      END;
    END;
    IF (NOT Contlist) AND (NOT DoneScan) THEN
      REPEAT
        TReadPrompt := 0;
        MainMenuHandle(Cmd);
        NewMenuCmd := '';
        CmdToExec := 0;
        Done := FALSE;
        REPEAT
          FCmd(Cmd,CmdToExec,CmdExists,CmdNotHid);
          IF (CmdToExec <> 0) AND (MemCmd^[CmdToExec].CmdKeys <> '-^') AND
             (MemCmd^[CmdToExec].CmdKeys <> '-/') AND (MemCmd^[CmdToExec].CmdKeys <> '-\') THEN
            DoMenuCommand(Done,
                          MemCmd^[CmdToExec].CmdKeys,
                          MemCmd^[CmdToExec].Options,
                          NewMenuCmd,
                          MemCmd^[CmdToExec].NodeActivityDesc);
        UNTIL (CmdToExec = 0) OR (Done) OR (HangUp);
        Abort := FALSE;
        Next := FALSE;
        CASE TReadPrompt OF
          1 : ;             { Read Again }
          2 : Dec(Msg_On);  { Previous Message }

          3 : IF (NOT MsgSysOp) THEN
                Print('^8You do not have the required access level for this option!^0')
              ELSE
                MoveMsg(Msg_On);

          4 : IF (NOT CoSysOp) THEN
                Print('^8You do not have the required access level for this option!^0')
              ELSE
                ExtractMsgToFile(Msg_On,Mheader);

          5 : IF (NOT FromYou(MHeader)) AND (NOT MsgSysOp) THEN
              BEGIN
                NL;
                Print('^8You can only edit messages that you have sent!^0');
              END
              ELSE
              BEGIN
                REPEAT
                  NL;
                  Prt('^2Message editing [^1?^2=^1Help^2]: ');
                  IF (MsgSysOp) THEN
                    InputChar('',Cmd1,'QADEFOPRSTV?'^M,[CapAll])
                  ELSE
                    InputChar('',Cmd1,'QDEFOST?'^M,[CapAll]);
                  CASE Cmd1 OF
                    (*
                    'D' : FOR Counter := 1 TO 6 DO
                            IF (HeaderLine(MHeader,Msg_On,HiMsg,Counter,Junk) <> '') THEN
                              PrintACR(Headerline(MHeader,Msg_On,HiMsg,Counter,Junk));
                    'O' : IF PYNQ('Reload old information? ',0,FALSE) THEN
                            LoadHeader(Msg_On,MHeader);
                    'E' : BEGIN
                            EditMessageText(Msg_On);
                            LoadHeader(Msg_On,MHeader);
                          END;
                    'S' : IF (MHeader.FileAttached = 0) OR (MsgSysOp) THEN
                          BEGIN
                            Prt('Subj: ');
                            InputDefault(MHeader.Subject,MHeader.Subject,40,[NoInputField],FALSE)
                          END
                          ELSE
                            Print('Sorry, you can''t edit that.');
                    'T' : BEGIN
                            Print('^01. Posted to  : ^1'+MHeader.MTo.A1S);
                            Print('^02. Real name  : ^1'+MHeader.MTo.Real);
                            Print('^03. System name: ^1'+MHeader.MTo.Name);
                            NL;
                            Prt('Edit name (^11^2-^13^2) [^1Q^2]uit: ');
                            Onek(Cmd1,'Q123'^M,TRUE,TRUE);
                            IF (NOT (Cmd1 IN ['Q',^M])) THEN
                              NL;
                            CASE Cmd1 OF
                              '1' : BEGIN
                                      Prt('Posted to: ');
                                      InputDefault(MHeader.MTo.A1S,MHeader.MTo.A1S,36,[],FALSE);
                                    END;
                              '2' : BEGIN
                                      Prt('Real name: ');
                                      InputDefault(MHeader.MTo.Real,MHeader.MTo.Real,36,[],FALSE);
                                    END;
                              '3' : BEGIN
                                      Prt('System name: ');
                                      InputDefault(MHeader.MTo.Name,MHeader.MTo.Name,36,[],FALSE);
                                    END;
                            END;
                            Cmd1 := #0;
                          END;
                    'F' : IF (MHeader.From.Anon > 0) OR (MsgSysOp) THEN
                          BEGIN
                            Print('^01. Posted to  : ^1'+MHeader.From.A1S);
                            Print('^02. Real name  : ^1'+MHeader.From.Real);
                            Print('^03. System name: ^1'+MHeader.From.Name);
                            NL;
                            Prt('Edit name (^11^2-^13^2) [^1Q^2]uit: ');
                            Onek(Cmd1,'Q123'^M,TRUE,TRUE);
                            IF (NOT (Cmd1 IN ['Q',^M])) THEN
                              NL;
                            CASE Cmd1 OF
                              '1' : BEGIN
                                      Prt('Posted to: ');
                                      InputDefault(MHeader.From.A1S,MHeader.From.A1S,36,[],FALSE);
                                    END;
                              '2' : BEGIN
                                      Prt('Real name: ');
                                      InputDefault(MHeader.From.Real,MHeader.From.Real,36,[],FALSE);
                                    END;
                              '3' : BEGIN
                                      Prt('System name: ');
                                      InputDefault(MHeader.From.Name,MHeader.From.Name,36,[],FALSE);
                                    END;
                            END;
                            Cmd1 := #0;
                          END
                          ELSE
                            Print('Sorry, you can''t edit that.');

                    'A' : IF (MsgSysOp) THEN
                          BEGIN
                            IF (MHeader.From.Anon IN [1,2]) THEN
                              MHeader.From.Anon := 0
                            ELSE
                            BEGIN
                              Loadurec(User,MHeader.From.UserNum);
                              IF AACS1(User,MHeader.From.UserNum,General.CSOP) THEN
                                MHeader.From.Anon := 2
                              ELSE
                                MHeader.From.Anon := 1;
                            END;
                            Print('Message is '+AOnOff((MHeader.From.Anon = 0),'not ','')+'anonymous');
                            SysOpLog('Message is '+AOnOff((MHeader.From.Anon = 0),'not ','')+'anonymous');
                          END;
                    *)
                    'A' : IF (NOT MsgSysOp) THEN
                          BEGIN
                            NL;
                            Print('^8You do not have the required access level for this option!^0')
                          END
                          ELSE
                          BEGIN
                            IF (MHeader.From.Anon IN [1,2]) THEN
                            BEGIN
                              MHeader.From.Anon := 0;
                              NL;
                              Print('Message status is not anonymous.');
                              SysOpLog('Message status is not anonymous.');
                            END
                            ELSE
                            BEGIN
                              LoadURec(User,MHeader.From.UserNum);
                              IF AACS1(User,MHeader.From.UserNum,General.CSOP) THEN
                                MHeader.From.Anon := 2
                              ELSE
                                MHeader.From.Anon := 1;
                              NL;
                              Print('Message status is anonymous.');
                              SysOpLog('Message status is anonymous.');
                            END;
                          END;

                    'D' : BEGIN
                            NL;
                            FOR Counter := 1 TO 6 DO
                              IF (HeaderLine(MHeader,Msg_On,HiMsg,Counter,Junk) <> '') THEN
                                PrintACR(Headerline(MHeader,Msg_On,HiMsg,Counter,Junk));
                          END;

                    'E' : BEGIN
                            EditMessageText(Msg_On);
                            LoadHeader(Msg_On,MHeader);
                          END;

                    'F' : IF (MHeader.From.Anon > 0) OR (MsgSysOp) THEN
                          BEGIN
                            NL;
                            Print('^0(^11^0) Posted From : ^1'+MHeader.From.A1S);
                            Print('^0(^12^0) Real Name   : ^1'+MHeader.From.Real);
                            Print('^0(^13^0) System Name : ^1'+MHeader.From.Name);
                            NL;
                            InputChar('^2Edit Names [^11^2-^13^2,<^1CR^2>Quit]: ',Cmd1,^M'123',[CapAll]);
                            CASE Cmd1 OF
                              '1' : BEGIN
                                      InputString('%LF^2Posted From: ',MHeader.From.A1S,36,[InteractiveEdit,
                                                  NoBlankPrompt,NoLineFeed],Changed);
                                    { NL;
                                      Prt('Posted from: ');
                                      InputDefault(MHeader.From.A1S,MHeader.From.A1S,36,[],FALSE); }
                                    END;
                              '2' : BEGIN
                                      InputString('%LF^2Real Name: ',MHeader.From.Real,36,[InteractiveEdit,
                                                  NoBlankPrompt,NoLineFeed],Changed);
                                    { NL;
                                      Prt('Real name: ');
                                      InputDefault(MHeader.From.Real,MHeader.From.Real,36,[],FALSE); }
                                    END;
                              '3' : BEGIN
                                      InputString('%LF^2System Name: ',MHeader.From.Name,36,[InteractiveEdit,
                                                  NoBlankPrompt,NoLineFeed],Changed);
                                    { NL;
                                      Prt('System name: ');
                                      InputDefault(MHeader.From.Name,MHeader.From.Name,36,[],FALSE); }
                                    END;
                            END;
                            Cmd1 := #0;
                          END;

                    'O' : BEGIN
                            NL;
                            IF PYNQ('Reload old information? ',0,FALSE) THEN
                              LoadHeader(Msg_On,MHeader);
                          END;
                    'P' : IF (NOT Pub) THEN
                          BEGIN
                            NL;
                            Print('^8This option is not available when reading private messages!^0');
                          END
                          ELSE IF (NOT MsgSysOp) THEN
                          BEGIN
                            NL;
                            Print('^8You do not have the required access level for this option!^0')
                          END
                          ELSE
                          BEGIN
                            IF (Permanent IN MHeader.Status) THEN
                            BEGIN
                              Exclude(MHeader.Status,Permanent);
                              NL;
                              Print('Message status is not permanent.');
                              SysOpLog('Message status is not permanent.');
                            END
                            ELSE
                            BEGIN
                              Include(MHeader.Status,Permanent);
                              NL;
                              Print('Message status is permanent.');
                              SysOpLog('Message status is permanent.');
                            END;
                          END;


                    'R' : IF (NOT MsgSysOp) THEN
                          BEGIN
                            NL;
                            Print('^8You do not have the required access level for this option!^0')
                          END
                          ELSE
                          BEGIN
                            IF (Sent IN MHeader.Status) THEN
                            BEGIN
                              Exclude(MHeader.Status,Sent);
                              IF (PUB) AND (MemMsgArea.MAType IN [1..2]) AND (NOT (MAScanOut IN MemMsgArea.MAFlags)) THEN
                                UpdateBoard;
                              NL;
                              Print('Message status is not sent.');
                              SysOpLog('Message status is not sent.');
                            END
                            ELSE
                            BEGIN
                              Include(MHeader.Status,Sent);
                              NL;
                              Print('Message status is sent.');
                              SysOpLog('Message status is sent.');
                            END;
                          END;

                    'S' : IF (NOT MsgSysOp) THEN
                          BEGIN
                            NL;
                            Print('^8You do not have the required access level for this option!^0')
                          END
                          ELSE IF (MHeader.FileAttached > 0) THEN
                          BEGIN
                            NL;
                            Print('^8There is no file attached to this message!^0');
                          END
                          ELSE
                          BEGIN
                            InputString('%LF^2Subj: ',MHeader.Subject,40,[InteractiveEdit],Changed);
                          { NL;
                            Prt('Subj: ');
                            InputDefault(MHeader.Subject,MHeader.Subject,40,[NoInputField],FALSE); }
                            SysOpLog('Message subject has been modified.');
                          END;

                    'T' : BEGIN
                            NL;
                            Print('^0(^11^0) Posted To   : ^1'+MHeader.MTo.A1S);
                            Print('^0(^12^0) Real Name   : ^1'+MHeader.MTo.Real);
                            Print('^0(^13^0) System Name : ^1'+MHeader.MTo.Name);
                            NL;
                            InputChar('^2Edit Names [^11^2-^13^2,<^1CR^2>Quit]: ',Cmd1,^M'123',[CapAll]);
                            CASE Cmd1 OF
                              '1' : BEGIN
                                      InputString('%LF^2Posted To: ',MHeader.MTo.A1S,36,[InteractiveEdit,
                                                  NoBlankPrompt,NoLineFeed],Changed);
                                    { NL;
                                      Prt('Posted to: ');
                                      InputDefault(MHeader.MTo.A1S,MHeader.MTo.A1S,36,[],FALSE); }
                                    END;
                              '2' : BEGIN
                                      InputString('%LF^2Real Name: ',MHeader.MTo.Real,36,[InteractiveEdit,
                                                  NoBlankPrompt,NoLineFeed],Changed);
                                    { NL;
                                      Prt('Real name: ');
                                      InputDefault(MHeader.MTo.Real,MHeader.MTo.Real,36,[],FALSE); }
                                    END;
                              '3' : BEGIN
                                      InputString('%LF^2System Name: ',MHeader.MTo.Name,36,[InteractiveEdit,
                                                  NoBlankPrompt,NoLineFeed],Changed);
                                    { NL;
                                      Prt('System name: ');
                                      InputDefault(MHeader.MTo.Name,MHeader.MTo.Name,36,[],FALSE); }
                                    END;
                            END;
                            Cmd1 := #0;
                          END;

                    'V' : IF (NOT Pub) THEN
                          BEGIN
                            NL;
                            Print('^8This option is not available when reading private messages!^0');
                          END
                          ELSE IF (NOT MsgSysOp) THEN
                          BEGIN
                            NL;
                            Print('^8You do not have the required access level for this option!^0')
                          END
                          ELSE
                          BEGIN
                            IF (UnValidated IN MHeader.Status) THEN
                            BEGIN
                              Exclude(MHeader.Status,UnValidated);
                              NL;
                              Print('Message status is validated.');
                              SysOpLog('Message status is validated.');
                            END
                            ELSE
                            BEGIN
                              Include(MHeader.Status,UnValidated);
                              NL;
                              Print('Message status is unvalidated.');
                              SysOpLog('Message status is unvalidated.');
                            END;
                          END;

                    '?' : BEGIN
                            NL;
                            LCmds(15,1,'From','To');
                            LCmds(15,1,'Subject','Edit text');
                            LCmds(15,1,'Oops','Display header');
                            IF (MsgSysOp) THEN
                            BEGIN
                              LCmds(15,1,'Permanent','Validation');
                              LCmds(15,1,'Rescan','Anonymous');
                            END;
                            LCmds(15,1,'Quit','');
                          END;
                  END;
                UNTIL (Cmd1 IN ['Q',^M]) OR (HangUp);
                Cmd1 := #0;
                SaveHeader(Msg_On,MHeader);
              END;
          6 : BEGIN
                DumpQuote(MHeader);
                IF (NOT Pub) THEN
                  AutoReply(MHeader)
                ELSE
                BEGIN
                  NL;
                  IF (MHeader.From.Anon = 0) OR (AACS(General.AnonPubRead)) THEN
                    IF PYNQ('Is this to be a private reply? ',0,Prvt IN MHeader.Status) THEN
                      IF (MAPrivate IN MemMsgArea.MAFlags) THEN
                        IF PYNQ('Reply in Email? ',0,FALSE) THEN
                          AutoReply(MHeader)
                        ELSE
                          Post(Msg_On,MHeader.From,TRUE)
                      ELSE
                        AutoReply(MHeader)
                    ELSE
                      Post(Msg_On,MHeader.From,FALSE)
                  ELSE
                    Post(Msg_On,MHeader.From,FALSE);
                END;
              END;
          7 : BEGIN
                Msg_On := (HiMsg + 1);
                IF (Pub) THEN
                BEGIN
                  LoadHeader(HiMsg,MHeader);
                  IF (MHeader.Date <= GetPackDateTime) THEN
                    TempLastRead := MHeader.Date;
                END;
                Next := FALSE;
              END;

          8 : IF (Pub) AND ((Msg_On - MHeader.ReplyTo) > 0) AND (MHeader.ReplyTo > 0) THEN
              BEGIN
                IF (ThreadStart = 0) THEN
                  ThreadStart := Msg_On;
                Dec(Msg_On,MHeader.ReplyTo);
              END;

          9 : IF (Pub) AND ((ThreadStart >= 1) AND (ThreadStart <= HiMsg)) THEN
              BEGIN
                Msg_On := ThreadStart;
                ThreadStart := 0;
              END;

         10 : BEGIN
                Contlist := TRUE;
                Abort := FALSE;
                NL;
                Print('Continuous message listing on.');
              END;
         11 : IF (Pub) THEN
              BEGIN
                IF (Permanent IN MHeader.Status) THEN
                BEGIN
                  NL;
                  Print('^8This is a permanent public message!^0');
                END
                ELSE
                BEGIN
                  IF (Msg_On >= 1) AND (Msg_On <= HiMsg) AND (MsgSysOp OR FromYou(MHeader)) THEN
                  BEGIN
                    LoadHeader(Msg_On,MHeader);
                    IF (MDeleted IN MHeader.Status) THEN
                      Exclude(MHeader.Status,MDeleted)
                    ELSE
                      Include(MHeader.Status,MDeleted);
                    SaveHeader(Msg_On,MHeader);
                    IF (NOT (MDeleted IN MHeader.Status)) THEN
                    BEGIN
                      IF FromYou(MHeader) THEN
                      BEGIN
                        IF (ThisUser.MsgPost < 2147483647) THEN
                          Inc(ThisUser.MsgPost);
                        AdjustBalance(General.Creditpost);
                      END;
                      NL;
                      Print('Public message undeleted.');
                      SysOpLog('* Undeleted public message: ^1'+MHeader.Subject);
                    END
                    ELSE
                    BEGIN
                      IF FromYou(MHeader) THEN
                      BEGIN
                        IF (ThisUser.MsgPost > 0) THEN
                          Dec(ThisUser.MsgPost);
                        AdjustBalance(-General.Creditpost);
                      END;
                      NL;
                      Print('Public message deleted.');
                      SysOpLog('* Deleted public message: ^1'+MHeader.Subject);
                    END;
                  END
                  ELSE
                  BEGIN
                    NL;
                    Print('^8You can only delete public messages from you!^0');
                  END;
                END;
              END
              ELSE
              BEGIN
                IF (Msg_On >= 1) AND (Msg_On <= HiMsg) AND (MsgSysOp OR FromYou(MHeader) OR ToYou(MHeader)) THEN
                BEGIN
                  LoadHeader(Msg_On,MHeader);
                  IF (MDeleted IN MHeader.Status) THEN
                    Exclude(MHeader.Status,MDeleted)
                  ELSE
                    Include(MHeader.Status,MDeleted);
                  SaveHeader(Msg_On,MHeader);
                  IF (NOT (MDeleted IN MHeader.Status)) THEN
                  BEGIN
                    LoadURec(User,MHeader.MTo.UserNum);
                    IF (User.Waiting < 255) THEN
                      Inc(User.Waiting);
                    SaveURec(User,MHeader.MTo.UserNum);
                    NL;
                    Print('Private message undeleted.');
                    IF FromYou(MHeader) OR (MsgSysOp) THEN
                      SysOpLog('* Undeleted private message from: ^1'+Caps(MHeader.From.A1S))
                    ELSE IF ToYou(MHeader) OR (MsgSysOp) THEN
                      SysOpLog('* Undeleted private message to: ^1'+Caps(MHeader.MTo.A1S));
                  END
                  ELSE
                  BEGIN
                    LoadURec(User,MHeader.MTo.UserNum);
                    IF (User.Waiting > 0) THEN
                      Dec(User.Waiting);
                    SaveURec(User,MHeader.MTo.UserNum);
                    NL;
                    Print('Private message deleted.');
                    IF FromYou(MHeader) OR (MsgSysOp) THEN
                      SysOpLog('* Deleted private message from: ^1'+Caps(MHeader.From.A1S))
                    ELSE IF ToYou(MHeader) OR (MsgSysOp) THEN
                      SysOpLog('* Deleted private message to: ^1'+Caps(MHeader.MTo.A1S));
                  END;
                END
                ELSE
                BEGIN
                  NL;
                  Print('^8You can only delete private messages from or to you!^0');
                END;
              END;
         12 : IF (NOT Pub) THEN
              BEGIN
                NL;
                Print('^8This option is not available when reading private messages!^0');
              END
              ELSE
              BEGIN
                NL;
                Print('Highest-read pointer for this area set to message #'+IntToStr(Msg_On)+'.');
                IF (MHeader.Date <= GetPackDateTime) THEN
                  TempLastRead := MHeader.Date;
              END;
         13 : BEGIN
                { Lightbar message selector / jump-to-message }
                IF (HiMsg = 0) THEN
                  BEGIN
                    NL;
                    Print('No messages to select.');
                  END
                ELSE
                  BEGIN
                    MsgSel_EscPressed := FALSE;
                    MsgSel_IgnoreRemaining := FALSE;
                    SelectMsgLightBar(Msg_On,HiMsg,Pub);
                    IF MsgSel_IgnoreRemaining THEN
                    BEGIN
                      { Ignore remaining exits to message menu }
                      TReadPrompt := 7;
                      DoneScan := TRUE;
                      Abort := TRUE;
                    END
                    ELSE IF MsgSel_EscPressed THEN
                    BEGIN
                      { ESC/Q cancels selector and exits cleanly }
                      TReadPrompt := 7;
                      DoneScan := TRUE;
                      Abort := TRUE;
                    END
                    ELSE
                      { Force re-read at the newly selected message }
                      TReadPrompt := 1;
                  END;
              END;
         14 : BEGIN
                DoneScan := TRUE;
                Abort := TRUE;
              END;
         15 : BEGIN
                { R+L : List Messages (lightbar-select when enabled) }
                IF (NOT OkANSI) OR (NOT General.UseLightBars) OR
                   (NOT (LightBars IN ThisUser.SFlags)) THEN
                  ListMessages(Pub)
                ELSE
                BEGIN
                  RL_IgnoreRemaining := FALSE;
                   RL_EscPressed := FALSE;
                   RL_ListLightBarSelect(Msg_On,Pub);
                   IF (RL_EscPressed) THEN
                   BEGIN
                     { ESC/Q exits to msg menu }
                     TReadPrompt := 7;
                     DoneScan := TRUE;
                     Abort := TRUE;
                   END
                   ELSE IF (RL_IgnoreRemaining) THEN
                   BEGIN
                     { Ignore Remaining: mark hi-read and continue new scan }
                     LoadHeader(HiMsg, MHeader);
                     TempLastRead := MHeader.Date;
                     DoneScan := TRUE;
                     Abort := FALSE;
                   END
                   ELSE
                     TReadPrompt := 1;
                END;
              END;
         16 : IF (NOT CoSysOp) THEN
                Print('^8You do not have the required access level for this option!^0')
              ELSE IF (LastAuthor < 1) OR (LastAuthor > (MaxUsers - 1)) THEN
                Print('^8The sender of this message does not have an account on this BBS!^0')
              ELSE IF (CheckPW) THEN
                UserEditor(LastAuthor);
         17 : IF (NOT PUB) THEN
              BEGIN
                NL;
                Print('^8This option is not available when reading private messages!^0');
              END
              ELSE
              BEGIN
                IF (MAForceRead IN MemMsgArea.MAFlags) THEN
                BEGIN
                  NL;
                  Print('^8This message area can not be removed from your new scan!^0')
                END
                ELSE
                BEGIN

                  NL;
                  Print('^1'+MemMsgArea.Name+'^1 '+AOnOff(LastReadRecord.NewScan,'will NOT','WILL')+
                        ' be scanned in future new scans.');
                  SysOpLog('* Toggled ^1'+MemMsgArea.Name+ '^0 '+AOnOff(LastReadRecord.NewScan,'out of','back in')+
                           ' new scan.');

                  LoadLastReadRecord(LastReadRecord);
                  LastReadRecord.NewScan := (NOT LastReadRecord.NewScan);
                  SaveLastReadRecord(LastReadRecord);
                END;
              END;
         18 : Inc(Msg_On);
         19 : IF (NOT CoSysOp) THEN
                Print('^8You do not have the required access level for this option!^0')
              ELSE IF (LastAuthor < 1) OR (LastAuthor > (MaxUsers - 1)) THEN
                Print('^8The sender of this message does not have an account on this BBS!^0.')
              ELSE
              BEGIN
                LoadURec(User,LastAuthor);
                ShowUserInfo(1,LastAuthor,User);
              END;
         20 : IF (NOT CoSysOp) THEN
                Print('^8You do not have the required access level for this option!^0')
              ELSE IF (LastAuthor < 1) OR (LastAuthor > (MaxUsers - 1)) THEN
                Print('^8The sender of this message does not have an account on this BBS!^0')
              ELSE
              BEGIN
                LoadURec(User,LastAuthor);
                AutoVal(User,LastAuthor);
              END;
         21 : ForwardMessage(Msg_On);
        END;
      UNTIL (TReadPrompt IN [1..2,7..10,13..15,18]) OR (Abort) OR (Next) OR (HangUp)
    ELSE
      Inc(Msg_On);

    IF (OncOnly) AND (TReadPrompt IN [13,14,18]) THEN
      DoneScan := TRUE;

  UNTIL (DoneScan) OR (HangUp);

  CurMenu := SaveMenu;

  NewMenuToLoad := TRUE;

  AllowContinue := FALSE;

  IF ((Pub) AND (HadUnVal) AND (MsgSysOp)) THEN
    IF PYNQ('%LFValidate all messages here? ',0,FALSE) THEN
    BEGIN
      FOR MsgNum := 1 TO HiMsg DO
      BEGIN
        LoadHeader(MsgNum,MHeader);
        IF (UnValidated IN MHeader.Status) THEN
          Exclude(MHeader.Status,UnValidated);
        SaveHeader(MsgNum,MHeader);
      END;
    END;

  IF ((Pub) AND (AskPost) AND (AACS(MemMsgArea.PostACS)) AND
     (NOT (RPost IN ThisUser.ACFlags)) AND (PublicPostsToday < General.MaxPubPost)) THEN
    IF (TReadPrompt <> 7) THEN
      IF PYNQ('%LFPost on ^1'+MemMsgArea.Name+'^8? ',0,FALSE) THEN
        IF (MAPrivate IN MemMsgArea.MAFlags) THEN
          Post(-1,MHeader.From,PYNQ('%LFIs this to be a private message? ',0,FALSE))
        ELSE
          Post(-1,MHeader.From,FALSE);
END;

PROCEDURE ReadAllMessages(MenuOption: Str50);
VAR
  InputStr: AStr;
  SaveReadMsgArea: Integer;
BEGIN
  SaveReadMsgArea := ReadMsgArea;
  Abort := FALSE;
  Next := FALSE;
  IF (MenuOption = '') THEN
    MsgArea := -1;
  InitMsgArea(MsgArea);
  IF (HiMsg = 0) THEN
    BEGIN
      Print('%LFNo messages on ^1'+MemMsgArea.Name+'^0.');
      IF (Novice IN ThisUser.ACFlags) THEN
        PauseScr(FALSE);
    END
  ELSE
    BEGIN      Msg_On := 1;

      { When lightbars are enabled, use the same selector as R+L }
      IF (OkANSI) AND (General.UseLightBars) AND (LightBars IN ThisUser.SFlags) THEN
      BEGIN
        RL_ListLightBarSelect(Msg_On,(MsgArea <> -1));
         { ESC/Q or Ignore Remaining should exit M+R cleanly }
         IF (RL_EscPressed) OR (RL_IgnoreRemaining) THEN
         BEGIN
           Msg_On := 0;
         END;
      END
      ELSE
      BEGIN
        InputStr := '?';
        REPEAT
          IF (InputStr = '?') THEN
            ListMessages(MsgArea <> -1);
          NL;
          lRGLngStr(32,FALSE);
          ScanInput(InputStr,'Q?'^M);
          IF (InputStr = 'Q') THEN
            Msg_On := 0
          ELSE
            BEGIN
              IF (InputStr = ^M) THEN
                BEGIN
                  InputStr := '?';
                  IF (Msg_On >= HiMsg) THEN
                    Msg_On := 1;
                END
              ELSE IF (InputStr = '?') THEN
                BEGIN
                  Msg_On := 1;
                  InputStr := '?';
                END
              ELSE
                BEGIN
                  Msg_On := StrToInt(InputStr);
                  IF (Msg_On >= 1) AND (Msg_On <= HiMsg) THEN
                    InputStr := 'Q'
                  ELSE
                    BEGIN
                      NL;
                      Print('^8The range must be from 1 to '+IntToStr(HiMsg)+'^0');
                      PauseScr(FALSE);
                      Msg_On := 1;
                      InputStr := '?';
                    END;
                END;
            END;
        UNTIL (InputStr = 'Q') OR (HangUp);
      END;
      IF (Msg_On >= 1) AND (Msg_On <= HiMsg) AND (NOT HangUp) THEN
        BEGIN
          IF (MsgArea <> -1) THEN
            BEGIN
              LoadLastReadRecord(LastReadRecord);
              TempLastRead := LastReadRecord.LastRead;
            END;
          WHILE KeyPressed DO ReadKey;

          MainRead(FALSE,FALSE,(MsgArea <> -1));
          IF (MsgArea <> -1) THEN
            BEGIN
              LastReadRecord.LastRead := TempLastRead;
              SaveLastReadRecord(LastReadRecord);
            END;
        END;
    END;
  MsgArea := SaveReadMsgArea;
  LoadMsgArea(MsgArea);
END;

FUNCTION FirstNew: Word;
VAR
  MHeader: MHeaderRec;
  MaxMsgs,
  MsgNum: Word;
  Done: Boolean;
BEGIN
  MaxMsgs := HiMsg;
  MsgNum := 0;
  IF (MaxMsgs > 0) THEN
  BEGIN
    Done := FALSE;
    MsgNum := 1;
    WHILE (MsgNum <= MaxMsgs) AND (NOT Done) DO
    BEGIN
      LoadHeader(MsgNum,MHeader);
      IF (LastReadRecord.LastRead < MHeader.Date) AND NOT (MDeleted IN MHeader.Status) THEN {leew: added mdeleted}

      { add this instead
          CantBeSeen := (NOT MsgSysOp) AND ((UnValidated IN MHeader.Status) OR (MDeleted IN MHeader.Status) OR
                  ((Prvt IN MHeader.Status) AND NOT (ToYou(MHeader) OR FromYou(MHeader))));
      }
        Done := TRUE
      ELSE
      {(UnValidated IN MHeader.Status)(Prvt IN MHeader.Status) leew more maybe}
      BEGIN
        IF (MsgNum < MaxMsgs) THEN
          Inc(MsgNum,1)
        ELSE
        BEGIN
          MsgNum := 0;
          Done := TRUE;
        END;
      END;
    END;
  END;
  FirstNew := MsgNum;
END;

PROCEDURE ScanMessages(MArea: Integer; AskUpdate: Boolean; MenuOption: Str50);
VAR
  ScanFor: STRING[40];
  Cmd: Char;
  SaveMsgArea,
  MsgNum: Word;
  ScanNew,
  ScanGlobal: Boolean;

  PROCEDURE Searchboard(MArea1: Integer; Cmd1: Char);
  VAR
    MsgHeader: MHeaderRec;
    Searched: STRING;
    TotLoad: Word;
    Match,
    AnyShown: Boolean;
  BEGIN
    IF (MsgArea <> MArea1) THEN
      ChangeMsgArea(MArea1);
    IF (MsgArea = MArea1) THEN
    BEGIN
      InitMsgArea(MsgArea);
      AnyShown := FALSE;
      LIL := 0;
      CLS;
      Prompt('^0Scanning ^1'+MemMsgArea.Name+' #'+IntToStr(CompMsgArea(MsgArea,0))+' ^0...');
      Reset(MsgHdrF);
      Reset(MsgTxtF,1);
      IF (IOResult <> 0) THEN
        Exit;
      IF (ScanNew) THEN
        MsgNum := FirstNew
      ELSE
        MsgNum := 1;
      IF (MsgNum > 0) AND (FileSize(MsgHdrF) > 0) THEN
        WHILE (MsgNum <= FileSize(MsgHdrF)) AND (NOT Next) AND (NOT Abort) AND (NOT HangUp) DO
        BEGIN
          LoadHeader(MsgNum,MsgHeader);
          Match := FALSE;
          IF (Cmd1 IN ['Y',^M]) THEN
            IF ToYou(MsgHeader) THEN
              Match := TRUE;
          IF (Cmd1 IN ['F','A']) THEN
          BEGIN
            IF (MARealName IN MemMsgArea.MAFlags) THEN
              Searched := MsgHeader.From.Real
            ELSE
              Searched := MsgHeader.From.A1S;
            IF (MemMsgArea.MAtype = 0) THEN
              Searched := Searched;
            Searched := AllCaps(UseName(MsgHeader.From.Anon,Searched));
            IF (Pos(ScanFor,Searched) > 0) THEN
              Match := TRUE;
          END;
          IF (Cmd1 IN ['T','A'] ) THEN
          BEGIN
            IF (MARealName IN MemMsgArea.MAFlags) THEN
              Searched := MsgHeader.MTo.Real
            ELSE
              Searched := MsgHeader.MTo.A1S;
            IF (MemMsgArea.MAtype = 0) THEN
              Searched := Searched;
            Searched := AllCaps(UseName(MsgHeader.MTo.Anon,Searched));
            IF (Pos(ScanFor,Searched) > 0) THEN
              Match := TRUE;
          END;
          IF (Cmd1 IN ['S','A'] ) THEN
            IF (Pos(ScanFor,AllCaps(MsgHeader.Subject)) > 0) THEN
              Match := TRUE;
          IF (Cmd1 = 'A') AND (NOT Match) AND (MsgHeader.TextSize > 0) AND
             (((MsgHeader.Pointer - 1) + MsgHeader.TextSize) <= FileSize(MsgTxtF)) AND
             (MsgHeader.Pointer > 0) THEN
            WITH MsgHeader DO
            BEGIN
              Seek(MsgTxtF,(Pointer - 1));
              TotLoad := 0;
              REPEAT
                BlockRead(MsgTxtF,Searched[0],1);
                BlockRead(MsgTxtF,Searched[1],Ord(Searched[0]));
                LastError := IOResult;
                Inc(TotLoad,Length(Searched) + 1);
                IF (Pos(ScanFor,AllCaps(Searched)) > 0) THEN
                  Match := TRUE;
              UNTIL (TotLoad >= TextSize) OR (Match);
            END;
          IF (Match) THEN
          BEGIN
            Close(MsgHdrF);
            Close(MsgTxtF);
            Msg_On := MsgNum;
            NL;
            MainRead(TRUE,AskUpdate,(MsgArea <> -1));
            NL;
            Reset(MsgHdrF);
            Reset(MsgTxtF,1);
            AnyShown := TRUE;
          END;
          Wkey;
          IF (Next) THEN
            Abort := TRUE;
          Inc(MsgNum);
        END;
      Close(MsgHdrF);
      Close(MsgTxtF);
      IF (NOT AnyShown) THEN
        BackErase(14 + Lennmci(MemMsgArea.Name) + Length(IntToStr(CompMsgArea(MsgArea,0))));
    END;
  END;

BEGIN
  SaveMsgArea := MsgArea;
  ScanNew := FALSE;
  ScanGlobal := FALSE;
  MenuOption := AllCaps(MenuOption);
  IF (MenuOption <> '') THEN
    Cmd := 'Y'
  ELSE
    Cmd := #0;
  IF (Pos('N',MenuOption) > 0) THEN
    ScanNew := TRUE;
  IF (Pos('G',MenuOption) > 0) THEN
    ScanGlobal := TRUE;
  IF (Cmd = #0) THEN
    REPEAT
      NL;
      InputChar('Scan method (^1?^2=^1Help^2): ',Cmd,'QFTSAY?'^M,[CapAll]);
      IF (Cmd = '?') THEN
      BEGIN
        NL;
        LCmds(15,1,'From field','To field');
        LCmds(15,1,'Subject field','All text');
        LCmds(15,1,'Your messages','Quit');
      END;
    UNTIL (Cmd <> '?') OR (HangUp);
  NL;
  IF (NOT (Cmd IN ['Q',^M])) THEN
  BEGIN
    IF (Cmd <> 'Y') THEN
    BEGIN
      Prt('Text to scan for: ');
      InputMain(ScanFor,SizeOf(ScanFor)-1,[CapAll]);
      IF (ScanFor = '') THEN
        Exit;
      NL;
    END;
    IF (MenuOption = '') THEN
      ScanNew := PYNQ('Scan new messages only? ',0,TRUE);
    IF (ScanGlobal) OR ((MenuOption = '') AND PYNQ('Global scan? ',0,FALSE)) THEN
    BEGIN
      MArea := 1;
      WHILE (MArea >= 1) AND (MArea <= NumMsgAreas) AND (NOT Abort) AND (NOT HangUp) DO
      BEGIN
        Searchboard(MArea,Cmd);
        Wkey;
        Inc(MArea);
      END;
    END
    ELSE
      Searchboard(MArea,Cmd);
  END;
  MsgArea := SaveMsgArea;
  LoadMsgArea(MsgArea);
END;

PROCEDURE ScanYours;
VAR
  ScanAllPublicMsgFile: FILE OF Boolean;
  MsgHeader: MHeaderRec;
  MArea,
  SaveMsgArea: Integer;
  MsgNum,
  PubMsgsFound: Word;
  SaveConfSystem,
  AnyFound,
  FirstTime,
  MsgsFound: Boolean;
BEGIN
  SaveMsgArea := MsgArea;
  SaveConfSystem := ConfSystem;
  ConfSystem := FALSE;
  IF (SaveConfSystem) THEN
    NewCompTables;
  Assign(ScanAllPublicMsgFile,TempDir+'SAPM'+IntToStr(ThisNode)+'.DAT');
  ReWrite(ScanAllPublicMsgFile);
  FOR MArea := 1 TO NumMsgAreas DO
  BEGIN
    MsgsFound := FALSE;
    Write(ScanAllPublicMsgFile,MsgsFound);
  END;
  {Prompt('%LF|11S|03canning |11F|03or |11Y|03our |15NEW |11P|03ublic |11M|03essages |11. . . ');}
  lRGLngStr(278,FALSE);
  FirstTime := TRUE;
  AnyFound := FALSE;
  MArea := 1;
  WHILE (MArea >= 1) AND (MArea <= NumMsgAreas) AND (NOT Abort) AND (NOT HangUp) DO
  BEGIN
    IF (MsgArea <> MArea) THEN
      ChangeMsgArea(MArea);
    IF (MsgArea = MArea) THEN
    BEGIN
      InitMsgArea(MsgArea);
      IF (LastReadRecord.NewScan) THEN
      BEGIN
        Reset(MsgHdrF);
        Reset(MsgTxtF,1);
        IF (IOResult = 0) THEN
        BEGIN
          PubMsgsFound := 0;
          MsgNum := FirstNew;
          IF (MsgNum > 0) AND (FileSize(MsgHdrF) > 0) THEN
            WHILE (MsgNum <= FileSize(MsgHdrF)) AND (NOT HangUp) DO
            BEGIN
              LoadHeader(MsgNum,MsgHeader);
              IF (ToYou(MsgHeader)) THEN
              BEGIN
                Seek(ScanAllPublicMsgFile,(MArea - 1));
                MsgsFound := TRUE;
                Write(ScanAllPublicMsgFile,MsgsFound);
                Inc(PubMsgsFound);
              END;
              Inc(MsgNum);
            END;
          Close(MsgHdrF);
          Close(MsgTxtF);
          IF (PubMsgsFound > 0) THEN
          BEGIN
            IF (FirstTime) THEN
            BEGIN
              NL;
              {NL;}
              FirstTime := FALSE;
            END;
            {Print('^1'+PadLeftStr(MemMsgArea.Name,30)+' ^0'+IntToStr(PubMsgsFound));}
            LangStringArray[0] := MemMsgArea.Name;
            LangStringArray[1] := IntToStr(PubMsgsFound);
            lRGLngStr(279,FALSE);
            AnyFound := TRUE;
          END;
        END;
      END;
    END;
    Inc(MArea);
  END;
  Close(ScanAllPublicMsgFile);
  IF (NOT AnyFound) THEN
    lRGLngStr(280,FALSE)
    {Print('|15NO |11M|03essages |11F|03ound|11.')}
  ELSE
  BEGIN
    Abort := FALSE;
    Next := FALSE;
    {NL;}
    IF PYNQ(lRGLngStr(281,TRUE){;'Read your new public messages now? '},0,FALSE) THEN
    BEGIN
      Assign(ScanAllPublicMsgFile,TempDir+'SAPM'+IntToStr(ThisNode)+'.DAT');
      Reset(ScanAllPublicMsgFile);
      MArea := 1;
      WHILE (MArea >= 1) AND (MArea <= NumMsgAreas) AND (NOT Abort) AND (NOT HangUp) DO
      BEGIN
        Seek(ScanAllPublicMsgFile,(MArea - 1));
        Read(ScanAllPublicMsgFile,MsgsFound);
        IF (MsgsFound) THEN
          ScanMessages(MArea,TRUE,'N');
        WKey;
        Inc(MArea);
      END;
      Close(ScanAllPublicMsgFile);
    END;
  END;
  ConfSystem := SaveConfSystem;
  IF (SaveConfSystem) THEN
    NewCompTables;
  MsgArea := SaveMsgArea;
  LoadMsgArea(MsgArea);
  LastError := IOResult;
END;

PROCEDURE StartNewScan(MenuOption: Str50);
VAR
  MArea,
  SaveMsgArea: Integer;
  Global: Boolean;

  PROCEDURE NewScan(MArea1: Integer);
  BEGIN
    IF (MsgArea <> MArea1) THEN
      ChangeMsgArea(MArea1);
    IF (MsgArea = MArea1) THEN
      BEGIN
        InitMsgArea(MsgArea);
        IF (LastReadRecord.NewScan) OR ((MAForceRead IN MemMsgArea.MAFlags) AND (NOT CoSysOp)) THEN
          BEGIN
            TempLastRead := LastReadRecord.LastRead;
            Lil := 0;
            lRGLngStr(8,FALSE); {"Scanning ..."}
            Msg_On := FirstNew;
            IF (Msg_On > 0) THEN
              MainRead(FALSE,FALSE,(MsgArea <> -1));
            LastReadRecord.LastRead := TempLastRead;
            SaveLastReadRecord(LastReadRecord);
            (*  Add backarase *)
            lRGLngStr(9,FALSE); {"Done!"}
          END;
        IF NOT (Global) THEN
          SysOpLog('New scan of message area #'+IntToStr(MsgArea)); {LeeW: Add name}
      END;
  END;

BEGIN
  SaveMsgArea := MsgArea;
  MArea := MsgArea;
  Global := FALSE;
  Abort := FALSE;
  Next := FALSE;
  IF (UpCase(MenuOption[1]) = 'C') THEN
    MArea := MsgArea
  ELSE IF (UpCase(MenuOption[1]) = 'G') THEN
    Global := TRUE
  ELSE IF (StrToInt(MenuOption) <> 0) THEN
    MArea := StrToInt(MenuOption)
  ELSE IF (MenuOption = '') THEN
    Global := PYNQ('%LFScan all message areas? ',0,FALSE);
  IF (NOT Global) THEN
    NewScan(MArea)
  ELSE
    BEGIN
      MArea := 1;
      lRGLngStr(35,FALSE); {"Global new message scan beginning"}
      WHILE (MArea >= 1) AND (MArea <= NumMsgAreas) AND (NOT Abort) AND (NOT HangUp) DO
        BEGIN
          NewScan(MArea);
          WKey;
          Inc(MArea);
        END;
      lRGLngStr(36,FALSE); {"Global new message scan complete"}
      SysOpLog('Global new scan of message areas');
    END;
  MsgArea := SaveMsgArea;
  LoadMsgArea(MsgArea);
END;
END.