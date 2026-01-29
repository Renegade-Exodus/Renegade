{$A+,B-,D-,E-,F+,I-,L-,N-,O+,R-,S-,V-}

UNIT SysOp4; { Text editor, scrolling viewer}

INTERFACE

USES
  Common;

PROCEDURE TView(VAR FSpec: AStr); { Scrolling text file viewer }
PROCEDURE TEdit1;
PROCEDURE TEdit(CONST FSpec: AStr);

IMPLEMENTATION

USES
  DOS,
  ANSIPAGE;

{--- Remote-safe screen controls (no CRT) ---}
PROCEDURE GotoXY(X, Y: Integer);
VAR sx, sy: String;
BEGIN
  Str(X, sx);
  Str(Y, sy);
  Prt(#27+'['+sy+';'+sx+'H');
END;

PROCEDURE ClrScr;
BEGIN
  Prt(#27+'[2J'+#27+'[H');
END;

PROCEDURE ClrEol;
BEGIN
  Prt(#27+'[K');
END;


VAR
  ParseAnsiAfterEsc : Word;



  ArcItemCount: Integer;

{--- Local helpers for remote-safe screen control (no CRT required) ---}
VAR
  CurFG: Byte;
  CurBG: Byte;

FUNCTION IntToStrL(I: LongInt): AStr;
VAR S: String;
BEGIN
  Str(I, S);
  IntToStrL := S;
END;

FUNCTION PadRightStr(CONST S: AStr; N: Integer): AStr;
VAR T: AStr;
BEGIN
  T := S;
  WHILE Length(T) < N DO T := T + ' ';
  IF Length(T) > N THEN T := Copy(T,1,N);
  PadRightStr := T;
END;

FUNCTION AnsiColor(FG, BG: Byte): AStr;
{ Convert 0..15 FG, 0..7 BG to ANSI SGR string }
VAR
  F, B: Byte;
BEGIN
  F := FG AND 15;
  B := BG AND 7;
  IF F > 7 THEN
    AnsiColor := #27+'[1;'+IntToStrL(30 + (F-8))+';'+IntToStrL(40 + B)+'m'
  ELSE
    AnsiColor := #27+'[0;'+IntToStrL(30 + F)+';'+IntToStrL(40 + B)+'m';
END;

PROCEDURE TextColor(C: Byte);
BEGIN
  CurFG := C AND 15;
  Prt(AnsiColor(CurFG, CurBG));
END;

PROCEDURE TextBackground(C: Byte);
BEGIN
  CurBG := C AND 7;
  Prt(AnsiColor(CurFG, CurBG));
END;

PROCEDURE GotoRC(R, C: Integer);
BEGIN
  Prt(#27+'['+IntToStrL(R)+';'+IntToStrL(C)+'H');
END;

{--- TP7 helpers added to fix missing identifiers ---}
FUNCTION IntToStr(I: LongInt): AStr;
VAR S: String;
BEGIN
  Str(I, S);
  IntToStr := S;
END;

FUNCTION ZeroPad(CONST SIn: AStr): AStr;
VAR S: AStr;
BEGIN
  S := SIn;
  WHILE Length(S) < 2 DO
    S := '0' + S;
  ZeroPad := S;
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
  IsAnsiFile: Boolean;



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


    PROCEDURE ClearWin;
  VAR
    R: Integer;
  BEGIN
    { Always clear using normal (dark gray) attribute to prevent color bleed }
        FOR R := WinTop TO WinTop+WinH-1 DO
    BEGIN
      GotoRC(R,1);
      { clear line }
      Prt(AnsiColor(8,0));
      Prt(PadRightStr('',WinW));
    END;


      END;

  PROCEDURE DrawFrame;
  BEGIN
    CLS;
    Print('|15Archive File View: |11'+Title);
    Print('|09Up/Down PgUp/PgDn  Home/End  S=Mode  ESC=Back');
    Print('|08'+ '-------------------------------------------------------------------------------');
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
  END;  FUNCTION UpperStr(S: AStr): AStr;
  VAR J: Integer;
  BEGIN
    FOR J := 1 TO Length(S) DO
      S[J] := UpCase(S[J]);
    UpperStr := S;
  END;



  PROCEDURE RenderAnsiSGR(CONST S: AStr);
  VAR
    I, J, Col: Integer;
    Num: Integer;
    CodeStr: AStr;
    Bright: Boolean;

    PROCEDURE ApplySGR(Code: Integer);
    BEGIN
      CASE Code OF
        0: BEGIN TextColor(7); TextBackground(0); Bright := FALSE; END;
        1: BEGIN Bright := TRUE; END;
        22: Bright := FALSE;

        30..37: BEGIN TextColor((Code-30) + (Ord(Bright)*8)); END;
        40..47: BEGIN TextBackground(Code-40); END;
      END;
    END;

    FUNCTION ReadNum(CONST SS: AStr; VAR P: Integer): Integer;
    VAR V: Integer;
    BEGIN
      V := 0;
      WHILE (P <= Length(SS)) AND (SS[P] >= '0') AND (SS[P] <= '9') DO
      BEGIN
        V := (V*10) + Ord(SS[P]) - Ord('0');
        Inc(P);
      END;
      ReadNum := V;
    END;

  BEGIN
    Bright := FALSE;
    Col := 0;
    I := 1;
    WHILE (I <= Length(S)) AND (Col < WinW) DO
    BEGIN
      IF (S[I] = #27) AND (I < Length(S)) AND (S[I+1] = '[') THEN
      BEGIN
        I := I + 2;
        WHILE I <= Length(S) DO
        BEGIN
          IF (S[I] = 'm') THEN
          BEGIN
            Inc(I);
            Break;
          END;
          IF (S[I] = ';') THEN
          BEGIN
            Inc(I);
          END
          ELSE IF (S[I] >= '0') AND (S[I] <= '9') THEN
          BEGIN
            J := I;
            Num := ReadNum(S, J);
            ApplySGR(Num);
            I := J;
          END
          ELSE
          BEGIN
            Inc(I);
          END;
        END;
      END
      ELSE
      BEGIN
        { printable char }
        Write(S[I]);
        Inc(Col);
        Inc(I);
      END;
    END;
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
            BEGIN
        { clear line }
        TextColor(8); TextBackground(0);
        FOR Col := 1 TO WinW DO Write(' ');
      END;

IF ReadLineAt(S,L) THEN
      BEGIN
        S := SanitizeTextLine(S);
        GotoRC(WinTop+R,1);
        IF IsAnsiFile THEN
          RenderAnsiSGR(S)
        ELSE
          Prt(ClipVisible(S,WinW));
END;
    END;

    { status }
        GotoRC(WinTop+WinH,1);
    BEGIN
        { clear line }
        TextColor(8); TextBackground(0);
        FOR Col := 1 TO WinW DO Write(' ');
      END;

Plain := 'Line '+IntToStr(CurLine)+'/'+IntToStr(LineCnt);
    Col := 80 - Length(Plain) + 1;
    IF Col < 1 THEN Col := 1;
    GotoRC(WinTop+WinH,Col);
    Prt('|08Line |15'+IntToStr(CurLine)+'|08/|15'+IntToStr(LineCnt));
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

  { detect ANSI by extension }
  IsAnsiFile := (Pos('.ANS',UpperStr(FN)) = Length(UpperStr(FN))-3) OR (Pos('.ASC',UpperStr(FN)) = Length(UpperStr(FN))-3);

  TopLine := 1;
  CurLine := 1;
  FollowMode := FALSE;
  Done := FALSE;

  DrawFrame;
  DrawPage;

  REPEAT
    Key := InKey;
    CASE Key OF
        71,72,73,75,77,79,80,81: Key := Key * 256; { Home,Up,PgUp,Left,Right,End,Down,PgDn }
      ELSE
        { leave as-is }
      END;

    { jump-scroll only (no follow/smooth mode) }
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
BEGIN
  { Stubbed: extraction pipeline depends on other units (General/ExecBatch/MCI).
    For SYSOP4 viewer stability we simply view the archive file itself. }
  ViewFileScroll(ArcFN, InnerName);
END;


PROCEDURE BrowseArchiveUI(CONST ArcFN: AStr; ArcType: Byte);
BEGIN
  { Archive browsing UI stubbed out in SYSOP4 transplant.
    SYSOP4 viewer supports .ANS/.TXT passthrough via ViewFileScroll. }
  ViewFileScroll(ArcFN, ArcFN);
END;



PROCEDURE ViewAnsiPage(CONST FN, Title: AStr);
CONST
  WinTop = 4;
  WinH   = 21;
  WinW   = 80;
  { page history limit }
  MaxPages = 512;
TYPE
  TPageArr = ARRAY[1..MaxPages] OF LongInt;

VAR
  F: FILE;
  Buf: ARRAY[1..2048] OF Byte;
  BufLen, BufPos: Word;
  CurAbs: LongInt;      { absolute file offset of current byte }
  Row, Col: Integer;    { 1-based inside content window }
  SaveRow, SaveCol: Integer;
  FG, BG: Integer;
  CurAttr: Byte;
  TextAttr: Byte;

  Pages: TPageArr;
  PageCount: Integer;
  CurPage: Integer;
  NextOff: LongInt;
  Done: Boolean;

  FUNCTION MinI(A,B: Integer): Integer;
  BEGIN
    IF A < B THEN MinI := A ELSE MinI := B;
  END;

  FUNCTION ClampI(V,Lo,Hi: Integer): Integer;
  BEGIN
    IF V < Lo THEN V := Lo;
    IF V > Hi THEN V := Hi;
    ClampI := V;
  END;

  PROCEDURE ResetState;
  BEGIN
    Row := 1;
    Col := 1;
    SaveRow := 1;
    SaveCol := 1;
    FG := 7;
    BG := 0;
    CurAttr := Byte(FG + (BG SHL 4));
    TextAttr := CurAttr;
  END;

  PROCEDURE ClearContent;
  VAR R: Integer;
  BEGIN
    TextAttr := 7;
    FOR R := WinTop TO WinTop+WinH-1 DO
    BEGIN
      GotoXY(1,R);
      ClrEol;
    END;
    TextAttr := CurAttr;
    GotoXY(1,WinTop);
  END;

  PROCEDURE DrawHeader;
  BEGIN
    TextAttr := 7;
    GotoXY(1,1); ClrEol;
    Write('Archive File View: ');
    TextAttr := 11;
    Write(Title);
    TextAttr := 7;
    GotoXY(1,2); ClrEol;
    TextAttr := 9;
    Write('Up/Down  Home/End  ESC=Back');
    TextAttr := 7;
    GotoXY(1,3); ClrEol;
    Write('----------------------------------------------------------------------------');
    TextAttr := CurAttr;
  END;

  PROCEDURE DrawFooter;
  BEGIN
    TextAttr := 7;
    GotoXY(70,25);
    Write('Page ',CurPage:1,'/',PageCount:1);
    TextAttr := CurAttr;
  END;

  PROCEDURE SeekAbs(P: LongInt);
  BEGIN
    Seek(F, P);
    BufLen := 0;
    BufPos := 0;
  END;

  FUNCTION GetByte(VAR B: Byte; VAR Ok: Boolean): Boolean;
  BEGIN
    IF BufPos >= BufLen THEN
    BEGIN
      BlockRead(F, Buf, SizeOf(Buf), BufLen);
      BufPos := 0;
      IF BufLen = 0 THEN
      BEGIN
        Ok := False;
        GetByte := False;
        Exit;
      END;
    END;
    Inc(BufPos);
    B := Buf[BufPos];
    Ok := True;
    GetByte := True;
  END;

  PROCEDURE PutCh(Ch: Char);
  BEGIN
    IF (Ch = #13) THEN Exit;
    IF (Ch = #10) THEN
    BEGIN
      Inc(Row);
      Col := 1;
      Exit;
    END;

    { enforce within content area }
    Row := ClampI(Row, 1, WinH);
    Col := ClampI(Col, 1, WinW);

    GotoXY(Col, WinTop + Row - 1);
    Write(Ch);

    Inc(Col);
    IF Col > WinW THEN
    BEGIN
      Col := 1;
      Inc(Row);
    END;
  END;

  PROCEDURE ApplySGR(Parm: Integer);
  BEGIN
    CASE Parm OF
      0: BEGIN FG := 7; BG := 0; END;
      1: IF FG < 8 THEN Inc(FG,8);
      30..37: FG := Parm-30;
      40..47: BG := Parm-40;
    END;
    CurAttr := Byte((BG SHL 4) + (FG AND 15));
    TextAttr := CurAttr;
  END;

  PROCEDURE ParseCSI;
  VAR
    Ok: Boolean;
    B: Byte;
    S: String[32];
    I, V, N: Integer;
    C: Char;
    Parm: ARRAY[1..8] OF Integer;
    ParmCnt: Integer;

    PROCEDURE PushParm(Val: Integer);
    BEGIN
      IF ParmCnt < 8 THEN
      BEGIN
        Inc(ParmCnt);
        Parm[ParmCnt] := Val;
      END;
    END;

  BEGIN
    S := '';
    ParmCnt := 0;

    { read until a final letter, collecting digits/; }
    REPEAT
      CurAbs := FilePos(F) - LongInt(BufLen) + LongInt(BufPos);
      IF NOT GetByte(B, Ok) THEN Exit;
      C := Char(B);
      IF (C >= '0') AND (C <= '9') OR (C = ';') THEN
      BEGIN
        IF Length(S) < 32 THEN S := S + C;
      END
      ELSE
        Break;
    UNTIL False;

    { parse parms }
    IF S = '' THEN
      PushParm(0)
    ELSE
    BEGIN
      V := 0; N := 0;
      FOR I := 1 TO Length(S) DO
      BEGIN
        IF S[I] = ';' THEN
        BEGIN
          PushParm(V);
          V := 0; N := 0;
        END
        ELSE
        BEGIN
          V := V*10 + Ord(S[I]) - Ord('0');
          Inc(N);
        END;
      END;
      PushParm(V);
    END;

    CASE C OF
      'm': BEGIN
             FOR I := 1 TO ParmCnt DO
               ApplySGR(Parm[I]);
           END;
      'H','f': BEGIN
                 { cursor position 1-based }
                 IF ParmCnt < 2 THEN
                 BEGIN
                   Row := 1; Col := 1;
                 END
                 ELSE
                 BEGIN
                   Row := ClampI(Parm[1],1,WinH);
                   Col := ClampI(Parm[2],1,WinW);
                 END;
               END;
      'A': BEGIN IF ParmCnt=0 THEN V:=1 ELSE V:=Parm[1];
                 Dec(Row, V); IF Row < 1 THEN Row := 1;
           END;
      'B': BEGIN IF ParmCnt=0 THEN V:=1 ELSE V:=Parm[1];
                 Inc(Row, V); IF Row > WinH THEN Row := WinH;
           END;
      'C': BEGIN IF ParmCnt=0 THEN V:=1 ELSE V:=Parm[1];
                 Inc(Col, V); IF Col > WinW THEN Col := WinW;
           END;
      'D': BEGIN IF ParmCnt=0 THEN V:=1 ELSE V:=Parm[1];
                 Dec(Col, V); IF Col < 1 THEN Col := 1;
           END;
      'J': BEGIN
             { treat clear-screen as clear-content only }
             ClearContent;
             Row := 1; Col := 1;
           END;
      'K': BEGIN
             { erase to end of line }
             GotoXY(Col, WinTop + Row - 1);
             ClrEol;
           END;
      's': BEGIN SaveRow := Row; SaveCol := Col; END;
      'u': BEGIN Row := SaveRow; Col := SaveCol; END;
    END;
  END;

  PROCEDURE RenderFrom(Off: LongInt; VAR StopOff: LongInt);
  VAR
    Ok: Boolean;
    B: Byte;
    Ch: Char;
    Esc: Boolean;
  BEGIN
    StopOff := -1;
    SeekAbs(Off);
    ResetState;
    ClearContent;

    Esc := False;
    REPEAT
      CurAbs := FilePos(F) - LongInt(BufLen) + LongInt(BufPos);

      IF NOT GetByte(B, Ok) THEN
      BEGIN
        StopOff := -1;
        Exit;
      END;

      Ch := Char(B);

      { if we are about to go past window, stop before consuming further }
      IF Row > WinH THEN
      BEGIN
        StopOff := CurAbs;
        Exit;
      END;

      IF NOT Esc THEN
      BEGIN
        IF Ch = #27 THEN
          Esc := True
        ELSE
          PutCh(Ch);
      END
      ELSE
      BEGIN
        { ESC handler }
        Esc := False;
        IF Ch = '[' THEN
          ParseCSI
        ELSE
        BEGIN
          { ignore other ESC sequences }
        END;
      END;
    UNTIL False;
  END;
BEGIN
  Assign(F, FN);
  {$I-} Reset(F,1); {$I+}
  IF IOResult <> 0 THEN Exit;

  BufLen := 0; BufPos := 0;

  { page 1 starts at 0 }
  PageCount := 1;
  Pages[1] := 0;
  CurPage := 1;

  Done := False;
  WHILE NOT Done DO
  BEGIN
    ClrScr;
    DrawHeader;
    RenderFrom(Pages[CurPage], NextOff);

    { If we discovered a next page and we're at the end of known pages, add it }
    IF (NextOff >= 0) AND (CurPage = PageCount) AND (PageCount < MaxPages) THEN
    BEGIN
      Inc(PageCount);
      Pages[PageCount] := NextOff;
    END;

    DrawFooter;

    CASE InKey OF
      27: Done := True;  { ESC }
      256+72, 256+73: IF CurPage > 1 THEN Dec(CurPage);          { Up/PgUp }
      256+80, 256+81: IF CurPage < PageCount THEN Inc(CurPage);  { Down/PgDn }
      256+71: CurPage := 1;                                      { Home }
      256+79: CurPage := PageCount;                              { End }
    END;
  END;

  Close(F);
END;



PROCEDURE TView(VAR FSpec: AStr); { View a text/ANSI file }
VAR
  Dir: DirStr;
  Name: NameStr;
  Ext: ExtStr;
  Title: AStr;
  UExt: ExtStr;
  I: Integer;
BEGIN
  FSplit(FSpec, Dir, Name, Ext);
  Title := Name + Ext;

  UExt := Ext;
  FOR I := 1 TO Length(UExt) DO
    UExt[I] := UpCase(UExt[I]);

  IF (UExt = '.ANS') OR (UExt = '.ASC') THEN
    ViewAnsiFile(FSpec, Title)
  ELSE
    ViewFileScroll(FSpec, Title);
END;

PROCEDURE TEdit1;
VAR
  FSpec: AStr;
  Dir: DirStr;
  Name: NameStr;
  Ext: ExtStr;
BEGIN
  NL;
  Prt('File name: ');
  IF (FileSysOp) THEN
    BEGIN
      InputMain(FSpec,50,[CapAll]);
    END
  ELSE
    BEGIN
      InputMain(FSpec,12,[CapAll]);
      FSplit(FSpec,Dir,Name,Ext);
      FSpec := Name+Ext;
    END;
  TEdit(FSpec);
END;

PROCEDURE TEdit(CONST FSpec: AStr);
TYPE
  StrPtr = ^StrRec;

  StrRec = RECORD
    S: AStr;
    Next,
    Last: StrPtr;
  END;

VAR
  TopHeap: ^Byte;
  Fil: Text;
  Cur,
  Nex,
  Las,
  Top,
  Bottom,
  Used: StrPtr;
  S: AStr;
  TotalLines,
  CurLine,
  I: Integer;
  Done,
  AllRead: Boolean;

  PROCEDURE InLi(VAR S1: AStr);
  VAR
    C,
    C1: Char;
    Cp,
    Rp,
    CV,
    CC: Integer;

    PROCEDURE BKSpc;
    BEGIN
      IF (Cp > 1) THEN
      BEGIN
        IF (S1[Cp - 2] = '^') AND (S1[Cp - 1] IN ['0'..'9']) THEN
        BEGIN
          UserColor(0);
          Dec(Cp);
        END
        ELSE IF (S1[Cp - 1] = #8) THEN
        BEGIN
          Prompt(' ');
          Inc(Rp);
        END
        ELSE IF (S1[Cp - 1] <> #10) THEN
        BEGIN
          Prompt(#8+' '+#8);
          Dec(Rp);
        END;
        Dec(Cp);
      END;
    END;

  BEGIN
    Rp := 1;
    Cp := 1;
    S1 := '';
    IF (LastLineStr <> '') THEN
    BEGIN
      Prompt(LastLineStr);
      S1 := LastLineStr;
      LastLineStr := '';
      Cp := (Length(S1) + 1);
      Rp := Cp;
    END;
    REPEAT
      C := Char(GetKey);
      CASE C of
        #32..#255 :
              IF (Cp < StrLen) AND (Rp < ThisUser.LineLen) THEN
              BEGIN
                S1[Cp] := C;
                Inc(Cp);
                Inc(Rp);
                OutKey(C);
              END;
         ^H : BKSpc;
         ^S : BEGIN
                CV := (5 - (Cp MOD 5));
                IF ((Cp + CV) < StrLen) AND ((Rp + CV) < ThisUser.LineLen) THEN
                  FOR CC := 1 TO CV DO
                  BEGIN
                    Prompt(' ');
                    S1[Cp] := ' ';
                    Inc(Rp);
                    Inc(Cp);
                  END;
              END;
         ^P : IF (OkANSI OR OkAvatar) AND (Cp < (StrLen - 1)) THEN
              BEGIN
                C1 := Char(GetKey);
                IF (C1 IN ['0'..'9']) THEN
                BEGIN
                  S1[Cp] := '^';
                  Inc(Cp);
                  S1[Cp] := C1;
                  Inc(Cp);
                  UserColor(Ord(S1[Cp - 1]));
                END;
              END;
         ^X : BEGIN
                Cp := 1;
                FOR CV := 1 TO (Rp - 1) DO
                  Prompt(#8+' '+#8);
                UserColor(0);
                Rp := 1;
              END;
      END;
    UNTIL ((C = ^M) OR (Rp = ThisUser.LineLen) OR (HangUp));
    S1[0] := Chr(Cp - 1);
    IF (C <> ^M ) THEN
    BEGIN
      CV := (Cp - 1);
      WHILE (CV > 1) AND (S1[CV] <> ' ') AND ((S1[CV] <> ^H) OR (S1[CV - 1] = '^')) DO
        Dec(CV);
      IF (CV > (Rp DIV 2)) AND (CV <> (Cp - 1)) THEN
      BEGIN
        LastLineStr := Copy(S1,(CV + 1),(Cp - CV));
        FOR CC := (Cp - 2) DOWNTO CV DO
          Prompt(^H);
        FOR CC := (Cp - 2) DOWNTO CV DO
          Prompt(' ');
        S1[0] := Chr(CV - 1);
      END;
    END;
    NL;
  END;

  FUNCTION NewPtr(VAR x: StrPtr): Boolean;
  BEGIN
    IF (Used <> NIL) THEN
    BEGIN
      x := Used;
      Used := Used^.Next;
      NewPtr := TRUE;
    END
    ELSE
    BEGIN
      IF (MaxAvail > 2048) THEN
      BEGIN
        New(x);
        NewPtr := TRUE;
      END
      ELSE
        NewPtr := FALSE;
    END;
  END;

  PROCEDURE OldPtr(VAR x: StrPtr);
  BEGIN
    x^.Next := Used;
    Used := x;
  END;

  PROCEDURE PLine(Cl: Integer; VAR Cp: StrPtr);
  VAR
    S1: AStr;
  BEGIN
    IF (NOT Abort) THEN
    BEGIN
      IF (Cp = NIL) THEN
        S1 := '      ^1'+'[^1'+'END^1'+']'
      ELSE
        S1 := PadRightInt(Cl,4)+': '+Cp^.S;
      PrintACR(S1);
    END;
  END;

  PROCEDURE PL;
  BEGIN
    Abort := FALSE;
    PLine(CurLine,Cur);
  END;

BEGIN
  Mark(TopHeap);
  Used := NIL;
  Top := NIL;
  Bottom := NIL;
  AllRead := TRUE;
  IF (FSpec = '') THEN
  BEGIN
    Print('Aborted.');
  END
  ELSE
  BEGIN
    Abort := FALSE;
    Next := FALSE;
    TotalLines := 0;
    New(Cur);
    Cur^.Last := NIL;
    Cur^.S := '';
    NL;
    Assign(Fil,FSpec);
    Reset(Fil);
    IF (IOResult <> 0) THEN
    BEGIN
      ReWrite(Fil);
      IF (IOResult <> 0) THEN
      BEGIN
        Print('Error reading file.');
        Abort := TRUE;
      END
      ELSE
      BEGIN
        Close(Fil);
        Erase(Fil);
        Print('New file.');
        TotalLines := 0;
        Cur := NIL;
        Top := Cur;
        Bottom := Cur;
      END;
    END
    ELSE
    BEGIN
      Abort := NOT NewPtr(Nex);
      Top := Nex;
      Print('^0Loading...');
      WHILE ((NOT EOF(Fil)) AND (NOT Abort)) DO
      BEGIN
        Inc(TotalLines);
        Cur^.Next := Nex;
        Nex^.Last := Cur;
        Cur := Nex;
        ReadLn(Fil,S);
        Cur^.S := S;
        Abort := NOT NewPtr(Nex);
      END;
      Close(Fil);
      Cur^.Next :=  NIL;
      IF (TotalLines = 0) THEN
      BEGIN
        Cur := NIL;
        Top := NIL;
      END;
      Bottom := Cur;
      IF (Abort) THEN
      BEGIN
        NL;
        Print(^G^G'|12WARNING: |10Not all of file read.^1');
        NL;
        AllRead := FALSE;
      END;
      Abort := FALSE;
    END;
    IF (NOT Abort) THEN
    BEGIN
      Print('Total lines: '+IntToStr(TotalLines));
      Cur := Top;
      IF (Top <> NIL) THEN
        Top^.Last := NIL;
      CurLine := 1;
      Done := FALSE;
      PL;
      REPEAT
        Prt(':');
        InputMain(S,10,[CapAll]);
        IF (S = '') THEN
          S := '+';
        IF (StrToInt(S) > 0) THEN
        BEGIN
          I := StrToInt(S);
          IF ((I > 0) AND (I <= TotalLines)) THEN
          BEGIN
            WHILE (I <> CurLine) DO
              IF (I < CurLine) THEN
              BEGIN
                IF (Cur = NIL) THEN
                BEGIN
                  Cur := Bottom;
                  CurLine := TotalLines;
                END
                ELSE
                BEGIN
                  Dec(CurLine);
                  Cur := Cur^.Last;
                END;
              END
              ELSE
              BEGIN
                Inc(CurLine);
                Cur := Cur^.Next;
              END;
              PL;
          END;
        END
        ELSE
          CASE S[1] of
            '?' : BEGIN
                    LCmds(14,1,'+Forward line','-Back line');
                    LCmds(14,1,'Top','Bottom');
                    LCmds(14,1,'Print line','List');
                    LCmds(14,1,'Insert lines','Delete line');
                    LCmds(14,1,'Replace line','Clear all');
                    LCmds(14,1,'Quit (Abort)','Save');
                    LCmds(14,1,'*Center line','!Memory Available');
                  END;
            '!' : Print('Heap space available: '+IntToStr(MemAvail));
            '*' : IF (Cur <> NIL) THEN
                    Cur^.S := #2+Cur^.S;
            '+' : IF (Cur <> NIL) THEN
                  BEGIN
                    I := StrToInt(Copy(S,2,9));
                    IF (I = 0) THEN
                      I := 1;
                    WHILE (Cur <> NIL) AND (I > 0) DO
                    BEGIN
                      Cur := Cur^.Next;
                      Inc(CurLine);
                      Dec(I);
                    END;
                    PL;
                  END;
            '-' : BEGIN
                    I := StrToInt(Copy(S,2,9));
                    IF (I = 0) THEN
                      I := 1;
                    IF (Cur = NIL) THEN
                    BEGIN
                      Cur := Bottom;
                      CurLine := TotalLines;
                      Dec(I);
                    END;
                    IF (Cur <> NIL) THEN
                      IF (Cur^.Last <> NIL) THEN
                      BEGIN
                        WHILE ((Cur^.Last <> NIL) AND (I > 0)) DO
                        BEGIN
                          Cur := Cur^.Last;
                          Dec(CurLine);
                         Dec(I);
                        END;
                        PL;
                      END;
                  END;
            'B' : BEGIN
                    Cur := NIL;
                    CurLine := (TotalLines + 1);
                    PL;
                  END;
            'C' : IF PYNQ('Clear workspace? ',0,FALSE) THEN
                  BEGIN
                    TotalLines := 0;
                    CurLine := 1;
                    Cur := NIL;
                    Top := NIL;
                    Bottom := NIL;
                    Release(TopHeap);
                  END;
            'D' : BEGIN
                    I := StrToInt(Copy(S,2,9));
                    IF (I = 0) THEN
                      I := 1;
                    WHILE (Cur <> NIL) AND (I > 0) DO
                    BEGIN
                      Las := Cur^.Last;
                      Nex := Cur^.Next;
                      IF (Las <> NIL) THEN
                        Las^.Next := Nex;
                      IF (Nex <> NIL) THEN
                        Nex^.Last := Las;
                      OldPtr(Cur);
                      IF (Bottom = Cur) THEN
                        Bottom := Las;
                      IF (Top = Cur) THEN
                        Top := Nex;
                      Cur := Nex;
                      Dec(TotalLines);
                      Dec(I);
                    END;
                    PL;
                  END;
            'I' : BEGIN
                    Abort := FALSE;
                    Next := FALSE;
                    LastLineStr := '';
                    NL;
                    Print('   Enter "." on a separate line to exit insert mode.');
                    IF (OkANSI OR OkAvatar) THEN
                      Print('^1   ^0');
                    Dec(ThisUser.LineLen,6);
                    S := '';
                    WHILE (S <> '.') AND (S <> '.'+#1) AND (NOT Abort) AND (NOT HangUp) DO
                    BEGIN
                      Prompt(PadRightInt(CurLine,4)+': ');
                      InLi(S);
                      IF (S <> '.') AND (S <> '.'+#1) THEN
                      BEGIN
                        Abort := NOT NewPtr(Nex);
                        IF (Abort) THEN
                          Print('Out of space.')
                        ELSE
                        BEGIN
                          Nex^.S := S;
                          IF (Top = Cur) THEN
                            IF (Cur = NIL) THEN
                            BEGIN
                              Nex^.Last := NIL;
                              Nex^.Next := NIL;
                              Top := Nex;
                              Bottom := Nex;
                            END
                            ELSE
                            BEGIN
                              Nex^.Next := Cur;
                              Cur^.Last := Nex;
                              Top := Nex;
                            END
                          ELSE
                          BEGIN
                            IF (Cur = NIL) THEN
                            BEGIN
                              Bottom^.Next := Nex;
                              Nex^.Last := Bottom;
                              Nex^.Next := NIL;
                              Bottom := Nex;
                            END
                            ELSE
                            BEGIN
                              Las := Cur^.Last;
                              Nex^.Last := Las;
                               Nex^.Next := Cur;
                              Cur^.Last := Nex;
                              Las^.Next := Nex;
                            END;
                          END;
                          Inc(CurLine);
                          Inc(TotalLines);
                        END
                      END;
                    END;
                    Inc(ThisUser.LineLen,6);
                  END;
            'L' : BEGIN
                    Abort := FALSE;
                    Next := FALSE;
                    Nex := Cur;
                    I := CurLine;
                    WHILE (Nex <> NIL) AND (NOT Abort) AND (NOT HangUp) DO
                    BEGIN
                      PLine(I,Nex);
                      Nex := Nex^.Next;
                      Inc(I);
                    END;
                  END;
            'P' : PL;
            'R' : IF (Cur <> NIL) THEN
                  BEGIN
                    PL;
                    Prompt(PadRightInt(CurLine,4)+': ');
                    InLi(S);
                    Cur^.S := S;
                  END;
            'Q' : Done := TRUE;
            'S' : BEGIN
                    IF (NOT AllRead) THEN
                    BEGIN
                      UserColor(1);
                      Prompt('Not all of file read.  ');
                      AllRead := PYNQ('Save anyway? ',0,FALSE);
                    END;
                    IF (AllRead) THEN
                    BEGIN
                      Done := TRUE;
                      Print('Saving ...');
                      SysOpLog('Saved "'+FSpec+'"');
                      ReWrite(Fil);
                      I := 0;
                      Cur := Top;
                      WHILE (Cur <> NIL) DO
                      BEGIN
                        WriteLn(Fil,Cur^.S);
                        Cur := Cur^.Next;
                        Dec(I);
                      END;

                      IF (I = 0) THEN
                        WriteLn(Fil);

                      Close(Fil);
                    END;
                  END;
            'T' : BEGIN
                    Cur := Top;
                    CurLine := 1;
                    PL;
                  END;
          END;
      UNTIL ((Done) OR (HangUp));
    END;
  END;
  Release(TopHeap);
  PrintingFile := FALSE;
  LastError := IOResult;
END;

END.