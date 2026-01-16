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

  ESC = #27;

TYPE
  TOffsets = ARRAY[0..MaxPages] OF LongInt;

VAR
  Offsets : TOffsets;
  PageCnt : Integer;

PROCEDURE OutStr(CONST S: String);
BEGIN
  { Prompt does not append CR/LF }
  Prompt(S);
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
BEGIN
  TermGotoRC(TopRow, 1);
  OutStr(ESC + '[0J');
END;

PROCEDURE DrawHeader(CONST Title: AStr);
BEGIN
  TermGotoRC(1,1); OutStr(ESC + '[0m'); { reset attrs }
  OutStr(ESC + '[2K');  { clear line }
  OutStr('|11 ' + Title);
  TermGotoRC(2,1); OutStr(ESC + '[2K');
  OutStr(' |09Up/Down=Page  Home/End  |14ESC|09=Exit');
  TermGotoRC(3,1); OutStr(ESC + '[2K');
  OutStr('|01컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴컴�');
          
END;

PROCEDURE DrawFooter(CurPage, TotalPages: Integer);
VAR
  S1,S2: String;
BEGIN
  TermGotoRC(25,1);
  OutStr(ESC + '[2K');
  Str(CurPage+1, S1);
  Str(TotalPages, S2);
  OutStr(' Page ' + S1 + '/' + S2);
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

  Assign(F, FN);
  Reset(F, 1);
  Posn := 0;
  Lines := 0;

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
  Assign(F, FN);
  Reset(F, 1);

  StartPos := Offsets[CurPage];
  IF CurPage < PageCnt THEN
    EndPos := Offsets[CurPage+1]
  ELSE
    EndPos := High(LongInt);

  Seek(F, StartPos);

  ClearBelowHeader;
  TermGotoRC(TopRow, 1);

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

PROCEDURE ViewAnsiFile(CONST FName, Title: AStr);
VAR
  CurPage: Integer;
  Total: Integer;
  Key: Word;
BEGIN
  ScanPages(FName);
  Total := PageCnt + 1;
  IF Total < 1 THEN Total := 1;
  CurPage := 0;

  DrawHeader(Title);
  RenderPage(FName, CurPage);
  { draw footer last so ANSI output can't overwrite it }
  DrawFooter(CurPage, Total);

  REPEAT
    { InKey updates, GetKey returns word }
    InKey;
    Key := GetKey;

    CASE Key OF
      27: Break; { ESC }

      { GetKey returns ScanCode*256 for extended keys }
      72*256, 73*256: { Up or PgUp }
        IF CurPage > 0 THEN
        BEGIN
          Dec(CurPage);
          DrawHeader(Title);
          RenderPage(FName, CurPage);
          DrawFooter(CurPage, Total);
        END;

      80*256, 81*256: { Down or PgDn }
        IF CurPage < (Total-1) THEN
        BEGIN
          Inc(CurPage);
          DrawHeader(Title);
          RenderPage(FName, CurPage);
          DrawFooter(CurPage, Total);
        END;

      71*256: { Home }
        IF CurPage <> 0 THEN
        BEGIN
          CurPage := 0;
          DrawHeader(Title);
          RenderPage(FName, CurPage);
          DrawFooter(CurPage, Total);
        END;

      79*256: { End }
        IF CurPage <> (Total-1) THEN
        BEGIN
          CurPage := Total-1;
          DrawHeader(Title);
          RenderPage(FName, CurPage);
          DrawFooter(CurPage, Total);
        END;
    END;

  UNTIL False;

  { reset attrs and move cursor }
  OutStr(ESC+'[0m');
  TermGotoRC(25,1);
END;

END.
