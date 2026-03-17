UNIT ANSIPAGE;

INTERFACE

USES
  Common;

PROCEDURE ViewAnsiFile(CONST FName, Title: AStr);

IMPLEMENTATION

USES
  Dos;

CONST
  HeaderRows = 3;
  TopRow     = HeaderRows + 1;   { 4 }
  BottomRow  = 24;               { reserve row 25 for footer/page }
  PageRows   = BottomRow - TopRow + 1; { 21 }
  MaxPages   = 300;              { plenty for most ANSI packs }
  ScreenCols = 80;               { standard Renegade width }

  ESC = #27;

TYPE
  TOffsets = ARRAY[0..MaxPages] OF LongInt;

VAR
  Offsets    : TOffsets;
  PageCnt    : Integer;
  IsAnsiFileG : Boolean;
  TotalLines : LongInt;

  FileOK     : Boolean;
PROCEDURE OutStr(CONST S: String);
BEGIN
  { Prompt does not append CR/LF }
  Prompt(S);
END;

{ Forward decl (TP requires this because PutRight calls TermGotoRC) }
PROCEDURE TermGotoRC(R, C: Integer); FORWARD;

PROCEDURE PutRight(Row: Integer; CONST S: String);
VAR
  C: Integer;
BEGIN
  C := ScreenCols - Length(S) + 1;
  IF C < 1 THEN C := 1;
  TermGotoRC(Row, C);
  OutStr(S);
END;


PROCEDURE TermGotoRC(R, C: Integer);
VAR
  S: String;
BEGIN
  Str(R, S);
  OutStr(ESC + '[' + S + ';');
  Str(C, S);
  OutStr(S + 'H');
END;

PROCEDURE ClearBelowHeader;
VAR
  R: Integer;
BEGIN
  { Explicit per-line clear is more compatible than ESC[0J on some remote terms }
  FOR R := TopRow TO 25 DO
  BEGIN
    TermGotoRC(R, 1);
    OutStr(ESC + '[2K');
  END;
END;

PROCEDURE DrawHeader(CONST Title: AStr;
  CurPage, TotalPages: Integer;
  CurLine, TotLines: LongInt;
  ShowLineHint, LineMode: Boolean);
VAR
  S1,S2,S3,S4,Status: String;
BEGIN
  { Clean, self-contained header (visual style: simple, stable) }
  TermGotoRC(1,1); OutStr(ESC + '[0m'); { reset attrs }
  OutStr(ESC + '[2K');  { clear line }
  OutStr('|11 ' + Title);
  { right-aligned counters }
  Str(CurLine, S1);
  Str(TotLines, S2);
  Str(CurPage+1, S3);
  Str(TotalPages, S4);
  Status := 'Ln ' + S1 + '/' + S2 + '  Pg ' + S3 + '/' + S4;
  PutRight(1, '|11' + Status);

  TermGotoRC(2,1); OutStr(ESC + '[2K');
  OutStr(' |09Up|08/|09Down|08=|09Page  |09Home|08/|09End  |15ESC|08=|09Exit');
  IF ShowLineHint THEN
  BEGIN
    IF LineMode THEN
      OutStr('  |15L|08=|09Line Reader |12(ON)')
    ELSE
      OutStr('  |15L|08=|09Line Reader');
  END;
  TermGotoRC(3,1); OutStr(ESC + '[2K');
  OutStr('|01');
          
END;

PROCEDURE DrawFooter;
BEGIN
  { keep footer row clean (ANSI pages can overwrite) }
  TermGotoRC(25,1);
  OutStr(ESC + '[2K');
END;

FUNCTION IsFinalByte(Ch: Char): Boolean;
BEGIN
  { CSI final bytes are in range @..~ but we care about letters too }
  IsFinalByte := (Ch >= '@') AND (Ch <= '~');
END;

FUNCTION ParseInt(CONST S: String; VAR I: Integer): Integer;
VAR
  N, V: Integer;
BEGIN
  V := 0;
  N := 0;
  WHILE (I <= Length(S)) AND (S[I] >= '0') AND (S[I] <= '9') DO
  BEGIN
    V := (V * 10) + (Ord(S[I]) - Ord('0'));
    Inc(I);
    Inc(N);
  END;
  IF N = 0 THEN
    ParseInt := -1
  ELSE
    ParseInt := V;
END;

FUNCTION RemapCSI(CONST Seq: String): String;
{ Seq includes leading ESC '[' ... final }
VAR
  F: Char;
  Body: String;
  I: Integer;
  R, C: Integer;
  RS, CS: String;
BEGIN
  RemapCSI := Seq;

  IF (Length(Seq) < 3) THEN Exit;
  IF (Seq[1] <> ESC) OR (Seq[2] <> '[') THEN Exit;

  F := Seq[Length(Seq)];

  { Drop full clear screen }
  IF (F = 'J') AND (Length(Seq) >= 4) AND (Seq[3] = '2') THEN
  BEGIN
    RemapCSI := ''; { suppress ESC[2J }
    Exit;
  END;

  { Home cursor variants }
  IF (F = 'H') AND ((Length(Seq) = 3) OR (Seq = ESC+'[H') OR (Seq = ESC+'[;H')) THEN
  BEGIN
    RemapCSI := ESC + '[4;1H';
    Exit;
  END;

  { Cursor position: ESC[<r>;<c>H or f }
  IF (F = 'H') OR (F = 'f') THEN
  BEGIN
    Body := Copy(Seq, 3, Length(Seq)-3); { between '[' and final }
    I := 1;
    R := ParseInt(Body, I);
    IF R < 0 THEN R := 1;
    IF (I <= Length(Body)) AND (Body[I] = ';') THEN Inc(I);
    C := ParseInt(Body, I);
    IF C < 0 THEN C := 1;

    { shift down to preserve header }
    IF R <= HeaderRows THEN R := R + HeaderRows;
    IF R < TopRow THEN R := TopRow;
    IF R > 25 THEN R := 25;

    Str(R, RS);
    Str(C, CS);
    RemapCSI := ESC + '[' + RS + ';' + CS + F;
    Exit;
  END;
END;

PROCEDURE ScanPages(CONST FN: AStr);
VAR
  F: File;
  Buf: ARRAY[0..1023] OF Byte;
  Got: Word;
  Posn: LongInt;
  Lines: Integer;
  B0,B1,B2,B3: Byte;
  I: Integer;
  HasClear: Boolean;
BEGIN
  PageCnt := 0;
  Offsets[0] := 0;
  HasClear := False;

    FileOK := True;
  Assign(F, FN);
  {$I-}
  Reset(F, 1);
  {$I+}
  IF (IOResult <> 0) THEN
  BEGIN
    FileOK := False;
    Exit;
  END;
Posn := 0;
  Lines := 0;
  TotalLines := 0;

  B0 := 0; B1 := 0; B2 := 0; B3 := 0;

  REPEAT
    BlockRead(F, Buf, SizeOf(Buf), Got);
    FOR I := 0 TO Got-1 DO
    BEGIN
      { shift history }
      B0 := B1; B1 := B2; B2 := B3; B3 := Buf[I];

      { line counting fallback }
      IF B3 = 10 THEN
      BEGIN
        Inc(Lines);
        Inc(TotalLines);
        IF (Lines >= PageRows) AND (PageCnt < MaxPages) AND (NOT HasClear) THEN
        BEGIN
          Inc(PageCnt);
          Offsets[PageCnt] := Posn + I + 1;
          Lines := 0;
        END;
      END;

      { detect ESC [ 2 J => page break }
      IF (B0 = 27) AND (B1 = Ord('[')) AND (B2 = Ord('2')) AND (B3 = Ord('J')) THEN
      BEGIN
        HasClear := True;
        Lines := 0;
        IF (PageCnt < MaxPages) THEN
        BEGIN
          Inc(PageCnt);
          Offsets[PageCnt] := Posn + I + 1; { after the J }
        END;
      END;
    END;

    Inc(Posn, Got);
  UNTIL Got = 0;

  Close(F);

  { If we saw clears, ignore any line-count pages beyond the clear breaks already stored. }
  { PageCnt already reflects those breaks. }
END;

PROCEDURE RenderPage(CONST FN: AStr; CurPage: Integer);
VAR
  F: File;
  Buf: ARRAY[0..1023] OF Byte;
  Got: Word;
  StartPos, EndPos: LongInt;
  CurPos: LongInt;
  SBuf: String;
  EscSeq: String;
  InEsc: Boolean;
  Ch: Char;
  I: Integer;
  OutChunk: String;
BEGIN
    FileOK := True;
  Assign(F, FN);
  {$I-}
  Reset(F, 1);
  {$I+}
  IF (IOResult <> 0) THEN
  BEGIN
    FileOK := False;
    Exit;
  END;
StartPos := Offsets[CurPage];
  IF CurPage < PageCnt THEN
    EndPos := Offsets[CurPage+1]
  ELSE
    EndPos := High(LongInt);

  Seek(F, StartPos);

  ClearBelowHeader;
  TermGotoRC(TopRow, 1);

  
  IF NOT IsAnsiFileG THEN OutStr('|07');
InEsc := False;
  EscSeq := '';
  OutChunk := '';

  CurPos := StartPos;

  REPEAT
    BlockRead(F, Buf, SizeOf(Buf), Got);
    IF Got = 0 THEN Break;

    FOR I := 0 TO Got-1 DO
    BEGIN
      IF (EndPos <> High(LongInt)) AND (CurPos >= EndPos) THEN
      BEGIN
        Got := 0;
        Break;
      END;

      Ch := Char(Buf[I]);

      IF NOT InEsc THEN
      BEGIN
        IF Ch = ESC THEN
        BEGIN
          InEsc := True;
          EscSeq := ESC;
        END
        ELSE
        BEGIN
          OutChunk := OutChunk + Ch;
          IF Length(OutChunk) >= 200 THEN
          BEGIN
            OutStr(OutChunk);
            OutChunk := '';
          END;
        END;
      END
      ELSE
      BEGIN
        EscSeq := EscSeq + Ch;

        { Only handle CSI sequences }
        IF (Length(EscSeq) = 2) AND (Ch <> '[') THEN
        BEGIN
          { Non-CSI escape, just output as-is }
          OutChunk := OutChunk + EscSeq;
          EscSeq := '';
          InEsc := False;
        END
        ELSE IF (Length(EscSeq) >= 3) AND IsFinalByte(Ch) THEN
        BEGIN
          SBuf := RemapCSI(EscSeq);
          IF SBuf <> '' THEN
            OutChunk := OutChunk + SBuf;
          EscSeq := '';
          InEsc := False;
          IF Length(OutChunk) >= 200 THEN
          BEGIN
            OutStr(OutChunk);
            OutChunk := '';
          END;
        END
        ELSE IF Length(EscSeq) > 40 THEN
        BEGIN
          { safety: give up }
          OutChunk := OutChunk + EscSeq;
          EscSeq := '';
          InEsc := False;
        END;
      END;

      Inc(CurPos);
    END;

    IF OutChunk <> '' THEN
    BEGIN
      OutStr(OutChunk);
      OutChunk := '';
    END;

  UNTIL Got = 0;

  { flush dangling escape }
  IF InEsc AND (EscSeq <> '') THEN
    OutStr(EscSeq);

  Close(F);
END;

FUNCTION UpperStr(CONST S: AStr): AStr;
VAR
  I: Integer;
  T: AStr;
BEGIN
  T := S;
  FOR I := 1 TO Length(T) DO
    T[I] := UpCase(T[I]);
  UpperStr := T;
END;


FUNCTION IsAnsiExt(CONST FN: AStr): Boolean;
VAR
  U: AStr;
  Ext: AStr;
  I: Integer;
BEGIN
  U := UpperStr(FN);
  Ext := '';
  I := Length(U);
  WHILE (I > 0) AND (U[I] <> '.') AND (U[I] <> '\\') AND (U[I] <> '/') DO
    Dec(I);
  IF (I > 0) AND (U[I] = '.') THEN
    Ext := Copy(U, I, 4);
  IsAnsiExt := (Ext = '.ANS');
END;

FUNCTION AllowLineReader(CONST FN: AStr): Boolean;
VAR
  U: AStr;
  Ext: AStr;
  I: Integer;
BEGIN
  U := UpperStr(FN);

  { Special case }
  IF Pos('FILE_ID.DIZ', U) > 0 THEN
  BEGIN
    AllowLineReader := True;
    Exit;
  END;

  Ext := '';
  I := Length(U);
  WHILE (I > 0) AND (U[I] <> '.') AND (U[I] <> '\') AND (U[I] <> '/') DO
    Dec(I);
  IF (I > 0) AND (U[I] = '.') THEN
    Ext := Copy(U, I, 4);

  { Only offer line-reader for plain text-ish files }
  IF (Ext = '.TXT') OR (Ext = '.ASC') OR (Ext = '.NFO') OR (Ext = '.DIZ') OR
     (Ext = '.DOC') OR (Ext = '.1ST') OR (Ext = '.FAQ') OR (Ext = '.ANS') THEN
  BEGIN
    { .ANS is usually ANSI; do NOT allow line mode }
    AllowLineReader := (Ext <> '.ANS');
  END
  ELSE
    AllowLineReader := False;
END;

PROCEDURE RenderWindow(CONST FN: AStr; StartLine: LongInt);
{ Render a scrolling window of PageRows lines starting at StartLine (1-based) }
VAR
  F: File;
  Buf: ARRAY[0..1023] OF Byte;
  Got: Word;
  CurPos: LongInt;
  CurLine: LongInt;
  LinesOut: LongInt;
  SBuf: String;
  EscSeq: String;
  InEsc: Boolean;
  Ch: Char;
  I: Integer;
  OutChunk: String;
BEGIN
  FileOK := True;
  Assign(F, FN);
  {$I-}
  Reset(F, 1);
  {$I+}
  IF (IOResult <> 0) THEN
  BEGIN
    FileOK := False;
    Exit;
  END;

  { skip to StartLine }
  CurLine := 1;
  CurPos := 0;

  IF StartLine > 1 THEN
  BEGIN
    REPEAT
      BlockRead(F, Buf, SizeOf(Buf), Got);
      IF Got = 0 THEN Break;

      FOR I := 0 TO Got-1 DO
      BEGIN
        Ch := Char(Buf[I]);
        Inc(CurPos);

        IF Ch = #10 THEN
        BEGIN
          Inc(CurLine);
          { After LF, CurPos is at the start of the next line }
          IF CurLine = StartLine THEN
          BEGIN
            Seek(F, CurPos);
            Got := 0;
            Break;
          END;
        END;
      END;
    UNTIL Got = 0;
  END
  ELSE
    Seek(F, 0);

  InEsc := False;
  EscSeq := '';
  OutChunk := '';
  ClearBelowHeader;
  TermGotoRC(TopRow, 1);

  
  IF NOT IsAnsiFileG THEN OutStr('|07');
InEsc := False;
  EscSeq := '';
  OutChunk := '';
  LinesOut := 0;

  REPEAT
    BlockRead(F, Buf, SizeOf(Buf), Got);
    IF Got = 0 THEN Break;

    FOR I := 0 TO Got-1 DO
    BEGIN
      Ch := Char(Buf[I]);

      { Count displayed lines by LF }
      IF (Ch = #10) THEN
      BEGIN
        Inc(LinesOut);
        IF LinesOut >= PageRows THEN
        BEGIN
          { flush buffers and stop }
          IF OutChunk <> '' THEN
          BEGIN
            OutStr(OutChunk);
            OutChunk := '';
          END;
          Close(F);
          Exit;
        END;
      END;

      IF NOT InEsc THEN
      BEGIN
        IF Ch = ESC THEN
        BEGIN
          InEsc := True;
          EscSeq := ESC;
        END
        ELSE
        BEGIN
          OutChunk := OutChunk + Ch;
          IF Length(OutChunk) >= 200 THEN
          BEGIN
            OutStr(OutChunk);
            OutChunk := '';
          END;
        END;
      END
      ELSE
      BEGIN
        EscSeq := EscSeq + Ch;

        IF (Length(EscSeq) = 2) AND (Ch <> '[') THEN
        BEGIN
          OutChunk := OutChunk + EscSeq;
          EscSeq := '';
          InEsc := False;
        END
        ELSE IF (Length(EscSeq) >= 3) AND IsFinalByte(Ch) THEN
        BEGIN
          SBuf := RemapCSI(EscSeq);
          IF SBuf <> '' THEN
            OutChunk := OutChunk + SBuf;
          EscSeq := '';
          InEsc := False;
          IF Length(OutChunk) >= 200 THEN
          BEGIN
            OutStr(OutChunk);
            OutChunk := '';
          END;
        END
        ELSE IF Length(EscSeq) > 40 THEN
        BEGIN
          OutChunk := OutChunk + EscSeq;
          EscSeq := '';
          InEsc := False;
        END;
      END;
    END;

    IF OutChunk <> '' THEN
    BEGIN
      OutStr(OutChunk);
      OutChunk := '';
    END;
  UNTIL Got = 0;

  IF InEsc AND (EscSeq <> '') THEN
    OutStr(EscSeq);

  Close(F);
END;

PROCEDURE ViewAnsiFile(CONST FName, Title: AStr);
VAR
  CurPage: Integer;
  Total: Integer;
  Key: Word;
  CurLine: LongInt;
  TotLinesDisp: LongInt;
  StartLine: LongInt;
  LineMode: Boolean;
  AllowLine: Boolean;

  PROCEDURE ClampStartLine;
  VAR
    MaxStart: LongInt;
  BEGIN
    MaxStart := TotLinesDisp - PageRows + 1;
    IF MaxStart < 1 THEN MaxStart := 1;
    IF StartLine < 1 THEN StartLine := 1;
    IF StartLine > MaxStart THEN StartLine := MaxStart;
  END;

  PROCEDURE Redraw;
  BEGIN
    IF LineMode THEN
    BEGIN
      ClampStartLine;
      CurPage := (StartLine - 1) DIV PageRows;
      CurLine := StartLine;
      DrawHeader(Title, CurPage, Total, CurLine, TotLinesDisp, AllowLine, LineMode);
      RenderWindow(FName, StartLine);
      DrawFooter;
    END
    ELSE
    BEGIN
      CurLine := (LongInt(CurPage) * PageRows) + 1;
      IF CurLine > TotLinesDisp THEN CurLine := TotLinesDisp;
      DrawHeader(Title, CurPage, Total, CurLine, TotLinesDisp, AllowLine, LineMode);
      RenderPage(FName, CurPage);
      DrawFooter;
    END;
  END;

BEGIN
  IsAnsiFileG := IsAnsiExt(FName);
  ScanPages(FName);
  IF (NOT FileOK) THEN
  BEGIN
    NL;
    Prompt('^8File not found: ^0' + FName);
    NL;
    Prompt('^7Press any key...^0');
    GetKey;
    Exit;
  END;

  Total := PageCnt + 1;
  IF Total < 1 THEN Total := 1;

  TotLinesDisp := TotalLines;
  IF TotLinesDisp < 1 THEN TotLinesDisp := 1;

  CurPage := 0;
  StartLine := 1;
  AllowLine := AllowLineReader(FName);
  { Default Line Reader ON for text-ish files; keep Page mode for ANSI }
  LineMode := AllowLine AND (NOT IsAnsiFileG);

  Redraw;

  REPEAT
    InKey;
    Key := GetKey;

    IF NOT LineMode THEN
    BEGIN
      CASE Key OF
        27: Break; { ESC }

        76, 108: { L / l }
          IF AllowLine THEN
          BEGIN
            LineMode := True;
            StartLine := (LongInt(CurPage) * PageRows) + 1;
            Redraw;
          END;

        72*256, 73*256: { Up or PgUp }
          IF CurPage > 0 THEN
          BEGIN
            Dec(CurPage);
            Redraw;
          END;

        80*256, 81*256: { Down or PgDn }
          IF CurPage < (Total-1) THEN
          BEGIN
            Inc(CurPage);
            Redraw;
          END;

        71*256: { Home }
          IF CurPage <> 0 THEN
          BEGIN
            CurPage := 0;
            Redraw;
          END;

        79*256: { End }
          IF CurPage <> (Total-1) THEN
          BEGIN
            CurPage := Total-1;
            Redraw;
          END;
      END;
    END
    ELSE
    BEGIN
      CASE Key OF
        27: Break; { ESC }

        76, 108: { L / l }
          BEGIN
            LineMode := False;
            CurPage := (StartLine - 1) DIV PageRows;
            IF CurPage < 0 THEN CurPage := 0;
            IF CurPage > (Total-1) THEN CurPage := Total-1;
            Redraw;
          END;

        72*256: { Up }
          BEGIN
            Dec(StartLine);
            Redraw;
          END;

        80*256: { Down }
          BEGIN
            Inc(StartLine);
            Redraw;
          END;

        73*256: { PgUp }
          BEGIN
            StartLine := StartLine - PageRows;
            Redraw;
          END;

        81*256: { PgDn }
          BEGIN
            StartLine := StartLine + PageRows;
            Redraw;
          END;

        71*256: { Home }
          BEGIN
            StartLine := 1;
            Redraw;
          END;

        79*256: { End }
          BEGIN
            StartLine := TotLinesDisp; { ClampStartLine will adjust }
            Redraw;
          END;

        13, 32: { Enter or Space }
          BEGIN
            Inc(StartLine);
            Redraw;
          END;

        8: { Backspace }
          BEGIN
            Dec(StartLine);
            Redraw;
          END;
      END;
    END;

  UNTIL False;

  { reset attrs and move cursor }
  OutStr(ESC+'[0m');
  TermGotoRC(25,1);
END;

END.
