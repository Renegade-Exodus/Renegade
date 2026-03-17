{$A+,B-,D-,E-,F+,I-,L-,N-,O+,R-,S+,V-}

UNIT Nodelist;

INTERFACE

USES
  Common;

PROCEDURE ToggleNetAttr(NetAttrT: NetAttr; VAR NetAttrS: NetAttribs);
PROCEDURE ToggleNetAttrs(C: CHAR; VAR NetAttrS: NetAttribs);
FUNCTION GetNewAddr(DisplayStr: AStr; MaxLen: Byte; VAR Zone,Net,Node,Point: Word): Boolean;
PROCEDURE GetNetAddress(VAR SysOpName: AStr; VAR Zone,Net,Node,Point,Fee: Word; GetFee: Boolean);
PROCEDURE ChangeFlags(VAR MsgHeader: MHeaderRec);
FUNCTION NetMail_Attr(NetAttribute: NetAttribs): AStr;
PROCEDURE BrowseNodeLists;

IMPLEMENTATION

USES
  Mail0, Dos;

TYPE
  CompProc = FUNCTION(VAR ALine,Desire; L: Char): Integer;

  DATRec = RECORD
    Zone,                                           { Zone of board                             }
    Net,                                                { Net Address of board              }
    Node,                                           { Node Address of board             }
    Point: Integer;             { Either Point number OR 0      }
    CallCost,                                   { Cost to sysop to send             }
    MsgFee,                                         { Cost to user to send              }
    NodeFlags: Word;                { Node flags                                    }
    ModemType,                                  { Modem TYPE                                    }
    PassWord: STRING[9];
    Phone,
    BName,
    CName,
    SName: STRING[39];
    BaudRate,                   { Highest Baud Rate                     }
    RecSize: Byte;              { Size of the Node on FILE      }
  END;

  IndxRefBlk = RECORD
    IndxOfs,        { Offset of STRING into block }
    IndxLen: Word;  { Length of STRING                      }
    IndxData,           { RECORD number of STRING       }
    IndxPtr: LongInt;   { Block number of lower index }
  END;  { IndxRef }

  LeafRefBlk = RECORD
    KeyOfs,         { Offset of STRING into block }
    KeyLen: Word;   { Length of STRING                      }
    KeyVal: LongInt;    { Pointer to Data block             }
  END;  { LeafRef }

  CtlBlk = RECORD
    CtlBlkSize: Word;   { blocksize of Index blocks     }
    CtlRoot,                                        { Block number of Root              }
    CtlHiBlk,                                   { Block number of last block    }
    CtlLoLeaf,      { Block number of first leaf    }
    CtlHiLeaf,      { Block number of last leaf     }
    CtlFree: LongInt;   { Head of freelist                      }
    CtlLvls,        { Number of index levels            }
    CtlParity: Word;    { XOR of above fields               }
  END;

  INodeBlk = RECORD
    IndxFirst,          { Pointer to next lower level }
    IndxBLink,          { Pointer to previous link      }
    IndxFLink: LongInt;         { Pointer to next link              }
    IndxCnt: Integer;           { Count of Items IN block       }
    IndxStr: Word;              { Offset IN block of 1st str    }
                                { IF IndxFirst is NOT -1, this is INode:    }
    IndxRef: ARRAY [0..49] OF IndxRefBlk;
  END;

  LNodeBlk = RECORD
    IndxFirst,          { Pointer to next lower level }
    IndxBLink,          { Pointer to previous link      }
    IndxFLink: LongInt;         { Pointer to next link              }
    IndxCnt: Integer;           { Count of Items IN block       }
    IndxStr: Word;              { Offset IN block of 1st str    }
    LeafRef: ARRAY [0..49] OF LeafRefBlk;
  END;

PROCEDURE ToggleNetAttr(NetAttrT: NetAttr; VAR NetAttrS: NetAttribs);
BEGIN
  IF (NetAttrT IN NetAttrS) THEN
    Exclude(NetAttrS,NetAttrT)
  ELSE
    Include(NetAttrS,NetAttrT);
END;

PROCEDURE ToggleNetAttrs(C: CHAR; VAR NetAttrS: NetAttribs);
BEGIN
  CASE C OF
    'C' : ToggleNetAttr(Crash,NetAttrS);
    'H' : ToggleNetAttr(Hold,NetAttrS);
    'I' : ToggleNetAttr(InTransit,NetAttrS);
    'K' : ToggleNetAttr(KillSent,NetAttrS);
    'L' : ToggleNetAttr(Local,NetAttrS);
    'P' : ToggleNetAttr(Private,NetAttrS);
  END;
END;

FUNCTION GetNewAddr(DisplayStr: AStr; MaxLen: Byte; VAR Zone,Net,Node,Point: Word): Boolean;
BEGIN
  GetNewAddr := FALSE;
  Prt(DisplayStr);
  InputMain(DisplayStr,MaxLen,[CapAll]);
  IF (DisplayStr = '') OR (Pos('/',DisplayStr) = 0) THEN
    Exit;
  IF (Pos(':',DisplayStr) > 0) THEN
  BEGIN
    Zone := StrToInt(Copy(DisplayStr,1,Pos(':',DisplayStr)));
    DisplayStr := Copy(DisplayStr,Pos(':',DisplayStr)+1,Length(DisplayStr));
  END
  ELSE
    Zone := 1;
  IF (Pos('.',DisplayStr) > 0) THEN
  BEGIN
    Point := StrToInt(Copy(DisplayStr,Pos('.',DisplayStr)+1,Length(DisplayStr)));
    DisplayStr := Copy(DisplayStr,1,Pos('.',DisplayStr)-1);
  END
  ELSE
    Point := 0;
  Net := StrToInt(Copy(DisplayStr,1,Pos('/',DisplayStr)));
  Node := StrToInt(Copy(DisplayStr,Pos('/',DisplayStr)+1,Length(DisplayStr)));
  GetNewAddr := TRUE;
END;

FUNCTION NetMail_Attr(NetAttribute: NetAttribs): Astr;
VAR
  s: AStr;
BEGIN
  s := '';
  IF (Local IN NetAttribute) THEN
    s := 'Local ';
  IF (Private IN NetAttribute) THEN
    s := s + 'Private ';
  IF (Crash IN NetAttribute) THEN
    s := s + 'Crash ';
  IF (FileAttach IN NetAttribute) THEN
    s := s + 'FileAttach ';
  IF (InTransit IN NetAttribute) THEN
    s := s + 'InTransit ';
  IF (KillSent IN NetAttribute) THEN
    s := s + 'KillSent ';
  IF (Hold IN NetAttribute) THEN
    s := s + 'Hold ';
  IF (FileRequest IN NetAttribute) THEN
    s := s + 'File Request ';
  IF (FileUpdateRequest IN NetAttribute) THEN
    s := s + 'Update Request ';
  NetMail_Attr := s;
END;

FUNCTION CompName(VAR ALine,Desire; L: Char): Integer;
VAR
  Key,
  Desired: STRING[36];
  Len: Byte ABSOLUTE L;
BEGIN
  Key[0] := L;
  Desired[0] := L;
  Move(ALine,Key[1],Len);
  Move(Desire,Desired[1],Len);
  IF (Key > Desired) THEN
    CompName := 1
  ELSE IF (Key < Desired) THEN
    CompName := -1
  ELSE
    CompName := 0;
END;

FUNCTION CompAddress(VAR ALine,Desire; L: Char): Integer;
TYPE
  NodeType = RECORD
    Zone,
    Net,
    Node,
    Point: Word;
  END;
VAR
  Key: NodeType ABSOLUTE ALine;
  Desired: NodeType ABSOLUTE Desire;
  Count: Byte;
  K: Integer;
BEGIN
  Count := 0;
  REPEAT
    Inc(Count);
    CASE Count OF
      1 : Word(K) := Key.Zone - Desired.Zone;
      2 : Word(K) := Key.Net  - Desired.Net;
      3 : Word(K) := Key.Node - Desired.Node;
      4 : BEGIN
            IF (L = #6) THEN
              Key.Point := 0;
            Word(K) := Key.Point - Desired.Point;
          END;
    END;
  UNTIL (Count = 4) OR (K <> 0);
  Compaddress := K;
END;

PROCEDURE GetNetAddress(VAR SysOpName:AStr; VAR Zone,Net,Node,Point,Fee:Word; GetFee:Boolean);
VAR
  DataFile,
  NDXFile: FILE;
  s: STRING[36];
  Location: LongInt;
  Dat: DatRec;
  Internet: Boolean;

  FUNCTION FullNodeStr(NodeStr: AStr): STRING;
  { These constants are the defaults IF the user does NOT specify them }
  CONST
    DefZone = '1';          { Default Zone  }
    DefNet = '1';         { Default Net   }
    DefNode = '1';          { Default Node  }
    DefPoint = '0';         { Default Point }
  BEGIN
    IF (NodeStr[1] = '.') THEN
      NodeStr := DefNode + NodeStr;
    IF (Pos('/',NodeStr) = 0) THEN
      IF (Pos(':',NodeStr) = 0) THEN
        NodeStr := DefZone+':'+DefNet+'/'+NodeStr
      ELSE
    ELSE
    BEGIN
      IF (NodeStr [1] = '/') THEN
        NodeStr := DefNet + NodeStr;
      IF (Pos(':',NodeStr) = 0) THEN
        NodeStr := DefZone + ':' + NodeStr;
      IF (NodeStr[Length(NodeStr)] = '/') THEN
        NodeStr := NodeStr + DefNode;
    END;
    IF (Pos('.',NodeStr) = 0) THEN
      NodeStr := NodeStr+'.'+DefPoint;
    FullNodeStr := NodeStr;
  END;

  FUNCTION MakeAddress(Z,Nt,N,P: Word): STRING;
  TYPE
    NodeType = RECORD           { A Node address TYPE }
      Len: Byte;
      Zone,
      Net,
      Node,
      Point: Word;
    END;
  VAR
    Address: NodeType;
    S2: STRING ABSOLUTE Address;
  BEGIN
    WITH Address DO
    BEGIN
      Zone := Z;
      Net := Nt;
      Node := N;
      Point := P;
      Len := 8;
    END;
    MakeAddress := S2;
  END;

  FUNCTION MakeName(Name: AStr): STRING;
  VAR
    Temp: STRING[36];
    Comma: STRING[2];
  BEGIN
    Temp := Caps(Name);
    IF (Pos(' ', Name) > 0) THEN
      Comma := ', '
    ELSE
      Comma := '';
    MakeName := Copy(Temp, Pos(' ',Temp) + 1, Length(Temp) - Pos(' ',Temp))
                     + Comma + Copy(Temp,1,Pos(' ',Temp) - 1) + #0;
  END;

  PROCEDURE UnPk(S1: STRING; VAR S2: STRING; Count: Byte);
  CONST
    UnWrk: ARRAY [0..38] OF Char = ' EANROSTILCHBDMUGPKYWFVJXZQ-''0123456789';
  TYPE
    CharType = RECORD
      C1,
      C2: Byte;
    END;
  VAR
    U: CharType;
    W1: Word ABSOLUTE U;
    I,
    J: Integer;
    OBuf: ARRAY [0..2] OF Char;
    Loc1,
    Loc2: Byte;
  BEGIN
    S2 := '';
    Loc1 := 1;
    Loc2 := 1;
    WHILE (Count > 0) DO
    BEGIN
      U.C1 := Ord(S1[Loc1]);
      Inc(Loc1);
      U.C2 := Ord(S1[Loc1]);
      Inc(Loc1);
      Count := Count - 2;
      for J := 2 downto 0 DO
      BEGIN
        I := W1 MOD 40;
        W1 := W1 DIV 40;
        OBuf[J] := UnWrk[I];
      END;
      Move(OBuf,S2[Loc2],3);
      Inc(Loc2,3);
    END;
    S2[0] := Chr(Loc2);
  END;

  FUNCTION GetData(VAR F1: FILE; SL: LongInt; VAR Dat: DATRec): Boolean;
  TYPE
    RealDATRec = RECORD
      Zone,                                             { Zone of board                             }
      Net,                                              { Net Address of board              }
      Node,                                             { Node Address of board             }
      Point: Integer;               { Either Point number OR 0      }
      CallCost,                                     { Cost to sysop to send             }
      MsgFee,                                       { Cost to user to send              }
      NodeFlags: Word;              { Node flags                                    }
      ModemType,                                    { Modem TYPE                                    }
      PhoneLen,                                     { Length of Phone Number            }
      PassWordLen,                              { Length of Password                    }
      BNameLen,                                     { Length of Board Name              }
      SNameLen,                                     { Length of Sysop Name              }
      CNameLen,                                     { Length of City/State Name     }
      PackLen,                                      { Length of Packed STRING       }
      Baud: Byte;               { Highest Baud Rate                     }
      Pack: ARRAY [1..160] of Char;     { The Packed STRING                     }
    END;
  VAR
    Data: RealDATRec;
    Error: Boolean;
    UnPack: STRING[160];
  BEGIN
    Seek(F1,SL);
    { Read everything at once to keep disk access to a minimum }
    BlockRead(F1,Data,SizeOf(Data));
    Error := (IOResult <> 0);
    IF (NOT Error) THEN
      WITH Dat,Data DO
      BEGIN
        Move(Data,Dat,15);
        Phone := Copy(Pack,1,PhoneLen);
        PassWord := Copy(Pack,(PhoneLen + 1),PasswordLen);
        Move(Pack[PhoneLen + PasswordLen + 1],Pack[1],PackLen);
        UnPk(Pack,UnPack,PackLen);
        BName := AllCaps(Copy(UnPack,1,BNameLen));
        SName := AllCaps(Copy(Unpack,(BNameLen + 1),SNameLen));
        CName := AllCaps(Copy(UnPack,BNameLen + SNameLen + 1,CNameLen));
        BaudRate := Baud;
        RecSize := (PhoneLen + PassWordLen + PackLen) + 22;
      END;
  END;

  PROCEDURE Get7Node(VAR F: FILE; SL: LongInt; VAR Buf);
  BEGIN
    Seek(F,SL);
    BlockRead(F,Buf,512);
    IF (IOResult <> 0) THEN
      Halt(1);
  END;

  FUNCTION BTree(VAR F1: FILE; Desired: AStr; Compare: CompProc): LongInt;
  LABEL
    Return;
  VAR
    Buf: ARRAY [0..511] OF Char;  { These four variables }
    CTL: CTLBlk ABSOLUTE Buf;     { all occupy the same  }
    INode: INodeBlk ABSOLUTE Buf; { memory location      }
    LNode: LNodeBlk ABSOLUTE Buf; { Total of 512 bytes   }
    {/}
    NodeCTL: CTLBlk;              { Store the CTL block seperately }
    ALine: STRING[160];           { Address from NDX FILE }
    J,
    K,
    L,Count: Integer; { Temp integers }
    TP: Word; { Pointer to location IN BUF }
    Rec, { A temp RECORD IN the FILE }
    FRec: LongInt; { The RECORD when found OR NOT }
  BEGIN
    FRec := -1;
    Get7Node(F1,0,Buf);
    IF (CTL.CTLBlkSize = 0) THEN GOTO
      Return;
    Move(Buf,NodeCTL,SizeOf(CTL));
    Get7Node(F1,NodeCTL.CtlRoot * NodeCTL.CtlBlkSize,Buf);
    WHILE (INode.IndxFirst <> -1) AND (FRec = -1) DO
    BEGIN
      Count := INode.IndxCnt;
      IF (Count = 0) THEN GOTO
        Return;
      J := 0;
      K := -1;
      WHILE (J < Count) AND (K < 0) DO
      BEGIN
        TP := INode.IndxRef[J].IndxOfs;
        L := INode.IndxRef[J].IndxLen;
        { ALine [0] := Chr (L); }
        Move(Buf[TP],ALine[1],L);
        K := Compare(ALine[1],Desired[1],Chr(L));
        IF (K = 0) THEN
          FRec := INode.IndxRef[J].IndxData
        ELSE IF (K < 0) THEN
          Inc(J);
      END;
      IF (FRec = -1) THEN
      BEGIN
        IF (J = 0) THEN
          Rec := INode.IndxFirst
        ELSE
          Rec := INode.IndxRef[J - 1].IndxPtr;
        Get7Node(F1,Rec * NodeCTL.CtlBlkSize,Buf);
      END;
    END;
    IF (FRec = -1) THEN
    BEGIN
      Count := LNode.IndxCnt;
      IF (Count <> 0) THEN
      BEGIN
        J := 0;
        WHILE (J < Count) AND (FRec = -1) DO
        BEGIN
          TP := LNode.LeafRef[J].KeyOfs;
          L := LNode.LeafRef[J].KeyLen;
          { ALine [0] := Chr (L); }
          Move(Buf[TP],ALine[1],L);
          K := Compare(ALine[1],Desired[1],Chr(L));
          IF (K = 0) THEN
            FRec := LNode.LeafRef[J].KeyVal;
          Inc(J);
        END;
      END;
    END;
    Return :
    BTree := FRec;
  END;

  FUNCTION Pull(VAR S: STRING; C: Char): STRING;
  VAR
    I: Byte;
  BEGIN
    I := Pos(C,S);
    Pull := Copy(S,1,(I - 1));
    Delete(S,1,I);
  END;

BEGIN
  NL;
  Internet := FALSE;
  IF NOT Exist(General.NodePath+'NODEX.DAT') OR
     NOT Exist(General.NodePath+'SYSOP.NDX') OR
     NOT Exist(General.NodePath+'NODEX.NDX') THEN
  BEGIN
    IF (GetFee) THEN
    BEGIN
      Fee := 0;
      Exit;
    END;
  { Print('Enter name of intended receiver.');
    Prt(':');
    InputDefault(SysOpName,SysOpName,36,[CapWords],TRUE); }
    InputString('Enter name of intended receiver ',SysOpName,36,[InteractiveEdit,CapWords],Changed);
    IF (SysOpName = '') THEN
      Exit;
    {IF (Pos('@',SysOpName) > 0) THEN
      IF (PYNQ('Is this an Internet message? ',0,FALSE)) THEN
      BEGIN
        Internet := TRUE;
        Zone := General.Aka[20].Zone;
        Net := General.Aka[20].Net;
        Node := General.Aka[20].Node;
        Point := General.Aka[20].Point;
        Fee := 0;
        Exit;
      END
      ELSE}
        NL;
    IF NOT GetNewAddr('^2Enter network address (^1Z^2:^1N^2/^1N^2.^1P^2 format): ',30,Zone,Net,Node,Point) THEN
      Exit;
    Exit;
  END;
  Assign(DataFile,General.NodePath+'NODEX.DAT');
  IF (GetFee) THEN
  BEGIN
    s := IntToStr(Net)+'/'+IntToStr(Node);
    IF (Zone > 0) THEN
      s := IntToStr(Zone)+':'+s;
    IF (Point > 0) THEN
      s := s+'.'+IntToStr(Point);
    s := FullNodeStr(s);
    Assign(NDXFile,General.NodePath+'NODEX.NDX');
    Reset(NDXFile,1);
    Location := BTree(NDXFile,MakeAddress(StrToInt(Pull(S,':')),
                      StrToInt(Pull(S,'/')),StrToInt(Pull(S,'.')),
                      StrToInt(S)),Compaddress);
    Close(NDXFile);
    IF (Location <> -1) THEN
    BEGIN
      Reset(DataFile,1);
      GetData(DataFile,Location,Dat);
      Close(DataFile);
      Fee := Dat.MsgFee;
    END
    ELSE
      Fee := 0;
    Exit;
  END;
  s := SysOpName;
  SysOpName := '';
  Fee := 0;
  REPEAT
  { Print('Enter a name, a Fidonet address, or an Internet address.');
    Prt(':');
    InputDefault(s,s,36,[],TRUE); } {LeeW: Changed--checkthis}
    InputString('^2Enter network address (^1Z^2:^1N^2/^1N^2.^1P^2 format): ',s,20,[InteractiveEdit],Changed);
    Print('');
	IF (s = '') THEN
      Break;
    IF (Pos('/',s) > 0) THEN
    BEGIN
      s := FullNodeStr(s);
      Assign(NDXFile,General.NodePath+'NODEX.NDX');
      Reset(NDXFile,1);
      Location := BTree(NDXFile,MakeAddress(StrToInt(Pull(S,':')),StrToInt(Pull(S,'/')),StrToInt(Pull(S,'.')),StrToInt(S)),
                        Compaddress);
      Close(NDXFile);
    END
    ELSE
    BEGIN
      Assign(NDXFile,General.NodePath+'SYSOP.NDX');
      Reset(NDXFile,1);
      Location := BTree(NDXFile,MakeName(S),CompName);
      Close(NDXFile);
    END;
    IF (Location <> -1) THEN
    BEGIN
      Reset(DataFile,1);
      GetData(DataFile,Location,Dat);
      Close(DataFile);
      WITH Dat DO
      BEGIN
      NL;
	    Print('^2System Name|11: ^1'+BName+' |08(|15'+IntToStr(Zone)+':'+IntToStr(Net)+'/'+IntToStr(Node)+'|08)^1');
        Print(' ^2SysOp Name|11: ^1'+SName);
		NL;
        {Print('|03Phone : |11'+Phone);
        Print('|03Where : |11'+CName);
        Print('|04Cost  |12: |14'+IntToStr(MsgFee)+' |15credits');}
      END;
      IF (Dat.MsgFee > (ThisUser.lCredit - ThisUser.Debit)) THEN
      BEGIN
        Print('You do not have enough credit to netmail this Node!');
        s := '';
      END
      ELSE IF PYNQ('Is this correct?',0,FALSE) THEN
      BEGIN
        SysOpName := Dat.Sname;
        Zone := Dat.Zone;
        Net := Dat.Net;
        Node := Dat.Node;
        Point := 0;
        Fee := Dat.MsgFee;
      END
      ELSE
        s := '';
    END
{    ELSE IF (Pos('@',s) > 0) THEN
      IF (NOT PYNQ('Is this an Internet message? ',0,FALSE)) THEN
      BEGIN
        Print('That name is not in the nodelist!'^M^J);
        S := '';
      END
      ELSE
      BEGIN
        Internet := TRUE;
        SysOpName := s;
        Zone := General.Aka[20].Zone;
        Net := General.Aka[20].Net;
        Node := General.Aka[20].Node;
        Point := General.Aka[20].Point;
        Fee := 0;
      END;}
      ELSE
      BEGIN
        Print('That name is not in the nodelist!'^M^J);
        S := '';
      END
  UNTIL (SysOpName <> '') OR (HangUp);
  IF (NOT Internet) AND (Pos('/',s) = 0) AND (s <> '') THEN
  BEGIN
  { NL;
    Print('Enter name of intended receiver.');
    Prt(':');
    InputDefault(SysOpName,SysOpName,36,[CapWords],FALSE); }
	NL;
    InputString('^2Enter name of intended receiver: ',SysOpName,36,[InteractiveEdit,CapWords],Changed);
    IF (SysOpName = '') THEN
      Exit;
  END;
  LastError := IOResult;
END;

PROCEDURE ChangeFlags(VAR MsgHeader: MHeaderRec);
VAR
  Cmd: Char;
BEGIN
  IF (CoSysOp) AND (PYNQ('Change default netmail flags? ',0,FALSE)) THEN
  BEGIN
    Cmd := #0;
    NL;
    REPEAT
      IF (Cmd <> '?') THEN
      BEGIN
        Print('^2Current flags: ^1'+NetMail_Attr(MsgHeader.NetAttribute));
        NL
      END;
      Prt('Flag to change: ');
      InputChar('',Cmd,'QPCAIKHRLU?'^M,[CapAll]);
      IF (Cmd IN ['?']) THEN
        NL;
      WITH MsgHeader DO
        CASE Cmd OF
          'L' : ToggleNetAttr(Local,NetAttribute);
          'U' : ToggleNetAttr(FileUpdateRequest,NetAttribute);
          'R' : ToggleNetAttr(FileRequest,NetAttribute);
          'H' : ToggleNetAttr(Hold,NetAttribute);
          'K' : ToggleNetAttr(KillSent,NetAttribute);
          'I' : ToggleNetAttr(InTransit,NetAttribute);
          'A' : ToggleNetAttr(FileAttach,NetAttribute);
          'C' : ToggleNetAttr(Crash,NetAttribute);
          'P' : ToggleNetAttr(Private,NetAttribute);
          '?' : BEGIN
                  LCmds3(15,1,'Private','Crash','Attached File');
                  LCmds3(15,1,'InTransit','KillSent','Hold');
                  LCmds3(15,1,'Req file','Update Req','Local');
                END;
        END;
    UNTIL (Cmd IN ['Q',^M]) OR (HangUp);
  END;
  NL;
END;



FUNCTION FileExistsFN(FN: AStr): Boolean;
VAR
  F: File;
BEGIN
  Assign(F, FN);
  {$I-} Reset(F); {$I+}
  IF IOResult = 0 THEN
  BEGIN
    Close(F);
    FileExistsFN := TRUE;
  END
  ELSE
    FileExistsFN := FALSE;
END;

CONST
  NLMaxZones     = 32;
  NLMaxNetPages  = 64;
  NLNetsPerPage  = 32;
  NLMaxNodePages = 400;
  NLNodesPerPage = 24;
  NLMaxCfgItems  = 32;
  NLViewRows     = 18;
  NLSubBoxWidth  = 65;
  NLSubBoxHeight = 15;
  NLSubBoxRows   = 13;

TYPE
  NLS20 = STRING[20];
  NLS40 = STRING[40];
  NLS60 = STRING[60];
  NLS79 = STRING[79];

  PNLNodeRec = ^NLNodeRec;
  NLNodeRec = RECORD
    Number : Integer;
    Addr   : NLS20;
    Status : NLS20;
    BBS    : NLS60;
    City   : NLS40;
    Sysop  : NLS40;
    Phone  : NLS40;
    Baud   : NLS20;
  END;

  NLNodePageRec = RECORD
    Items : ARRAY[1..NLNodesPerPage] OF NLNodeRec;
  END;
  PNLNodePage = ^NLNodePageRec;

  PNLNetRec = ^NLNetRec;
  NLNetRec = RECORD
    NetNum    : Integer;
    Kind      : Char;
    Name      : NLS60;
    ZoneNum   : Integer;
    NodeStart : LongInt;
    NodeEnd   : LongInt;
  END;

  NLNetPageRec = RECORD
    Items : ARRAY[1..NLNetsPerPage] OF NLNetRec;
  END;
  PNLNetPage = ^NLNetPageRec;

  NLZoneRec = RECORD
    ZoneNum  : Integer;
    Name     : NLS60;
    NetStart : Integer;
    NetEnd   : Integer;
  END;
  PNLZoneRec = ^NLZoneRec;

  NLCfgRec = RECORD
    Name     : NLS60;
    Mask     : NLS79;
    Resolved : NLS79;
  END;
  PNLCfgRec = ^NLCfgRec;

VAR
  NLNodePages   : ARRAY[1..NLMaxNodePages] OF PNLNodePage;
  NLNetPages    : ARRAY[1..NLMaxNetPages] OF PNLNetPage;
  NLZones       : ARRAY[1..NLMaxZones] OF PNLZoneRec;
  NLStartNodeIdx: LongInt;
  NLNodeCount   : LongInt;
  NLNetCount    : Integer;
  NLZoneCount   : Integer;
  NLSourceFile  : NLS79;
  NLCfgItems    : ARRAY[1..NLMaxCfgItems] OF PNLCfgRec;
  NLCfgCount    : Integer;
  NLQuit        : Boolean;

FUNCTION NLTrimS(S: STRING): STRING;
BEGIN
  WHILE (Length(S) > 0) AND (S[1] = ' ') DO
    Delete(S, 1, 1);
  WHILE (Length(S) > 0) AND (S[Length(S)] = ' ') DO
    Delete(S, Length(S), 1);
  NLTrimS := S;
END;

FUNCTION NLUpperS(S: STRING): STRING;
VAR
  I: Integer;
BEGIN
  FOR I := 1 TO Length(S) DO
    S[I] := UpCase(S[I]);
  NLUpperS := S;
END;

FUNCTION NLU2Sp(S: STRING): STRING;
VAR
  I: Integer;
BEGIN
  FOR I := 1 TO Length(S) DO
    IF S[I] = '_' THEN
      S[I] := ' ';
  NLU2Sp := S;
END;

FUNCTION NLNextToken(VAR S: STRING): STRING;
VAR
  P: Integer;
BEGIN
  P := Pos(',', S);
  IF P = 0 THEN
  BEGIN
    NLNextToken := S;
    S := '';
  END
  ELSE
  BEGIN
    NLNextToken := Copy(S, 1, P - 1);
    Delete(S, 1, P);
  END;
END;

FUNCTION NLDirPartOnly(S: STRING): STRING;
VAR
  I: Integer;
BEGIN
  I := Length(S);
  WHILE (I > 0) AND (S[I] <> '\') AND (S[I] <> '/') AND (S[I] <> ':') DO
    Dec(I);
  IF I > 0 THEN
    NLDirPartOnly := Copy(S, 1, I)
  ELSE
    NLDirPartOnly := '';
END;

FUNCTION NLBaseNameOnly(S: STRING): STRING;
VAR
  I: Integer;
BEGIN
  I := Length(S);
  WHILE (I > 0) AND (S[I] <> '\') AND (S[I] <> '/') AND (S[I] <> ':') DO
    Dec(I);
  NLBaseNameOnly := Copy(S, I + 1, 255);
END;

FUNCTION NLNameWithoutExt(S: STRING): STRING;
VAR
  P: Integer;
BEGIN
  P := Pos('.', S);
  IF P = 0 THEN
    NLNameWithoutExt := S
  ELSE
    NLNameWithoutExt := Copy(S, 1, P - 1);
END;

FUNCTION NLExtNum2(S: AStr): Integer;
VAR
  P, N, Code: Integer;
  E: AStr;
BEGIN
  NLExtNum2 := -1;
  P := Pos('.', S);
  IF P = 0 THEN Exit;
  E := Copy(S, P + 1, 3);
  IF Length(E) <> 3 THEN Exit;
  Val(E, N, Code);
  IF Code <> 0 THEN Exit;
  IF (N < 0) OR (N > 999) THEN Exit;
  NLExtNum2 := N;
END;

FUNCTION ResolveLatestNodeList2(Mask: AStr): AStr;
VAR
  SR: SearchRec;
  BestName, DirPart, FindMask, MatchBase: AStr;
  BestExt, CurExt: Integer;
BEGIN
  ResolveLatestNodeList2 := '';

  IF FileExistsFN(Mask) THEN
  BEGIN
    ResolveLatestNodeList2 := Mask;
    Exit;
  END;

  DirPart := NLDirPartOnly(Mask);
  MatchBase := NLUpperS(NLNameWithoutExt(NLBaseNameOnly(Mask)));
  FindMask := Mask;
  IF (Length(Mask) >= 4) AND
     (Copy(NLUpperS(Mask), Length(Mask) - 3, 4) = '.###') THEN
    FindMask := DirPart + MatchBase + '.*';

  BestName := '';
  BestExt := -1;
  FindFirst(FindMask, AnyFile, SR);
  WHILE DosError = 0 DO
  BEGIN
    CurExt := NLExtNum2(SR.Name);
    IF (CurExt >= 0) AND
       (NLUpperS(NLNameWithoutExt(SR.Name)) = MatchBase) THEN
      IF CurExt > BestExt THEN
      BEGIN
        BestExt := CurExt;
        BestName := SR.Name;
      END;
    FindNext(SR);
  END;

  IF BestName <> '' THEN
    ResolveLatestNodeList2 := DirPart + BestName;
END;

PROCEDURE NLResetNodesOnly;
VAR
  I: Integer;
BEGIN
  FOR I := 1 TO NLMaxNodePages DO
    IF NLNodePages[I] <> NIL THEN
    BEGIN
      Dispose(NLNodePages[I]);
      NLNodePages[I] := NIL;
    END;
  NLNodeCount := 0;
END;

PROCEDURE NLResetData;
VAR
  I: Integer;
BEGIN
  NLResetNodesOnly;
  NLNetCount := 0;
  FOR I := 1 TO NLZoneCount DO
    IF NLZones[I] <> NIL THEN
    BEGIN
      Dispose(NLZones[I]);
      NLZones[I] := NIL;
    END;
  NLZoneCount := 0;
END;

PROCEDURE NLInitPages;
VAR
  I: Integer;
BEGIN
  FOR I := 1 TO NLMaxNodePages DO
    NLNodePages[I] := NIL;
  FOR I := 1 TO NLMaxNetPages DO
    NLNetPages[I] := NIL;
  FOR I := 1 TO NLMaxZones DO
    NLZones[I] := NIL;
END;

PROCEDURE NLDonePages;
VAR
  I: Integer;
BEGIN
  FOR I := 1 TO NLMaxNodePages DO
    IF NLNodePages[I] <> NIL THEN
    BEGIN
      Dispose(NLNodePages[I]);
      NLNodePages[I] := NIL;
    END;
  FOR I := 1 TO NLMaxNetPages DO
    IF NLNetPages[I] <> NIL THEN
    BEGIN
      Dispose(NLNetPages[I]);
      NLNetPages[I] := NIL;
    END;
  FOR I := 1 TO NLZoneCount DO
    IF NLZones[I] <> NIL THEN
    BEGIN
      Dispose(NLZones[I]);
      NLZones[I] := NIL;
    END;
  NLZoneCount := 0;
END;


PROCEDURE NLDoneCfg;
VAR
  I: Integer;
BEGIN
  FOR I := 1 TO NLCfgCount DO
    IF NLCfgItems[I] <> NIL THEN
    BEGIN
      Dispose(NLCfgItems[I]);
      NLCfgItems[I] := NIL;
    END;
  NLCfgCount := 0;
END;

PROCEDURE NLEnsureNodePage(PageNo: Integer);
BEGIN
  IF (PageNo >= 1) AND (PageNo <= NLMaxNodePages) AND
     (NLNodePages[PageNo] = NIL) THEN
    New(NLNodePages[PageNo]);
END;

PROCEDURE NLEnsureNetPage(PageNo: Integer);
BEGIN
  IF (PageNo >= 1) AND (PageNo <= NLMaxNetPages) AND
     (NLNetPages[PageNo] = NIL) THEN
    New(NLNetPages[PageNo]);
END;

FUNCTION NLGetNodePtr(Index: LongInt): PNLNodeRec;
VAR
  PageNo, Ofs: Integer;
BEGIN
  PageNo := (Index - 1) DIV NLNodesPerPage + 1;
  Ofs := (Index - 1) MOD NLNodesPerPage + 1;
  NLGetNodePtr := @NLNodePages[PageNo]^.Items[Ofs];
END;

FUNCTION NLGetNetPtr(Index: Integer): PNLNetRec;
VAR
  PageNo, Ofs: Integer;
BEGIN
  PageNo := (Index - 1) DIV NLNetsPerPage + 1;
  Ofs := (Index - 1) MOD NLNetsPerPage + 1;
  NLGetNetPtr := @NLNetPages[PageNo]^.Items[Ofs];
END;

FUNCTION NLFindNetOfNode(NodeIdx: LongInt): Integer;
VAR
  I: Integer;
  P: PNLNetRec;
BEGIN
  NLFindNetOfNode := 0;
  IF (NodeIdx < 1) OR (NodeIdx > NLNodeCount) THEN Exit;
  FOR I := 1 TO NLNetCount DO
  BEGIN
    P := NLGetNetPtr(I);
    IF (NodeIdx >= P^.NodeStart) AND (NodeIdx <= P^.NodeEnd) THEN
    BEGIN
      NLFindNetOfNode := I;
      Exit;
    END;
  END;
END;

FUNCTION NLFindNodeGlobal(Q: AStr): LongInt;
VAR
  J: LongInt;
  PN: PNLNodeRec;
  UQ: AStr;
  Want, Code: Integer;
BEGIN
  NLFindNodeGlobal := 0;
  UQ := NLUpperS(Q);
  Val(Q, Want, Code);
  FOR J := 1 TO NLNodeCount DO
  BEGIN
    PN := NLGetNodePtr(J);
    IF (Code = 0) AND (PN^.Number = Want) THEN
    BEGIN
      NLFindNodeGlobal := J;
      Exit;
    END;
    IF Pos(UQ, NLUpperS(PN^.Addr)) > 0 THEN
    BEGIN
      NLFindNodeGlobal := J;
      Exit;
    END;
    IF Pos(UQ, NLUpperS(PN^.BBS)) > 0 THEN
    BEGIN
      NLFindNodeGlobal := J;
      Exit;
    END;
    IF Pos(UQ, NLUpperS(PN^.Sysop)) > 0 THEN
    BEGIN
      NLFindNodeGlobal := J;
      Exit;
    END;
  END;
END;

FUNCTION NLNormSearch(S: STRING): STRING;
VAR
  I: Integer;
BEGIN
  S := NLU2Sp(NLUpperS(NLTrimS(S)));
  FOR I := 1 TO Length(S) DO
    IF S[I] = #9 THEN
      S[I] := ' ';
  NLNormSearch := S;
END;

FUNCTION NLMatchSearch(CONST Query, Addr, BBS, City, Sysop: STRING;
  NodeNum: Integer): Boolean;
VAR
  QN, AN, BN, CN, SN: STRING;
  Want, Code: Integer;
BEGIN
  QN := NLNormSearch(Query);
  AN := NLNormSearch(Addr);
  BN := NLNormSearch(BBS);
  CN := NLNormSearch(City);
  SN := NLNormSearch(Sysop);

  NLMatchSearch := FALSE;
  IF QN = '' THEN Exit;

  Val(Query, Want, Code);
  IF (Code = 0) AND (NodeNum = Want) THEN
  BEGIN
    NLMatchSearch := TRUE;
    Exit;
  END;

  IF Pos(QN, AN) > 0 THEN
  BEGIN
    NLMatchSearch := TRUE;
    Exit;
  END;
  IF Pos(QN, BN) > 0 THEN
  BEGIN
    NLMatchSearch := TRUE;
    Exit;
  END;
  IF Pos(QN, CN) > 0 THEN
  BEGIN
    NLMatchSearch := TRUE;
    Exit;
  END;
  IF Pos(QN, SN) > 0 THEN
  BEGIN
    NLMatchSearch := TRUE;
    Exit;
  END;
END;

FUNCTION NLSearchNodeInFile(FN, Query: STRING; VAR FoundZone, FoundNet,
  FoundNode: Integer; VAR FoundKind: Char): Boolean;
VAR
  F: Text;
  Line, S, Tok, BBS, City, Sysop, Phone, Baud, Status, Addr: STRING;
  Num, Code, CurZoneNum, CurNetNum, NodeNum: Integer;
BEGIN
  NLSearchNodeInFile := FALSE;
  FoundZone := 0;
  FoundNet := 0;
  FoundNode := 0;
  FoundKind := ' ';

  Assign(F, FN);
  {$I-} Reset(F); {$I+}
  IF IOResult <> 0 THEN Exit;

  CurZoneNum := 0;
  CurNetNum := 0;
  WHILE NOT EOF(F) DO
  BEGIN
    ReadLn(F, Line);
    Line := NLTrimS(Line);
    IF Line = '' THEN Continue;
    IF Line[1] = ';' THEN Continue;

    S := Line;
    Tok := NLUpperS(NLTrimS(NLNextToken(S)));

    IF Tok = 'ZONE' THEN
    BEGIN
      Val(NLTrimS(NLNextToken(S)), Num, Code);
      IF Code <> 0 THEN Continue;
      BBS := NLTrimS(NLNextToken(S));
      City := NLTrimS(NLNextToken(S));
      Sysop := NLTrimS(NLNextToken(S));
      Phone := NLTrimS(NLNextToken(S));
      Baud := NLTrimS(NLNextToken(S));
      CurZoneNum := Num;
      CurNetNum := Num;
      Addr := IntToStr(CurZoneNum) + ':' + IntToStr(CurNetNum) + '/0';
      IF NLMatchSearch(Query, Addr, BBS, City, Sysop, 0) THEN
      BEGIN
        FoundZone := CurZoneNum;
        FoundNet := CurNetNum;
        FoundNode := 0;
        FoundKind := 'Z';
        NLSearchNodeInFile := TRUE;
        Close(F);
        Exit;
      END;
    END
    ELSE IF Tok = 'REGION' THEN
    BEGIN
      Val(NLTrimS(NLNextToken(S)), Num, Code);
      IF Code <> 0 THEN Continue;
      BBS := NLTrimS(NLNextToken(S));
      City := NLTrimS(NLNextToken(S));
      Sysop := NLTrimS(NLNextToken(S));
      Phone := NLTrimS(NLNextToken(S));
      Baud := NLTrimS(NLNextToken(S));
      CurNetNum := Num;
      Addr := IntToStr(CurZoneNum) + ':' + IntToStr(CurNetNum) + '/0';
      IF NLMatchSearch(Query, Addr, BBS, City, Sysop, 0) THEN
      BEGIN
        FoundZone := CurZoneNum;
        FoundNet := CurNetNum;
        FoundNode := 0;
        FoundKind := 'R';
        NLSearchNodeInFile := TRUE;
        Close(F);
        Exit;
      END;
    END
    ELSE IF Tok = 'HOST' THEN
    BEGIN
      Val(NLTrimS(NLNextToken(S)), Num, Code);
      IF Code <> 0 THEN Continue;
      BBS := NLTrimS(NLNextToken(S));
      City := NLTrimS(NLNextToken(S));
      Sysop := NLTrimS(NLNextToken(S));
      Phone := NLTrimS(NLNextToken(S));
      Baud := NLTrimS(NLNextToken(S));
      CurNetNum := Num;
      Addr := IntToStr(CurZoneNum) + ':' + IntToStr(CurNetNum) + '/0';
      IF NLMatchSearch(Query, Addr, BBS, City, Sysop, 0) THEN
      BEGIN
        FoundZone := CurZoneNum;
        FoundNet := CurNetNum;
        FoundNode := 0;
        FoundKind := 'H';
        NLSearchNodeInFile := TRUE;
        Close(F);
        Exit;
      END;
    END
    ELSE
    BEGIN
      Status := '';
      Val(Tok, Num, Code);
      IF Code <> 0 THEN
      BEGIN
        Status := Tok;
        Val(NLTrimS(NLNextToken(S)), Num, Code);
        IF Code <> 0 THEN Continue;
      END;
      NodeNum := Num;
      BBS := NLTrimS(NLNextToken(S));
      City := NLTrimS(NLNextToken(S));
      Sysop := NLTrimS(NLNextToken(S));
      Phone := NLTrimS(NLNextToken(S));
      Baud := NLTrimS(NLNextToken(S));
      Addr := IntToStr(CurZoneNum) + ':' + IntToStr(CurNetNum) + '/' +
        IntToStr(NodeNum);
      IF NLMatchSearch(Query, Addr, BBS, City, Sysop, NodeNum) THEN
      BEGIN
        FoundZone := CurZoneNum;
        FoundNet := CurNetNum;
        FoundNode := NodeNum;
        FoundKind := 'N';
        NLSearchNodeInFile := TRUE;
        Close(F);
        Exit;
      END;
    END;
  END;

  Close(F);
END;

FUNCTION NLFindNetIndex(ZoneNum, NetNum: Integer): Integer;
VAR
  I: Integer;
  P: PNLNetRec;
BEGIN
  NLFindNetIndex := 0;
  FOR I := 1 TO NLNetCount DO
  BEGIN
    P := NLGetNetPtr(I);
    IF (P^.ZoneNum = ZoneNum) AND (P^.NetNum = NetNum) THEN
    BEGIN
      NLFindNetIndex := I;
      Exit;
    END;
  END;
END;

FUNCTION NLFindLoadedNodeByNumber(NodeNum: Integer): LongInt;
VAR
  J: LongInt;
  PN: PNLNodeRec;
BEGIN
  NLFindLoadedNodeByNumber := 0;
  FOR J := 1 TO NLNodeCount DO
  BEGIN
    PN := NLGetNodePtr(J);
    IF PN^.Number = NodeNum THEN
    BEGIN
      NLFindLoadedNodeByNumber := J;
      Exit;
    END;
  END;
END;

PROCEDURE NLParseNodeList(FN: STRING); FORWARD;
PROCEDURE NLBrowseNodes(NetIdx: Integer); FORWARD;

FUNCTION NLOpenGlobalSearchResult(FN, Query: STRING): Boolean;
VAR
  ZoneNum, NetNum, NodeNum: Integer;
  Kind: Char;
  NetIdx: Integer;
BEGIN
  NLOpenGlobalSearchResult := FALSE;
  IF NOT NLSearchNodeInFile(FN, Query, ZoneNum, NetNum, NodeNum, Kind) THEN
    Exit;

  NLDonePages;
  NLInitPages;
  NLSourceFile := FN;
  NLParseNodeList(NLSourceFile);
  NetIdx := NLFindNetIndex(ZoneNum, NetNum);
  IF NetIdx <= 0 THEN Exit;
  NLStartNodeIdx := NodeNum;
  NLBrowseNodes(NetIdx);
  NLOpenGlobalSearchResult := TRUE;
END;

FUNCTION NLOpenSearchAcrossCfg(Query: STRING): Boolean;
VAR
  I: Integer;
  FN: STRING;
BEGIN
  NLOpenSearchAcrossCfg := FALSE;
  FOR I := 1 TO NLCfgCount DO
  BEGIN
    FN := ResolveLatestNodeList2(NLCfgItems[I]^.Mask);
    IF FN = '' THEN Continue;
    IF NLOpenGlobalSearchResult(FN, Query) THEN
    BEGIN
      NLOpenSearchAcrossCfg := TRUE;
      Exit;
    END;
  END;
END;

PROCEDURE NLAddNode(Num: Integer; CONST St, ABBS, ACity, ASysop, APhone,
  ABaud: STRING; ZoneNum, NetNum: Integer);
VAR
  PageNo: Integer;
  P: PNLNodeRec;
BEGIN
  Inc(NLNodeCount);
  PageNo := (NLNodeCount - 1) DIV NLNodesPerPage + 1;
  IF PageNo > NLMaxNodePages THEN
  BEGIN
    Dec(NLNodeCount);
    Exit;
  END;
  NLEnsureNodePage(PageNo);
  P := NLGetNodePtr(NLNodeCount);
  P^.Number := Num;
  P^.Status := St;
  P^.BBS := NLU2Sp(NLTrimS(ABBS));
  P^.City := NLU2Sp(NLTrimS(ACity));
  P^.Sysop := NLU2Sp(NLTrimS(ASysop));
  P^.Phone := NLTrimS(APhone);
  P^.Baud := NLTrimS(ABaud);
  P^.Addr := IntToStr(ZoneNum) + ':' + IntToStr(NetNum) + '/' + IntToStr(Num);
END;

FUNCTION NLAddZone(ZoneNum: Integer; AName: STRING): Integer;
BEGIN
  IF NLZoneCount >= NLMaxZones THEN
  BEGIN
    NLAddZone := 0;
    Exit;
  END;
  Inc(NLZoneCount);
  New(NLZones[NLZoneCount]);
  NLZones[NLZoneCount]^.ZoneNum := ZoneNum;
  NLZones[NLZoneCount]^.Name := NLU2Sp(NLTrimS(AName));
  NLZones[NLZoneCount]^.NetStart := NLNetCount + 1;
  NLZones[NLZoneCount]^.NetEnd := NLNetCount;
  NLAddZone := NLZoneCount;
END;

FUNCTION NLAddNet(ZoneNum, NetNum: Integer; Kind: Char;
  AName: STRING): Integer;
VAR
  PageNo, Z: Integer;
  P: PNLNetRec;
BEGIN
  Inc(NLNetCount);
  PageNo := (NLNetCount - 1) DIV NLNetsPerPage + 1;
  IF PageNo > NLMaxNetPages THEN
  BEGIN
    Dec(NLNetCount);
    NLAddNet := 0;
    Exit;
  END;
  NLEnsureNetPage(PageNo);
  P := NLGetNetPtr(NLNetCount);
  P^.ZoneNum := ZoneNum;
  P^.NetNum := NetNum;
  P^.Kind := Kind;
  P^.Name := NLU2Sp(NLTrimS(AName));
  P^.NodeStart := NLNodeCount + 1;
  P^.NodeEnd := NLNodeCount;

  FOR Z := 1 TO NLZoneCount DO
    IF (NLZones[Z] <> NIL) AND (NLZones[Z]^.ZoneNum = ZoneNum) THEN
      NLZones[Z]^.NetEnd := NLNetCount;

  NLAddNet := NLNetCount;
END;

PROCEDURE NLParseNodeList(FN: STRING);
VAR
  F: Text;
  Line, S, Tok: STRING;
  Num, Code: Integer;
  ZIdx, NIdx: Integer;
  CurZoneNum, CurNetNum: Integer;
  BBS, City, Sysop, Phone, Baud: STRING;
BEGIN
  Assign(F, FN);
  {$I-} Reset(F); {$I+}
  IF IOResult <> 0 THEN Exit;

  NLResetData;
  CurZoneNum := 0;
  CurNetNum := 0;
  ZIdx := 0;
  NIdx := 0;

  WHILE NOT EOF(F) DO
  BEGIN
    ReadLn(F, Line);
    Line := NLTrimS(Line);
    IF Line = '' THEN Continue;
    IF Line[1] = ';' THEN Continue;

    S := Line;
    Tok := NLUpperS(NLTrimS(NLNextToken(S)));

    IF Tok = 'ZONE' THEN
    BEGIN
      Val(NLTrimS(NLNextToken(S)), Num, Code);
      IF Code <> 0 THEN Continue;
      BBS := NLTrimS(NLNextToken(S));
      City := NLTrimS(NLNextToken(S));
      Sysop := NLTrimS(NLNextToken(S));
      Phone := NLTrimS(NLNextToken(S));
      Baud := NLTrimS(NLNextToken(S));

      ZIdx := NLAddZone(Num, BBS);
      IF ZIdx = 0 THEN Break;
      CurZoneNum := Num;
      CurNetNum := Num;

      NIdx := NLAddNet(CurZoneNum, CurNetNum, 'Z', BBS);
      IF NIdx = 0 THEN Break;
    END
    ELSE IF Tok = 'REGION' THEN
    BEGIN
      Val(NLTrimS(NLNextToken(S)), Num, Code);
      IF Code <> 0 THEN Continue;
      BBS := NLTrimS(NLNextToken(S));
      City := NLTrimS(NLNextToken(S));
      Sysop := NLTrimS(NLNextToken(S));
      Phone := NLTrimS(NLNextToken(S));
      Baud := NLTrimS(NLNextToken(S));

      CurNetNum := Num;
      NIdx := NLAddNet(CurZoneNum, CurNetNum, 'R', BBS);
      IF NIdx = 0 THEN Break;
    END
    ELSE IF Tok = 'HOST' THEN
    BEGIN
      Val(NLTrimS(NLNextToken(S)), Num, Code);
      IF Code <> 0 THEN Continue;
      BBS := NLTrimS(NLNextToken(S));
      City := NLTrimS(NLNextToken(S));
      Sysop := NLTrimS(NLNextToken(S));
      Phone := NLTrimS(NLNextToken(S));
      Baud := NLTrimS(NLNextToken(S));

      CurNetNum := Num;
      NIdx := NLAddNet(CurZoneNum, CurNetNum, 'H', BBS);
      IF NIdx = 0 THEN Break;
    END;
  END;

  Close(F);
END;

PROCEDURE NLLoadNodesForNet(FN: STRING; ZoneNum, NetNum: Integer; Kind: Char);
VAR
  F: Text;
  Line, S, Tok: STRING;
  Num, Code: Integer;
  CurZoneNum, CurNetNum: Integer;
  BBS, City, Sysop, Phone, Baud, Status: STRING;
  Active: Boolean;
BEGIN
  Assign(F, FN);
  {$I-} Reset(F); {$I+}
  IF IOResult <> 0 THEN Exit;

  NLResetNodesOnly;
  CurZoneNum := 0;
  CurNetNum := 0;
  Active := FALSE;

  WHILE NOT EOF(F) DO
  BEGIN
    ReadLn(F, Line);
    Line := NLTrimS(Line);
    IF Line = '' THEN Continue;
    IF Line[1] = ';' THEN Continue;

    S := Line;
    Tok := NLUpperS(NLTrimS(NLNextToken(S)));

    IF Tok = 'ZONE' THEN
    BEGIN
      Val(NLTrimS(NLNextToken(S)), Num, Code);
      IF Code <> 0 THEN Continue;
      BBS := NLTrimS(NLNextToken(S));
      City := NLTrimS(NLNextToken(S));
      Sysop := NLTrimS(NLNextToken(S));
      Phone := NLTrimS(NLNextToken(S));
      Baud := NLTrimS(NLNextToken(S));

      IF Active THEN
      BEGIN
        IF Kind = 'Z' THEN
        BEGIN
          IF Num <> ZoneNum THEN Break;
        END
        ELSE
          Break;
      END;

      CurZoneNum := Num;
      CurNetNum := Num;
      IF (Kind = 'Z') AND (CurZoneNum = ZoneNum) THEN
      BEGIN
        Active := TRUE;
        NLAddNode(0, 'Zone', BBS, City, Sysop, Phone, Baud,
          CurZoneNum, CurNetNum);
      END
      ELSE
        Active := FALSE;
    END
    ELSE IF Tok = 'REGION' THEN
    BEGIN
      Val(NLTrimS(NLNextToken(S)), Num, Code);
      IF Code <> 0 THEN Continue;
      BBS := NLTrimS(NLNextToken(S));
      City := NLTrimS(NLNextToken(S));
      Sysop := NLTrimS(NLNextToken(S));
      Phone := NLTrimS(NLNextToken(S));
      Baud := NLTrimS(NLNextToken(S));

      IF Active AND (Kind <> 'Z') THEN Break;

      CurNetNum := Num;
      IF Kind = 'Z' THEN
      BEGIN
        IF Active THEN Break;
        CurNetNum := Num;
        Continue;
      END;

      IF (CurZoneNum = ZoneNum) AND (Kind = 'R') AND (CurNetNum = NetNum) THEN
      BEGIN
        Active := TRUE;
        NLAddNode(0, 'Region', BBS, City, Sysop, Phone, Baud,
          CurZoneNum, CurNetNum);
      END
      ELSE
        Active := FALSE;
    END
    ELSE IF Tok = 'HOST' THEN
    BEGIN
      Val(NLTrimS(NLNextToken(S)), Num, Code);
      IF Code <> 0 THEN Continue;
      BBS := NLTrimS(NLNextToken(S));
      City := NLTrimS(NLNextToken(S));
      Sysop := NLTrimS(NLNextToken(S));
      Phone := NLTrimS(NLNextToken(S));
      Baud := NLTrimS(NLNextToken(S));

      IF Active AND (Kind <> 'Z') THEN Break;

      CurNetNum := Num;
      IF Kind = 'Z' THEN
      BEGIN
        IF Active THEN Break;
        CurNetNum := Num;
        Continue;
      END;

      IF (CurZoneNum = ZoneNum) AND (Kind = 'H') AND (CurNetNum = NetNum) THEN
      BEGIN
        Active := TRUE;
        NLAddNode(0, 'Host', BBS, City, Sysop, Phone, Baud,
          CurZoneNum, CurNetNum);
      END
      ELSE
        Active := FALSE;
    END
    ELSE
    BEGIN
      IF NOT Active THEN Continue;

      Status := '';
      Val(Tok, Num, Code);
      IF Code <> 0 THEN
      BEGIN
        Status := Tok;
        Val(NLTrimS(NLNextToken(S)), Num, Code);
        IF Code <> 0 THEN Continue;
      END;
      BBS := NLTrimS(NLNextToken(S));
      City := NLTrimS(NLNextToken(S));
      Sysop := NLTrimS(NLNextToken(S));
      Phone := NLTrimS(NLNextToken(S));
      Baud := NLTrimS(NLNextToken(S));

      NLAddNode(Num, Status, BBS, City, Sysop, Phone, Baud,
        CurZoneNum, CurNetNum);
    END;
  END;

  Close(F);
END;

FUNCTION NLKindName(K: Char): STRING;
BEGIN
  CASE K OF
    'Z': NLKindName := 'Zone';
    'R': NLKindName := 'Region';
    'H': NLKindName := 'Host';
  ELSE
    NLKindName := 'Net';
  END;
END;

PROCEDURE NLPadRight(VAR SS: AStr; N: Byte);
BEGIN
  IF (N = 0) THEN
    Exit;
  IF (Length(SS) > N) THEN
    SS := Copy(SS,1,N)
  ELSE
    WHILE (Length(SS) < N) DO
      SS := SS + ' ';
END;

FUNCTION NLVisibleLen(S: AStr): Integer;
VAR
  I, L: Integer;
BEGIN
  I := 1;
  L := 0;
  WHILE (I <= Length(S)) DO
  BEGIN
    IF (S[I] = '|') AND (I + 2 <= Length(S)) THEN
      IF (S[I + 1] IN ['0'..'9']) AND (S[I + 2] IN ['0'..'9']) THEN
      BEGIN
        Inc(I, 3);
        Continue;
      END;
    Inc(L);
    Inc(I);
  END;
  NLVisibleLen := L;
END;

PROCEDURE NLHeader(Title, Help: AStr);
VAR
  S, Pad: AStr;
  X, I: Integer;
BEGIN
  CLS;
  S := '|14Renegade Nodelist Browser |07-- |15' + Title;
  X := (80 - NLVisibleLen(S)) DIV 2;
  IF (X < 0) THEN
    X := 0;
  Pad := '';
  FOR I := 1 TO X DO
    Pad := Pad + ' ';
  ANSIG(1, 1);
  PrintACR(Pad + S);
  ANSIG(1, 3);
  PrintACR('|04' + Help);
  ANSIG(1, 5);

  PrintACR('|01 ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ');
  Prompt(#27 + '[0m');
  Prompt(#27 + '[37;40m');
END;

PROCEDURE NLColorSeq(ColorKind: Char);
BEGIN
  CASE ColorKind OF
    'Z', 'C': Prompt(#27 + '[1;31;40m'); { red }
    'R':      Prompt(#27 + '[1;35;40m'); { purple }
    'N', 'H': Prompt(#27 + '[1;33;40m'); { yellow }
    'D':      Prompt(#27 + '[1;30;40m'); { dark gray }
  ELSE
    Prompt(#27 + '[37;40m');
  END;
END;

FUNCTION NLStatusColorKind(CONST S: STRING): Char;
VAR
  U: STRING;
BEGIN
  U := NLUpperS(S);
  IF U = 'ZONE' THEN
    NLStatusColorKind := 'Z'
  ELSE IF U = 'REGION' THEN
    NLStatusColorKind := 'R'
  ELSE IF U = 'HOST' THEN
    NLStatusColorKind := 'H'
  ELSE
    NLStatusColorKind := 'D';
END;

FUNCTION NLKindColorKind(K: Char): Char;
BEGIN
  CASE UpCase(K) OF
    'Z': NLKindColorKind := 'Z';
    'R': NLKindColorKind := 'R';
    'H': NLKindColorKind := 'H';
  ELSE
    NLKindColorKind := 'D';
  END;
END;

FUNCTION NLStatusPrefix(CONST S: STRING): STRING;
VAR
  U: STRING;
BEGIN
  U := NLUpperS(S);
  IF U = 'ZONE' THEN
    NLStatusPrefix := ' ' + #196 + #196 + ' '
  ELSE IF U = 'REGION' THEN
    NLStatusPrefix := '   ' + #195 + #196 + ' '
  ELSE IF U = 'HOST' THEN
    NLStatusPrefix := '     ' + #195 + #196 + ' '
  ELSE
    NLStatusPrefix := '       ' + #179 + ' ';
END;

FUNCTION NLKindPrefix(K: Char): STRING;
BEGIN
  CASE UpCase(K) OF
    'Z': NLKindPrefix := ' ' + #196 + #196 + ' ';
    'R': NLKindPrefix := '   ' + #195 + #196 + ' ';
    'H': NLKindPrefix := '     ' + #195 + #196 + ' ';
  ELSE
    NLKindPrefix := ' ';
  END;
END;

PROCEDURE NLPrintLine(Row: Integer; S: AStr; Selected: Boolean; ColorKind: Char);
BEGIN
  S := Copy(S,1,79);
  NLPadRight(S,79);

  ANSIG(1, Row);
  Prompt(#27 + '[0m');
  Prompt(#27 + '[37;40m');
  Prompt(#27 + '[0K');
  ANSIG(1, Row);

  IF Selected THEN
  BEGIN
    Prompt(#27 + '[1;37;44m');
    Prompt(S);
    Prompt(#27 + '[0m');
    Prompt(#27 + '[37;40m');
  END
  ELSE
  BEGIN
    NLColorSeq(ColorKind);
    Prompt(S);
    Prompt(#27 + '[0m');
    Prompt(#27 + '[37;40m');
  END;
END;


PROCEDURE NLDrawBox(LeftCol, TopRow, BoxWidth, BoxHeight: Integer);
VAR
  I: Integer;
BEGIN
  ANSIG(LeftCol, TopRow);
  Prompt(#27 + '[0m');
  Prompt(#27 + '[37;40m');
  Prompt(#27 + '[1;34;40m');
  Prompt(#218);
  FOR I := 1 TO BoxWidth - 2 DO
    Prompt(#196);
  Prompt(#191);
  FOR I := 1 TO BoxHeight - 2 DO
  BEGIN
    ANSIG(LeftCol, TopRow + I);
    Prompt(#179);
    ANSIG(LeftCol + BoxWidth - 1, TopRow + I);
    Prompt(#179);
  END;
  ANSIG(LeftCol, TopRow + BoxHeight - 1);
  Prompt(#192);
  FOR I := 1 TO BoxWidth - 2 DO
    Prompt(#196);
  Prompt(#217);
  Prompt(#27 + '[0m');
  Prompt(#27 + '[37;40m');
END;

PROCEDURE NLPrintBoxLine(LeftCol, Row, Width: Integer; S: AStr; Selected: Boolean;
  ColorKind: Char);
BEGIN
  S := Copy(S, 1, Width);
  NLPadRight(S, Width);
  ANSIG(LeftCol, Row);
  Prompt(#27 + '[0m');
  Prompt(#27 + '[37;40m');
  IF Selected THEN
  BEGIN
    Prompt(#27 + '[1;37;44m');
    Prompt(S);
    Prompt(#27 + '[0m');
    Prompt(#27 + '[37;40m');
  END
  ELSE
  BEGIN
    NLColorSeq(ColorKind);
    Prompt(S);
    Prompt(#27 + '[0m');
    Prompt(#27 + '[37;40m');
  END;
END;

PROCEDURE NLClearListArea;
VAR
  R: Integer;
BEGIN
  FOR R := 6 TO 6 + NLViewRows - 1 DO
  BEGIN
    ANSIG(1, R);
    Prompt(#27 + '[0m');
    Prompt(#27 + '[37;40m');
    Prompt(#27 + '[0K');
  END;
  Prompt(#27 + '[0m');
  Prompt(#27 + '[37;40m');
END;

FUNCTION NLPageCountRows(Top, Total: LongInt; Rows: Integer): Integer;
VAR
  Cnt: Integer;
BEGIN
  Cnt := Total - Top + 1;
  IF Cnt > Rows THEN
    Cnt := Rows;
  IF Cnt < 0 THEN
    Cnt := 0;
  NLPageCountRows := Cnt;
END;

FUNCTION NLPageCount(Top, Total: LongInt): Integer;
BEGIN
  NLPageCount := NLPageCountRows(Top, Total, NLViewRows);
END;

FUNCTION NLAbsToPagePos(AbsIdx, Top: LongInt): Integer;
BEGIN
  NLAbsToPagePos := AbsIdx - Top + 1;
END;

FUNCTION NLPagePosToAbs(PagePos: Integer; Top: LongInt): LongInt;
BEGIN
  NLPagePosToAbs := Top + PagePos - 1;
END;

PROCEDURE NLWaitKey;
VAR
  K: Word;
BEGIN
  REPEAT
    K := GetKey;
  UNTIL (K = 13) OR (K = 10) OR (K = 27) OR (K = F_LEFT) OR (K = F_RIGHT) OR (K = Ord('Q')) OR (K = Ord('q'));
END;

FUNCTION NLIsEnterKey(K: Word): Boolean;
BEGIN
  NLIsEnterKey := (K = 13) OR (K = 10);
END;

PROCEDURE NLMsgBox(S: AStr);
BEGIN
  CLS;
  ANSIG(1, 1);
  PrintACR('^5Renegade Nodelist Browser');
  ANSIG(1, 3);
  PrintACR('^7' + S);
  ANSIG(1, 5);
  {PrintACR('|09[â–  |15Press any key |09â– ]');}
  Prompt(#27 + '[0m');
  Prompt(#27 + '[37;40m');
  PauseScr(FALSE);
END;

FUNCTION NLInputField(PromptS: AStr; MaxLen: Byte): AStr;
VAR
  S: AStr;
  Changed: Boolean;
BEGIN
  S := '';
  PrintACR(PromptS);
  InputString('', S, MaxLen, [InteractiveEdit], Changed);
  NLInputField := S;
END;

FUNCTION NLLoadCfg(FN: STRING): Boolean;
VAR
  F: Text;
  NameLine, MaskLine: STRING;
BEGIN
  NLLoadCfg := FALSE;
  NLCfgCount := 0;
  Assign(F, FN);
  {$I-} Reset(F); {$I+}
  IF IOResult <> 0 THEN Exit;

  WHILE (NOT EOF(F)) AND (NLCfgCount < NLMaxCfgItems) DO
  BEGIN
    ReadLn(F, NameLine);
    NameLine := NLTrimS(NameLine);
    IF EOF(F) THEN Break;
    ReadLn(F, MaskLine);
    MaskLine := NLTrimS(MaskLine);

    IF (NameLine <> '') AND (MaskLine <> '') THEN
    BEGIN
      Inc(NLCfgCount);
      New(NLCfgItems[NLCfgCount]);
      NLCfgItems[NLCfgCount]^.Name := NameLine;
      NLCfgItems[NLCfgCount]^.Mask := MaskLine;
      NLCfgItems[NLCfgCount]^.Resolved := ResolveLatestNodeList2(MaskLine);
    END;
  END;
  Close(F);
  NLLoadCfg := NLCfgCount > 0;
END;


FUNCTION NLFindCfgItem(Q: AStr): Integer;
VAR
  J, Want, Code: Integer;
  UQ: AStr;
BEGIN
  NLFindCfgItem := 0;
  UQ := NLUpperS(Q);
  Val(Q, Want, Code);
  FOR J := 1 TO NLCfgCount DO
    IF ((Code = 0) AND (J = Want)) OR
       (Pos(UQ, NLUpperS(NLCfgItems[J]^.Name)) > 0) THEN
    BEGIN
      NLFindCfgItem := J;
      Exit;
    END;
END;

FUNCTION NLFindZoneItem(Q: AStr): Integer;
VAR
  J, Want, Code: Integer;
  UQ: AStr;
BEGIN
  NLFindZoneItem := 0;
  UQ := NLUpperS(Q);
  Val(Q, Want, Code);
  FOR J := 1 TO NLZoneCount DO
    IF ((Code = 0) AND (NLZones[J]^.ZoneNum = Want)) OR
       (Pos(UQ, NLUpperS(NLZones[J]^.Name)) > 0) THEN
    BEGIN
      NLFindZoneItem := J;
      Exit;
    END;
END;

FUNCTION NLFindNetItem(ZoneIdx: Integer; Q: AStr): Integer;
VAR
  J, Want, Code: Integer;
  UQ: AStr;
  NP: PNLNetRec;
BEGIN
  NLFindNetItem := 0;
  UQ := NLUpperS(Q);
  Val(Q, Want, Code);
  FOR J := NLZones[ZoneIdx]^.NetStart TO NLZones[ZoneIdx]^.NetEnd DO
  BEGIN
    NP := NLGetNetPtr(J);
    IF (((Code = 0) AND (NP^.NetNum = Want)) OR
        (Pos(UQ, NLUpperS(NP^.Name)) > 0) OR
        (Pos(UQ, NLUpperS(NLKindName(NP^.Kind))) > 0)) THEN
    BEGIN
      NLFindNetItem := J;
      Exit;
    END;
  END;
END;

FUNCTION NLChooseCfgFile: Boolean;
CONST
  NLCfgBoxLeft = 26;
  NLCfgBoxTop = 6;
  NLCfgBoxWidth = 30;
  NLCfgBoxHeight = 15;
  NLCfgBoxRows = 13;
VAR
  Cur, Top, OldCur, OldTop, I, PagePos, PageCnt: Integer;
  K: Word;
  Line: AStr;

  PROCEDURE DrawRowAbs(AbsIdx: Integer; Sel: Boolean);
  VAR
    RowPos: Integer;
    ClearLine: AStr;
  BEGIN
    IF (AbsIdx < Top) OR (AbsIdx > NLCfgCount) OR
       (NLAbsToPagePos(AbsIdx, Top) > NLCfgBoxRows) THEN
      Exit;

    RowPos := NLCfgBoxTop + NLAbsToPagePos(AbsIdx, Top);

    ClearLine := '';
    NLPadRight(ClearLine, NLCfgBoxWidth - 2);
    ANSIG(NLCfgBoxLeft + 1, RowPos);
    Prompt(#27 + '[0m');
    Prompt(#27 + '[37;40m');
    Prompt(ClearLine);

    ANSIG(NLCfgBoxLeft + 1, RowPos);
    IF Sel THEN
    BEGIN
      Line := ' ' + IntToStr(AbsIdx) + '. ' + NLCfgItems[AbsIdx]^.Name;
      NLPadRight(Line, NLCfgBoxWidth - 2);
      Prompt(#27 + '[1;37;44m');
      Prompt(Line);
    END
    ELSE
    BEGIN
      Prompt(' |08' + IntToStr(AbsIdx) + '. |10' + NLCfgItems[AbsIdx]^.Name);
    END;
    Prompt(#27 + '[0m');
    Prompt(#27 + '[37;40m');
  END;

  PROCEDURE DrawScreen;
  VAR
    DrawI: Integer;
  BEGIN
    NLHeader('Select Network',
      '  |08[|11Arrows|08] |07= Up/Down, ' +
      '|08[|11Enter|08] |07= Select, |08[|11S|08] |07= Search, ' +
      '|08[|11ESC|08] |07= Back, |08[|11Q|08] |07= Quit');
    NLClearListArea;
    NLDrawBox(NLCfgBoxLeft, NLCfgBoxTop, NLCfgBoxWidth, NLCfgBoxHeight);
    PageCnt := NLPageCountRows(Top, NLCfgCount, NLCfgBoxRows);
    IF PageCnt > NLCfgBoxRows THEN
      PageCnt := NLCfgBoxRows;
    FOR DrawI := 1 TO PageCnt DO
      DrawRowAbs(Top + DrawI - 1, DrawI = Cur);
  END;

PROCEDURE DoSearch;
VAR
  Query: AStr;
BEGIN
  CLS;
  PrintACR('%LF%LF|11Find Node');
  NL;
  PrintACR('|03Search by |11Node #|03, |11BBS Name|03, or |11SysOp Name');
  NL;
  Query := NLInputField('|03Search text    : |11', 40);
  IF Query = '' THEN
  BEGIN
    DrawScreen;
    Exit;
  END;
  IF NOT NLOpenSearchAcrossCfg(Query) THEN
    NLMsgBox('No matching node found.');
  DrawScreen;
END;

BEGIN
  NLChooseCfgFile := FALSE;
  IF NLCfgCount = 0 THEN Exit;

  Top := 1;
  Cur := 1;
  IF NLStartNodeIdx > 0 THEN
  BEGIN
    OldTop := NLFindLoadedNodeByNumber(NLStartNodeIdx);
    IF OldTop > 0 THEN
    BEGIN
      Top := ((OldTop - 1) DIV NLSubBoxRows) * NLSubBoxRows + 1;
      Cur := OldTop - Top + 1;
    END;
    NLStartNodeIdx := 0;
  END;
  DrawScreen;

  REPEAT
    K := GetKey;
    OldCur := Cur;
    OldTop := Top;
    PageCnt := NLPageCountRows(Top, NLCfgCount, NLCfgBoxRows);
    IF PageCnt > NLCfgBoxRows THEN
      PageCnt := NLCfgBoxRows;
    CASE K OF
      F_HOME: BEGIN Top := 1; Cur := 1; END;
      F_END:
        BEGIN
          IF NLCfgCount > NLCfgBoxRows THEN
            Top := NLCfgCount - NLCfgBoxRows + 1
          ELSE
            Top := 1;
          Cur := NLPageCount(Top, NLCfgCount);
          IF Cur > NLCfgBoxRows THEN
            Cur := NLCfgBoxRows;
        END;
      F_PGUP:
        BEGIN
          IF Top > 1 THEN
          BEGIN
            Top := Top - NLCfgBoxRows;
            IF Top < 1 THEN Top := 1;
            Cur := NLPageCountRows(Top, NLCfgCount, NLCfgBoxRows);
            IF Cur > NLCfgBoxRows THEN
              Cur := NLCfgBoxRows;
          END
          ELSE
            Cur := 1;
        END;
      F_PGDN:
        BEGIN
          IF Top + NLCfgBoxRows <= NLCfgCount THEN
          BEGIN
            Top := Top + NLCfgBoxRows;
            Cur := 1;
          END
          ELSE
          BEGIN
            IF NLCfgCount > NLCfgBoxRows THEN
              Top := NLCfgCount - NLCfgBoxRows + 1
            ELSE
              Top := 1;
            Cur := NLPageCountRows(Top, NLCfgCount, NLCfgBoxRows);
            IF Cur > NLCfgBoxRows THEN
              Cur := NLCfgBoxRows;
          END;
        END;
      F_UP:
        BEGIN
          IF Cur > 1 THEN
            Dec(Cur)
          ELSE IF Top > 1 THEN
          BEGIN
            Top := Top - NLCfgBoxRows;
            IF Top < 1 THEN Top := 1;
            Cur := NLPageCountRows(Top, NLCfgCount, NLCfgBoxRows);
            IF Cur > NLCfgBoxRows THEN
              Cur := NLCfgBoxRows;
          END;
        END;
      F_DOWN:
        BEGIN
          IF Cur < PageCnt THEN
            Inc(Cur)
          ELSE IF Top + NLCfgBoxRows <= NLCfgCount THEN
          BEGIN
            Top := Top + NLCfgBoxRows;
            Cur := 1;
          END;
        END;
      13, 10, F_RIGHT:
        BEGIN
          PagePos := NLPagePosToAbs(Cur, Top);
          NLSourceFile := ResolveLatestNodeList2(NLCfgItems[PagePos]^.Mask);
          IF NLSourceFile = '' THEN
          BEGIN
            NLMsgBox('Could not locate nodelist: ' + NLCfgItems[PagePos]^.Mask);
            DrawScreen;
          END
          ELSE
          BEGIN
            NLChooseCfgFile := TRUE;
            Exit;
          END;
        END;
      Ord('S'), Ord('s'), Ord('/'):
        BEGIN
          DoSearch;
        END;
      27, F_LEFT: Exit;
      Ord('Q'), Ord('q'):
        BEGIN
          NLQuit := TRUE;
          Exit;
        END;
    END;

    IF Top <> OldTop THEN
      DrawScreen
    ELSE IF Cur <> OldCur THEN
    BEGIN
      DrawRowAbs(NLPagePosToAbs(OldCur, Top), FALSE);
      DrawRowAbs(NLPagePosToAbs(Cur, Top), TRUE);
    END;
  UNTIL FALSE;
END;

PROCEDURE NLShowNode(P: PNLNodeRec);
VAR
  BoxX, BoxY, BoxW, BoxH: Integer;
BEGIN
  NLHeader('Node Details','                              |10Press |08[|15ENTER|08] |10to Return');

  BoxW := 50;
  BoxH := 17;
  BoxX := ((80 - BoxW) DIV 2) + 1;
  BoxY := 6;

  NLDrawBox(BoxX, BoxY, BoxW, BoxH);

  ANSIG(BoxX + 2, BoxY + 2);  PrintACR('|00^2Address ^1: |15' + P^.Addr);
  ANSIG(BoxX + 2, BoxY + 4);
  IF NLUpperS(P^.Status) = 'ZONE' THEN
    PrintACR('^2Status  ^1: |12Zone')
  ELSE IF NLUpperS(P^.Status) = 'REGION' THEN
    PrintACR('^2Status  ^1: |13Region')
  ELSE IF NLUpperS(P^.Status) = 'HOST' THEN
    PrintACR('^2Status  ^1: |14Host')
  ELSE
    PrintACR('^2Status  ^1: ^7' + P^.Status);
  ANSIG(BoxX + 2, BoxY + 6);  PrintACR('^2BBS     ^1: |15' + P^.BBS);
  ANSIG(BoxX + 2, BoxY + 8);  PrintACR('^2City    ^1: |15' + P^.City);
  ANSIG(BoxX + 2, BoxY + 10); PrintACR('^2SysOp   ^1: |15' + P^.Sysop);
  ANSIG(BoxX + 2, BoxY + 12); PrintACR('^2Phone   ^1: |15' + P^.Phone);
  ANSIG(BoxX + 2, BoxY + 14); PrintACR('^2Baud    ^1: |15' + P^.Baud);
  {ANSIG(BoxX + 2, BoxY + 15); PrintACR('|10Press Enter to return.');}

  Prompt(#27 + '[0m');
  Prompt(#27 + '[37;40m');
  NLWaitKey;
END;

PROCEDURE NLClampNodeView(VAR Cur, Top: LongInt; FirstIdx, LastIdx: LongInt);
BEGIN
  IF Cur < FirstIdx THEN Cur := FirstIdx;
  IF Cur > LastIdx THEN Cur := LastIdx;
  IF Top > Cur THEN Top := Cur;
  IF Cur > Top + NLViewRows - 1 THEN
    Top := Cur - NLViewRows + 1;
  IF Top < FirstIdx THEN Top := FirstIdx;
  IF Top > LastIdx THEN Top := LastIdx;
END;

PROCEDURE NLBrowseNodes(NetIdx: Integer);
VAR
  Cur, Top, OldCur, OldTop, I, PageCnt: LongInt;
  K: Word;
  P: PNLNodeRec;
  NP: PNLNetRec;
  Line, StatusStr: AStr;
  BoxLeft, BoxTop, BoxWidth, BoxHeight: Integer;
  SaveZoneNum, SaveNetNum: Integer;
  SaveKind: Char;

  PROCEDURE DrawRowAbs(AbsIdx: LongInt; Sel: Boolean);
  BEGIN
    IF (AbsIdx < Top) OR (AbsIdx > NLNodeCount) OR
       (NLAbsToPagePos(AbsIdx, Top) > NLSubBoxRows) THEN
      Exit;
    P := NLGetNodePtr(AbsIdx);
    StatusStr := P^.Status;
    IF StatusStr <> '' THEN
      StatusStr := ' [' + StatusStr + ']';
    Line := NLStatusPrefix(P^.Status) + P^.Addr + StatusStr + ' ' + P^.BBS;
    NLPrintBoxLine(BoxLeft + 1, BoxTop + NLAbsToPagePos(AbsIdx, Top),
      BoxWidth - 2, Line, Sel, NLStatusColorKind(P^.Status));
  END;

  PROCEDURE DrawScreen;
  VAR
    DrawI: LongInt;
  BEGIN
    NLHeader(NLKindName(NP^.Kind) + ' ' + IntToStr(NP^.NetNum) + ' - ' +
      NP^.Name,
      '  |08[|11Arrows|08] |07= Up/Down, ' +
      '|08[|11Enter|08] |07= Select, |08[|11S|08] |07= Search, ' +
      '|08[|11ESC|08] |07= Back, |08[|11Q|08] |07= Quit');
    NLClearListArea;
    NLDrawBox(BoxLeft, BoxTop, BoxWidth, BoxHeight);
    PageCnt := NLPageCountRows(Top, NLNodeCount, NLSubBoxRows);
    IF PageCnt > NLSubBoxRows THEN
      PageCnt := NLSubBoxRows;
    FOR DrawI := 1 TO PageCnt DO
      DrawRowAbs(Top + DrawI - 1, DrawI = Cur);
  END;


  FUNCTION NLFindNodeByNumber(Q: AStr): LongInt;
  VAR
    J, Code, Want: Integer;
    PN: PNLNodeRec;
  BEGIN
    NLFindNodeByNumber := 0;
    Val(Q, Want, Code);
    FOR J := 1 TO NLNodeCount DO
    BEGIN
      PN := NLGetNodePtr(J);
      IF (Code = 0) AND (PN^.Number = Want) THEN
      BEGIN
        NLFindNodeByNumber := J;
        Exit;
      END;
      IF Pos(NLUpperS(Q), NLUpperS(PN^.Addr)) > 0 THEN
      BEGIN
        NLFindNodeByNumber := J;
        Exit;
      END;
    END;
  END;

  FUNCTION NLFindNodeByBBS(Q: AStr): LongInt;
  VAR
    J: Integer;
    PN: PNLNodeRec;
    UQ: AStr;
  BEGIN
    NLFindNodeByBBS := 0;
    UQ := NLUpperS(Q);
    FOR J := 1 TO NLNodeCount DO
    BEGIN
      PN := NLGetNodePtr(J);
      IF Pos(UQ, NLUpperS(PN^.BBS)) > 0 THEN
      BEGIN
        NLFindNodeByBBS := J;
        Exit;
      END;
    END;
  END;

  FUNCTION NLFindNodeBySystem(Q: AStr): LongInt;
  VAR
    J: Integer;
    PN: PNLNodeRec;
    UQ: AStr;
  BEGIN
    NLFindNodeBySystem := 0;
    UQ := NLUpperS(Q);
    FOR J := 1 TO NLNodeCount DO
    BEGIN
      PN := NLGetNodePtr(J);
      IF (Pos(UQ, NLUpperS(PN^.Sysop)) > 0) OR
         (Pos(UQ, NLUpperS(PN^.BBS)) > 0) OR
         (Pos(UQ, NLUpperS(PN^.City)) > 0) THEN
      BEGIN
        NLFindNodeBySystem := J;
        Exit;
      END;
    END;
  END;

  PROCEDURE NLJumpToFound(Idx: LongInt);
  BEGIN
    IF (Idx < 1) OR (Idx > NLNodeCount) THEN Exit;
    Top := ((Idx - 1) DIV NLSubBoxRows) * NLSubBoxRows + 1;
    Cur := Idx - Top + 1;
  END;

  PROCEDURE DoSearch;
  VAR
    Query: AStr;
    PrevSource: STRING;
  BEGIN
    CLS;
    PrintACR('%LF%LF|11Find Node');
    NL;
    PrintACR('|03Search by |11Node #|03, |11BBS Name|03, or |11SysOp Name');
    NL;
    Query := NLInputField('|03Search text    : |11', 40);
    IF Query = '' THEN
    BEGIN
      DrawScreen;
      Exit;
    END;

    PrevSource := NLSourceFile;
    IF NOT NLOpenGlobalSearchResult(PrevSource, Query) THEN
      NLMsgBox('No matching node found.');
    IF NLQuit THEN Exit;

    NLSourceFile := PrevSource;
    NLDonePages;
    NLInitPages;
    NLParseNodeList(NLSourceFile);
    NetIdx := NLFindNetIndex(SaveZoneNum, SaveNetNum);
    IF NetIdx <= 0 THEN
    BEGIN
      NLMsgBox('Unable to restore previous node list.');
      Exit;
    END;
    NP := NLGetNetPtr(NetIdx);
    NLLoadNodesForNet(NLSourceFile, SaveZoneNum, SaveNetNum, SaveKind);
    IF NLNodeCount <= 0 THEN
    BEGIN
      NLMsgBox('No entries found for this item.');
      Exit;
    END;
    DrawScreen;
  END;

BEGIN
  BoxWidth := NLSubBoxWidth;
  BoxHeight := NLSubBoxHeight;
  BoxLeft := ((80 - BoxWidth) DIV 2) + 1;
  BoxTop := 7;

  NP := NLGetNetPtr(NetIdx);
  SaveZoneNum := NP^.ZoneNum;
  SaveNetNum := NP^.NetNum;
  SaveKind := NP^.Kind;
  NLLoadNodesForNet(NLSourceFile, SaveZoneNum, SaveNetNum, SaveKind);
  IF NLNodeCount <= 0 THEN
  BEGIN
    NLMsgBox('No entries found for this item.');
    Exit;
  END;

  Top := 1;
  Cur := 1;
  IF NLStartNodeIdx > 0 THEN
  BEGIN
    OldTop := NLFindLoadedNodeByNumber(NLStartNodeIdx);
    IF OldTop > 0 THEN
    BEGIN
      Top := ((OldTop - 1) DIV NLSubBoxRows) * NLSubBoxRows + 1;
      Cur := OldTop - Top + 1;
    END;
    NLStartNodeIdx := 0;
  END;
  DrawScreen;

  REPEAT
    K := GetKey;
    OldCur := Cur;
    OldTop := Top;
    PageCnt := NLPageCountRows(Top, NLNodeCount, NLSubBoxRows);
    CASE K OF
      F_HOME: BEGIN Top := 1; Cur := 1; END;
      F_END:
        BEGIN
          IF NLNodeCount > NLSubBoxRows THEN
            Top := NLNodeCount - NLSubBoxRows + 1
          ELSE
            Top := 1;
          Cur := NLPageCount(Top, NLNodeCount);
        END;
      F_PGUP:
        BEGIN
          IF Top > 1 THEN
          BEGIN
            Top := Top - NLSubBoxRows;
            IF Top < 1 THEN Top := 1;
            Cur := NLPageCountRows(Top, NLNodeCount, NLSubBoxRows);
          END
          ELSE
            Cur := 1;
        END;
      F_PGDN:
        BEGIN
          IF Top + NLSubBoxRows <= NLNodeCount THEN
          BEGIN
            Top := Top + NLSubBoxRows;
            Cur := 1;
          END
          ELSE
          BEGIN
            IF NLNodeCount > NLSubBoxRows THEN
              Top := NLNodeCount - NLSubBoxRows + 1
            ELSE
              Top := 1;
            Cur := NLPageCountRows(Top, NLNodeCount, NLSubBoxRows);
          END;
        END;
      F_UP:
        BEGIN
          IF Cur > 1 THEN
            Dec(Cur)
          ELSE IF Top > 1 THEN
          BEGIN
            Top := Top - NLSubBoxRows;
            IF Top < 1 THEN Top := 1;
            Cur := NLPageCountRows(Top, NLNodeCount, NLSubBoxRows);
          END;
        END;
      F_DOWN:
        BEGIN
          PageCnt := NLPageCountRows(Top, NLNodeCount, NLSubBoxRows);
          IF Cur < PageCnt THEN
            Inc(Cur)
          ELSE IF Top + NLSubBoxRows <= NLNodeCount THEN
          BEGIN
            Top := Top + NLSubBoxRows;
            Cur := 1;
          END;
        END;
      13, 10, F_RIGHT:
        BEGIN
          NLShowNode(NLGetNodePtr(NLPagePosToAbs(Cur, Top)));
          DrawScreen;
        END;
      Ord('S'), Ord('s'), Ord('/'):
        BEGIN
          DoSearch;
        END;
      27, F_LEFT: Exit;
      Ord('Q'), Ord('q'):
        BEGIN
          NLQuit := TRUE;
          Exit;
        END;
    END;

    IF Top <> OldTop THEN
      DrawScreen
    ELSE IF Cur <> OldCur THEN
    BEGIN
      DrawRowAbs(NLPagePosToAbs(OldCur, Top), FALSE);
      DrawRowAbs(NLPagePosToAbs(Cur, Top), TRUE);
    END;
  UNTIL FALSE;
END;

PROCEDURE NLBrowseNets(ZoneIdx: Integer);
VAR
  Cur, Top, OldCur, OldTop, I, Count, PageCnt: Integer;
  K: Word;
  NP: PNLNetRec;
  Line: AStr;
  BoxLeft, BoxTop, BoxWidth, BoxHeight: Integer;

  PROCEDURE DrawRowAbs(AbsIdx: Integer; Sel: Boolean);
  BEGIN
    IF (AbsIdx < Top) OR (AbsIdx > NLZones[ZoneIdx]^.NetEnd) OR
       (NLAbsToPagePos(AbsIdx, Top) > NLSubBoxRows) THEN
      Exit;
    NP := NLGetNetPtr(AbsIdx);
    Line := NLKindPrefix(NP^.Kind) + NLKindName(NP^.Kind) + ' #' +
      IntToStr(NP^.NetNum) + ': ' + NP^.Name;
    NLPrintBoxLine(BoxLeft + 1, BoxTop + NLAbsToPagePos(AbsIdx, Top),
      BoxWidth - 2, Line, Sel, NLKindColorKind(NP^.Kind));
  END;

  PROCEDURE DrawScreen;
  VAR
    DrawI: Integer;
  BEGIN
    NLHeader('Zone ' + IntToStr(NLZones[ZoneIdx]^.ZoneNum) + ' - ' +
      NLZones[ZoneIdx]^.Name,
      '  |08[|11Arrows|08] |07= Up/Down, ' +
      '|08[|11Enter|08] |07= Select, |08[|11S|08] |07= Search, ' +
      '|08[|11ESC|08] |07= Back, |08[|11Q|08] |07= Quit');
    NLClearListArea;
    NLDrawBox(BoxLeft, BoxTop, BoxWidth, BoxHeight);
    PageCnt := NLPageCountRows(Top, NLZones[ZoneIdx]^.NetEnd, NLSubBoxRows);
    IF PageCnt > NLSubBoxRows THEN
      PageCnt := NLSubBoxRows;
    FOR DrawI := 1 TO PageCnt DO
      DrawRowAbs(Top + DrawI - 1, DrawI = Cur);
  END;

PROCEDURE DoSearch;
VAR
  Query: AStr;
  PrevSource: STRING;
BEGIN
  CLS;
  PrintACR('%LF%LF|11Find Node');
  NL;
  PrintACR('|03Search by |11Node #|03, |11BBS Name|03, or |11SysOp Name');
  NL;
  Query := NLInputField('|03Search text    : |11', 40);
  IF Query = '' THEN
  BEGIN
    DrawScreen;
    Exit;
  END;
  PrevSource := NLSourceFile;
  IF NOT NLOpenGlobalSearchResult(PrevSource, Query) THEN
    NLMsgBox('No matching node found.');
  IF NLQuit THEN Exit;
  NLSourceFile := PrevSource;
  NLDonePages;
  NLInitPages;
  NLParseNodeList(NLSourceFile);
  DrawScreen;
END;

BEGIN
  IF NLZones[ZoneIdx] = NIL THEN Exit;
  IF NLZones[ZoneIdx]^.NetEnd < NLZones[ZoneIdx]^.NetStart THEN Exit;

  BoxWidth := NLSubBoxWidth;
  BoxHeight := NLSubBoxHeight;
  BoxLeft := ((80 - BoxWidth) DIV 2) + 1;
  BoxTop := 7;

  Top := NLZones[ZoneIdx]^.NetStart;
  Cur := 1;
  Count := NLZones[ZoneIdx]^.NetEnd - NLZones[ZoneIdx]^.NetStart + 1;
  DrawScreen;

  REPEAT
    K := GetKey;
    OldCur := Cur;
    OldTop := Top;
    PageCnt := NLPageCountRows(Top, NLZones[ZoneIdx]^.NetEnd, NLSubBoxRows);
    CASE K OF
      F_HOME: BEGIN Top := NLZones[ZoneIdx]^.NetStart; Cur := 1; END;
      F_END:
        BEGIN
          IF Count > NLSubBoxRows THEN
            Top := NLZones[ZoneIdx]^.NetEnd - NLSubBoxRows + 1
          ELSE
            Top := NLZones[ZoneIdx]^.NetStart;
          Cur := NLPageCountRows(Top, NLZones[ZoneIdx]^.NetEnd, NLSubBoxRows);
        END;
      F_PGUP:
        BEGIN
          IF Top > NLZones[ZoneIdx]^.NetStart THEN
          BEGIN
            Top := Top - NLSubBoxRows;
            IF Top < NLZones[ZoneIdx]^.NetStart THEN
              Top := NLZones[ZoneIdx]^.NetStart;
            Cur := NLPageCountRows(Top, NLZones[ZoneIdx]^.NetEnd, NLSubBoxRows);
          END
          ELSE
            Cur := 1;
        END;
      F_PGDN:
        BEGIN
          IF Top + NLSubBoxRows <= NLZones[ZoneIdx]^.NetEnd THEN
          BEGIN
            Top := Top + NLSubBoxRows;
            Cur := 1;
          END
          ELSE
          BEGIN
            IF Count > NLSubBoxRows THEN
              Top := NLZones[ZoneIdx]^.NetEnd - NLSubBoxRows + 1
            ELSE
              Top := NLZones[ZoneIdx]^.NetStart;
            Cur := NLPageCountRows(Top, NLZones[ZoneIdx]^.NetEnd, NLSubBoxRows);
          END;
        END;
      F_UP:
        BEGIN
          IF Cur > 1 THEN
            Dec(Cur)
          ELSE IF Top > NLZones[ZoneIdx]^.NetStart THEN
          BEGIN
            Top := Top - NLSubBoxRows;
            IF Top < NLZones[ZoneIdx]^.NetStart THEN
              Top := NLZones[ZoneIdx]^.NetStart;
            Cur := NLPageCountRows(Top, NLZones[ZoneIdx]^.NetEnd, NLSubBoxRows);
          END;
        END;
      F_DOWN:
        BEGIN
          PageCnt := NLPageCountRows(Top, NLZones[ZoneIdx]^.NetEnd, NLSubBoxRows);
          IF Cur < PageCnt THEN
            Inc(Cur)
          ELSE IF Top + NLSubBoxRows <= NLZones[ZoneIdx]^.NetEnd THEN
          BEGIN
            Top := Top + NLSubBoxRows;
            Cur := 1;
          END;
        END;
      13, 10, F_RIGHT:
        BEGIN
          NLBrowseNodes(NLPagePosToAbs(Cur, Top));
          IF NLQuit THEN Exit;
          DrawScreen;
        END;
      Ord('S'), Ord('s'), Ord('/'):
        BEGIN
          DoSearch;
        END;
      27, F_LEFT: Exit;
      Ord('Q'), Ord('q'):
        BEGIN
          NLQuit := TRUE;
          Exit;
        END;
    END;

    IF Top <> OldTop THEN
      DrawScreen
    ELSE IF Cur <> OldCur THEN
    BEGIN
      DrawRowAbs(NLPagePosToAbs(OldCur, Top), FALSE);
      DrawRowAbs(NLPagePosToAbs(Cur, Top), TRUE);
    END;
  UNTIL FALSE;
END;

PROCEDURE NLBrowseZones;
VAR
  Cur, Top, OldCur, OldTop, I, PageCnt: Integer;
  K: Word;
  Line: AStr;
  BoxLeft, BoxTop, BoxWidth, BoxHeight: Integer;

  PROCEDURE DrawRowAbs(AbsIdx: Integer; Sel: Boolean);
  BEGIN
    IF (AbsIdx < Top) OR (AbsIdx > NLZoneCount) OR
       (NLAbsToPagePos(AbsIdx, Top) > NLSubBoxRows) THEN
      Exit;
    Line := NLKindPrefix('Z') + 'Zone #' + IntToStr(NLZones[AbsIdx]^.ZoneNum) +
      ': ' + NLZones[AbsIdx]^.Name;
    NLPrintBoxLine(BoxLeft + 1, BoxTop + NLAbsToPagePos(AbsIdx, Top),
      BoxWidth - 2, Line, Sel, 'Z');
  END;

  PROCEDURE DrawScreen;
  VAR
    DrawI: Integer;
  BEGIN
    NLHeader(NLBaseNameOnly(NLSourceFile),
      '  |08[|11Arrows|08] |07= Up/Down, ' +
      '|08[|11Enter|08] |07= Select, |08[|11S|08] |07= Search, ' +
      '|08[|11ESC|08] |07= Back, |08[|11Q|08] |07= Quit');
    NLClearListArea;
    NLDrawBox(BoxLeft, BoxTop, BoxWidth, BoxHeight);
    PageCnt := NLPageCountRows(Top, NLZoneCount, NLSubBoxRows);
    IF PageCnt > NLSubBoxRows THEN
      PageCnt := NLSubBoxRows;
    FOR DrawI := 1 TO PageCnt DO
      DrawRowAbs(Top + DrawI - 1, DrawI = Cur);
  END;

PROCEDURE DoSearch;
VAR
  Query: AStr;
  PrevSource: STRING;
BEGIN
  CLS;
  PrintACR('%LF%LF|11Find Node');
  NL;
  PrintACR('|03Search by |11Node #|03, |11BBS Name|03, or |11SysOp Name');
  NL;
  Query := NLInputField('|03Search text    : |11', 40);
  IF Query = '' THEN
  BEGIN
    DrawScreen;
    Exit;
  END;
  PrevSource := NLSourceFile;
  IF NOT NLOpenGlobalSearchResult(PrevSource, Query) THEN
    NLMsgBox('No matching node found.');
  IF NLQuit THEN Exit;
  NLSourceFile := PrevSource;
  NLDonePages;
  NLInitPages;
  NLParseNodeList(NLSourceFile);
  DrawScreen;
END;

BEGIN
  IF NLZoneCount = 0 THEN Exit;

  BoxWidth := NLSubBoxWidth;
  BoxHeight := NLSubBoxHeight;
  BoxLeft := ((80 - BoxWidth) DIV 2) + 1;
  BoxTop := 7;

  Top := 1;
  Cur := 1;
  DrawScreen;

  REPEAT
    K := GetKey;
    OldCur := Cur;
    OldTop := Top;
    PageCnt := NLPageCountRows(Top, NLZoneCount, NLSubBoxRows);
    CASE K OF
      F_HOME: BEGIN Top := 1; Cur := 1; END;
      F_END:
        BEGIN
          IF NLZoneCount > NLSubBoxRows THEN
            Top := NLZoneCount - NLSubBoxRows + 1
          ELSE
            Top := 1;
          Cur := NLPageCountRows(Top, NLZoneCount, NLSubBoxRows);
        END;
      F_PGUP:
        BEGIN
          IF Top > 1 THEN
          BEGIN
            Top := Top - NLSubBoxRows;
            IF Top < 1 THEN Top := 1;
            Cur := NLPageCountRows(Top, NLZoneCount, NLSubBoxRows);
          END
          ELSE
            Cur := 1;
        END;
      F_PGDN:
        BEGIN
          IF Top + NLSubBoxRows <= NLZoneCount THEN
          BEGIN
            Top := Top + NLSubBoxRows;
            Cur := 1;
          END
          ELSE
          BEGIN
            IF NLZoneCount > NLSubBoxRows THEN
              Top := NLZoneCount - NLSubBoxRows + 1
            ELSE
              Top := 1;
            Cur := NLPageCountRows(Top, NLZoneCount, NLSubBoxRows);
          END;
        END;
      F_UP:
        BEGIN
          IF Cur > 1 THEN
            Dec(Cur)
          ELSE IF Top > 1 THEN
          BEGIN
            Top := Top - NLSubBoxRows;
            IF Top < 1 THEN Top := 1;
            Cur := NLPageCountRows(Top, NLZoneCount, NLSubBoxRows);
          END;
        END;
      F_DOWN:
        BEGIN
          PageCnt := NLPageCountRows(Top, NLZoneCount, NLSubBoxRows);
          IF Cur < PageCnt THEN
            Inc(Cur)
          ELSE IF Top + NLSubBoxRows <= NLZoneCount THEN
          BEGIN
            Top := Top + NLSubBoxRows;
            Cur := 1;
          END;
        END;
      13, 10, F_RIGHT:
        BEGIN
          NLBrowseNets(NLPagePosToAbs(Cur, Top));
          IF NLQuit THEN Exit;
          DrawScreen;
        END;
      Ord('S'), Ord('s'), Ord('/'):
        BEGIN
          DoSearch;
        END;
      27, F_LEFT: Exit;
      Ord('Q'), Ord('q'):
        BEGIN
          NLQuit := TRUE;
          Exit;
        END;
    END;

    IF Top <> OldTop THEN
      DrawScreen
    ELSE IF Cur <> OldCur THEN
    BEGIN
      DrawRowAbs(NLPagePosToAbs(OldCur, Top), FALSE);
      DrawRowAbs(NLPagePosToAbs(Cur, Top), TRUE);
    END;
  UNTIL FALSE;
END;

PROCEDURE BrowseNodeLists;
VAR
  DatFile: AStr;
BEGIN
  NLQuit := FALSE;
  NLStartNodeIdx := 0;
  NLInitPages;
  DatFile := General.DataPath + 'NODELIST.DAT';
  IF NOT NLLoadCfg(DatFile) THEN
  BEGIN
    CLS;
    PrintACR('%LF%LFNODELIST.DAT not found or empty: ' + DatFile);
    NL;
    PauseScr(FALSE);
    Exit;
  END;

  REPEAT
    IF NOT NLChooseCfgFile THEN Break;
    IF NLQuit THEN Break;

    NLDonePages;
    NLParseNodeList(NLSourceFile);

    IF NLZoneCount = 0 THEN
    BEGIN
      CLS;
      PrintACR('%LF%LFCould not parse nodelist: ' + NLSourceFile);
      NL;
      PauseScr(FALSE);
    END
    ELSE
      NLBrowseZones;
    IF NLQuit THEN Break;
  UNTIL FALSE;
  NLDonePages;
  NLDoneCfg;
END;


END.
