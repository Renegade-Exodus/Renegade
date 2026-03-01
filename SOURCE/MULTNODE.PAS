{$A+,B-,D-,E-,F+,I-,L-,N-,O+,R-,S+,V-}

UNIT Multnode;

INTERFACE

USES
  Crt,
  Common;

PROCEDURE CheckStatus;
PROCEDURE DumpNode;
PROCEDURE ListNodes;
PROCEDURE MessageNode(CONST b: ASTR);
PROCEDURE PageNode;
PROCEDURE TeleConfCheck;
PROCEDURE TeleConference;
PROCEDURE ToggleChatAvailability;

IMPLEMENTATION

USES
    Doors,
  Menus,
  Script,
  ShortMsg,
  TimeFunc;

FUNCTION IntToStr(N: LongInt): STRING;
VAR
  S: STRING;
BEGIN
  Str(N, S);
  IntToStr := S;
END;

FUNCTION TC_CapsThis(S: STRING): STRING;
VAR
  I: Integer;
  UpNext: Boolean;
  C: Char;
BEGIN
  UpNext := TRUE;
  FOR I := 1 TO Length(S) DO
  BEGIN
    C := S[I];
    {lowercase A-Z}
    IF (C >= 'A') AND (C <= 'Z') THEN
      S[I] := Chr(Ord(C) + 32);
    {uppercase first letter of each word}
    IF UpNext THEN
    BEGIN
      C := S[I];
      IF (C >= 'a') AND (C <= 'z') THEN
        S[I] := Chr(Ord(C) - 32);
    END;
    C := S[I];
    {next word after non-alphanum}
    UpNext := NOT (((C >= 'a') AND (C <= 'z')) OR ((C >= 'A') AND (C <= 'Z')) OR ((C >= '0') AND (C <= '9')));
  END;
  TC_CapsThis := S;
END;


VAR
  TeleConfInputLine: STRING;   {Current line being typed in TeleConference InputMain}
  TeleConfActive: BOOLEAN;     {True while in TeleConference}
  TCChatTop: Byte;             {Top row of scrolling chat area (below header)}

CONST
  TC_CHAT_TOP_DEFAULT = 6;
  TC_CHAT_BOTTOM = 21;  {reserve last 2 rows (24-25) for status bar}
  TC_DIV_ROW     = 22;
  TC_INPUT_ROW   = 23;
  TC_STATUS_ROW  = 25;

{ Local window helpers (SysOp console).  Uses CRT windowing to keep chat from scrolling the status bar. }
PROCEDURE TC_LocalChatWindowOn;
BEGIN
  {Chat area only}
  Window(1, TCChatTop, 80, TC_CHAT_BOTTOM);
END;

FUNCTION TC_LocalBottomY: Byte;
BEGIN
  TC_LocalBottomY := TC_CHAT_BOTTOM - TCChatTop + 1;
END;

PROCEDURE TC_LocalFullWindow;
BEGIN
  Window(1, 1, 80, 25);
END;




FUNCTION TC_RepeatChar(C: Char; N: Byte): STRING;
VAR
  I: Byte;
  S: STRING;
BEGIN
  S := '';
  FOR I := 1 TO N DO
    S := S + C;
  TC_RepeatChar := S;
END;

PROCEDURE TC_SendAnsiStr(CONST A: STRING);
VAR
  T: AStr;
BEGIN
  {Send raw ANSI only to the remote user.  Local console uses direct screen writes.}
  IF (OkANSI) AND (ComPortSpeed > 0) THEN
  BEGIN
    T := A;
    SerialOut(T);
  END;
END;




{ ===== Remote Chat Buffer + Redraw (fTelnet-safe) ===== }

CONST
  TC_REMOTE_MAX = 16;  {rows 6..21}

VAR
  TC_RemoteBuf : ARRAY[1..TC_REMOTE_MAX] OF STRING;
  TC_RemoteCnt : Byte;

PROCEDURE TC_RemoteInit;
VAR
  i: Byte;
BEGIN
  TC_RemoteCnt := 0;
  FOR i := 1 TO TC_REMOTE_MAX DO
    TC_RemoteBuf[i] := '';
END;

PROCEDURE TC_RemoteAddLine(CONST L: STRING);
VAR
  i: Byte;
BEGIN
  IF TC_RemoteCnt < TC_REMOTE_MAX THEN
  BEGIN
    Inc(TC_RemoteCnt);
    TC_RemoteBuf[TC_RemoteCnt] := L;
  END
  ELSE
  BEGIN
    FOR i := 1 TO TC_REMOTE_MAX-1 DO
      TC_RemoteBuf[i] := TC_RemoteBuf[i+1];
    TC_RemoteBuf[TC_REMOTE_MAX] := L;
  END;
END;

PROCEDURE TC_RemoteRedraw;
VAR
  i, row: Byte;
BEGIN
  IF NOT ((OkANSI) AND (ComPortSpeed > 0)) THEN
    Exit;

    {Draw buffered lines bottom-aligned so chat grows upward}
  IF TC_RemoteCnt < TC_REMOTE_MAX THEN
    row := TC_CHAT_BOTTOM - TC_RemoteCnt + 1
  ELSE
    row := TC_CHAT_TOP_DEFAULT;
FOR i := 1 TO TC_REMOTE_MAX DO
  BEGIN
    TC_SendAnsiStr(#27+'['+IntToStr(row)+';1H');
    TC_SendAnsiStr(#27+'[0m'+#27+'[37;40m'+#27+'[2K');
    IF (i <= TC_RemoteCnt) AND (TC_RemoteBuf[i] <> '') THEN
      TC_SendAnsiStr(TC_RemoteBuf[i]);
    Inc(row);
  END;
END;

{ ===== End Remote Chat Buffer ===== }

PROCEDURE TC_GotoXY(X, Y: Byte);
BEGIN
  {Move local cursor - Exo }
  GotoXY(X, Y);
  {Move remote cursor via ANSI (do NOT rely on ANSIG which is mostly remote-only - Exo)}
  IF (OkANSI) AND (ComPortSpeed > 0) THEN
    TC_SendAnsiStr(#27+'['+IntToStr(Y)+';'+IntToStr(X)+'H');
END;

PROCEDURE TC_SetDefaultAttr;
BEGIN
  {Force sane default attributes (white on black) so clears don't "paint" with a colored background - Exo}
  TC_SendAnsiStr(#27+'[0m'+#27+'[37;40m');
END;


FUNCTION TC_PipeToAnsi(s: STRING): STRING;
VAR
  i: Integer;
  code, fg: Integer;
  bright: Boolean;
  outS: STRING;
BEGIN
  outS := '';
  i := 1;
  WHILE i <= Length(s) DO
  BEGIN
    IF (s[i] = '|') AND (i < Length(s)) THEN
    BEGIN
      IF (s[i+1] = '|') THEN
      BEGIN
        outS := outS + '|';
        Inc(i,2);
        Continue;
      END;

      { |XX color code -Exo}
      IF (i+2 <= Length(s)) AND (s[i+1] IN ['0'..'9']) AND (s[i+2] IN ['0'..'9']) THEN
      BEGIN
        code := (Ord(s[i+1]) - Ord('0'))*10 + (Ord(s[i+2]) - Ord('0'));
        IF (code >= 0) AND (code <= 15) THEN
        BEGIN
          bright := (code >= 8);
          fg := code MOD 8;

          {Force black background - Exo}
          outS := outS + #27 + '[';
          IF bright THEN
            outS := outS + '1;'
          ELSE
            outS := outS + '0;';
          outS := outS + IntToStr(30 + fg) + ';40m';

          Inc(i,3);
          Continue;
        END;
      END;
    END;

    outS := outS + s[i];
    Inc(i);
  END;

  TC_PipeToAnsi := outS;
END;

FUNCTION TC_StripAnsi(CONST S: STRING): STRING;
{Removes ANSI ESC[... sequences so local console doesn't show raw codes -Exo}
VAR
  i, j: Integer;
  outS: STRING;
BEGIN
  outS := '';
  i := 1;
  WHILE i <= Length(S) DO
  BEGIN
    IF (S[i] = #27) THEN
    BEGIN
      {Skip ESC[ ... <final>}
      Inc(i);
      IF (i <= Length(S)) AND (S[i] = '[') THEN
      BEGIN
        Inc(i);
        j := i;
        WHILE (j <= Length(S)) AND NOT (S[j] IN ['A'..'Z','a'..'z']) DO Inc(j);
        IF (j <= Length(S)) THEN
          i := j + 1
        ELSE
          i := Length(S) + 1;
      END
      ELSE
        Inc(i);
    END
    ELSE
    BEGIN
      outS := outS + S[i];
      Inc(i);
    END;
  END;
  TC_StripAnsi := outS;
END;


FUNCTION TC_NormalizeChatLine(s: STRING): STRING;
VAR
  i, j: Integer;
  t: STRING;
BEGIN
  WHILE (Length(s) > 0) DO
  BEGIN
    IF (s[1] = #13) OR (s[1] = #10) THEN
      Delete(s,1,1)
    ELSE
      Break;
  END;

  WHILE (Length(s) > 0) DO
  BEGIN
    IF (s[Length(s)] = #13) OR (s[Length(s)] = #10) THEN
      Delete(s, Length(s), 1)
    ELSE
      Break;
  END;


  t := '';
  i := 1;
  WHILE i <= Length(s) DO
  BEGIN
    IF s[i] = '%' THEN
    BEGIN
      j := i + 1;
      WHILE (j <= Length(s)) AND (s[j] <> '%') DO
        Inc(j);
      IF (j <= Length(s)) AND (s[j] = '%') THEN
      BEGIN
        i := j + 1;  {skip token}
        Continue;
      END;
    END;
    t := t + s[i];
    Inc(i);
  END;
  s := t;


i := 1;
WHILE (i <= Length(s)) DO
BEGIN
  IF (s[i] = '^') AND (i < Length(s)) AND (s[i+1] in ['0'..'9','A'..'F','a'..'f']) THEN
  BEGIN
    Delete(s, i, 2);
    Continue;
  END;
  Inc(i);
END;


  i := 1;
  WHILE i <= Length(s) DO
  BEGIN
    IF (Ord(s[i]) < 32) AND (s[i] <> #27) THEN
    BEGIN
      Delete(s,i,1);
      Continue;
    END;
    Inc(i);
  END;
  TC_NormalizeChatLine := s;
END;

PROCEDURE TC_SetScrollRegion(TopRow, BottomRow: Byte);
BEGIN
  {ESC[<top>;<bottom>r}
  TC_SendAnsiStr(#27+'['+IntToStr(TopRow)+';'+IntToStr(BottomRow)+'r');
END;


PROCEDURE TC_ApplyScrollRegion;
BEGIN
  TC_SetScrollRegion(TC_CHAT_TOP_DEFAULT, TC_CHAT_BOTTOM);
END;

PROCEDURE TC_InitUI;
BEGIN
  CLS;
  TC_SendAnsiStr(#27+'[0m'+#27+'[37;40m');
  TC_SetScrollRegion(1,25);
END;

PROCEDURE TC_RestoreUI;
BEGIN
  {Restore full-screen scrolling region for remote - Exo}
  TC_SetScrollRegion(1,25);
  TC_SendAnsiStr(#27+'[0m'+#27+'[37;40m'+#27+'[?25h');

  {Local: restore full window - Exo}
  Window(1,1,80,25);
END;

PROCEDURE TC_ClearLine(Row: Byte);
VAR
  i: Integer;
BEGIN
  {Remote: clear entire line - Exo}
  TC_SendAnsiStr(#27+'['+IntToStr(Row)+';1H'+#27+'[2K');

  {Local: move and overwrite with spaces (local console is direct screen, not ANSI)}
  GotoXY(1, Row);
  FOR i := 1 TO 80 DO
    Write(' ');
  GotoXY(1, Row);
END;

PROCEDURE TC_RedrawInput;
VAR
  SaveMCIAllowed: Boolean;
  SaveColor: Byte;
BEGIN
    {Ensure input bar is fully painted}
  TC_ClearLine(TC_INPUT_ROW);
SaveColor := CurrentColor;
  SaveMCIAllowed := MCIAllowed;

  {Remote: clear + redraw input line}
  IF (OkANSI) AND (ComPortSpeed > 0) THEN
  BEGIN
    TC_SendAnsiStr(#27+'['+IntToStr(TC_INPUT_ROW)+';1H'+#27+'[2K');
    TC_SendAnsiStr(#27+'[0m'+#27+'[37;44m'); {white on blue for input bar}
    TC_SendAnsiStr('> ' + TeleConfInputLine);
    {Position cursor after prompt + current input (keep '>' intact)}
    TC_SendAnsiStr(#27+'['+IntToStr(TC_INPUT_ROW)+';'+IntToStr(3+Length(TeleConfInputLine))+'H');
  END;

  {Local: clear + redraw input line - Exo}
  BEGIN
    {Draw a blue input bar locally (match remote)}
    TC_LocalFullWindow;
    GotoXY(1, TC_INPUT_ROW);
    TextAttr := (1 * 16) + 15; {blue background, white text}
    ClrEol;
    Write('> ');
  GotoXY(3, TC_INPUT_ROW);
  Write(TeleConfInputLine);
    {Position cursor after prompt + current input}
    GotoXY(3 + Length(TeleConfInputLine), TC_INPUT_ROW);
    TextAttr := (1 * 16) + 15; {keep white on blue while typing}
  END;

  {Restore}
  SetC(SaveColor);
  MCIAllowed := SaveMCIAllowed;
END;



PROCEDURE TC_PrintChatLine(CONST S: STRING);
VAR
  PlainLine: STRING;
  NamePart: STRING;
  MsgPart: STRING;
  j, k: Integer;
  SaveMCIAllowed: Boolean;
  SaveColor: Byte;
  RemoteLine: STRING;
  LocalLine: STRING;
BEGIN
  SaveColor := CurrentColor;
  SaveMCIAllowed := MCIAllowed;

  {Local uses Renegade color engine (|xx etc), remote needs stripped ANSI-safe text}
  LocalLine  := TC_NormalizeChatLine(S);
  RemoteLine := TC_NormalizeChatLine(TC_PipeToAnsi(S));

  {Force [Name]: colors to match local: cyan brackets, light cyan name}
  PlainLine := TC_NormalizeChatLine(S);
  IF (Length(PlainLine) > 0) AND (PlainLine[1] = '[') THEN
  BEGIN
    j := Pos(']', PlainLine);
    k := Pos(']:', PlainLine);
    IF (j > 2) AND (k > j) THEN
    BEGIN
      NamePart := Copy(PlainLine, 2, j-2);
      MsgPart := Copy(PlainLine, k+2, Length(PlainLine)-(k+1));
      {trim leading space}
      IF (Length(MsgPart) > 0) AND (MsgPart[1] = ' ') THEN
        Delete(MsgPart, 1, 1);

      RemoteLine := #27+'[0;36;40m'+'[' +
                    #27+'[1;36;40m'+NamePart +
                    #27+'[0;36;40m'+']:'+' ' +
                    #27+'[0;37;40m' + TC_PipeToAnsi(MsgPart);
    END;
  END;


    {Remote safety: remove any embedded CR/LF that would cause double-spacing}
  WHILE Pos(#13, RemoteLine) > 0 DO Delete(RemoteLine, Pos(#13, RemoteLine), 1);
  WHILE Pos(#10, RemoteLine) > 0 DO Delete(RemoteLine, Pos(#10, RemoteLine), 1);

  IF (OkANSI) AND (ComPortSpeed > 0) THEN
  BEGIN
    TC_RemoteAddLine(RemoteLine);
    TC_RemoteRedraw;
    TC_RedrawInput;
  END
  ELSE
  BEGIN
    {Local console: scroll within the chat window using CRT windowing}
    Window(1, TC_CHAT_TOP_DEFAULT, 80, TC_CHAT_BOTTOM);
    GotoXY(1, TC_CHAT_BOTTOM - TC_CHAT_TOP_DEFAULT + 1);
    {Scroll up by one line}
    WriteLn;
    GotoXY(1, TC_CHAT_BOTTOM - TC_CHAT_TOP_DEFAULT + 1);
    TextAttr := 7;
    ClrEol;
    {Print line with Renegade colors}
    Window(1, 1, 80, 25);
    MCIAllowed := FALSE;
    SetC(7);
    GotoXY(1, TC_CHAT_BOTTOM);
    ClrEol;
    Print(LocalLine);
    Window(1, 1, 80, 25);
  END;

  {Restore}
  MCIAllowed := SaveMCIAllowed;
  SetC(SaveColor);
END;


PROCEDURE TC_DrawUI;
VAR
  i: Integer;
BEGIN
  {Fixed chat region layout (keeps divider/status static)}
  TCChatTop := TC_CHAT_TOP_DEFAULT;
  IF (TCChatTop < 1) THEN TCChatTop := 1;
  IF (TCChatTop > TC_CHAT_BOTTOM) THEN TCChatTop := 1;

  {Draw divider line locally + remotely at TC_DIV_ROW}
  SetC(1);
  TC_ClearLine(TC_DIV_ROW);
  TC_GotoXY(1, TC_DIV_ROW);
  Prompt(TC_RepeatChar(Char(#196), 80));
  SetC(7);

  IF (OkANSI) AND (ComPortSpeed > 0) THEN
    TC_SetScrollRegion(TCChatTop, TC_CHAT_BOTTOM);

  TeleConfInputLine := '';

  IF (OkANSI) AND (ComPortSpeed > 0) THEN
    TC_RemoteInit;

  TC_RedrawInput;

  TC_LocalFullWindow;
END;



{------------------------------------------------------------}
{ Full-screen command mode (for /? /L /U etc)                 }
{ Prevents the teleconf scroll region + input bar from        }
{ getting scrolled into command output.                       }
{------------------------------------------------------------}
PROCEDURE TC_CommandModeStart;
BEGIN
  {Remote: full screen scroll + normal colors}
  IF (OkANSI) AND (ComPortSpeed > 0) THEN
  BEGIN
    TC_SendAnsiStr(#27+'[0m'+#27+'[37;40m');
    TC_SendAnsiStr(#27+'[1;25r');   {disable custom scroll region}
    TC_SendAnsiStr(#27+'[2J');      {clear screen}
    TC_SendAnsiStr(#27+'[H');       {home}
  END;

  {Local: full screen + normal}
  TC_LocalFullWindow;
  TextAttr := 7;
  ClrScr;

  {Clear our UI rows so they can't bleed/scroll into command output}
  TC_ClearLine(TC_DIV_ROW);
  TC_ClearLine(TC_INPUT_ROW);
  TC_ClearLine(TC_STATUS_ROW);
  GotoXY(1,1);
END;

PROCEDURE TC_CommandModeEnd;
BEGIN
  {Rebuild teleconference UI (divider + scroll region + input bar)}
  TC_DrawUI;

  {Force cursor to column 3 immediately (avoid col 1 until keypress)}
  IF (OkANSI) AND (ComPortSpeed > 0) THEN
    TC_SendAnsiStr(#27+'['+IntToStr(TC_INPUT_ROW)+';3H');

  TC_LocalFullWindow;
  GotoXY(3, TC_INPUT_ROW);
END;


PROCEDURE pick_node(VAR NodeNum: Byte; IsChat: BOOLEAN);
BEGIN
  ListNodes;
  InputByte('Which node',NodeNum,[NumbersOnly],1,MaxNodes,Changed);
  IF (NodeNum >= 1) AND (NodeNum <= MaxNodes) AND (NodeNum <> ThisNode) THEN
  BEGIN
    LoadNode(NodeNum);
    IF (NOT (NActive IN NodeR.Status) OR (NOT (NAvail IN NodeR.Status) AND IsChat)) AND NOT
       ((NInvisible IN NodeR.Status) AND NOT CoSysOp) THEN
    BEGIN
      NL;
      Print('That node is unavailable.');
      NodeNum := 0;
    END;
    IF (NodeR.User = 0) OR NOT (NAvail IN NodeR.Status) OR ((NInvisible IN NodeR.Status) AND NOT CoSysOp) THEN
      NodeNum := 0;
  END
  ELSE
    NodeNum := 0;
END;

PROCEDURE DumpNode;
VAR
  NodeNum: Byte;
BEGIN
  pick_node(NodeNum,FALSE);
  IF (NodeNum > 0) THEN
    IF PYNQ('Hang up user on node '+IntToStr(NodeNum)+'? ',0,FALSE) THEN
    BEGIN
      LoadNode(NodeNum);
      Include(NodeR.Status,NHangup);
      IF PYNQ('Recycle node '+IntToStr(NodeNum)+' after logoff? ',0,FALSE) THEN
        Include(NodeR.Status,NRecycle);
      SaveNode(NodeNum);
    END;
END;

PROCEDURE PageNode;
VAR
  NodeNum: Byte;
BEGIN
  NL;
  IF (NOT General.MultiNode) THEN
  BEGIN
    Print('This BBS is currently not operating in Multi-Node.');
    Exit;
  END;
  pick_node(NodeNum,TRUE);
  IF (NodeNum > 0) AND (NodeNum <> ThisNode) THEN
    MessageNode(IntToStr(NodeNum)+';^8'+Caps(ThisUser.Name)+' on node '+IntToStr(ThisNode)+' has paged you for chat.'^M^J);
END;

PROCEDURE CheckStatus;
VAR
  f: FILE;
  s: STRING;
  j: BYTE;
BEGIN
  LoadNode(ThisNode);
  WITH NodeR DO
  BEGIN
    IF (NUpdate IN Status) THEN
    BEGIN
      j := ThisUser.Waiting;
      Reset(UserFile);
      Seek(UserFile,UserNum);
      Read(UserFile,ThisUser);
      Close(UserFile);
      LastError := IOResult;
      update_screen;
      IF (ThisUser.Waiting > j) THEN
      BEGIN
        NL;
        Print('^8You have new private mail waiting.');
        NL;
      END;
      Exclude(Status,NUpdate);
      SaveNode(ThisNode);
      IF (SMW IN ThisUser.ACFlags) THEN
      BEGIN
        ReadShortMessage;
        NL;
      END;
    END;
    IF (NHangup IN Status) OR (NRecycle IN Status) THEN
    BEGIN
      HangUp := TRUE;
      IF (NRecycle IN Status) THEN
        QuitAfterDone := TRUE;
    END;
    IF (NOT MultiNodeChat) AND (MaxChatRec > NodeChatLastRec) THEN
    BEGIN
      Assign(f,General.TempPath+'MSG'+IntToStr(ThisNode)+'.TMP');
      Reset(f,1);
      Seek(f,NodeChatLastRec);
      WHILE NOT EOF(f) DO
      BEGIN
        BlockRead(f,s[0],1);
        BlockRead(f,s[1],Ord(s[0]));
        Print(s);
      END;
      Close(f);
      LastError := IOResult;
      NodeChatLastRec := MaxChatRec;
      PauseScr(FALSE);
    END;
  END;
END;

PROCEDURE LowLevelSend(s: STRING; Node: Byte);
VAR
  F: FILE;
BEGIN
  IF (Node < 0) THEN
    Exit;
  Assign(f,General.TempPath+'MSG'+IntToStr(Node)+'.TMP');
  Reset(f,1);
  IF (IOResult = 2) THEN
    ReWrite(f,1);
  Seek(f,FileSize(f));
  BlockWrite(f,s[0],(Length(s) + 1));
  Close(f);
  LastError := IOResult;
END;

PROCEDURE TeleConfCheck;
VAR
  f: FILE;
  s: STRING;
  Counter: Byte;
  SaveMCIAlllowed: Boolean;
  { Only check if we're bored and not slicing }
BEGIN
  IF (MaxChatRec > NodeChatLastRec) AND (NOT HangUp) THEN
  BEGIN
    {If a message arrives while the user is typing, redraw the prompt + current line}
    IF (TeleConfActive) THEN
    BEGIN
      OutKey(#13);
      FOR Counter := 1 TO 80 DO
        OutKey(' ');
      OutKey(#13);
    END
    ELSE
    BEGIN
      FOR Counter := 1 TO (LennMCI(MLC) + 5) DO
           IF (NOT TeleConfActive) THEN BackSpace;
    END;
Assign(f,General.TempPath+'MSG'+IntToStr(ThisNode)+'.TMP');
    Reset(f,1);
    Seek(f,NodeChatLastRec);
    WHILE NOT EOF(f) DO
    BEGIN
      BlockRead(f,s[0],1);
      BlockRead(f,s[1],Ord(s[0]));
      MultiNodeChat := FALSE;  {Avoid recursive calls during pause!}
      SaveMCIAlllowed := MCIAllowed;
      MCIAllowed := FALSE;
      IF (TeleConfActive) THEN
        TC_PrintChatLine(s)
      ELSE
        Print(s);
      MCIAllowed := SaveMCIAlllowed;
      MultiNodeChat := TRUE;
    END;
    Close(f);
    LastError := IOResult;
    NodeChatLastRec := MaxChatRec;
    TC_SetDefaultAttr;
    IF (TeleConfActive) THEN
      TC_RedrawInput
    ELSE
      Prompt(MLC);
  END;
END;
PROCEDURE TeleConference;
type
  WhyNot = (NotModerator,NotOnline,NotRoom,NotInRoom,NotValid);
VAR
  RoomFile: FILE OF RoomRec;
  ActionsFile: TEXT;
  Room: RoomRec;
  User: UserRecordType;
  s: STRING;
  s2,
  s3,
  execs: ASTR;
  SaveName: STRING[36];
  Cmd: CHAR;
  i,
  j,
  SaveTimeOut,
  SaveTimeOutBell: INTEGER;
  Done,
  ChannelOnly,
  CmdMode: BOOLEAN;
  RestoreHeaderPending: BOOLEAN;

  FUNCTION ActionMCI(s: ASTR): STRING;
  VAR
    Temp: ASTR;
    Index: INTEGER;
  BEGIN
    Temp := '';
    FOR Index := 1 TO Length(s) DO
      IF (s[Index] = '%') THEN
        CASE (UpCase(s[Index + 1])) OF
        'S' : BEGIN
                Temp := Temp + Caps(ThisUser.Name);
                Inc(Index);
              END;
        'R' : BEGIN
                Temp := Temp + Caps(SaveName);
                Inc(Index);
              END;
        'G' : BEGIN
                Temp := Temp + AOnOff((ThisUser.sex = 'M'),'his','her');
                Inc(Index);
              END;
        'H' : BEGIN
                Temp := Temp + AOnOff((ThisUser.sex = 'M'),'him','her');
                Inc(Index);
              END;
        END
        ELSE
          Temp := Temp + s[Index];
    ActionMCI := Temp;
  END;

  PROCEDURE LoadRoom(VAR Chan: INTEGER);
  BEGIN
    Reset(RoomFile);
    Seek(RoomFile,(Chan - 1));
    Read(RoomFile,Room);
    Close(RoomFile);
    LastError := IOResult;
  END;

  PROCEDURE SaveRoom(VAR Chan: INTEGER);
  BEGIN
    Reset(RoomFile);
    Seek(RoomFile,(Chan - 1));
    Write(RoomFile,Room);
    Close(RoomFile);
    LastError := IOResult;
  END;

  PROCEDURE SendMessage(s: STRING; showhere: BOOLEAN);
  VAR
    i: WORD;
    Trap: TEXT;
  BEGIN
    IF (General.TrapTeleConf) THEN
    BEGIN
      Assign(Trap,General.LogsPath+'ROOM'+IntToStr(RoomNumber)+'.TRP');
      Append(Trap);
      IF (IOResult = 2) THEN
        ReWrite(Trap);
      WriteLn(Trap,StripColor(s));
      Close(Trap);
    END;
    s := TC_NormalizeChatLine(s);
    WITH NodeR DO
      FOR i := 1 TO MaxNodes DO
      BEGIN
        LoadNode(i);
        IF (i <> ThisNode) AND (NOT ((ThisNode MOD 8) IN NodeR.Forget[ThisNode DIV 8])) THEN
        BEGIN
          IF (ChannelOnly) THEN
          BEGIN
            IF (ChatChannel > 0) AND (NodeR.Channel = ChatChannel) THEN
              LowLevelSend(s,i);
          END
          ELSE
          BEGIN
            IF (NodeR.GroupChat) AND (NodeR.Room = RoomNumber) THEN
              LowLevelSend(s,i);
          END;
        END;
      END;
    IF (ShowHere) THEN
    BEGIN
      IF (TeleConfActive) THEN
        TC_PrintChatLine(s)
      ELSE
      BEGIN
        IF (MultiNodeChat) AND NOT AACS(General.TeleConfMCI) THEN
          MCIAllowed := FALSE;
        Print(s);
        MCIAllowed := TRUE;
      END;
    END;
  END;

  PROCEDURE AddToRoom(VAR Chan: INTEGER);
  VAR
    People: WORD;
    i: WORD;
  BEGIN
    IF (NOT IsInvisible) AND NOT ((Chan MOD 8) IN NodeR.Booted[Chan DIV 8]) THEN
      SendMessage('^1[^9'+Caps(ThisUser.Name)+' ^1has entered the room. ]',FALSE);
    NL;
    Print('^0You are now in conference room ^1'+IntToStr(Chan));
    LoadRoom(Chan);
    IF (NOT Room.Occupied) THEN
    BEGIN
      Room.Occupied := TRUE;
      SaveRoom(Chan);
    END;
    People := 0;
    FOR i := 1 TO MaxNodes DO
    BEGIN
      IF (i = ThisNode) THEN
        Continue;
      LoadNode(i);
      IF (NodeR.Room = Chan) AND (NodeR.GroupChat) THEN
        Inc(People);
    END;
    WITH Room DO
    BEGIN
      IF (Chan = 1) THEN
        Topic := 'Main';
      IF (Topic <> '') THEN
        Print('^0The Current Topic is: ^1'+Topic);
      IF (People = 0) THEN
        Print('^0You are the only one present.')
      ELSE
        Print('^0There '+AOnOff(People = 1,'is','are')+' '+IntToStr(People)+
               ' other '+AOnOff(People = 1,'person','people')+' present.');
    END;
    LoadNode(ThisNode);
    NodeR.Room := Chan;
    SaveNode(ThisNode);
  END;

  PROCEDURE RemoveFromRoom(VAR Chan: INTEGER);
  VAR
    People: WORD;
    i: WORD;
  BEGIN
    IF (NOT IsInvisible) AND NOT ((Chan MOD 8) IN NodeR.Booted[Chan DIV 8]) THEN
      SendMessage('^1[^9 '+Caps(ThisUser.Name)+'^1 has left the room. ]', FALSE);
    LoadRoom(Chan);
    WITH Room DO
      IF (Moderator = UserNum) THEN
        Moderator := 0;
    People := 0;
    FOR i := 1 TO MaxNodes DO
    BEGIN
      IF (i = ThisNode) THEN
        Continue;
      LoadNode(i);
      IF (NodeR.Room = Chan) AND (NodeR.GroupChat) THEN
        Inc(People);
    END;
    IF (People = 1) THEN
      Room.Occupied := FALSE;
    IF (NOT IsInvisible) THEN
      SaveRoom(Chan);
  END;

  FUNCTION Name2Number(VAR s,sname: ASTR): INTEGER;
  VAR
    i: INTEGER;
    Temp: STRING;
  BEGIN
    Name2Number := 0;
    IF (Pos(' ',s) > 0) THEN
      Sname := Copy(s,1,Pos(' ',s))
    ELSE
      Sname := s;
    i := StrToInt(SQOutSp(Sname));
    IF (SQOutSp(Sname) = IntToStr(i)) AND ((i > 0) AND (i <= MaxNodes)) THEN
    BEGIN
      LoadNode(i);
      WITH NodeR DO
        IF (User > 0) THEN
        BEGIN
          IF ((NOT (NInvisible IN Status)) OR (CoSysOp)) THEN
            Name2Number := i
          ELSE
            Name2Number := 0;
          s := Copy(s,(Length(Sname) + 1),255);
          Sname := Caps(UserName);
          Exit;
        END;
    END;
    i := 1;
    Sname := '';
    IF (Pos(' ',s) > 0) THEN
      Temp := AllCaps(Copy(s,1,(Pos(' ',s) - 1)))
    ELSE
      Temp := AllCaps(s);
    WHILE (i <= MaxNodes) DO
    BEGIN
      LoadNode(i);
      WITH NodeR DO
        IF (User > 0) THEN
        BEGIN
          IF ((UserName = AllCaps(Copy(s,1,Length(UserName)))) OR (Pos(Temp,UserName) > 0)) THEN
          BEGIN
            Name2Number := i;
            IF (UserName = AllCaps(Copy(s,1,Length(UserName)))) THEN
              s := Copy(s,(Length(UserName) + 2), 255)
            ELSE
              s := Copy(s,(Length(temp) + 2), 255);
            sname := Caps(UserName);
            Break;
          END;
        END;
        Inc(i);
    END;
  END;

  PROCEDURE Nope(Reason: WhyNot);
  BEGIN
    NL;
    CASE Reason OF
      NotModerator : Print('|10You are not the moderator.');
      NotOnline    : Print('|10That user is not logged on.');
      NotRoom      : Print('|10Invalid room number.');
      NotInRoom    : Print('|10That user is not in this room.');
      NotValid     : Print('|10Invalid option - Enter "/?" for help');
    END;
    NL;
  END;

    PROCEDURE ShowRoom(Chan: INTEGER);
  VAR
    People: WORD;
    i, j: WORD;
  BEGIN
    LoadRoom(Chan);

    {Count users in this channel (including yourself). If nobody is here, show nothing.}
    People := 0;
    FOR i := 1 TO MaxNodes DO
    BEGIN
      LoadNode(i);
      IF (NodeR.Room = Chan) AND (NodeR.GroupChat) THEN
        IF (CoSysOp) OR (NOT (NInvisible IN NodeR.Status)) THEN
          Inc(People);
    END;

    IF (People = 0) THEN
      Exit;

    NL;
    PrintACR('^0Users in channel #'+IntToStr(Chan)+':');
    PrintACR('^3'+PadRightStr('Username',30)+' '+PadRightStr('Node',7)+'Moderator');
    PrintACR('^3'+TC_RepeatChar('-',50));
    IF (Room.Moderator >= 0) THEN
    BEGIN
      LoadURec(User, Room.Moderator);
      PrintACR('^1'+PadRightStr(TC_CapsThis(User.Name), 30)+'      '+PadRightStr('',7)+'YES');
    END;
    FOR j := 1 TO MaxNodes DO
    BEGIN
      LoadNode(j);
      IF (NodeR.Room = Chan) AND (NodeR.GroupChat) THEN
        IF (CoSysOp) OR (NOT (NInvisible IN NodeR.Status)) THEN
        BEGIN
          LoadURec(User, NodeR.User);
          PrintACR('^1'+PadRightStr(TC_CapsThis(User.Name),30)+' '+PadRightStr(IntToStr(j),7));
        END;
    END;
    NL;
  END;


  PROCEDURE InputMain(VAR s: STRING);
  VAR
    os,
    cs: STRING;
    cp: INTEGER;
    c: CHAR;
    ml,
    origcolor: BYTE;
    cb: WORD;
    LastCheck: LONGINT;

    PROCEDURE DoBackSpace;
    VAR
      i,j,c: BYTE;
      WasColor: BOOLEAN;

      PROCEDURE set_color;
      BEGIN
        c := origcolor;
        i := 1;
        WHILE (i < cp) DO
        BEGIN
          IF (s[i]='^') THEN
          BEGIN
            c := Scheme.Color[Ord(s[i+1]) + Ord('1')];
            Inc(i);
          END;
          IF (s[i]='|') AND (i + 1 < Length(s)) AND (s[i + 1] IN ['0'..'9']) AND (s[i + 2] IN ['0'..'9']) THEN
          BEGIN
            cs := s[i + 1] + s[i + 2];
            CASE cb OF
              0..15  : c := (c - (c MOD 16) + cb);
              16..23 : c:= ((cb - 16) * 16) + (c MOD 16);
            END;
          END;
          Inc(i);
        END;
        SetC(c);
      END;

    BEGIN
      WasColor := FALSE;
      IF (cp > 1) THEN
      BEGIN
        Dec(cp);
        IF (cp > 1) THEN
        BEGIN
          IF (s[cp] IN ['0'..'9']) THEN
          BEGIN
            IF (s[cp-1] = '^') THEN
            BEGIN
              Dec(cp);
              WasColor := TRUE;
              set_color;
            END
            ELSE
            BEGIN
              j := 0;
              WHILE (s[cp-j] <> '|') AND (s[cp - j] IN ['0'..'9']) AND (j < cp) DO
              BEGIN
                Inc(j);
              END;
              IF (s[cp - j] = '|') THEN
              BEGIN
                 WasColor := TRUE;
                 Dec(cp,j);
                 set_color;
              END;
            END;
          END;
        END;
        IF (NOT WasColor) THEN
        BEGIN
           IF (NOT TeleConfActive) THEN BackSpace;
          IF (trapping) THEN
            Write(TrapFile,^H' '^H);
        END;
      END;
    END;

  BEGIN
    origcolor := CurrentColor;
    os := s;
    s:='';
    TeleConfInputLine := '';
    ml := (253 - Length(MCI(lRGLngStr(191,TRUE))));
    checkhangup;
    IF (HangUp) THEN
      Exit;
    cp := 1;
    LastCheck := 0;
    repeat
      mlc := s;
      MultiNodeChat := TRUE;
      IF (cp > 1) AND MultiNodeChat AND NOT ThisUser.TeleConfInt THEN
        MultiNodeChat := FALSE;
      C := CHAR(GetKey);
      IF (Timer - LastCheck > 1) THEN
      BEGIN
        LoadNode(ThisNode);
        IF ((RoomNumber MOD 8) IN NodeR.Booted[RoomNumber DIV 8]) THEN
        BEGIN
          s := '';
          Print('^1You have been ^1EJECTED^1 from the room.'^M^J);
          IF (RoomNumber = 1) THEN
            Done := TRUE
          ELSE
          BEGIN
            RemoveFromRoom(RoomNumber);
            RoomNumber := 1;
            AddToRoom(RoomNumber);
          END;
          Exit;
        END
      END;
      CASE c OF
        ^H : DoBackSpace;
        ^P : IF (cp < ml) THEN
             BEGIN
               c := CHAR(GetKey);
               IF (c IN ['0'..'9']) THEN
               BEGIN
                 UserColor(Ord(c)-48);
                 s[cp] := '^';
                 s[cp + 1] := c;
                 Inc(cp,2);
               END;
             END;
         #32..#123,#125..#255 :
             IF (cp <= ml) THEN
             BEGIN
               s[cp] := c;
               Inc(cp);
               IF (NOT TeleConfActive) THEN outkey(c);
               IF (trapping) THEN
                 Write(TrapFile,c);
             END;
        '|' : IF (cp + 1 <= ml) THEN
              BEGIN
                cs := '';
                c := '0';
                cb := 0;
                WHILE (c IN ['0'..'9']) AND (cb < 2) DO
                BEGIN
                  c := CHAR(GetKey);
                  IF (c IN ['0'..'9']) THEN
                    cs := cs + c;
                  Inc(cb);
                END;
                cb := StrToInt(cs);
                CASE cb OF
                   0..15 : SetC(CurrentColor - (CurrentColor MOD 16) + cb);
                  16..23 : SetC(((cb - 16) * 16) + (CurrentColor MOD 16));
                END;
                IF NOT (c IN ['0'..'9']) THEN
                BEGIN
                  IF (NOT TeleConfActive) THEN outkey(c);
                  IF (trapping) THEN
                    Write(TrapFile,c);
                  cs := cs + c;  {here was buf}
                END;
                s := s + '|' + cs;
                Inc(cp,Length(cs)+1);
              END
              ELSE IF (cp <= ml) THEN
              BEGIN
                s[cp] := c;
                Inc(cp);
                IF (NOT TeleConfActive) THEN outkey(c);
                IF (trapping) THEN
                  Write(TrapFile,c);
              END;
        ^X : BEGIN
               WHILE (cp <> 1) DO
                 DoBackSpace;
                 SetC(origcolor);
               END;
      END;
      s[0] := Chr(cp - 1);
      TeleConfInputLine := s;
      IF (TeleConfActive) THEN TC_RedrawInput;
    until ((c = ^M) OR (c = ^N) OR (HangUp));
    mlc := '';
  END;

BEGIN
  NL;
  IF (NOT General.MultiNode) THEN
  BEGIN
    Print('This BBS is currently not operating in Multi-Node.');
    Exit;
  END;

  Assign(ActionsFile,General.MiscPath+'ACTIONS.LST');
  Reset(ActionsFile);
  IF (IOResult = 2) THEN
    ReWrite(ActionsFile);
  Close(ActionsFile);

  Assign(RoomFile,General.DataPath+'ROOM.DAT');
  Reset(RoomFile);
  IF (IOResult = 2) THEN
    ReWrite(RoomFile);
  FillChar(Room,SizeOf(Room),0);
  Seek(RoomFile,FileSize(RoomFile));
  WHILE (FileSize(RoomFile) < 255) DO
    Write(RoomFile,Room);
  Close(RoomFile);

  IF (IOResult <> 0) THEN
    Exit;

  SaveTimeOut := General.TimeOut;
  General.TimeOut := -1;
  SaveTimeOutBell := General.TimeOutBell;
  General.TimeOutBell := -1;

  Kill(General.TempPath+'MSG'+IntToStr(ThisNode)+'.TMP');

  ChannelOnly := FALSE;

  IF (General.MultiNode) THEN
  BEGIN
    LoadNode(ThisNode);
    NodeR.GroupChat := TRUE;
    SaveNode(ThisNode);
  END;

  mlc := '';
  RoomNumber := 1;
  NodeChatLastRec := 0;

  TeleConfActive := TRUE;
  TeleConfInputLine := '';
  RestoreHeaderPending := FALSE;
  TCChatTop := 1;
  TC_InitUI;

  SysOpLog('Entered Teleconferencing');
  PrintF('TELECONF');
  IF (NoFile) THEN
    Print('^1  Welcome to Teleconferencing.  Type ^1/?^1 for help or ^1/Q^1 to quit.');
  AddToRoom(RoomNumber);
  NL;

  {Set chat scroll area to start below the header we just printed}
  TCChatTop := TC_CHAT_TOP_DEFAULT;
  IF (TCChatTop < 1) THEN TCChatTop := 1;
  IF (TCChatTop > TC_CHAT_BOTTOM) THEN TCChatTop := 1;

  TC_DrawUI;

  Done := FALSE;
  WHILE (NOT Done) AND (NOT HangUp) DO
  BEGIN
    TLeft;
    MultiNodeChat := TRUE;
    LoadNode(ThisNode);
    UserColor(7);
    {Ensure SysOp output stays inside chat region}
    TC_LocalChatWindowOn;
    GotoXY(1, TC_LocalBottomY);
    checkstatus;
    TC_LocalFullWindow;
    {Status line updates may reset the ANSI scroll region; restore it}
    TC_ApplyScrollRegion;
    TC_RedrawInput;
    TC_GotoXY(3,TC_INPUT_ROW);
    InputMain(s);
    {If we just ran a /command, restore the TELECONF header once the user presses Enter or sends a chat line}
    IF (RestoreHeaderPending) THEN
    BEGIN
      {After /? /L /U etc, restore the normal TELECONF screen on next Enter or next real chat line}
      IF (s = '') OR ((s <> '') AND (s[1] <> '/')) THEN
      BEGIN
        {Reset colors BEFORE clearing so we don't fill the whole screen blue}
        IF (OkANSI) AND (ComPortSpeed > 0) THEN
          TC_SendAnsiStr(#27+'[0m'+#27+'[37;40m'+#27+'[2J'+#27+'[H')
        ELSE
        BEGIN
          TC_LocalFullWindow;
          TextAttr := 7;
          ClrScr;
        END;

        {Re-print TELECONF header + room info exactly like first entry}
        SysOpLog('Returned to Teleconferencing');
        PrintF('TELECONF');
        IF (NoFile) THEN
          Print('^1  Welcome to Teleconferencing.  Type ^1/?^1 for help or ^1/Q^1 to quit.');
        AddToRoom(RoomNumber);
        NL;

        {Rebuild scroll region + divider + input bar}
        TCChatTop := TC_CHAT_TOP_DEFAULT;
        IF (TCChatTop < 1) THEN TCChatTop := 1;
        IF (TCChatTop > TC_CHAT_BOTTOM) THEN TCChatTop := 1;
        TC_DrawUI;

        TeleConfInputLine := '';
        TC_RedrawInput;
        RestoreHeaderPending := FALSE;
      END;
    END;
    ChannelOnly := FALSE;
    MultiNodeChat := FALSE;
    IF (HangUp) THEN
      s := '/Q';
    IF (s = '`') THEN
      IF (ChatChannel > 0) THEN
      BEGIN
        j := 1;
        Print('^1The following people are in global channel '+IntToStr(ChatChannel)+': '^M^J);
        WHILE (J <= MaxNodes) AND (NOT Abort) DO
        BEGIN
          LoadNode(j);
          WITH NodeR DO
            IF (GroupChat) AND (Channel = ChatChannel) AND (j <> ThisNode) THEN
            BEGIN
              PrintACR('^9'+Caps(UserName)+' on node '+IntToStr(j));
              ChannelOnly := TRUE;
            END;
            Inc(j);
        END;
        IF (NOT ChannelOnly) THEN
          Print('^9None.')
        ELSE
          ChannelOnly := FALSE;
        NL;
        s := '';
      END
      ELSE
      BEGIN
        Print('^1You are not in a global channel.'^M^J);
        s := '';
      END;
    IF (NOT Done) AND (s <> '') AND (s[1] = '/') THEN
    BEGIN
      CmdMode := TRUE;
      TC_CommandModeStart;
      Cmd := UpCase(s[2]);
      s3 := AllCaps(Copy(s,2,255));
      IF (Pos(' ',s3) > 0) THEN
      BEGIN
        SaveName := Copy(s3,(Pos(' ',s3) + 1),255);
        s3 := Copy(s3,1,(Pos(' ',s3) - 1));
      END
      ELSE
        SaveName := '';
      s2 := SaveName;
      IF (SaveName <> '') THEN
      BEGIN
        i := Name2Number(s2,SaveName);
        IF (SaveName = '') THEN
          i := -1;
      END
      ELSE
        i := 0;
      Reset(ActionsFile);
      WHILE NOT EOF(ActionsFile) DO
      BEGIN
        ReadLn(ActionsFile,s2);            { Action WORD }
        IF (AllCaps(s2) = s3) THEN
        BEGIN
          ReadLn(ActionsFile,s2);        { What sender sees }
          s2 := MCI(s2);
          IF (Copy(AllCaps(s2),1,5) <> ':EXEC') THEN
          BEGIN
            Print('^1'+ActionMCI(s2));
            execs := '';
          END
          ELSE
            execs := Copy(s2,6,255);    { strip ":EXEC" }
          ReadLn(ActionsFile,s2);        { What everybody ELSE sees }
          IF (i = 0) THEN
            ReadLn(ActionsFile,s2);      { What evrybdy sees IF no rcvr }
          s2 := MCI(s2);
          s2 := '^1' + ActionMCI(s2);
          WITH NodeR DO
            FOR j := 1 TO MaxNodes DO
            BEGIN
              LoadNode(j);
              IF (GroupChat) AND (Room = RoomNumber) AND
                 (j <> ThisNode) AND NOT ((ThisNode MOD 8) IN Forget[ThisNode DIV 8]) AND
                 (j <> i) THEN
                LowLevelSend(s2,j);
            END;
          IF (i > 0) THEN
            ReadLn(ActionsFile,s2);
          ReadLn(ActionsFile,s2);        { What receiver sees }
          s2 := MCI(s2);
          IF (i > 0) THEN
          BEGIN
            LoadNode(i);
            IF (NodeR.GroupChat) AND (NodeR.Room = RoomNumber) AND
               NOT ((ThisNode MOD 8) IN NodeR.Forget[ThisNode DIV 8]) THEN
              LowLevelSend('^1'+ActionMCI(s2), i);
          END;
          s := '';
          IF (execs <> '') THEN
          BEGIN
            Cmd := execs[1];
            execs := Copy(execs,2,255);
            dodoorfunc(Cmd,execs);
          END;
          Break;
        END
        ELSE FOR j := 1 TO 4 DO
          ReadLn(ActionsFile,s2);
      END;
      Close(ActionsFile);

      IF (s <> '') THEN
        CASE Cmd OF
          {'/' : IF (Copy(s,2,3) = '/\\') AND (SysOp) THEN
                  DoMenuCommand(Done,AllCaps(Copy(S,5,2)),AllCaps(Copy(s,7,255)),s2,'Activating SysOp Cmd');}

          'A' : IF (AllCaps(Copy(s,2,4)) <> 'ANON') THEN
                BEGIN
                  s := Copy(s,4,(Length(s) - 3));
                  s := '^1'+Caps(ThisUser.Name)+' '+s;
                END
                ELSE
                BEGIN
                  IF (Room.Moderator = UserNum) OR (CoSysOp) THEN
                  BEGIN
                    LoadRoom(RoomNumber);
                    Room.Anonymous := NOT Room.Anonymous;
                    SaveRoom(RoomNumber);
                    SendMessage('^1[ This room is now in ^1'+AOnOff(Room.Anonymous,'Anonymous','Regular')+'^1 ]',TRUE);
                  END
                  ELSE
                    Nope(NotModerator);
                END;

          'E' : BEGIN
                  IF (AllCaps(Copy(s,2,4)) = 'ECHO') THEN
                  BEGIN
                    ThisUser.TeleConfEcho := NOT ThisUser.TeleConfEcho;
                    Print('^9Your message echo is now '+ShowOnOff(ThisUser.TeleConfEcho));
                  END
                  ELSE IF (AllCaps(Copy(s,2,5)) = 'EJECT') THEN
                  BEGIN
                    IF (Room.Moderator = UserNum) OR (CoSysOp) THEN
                    BEGIN
                      s := Copy(s,(Pos(' ',s) + 1),Length(s));
                      i := Name2Number(s,SaveName);
                      IF (i > 0) AND (i <= MaxNodes) THEN
                      BEGIN
                        LoadNode(i);
                        IF (NodeR.GroupChat) AND (NodeR.Room = RoomNumber) THEN
                        BEGIN
                          LoadURec(User,NodeR.User);
                          IF (aacs1(User, NodeR.User, General.CSOp)) THEN
                            Print('^9You cannot eject that person.'^M^J)
                          ELSE
                          BEGIN
                            NodeR.Booted[RoomNumber DIV 8] := NodeR.Booted[RoomNumber DIV 8] + [RoomNumber MOD 8];
                            NodeR.Room := 1;
                            SaveNode(i);
                            IF (NOT IsInvisible) THEN
                              SendMessage('^1'+SaveName+'^9 has just been ejected from the room by ^1'+
                                          Caps(ThisUser.Name),TRUE);
                            SysOpLog('Ejected '+SaveName);
                          END;
                        END
                        ELSE
                          Nope(NotInRoom);
                      END
                      ELSE
                        Nope(NotOnline);
                      s := '';
                    END
                    ELSE
                      Nope(NotModerator);
                  END;
                END;

          'F' : IF (S[3] <> ' ') OR (Copy(S,4,(Length(s) - 3)) = '') THEN
                  Nope(NotValid)
                ELSE
                BEGIN
                  s := Copy(s,4,(Length(s) - 3));
                  i := Name2Number(s,SaveName);
                  IF (i > 0) AND (i <= MaxNodes) THEN
                  BEGIN
                    LoadURec(User,NodeR.User);
                    IF (aacs1(User,NodeR.User,General.CSOp)) THEN
                      Print('^9You cannot forget a sysop.'^M^J)
                    ELSE
                    BEGIN
                      LoadNode(ThisNode);
                      NodeR.Forget[i DIV 8] := NodeR.Forget[i DIV 8] + [i MOD 8];
                      SaveNode(ThisNode);
                      Print('^1'+SaveName+'^9 has been forgotten.');
                    END;
                  END
                  ELSE
                    Nope(NotOnLine);
                  s := '';
                END;

          'G' : IF (AllCaps(Copy(s,2,6)) = 'GLOBAL') THEN
                BEGIN
                  LoadNode(ThisNode);
                  NodeR.Channel := StrToInt(Copy(s,(Pos(' ',s) + 1),255));
                  Print(^M^J'^1You are now in global channel '+IntToStr(NodeR.Channel)+'.'^M^J);
                  ChatChannel := NodeR.Channel;
                  SaveNode(ThisNode);
                  ChannelOnly := TRUE;
                  IF (NOT IsInvisible) THEN
                    SendMessage('^9'+Caps(ThisUser.Name)+' has joined global channel '+IntToStr(chatchannel)+'.', FALSE);
                END
                ELSE IF (AllCaps(s) = '/G') THEN
                BEGIN
                  IF PYNQ('Are you sure you want to disconnect? ',39,FALSE) THEN
                  BEGIN
                    IF (NOT IsInvisible) THEN
                      SendMessage('^1[ ^1'+Caps(ThisUser.Name)+'^1 has disconnected on node '+IntToStr(ThisNode)+' ]',FALSE);
                    HangUp := TRUE;
                  END;
                END;

          'I' : IF (AllCaps(Copy(s,2,9)) = 'INTERRUPT') THEN
                BEGIN
                  ThisUser.TeleConfInt := NOT ThisUser.TeleConfInt;
                  Print('^9Your message interruption is now '+ShowOnOff(ThisUser.TeleConfInt));
                END
                ELSE
                BEGIN
                  IF (Room.Moderator = UserNum) OR (CoSysOp) THEN
                  BEGIN
                    IF (Length(s) = 2) THEN
                    BEGIN
                      LoadRoom(RoomNumber);
                      Room.Private := NOT Room.Private;
                      SaveRoom(RoomNumber);
                      SendMessage('^1[ This room is now ^1'+AOnOff(Room.Private,'private','public') + '^1 ]', TRUE);
                    END
                    ELSE
                    BEGIN
                      s := Copy(s,4,(Length(s) - 3));
                      i := Name2Number(s,SaveName);
                      IF (i > 0) AND (i <= MaxNodes) THEN
                      BEGIN
                        LoadNode(i);
                        s := ^M^J+'^9[^1 ' + Caps(ThisUser.Name) + '^9 is inviting you to join conference room '
                             +IntToStr(RoomNumber)+' ]';
                            NodeR.Invited[RoomNumber DIV 8] := NodeR.Invited[RoomNumber DIV 8] + [RoomNumber MOD 8];
                            NodeR.Booted[RoomNumber DIV 8] := NodeR.Booted[RoomNumber DIV 8] - [RoomNumber MOD 8];
                        Print('^1'+SaveName+'^9 on node '+IntToStr(i)+' has been invited.');
                        SaveNode(i);
                        IF (i <> ThisNode) THEN
                          LowLevelSend(s,i);
                      END
                      ELSE
                        Nope(NotOnline);
                      s := '';
                    END;
                  END
                  ELSE
                    Nope(NotModerator);
                END;

          'J' : IF (S[3] <> ' ') OR (Copy(S,4,(Length(s) - 3)) = '') THEN
                  Nope(NotValid)
                ELSE
                BEGIN
                  s := Copy(s,4,3);
                  i := StrToInt(s);
                  IF (i >= 1) AND (i <= 255) THEN
                  BEGIN
                    LoadNode(ThisNode);
                    IF ((i MOD 8) IN NodeR.Booted[i DIV 8]) THEN
                    BEGIN
                      NL;
                      Print('^1You were ^1EJECTED^1 from that room.');
                      NL;
                    END
                    ELSE
                    BEGIN
                      LoadRoom(i);
                      IF (Room.Private) AND NOT (CoSysOp) AND NOT ((i MOD 8) IN NodeR.Invited[i DIV 8]) THEN
                      BEGIN
                        NL;
                        Print('^9You must be invited to private conference rooms.');
                        NL;
                        LoadRoom(RoomNumber);
                      END
                      ELSE
                      BEGIN
                        RemoveFromRoom(RoomNumber);
                        RoomNumber := i;
                        AddToRoom(RoomNumber);
                        SysOpLog('Joined room '+IntToStr(RoomNumber)+' '+Room.Topic);
                      END;
                    END;
                  END
                  ELSE
                    Nope(NotRoom);
                  s := '';
                END;

          'L' : IF (Copy(S,3,(Length(S) - 2)) <> '') THEN
                  Nope(NotValid)
                ELSE
				BEGIN
                  PrintF('ACTIONS');
				  Print('%PAf%CL|00');
				  RestoreHeaderPending := TRUE;
				END;

          'M' : IF (S[3] <> ' ') OR (Copy(S,4,(Length(s) - 3)) = '') THEN
                  Nope(NotValid)
                ELSE
                BEGIN
                  NL;
                  IF (CoSysOp) OR (Room.Moderator = UserNum) OR ((Room.Moderator = 0) AND (RoomNumber <> 1)) THEN
                  BEGIN
                    s := Copy(S,4,40);
                    LoadRoom(RoomNumber);
                    Room.Topic := s;
                    IF (NOT IsInvisible) THEN
                      SendMessage('^1[ Conference "^1'+Room.Topic+'^1" is now moderated by ^1'+
                                  Caps(ThisUser.Name)+'^1 ]',TRUE);
                    IF (Room.Moderator = 0) THEN
                    BEGIN
                      FOR i := 1 TO MaxNodes DO
                      BEGIN
                        LoadNode(i);
                        NodeR.Invited[RoomNumber DIV 8] := NodeR.Invited[RoomNumber DIV 8] - [RoomNumber MOD 8];
                        NodeR.Booted[RoomNumber DIV 8] := NodeR.Booted[RoomNumber DIV 8] - [RoomNumber MOD 8];
                        SaveNode(i);
                      END;
                    END;
                    Room.Moderator := UserNum;
                    SaveRoom(RoomNumber);
                  END
                  ELSE
                    Nope(NotModerator);
                  s := '';
                END;

          'P' : IF (S[3] <> ' ') OR (Copy(s,4,(Length(s) - 3)) = '') THEN
                  Nope(NotValid)
                ELSE
                BEGIN
                  s := Copy(s,4,(Length(s) - 3));
                  i := Name2Number(s,SaveName);
                  IF (i > 0) AND (i <= MaxNodes) THEN
                  BEGIN
				  Print('%CL|00');
                    LoadNode(i);
                    IF ((ThisNode MOD 8) IN NodeR.Forget[ThisNode DIV 8]) THEN
                      Print('^9That user has forgotten you.'^M^J)
                    ELSE IF NOT (NAvail IN NodeR.Status) THEN
                      Print('^9That user is unavailable.'^M^J)
                    ELSE IF NOT (NInvisible IN NodeR.Status) THEN
                    BEGIN
                      Print('^9Private message sent to ^1'+SaveName);
                      IF AACS(General.TeleConfMCI) THEN
                        s := MCI(s);
                      s := MCI(lRGLngStr(194,TRUE)) + s;
                      LowLevelSend(s,i)
                    END
                    ELSE
                      Nope(NotOnline);
                  END
                  ELSE
                    Nope(NotOnline);
                  s := '';
                END;

          'Q' : BEGIN
                  s := Copy(s,4,40);
                  IF (s <> '') THEN
                    s := '^1'+Caps(ThisUser.Name)+' '+s;
                  LoadNode(ThisNode);
                  SaveNode(ThisNode);
                  Done := TRUE;
                END;

          'R' : IF (AllCaps(Copy(s,2,8)) = 'REMEMBER') THEN
                BEGIN
                  s := Copy(s,(Pos(' ',s) + 1), 255);
                  i := Name2Number(s,SaveName);
                  IF (i > 0) AND (i <= MaxNodes) THEN
                  BEGIN
                    LoadNode(ThisNode);
                    NodeR.Forget[i DIV 8] := NodeR.Forget[i DIV 8] - [i MOD 8];
                    SaveNode(ThisNode);
                    Print('^1'+SaveName+'^9 has been remembered.');
                  END
                  ELSE
                    Nope(NotOnLine);
                END
                ELSE
                BEGIN
                  s:= Copy(s,(Pos(' ',s) + 1),255);
                  i := SearchUser(s,FALSE);
                  readasw(i,'registry');
                  s := '';
                END;

          'S' : IF (Copy(S,3,(Length(s) - 2)) <> '') THEN
                  Nope(NotValid)
                ELSE
                BEGIN
                  Print('%CL|00');
                  Abort := FALSE;
                  i := 1;
                  WHILE (i <= 255) AND (NOT Abort) DO
                  BEGIN
                    ShowRoom(i);
                    Inc(i);
                  END;
                  PauseScr(FALSE);
                  Print('%CL|00');
                  LoadRoom(RoomNumber);
                  s := '';
                END;

          'U' : IF (Copy(S,3,(Length(s) - 2)) <> '') THEN
                  Nope(NotValid)
                ELSE
                BEGIN
                  Print('%CL|00');
				  ShowRoom(RoomNumber);
                  s := '';
                END;

          'W' : IF (Copy(S,3,(Length(s) - 2)) <> '') THEN
                  Nope(NotValid)
                ELSE
		BEGIN
                  ListNodes;
		  Print('%CL|00');
		  RestoreHeaderPending := TRUE;
                END;

          '?' : IF (Copy(S,3,(Length(s) - 2)) <> '') THEN
                  Nope(NotValid)
                ELSE
                BEGIN
					Print('%CL|00');
					PrintF('TELEHELP');
					PauseScr(FALSE);
					Print('%CL|00');
				END;
        END;
      {Return to teleconference UI}
      CmdMode := FALSE;
      RestoreHeaderPending := TRUE;
      TC_DrawUI;
      TC_LocalFullWindow;
      GotoXY(3, TC_INPUT_ROW);
IF (s[1] = '/') THEN
      s := '';
  END
  ELSE
    IF (s <> '') THEN
      BEGIN
        LoadRoom(RoomNumber);
        IF (s[1] <> '`') THEN
          IF (Room.Anonymous) THEN
            s := MCI(lRGLngStr(192,TRUE)) + s
          ELSE
            s := MCI(lRGLngStr(191,TRUE)) + s
        ELSE
          BEGIN
            s := MCI(lRGLngStr(193,TRUE)) + Copy(s,2,255);
            ChannelOnly := TRUE;
          END;
      END
    ELSE
      s := '';
    IF (s <> '') THEN
    BEGIN
      MultiNodeChat := TRUE;
      IF (AACS(General.TeleConfMCI)) THEN
        s := MCI(s);
      {Force color reset at end of each line to prevent bleed}
      s := s + '^0' + #27 + '[0m' + #27 + '[37;40m';
      SendMessage(s,FALSE);
      TeleConfInputLine := '';
      IF (TeleConfActive) THEN
        TC_PrintChatLine(s)
      ELSE
        Print(s);
END;
  END;
  MultiNodeChat := FALSE;


  {Restore full-screen scrolling region / UI}
  TC_RestoreUI;
  TeleConfActive := FALSE;
  TeleConfInputLine := '';
  IF (General.MultiNode) THEN
  BEGIN
    LoadNode(ThisNode);
    NodeR.GroupChat := FALSE;
    SaveNode(ThisNode);
  END;

  RemoveFromRoom(RoomNumber);

  NodeChatLastRec := 0;
  Kill(General.TempPath+'MSG'+IntToStr(ThisNode)+'.TMP');
  General.TimeOut := SaveTimeOut;
  General.TimeOutBell := SaveTimeOutBell;
END;

PROCEDURE ToggleChatAvailability;
BEGIN
  NL;
  IF (NOT General.MultiNode) THEN
  BEGIN
    Print('This BBS is currently not operating in Multi-Node.');
    Exit;
  END;
  LoadNode(ThisNode);
  IF (NAvail IN NodeR.Status) THEN
  BEGIN
    Exclude(NodeR.Status,NAvail);
{    Print('You are not available for chat.');}
  END
  ELSE
  BEGIN
    Include(NodeR.Status,NAvail);
{    Print('You are now available for chat.');}
  END;
  SaveNode(ThisNode);
END;

PROCEDURE MessageNode(CONST b: ASTR);
VAR
  s: STRING;
  NodeNum: Byte;
  Forced: BOOLEAN;
BEGIN
  NL;
  IF (NOT General.MultiNode) THEN
  BEGIN
    Print('This BBS is currently not operating in Multi-Node.');
    Exit;
  END;
  s := b;
  NodeNum := StrToInt(s);
  IF (b <> '') AND (IsInvisible) THEN
    Exit;
  Forced := (s <> '');
  IF (NodeNum = 0) AND (Copy(s,1,1) <> '0') THEN
  BEGIN
    pick_node(NodeNum,TRUE);
    Forced := FALSE;
    IF (NodeNum = 0) THEN
      Exit;
  END;
  IF (NodeNum = ThisNode) THEN
    Exit;
  IF (Forced OR AACS(General.TeleConfMCI)) THEN
    s := MCI(s);
  IF (NodeNum > 0) THEN
  BEGIN
    LoadNode(NodeNum);
    IF (NodeR.User = 0) THEN
      Exit;
  END;
  IF (s <> '') THEN
    s := '^0'+Copy(s,(Pos(';',s) + 1),255)
  ELSE
  BEGIN
    Prt('Message: ');
    InputMain(s,(SizeOf(s) - 1),[NoInputField]);
  END;
  IF (Forced OR AACS(General.TeleConfMCI)) THEN
    s := MCI(s);
  IF (s <> '') THEN
  BEGIN
    IF (NOT Forced) THEN
    BEGIN
      LoadNode(NodeNum);
      IF (NOT ((ThisNode MOD 8) IN NodeR.Forget[ThisNode DIV 8])) THEN
        LowLevelSend(^M^J'^1Message from '+Caps(ThisUser.Name)+' on node '+IntToStr(ThisNode)+':^0'^M^J,NodeNum)
      ELSE
        Print(^M^J'That node has forgotten you.');
    END;
    IF (NodeNum = 0) THEN
      FOR NodeNum := 1 TO MaxNodes DO
        IF (NodeNum <> ThisNode) THEN
        BEGIN
          LoadNode(NodeNum);
          IF (NodeR.User > 0) THEN
            LowLevelSend(s,NodeNum)
        END
        ELSE      (* Match up ELSE Statements ??? *)
        ELSE
         LowLevelSend(s,NodeNum);
  END;
END;

FUNCTION NodeListMCI(CONST s: ASTR; Data1,Data2: Pointer): STRING;
VAR
  NodeRecPtr: ^NodeRecordType;
  NodeNum: ^Byte;
BEGIN
  NodeRecPtr := Data1;
  NodeNum := Data2;
  NodeListMCI := s;
  IF (NOT (NActive IN NodeRecPtr^.Status)) OR
     (NodeRecPtr^.User > (MaxUsers - 1)) OR
     (NodeRecPtr^.User < 1) OR
     ((NInvisible IN NodeRecPtr^.Status) AND
     (NOT CoSysOp)) THEN
  BEGIN
    NodeListMCI := '-';
    WITH NodeRecPtr^ DO
      CASE s[1] OF
        'N' : IF (s[2] = 'N') THEN
                NodeListMCI := IntToStr(NodeNum^);
        'A' : CASE s[2] OF
                'C' : NodelistMCI := lRGLngStr(143,TRUE);
                'V' : NodeListMCI := AOnOff((NAvail IN Status),'Y','N');
              END;
        'U' : IF (s[2] = 'N') THEN
                NodeListMCI := lRGLngStr(144,TRUE);
      END;
  END
  ELSE
    WITH NodeRecPtr^ DO
      CASE s[1] OF
        'A' : CASE s[2] OF
                'C' : NodeListMCI := ActivityDesc;
                'G' : NodeListMCI := IntToStr(Age);
                'T' : NodeListMCI := AOnOff((NActive IN Status),'Y','N');
                'V' : NodeListMCI := AOnOff((NAvail IN Status),'Y','N');
              END;
        'L' : IF (s[2] = 'C') THEN
                NodeListMCI := CityState;
        'N' : IF (s[2] = 'N') THEN
                NodeListMCI := IntToStr(NodeNum^);
        'U' : IF (s[2] = 'N') THEN
                NodeListMCI := Caps(UserName);
        'R' : IF (s[2] = 'M') THEN
                NodeListMCI := IntToStr(Room);
        'S' : IF (s[2] = 'X') THEN
                NodeListMCI := Sex;
        'T' : IF (s[2] = 'O') THEN
                NodeListMCI := IntToStr((GetPackDateTime - LogonTime) DIV 60);
      END;
END;

PROCEDURE ListNodes;
VAR
  NodeNum: Byte;
BEGIN
  IF (NOT General.MultiNode) THEN
  BEGIN
    NL;
    Print('This BBS is currently not operating in Multi-Node.');
    Exit;
  END;
  Abort := FALSE;
  Next := FALSE;
  AllowContinue := TRUE;
  IF (NOT ReadBuffer('NODELM')) THEN
    Exit;
  PrintF('NODELH');
  NodeNum := 1;
  WHILE (NodeNum <= MaxNodes) AND (NOT Abort) AND (NOT HangUp) DO
  BEGIN
    LoadNode(NodeNum);
    DisplayBuffer(NodeListMCI,@NodeR,@NodeNum);
    Inc(NodeNum);
  END;
  IF (NOT Abort) THEN
    PrintF('NODELT');
  AllowContinue := FALSE;
END;

END.
