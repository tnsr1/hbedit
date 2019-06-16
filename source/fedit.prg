
/*
 * Text editor
 *
 * Copyright 2019 Alexander S.Kresin <alex@kresin.ru>
 * www - http://www.kresin.ru
 */

#include "hbclass.ch"
#include "inkey.ch"
#include "setcurs.ch"
#include "hbgtinfo.ch"
#ifdef _FULL
#include "hbfuncsfull.ch"
#else
#include "hbfuncs.ch"
#endif

#define SHIFT_PRESSED 0x010000
#define CTRL_PRESSED  0x020000
#define ALT_PRESSED   0x040000
#define MAX_CBOARDS         10

#define UNDO_LINE1      1
#define UNDO_POS1       2
#define UNDO_LINE2      3
#define UNDO_POS2       4
#define UNDO_OPER       5
#define UNDO_TEXT       6

#define UNDO_OP_INS     1
#define UNDO_OP_OVER    2
#define UNDO_OP_DEL     3
#define UNDO_OP_SHIFT   4
#define UNDO_OP_START   5
#define UNDO_OP_END     6

#define UNDO_INC       12

STATIC aMenuMain := { {"Exit",@mnu_Exit(),Nil,"Esc,F10"}, {"Save",@mnu_Save(),Nil,"F2"}, ;
   {"Save as",@mnu_Save(),.T.,"Shift-F2"}, ;
   {"Mark block",@mnu_F3(),Nil,"F3"}, {"Open file",@mnu_F4(),{7,16},"F4 >"}, ;
   {"Search&GoTo",@mnu_Sea_Goto(),{8,16},">"}, {"Change mode",@mnu_ChgMode(),Nil,"Ctrl-Q"}, ;
   {"Codepage",@mnu_CPages(),{11,16},">"}, {"Syntax",@mnu_Syntax(),{12,16},"F8 >"}, ;
   {"Plugins",@mnu_Plugins(),Nil,"F11 >"}, {"Windows",@mnu_Windows(),{13,16}}, ;
   {"Buffers",@mnu_Buffers(),{14,16},"F12 >"} }

STATIC aKeysMove := { K_UP, K_DOWN, K_LEFT, K_RIGHT, K_PGDN, K_PGUP, K_HOME, K_END, K_CTRL_PGUP, K_CTRL_PGDN }
STATIC cKeysMove := "hjklwWeEbBG0$^"
STATIC hKeyMap

STATIC aLangExten := {}
STATIC cLangMapCP, aLangMapUpper, aLangMapLower
STATIC aMenu_CB
STATIC aLangs
STATIC lCase_Sea := .F., lWord_Sea := .F., lRegex_Sea := .F.
STATIC cDopMode := ""
STATIC cLastDir := ""
STATIC aMacro
STATIC cTab := e"\x9", cTabStr
STATIC nLastMacro

CLASS TEdit

   CLASS VAR aCPages    SHARED  INIT {}
   CLASS VAR aWindows   SHARED                   // An array with all TEdit objects
   CLASS VAR nCurr      SHARED                   // A currently processed TEdit object number
   CLASS VAR cpInit     SHARED
   CLASS VAR cLauncher  SHARED  INIT ""
   CLASS VAR lReadIni   SHARED  INIT .F.         // If ini file have been read already
   CLASS VAR options    SHARED  INIT { => }
   CLASS VAR aCmdHis    SHARED  INIT {}
   CLASS VAR aSeaHis    SHARED  INIT {}
   CLASS VAR aReplHis   SHARED  INIT {}
   CLASS VAR aEditHis   SHARED  INIT {}
   CLASS VAR aCBoards   SHARED                   // An array for clipboard buffers
   CLASS VAR aHiliAttrs SHARED  INIT { "W+/B", "W+/B", "W+/B", "W+/B", "GR+/B", "W/B", "W/B", "W/B", "W/B" }
   CLASS VAR aPlugins   SHARED  INIT {}
   CLASS VAR nDefMode   SHARED  INIT 0           // A start mode ( -1 - Edit only, 0 - Edit, 1- Vim )
   CLASS VAR cColor     SHARED  INIT "BG+/B"
   CLASS VAR cColorSel  SHARED  INIT "N/W"
   CLASS VAR cColorPane SHARED  INIT "N/BG"
   CLASS VAR cColorBra  SHARED  INIT "R+/B"
   CLASS VAR nTabLen    SHARED  INIT 4
   CLASS VAR aRectFull  SHARED
   CLASS VAR bNew       SHARED
   CLASS VAR hMacros    SHARED

   DATA   aRect       INIT { 0,0,24,79 }
   DATA   y1, x1, y2, x2
   DATA   cFileName   INIT ""
   DATA   dDateMod, cTimeMod
   DATA   cp
   DATA   nxFirst, nyFirst
   DATA   aText
   DATA   nMode                       // Current mode (Edit, Vim, Cmd)
   DATA   nDopMode    INIT 0          // A state in a Vim mode after pressing some keys
                                      // (m, ', 0..9, ...) when other keys are expected
   DATA   cSyntaxType

   DATA   oParent                     // A TEdit object of a parent edit window
   DATA   aUndo       INIT {}
   DATA   nUndo       INIT 0

   DATA   lTopPane    INIT .T.
   DATA   nTopName    INIT 36

   DATA   lCtrlTab    INIT .T.
   DATA   lReadOnly   INIT .F.
   DATA   lUtf8       INIT .F.
   DATA   lUpdated    INIT .F.
   DATA   lIns        INIT .T.
   DATA   lShiftKey   INIT .F.

   DATA   lTabs       INIT .F.

   DATA   nPos, nLine
   DATA   nPosBack, nLineBack
   DATA   lF3         INIT .F.
   DATA   nSeleMode   INIT  0
   DATA   nby1        INIT -1
   DATA   nby2        INIT -1
   DATA   nbx1, nbx2
   DATA   lTextOut    INIT .F.

   DATA   lShow
   DATA   lClose      INIT .F.
   DATA   cEol
   DATA   lBom        INIT .F.

   DATA   funSave
   DATA   bStartEdit, bEndEdit
   DATA   bOnKey, bWriteTopPane
   DATA   oHili
   DATA   hBookMarks
   DATA   npy1, npx1, npy2, npx2
   DATA   cargo

   METHOD New( cText, cFileName, y1, x1, y2, x2, cColor, lTopPane )
   METHOD SetText( cText, cFileName )
   METHOD Edit()
   METHOD TextOut( n1, n2 )
   METHOD LineOut( nLine )
   METHOD onKey( nKeyExt )
   METHOD WriteTopPane( lClear )
   METHOD RowToLine( nRow )   INLINE ( nRow - ::y1 + ::nyFirst )
   METHOD ColToPos( nRow, nCol )
   METHOD LineToRow( nLine )  INLINE ( Iif( nLine==Nil, ::nLine, nLine ) + ::y1 - ::nyFirst )
   METHOD PosToCol( nLine, nPos )
   METHOD Search( cSea, lCase, lNext, lWord, lRegex, ny, nx, lInc )
   METHOD GoTo( ny, nx, nSele, lNoGo )
   METHOD ToString( cEol, cp )
   METHOD Save( cFileName )
   METHOD InsText( nLine, nPos, cText, lOver, lChgPos, lNoUndo )
   METHOD DelText( nLine1, nPos1, nLine2, nPos2, lNoUndo )
   METHOD Undo( nLine1, nPos1, nLine2, nPos2, nOper, cText )
   METHOD Highlighter( oHili )
   METHOD OnExit()

ENDCLASS

METHOD New( cText, cFileName, y1, x1, y2, x2, cColor, lTopPane ) CLASS TEdit

   LOCAL i, cExt, dDateMod, cTimeMod

   IF !::lReadIni
      edi_ReadIni( edi_FindPath( "hbedit.ini" ) )
   ENDIF
   IF Empty( ::aRectFull )
      ::aRectFull := { 0, 0, MaxRow(), MaxCol() }
      IF y1 != Nil; ::aRectFull[1] := y1; ENDIF
      IF x1 != Nil; ::aRectFull[2] := x1; ENDIF
      IF y2 != Nil; ::aRectFull[3] := y2; ENDIF
      IF x2 != Nil; ::aRectFull[4] := x2; ENDIF
   ENDIF
   ::y1 := ::aRect[1] := Iif( y1==Nil, ::aRectFull[1], y1 )
   ::x1 := ::aRect[2] := Iif( x1==Nil, ::aRectFull[2], x1 )
   ::y2 := ::aRect[3] := Iif( y2==Nil, ::aRectFull[3], y2 )
   ::x2 := ::aRect[4] := Iif( x2==Nil, ::aRectFull[4], x2 )
   ::cColor := Iif( Empty(cColor), ::cColor, cColor )
   ::nxFirst := ::nyFirst := 1
   ::npy1 := ::npx1 := ::npy2 := ::npx2 := 0
   IF Valtype( lTopPane ) == "L" .AND. !lTopPane
      ::lTopPane := .F.
   ENDIF

   IF ::lTopPane
      ::nTopName := Max( ::x2 - ::x1 - Iif(::x2-::x1>54,44,37), 0 )
      ::y1 ++
   ENDIF
   ::nLine := ::nPos := 1

   ::nMode := Iif( ::nDefMode<0, 0, ::nDefMode )
   ::cp := ::cpInit

   ::SetText( cText, cFileName )
   IF !Empty( ::cFileName ) .AND. Left( ::cFileName,1 ) != "$" .AND. ;
      hb_fGetDateTime( ::cFileName, @dDateMod, @cTimeMod )
      ::dDateMod := dDateMod
      ::cTimeMod := cTimeMod
   ENDIF

   ::hBookMarks := hb_Hash()

   IF ::aWindows == Nil
      ::aWindows := {}
   ENDIF
   Aadd( ::aWindows, Self )

   IF !Empty( ::bNew )
      Eval( ::bNew, Self )
   ENDIF

   RETURN Self

METHOD SetText( cText, cFileName ) CLASS TEdit

   LOCAL i, arr, xPlugin, cFile_utf8, cExt, cFullPath, cBom := e"\xef\xbb\xbf"
   LOCAL nEol := hb_hGetDef( TEdit():options,"eol", 0 )
   LOCAL lT2Sp := hb_hGetDef( TEdit():options,"tabtospaces", .F. )

   IF !Empty( cFileName )
      IF Left( cFileName,1 ) == "$"
         ::cFileName := cFileName
      ELSE
         IF Empty( hb_fnameDir( cFileName ) )
#ifdef __PLATFORM__UNIX
            cFileName := '/' + Curdir() + '/' + cFileName
#else
            cFileName := hb_curDrive() + ":\" + Curdir() + '\' + cFileName
#endif
         ENDIF
         ::cFileName := cFileName
         cFile_utf8 := hb_Translate( cFileName,, "UTF8" )
         IF ( i := Ascan( TEdit():aEditHis, {|a|a[1]==cFile_utf8} ) ) > 0
            arr := TEdit():aEditHis[i]
            ADel( TEdit():aEditHis, i )
            hb_AIns( TEdit():aEditHis, 1, arr, .F. )
            hb_cdpSelect( ::cp := arr[2] )
            ::nLine := arr[3]
            ::nPos  := arr[4]
         ELSE
            hb_AIns( TEdit():aEditHis, 1, {cFile_utf8,::cp,1,1}, Len(TEdit():aEditHis)<hb_hGetDef(TEdit():options,"edithismax",10) )
         ENDIF
      ENDIF
   ENDIF

   ::lUtf8 := ( Lower(::cp) == "utf8" )
   IF Empty( cText )
      ::aText := { "" }
      ::cEol := Iif( nEol == 1, Chr(10), Chr(13) + Chr(10) )
   ELSE
      ::aText := hb_ATokens( cText, Chr(10) )
      IF nEol == 0
         ::cEol := Iif( Right( ::aText[1],1 ) == Chr(13), Chr(13) + Chr(10), Chr(10) )
      ELSE
         ::cEol := Iif( nEol == 1, Chr(10), Chr(13) + Chr(10) )
      ENDIF
      IF Left( ::aText[1], 3 ) == cBom
         hb_cdpSelect( ::cp := "UTF8" )
         ::lUtf8 := .T.
         ::aText[1] := Substr( ::aText[1], 4 )
         ::lBom := .T.
      ENDIF
      FOR i := 1 TO Len( ::aText )
         IF lT2Sp .AND. cTab $ ::aText[i]
            ::aText[i] := Strtran( ::aText[i], cTab, cTabStr )
            ::lTabs := .T.
         ENDIF
         IF Right( ::aText[i],1 ) == Chr(13)
            ::aText[i] := Left( ::aText[i], Len( ::aText[i])-1 )
         ELSEIF Left( ::aText[i],1 ) == Chr(13)
            ::aText[i] := Substr( ::aText[i], 2 )
         ENDIF
      NEXT
   ENDIF

   ::aUndo := {}
   ::nUndo := 0

   IF hb_hGetDef( TEdit():options, "syntax", .F. ) .AND. !Empty( cFileName )
      cExt := Lower( hb_fnameExt(cFileName) )
      FOR i := 1 TO Len(aLangExten)
         IF cExt $ aLangExten[i,2] .AND. hb_hHaskey(aLangs,aLangExten[i,1])
            mnu_SyntaxOn( Self, aLangExten[i,1] )
            IF !Empty( xPlugin := hb_hGetDef( ::oHili:hHili, "plugin", Nil ) )
               IF Valtype( xPlugin ) == "C" .AND. ;
                  !Empty( cFullPath := edi_FindPath( "plugins" + hb_ps() + xPlugin ) )
                  xPlugin := ::oHili:hHili["plugin"] := hb_hrbLoad( cFullPath )
                  IF Empty( xPlugin )
                     EXIT
                  ENDIF
               ENDIF
               hb_hrbDo( xPlugin, Self )
            ENDIF
            EXIT
         ENDIF
      NEXT
   ENDIF

   RETURN Nil

METHOD Edit() CLASS TEdit

   LOCAL i, nKeyExt, cFile_utf8, n

   hb_cdpSelect( ::cp )
   ::nCurr := Ascan( ::aWindows, {|o|o==Self} )

   SetCursor( SC_NONE )
   SetColor( ::cColor )
   Scroll( ::y1, ::x1, ::y2, ::x2 )

   IF ::nLine < 1 .OR. ::nLine > Len( ::aText )
      ::nyFirst := ::nxFirst := ::nLine := ::nPos := 1
   ENDIF

   ::WriteTopPane()

   IF !Empty( ::bStartEdit )
      Eval( ::bStartEdit, Self )
   ENDIF

   FOR i := Len( ::aWindows ) TO 1 STEP -1
      // Draw the child window, if found.
      IF !Empty( ::aWindows[i]:oParent ) .AND. ::aWindows[i]:oParent == Self
         ::aWindows[i]:WriteTopPane( .T. )
         ::aWindows[i]:TextOut()
      ENDIF
   NEXT

   ::GoTo( ::nLine, ::nPos )
   ::TextOut()

   ::nPosBack := ::nPos
   ::nLineBack := ::nLine
   ::lShow := .T.
   DO WHILE ::lShow
      SetCursor( Iif( ::lIns, SC_NORMAL, SC_SPECIAL1 ) )
      nKeyExt := Inkey( 0, HB_INKEY_ALL + HB_INKEY_EXT )
      IF !Empty( hKeyMap ) .AND. ( i := hb_hGetDef( hKeyMap, nKeyExt, 0 ) ) != 0
         nKeyExt := i
      ENDIF
      SetCursor( SC_NONE )
      ::onKey( nKeyExt )
   ENDDO

   hb_cdpSelect( ::cpInit )
   IF !Empty( ::cFileName )
      cFile_utf8 := hb_Translate( ::cFileName,, "UTF8" )
      IF ( i := Ascan( TEdit():aEditHis, {|a|a[1]==cFile_utf8} ) ) > 0
         TEdit():aEditHis[i,2] := ::cp
         TEdit():aEditHis[i,3] := ::nLine
         TEdit():aEditHis[i,4] := ::nPos
      ENDIF
   ENDIF

   ::WriteTopPane( .T. )
   IF !Empty( ::bEndEdit )
      Eval( ::bEndEdit, Self )
   ENDIF
   IF ::lClose
      IF Ascan( ::aWindows, {|o|o:oParent==Self} ) == 0
         edi_CloseWindow( Self )
      ELSEIF edi_Alert( "There are child windows.;Close anyway?", "Yes", "No" ) == 1
         IF ( n := edi_WindowUpdated( Self ) ) > 0
            IF ( i := edi_Alert( "Some files are updated.", "Cancel", "GoTo", "Close anyway" ) ) <= 1
               ::lClose := .F.
               RETURN Nil
            ELSEIF i == 2
               ::nCurr := i
               RETURN Nil
            ENDIF
         ENDIF
         edi_CloseWindow( Self )
      ELSE
         ::lClose := .F.
      ENDIF
   ENDIF

   RETURN Nil

METHOD TextOut( n1, n2 ) CLASS TEdit

   LOCAL i, nCol := Col(), nRow := Row()

   IF n1 == Nil; n1 := 1; ENDIF
   IF n2 == Nil; n2 := ::y2 -::y1 + 1; ENDIF

   FOR i := n1 TO n2
      ::LineOut( i )
   NEXT
   DevPos( nRow, nCol )

   RETURN Nil

METHOD LineOut( nLine, lInTextOut ) CLASS TEdit

   LOCAL n := nLine + ::nyFirst - 1, y := ::y1 + nLine - 1, nWidth := ::x2 - ::x1 + 1, s, nLen
   LOCAL lSel := .F., nby1, nby2, nbx1, nbx2, nx1, nx2, lTabs := .F., nf := ::nxFirst, nf1
   LOCAL aStru, i, aClrs
   LOCAL nxPosFirst := 1, nxPosLast := nf + nWidth

   IF n <= Len( ::aText )

      IF ::nby1 >= 0 .AND. ::nby2 >= 0
         IF ::nby1 < ::nby2 .OR. ( ::nby1 == ::nby2 .AND. ::nbx1 < ::nbx2 )
            nby1 := ::nby1; nbx1 := ::nbx1; nby2 := ::nby2; nbx2 := ::nbx2
         ELSE
            nby1 := ::nby2; nbx1 := ::nbx2; nby2 := ::nby1; nbx2 := ::nbx1
         ENDIF
         IF ::nSeleMode == 2
            IF n != nby1
               nbx1 := ::ColToPos( ::LineToRow(n), ::PosToCol( nby1,nbx1 ) )
            ENDIF
            IF n != nby2
               nbx2 := ::ColToPos( ::LineToRow(n), ::PosToCol( nby2,nbx2 ) )
            ENDIF
            IF nbx1 > nbx2
               i := nbx1; nbx1 := nbx2; nbx2 := i
            ENDIF
         ENDIF
         lSel := ( n >= nby1 .AND. n <= nby2 ) .AND. !( nby1 == nby2 .AND. nbx1 == nbx2 )
      ENDIF

      DevPos( y, ::x1 )
      IF nf == 1 .AND. !::lUtf8 .AND. ( nLen := Len(::aText[n]) ) < nWidth
         s := ::aText[n]
      ELSE
         nxPosFirst := edi_Col2Pos( Self, n, nf )
         s := cp_Substr( ::lUtf8, ::aText[n], nxPosFirst, nWidth )
         nLen := cp_Len( ::lUtf8, s )
      ENDIF
      DispBegin()
      IF nLen > 0
         i := 1
         IF ::nxFirst > 1 .AND. nxPosFirst < ::nxFirst
            nf := edi_ExpandTabs( Self, cp_Left(::lUtf8,::aText[n],nxPosFirst), 1, .T. )
            lTabs := .T.
            DevPos( y, i := (::x1 + nf - ::nxFirst) )
         ENDIF
         IF cTab $ s
            lTabs := .T.
            DevOut( cp_Left( ::lUtf8, edi_ExpandTabs( Self, s, nf ), nWidth-i+1 ) )
         ELSE
            DevOut( s )
         ENDIF
         IF lTabs
            nxPosLast := edi_Col2Pos( Self, n, nf + nWidth )
         ENDIF
         nLen := Col() - ::x1

         IF !Empty( ::oHili ) .AND. hb_hGetDef( TEdit():options, "syntax", .F. )
            ::oHili:Do( n )
            aStru := ::oHili:aLineStru
            IF ::oHili:nItems > 0
               aClrs := ::oHili:hHili["colors"]
               FOR i := 1 TO ::oHili:nItems
                  IF aStru[i,1] < nxPosLast
                     IF aStru[i,2] >= nxPosFirst .AND. aStru[i,3] > 0
                        nx1 := Max( nxPosFirst, aStru[i,1] )
                        nx2 := Min( aStru[i,2], nxPosLast - 1 )
                        SetColor( Iif( !Empty(aClrs[aStru[i,3]]), aClrs[aStru[i,3]], ::aHiliAttrs[aStru[i,3]] ) )
                        IF lTabs
                           nf1 := edi_ExpandTabs( Self, cp_Left( ::lUtf8, s, nx1 - nxPosFirst ), nf, .T. )
                           DevPos( y, ::x1 + nf + nf1 - ::nxFirst )
                           DevOut( cp_Substr( ::lUtf8, s, nx1-nxPosFirst+1, nx2-nx1+1 ) )
                        ELSE
                           DevPos( y, nx1 - nf + ::x1 )
                           DevOut( cp_Substr( ::lUtf8, s, nx1-nf+1, nx2-nx1+1 ) )
                        ENDIF
                     ENDIF
                  ELSE
                     EXIT
                  ENDIF
               NEXT
            ENDIF
         ENDIF
         SetColor( ::cColor )
         IF lSel
            nbx1 := Iif( n > nby1 .AND. ::nSeleMode != 2, 1, nbx1 )
            nbx2 := Iif( n < nby2 .AND. ::nSeleMode != 2, cp_Len(::lUtf8,::aText[n])+1, nbx2 )
            IF nbx1 < nxPosLast .AND. nbx2 > nxPosFirst
               nbx1 := Max( nbx1, nxPosFirst )
               nbx2 := Min( nbx2, nxPosLast - 1 )
               SetColor( ::cColorSel )
               IF lTabs
                  nf1 := edi_ExpandTabs( Self, cp_Left( ::lUtf8, s, nbx1 - nxPosFirst ), nf, .T. )
                  DevPos( y, ::x1 + nf + nf1 - ::nxFirst )
                  DevOut( edi_ExpandTabs( Self, ;
                     cp_Substr( ::lUtf8, s, nbx1-nxPosFirst+1, nbx2-nbx1 ), nf + nf1 ) )
               ELSE
                  DevPos( y, nbx1 - nf + ::x1 )
                  DevOut( cp_Substr( ::lUtf8, s, nbx1-nf+1, nbx2-nbx1 ) )
               ENDIF
            ENDIF
            SetColor( Iif( n < nby2 .AND. ::nSeleMode != 2, ::cColorSel, ::cColor ) )
         ENDIF
      ELSEIF lSel .AND. n < nby2 .AND. ::nSeleMode != 2
         SetColor( ::cColorSel )
      ENDIF
      IF nLen < nWidth
         Scroll( y, ::x1 + nLen, y, ::x2 )
      ENDIF
      SetColor( ::cColor )
      DispEnd()
   ELSE
      Scroll( y, ::x1, y, ::x2 )
   ENDIF
   RETURN Nil

METHOD onKey( nKeyExt ) CLASS TEdit

   LOCAL nKey := hb_keyStd(nKeyExt), i, j, n, nCol := Col(), nRow := Row()
   LOCAL s, lShift, lCtrl := .F., lNoDeselect := .F., lSkip := .F., x

   n := ::nLine
   ::lTextOut := .F.

   IF !Empty( ::bOnKey )
      i := Eval( ::bOnKey, Self, nKeyExt )
      IF i == - 1
         RETURN Nil
      ELSEIF i > 0
         nKeyExt := i
         nKey := hb_keyStd(nKeyExt)
      ENDIF
   ENDIF

   IF (nKey >= K_NCMOUSEMOVE .AND. nKey <= HB_K_MENU) .OR. nKey == K_MOUSEMOVE
      RETURN Nil
   ENDIF

   IF ::npy1 > 0
      // drop highlighting of matched parenthesis
      DevPos( ::LineToRow(::npy1), ::PosToCol(::npy1,::npx1) )
      DevOut( cp_Substr( ::lUtf8, ::aText[::npy1], ::npx1, 1 ) )
      IF ::npy2 >= ::nyFirst .AND. ::npy2 < ::nyFirst + ::y2 - ::y1 .AND. ;
            ::npx2 >= ::nxFirst .AND. ::npx2 < ::nxFirst + ::x2 - ::x1
         DevPos( ::LineToRow(::npy2), ::PosToCol(::npy1,::npx2) )
         DevOut( cp_Substr( ::lUtf8, ::aText[::npy2], ::npx2, 1 ) )
      ENDIF
      DevPos( ::LineToRow(::npy1), ::PosToCol(::npy1,::npx1) )
      ::npy1 := ::npx1 := ::npy2 := ::npx2 := 0
   ENDIF

   IF ::nDopMode == 113  // q - macro recording
      IF Len( cDopMode ) == 1
         nKey := edi_MapKey( Self, nKey )
         IF (nKey >= 48 .AND. nKey <= 57) .OR. (nKey >= 97 .AND. nKey <= 122)
            cDopMode := "Rec " + Chr( nKey )
            aMacro := {}
         ELSE
            ::nDopMode := 0
            cDopMode := ""
         ENDIF
         lSkip := .T.
      ELSE
         IF nKey == 113
            ::hMacros[Asc(Right(cDopMode,1))] := aMacro
            ::nDopMode := 0
            cDopMode := ""
            lSkip := .T.
         ELSE
            Aadd( aMacro, nKeyExt )
         ENDIF
      ENDIF
   ELSEIF ::nDopMode > 0
      IF nKey == K_ESC
         ::nDopMode := 0
      ELSE
         nKey := edi_MapKey( Self, nKey )
         SWITCH ::nDopMode
         CASE 109     // m
            edi_BookMarks( Self, nKey, .T. )
            ::nDopMode := 0
            EXIT
         CASE 39  // '
            IF nKey == 46   // .
               ::GoTo( ::aUndo[::nUndo][UNDO_LINE2], ::aUndo[::nUndo][UNDO_POS2] )
            ELSE
               edi_BookMarks( Self, nKey, .F. )
            ENDIF
            ::nDopMode := 0
            EXIT
         CASE 102 // f
            IF ( i := cp_At( ::lUtf8, cp_Chr(::lUtf8,nKey), ::aText[n], ::nPos+1 ) ) > 0
               ::GoTo( n, i )
            ENDIF
            ::nDopMode := 0
            EXIT
         CASE 70  // F
            IF ( i := cp_Rat( ::lUtf8, cp_Chr(::lUtf8,nKey), ::aText[n],,::nPos-1 ) ) > 0
               ::GoTo( n, i )
            ENDIF
            ::nDopMode := 0
            EXIT
         CASE 49  // 1
            cDopMode += Chr( nKey )
            IF nKey == 103    // g
               ::nDopMode := 103
            ELSEIF nKey == 64    // @
               ::nDopMode := 64
            ELSEIF Chr(nKey) $ cKeysMove .AND. nKey != 48
               edi_Move( Self, nKey, Val( cDopMode ) )
               nKey := K_RIGHT
               ::nDopMode := 0
            ELSEIF nKey == 120   // x
               FOR i := Val( cDopMode ) TO 1 STEP -1
                  ::DelText( n, ::nPos, n, ::nPos )
               NEXT
               ::nDopMode := 0
            ELSEIF nKey == 99   // c
               ::nDopMode := 99
            ELSEIF nKey == 100   // d
               ::nDopMode := 100
            ELSEIF !( nKey >= 48 .AND. nKey <= 57 )
               ::nDopMode := 0
            ENDIF
            EXIT
         CASE 99   // c
         CASE 100  // d
            IF nKey == 100    // d
               IF ::nDopMode == 100
                  x := Iif( IsDigit( cDopMode ), Val( cDopMode ), 1 )
                  FOR i := 1 TO x
                     IF n > 0 .AND. n <= Len( ::aText )
                        ::DelText( n, 0, n+1, 0 )
                     ENDIF
                  NEXT
               ENDIF
               ::nDopMode := 0

            ELSEIF nKey == 99    // c
               IF ::nDopMode == 99
                  x := Iif( IsDigit( cDopMode ), Val( cDopMode ), 1 )
                  FOR i := 1 TO x
                     IF n > 0 .AND. n <= Len( ::aText )
                        ::DelText( n, 1, n, cp_Len(::lUtf8,::aText[n]) )
                     ENDIF
                  NEXT
                  mnu_ChgMode( Self, .T. )
               ENDIF
               ::nDopMode := 0

            ELSEIF nKey == 105    // i
               //IF cDopMode == "d"
                  cDopMode += Chr( nKey )
               //ENDIF

            ELSEIF nKey == 98 .OR. nKey == 66    // b, B
               IF IsDigit( cDopMode )
                  x := Val( cDopMode )
                  i := Iif( ( i := At( 'd',cDopMode ) ) == 0, At( '�',cDopMode ), i )
                  cDopMode := Substr( cDopMode, i )
               ELSE
                  x := 1
               ENDIF
               IF cDopMode $ "cd"
                  mnu_F3( Self )
                  FOR i := 1 TO x
                     edi_PrevWord( Self, (nKey == 66) )
                     ::nby2 := ::nLine
                     ::nbx2 := ::nPos
                     cbDele( Self )
                  NEXT
                  IF ::nDopMode == 99
                     mnu_ChgMode( Self, .T. )
                  ENDIF
               ENDIF
               ::nDopMode := 0

            ELSEIF nKey == 101 .OR. nKey == 69   // e, E
               IF IsDigit( cDopMode )
                  x := Val( cDopMode )
                  i := Iif( ( i := At( 'd',cDopMode ) ) == 0, At( '�',cDopMode ), i )
                  cDopMode := Substr( cDopMode, i )
               ELSE
                  x := 1
               ENDIF
               IF cDopMode $ "cd"
                  mnu_F3( Self )
                  FOR i := 1 TO x
                     edi_NextWord( Self, (nKey == 69), .T. )
                     edi_GoRight( Self )
                     ::nby2 := ::nLine
                     ::nbx2 := ::nPos
                     cbDele( Self )
                  NEXT
                  IF ::nDopMode == 99
                     mnu_ChgMode( Self, .T. )
                  ENDIF
               ENDIF
               ::nDopMode := 0

            ELSEIF nKey == 119 .OR. nKey == 87   // w, W
               IF IsDigit( cDopMode )
                  x := Val( cDopMode )
                  i := Iif( ( i := At( 'd',cDopMode ) ) == 0, At( '�',cDopMode ), i )
                  cDopMode := Substr( cDopMode, i )
               ELSE
                  x := 1
               ENDIF
               IF cDopMode $ "cd"
                  mnu_F3( Self )
                  FOR i := 1 TO x
                     edi_NextWord( Self, (nKey == 87) )
                     ::nby2 := ::nLine
                     ::nbx2 := ::nPos
                     cbDele( Self )
                     ::lF3 := .F.
                  NEXT
                  IF ::nDopMode == 99
                     mnu_ChgMode( Self, .T. )
                  ENDIF
               ELSEIF cDopMode $ "di;ci"
                  edi_PrevWord( Self, .F.,, .T. )
                  mnu_F3( Self )
                  edi_NextWord( Self, (nKey == 87), .T. )
                  edi_GoRight( Self )
                  ::nby2 := ::nLine
                  ::nbx2 := ::nPos
                  cbDele( Self )
                  ::lF3 := .F.
                  IF ::nDopMode == 99
                     mnu_ChgMode( Self, .T. )
                  ENDIF
               ENDIF
               ::nDopMode := 0

            ELSEIF nKey == 34  // "
               IF cDopMode $ "di;ci"
                  IF ( i := edi_InQuo( Self, n, ::nPos ) ) > 0
                     x := cedi_Peek( ::lUtf8, ::aText[n], i )
                     IF ( j := cp_At( ::lUtf8, x, ::aText[n], i+1 ) ) > 0
                        ::nPos := i + 1
                        mnu_F3( Self )
                        ::nby2 := ::nLine
                        ::nbx2 := j
                        cbDele( Self )
                        ::lF3 := .F.
                        IF ::nDopMode == 99
                           mnu_ChgMode( Self, .T. )
                        ENDIF
                     ENDIF
                  ENDIF
               ENDIF
               ::nDopMode := 0
            ELSE
               ::nDopMode := 0
            ENDIF
            EXIT
         CASE 118  // v
            IF nKey == 87 .OR. nKey == 119  // w, W
               edi_PrevWord( Self, (nKey == 87),, .T. )
               ::nby1 := ::nLine
               ::nbx1 := ::nPos
               edi_NextWord( Self, (nKey == 87), .T. )
               edi_GoRight( Self )
               ::nby2 := ::nLine
               ::nbx2 := ::nPos
               nKey := K_RIGHT
               lNoDeselect := .T.
            ENDIF
            ::nDopMode := 0
            EXIT
         CASE 114  // r
            ::InsText( n, ::nPos, cp_Chr(::lUtf8,nKey), .T., .T. )
            ::nDopMode := 0
            EXIT
         CASE 103  // g
            IF nKey == 103    // g
               IF Val( cDopMode ) > 0
                  ::Goto( Val( cDopMode ) )
                  ::nDopMode := 0
               ELSE
                  ::Goto( 1 )
               ENDIF
            ELSEIF nKey == 105    // i
               IF ::nUndo > 0
                  ::GoTo( ::aUndo[::nUndo][UNDO_LINE2], ::aUndo[::nUndo][UNDO_POS2] )
               ENDIF
            ENDIF
            ::nDopMode := 0
            EXIT
         CASE 64   // @ - Macro playing
            ::nDopMode := 0
            IF ( n := Val( cDopMode ) ) == 0
               n := 1
            ENDIF
            IF nKey == 64 .AND. !Empty( nLastMacro )
               nKey := nLastMacro
            ENDIF
            IF hb_hHaskey( ::hMacros, nKey )
               nLastMacro := nKey
               x := ::hMacros[nKey]
               FOR j := 1 TO n
                  FOR i := 1 TO Len( x )
                     ::onKey( x[i] )
                  NEXT
               NEXT
            ENDIF
            EXIT
         CASE 90   // Z
            IF nKey == 90      // Z
               FOR i := Len( ::aWindows ) TO 1 STEP -1
                  IF ::aWindows[i]:lUpdated .AND. Empty(::aWindows[i]:cFileName)
                     edi_Alert( "Set file name" )
                     ::lShow := .F.
                     ::nCurr := i
                     RETURN Nil
                  ENDIF
               NEXT
               FOR i := Len( ::aWindows ) TO 1 STEP -1
                  IF !( ::aWindows[i] == Self )
                     IF ::aWindows[i]:lUpdated
                        ::aWindows[i]:Save()
                     ENDIF
                     hb_ADel( ::aWindows, i, .T. )
                  ENDIF
               NEXT
               ::Save()
               mnu_Exit( Self )
            ELSEIF nKey == 81  // Q
               FOR i := Len( ::aWindows ) TO 1 STEP -1
                  IF !( ::aWindows[i] == Self )
                     hb_ADel( ::aWindows, i, .T. )
                  ENDIF
               NEXT
               ::lUpdated := ::lShow := .F.
               ::lClose := .T.
            ENDIF
            ::nDopMode := 0
            EXIT
         CASE K_CTRL_W
            IF nKey == 119   // w
               mnu_Windows( Self,, 1 )
            ELSEIF nKey == 115   // s  split window horizontally
               mnu_Windows( Self,, 2 )
            ELSEIF nKey == 118   // v  split window vertically
               mnu_Windows( Self,, 3 )
            ELSEIF nKey == 99    // c
               IF ::oParent != Nil
                  mnu_Exit( Self )
               ENDIF
            ELSEIF nKey == 111   // o
            ELSEIF nKey == 43    // +
            ELSEIF nKey == 45    // -
            ELSEIF nKey == 60    // <
            ELSEIF nKey == 62    // >
            ENDIF
            ::nDopMode := 0
            EXIT
         END
      ENDIF
      IF ::nDopMode == 0
         cDopMode := ""
      ENDIF
      lSkip := .T.
   ENDIF

   IF !lSkip
      lShift := ( hb_BitAnd( nKeyExt, SHIFT_PRESSED ) != 0 .AND. Ascan( aKeysMove, nkey ) != 0 )
      IF lShift
         IF !::lShiftKey
            ::nby1 := ::nLine
            ::nbx1 := ::nPos
            ::nSeleMode := 0
            ::lShiftKey := .T.
         ENDIF
      ELSE
         ::lShiftKey := .F.
      ENDIF
      IF hb_BitAnd( nKeyExt, ALT_PRESSED ) != 0
         SWITCH nKey
         CASE K_ALT_F7
            mnu_SeaNext( Self, .F. )
            EXIT
         CASE K_ALT_F8
            mnu_GoTo( Self )
            ::lTextOut := .T.
            EXIT
         CASE K_ALT_B
            ::GoTo( ::nLineBack, ::nPosBack )
            EXIT
         CASE K_ALT_M
            ::nDopMode := 109
            cDopMode := "m"
            EXIT
         CASE K_ALT_QUOTE
            ::nDopMode := 39
            cDopMode := "'"
            EXIT
         CASE K_ALT_BS
            ::Undo()
            EXIT
         END
      ENDIF
      IF hb_BitAnd( nKeyExt, CTRL_PRESSED ) != 0

         lCtrl := .T.
         SWITCH nKey
         CASE K_CTRL_INS
         CASE 3                           // Ctrl-Ins or Ctrl-c
            IF !Empty( s := Text2cb( Self ) )
               hb_gtInfo( HB_GTI_CLIPBOARDDATA, TEdit():aCBoards[1,1] := s )
               TEdit():aCBoards[1,2] := Nil
               TEdit():aCBoards[1,3] := Iif( ::nSeleMode==2,.T.,Nil )
            ENDIF
            lNoDeselect := .T.
            EXIT
         CASE 22                          // Ctrl-v
            IF ::nMode == 1
               mnu_F3( Self, 2 )
               nKey := K_RIGHT
            ELSEIF !::lReadOnly
               cb2Text( Self, .T. )
            ENDIF
            EXIT
         CASE K_CTRL_X
            IF !Empty( s := Text2cb( Self ) )
               hb_gtInfo( HB_GTI_CLIPBOARDDATA, TEdit():aCBoards[1,1] := s )
               TEdit():aCBoards[1,2] := Nil
               TEdit():aCBoards[1,3] := Iif( ::nSeleMode==2,.T.,Nil )
            ENDIF
            cbDele( Self )
            EXIT
         CASE K_CTRL_Q
            IF hb_keyVal( nKeyExt ) == 81 .AND. ::nDefMode >= 0
               mnu_ChgMode( Self )
            ENDIF
            EXIT
         CASE K_CTRL_Y
            IF !::lReadOnly .AND. ::nMode == 0 .AND. n > 0 .AND. n <= Len( ::aText )
               ::DelText( n, 1, n+1, 1 )
            ENDIF
            EXIT
         CASE K_CTRL_A
            IF !::lF3
               ::nby1 := ::nbx1 := 1
               ::nby2 := Len( ::aText )
               ::nbx2 := cp_Len( ::lUtf8, ::aText[Len(::aText)] )
               ::nSeleMode := 0
               ::lF3 := .T.
            ENDIF
            EXIT
         CASE K_CTRL_TAB
            IF ::lCtrlTab
               ::lShow := .F.
               ::nCurr ++
            ENDIF
            lNoDeselect := .T.
            EXIT
         CASE K_CTRL_PGUP
         CASE K_CTRL_HOME
            ::nPosBack := ::nPos
            ::nLineBack := ::nLine
            ::lTextOut := (::nyFirst>1 .OR. ::nxFirst>1)
            ::nxFirst := ::nyFirst := 1
            edi_SetPos( Self, 1, 1 )
            EXIT
         CASE K_CTRL_PGDN
         CASE K_CTRL_END
            IF hb_keyVal( nKeyExt ) == 87  // Ctrl-W
               ::nDopMode := nKey
               cDopMode := "W"
            ELSE
               edi_Move( Self, 71 )
            ENDIF
            EXIT
         CASE K_CTRL_RIGHT
            IF hb_keyVal( nKeyExt ) == 66 // Ctrl-B
               IF ::nMode == 1
                  edi_Move( Self, K_CTRL_B )
               ELSE
                  edi_Bracket( Self )
               ENDIF
            ELSEIF hb_keyVal( nKeyExt ) == 16
               edi_NextWord( Self, .F. )
            ENDIF
            EXIT
         CASE K_CTRL_LEFT
            IF hb_keyVal( nKeyExt ) == 90  // Ctrl-Z
               ::Undo()
            ELSEIF hb_keyVal( nKeyExt ) == 15
               edi_PrevWord( Self, .F. )
            ENDIF
            EXIT
         CASE K_CTRL_F
            IF ::nMode == 1
               edi_Move( Self, K_CTRL_F )
            ENDIF
            EXIT
         CASE K_CTRL_F3
            mnu_F3( Self, 2 )
            nKey := K_RIGHT
            EXIT
         CASE K_CTRL_F4
            mnu_OpenFile( Self )
            ::lTextOut := .T.
            EXIT
         CASE K_CTRL_F7
            mnu_SeaAndRepl( Self )
            ::lTextOut := .T.
            EXIT
        END
      ELSE
         IF ( nKey >= K_SPACE .AND. nKey <= 255 ) .OR. ( ::lUtf8 .AND. nKey > 3000 )
            IF ::nby1 >= 0 .AND. ::nby2 >= 0
               nKey := edi_MapKey( Self, nKey )
               IF Chr(nKey) $ cKeysMove
                  edi_Move( Self, nKey )
                  nKey := K_RIGHT
               ELSE
                  SWITCH nKey
                  CASE 85   // U  Convert to upper case
                     edi_ConvertCase( Self, .T. )
                     lNoDeselect := .T.
                     EXIT
                  CASE 117   // u Convert to lower case
                     edi_ConvertCase( Self, .F. )
                     lNoDeselect := .T.
                     EXIT
                  CASE 99    // c Deletes selection and switch to Edit mode
                     IF ::nMode == 1
                        cbDele( Self )
                        mnu_ChgMode( Self, .T. )
                     ENDIF
                     EXIT
                  CASE 100   // d Deletes selection
                     cbDele( Self )
                     EXIT
                  CASE 121   // y Copy to clipboard
                     IF !Empty( s := Text2cb( Self ) )
                        hb_gtInfo( HB_GTI_CLIPBOARDDATA, TEdit():aCBoards[1,1] := s )
                        TEdit():aCBoards[1,2] := Nil
                        TEdit():aCBoards[1,3] := Iif( ::nSeleMode==2,.T.,Nil )
                     ENDIF
                     EXIT
                  CASE 62    // > Shift lines right
                     edi_Indent( Self, .T. )
                     lNoDeselect := .T.
                     EXIT
                  CASE 60    // > Shift lines left
                     edi_Indent( Self, .F. )
                     lNoDeselect := .T.
                     EXIT
                  CASE 105   // i
                     ::nDopMode := 118
                     cDopMode := "vi"
                     nKey := K_RIGHT
                     lNoDeselect := .T.
                     EXIT
                  CASE 111   // o
                     IF ::nLine == ::nby2 .AND. ::nPos == ::nbx2
                        ::nLine := ::nby1
                        ::nPos := ::nbx1
                     ELSE
                        ::nLine := ::nby2
                        ::nPos := ::nbx2
                     ENDIF
                     x := ::nby1; ::nby1 := ::nby2; ::nby2 := x
                     x := ::nbx1; ::nbx1 := ::nbx2; ::nbx2 := x
                     edi_SetPos( Self )
                     nKey := K_RIGHT
                     lNoDeselect := .T.
                     EXIT
                  CASE K_ESC
                     nKey := 0
                     EXIT
                  END
               ENDIF
            ELSEIF ::nMode == 1
               nKey := edi_MapKey( Self, nKey )
               IF Chr(nKey) $ cKeysMove
                  edi_Move( Self, nKey )
                  nKey := K_RIGHT
               ELSEIF nKey >= 49 .AND. nKey <= 57  // 1...9
                  ::nDopMode := 49
                  cDopMode := Chr( nKey )
               ELSE
                  SWITCH nKey
                  CASE 118   // v Start selection
                     mnu_F3( Self )
                     nKey := K_RIGHT
                     EXIT
                  CASE 86    // V Start selection
                     mnu_F3( Self, 1 )
                     nKey := K_RIGHT
                     EXIT
                  CASE 117   // u Undo
                     ::Undo()
                     EXIT
                  CASE 112   // p Insert clipboard after current coloumn
                     IF !::lReadOnly
                        edi_SetPos( Self, ::nLine, ++::nPos )
                        cb2Text( Self, .T. )
                     ENDIF
                     EXIT
                  CASE 80    // P Insert clipboard
                     IF !::lReadOnly
                        cb2Text( Self, .T. )
                     ENDIF
                     EXIT
                  CASE 105   // i - to edit mode
                     mnu_ChgMode( Self, .T. )
                     ::lIns := .T.
                     EXIT
                  CASE 73    // I - to edit mode
                     edi_Move( Self, 94 )
                     mnu_ChgMode( Self, .T. )
                     ::lIns := .T.
                     EXIT
                  CASE 97    // a - to edit mode
                     edi_GoRight( Self )
                     mnu_ChgMode( Self, .T. )
                     ::lIns := .T.
                     EXIT
                  CASE 65    // A - to edit mode
                     mnu_ChgMode( Self, .T. )
                     edi_GoEnd( Self )
                     ::lIns := .T.
                     EXIT
                  CASE 82    // R - to edit mode
                     mnu_ChgMode( Self, .T. )
                     ::lIns := .F.
                     EXIT
                  CASE 111   // o Insert line after current
                     ::InsText( n, cp_Len(::lUtf8,::aText[n])+1, Chr(10), .F., .T. )
                     mnu_ChgMode( Self, .T. )
                     ::lIns := .T.
                     EXIT
                  CASE 126   // ~ Invert case
                     x := cedi_Peek( ::lUtf8, ::aText[n], ::nPos )
                     IF ( s := cp_Upper( ::lUtf8, x ) ) != x .OR. ;
                           ( s := cp_Lower( ::lUtf8, x ) ) != x
                        ::InsText( n, ::nPos, s, .T., .T. )
                     ENDIF
                     EXIT
                  CASE 102   // f - find next char
                  CASE 70    // F - find previous char
                  CASE 109   // m - set bookmark
                  CASE 39    // ' - goto bookmark
                  CASE 99    // c - delete and edit
                  CASE 100   // d - delete
                  CASE 103   // g
                  CASE 113   // q - record macro
                  CASE 64    // w - play macro
                  CASE 114   // r - replace one char under cursor
                  CASE 90    // Z
                     ::nDopMode := nKey
                     cDopMode := Chr( nKey )
                     EXIT
                  CASE 120   // x - delete a char
                     ::DelText( n, ::nPos, n, ::nPos )
                     EXIT
                  CASE 37    // %  Go to matching parentheses
                     edi_Bracket( Self )
                     EXIT
                  CASE 72    // H
                     edi_SetPos( Self, ::nyFirst, ::nxFirst )
                     edi_Move( Self, 94 )
                     EXIT
                  CASE 77    // M
                     edi_SetPos( Self, Min( Len(::aText), ::nyFirst + Int((::y2-::y1)/2) ), ::nxFirst )
                     edi_Move( Self, 94 )
                     EXIT
                  CASE 76    // L
                     edi_SetPos( Self, Min( Len(::aText), ::nyFirst + ::y2-::y1 ), ::nxFirst )
                     edi_Move( Self, 94 )
                     EXIT
                  CASE 42    // *
                     i := edi_PrevWord( Self, .F., .F.,,, ::nPos+1 )
                     x := edi_NextWord( Self, .F., .T., .F.,, ::nPos-1 )
                     s := cp_Substr( ::lUtf8, ::aText[n], i, x-i+1 )
                     i := ::nPos
                     IF ::Search( s, .T., .T., .F., .F., @n, @i )
                        ::GoTo( n, i, 0 )
                     ENDIF
                     EXIT
                  CASE 35    // #
                     i := edi_PrevWord( Self, .F., .F.,,, ::nPos+1 )
                     x := edi_NextWord( Self, .F., .T., .F.,, ::nPos-1 )
                     s := cp_Substr( ::lUtf8, ::aText[n], i, x-i+1 )
                     i --
                     IF ::Search( s, .T., .F., .F., .F., @n, @i )
                        ::GoTo( n, i, 0 )
                     ENDIF
                     EXIT
                  CASE 47    // /
                     ::nMode := 2
                     ::WriteTopPane( 1 )
                     __KeyBoard( "/" )
                     mnu_CmdLine( Self )
                     EXIT
                  CASE 58    // :
                     IF ::nDefMode >= 0
                        mnu_ChgMode( Self )
                     ENDIF
                     EXIT
                  END
               ENDIF
            ELSE
               ::InsText( n, ::nPos, cp_Chr(::lUtf8,nKey), !::lIns, .T. )
            ENDIF

         ELSE
            SWITCH nKey
            CASE K_ENTER
               IF !::lReadOnly .AND. ::nMode == 0
                  s := ""
                  IF hb_hGetDef( TEdit():options, "autoindent", .F. )
                     i := 0
                     DO WHILE ( x := cp_Substr( ::lUtf8, ::aText[n], ++i, 1 )  ) == " " .OR. x == cTab
                        s += x
                     ENDDO
                     IF s != "" .AND. ::nPos <= Len( s )
                        s := Left( s, ::nPos - 1 )
                     ENDIF
                  ENDIF
                  ::InsText( n, ::nPos, Chr(10) + s, .F., .T. )
               ENDIF
               EXIT
            CASE K_DEL
               IF !::lReadOnly
                  IF ::nby1 >= 0 .AND. ::nby2 >= 0
                     IF hb_BitAnd( nKeyExt, SHIFT_PRESSED ) != 0 .AND. !Empty( s := Text2cb( Self ) )
                        hb_gtInfo( HB_GTI_CLIPBOARDDATA, TEdit():aCBoards[1,1] := s )
                        TEdit():aCBoards[1,2] := Nil
                        TEdit():aCBoards[1,3] := Iif( ::nSeleMode==2,.T.,Nil )
                     ENDIF
                     cbDele( Self )
                  ELSE
                     ::DelText( n, ::nPos, n, ::nPos )
                  ENDIF
               ENDIF
               EXIT
            CASE K_BS
               IF !::lReadOnly .AND. ::nMode == 0
                  IF ::nby1 >= 0 .AND. ::nby2 >= 0
                     IF hb_BitAnd( nKeyExt, SHIFT_PRESSED ) != 0 .AND. !Empty( s := Text2cb( Self ) )
                        hb_gtInfo( HB_GTI_CLIPBOARDDATA, TEdit():aCBoards[1,1] := s )
                        TEdit():aCBoards[1,2] := Nil
                        TEdit():aCBoards[1,3] := Iif( ::nSeleMode==2,.T.,Nil )
                     ENDIF
                     cbDele( Self )
                  ELSE
                     IF ::nPos == 1
                        IF n > 1
                           edi_GoUp( Self )
                           edi_GoEnd( Self )
                           ::DelText( n-1, ::nPos, n-1, ::nPos )
                        ENDIF
                     ELSEIF ::nPos <= cp_Len( ::lUtf8, ::aText[n] ) + 1
                        ::DelText( n, ::nPos-1, n, ::nPos-1 )
                     ELSE
                        edi_GoLeft( Self )
                     ENDIF
                  ENDIF
               ENDIF
               EXIT
            CASE K_TAB
               IF !::lReadOnly .AND. ::lIns
                  IF hb_hGetDef( TEdit():options,"tabtospaces", .F. )
                     ::InsText( n, ::nPos, cTabStr, .F., .T. )
                  ELSE
                     ::InsText( n, ::nPos, cTab, .F., .T. )
                  ENDIF
               ENDIF
               EXIT
            CASE K_INS
               IF hb_BitAnd( nKeyExt, SHIFT_PRESSED ) != 0
                  IF !::lReadOnly
                     cb2Text( Self, .T. )
                  ENDIF
               ELSE
                  ::lIns := !::lIns
               ENDIF
               EXIT
            CASE K_MWFORWARD
            CASE K_UP
               IF nKey == K_UP .OR. ( (nRow := MRow()) >= ::y1 .AND. ;
                  nRow <= ::y2 .AND. (nCol := MCol()) >= ::x1 .AND. nCol <= ::x2 )
                  edi_GoUp( Self )
               ENDIF
               EXIT
            CASE K_MWBACKWARD
            CASE K_DOWN
               IF nKey == K_DOWN .OR. ( (nRow := MRow()) >= ::y1 .AND. ;
                  nRow <= ::y2 .AND. (nCol := MCol()) >= ::x1 .AND. nCol <= ::x2 )
                  edi_GoDown( Self )
               ENDIF
               EXIT
            CASE K_LEFT
               edi_GoLeft( Self )
               EXIT
            CASE K_RIGHT
               edi_GoRight( Self )
               EXIT
            CASE K_HOME
               edi_Move( Self, 48 )
               EXIT
            CASE K_END
               edi_GoEnd( Self )
               EXIT
            CASE K_PGUP
               edi_Move( Self, K_CTRL_B )
               EXIT
            CASE K_PGDN
               edi_Move( Self, K_CTRL_F )
               EXIT
            CASE K_LBUTTONDOWN
               IF ::nDopMode == 0
                  nCol := MCol()
                  nRow := MRow()
                  IF ::lTopPane .AND. nRow == ::y1-1 .AND. nCol < 8
                     FMenu( Self, aMenuMain, 2, 6 )
                     ::lTextOut := .T.
                  ELSEIF nRow >= ::y1 .AND. nRow <= ::y2 .AND. nCol >= ::x1 .AND. nCol <= ::x2
                     IF ::RowToLine(nRow) > Len(::aText)
                        nRow := Len(::aText) - ::nyFirst + ::y1
                     ENDIF
                     edi_SetPos( Self, ::RowToLine(nRow), ::ColToPos(nRow,nCol) )
                  ELSEIF nRow >= ::aRectFull[1] .AND. nRow <= ::aRectFull[3] .AND. nCol >= ::aRectFull[2] .AND. nCol <= ::aRectFull[4]
                     IF ( x := edi_FindWindow( Self,, nRow, nCol ) ) != Nil
                        mnu_ToBuf( Self, x )
                        x:nLine := x:RowToLine(nRow)
                        IF x:nLine > Len( x:aText )
                           x:nLine := Len( x:aText )
                        ENDIF
                        x:nPos := x:ColToPos(x:LineToRow(x:nLine),nCol)
                     ENDIF
                  ELSE
                     RETURN Nil
                  ENDIF
               ENDIF
               EXIT
            CASE K_F1
               mnu_Help( Self )
               ::lTextOut := .T.
               edi_SetPos( Self )
               EXIT
            CASE K_F2
               ::Save()
               EXIT
            CASE K_SH_F2
               mnu_Save( Self, .T. )
               EXIT
            CASE K_F3
               mnu_F3( Self )
               lNoDeselect := .T.
               nKey := K_RIGHT
               EXIT
            CASE K_F4
               mnu_F4( Self, {2, 6} )
               ::lTextOut := .T.
               EXIT
            CASE K_SH_F4
               mnu_NewBuf( Self )
               ::lTextOut := .T.
               EXIT
            CASE K_F7
               mnu_Search( Self )
               ::lTextOut := .T.
               EXIT
            CASE K_F8
               mnu_Syntax( Self, {2, 6} )
               ::lTextOut := .T.
               EXIT
            CASE K_F9
               FMenu( Self, aMenuMain, 2, 6 )
               ::lTextOut := .T.
               edi_SetPos( Self )
               EXIT
            CASE K_F10
            CASE K_ESC
               IF nKey == K_ESC .AND. ::nDefMode == 1
                  IF ::nMode == 0
                     mnu_ChgMode( Self )
                  ENDIF
               ELSE
                  mnu_Exit( Self )
               ENDIF
               EXIT
            CASE K_F11
               mnu_Plugins( Self )
               ::lTextOut := .T.
               EXIT
            CASE K_F12
               mnu_Buffers( Self, {2, 6} )
               ::lTextOut := .T.
               EXIT
            CASE K_SH_F7
               mnu_SeaNext( Self, .T. )
               EXIT
            CASE K_SH_F8
               mnu_cPages( Self, {2,6} )
               ::lTextOut := .T.
               EXIT
            END
         ENDIF
      ENDIF

      IF ::lF3 .AND. nKey != K_MOUSEMOVE .AND. Ascan( aKeysMove, nKey ) == 0
         ::lF3 := .F.
      ENDIF
      IF (::lF3 .OR. lShift)
         IF !( lCtrl .AND. nKey == K_CTRL_A)
            ::nby2 := ::nLine
            IF ::nSeleMode == 1
               ::nbx2 := cp_Len( ::lUtf8, ::aText[::nLIne] ) + 1
            ELSE
               ::nbx2 := ::nPos
            ENDIF
         ENDIF
      ELSEIF !lNoDeselect
         IF ::nby1 >= 0 .AND. ::nby2 >= 0
            ::lTextOut := .T.
            ::nby1 := ::nby2 := -1
         ENDIF
      ENDIF
   ENDIF
   IF ::lTextOut .OR. (::nby1 >= 0 .AND. ::nby2 >= 0 .AND. nKey != K_MOUSEMOVE)
      ::TextOut()
   ENDIF

   IF !Empty( ::oHili ) .AND. ::oHili:hHili["bra"] .AND. !Empty( x := edi_Bracket( Self, .T., .T. ) )
      // highlighting matched parenthesis
      ::npy1 := ::nLine; ::npx1 := ::nPos
      ::npy2 := Iif( Valtype(x)=="A",x[1], ::npy1 ); ::npx2 := Iif( Valtype(x)=="A",x[2], x )
      SetColor( ::cColorBra )
      DevPos( ::LineToRow(::npy1), ::PosToCol(::npy1,::npx1) )
      DevOut( cp_Substr( ::lUtf8, ::aText[::npy1], ::npx1, 1 ) )
      IF ::npy2 >= ::nyFirst .AND. ::npy2 < ::nyFirst + ::y2 - ::y1 .AND. ;
            ::npx2 >= ::nxFirst .AND. ::npx2 < ::nxFirst + ::x2 - ::x1
         DevPos( ::LineToRow(::npy2), ::PosToCol(::npy2,::npx2) )
         DevOut( cp_Substr( ::lUtf8, ::aText[::npy2], ::npx2, 1 ) )
      ENDIF
      SetColor( ::cColor )
      DevPos( ::LineToRow(::npy1), ::PosToCol(::npy1,::npx1) )
   ENDIF

   ::WriteTopPane()

   RETURN Nil

METHOD WriteTopPane( lClear ) CLASS TEdit

   LOCAL y := ::y1 - 1, nCol := Col(), nRow := Row(), nF9 := 0
   LOCAL cLen := Ltrim(Str(Len(::aText))), nchars := Len(cLen)

   IF ::bWriteTopPane != Nil
      Eval( ::bWriteTopPane, Self, lClear, y )
   ELSE
      IF ::lTopPane
         DispBegin()
         SetColor( ::cColorPane )
         Scroll( y, ::x1, y, ::x2 )
         IF Empty( lClear )
            DevPos( y, ::x1 )
            IF ::x2 - ::x1 > 54
               DevOut( "F9-menu" )
               DevPos( y, ::x1+8 )
               nF9 := 8
            ENDIF
            DevOut( cp_Left( ::lUtf8, hb_fnameNameExt(::cFileName), ::nTopName ) )
            IF !Empty( cDopMode )
               DevPos( y, ::x1 )
               DevOut( Padr( cDopMode, 8 ) )
            ENDIF
            DevPos( y, ::x1 + nF9 + ::nTopName + 2 )
            DevOut( Iif( ::lUpdated, "* ", "  " ) + Lower( ::cp ) )
            DevPos( y, ::x1 + nF9 + ::nTopName + 12 )
            DevOut( PAdl(Ltrim(Str(::nLine)),nchars) + "/" + cLen )
            DevPos( y, ::x1 + nF9 + ::nTopName + 12 + nchars*2 + 3 )
            DevOut( "[" + Ltrim(Str(::PosToCol()-::x1+::nxFirst)) + "]" )
            SetColor( "W+/N" )
            DevPos( y, ::x2-3 )
            IF ::lF3 .OR. (::nby1 >= 0 .AND. ::nby2 >= 0)
               DevOut( "Sele" )
            ELSE
               DevOut( Iif( ::nMode == 0, Iif( ::lReadOnly, "View", "Edit" ), ;
                  Iif( ::nMode == 1, " Vim", " Cmd" ) ) )
            ENDIF
         ENDIF
         SetColor( ::cColor )
         DevPos( nRow, nCol )
         DispEnd()
      ENDIF
   ENDIF

   RETURN Nil

METHOD ColToPos( nRow, nCol ) CLASS TEdit

   nCol := nCol - ::x1 + ::nxFirst
   RETURN edi_Col2Pos( Self, ::RowToLine(nRow), nCol )
   //nCol := edi_Col2Pos( Self, ::RowToLine(nRow), nCol )
   //RETURN nCol - ::x1 + ::nxFirst

METHOD PosToCol( nLine, nPos ) CLASS TEdit

   LOCAL nAdd := 0
   IF nPos == Nil; nPos := ::nPos; ENDIF
   IF nLine == Nil; nLine := ::nLine; ENDIF

   IF nPos > 1
      edi_ExpandTabs( Self, cp_Left(::lUtf8,::aText[nLine],nPos-1), 1, .T., @nAdd )
   ENDIF
   nPos += nAdd
   RETURN nPos + ::x1 - ::nxFirst

METHOD Search( cSea, lCase, lNext, lWord, lRegex, ny, nx, lInc ) CLASS TEdit

   LOCAL lRes := .F., i, nLen := Len( ::aText ), nLenSea := cp_Len(::lUtf8,cSea), nPos, s

   IF !lCase
      cSea := cp_Lower( ::lUtf8, cSea )
   ENDIF
   IF lNext
      s := cp_Substr( ::lUtf8, ::aText[ny], nx, nLenSea )
      IF Empty( lInc ) .AND. cSea == Iif( lCase, s, cp_Lower( ::lUtf8,s ) )
         nx ++
      ENDIF
      FOR i := ny TO nLen
         s := Iif( lCase, ::aText[i], cp_Lower( ::lUtf8, ::aText[i] ) )
         IF i > ny
            nx := 1
         ENDIF
         DO WHILE .T.
            nPos := nx
            IF !lRegex .AND. ( nPos := cp_At( ::lUtf8, cSea, s, nx ) ) == 0
               EXIT
            ELSEIF lRegex .AND. hb_Atx( cSea, s, lCase, @nPos ) == Nil
               nPos := 0
               EXIT
            ENDIF
            IF lWord .AND. !lRegex
               IF ( nPos == 1 .OR. !edi_AlphaNum( cp_Asc( ::lUtf8, cedi_Peek(::lUtf8,s,nPos-1) ) ) ) ;
                  .AND. ( nPos+nLenSea > cp_Len( ::lUtf8, s ) .OR. !edi_AlphaNum( cp_Asc( ::lUtf8, cedi_Peek(::lUtf8,s,nPos+nLenSea) ) ) )
                  EXIT
               ELSE
                  nx ++
               ENDIF
            ELSE
               EXIT
            ENDIF
         ENDDO
         IF nPos > 0
            lRes := .T.; ny := i; nx := nPos
            EXIT
         ENDIF
      NEXT
   ELSE
      s := cp_Substr( ::lUtf8, ::aText[ny], nx, nLenSea )
      IF cSea == Iif( lCase, s, cp_Lower( ::lUtf8,s ) )
         nx --
      ENDIF
      FOR i := ny TO 1 STEP -1
         s := Iif( lCase, ::aText[i], cp_Lower( ::lUtf8, ::aText[i] ) )
         IF i < ny
            nx := cp_Len( ::lUtf8,::aText[i] )
         ENDIF
         DO WHILE ( nPos := cp_RAt( ::lUtf8, cSea, s, 1, nx ) ) > 0
            IF lWord
               IF ( nPos == 1 .OR. !edi_AlphaNum( cp_Asc( ::lUtf8, cedi_Peek(::lUtf8,s,nPos-1) ) ) ) ;
                  .AND. ( nPos+nLenSea > cp_Len( ::lUtf8, s ) .OR. !edi_AlphaNum( cp_Asc( ::lUtf8, cedi_Peek(::lUtf8,s,nPos+nLenSea) ) ) )
                  EXIT
               ELSE
                  nx --
               ENDIF
            ELSE
               EXIT
            ENDIF
         ENDDO
         IF nPos > 0
            lRes := .T.; ny := i; nx := nPos
            EXIT
         ENDIF
      NEXT
   ENDIF

   RETURN lRes

METHOD GoTo( ny, nx, nSele, lNoGo ) CLASS TEdit

   LOCAL lTextOut := .F., nRowOld

   IF ny == Nil; ny := ::nLine; ENDIF
   IF nx == Nil; nx := 1; ENDIF
   IF ny > Len(::aText)
      RETURN Nil
   ENDIF

   IF Empty( lNoGo )
      ::nPosBack := ::nPos
      ::nLineBack := ::nLine
   ENDIF
   IF ny < ::nyFirst .OR. ny > ::nyFirst + (::y2-::y1)
      ::nyFirst := Max( ny-3, 1 )
      lTextOut := .T.
   ENDIF
   IF nx < ::nxFirst .OR. nx > ::nxFirst + (::x2-::x1)
      ::nxFirst := Iif( nx < ::x2-::x1, 1, nx - Int((::x2-::x1)*0.8) )
      lTextOut := .T.
   ENDIF

   IF nSele != Nil .AND. nSele > 0
      ::nby1 := ::nby2 := ny; ::nbx1 := nx; ::nbx2 := nx + nSele
   ENDIF

   IF Empty( lNoGo )
      SetColor( ::cColor )
      IF lTextOut
         ::TextOut()
      ELSE
         IF nSele != Nil .AND. nSele > 0 .AND. ( nRowOld := (::nLine - ::nyFirst + 1) ) > 0
            ::LineOut( nRowOld )
         ENDIF
         ::LineOut( ny - ::nyFirst + 1 )
      ENDIF
      ::WriteTopPane()
      edi_SetPos( Self, ny, nx )
   ELSE
      ::nLine := ny
      ::nPos := nx
   ENDIF

   RETURN Nil

METHOD ToString( cEol, cp ) CLASS TEdit

   LOCAL i, nLen := Len( ::aText ), cBom := e"\xef\xbb\xbf", s := Iif( ::lBom, cBom, "" )
   LOCAL lTrim := hb_hGetDef( TEdit():options,"trimspaces", .F. )

   IF Empty( cEol )
      cEol := ::cEol
   ENDIF
   IF Empty( ::aText[nLen] )
      nLen --
   ENDIF
   FOR i := 1 TO nLen
      IF lTrim .AND. Right( ::aText[i], 1 ) == " "
         ::aText[i] := Trim( ::aText[i] )
      ENDIF
      IF cp != Nil .AND. !( cp == ::cp )
         s += hb_strToUtf8( Iif( ::lTabs, Strtran(::aText[i],cTabStr,cTab), ::aText[i] ), ::cp ) + cEol
      ELSE
         s += Iif( ::lTabs, Strtran(::aText[i],cTabStr,cTab), ::aText[i] ) + cEol
      ENDIF
   NEXT

   RETURN s

METHOD Save( cFileName ) CLASS TEdit

   LOCAL dDateMod := ::dDateMod, cTimeMod := ::cTimeMod

   IF cFileName == Nil
      cFileName := ::cFileName
   ENDIF
   IF Empty( cFileName )
      cFileName := edi_SaveDlg( Self )
      ::lTextOut := .T.
   ENDIF

   IF Empty( cFileName )
      RETURN .F.
   ELSE
      IF Empty( hb_fnameDir( cFileName ) )
         cFileName := edi_CurrPath() + cFileName
      ENDIF
      ::cFileName := cFileName
   ENDIF

   IF !Empty( ::dDateMod ) .AND. hb_fGetDateTime( ::cFileName, @dDateMod, @cTimeMod ) .AND. ;
      ( ::dDateMod != dDateMod .OR. ::cTimeMod != cTimeMod ) .AND. ;
      edi_Alert( "File was modified by other program!", "Save", "Cancel" ) != 1
      RETURN .F.
   ENDIF

   IF Empty( ::funSave )
      hb_MemoWrit( cFileName, ::ToString() )
      IF hb_fGetDateTime( ::cFileName, @dDateMod, @cTimeMod )
         ::dDateMod := dDateMod
         ::cTimeMod := cTimeMod
      ENDIF
   ELSE
      ::funsave:exec( cFileName, ::ToString() )
   ENDIF
   ::lUpdated := .F.

   RETURN .T.

METHOD InsText( nLine, nPos, cText, lOver, lChgPos, lNoUndo ) CLASS TEdit

   LOCAL arr, i, nLine2, nPos2, cTemp, cTextOld, nLineNew, nPosNew, nCol

   IF ::lReadOnly
      RETURN Nil
   ENDIF
   IF lOver == Nil; lOver := .F.; ENDIF
   IF lChgPos == Nil; lChgPos := .T.; ENDIF
   IF nLine > Len( ::aText )
      Aadd( ::aText, "" )
      nLine := Len( ::aText )
      nPos := 1
   ELSEIF ( i := (nPos - cp_Len(::lUtf8,::aText[nLine])) ) > 0
      nPos -= (i-1)
      IF lChgPos
         ::nPos -= (i-1)
      ENDIF
      cText := Space( i-1 ) + cText
   ENDIF
   nLine2 := nLine
   IF Chr(10) $ cText
      arr := hb_ATokens( cText, Chr(10) )
      IF lOver
         cTextOld := cp_Substr( ::lUtf8, ::aText[nLine], nPos ) + Chr(10)
         ::aText[nLine] := cp_Left( ::lUtf8, ::aText[nLine], nPos-1 ) + arr[1]
         FOR i := 2 TO Len(arr)-1
            cTextOld += ::aText[nLine+i-1] + Chr(10)
            ::aText[nLine+i-1] := arr[i]
            nLine2 ++
         NEXT
         cTextOld += cp_Left( ::lUtf8, ::aText[nLine+i-1], cp_Len( ::lUtf8,arr[i] ) )
         ::aText[nLine+i-1] := arr[i] + cp_Substr( ::lUtf8, ::aText[nLine+i-1], ;
            cp_Len(::lUtf8,arr[i]) + 1 )
         nLine2 ++
      ELSE
         cTemp := cp_Substr( ::lUtf8, ::aText[nLine], nPos )
         ::aText[nLine] := cp_Left( ::lUtf8, ::aText[nLine], nPos-1 ) + arr[1]
         FOR i := 2 TO Len(arr)-1
            hb_AIns( ::aText, nLine+i-1, arr[i], .T. )
            nLine2 ++
         NEXT
         hb_AIns( ::aText, nLine+i-1, arr[i] + cTemp, .T. )
         nLine2 ++
      ENDIF
      nPos2 := Max( cp_Len( ::lUtf8, arr[i] ), 1 )
      ::lTextOut := .T.
      IF lChgPos
         nLineNew := nLine + i - 1
         IF nLineNew - ::nyFirst + 1 > ::y2 - ::y1 - 1
            ::nyFirst := nLineNew - 3
         ENDIF
         nPosNew := cp_Len( ::lUtf8, arr[i] ) + 1
         IF nPosNew - ::nxFirst + 1 > ::x2 - ::x1 - 1
            ::nxFirst := nPosNew - 3
         ELSEIF nPosNew < ::nxFirst
            nPosNew := 1
         ENDIF
         edi_SetPos( Self, nLineNew, nPosNew )
      ENDIF
   ELSE
      i := cp_Len( ::lUtf8, cText )
      IF lOver
         cTextOld := cp_Substr( ::lUtf8, ::aText[nLine], nPos, i )
      ENDIF
      ::aText[nLine] := cp_Left( ::lUtf8, ::aText[nLine], nPos-1 ) + cText + ;
         cp_Substr( ::lUtf8, ::aText[nLine], nPos + Iif(lOver,i,0) )
      nPos2 := nPos + cp_Len( ::lUtf8, cText ) - 1
      IF lChgPos
         ::nPos += i
      ENDIF
      IF ( nCol := ::PosToCol() ) > ::x2
         IF lChgPos
            i := nCol - ::x2
            ::nxFirst += i
            ::nPos := ::ColToPos( ::LineToRow(),::x2 )
         ENDIF
         ::lTextOut := .T.
      ELSE
         ::LineOut( ::nLine - ::nyFirst + 1 )
         IF lChgPos
            edi_SetPos( Self )
         ENDIF
      ENDIF
   ENDIF

   IF Empty( lNoUndo )
      ::Undo( nLine, nPos, nLine2, nPos2, Iif( lOver,UNDO_OP_OVER,UNDO_OP_INS ), ;
         Iif( lOver,cTextOld,Nil ) )
   ENDIF
   IF !Empty( ::oHili )
      ::oHili:UpdSource( nLine )
   ENDIF
   ::lUpdated := .T.

   RETURN Nil

METHOD DelText( nLine1, nPos1, nLine2, nPos2, lNoUndo ) CLASS TEdit

   LOCAL i, n, ncou := 0, cTextOld

   IF ::lReadOnly
      RETURN Nil
   ENDIF
   IF nLine1 == nLine2
      IF nPos1 == nPos2 .AND. nPos1 > cp_Len( ::lUtf8, ::aText[nLine1] )
         cTextOld := Chr(10)
         IF nLine1 < Len( ::aText )
            ::aText[nLine1] += ::aText[nLine1+1]
            hb_ADel( ::aText, nLine1+1, .T. )
            ::lTextOut := .T.
         ENDIF
      ELSE
         cTextOld := cp_Substr( ::lUtf8, ::aText[nLine1], nPos1, nPos2-nPos1+1 )
         ::aText[nLine1] := cp_Left( ::lUtf8, ::aText[nLine1], nPos1-1 ) + ;
            cp_Substr( ::lUtf8, ::aText[nLine1], nPos2+1 )
         ::LineOut( nLine1 -::nyFirst + 1 )
         edi_SetPos( Self, ::nLine, nPos1 )
      ENDIF
   ELSE
      IF nPos1 > 1
         cTextOld := cp_Substr( ::lUtf8, ::aText[nLine1], nPos1 ) + Chr(10)
         ::aText[nLine1] := cp_Left( ::lUtf8, ::aText[nLine1], nPos1-1 )
      ELSE
         cTextOld := ::aText[nLine1] + Chr(10)
         ::aText[nLine1] := ""
      ENDIF
      n := nLine1 + 1
      FOR i := nLine1+1 TO nLine2-1
         cTextOld += ::aText[n] + Chr(10)
         ADel( ::aText, n )
         ncou ++
      NEXT

      IF nPos2 > 1
         cTextOld += cp_Left( ::lUtf8, ::aText[n], nPos2 )
         ::aText[nLine1] += cp_Substr( ::lUtf8, ::aText[n], nPos2+1 )
      ELSE
         ::aText[nLine1] += ::aText[n]
      ENDIF
      ADel( ::aText, n )
      ncou ++

      ::aText := ASize( ::aText, Len(::aText) - ncou )
      IF !( ( i := (nLine1 - ::nyFirst + 1) ) > 0 .AND. i < (::y2-::y1+1) )
         ::nyFirst := nLine1
      ENDIF
      edi_SetPos( Self, nLine1, Max( nPos1,1 ) )
      ::lTextOut := .T.
   ENDIF

   IF Empty( lNoUndo )
      ::Undo( nLine1, nPos1, nLine2, nPos2, UNDO_OP_DEL, cTextOld )
   ENDIF
   IF !Empty( ::oHili )
      ::oHili:UpdSource( nLine1 )
   ENDIF
   ::lUpdated := .T.

   RETURN Nil

METHOD Undo( nLine1, nPos1, nLine2, nPos2, nOper, cText ) CLASS TEdit

   LOCAL alast, nOpLast := 0, arrnew, i

   IF ::lReadOnly
      RETURN Nil
   ENDIF
   IF ::nUndo>0
      alast := ::aUndo[::nUndo]
      nOpLast := alast[UNDO_OPER]
   ENDIF
   IF PCount() == 0
      IF alast != Nil
         IF nOpLast == UNDO_OP_INS
            ::DelText( alast[UNDO_LINE1], alast[UNDO_POS1], alast[UNDO_LINE2], ;
               alast[UNDO_POS2], .T. )
            ::GoTo( alast[UNDO_LINE1], alast[UNDO_POS1] )

         ELSEIF nOpLast == UNDO_OP_OVER
            ::InsText( alast[UNDO_LINE1], alast[UNDO_POS1], alast[UNDO_TEXT], ;
               .T., .F., .T. )
            ::GoTo( alast[UNDO_LINE2], alast[UNDO_POS2] )

         ELSEIF nOpLast == UNDO_OP_DEL
            ::InsText( alast[UNDO_LINE1], alast[UNDO_POS1], alast[UNDO_TEXT], ;
               .F., .F., .T. )
            ::GoTo( alast[UNDO_LINE1], alast[UNDO_POS1] )

         ELSEIF nOpLast == UNDO_OP_SHIFT
            FOR i := alast[UNDO_LINE1] TO alast[UNDO_LINE2]
               IF alast[UNDO_TEXT] > 0
                  ::aText[i] := Substr( ::aText[i], alast[UNDO_TEXT]+1 )
               ELSEIF alast[UNDO_TEXT] < 0
                  ::aText[i] := Iif( Left(::aText[i],1) == cTab, ;
                     Replicate(cTab,Abs(alast[UNDO_TEXT])), Space(Abs(alast[UNDO_TEXT])) ) + ::aText[i]
               ENDIF
            NEXT
            ::GoTo( alast[UNDO_LINE2], 1 )
            ::lTextOut := .T.

         ENDIF
         ::aUndo[::nUndo] := Nil
         ::nUndo --
         IF nOpLast == UNDO_OP_END
            DO WHILE ::nUndo > 0
               nOpLast := ::aUndo[::nUndo,UNDO_OPER]
               ::Undo()
               IF nOpLast == UNDO_OP_START
                  EXIT
               ENDIF
            ENDDO
         ENDIF
         IF ::nUndo == 0
            ::lUpdated := .F.
         ENDIF
      ENDIF

   ELSEIF nOper == UNDO_OP_INS .OR. nOper == UNDO_OP_OVER
      IF nOper == nOpLast .AND. alast[UNDO_LINE2] == nLine2 .AND. alast[UNDO_POS2] == nPos1-1 ;
         .AND. alast[UNDO_LINE1] == nLine2 .AND. nLine1 == nLine2
         alast[UNDO_POS2] := nPos2
         IF nOper == UNDO_OP_OVER
            alast[UNDO_TEXT] += cText
         ENDIF
      ELSE
         arrnew := {nLine1, nPos1, nLine2, nPos2, nOper, cText}
      ENDIF
   ELSEIF nOper == UNDO_OP_DEL
      IF nOper == nOpLast .AND. alast[UNDO_LINE2] == nLine2 .AND. ;
         ( alast[UNDO_POS2] == nPos1 .OR. alast[UNDO_POS1] == nPos1+1 ) ;
         .AND. alast[UNDO_LINE1] == nLine2 .AND. nLine1 == nLine2
         IF alast[UNDO_POS2] == nPos1    // Del
            alast[UNDO_TEXT] += cText
            alast[UNDO_POS2] := nPos2
         ELSE                            // Backspace
            alast[UNDO_TEXT] := cText + alast[UNDO_TEXT]
            alast[UNDO_POS1] := nPos2
         ENDIF
      ELSE
         arrnew := {nLine1, nPos1, nLine2, nPos2, nOper, cText}
      ENDIF

   ELSEIF nOper == UNDO_OP_SHIFT
      IF nOper == nOpLast .AND. alast[UNDO_LINE2] == nLine2 .AND. alast[UNDO_LINE1] == nLine1
         alast[UNDO_TEXT] += cText
      ELSE
         arrnew := {nLine1, nPos1, nLine2, nPos2, nOper, cText}
      ENDIF

   ELSEIF nOper == UNDO_OP_START .OR. nOper == UNDO_OP_END
      arrnew := {nLine1, nPos1, nLine2, nPos2, nOper, cText}
   ENDIF
   IF arrnew != Nil
      IF Len( ::aUndo ) < ++::nUndo
         ::aUndo := ASize( ::aUndo, Len(::aUndo) + UNDO_INC )
      ENDIF
      ::aUndo[::nUndo] := arrnew
   ENDIF

   RETURN Nil

METHOD Highlighter( oHili ) CLASS TEdit

   IF oHili == Nil
      ::oHili := Nil
   ELSE
      ::oHili := oHili:Set( Self )
   ENDIF
   RETURN Nil

METHOD OnExit() CLASS TEdit

   LOCAL i, j, s := "", nSaveHis := TEdit():options["savehis"]
   LOCAL aMacros, arr, sLine

   IF nSaveHis > 0
      IF !Empty( TEdit():aSeaHis )
         s += "[SEARCH]" + Chr(13) + Chr(10)
         FOR i := 1 TO Len( TEdit():aSeaHis )
            s += "h" + PAdl(Ltrim(Str(i)),3,'0') + "=" + TEdit():aSeaHis[i] + Chr(13) + Chr(10)
         NEXT
      ENDIF

      IF !Empty( TEdit():aReplHis )
         s += Chr(13) + Chr(10) + "[REPLACE]" + Chr(13) + Chr(10)
         FOR i := 1 TO Len( TEdit():aReplHis )
            s += "h" + PAdl(Ltrim(Str(i)),3,'0') + "=" + TEdit():aReplHis[i] + Chr(13) + Chr(10)
         NEXT
      ENDIF

      IF !Empty( TEdit():aCmdHis )
         s += Chr(13) + Chr(10) + "[COMMANDS]" + Chr(13) + Chr(10)
         FOR i := 1 TO Len( TEdit():aCmdHis )
            s += "h" + PAdl(Ltrim(Str(i)),3,'0') + "=" + TEdit():aCmdHis[i] + Chr(13) + Chr(10)
         NEXT
      ENDIF

      IF !Empty( aMacros := ASort( hb_hKeys( ::hMacros ) ) )
         s += Chr(13) + Chr(10) + "[MACRO]" + Chr(13) + Chr(10)
         FOR i := 1 TO Len( aMacros )
            arr := ::hMacros[aMacros[i]]
            IF !Empty( arr )
               sLine := Chr( aMacros[i] ) + "="
               FOR j := 1 TO Len( arr )
                  sLine += edi_KeyNToC( arr[j] ) + ","
               NEXT
               sLine += Chr(13) + Chr(10)
               s += sLine
            ENDIF
         NEXT
      ENDIF

      IF !Empty( TEdit():aEditHis )
         s += Chr(13) + Chr(10) + "[EDIT]" + Chr(13) + Chr(10)
         FOR i := 1 TO Len( TEdit():aEditHis )
            s += "h" + PAdl(Ltrim(Str(i)),3,'0') + "=" + TEdit():aEditHis[i,2] + "," + ;
               Ltrim(Str(TEdit():aEditHis[i,3])) + "," + Ltrim(Str(TEdit():aEditHis[i,4])) + "," + ;
               TEdit():aEditHis[i,1] + Chr(13) + Chr(10)
         NEXT
      ENDIF

      hb_MemoWrit( IIf( nSaveHis==1, hb_DirBase(), "" ) + "hbedit.his", s )
   ENDIF

   RETURN Nil

FUNCTION NameShortcut( cName, nWidth, cIns )

   IF Len( cName ) > nWidth
      cIns := Iif( cIns==Nil, "...", cIns )
      IF nWidth > Len(cIns) + 3
         cName := Left( cName,3 ) + cIns + Substr( cName, Len(cName)-(nWidth-3-Len(cIns)) )
      ELSE
         cName := ""
      ENDIF
   ENDIF

   RETURN cName

STATIC FUNCTION Text2cb( oEdit )

   LOCAL s := "", i, j, nby1, nby2, nbx1, nbx2, nvx1, nvx2

   IF oEdit:nby1 >= 0 .AND. oEdit:nby2 >= 0
      IF oEdit:nby1 < oEdit:nby2 .OR. ( oEdit:nby1 == oEdit:nby2 .AND. oEdit:nbx1 < oEdit:nbx2 )
         nby1 := oEdit:nby1; nbx1 := oEdit:nbx1; nby2 := oEdit:nby2; nbx2 := oEdit:nbx2
      ELSE
         nby1 := oEdit:nby2; nbx1 := oEdit:nbx2; nby2 := oEdit:nby1; nbx2 := oEdit:nbx1
      ENDIF
      IF nby1 == nby2
         s := cp_Substr( oEdit:lUtf8, oEdit:aText[nby1], nbx1, nbx2-nbx1 )
      ELSE
         FOR i := nby1 TO nby2
            IF oEdit:nSeleMode == 2
               nvx1 := nbx1; nvx2 := nbx2
               IF i != nby1
                  nvx1 := oEdit:ColToPos( oEdit:LineToRow(i), oEdit:PosToCol( nby1,nbx1 ) )
               ENDIF
               IF i != nby2
                  nvx2 := oEdit:ColToPos( oEdit:LineToRow(i), oEdit:PosToCol( nby2,nbx2 ) )
               ENDIF
               IF nvx1 > nvx2
                  j := nvx1; nvx1 := nvx2; nvx2 := j
               ENDIF
               s += cp_Substr( oEdit:lUtf8, oEdit:aText[i], nvx1, nvx2-nvx1 ) + Chr(10)
            ELSE
               IF i == nby1
                  s += cp_Substr( oEdit:lUtf8, oEdit:aText[i], nbx1 ) + Chr(10)
               ELSEIF i == nby2
                  s += cp_Left( oEdit:lUtf8, oEdit:aText[i], nbx2-1 )
               ELSE
                  s += oEdit:aText[i] + oEdit:cEol
               ENDIF
            ENDIF
         NEXT
      ENDIF
   ENDIF

   RETURN Iif( oEdit:lTabs, Strtran(s,cTabStr,cTab), s )

FUNCTION cb2Text( oEdit, lToText )

   LOCAL arr
   LOCAL i, lMulti := .F., s := hb_gtInfo( HB_GTI_CLIPBOARDDATA ), lVert, nPos

   IF !( s == TEdit():aCBoards[1,1] )
      TEdit():aCBoards[1,1] := s
      TEdit():aCBoards[1,2] := Nil
      TEdit():aCBoards[1,3] := Nil
   ENDIF
   lVert := !Empty( TEdit():aCBoards[1,3] )
   FOR i := 2 TO MAX_CBOARDS
      IF !Empty( TEdit():aCBoards[i,1] )
         lMulti := .T.
         EXIT
      ENDIF
   NEXT

   IF lMulti
      FOR i := 1 TO MAX_CBOARDS
         aMenu_CB[i,1] := cp_Left( oEdit:lUtf8, TEdit():aCBoards[i,1], 32 )
         IF !Empty( TEdit():aCBoards[i,2] ) .AND. !( TEdit():aCBoards[i,2] == oEdit:cp )
            aMenu_CB[i,1] := hb_Translate( aMenu_CB[i,1], TEdit():aCBoards[i,2], oEdit:cp )
         ENDIF
      NEXT
      IF !Empty( i := FMenu( oEdit, aMenu_CB, 2, 6 ) )
         s := TEdit():aCBoards[i,1]
         lVert := !Empty( TEdit():aCBoards[i,3] )
         IF !Empty( TEdit():aCBoards[i,2] ) .AND. !( TEdit():aCBoards[i,2] == oEdit:cp )
            s := hb_Translate( s, TEdit():aCBoards[i,2], oEdit:cp )
         ENDIF
      ENDIF
      oEdit:lTextOut := .T.
   ENDIF

   IF Empty( lToText )
      RETURN s
   ELSE
      IF oEdit:lTabs
         s := Strtran( s, cTab, cTabStr )
      ENDIF
      IF Chr(13) $ s
         s := Strtran( s, Chr(13), "" )
      ENDIF

      IF lVert
         oEdit:Undo( oEdit:nLine, oEdit:nPos,,, UNDO_OP_START )
         arr := hb_ATokens( s, Chr(10) )
         nPos := oEdit:nPos
         FOR i := 1 TO Len( arr ) - 1
            oEdit:InsText( oEdit:nLine+i-1, ;
               oEdit:ColToPos( oEdit:LineToRow(oEdit:nLine+i-1), oEdit:PosToCol( oEdit:nLine,nPos ) ), arr[i], .F., .F. )
            oEdit:nPos := nPos
         NEXT
         oEdit:Undo( oEdit:nLine, oEdit:nPos,,, UNDO_OP_END )
         edi_SetPos( oEdit )
         oEdit:lTextOut := .T.
      ELSE
         oEdit:InsText( oEdit:nLine, oEdit:nPos, s, .F., .T. )
      ENDIF
   ENDIF

   RETURN Nil

STATIC FUNCTION cbDele( oEdit )

   LOCAL nby1, nby2, nbx1, nbx2, i, j, nvx1, nvx2

   IF !oEdit:lReadOnly .AND. oEdit:nby1 >= 0 .AND. oEdit:nby2 >= 0
      IF oEdit:nby1 < oEdit:nby2 .OR. ( oEdit:nby1 == oEdit:nby2 .AND. oEdit:nbx1 < oEdit:nbx2 )
         nby1 := oEdit:nby1; nbx1 := oEdit:nbx1; nby2 := oEdit:nby2; nbx2 := oEdit:nbx2
      ELSE
         nby1 := oEdit:nby2; nbx1 := oEdit:nbx2; nby2 := oEdit:nby1; nbx2 := oEdit:nbx1
      ENDIF
      oEdit:nby1 := oEdit:nby2 := -1
      IF oEdit:nSeleMode == 2
         oEdit:Undo( nby1, nbx1, nby2, nbx2, UNDO_OP_START )
         FOR i := nby1 TO nby2
            nvx1 := nbx1; nvx2 := nbx2
            IF i != nby1
               nvx1 := oEdit:ColToPos( oEdit:LineToRow(i), oEdit:PosToCol( nby1,nbx1 ) )
            ENDIF
            IF i != nby2
               nvx2 := oEdit:ColToPos( oEdit:LineToRow(i), oEdit:PosToCol( nby2,nbx2 ) )
            ENDIF
            IF nvx1 > nvx2
               j := nvx1; nvx1 := nvx2; nvx2 := j
            ENDIF
            oEdit:DelText( i, nvx1, i, Max(nvx2-1,1) )
         NEXT
         oEdit:Undo( nby1, nbx1, nby2, nbx2, UNDO_OP_END )
      ELSE
         oEdit:DelText( nby1, nbx1, nby2, Max(nbx2-1,1) )
      ENDIF
   ENDIF
   RETURN Nil

FUNCTION edi_ReadIni( xIni )

   LOCAL hIni, aIni, nSect, aSect, cSect, cLang, arr, arr1, s, n, i, nPos, cTemp, nTemp
   LOCAL lIncSea := .F., lAutoIndent := .F., lSyntax := .T., lTrimSpaces := .F., lTab2Spaces := .F.
   LOCAL nSaveHis := 1, ncmdhis := 20, nseahis := 20, nedithis := 20, nEol := 0
   LOCAL hHili
   LOCAL aHiliOpt := { "keywords1","keywords2","keywords3","keywords4","quotes","scomm","startline","mcomm","block" }

   TEdit():lReadIni := .T.
   hIni := Iif( Valtype( xIni ) == "C", edi_iniRead( xIni ), xIni )

   SetBlink( .F. )
   hb_gtInfo( HB_GTI_COMPATBUFFER, .F. )
   aLangs := hb_Hash()

   IF !Empty( hIni )
      aIni := hb_hKeys( hIni )
      FOR nSect := 1 TO Len( aIni )
         IF Upper(aIni[nSect]) == "OPTIONS"
            IF !Empty( aSect := hIni[ aIni[nSect] ] )
               hb_hCaseMatch( aSect, .F. )
               IF hb_hHaskey( aSect, cTemp := "defmode" ) .AND. !Empty( cTemp := aSect[ cTemp ] )
                  TEdit():nDefMode := Iif( (n := Val(cTemp)) < 2 .AND. n >= -1, n, 0 )
               ENDIF
               IF hb_hHaskey( aSect, cTemp := "incsearch" ) .AND. !Empty( cTemp := aSect[ cTemp ] )
                  lIncSea := ( Lower(cTemp) == "on" )
               ENDIF
               IF hb_hHaskey( aSect, cTemp := "autoindent" ) .AND. !Empty( cTemp := aSect[ cTemp ] )
                  lAutoIndent := ( Lower(cTemp) == "on" )
               ENDIF
               IF hb_hHaskey( aSect, cTemp := "trimspaces" ) .AND. !Empty( cTemp := aSect[ cTemp ] )
                  lTrimSpaces := ( Lower(cTemp) == "on" )
               ENDIF
               IF hb_hHaskey( aSect, cTemp := "syntax" ) .AND. !Empty( cTemp := aSect[ cTemp ] )
                  lSyntax := ( Lower(cTemp) == "on" )
               ENDIF
               IF hb_hHaskey( aSect, cTemp := "savehis" ) .AND. !Empty( cTemp := aSect[ cTemp ] )
                  nSaveHis := Val(cTemp)
                  IF nSaveHis < 0 .OR. nSaveHis > 2
                     nSaveHis := 1
                  ENDIF
               ENDIF
               IF hb_hHaskey( aSect, cTemp := "cmdhismax" ) .AND. !Empty( cTemp := aSect[ cTemp ] )
                  ncmdhis :=  Val(cTemp)
               ENDIF
               IF hb_hHaskey( aSect, cTemp := "seahismax" ) .AND. !Empty( cTemp := aSect[ cTemp ] )
                  nseahis :=  Val(cTemp)
               ENDIF
               IF hb_hHaskey( aSect, cTemp := "edithismax" ) .AND. !Empty( cTemp := aSect[ cTemp ] )
                  nedithis :=  Val(cTemp)
               ENDIF
               IF hb_hHaskey( aSect, cTemp := "eol" ) .AND. !Empty( cTemp := aSect[ cTemp ] )
                  nEol := Val(cTemp)
               ENDIF
               IF hb_hHaskey( aSect, cTemp := "langmap_cp" ) .AND. !Empty( cTemp := aSect[ cTemp ] )
                  IF hb_cdpExists( cTemp )
                     cLangMapCP := cTemp
                  ENDIF
               ENDIF
               IF hb_hHaskey( aSect, cTemp := "langmap_upper" ) .AND. !Empty( cTemp := aSect[ cTemp ] )
                  aLangMapUpper := hb_aTokens( cTemp )
               ENDIF
               IF hb_hHaskey( aSect, cTemp := "langmap_lower" ) .AND. !Empty( cTemp := aSect[ cTemp ] )
                  aLangMapLower := hb_aTokens( cTemp )
               ENDIF
               IF hb_hHaskey( aSect, cTemp := "colormain" ) .AND. !Empty( cTemp := aSect[ cTemp ] )
                  TEdit():cColor := cTemp
               ENDIF
               IF hb_hHaskey( aSect, cTemp := "colorsel" ) .AND. !Empty( cTemp := aSect[ cTemp ] )
                  TEdit():cColorSel := cTemp
               ENDIF
               IF hb_hHaskey( aSect, cTemp := "colorpane" ) .AND. !Empty( cTemp := aSect[ cTemp ] )
                  TEdit():cColorPane := cTemp
               ENDIF
               IF hb_hHaskey( aSect, cTemp := "colorbra" ) .AND. !Empty( cTemp := aSect[ cTemp ] )
                  TEdit():cColorbra := cTemp
               ENDIF
               IF hb_hHaskey( aSect, cTemp := "keymap" ) .AND. !Empty( cTemp := aSect[ cTemp ] )
                  arr := hb_aTokens( cTemp, ",", .T. )
                  hKeyMap := hb_Hash()
                  FOR i := 1 TO Len( arr )
                     IF ( nPos := At( "=>", arr[i] ) ) > 0 .AND. ;
                        ( nTemp := edi_KeyCToN(Left(arr[i],nPos-1)) ) != Nil .AND. ;
                        ( nPos := edi_KeyCToN(Substr(arr[i],nPos+2)) ) != Nil
                        hKeyMap[nTemp] := nPos
                     ENDIF
                  NEXT
               ENDIF
               IF hb_hHaskey( aSect, cTemp := "tablen" ) .AND. !Empty( cTemp := aSect[ cTemp ] )
                  TEdit():nTabLen := Val( cTemp )
               ENDIF
               IF hb_hHaskey( aSect, cTemp := "tabtospaces" ) .AND. !Empty( cTemp := aSect[ cTemp ] )
                  lTab2Spaces := ( Lower(cTemp) == "on" )
               ENDIF
            ENDIF

         ELSEIF Upper(aIni[nSect]) == "CODEPAGES"
            IF !Empty( aSect := hIni[ aIni[nSect] ] )
               hb_hCaseMatch( aSect, .F. )
               arr := ASort( hb_hKeys( aSect ) )
               TEdit():aCPages := Array( Len( arr ) )
               FOR i := 1 TO Len( arr )
                  TEdit():aCPages[i] := aSect[ arr[i] ]
               NEXT
            ENDIF

         ELSEIF Upper(aIni[nSect]) == "PLUGINS"
            IF !Empty( aSect := hIni[ aIni[nSect] ] )
               hb_hCaseMatch( aSect, .F. )
               arr := hb_hKeys( aSect )
               TEdit():aPlugins := {}
               FOR i := 1 TO Len( arr )
                  s := aSect[ arr[i] ]
                  IF ( n := At( ",", s ) ) > 0
                     cTemp := AllTrim( Left( s,n-1 ) )
                     IF !Empty( edi_FindPath( "plugins" + hb_ps() + cTemp ) )
                        s := Substr( s, n+1 )
                        IF ( n := At( ",", s ) ) > 0
                           Aadd( TEdit():aPlugins, { cTemp, Substr( s, n+1 ), AllTrim( Left( s,n-1 ) ), Nil } )
                        ENDIF
                     ENDIF
                  ENDIF
               NEXT
            ENDIF
         ELSEIF Upper(aIni[nSect]) == "HILIGHT"
            IF !Empty( aSect := hIni[ aIni[nSect] ] )
               hb_hCaseMatch( aSect, .F. )
               arr := hb_hKeys( aSect )
               FOR i := 1 TO Len( arr )
                  IF ( n := Ascan( aHiliOpt, arr[i] ) ) > 0
                     TEdit():aHiliAttrs[n] := aSect[ arr[i] ]
                  ENDIF
               NEXT
            ENDIF
         ELSEIF Left( Upper(aIni[nSect]),5 ) == "LANG_"
            IF !Empty( aSect := hIni[ aIni[nSect] ] )
               hb_hCaseMatch( aSect, .F. )
               cLang := Lower( Substr(aIni[nSect],6) )
               hHili := aLangs[ cLang ] := hb_hash()
               hHili["colors"] := Array(Len(aHiliOpt))
               hHili["bra"] := .F.
               arr := hb_hKeys( aSect )
               FOR i := 1 TO Len( arr )
                  IF !Empty( cTemp := aSect[ arr[i] ] )
                     IF ( n := Ascan( aHiliOpt, arr[i] ) ) > 0
                        s := aSect[ arr[i] ]
                        IF ( nPos := At( ",",s ) ) > 0
                           hHili["colors"][n] := Trim(Left(s,nPos-1))
                           s := Ltrim( Substr( s, nPos+1 ) )
                        ENDIF
                        hHili[arr[i]] := s
                     ELSEIF arr[i] == "ext"
                        AAdd( aLangExten, { cLang, cTemp } )
                     ELSEIF arr[i] == "case"
                        hHili[arr[i]] := ( Lower(cTemp) == "on" )
                     ELSEIF arr[i] == "plugin"
                        hHili["plugin"] := cTemp
                     ELSEIF arr[i] == "brackets"
                        hHili["bra"] := ( Lower(cTemp) == "on" )
                     ENDIF
                  ENDIF
               NEXT
            ENDIF
         ENDIF
      NEXT
   ENDIF

   TEdit():cpInit := hb_cdpSelect()
   TEdit():options["incsearch"]  := lIncSea
   TEdit():options["savehis"]    := nSaveHis
   TEdit():options["cmdhismax"]  := ncmdhis
   TEdit():options["seahismax"]  := nseahis
   TEdit():options["eol"]        := nEol
   TEdit():options["trimspaces"] := lTrimSpaces
   TEdit():options["tabtospaces"] := lTab2Spaces
   TEdit():options["edithismax"] := nedithis
   TEdit():options["autoindent"] := lAutoIndent
   TEdit():options["syntax"] := lSyntax
   cTabStr := Space( TEdit():nTablen )

   IF Empty( TEdit():aCPages )
      TEdit():aCPages := { "RU866", "RU1251", "UTF8" }
   ENDIF
   TEdit():aCBoards := Array( MAX_CBOARDS,3 )
   FOR i := 1 TO MAX_CBOARDS
      TEdit():aCBoards[i,1] := TEdit():aCBoards[i,2] := ""
   NEXT
   TEdit():hMacros := hb_Hash()

   IF nSaveHis > 0
      hIni := edi_iniRead( Iif( nSaveHis==1, hb_DirBase(), "" ) + "hbedit.his" )
      IF !Empty( hIni )
         hb_hCaseMatch( hIni, .F. )
         IF hb_hHaskey( hIni, cTemp := "SEARCH" ) .AND. !Empty( aSect := hIni[ cTemp ] )
            arr := ASort( hb_hKeys( aSect ) )
            TEdit():aSeaHis := Array( Len(arr) )
            FOR i := 1 TO Len(arr)
               TEdit():aSeaHis[i] := aSect[ arr[i] ]
            NEXT
         ENDIF
         IF hb_hHaskey( hIni, cTemp := "REPLACE" ) .AND. !Empty( aSect := hIni[ cTemp ] )
            arr := ASort( hb_hKeys( aSect ) )
            TEdit():aReplHis := Array( Len(arr) )
            FOR i := 1 TO Len(arr)
               TEdit():aReplHis[i] := aSect[ arr[i] ]
            NEXT
         ENDIF
         IF hb_hHaskey( hIni, cTemp := "COMMANDS" ) .AND. !Empty( aSect := hIni[ cTemp ] )
            arr := ASort( hb_hKeys( aSect ) )
            TEdit():aCmdHis := Array( Len(arr) )
            FOR i := 1 TO Len(arr)
               TEdit():aCmdHis[i] := aSect[ arr[i] ]
            NEXT
         ENDIF
         IF hb_hHaskey( hIni, cTemp := "MACRO" ) .AND. !Empty( aSect := hIni[ cTemp ] )
            arr := ASort( hb_hKeys( aSect ) )
            FOR i := 1 TO Len(arr)
               arr1 := {}
               s := aSect[ arr[i] ]
               nPos := 1
               DO WHILE ( n := hb_At( ",", s, nPos ) ) > 0
                  IF n-nPos == 0
                     AAdd( arr1, edi_KeyCToN( "," ) )
                  ELSE
                     cTemp := Substr( s, nPos, n-nPos )
                     AAdd( arr1, edi_KeyCToN( cTemp ) )
                  ENDIF
                  nPos := n + 1
               ENDDO
               TEdit():hMacros[Asc(arr[i])] := arr1
            NEXT
         ENDIF
         IF hb_hHaskey( hIni, cTemp := "EDIT" ) .AND. !Empty( aSect := hIni[ cTemp ] )
            arr := ASort( hb_hKeys( aSect ) )
            TEdit():aEditHis := Array( Len(arr) )
            FOR i := 1 TO Len(arr)
               arr1 := hb_ATokens( aSect[ arr[i] ], "," )
               IF Len(arr1) < 4
                  TEdit():aEditHis[i] := { "ru866", 1, 1, "err" }
               ELSE
                  s := Upper( arr1[1] )
                  IF Ascan( TEdit():aCPages, s ) == 0
                     s := TEdit():aCPages[1]
                  ENDIF
                  arr1[2] := Max( 1, Val(arr1[2]) )
                  arr1[3] := Max( 1, Val(arr1[3]) )
                  TEdit():aEditHis[i] := { Ltrim(arr1[4]), s, arr1[2], arr1[3] }
               ENDIF
            NEXT
         ENDIF
      ENDIF
   ENDIF

   RETURN Nil

FUNCTION mnu_Help( oEdit )

   LOCAL cFullPath := edi_FindPath( "hbedit.help" ), oHelp

   IF !Empty( cFullPath )
      oHelp := TEdit():New( MemoRead( cFullPath ), "$Help", ;
         oEdit:aRectFull[1], oEdit:aRectFull[2], oEdit:aRectFull[3], oEdit:aRectFull[4] )

      oHelp:lReadOnly := .T.
      oHelp:lCtrlTab  := .F.
      oHelp:Edit()
   ENDIF

   RETURN Nil

FUNCTION mnu_Exit( oEdit )

   LOCAL nRes := 2

   IF oEdit:lUpdated
      nRes := edi_Alert( "File has been modified. Save?", "Yes", "No", "Cancel" )
   ENDIF
   IF nRes == 1 .OR. nRes == 2
      IF nRes == 1
         IF !oEdit:Save()
            RETURN .F.
         ENDIF
      ENDIF
      oEdit:lShow := .F.
      oEdit:lClose := .T.
   ELSE
      edi_SetPos( oEdit )
   ENDIF
   RETURN .T.

FUNCTION mnu_CPages( oEdit, aXY )

   LOCAL iRes

   IF !Empty( iRes := FMenu( oEdit, oEdit:aCPages, aXY[1], aXY[2] ) )
      oEdit:cp := oEdit:aCPages[iRes]
      hb_cdpSelect( oEdit:cp )
      oEdit:lUtf8 := ( Lower(oEdit:cp) == "utf8" )
      oEdit:TextOut()
   ENDIF

   RETURN Nil

FUNCTION mnu_Syntax( oEdit, aXY )

   LOCAL aMenu := { {"Syntax Off",@mnu_SyntaxOn(),Nil} }, i, arr := hb_hKeys( aLangs )

   FOR i := 1 TO Len( arr )
      AAdd( aMenu, {arr[i], @mnu_SyntaxOn(), arr[i]} )
   NEXT

   FMenu( oEdit, aMenu, aXY[1], aXY[2] )

   RETURN Nil

FUNCTION mnu_SyntaxOn( oEdit, cLang )

   oEdit:Highlighter( Iif( Empty(cLang), Nil, Hili():New( aLangs[cLang] ) ) )
   oEdit:cSyntaxType := cLang

   RETURN Nil

FUNCTION mnu_Windows( oEdit, aXY, n )

   LOCAL aMenu := { {"Switch window",Nil,Nil,"Ctrl-w,w"}, ;
      {"Add window horizontally",Nil,Nil,"Ctrl-w,s"}, ;
      {"Add window vertically",Nil,Nil,"Ctrl-w,v"} }
   LOCAL i, o
   //STATIC cForbid := "Forbidden for a child window"

   IF n == Nil
      n := FMenu( oEdit, aMenu, aXY[1], aXY[2] )
   ENDIF
   IF n == 1
      mnu_ToBuf( oEdit, edi_FindWindow( oEdit, .T. ) )
   ELSEIF n == 2
      //IF !Empty( oEdit:oParent )
      //   edi_Alert( cForbid )
      //   oEdit:GoTo( ,1 )
      //ELSE
         o := edi_AddWindow( oEdit, MemoRead(oEdit:cFileName), oEdit:cFileName, 2, Int( (oEdit:y2-oEdit:y1)/2 ) )
         o:lReadOnly := .T.
      //ENDIF
   ELSEIF n == 3
      //IF !Empty( oEdit:oParent )
      //   edi_Alert( cForbid )
      //   oEdit:GoTo( ,1 )
      //ELSE
         o := edi_AddWindow( oEdit, MemoRead(oEdit:cFileName), oEdit:cFileName, 3, Int( (oEdit:x2-oEdit:x1)/2 ) )
         o:lReadOnly := .T.
      //ENDIF
   ENDIF

   RETURN Nil

FUNCTION mnu_Buffers( oEdit, aXY )

   LOCAL aMenu := { }, i, nCurr := 1

   FOR i := 1 TO Len( oEdit:aWindows )
      IF oEdit:aWindows[i] == oEdit
         nCurr := i
      ENDIF
      AAdd( aMenu, {NameShortcut(oEdit:aWindows[i]:cFileName,30,'~'),@mnu_ToBuf(),i} )
   NEXT
   IF !Empty( oEdit:cLauncher )
      AAdd( aMenu, {oEdit:cLauncher,@mnu_ToBuf(),0} )
   ENDIF

   FMenu( oEdit, aMenu, aXY[1], aXY[2],,,,, nCurr )

   RETURN Nil

FUNCTION mnu_ToBuf( oEdit, x )

   oEdit:lShow := .F.
   IF Valtype( x ) == "O"
      oEdit:nCurr := Ascan( oEdit:aWindows, {|o|o==x} )
   ELSEIF Valtype( x ) == "N"
      oEdit:nCurr := x
   ENDIF

   RETURN Nil

FUNCTION mnu_Save( oEdit, lAs )

   LOCAL cFileName, cPath

   IF !Empty( lAs )
      oEdit:lTextOut := .T.
      IF Empty( cFileName := edi_SaveDlg( oEdit ) )
         RETURN Nil
      ENDIF
      IF !Empty( cFileName ) .AND. Empty( hb_fnameDir(cFileName) ) ;
            .AND. !Empty( cPath := hb_fnameDir(oEdit:cFileName) )
         cFileName := cPath + cFileName
      ENDIF
   ENDIF

   oEdit:Save( cFileName )

   RETURN Nil

FUNCTION mnu_F3( oEdit, nSeleMode )

   LOCAL i

   nSeleMode := Iif( Empty( nSeleMode ), 0, nSeleMode )

   IF oEdit:nby1 >= 0 .AND. oEdit:nby2 >= 0
      oEdit:lF3 := .T.
   ENDIF

   IF !oEdit:lF3
      oEdit:nby1 := oEdit:nLine
      IF nSeleMode == 1
         oEdit:nbx1 := 1
         oEdit:nby2 := oEdit:nLine
         oEdit:nbx2 := cp_Len( oEdit:lUtf8, oEdit:aText[oEdit:nLine] ) + 1
      ELSE
         oEdit:nbx1 := oEdit:nPos
         oEdit:nby2 := oEdit:nbx2 := -1
      ENDIF
      oEdit:nSeleMode := nSeleMode
   ENDIF
   oEdit:lF3 := !oEdit:lF3
   IF !oEdit:lF3
      IF Empty( aMenu_CB )
         aMenu_CB := Array(MAX_CBOARDS)
         FOR i := 1 TO MAX_CBOARDS
            aMenu_CB[i] := { Nil,, i }
         NEXT
      ENDIF

      TEdit():aCBoards[1,1] := hb_gtInfo( HB_GTI_CLIPBOARDDATA )
      TEdit():aCBoards[1,2] := Nil
      TEdit():aCBoards[1,3] := Nil
      FOR i := 1 TO MAX_CBOARDS
         aMenu_CB[i,1] := cp_Left( oEdit:lUtf8, TEdit():aCBoards[i,1], 32 )
         IF !Empty( TEdit():aCBoards[i,2] ) .AND. !( TEdit():aCBoards[i,2] == oEdit:cp )
            aMenu_CB[i,1] := hb_Translate( aMenu_CB[i,1], TEdit():aCBoards[i,2], oEdit:cp )
         ENDIF
      NEXT
      IF !Empty( i := FMenu( oEdit, aMenu_CB, 2, 6 ) )
         TEdit():aCBoards[i,1] := Text2cb( oEdit )
         TEdit():aCBoards[i,2] := oEdit:cp
         TEdit():aCBoards[1,3] := Iif( oEdit:nSeleMode==2,.T.,Nil )
         IF i == 1
            hb_gtInfo( HB_GTI_CLIPBOARDDATA, TEdit():aCBoards[1,1] )
         ENDIF
      ENDIF
      oEdit:lTextOut := .T.
   ENDIF

   RETURN Nil

FUNCTION mnu_F4( oEdit, aXY )

   LOCAL aMenu := { {"New file",@mnu_NewBuf(),Nil,"Shift-F4"}, {"Open file",@mnu_OpenFile(),Nil,"Ctrl-F4"} }, i

   FOR i := 1 TO Len( oEdit:aEditHis )
      AAdd( aMenu, { NameShortcut(hb_Translate(oEdit:aEditHis[i,1],"UTF8"), 36,'~'), ;
         @mnu_OpenRecent(),i } )
   NEXT

   FMenu( oEdit, aMenu, aXY[1], aXY[2] )

   RETURN Nil

FUNCTION mnu_OpenRecent( oEdit, n )

   LOCAL cFileName := hb_Translate( oEdit:aEditHis[n,1], "UTF8", oEdit:cpInit )

   //RETURN mnu_NewBuf( oEdit, cFileName )
   RETURN mnu_OpenFile( oEdit, cFileName )

FUNCTION mnu_NewBuf( oEdit, cFileName )

   LOCAL oNew, s, j, cText

   IF !Empty( cFileName )
      s := Lower( cFileName )
      IF ( j := Ascan( oEdit:aWindows, {|o|Lower(o:cFileName)==s} ) ) > 0
         mnu_ToBuf( oEdit, j )
         RETURN oEdit:aWindows[j]
      ENDIF
      IF File( cFileName )
         cText := Memoread( cFileName )
      ELSE
         edi_Alert( "File not found" )
         RETURN Nil
      ENDIF
   ENDIF

   hb_cdpSelect( oEdit:cpInit )
   oNew := TEdit():New( cText, cFileName, oEdit:aRectFull[1], oEdit:aRectFull[2], oEdit:aRectFull[3], oEdit:aRectFull[4] )
   oNew:funSave := oEdit:funSave
   hb_cdpSelect( oEdit:cp )
   oEdit:lShow := .F.

   IF ( !Empty( oEdit:aText ) .AND. !Empty( oEdit:aText[1] ) ) ;
         .OR. oEdit:lUpdated .OR. !Empty( oEdit:cFilename )
      oEdit:nCurr := Len( oEdit:aWindows )
   ELSE
      oEdit:lClose := .T.
      oEdit:nCurr := Len( oEdit:aWindows ) - 1
   ENDIF

   RETURN oNew

FUNCTION mnu_OpenFile( oEdit, cFile )

   LOCAL cScBuf := Savescreen( 09, 10, 15, 72 )
   LOCAL oldc := SetColor( "N/W,W+/BG" ), cName, nRes, oNew
   LOCAL aGets := { {11,12,0,Iif(Empty(cFile),"",cFile),56}, ;
      {11,68,2,"[^]",3,"N/W","W+/RB",{||mnu_FileList(oEdit,aGets[1])}}, ;
      {12,13,1,.F.,1}, {12,31,1,.F.,1}, ;
      {14,26,2,"[Open]",10,"N/W","W+/BG",{||__KeyBoard(Chr(K_ENTER))}}, ;
      {14,46,2,"[Cancel]",10,"N/W","W+/BG",{||__KeyBoard(Chr(K_ESC))}} }

   hb_cdpSelect( "RU866" )
   @ 09, 10, 15, 72 BOX "�Ŀ����� "
   @ 13, 20 SAY "�"
   @ 13, 60 SAY "�"
   @ 13, 11 TO 13, 71
   hb_cdpSelect( oEdit:cp )
   @ 10, 12 SAY "Open file"
   @ 12, 12 SAY "[ ] ReadOnly"
   @ 12, 30 SAY "[ ] In a current window"
   SetColor( "W+/BG" )

   IF ( nRes := edi_READ( aGets ) ) > 0 .AND. nRes < Len(aGets)
      IF !Empty( cName := aGets[1,4] ) .AND. File( cName )
         IF aGets[4,4]
            IF oEdit:lUpdated
               IF mnu_Exit( oEdit )
                  oEdit:lShow := .T.
                  oEdit:lClose := .F.
               ELSE
                  SetColor( oldc )
                  edi_SetPos( oEdit )
                  RETURN Nil
               ENDIF
            ENDIF
            oEdit:SetText( MemoRead( cName ), cName )
            oEdit:lReadOnly := aGets[3,4]
         ELSE
            oNew := mnu_NewBuf( oEdit, cName )
            oNew:lReadOnly := aGets[3,4]
         ENDIF
      ENDIF
   ENDIF

   Restscreen( 09, 10, 15, 72, cScBuf )
   SetColor( oldc )
   edi_SetPos( oEdit )

   RETURN Nil

FUNCTION mnu_FileList( oEdit, aGet )

   LOCAL cPrefix, xFileName, i, cDir, ny2 := oEdit:aRectFull[3]-2
   LOCAL cScBuf := Savescreen( 12, 12, ny2, 67 )

#ifdef __PLATFORM__UNIX
   cPrefix := '/'
#else
   cPrefix := hb_curDrive() + ':\'
#endif

   cDir := Iif( Empty(cLastDir), cPrefix + CurDir() + hb_ps(), cLastDir )
   xFileName := edi_SeleFile( oEdit, cDir, 12, 12, ny2, 67 )
   Restscreen( 12, 12, ny2, 67, cScBuf )

   IF !Empty( xFileName )
      IF Valtype( xFileName ) == "A"
         IF Len( xFileName ) == 1
            xFileName := xFileName[1]
         ELSE
            FOR i := 1 TO Len( xFileName )
               mnu_NewBuf( oEdit, xFileName[i] )
            NEXT
            __KeyBoard( Chr(K_ESC) )
            RETURN Nil
         ENDIF
      ENDIF

      cLastDir := hb_fnameDir( xFileName )
      aGet[4] := xFileName
      ShowGetItem( aGet, .F., oEdit:lUtf8 )
   ENDIF

   RETURN Nil

FUNCTION mnu_Sea_goto( oEdit, aXY )

   LOCAL aMenu := { {"Search",@mnu_Search(),Nil,"F7"}, {"Next",@mnu_SeaNext(),.T.,"Shift-F7"}, ;
      {"Previous",@mnu_SeaNext(),.F.,"Alt-F7"}, {"Replace",@mnu_SeaAndRepl(),Nil,"Ctrl-F7"}, ;
      {"Go to",@mnu_GoTo(),Nil,"Alt-F8"}, {"Back",@mnu_Back(),Nil,"Alt-B"} }

   FMenu( oEdit, aMenu, aXY[1], aXY[2] )

   RETURN Nil

FUNCTION mnu_Back( oEdit )
   RETURN oEdit:GoTo( oEdit:nLineBack, oEdit:nPosBack )

FUNCTION mnu_Search( oEdit )

   LOCAL cScBuf := Savescreen( 09, 20, 16, 60 )
   LOCAL oldc := SetColor( "N/W,N/W,,N+/BG,N/W" ), nRes, i
   LOCAL aGets := { {11,22,0,"",33,"W+/BG","W+/BG"}, ;
      {11,55,2,"[^]",3,"N/W","W+/RB",{||mnu_SeaHist(oEdit,aGets[1])}}, ;
      {12,23,1,.F.,1}, {12,43,1,.F.,1}, {13,23,1,.F.,1}, {13,43,1,.F.,1}, ;
      {15,25,2,"[Search]",10,"N/W","W+/BG",{||__KeyBoard(Chr(K_ENTER))}}, ;
      {15,40,2,"[Cancel]",10,"N/W","W+/BG",{||__KeyBoard(Chr(K_ESC))}} }
   LOCAL cSearch, lCase, lBack := .F., lWord, lRegex, cs_utf8
   LOCAL ny := oEdit:nLine, nx := oEdit:nPos

   hb_cdpSelect( "RU866" )
   @ 09, 20, 16, 60 BOX "�Ŀ����� "
   @ 14, 20 SAY "�"
   @ 14, 60 SAY "�"
   @ 14, 21 TO 14, 59
   hb_cdpSelect( oEdit:cp )

   @ 10,22 SAY "Search for"
   @ 12, 22 SAY "[ ] Case sensitive"
   @ 12, 42 SAY "[ ] Backward"
   @ 13, 22 SAY "[ ] Whole word"
   @ 13, 42 SAY "[ ] Regular expr."

   IF !Empty( TEdit():aSeaHis )
      aGets[1,4] := TEdit():aSeaHis[1]
      aGets[3,4] := lCase_Sea
      aGets[6,4] := lRegex_Sea
   ENDIF

   IF ( nRes := edi_READ( aGets ) ) > 0 .AND. nRes < Len(aGets)
      cSearch := Trim( aGets[1,4] )
      lCase := aGets[3,4]
      lBack := aGets[4,4]
      lWord := aGets[5,4]
      lRegex := aGets[6,4]
      cs_utf8 := hb_Translate( cSearch,, "UTF8" )
      IF ( i := Ascan( TEdit():aSeaHis, {|cs|cs==cs_utf8} ) ) > 0
         ADel( TEdit():aSeaHis, i )
         hb_AIns( TEdit():aSeaHis, 1, cs_utf8, .F. )
      ELSE
         hb_AIns( TEdit():aSeaHis, 1, cs_utf8, Len(TEdit():aSeaHis)<hb_hGetDef(TEdit():options,"seahismax",10) )
      ENDIF
      IF oEdit:Search( cSearch, lCase_Sea := lCase, !lBack, lWord_Sea := lWord, lRegex_Sea := lRegex, @ny, @nx )
         oEdit:GoTo( ny, nx, 0 )
      ELSE
         edi_Alert( "String is not found:;" + cSearch )
         oEdit:lTextOut := .T.
      ENDIF
   ENDIF

   Restscreen( 09, 20, 15, 60, cScBuf )
   SetColor( oldc )
   edi_SetPos( oEdit )

   RETURN Nil

FUNCTION mnu_SeaHist( oEdit, aGet )

   LOCAL aMenu, i, bufc

   IF !Empty( TEdit():aSeaHis )
      aMenu := Array( Len(TEdit():aSeaHis) )
      FOR i := 1 TO Len(aMenu)
         aMenu[i] := { hb_Translate( TEdit():aSeaHis[i], "UTF8" ), Nil, i }
      NEXT
      bufc := SaveScreen( 12, 22, 12 + Min(6,Len(aMenu)+1), 55 )
      IF !Empty( i := FMenu( oEdit, aMenu, 12, 22, 12 + Min(6,Len(aMenu)+1), 55 ) )
         aGet[4] := aMenu[i,1]
         ShowGetItem( aGet, .F., oEdit:lUtf8 )
      ENDIF
      RestScreen( 12, 22, 12 + Min(6,Len(aMenu)+1), 55, bufc )
      __KeyBoard(Chr(K_UP))
   ENDIF

   RETURN Nil

FUNCTION mnu_SeaNext( oEdit, lNext )

   LOCAL ny := oEdit:nLine, nx := oEdit:nPos
   LOCAL cSearch

   IF !Empty( TEdit():aSeaHis )
      cSearch := hb_Translate(TEdit():aSeaHis[1],"UTF8")
      IF oEdit:Search( cSearch, lCase_Sea, lNext, lWord_Sea, lRegex_Sea, @ny, @nx )
         oEdit:GoTo( ny, nx, 0 )
      ELSE
         edi_Alert( "String is not found:;" + cSearch )
         oEdit:lTextOut := .T.
         edi_SetPos( oEdit )
      ENDIF
   ENDIF

   RETURN Nil

FUNCTION mnu_SeaAndRepl( oEdit )

   LOCAL cScBuf := Savescreen( 09, 20, 17, 60 )
   LOCAL oldc := SetColor( "N/W,N/W,,N+/BG,N/W" ), nRes, i
   LOCAL aGets := { {11,22,0,"",33,"W+/BG","W+/BG"}, ;
      {11,55,2,"[^]",3,"N/W","W+/RB",{||mnu_SeaHist(oEdit,aGets[1])}}, ;
      {13,22,0,"",33,"W+/BG","W+/BG"}, ;
      {13,55,2,"[^]",3,"N/W","W+/RB",{||mnu_ReplHist(oEdit,aGets[3])}}, ;
      {14,23,1,.F.,1}, {14,43,1,.F.,1}, ;
      {16,25,2,"[Replace]",10,"N/W","W+/BG",{||__KeyBoard(Chr(K_ENTER))}}, ;
      {16,40,2,"[Cancel]",10,"N/W","W+/BG",{||__KeyBoard(Chr(K_ESC))}} }
   LOCAL cSearch, cRepl, lCase, lBack := .F., cs_utf8, cr_utf8, nSeaLen
   LOCAL ny := oEdit:nLine, nx := oEdit:nPos

   hb_cdpSelect( "RU866" )
   @ 09, 20, 17, 60 BOX "�Ŀ����� "
   @ 15, 20 SAY "�"
   @ 15, 60 SAY "�"
   @ 15, 21 TO 15, 59
   hb_cdpSelect( oEdit:cp )

   @ 10,22 SAY "Search for"
   @ 12,22 SAY "Replace with"
   @ 14, 22 SAY "[ ] Case sensitive"
   @ 14, 42 SAY "[ ] Backward"

   IF !Empty( TEdit():aSeaHis )
      aGets[1,4] := TEdit():aSeaHis[1]
      aGets[5,4] := lCase_Sea
   ENDIF
   IF !Empty( TEdit():aReplHis )
      aGets[3,4] := TEdit():aReplHis[1]
   ENDIF

   IF ( nRes := edi_READ( aGets ) ) > 0 .AND. nRes < Len(aGets)
      cSearch := Trim( aGets[1,4] )
      nSeaLen := cp_Len( oEdit:lUtf8, cSearch )
      cRepl := Trim( aGets[3,4] )
      lCase := aGets[5,4]
      lBack := aGets[6,4]
      cs_utf8 := hb_Translate( cSearch,, "UTF8" )
      cr_utf8 := hb_Translate( cRepl,, "UTF8" )
      IF ( i := Ascan( TEdit():aSeaHis, {|cs|cs==cs_utf8} ) ) > 0
         ADel( TEdit():aSeaHis, i )
         hb_AIns( TEdit():aSeaHis, 1, cs_utf8, .F. )
      ELSE
         hb_AIns( TEdit():aSeaHis, 1, cs_utf8, Len(TEdit():aSeaHis)<hb_hGetDef(TEdit():options,"seahismax",10) )
      ENDIF
      IF ( i := Ascan( TEdit():aReplHis, {|cs|cs==cr_utf8} ) ) > 0
         ADel( TEdit():aReplHis, i )
         hb_AIns( TEdit():aReplHis, 1, cr_utf8, .F. )
      ELSE
         hb_AIns( TEdit():aReplHis, 1, cr_utf8, Len(TEdit():aReplHis)<hb_hGetDef(TEdit():options,"seahismax",10) )
      ENDIF
      nRes := 0
      DO WHILE .T.
         IF oEdit:Search( cSearch, lCase_Sea := lCase, !lBack, .F., .F., @ny, @nx )
            oEdit:GoTo( ny, nx, nSeaLen )
            oEdit:TextOut()
            edi_SetPos( oEdit )
            IF nRes != 2
               nRes := mnu_ReplNext( oEdit )
            ENDIF
            IF nRes == 1 .OR. nRes == 2
               oEdit:DelText( ny, nx, ny, nx + nSeaLen - 1 )
               oEdit:InsText( ny, nx, cRepl )
            ELSEIF nRes == 3
               LOOP
            ELSE
               EXIT
            ENDIF
         ELSE
            edi_Alert( "String is not found:;" + cSearch )
            oEdit:lTextOut := .T.
            EXIT
         ENDIF
      ENDDO
   ENDIF

   Restscreen( 09, 20, 17, 60, cScBuf )
   SetColor( oldc )
   edi_SetPos( oEdit )

   RETURN Nil

FUNCTION mnu_ReplHist( oEdit, aGet )

   LOCAL aMenu, i, bufc

   IF !Empty( TEdit():aReplHis )
      aMenu := Array( Len(TEdit():aReplHis) )
      FOR i := 1 TO Len(aMenu)
         aMenu[i] := { hb_Translate( TEdit():aReplHis[i], "UTF8" ), Nil, i }
      NEXT
      bufc := SaveScreen( 14, 22, 14 + Min(6,Len(aMenu)+1), 55 )
      IF !Empty( i := FMenu( oEdit, aMenu, 14, 22, 14 + Min(6,Len(aMenu)+1), 55 ) )
         aGet[4] := aMenu[i,1]
         ShowGetItem( aGet, .F., oEdit:lUtf8 )
      ENDIF
      RestScreen( 14, 22, 14 + Min(6,Len(aMenu)+1), 55, bufc )
      __KeyBoard(Chr(K_UP))
   ENDIF

   RETURN Nil

FUNCTION mnu_ReplNext( oEdit )

   LOCAL oldc := SetColor( "N/W,N/W,,,N/W" ), nRes := 0
   LOCAL y1 := Iif( Row()>oEdit:y2-6, oEdit:y1+2, oEdit:y2-6 ), x1 := oEdit:x2-40
   LOCAL aGets := { ;
      {y1+4,x1+2,2,"[Replace]",9,"N/W","W+/BG",{||__KeyBoard(Chr(K_ENTER))}}, ;
      {y1+4,x1+14,2,"[All]",5,"N/W","W+/BG",{||__KeyBoard(Chr(K_ENTER))}}, ;
      {y1+4,x1+21,2,"[Skip]",6,"N/W","W+/BG",{||__KeyBoard(Chr(K_ENTER))}}, ;
      {y1+4,x1+30,2,"[Cancel]",8,"N/W","W+/BG",{||__KeyBoard(Chr(K_ENTER))}} }
   LOCAL cSearch, cRepl, nSeaLen, ny, nx

   IF !Empty( TEdit():aSeaHis ) .AND. !Empty( TEdit():aReplHis )
      hb_cdpSelect( "RU866" )
      @ y1, x1, y1+5, x1+40 BOX "�Ŀ����� "
      @ y1+3, x1 SAY "�"
      @ y1+3, x1+40 SAY "�"
      @ y1+3, x1+1 TO y1+3, x1+39
      hb_cdpSelect( oEdit:cp )

      ny := oEdit:nLine
      nx := oEdit:nPos
      cSearch := hb_Translate(TEdit():aSeaHis[1],"UTF8")
      nSeaLen := cp_Len( oEdit:lUtf8, cSearch )
      cSearch := cp_Substr( oEdit:lUtf8, oEdit:aText[ny], nx, nSeaLen )
      cRepl := hb_Translate(TEdit():aReplHis[1],"UTF8")
      @ y1+1,x1+2 SAY 'Replace "' + cSearch + '"'
      @ y1+2,x1+2 SAY 'With "' + cRepl + '"'

      nRes := edi_Read( aGets )
      SetColor( oldc )
      edi_SetPos( oEdit )
   ENDIF

   RETURN nRes

FUNCTION mnu_GoTo( oEdit )

   LOCAL oldc := SetColor( "N/W,W+/BG" )
   LOCAL aGets := { {11,27,0,"",26}, ;
      {13,28,2,"[Ok]",4,"N/W","W+/BG",{||__KeyBoard(Chr(K_ENTER))}}, ;
      {13,42,2,"[Cancel]",10,"N/W","W+/BG",{||__KeyBoard(Chr(K_ESC))}} }
   LOCAL arr, ny, nx, nRes

   hb_cdpSelect( "RU866" )
   @ 09, 25, 14, 55 BOX "�Ŀ����� "
   @ 12, 25 SAY "�"
   @ 12, 55 SAY "�"
   @ 12, 26 TO 12, 54
   hb_cdpSelect( oEdit:cp )

   @ 10,32 SAY "Go to position"
   SetColor( "W+/BG" )

   IF ( nRes := edi_READ( aGets ) ) > 0 .AND. nRes < Len(aGets)
      arr := hb_aTokens( aGets[1,4], "," )
      ny := Val( arr[1] )
      nx := Iif( Len(arr)>1 .AND. Val(arr[2])>0, Val(arr[2]), 1 )
      IF ny > 0 .AND. ny <= Len(oEdit:aText)
         IF nx >= cp_Len( oEdit:lUtf8, oEdit:aText[ny] )
            nx := 1
         ENDIF
         oEdit:GoTo( ny, edi_Col2Pos( oEdit, ny, nx ), 0 )
      ENDIF
   ENDIF

   SetColor( oldc )
   edi_SetPos( oEdit )

   RETURN Nil

FUNCTION mnu_Plugins( oEdit )

   LOCAL aMenu := {}, i

   FOR i := 1 TO Len( TEdit():aPlugins )
      IF Empty( TEdit():aPlugins[i,3] ) .OR. TEdit():aPlugins[i,3] == oEdit:cSyntaxType
         AAdd( aMenu, { TEdit():aPlugins[i,2], Nil, i} )
      ENDIF
   NEXT
   IF !Empty( aMenu )
      IF ( i := FMenu( oEdit, aMenu, 2, 6 ) ) > 0
         i := aMenu[i,3]
         edi_RunPlugin( oEdit, i )
      ENDIF
   ENDIF

   RETURN Nil

FUNCTION mnu_ChgMode( oEdit, lBack )

   SetColor( "N/W+" )
   Scroll( oEdit:y1-1, oEdit:x1, oEdit:y1-1, oEdit:x2 )
   Inkey( 0.1 )
   edi_SetPos( oEdit )

   IF !Empty( lBack )
      oEdit:nMode := Iif( oEdit:nMode==2, 1, 0 )
      oEdit:WriteTopPane( 1 )
   ELSE
      IF oEdit:nMode == 0
         oEdit:nMode := 1
         oEdit:WriteTopPane( 1 )
      ELSEIF oEdit:nMode == 1
         oEdit:nMode := 2
         oEdit:WriteTopPane( 1 )
         mnu_CmdLine( oEdit )
      ENDIF
   ENDIF

   RETURN Nil

FUNCTION edi_RunPlugin( oEdit, xPlugin )

   LOCAL i, cPlugin, cFullPath

   IF Valtype( xPlugin ) == "N"
      i := xPlugin
   ELSEIF Valtype( xPlugin ) == "C"
      i := Ascan( TEdit():aPlugins, {|a|a[1]==xPlugin} )
   ENDIF
   IF i > 0
      IF Empty( TEdit():aPlugins[i,4] )
         cPlugin := TEdit():aPlugins[i,1]
         IF !Empty( cFullPath := edi_FindPath( "plugins" + hb_ps() + cPlugin ) )
            TEdit():aPlugins[i,4] := hb_hrbLoad( cFullPath )
         ENDIF
      ENDIF
      IF !Empty( TEdit():aPlugins[i,4] )
         hb_hrbDo( TEdit():aPlugins[i,4], oEdit )
      ENDIF
   ENDIF

   RETURN Nil

FUNCTION edi_SetPos( oEdit, nLine, nPos )

   IF nLine != Nil; oEdit:nLine := nLine; ENDIF
   IF nPos != Nil; oEdit:nPos := nPos; ENDIF

   RETURN DevPos( oEdit:LineToRow(nLine), oEdit:PosToCol(nLine,nPos) )

STATIC FUNCTION edi_Move( oEdit, nKey, nRepeat )

   LOCAL i, x

   IF nRepeat == Nil; nRepeat := 1; ENDIF
   IF nKey == 71 // G
      IF nRepeat == 1
         oEdit:nPosBack := oEdit:nPos
         oEdit:nLineBack := oEdit:nLine
         IF Len( oEdit:aText ) > oEdit:y2-oEdit:y1+1
            oEdit:nxFirst := 1
            oEdit:nyFirst := Len( oEdit:aText ) - (oEdit:y2-oEdit:y1)
            oEdit:lTextOut := .T.
            edi_SetPos( oEdit, oEdit:nyFirst + oEdit:y2 - oEdit:y1, Min( oEdit:nPos,Iif(nKey==K_CTRL_END,1,cp_Len(oEdit:lUtf8,ATail(oEdit:aText))+1)) )
         ELSE
            edi_SetPos( oEdit, Len(oEdit:aText)+oEdit:y1-1, Iif(nKey==K_CTRL_END,1,Min(oEdit:nPos,cp_Len(oEdit:lUtf8,ATail(oEdit:aText))+1)) )
         ENDIF
      ELSE
         oEdit:GoTo( nRepeat )
      ENDIF
      RETURN Nil
   ELSEIF nKey == 48  // 0
      IF oEdit:nxFirst > 1
         oEdit:nxFirst := 1
         oEdit:lTextOut := .T.
      ENDIF
      edi_SetPos( oEdit, oEdit:nLine, oEdit:nxFirst )
      RETURN Nil
   ELSEIF nKey == 94  // ^
      edi_Move( oEdit, 48 )
      edi_Move( oEdit, 119 )
      RETURN Nil
   ELSEIF nKey == 36  // $
      edi_GoEnd( oEdit )
      RETURN Nil
   ENDIF
   FOR i := 1 TO nRepeat
      SWITCH nKey
      CASE 104   // h Move left
         edi_GoLeft( oEdit )
         EXIT
      CASE 108   // l Move right
         edi_GoRight( oEdit )
         EXIT
      CASE 107   // k Move up
         edi_GoUp( oEdit )
         EXIT
      CASE 106   // j Move down
         edi_GoDown( oEdit )
         EXIT
      CASE 119   // w Move to the next word
         edi_NextWord( oEdit, .F. )
         EXIT
      CASE 87    // W Move to the next big word
         edi_NextWord( oEdit, .T. )
         EXIT
      CASE 101   // e Move to the end of word
         edi_NextWord( oEdit, .F., .T. )
         EXIT
      CASE 69    // E Move to the end of a big word
         edi_NextWord( oEdit, .T., .T. )
         EXIT
      CASE 98    // b Move to the previous word
         edi_PrevWord( oEdit, .F. )
         EXIT
      CASE 66    // B Move to the previous big word
         edi_PrevWord( oEdit, .T. )
         EXIT
      CASE K_CTRL_F   // Ctrl-F PgDn
         IF oEdit:nyFirst + (oEdit:y2-oEdit:y1) <= Len( oEdit:aText )
            oEdit:nyFirst += (oEdit:y2-oEdit:y1)
            oEdit:lTextOut := .T.
            edi_SetPos( oEdit, Min( oEdit:nLine+(oEdit:y2-oEdit:y1),Len(oEdit:aText) ), oEdit:nPos )
         ELSE
            edi_SetPos( oEdit, Len(oEdit:aText), oEdit:nPos )
         ENDIF
         EXIT
      CASE K_CTRL_B   // Ctrl-B PgUp
         IF oEdit:nyFirst > (oEdit:y2-oEdit:y1)
            oEdit:nyFirst -= (oEdit:y2-oEdit:y1)
            oEdit:lTextOut := .T.
            edi_SetPos( oEdit, oEdit:nLine-(oEdit:y2-oEdit:y1), oEdit:nPos )
         ELSEIF oEdit:nyFirst > 1
            x := oEdit:nyFirst - 1
            oEdit:nyFirst := 1
            oEdit:lTextOut := .T.
            edi_SetPos( oEdit, oEdit:nLine-x, oEdit:nPos )
         ELSE
            edi_Setpos( oEdit, 1, oEdit:nPos )
         ENDIF
         EXIT
      END
   NEXT

   RETURN Nil

STATIC FUNCTION edi_GoUp( oEdit )

   IF oEdit:nLine == oEdit:nyFirst
      IF oEdit:nyFirst > 1
         oEdit:nyFirst --
         oEdit:lTextOut := .T.
         edi_SetPos( oEdit, oEdit:nyFirst, oEdit:ColToPos( Row(), Col() ) )
      ENDIF
   ELSE
      edi_SetPos( oEdit, oEdit:nLine-1, oEdit:ColToPos( Row()-1, Col() ) )
   ENDIF
   RETURN Nil

STATIC FUNCTION edi_GoDown( oEdit )

   IF oEdit:nLine < Len(oEdit:aText)
      IF oEdit:LineToRow() == oEdit:y2
         oEdit:nyFirst ++
         oEdit:lTextOut := .T.
      ENDIF
      edi_SetPos( oEdit, oEdit:nLine+1, oEdit:ColToPos( oEdit:LineToRow(oEdit:nLine+1), Col() ) )
   ENDIF

   RETURN Nil

STATIC FUNCTION edi_GoRight( oEdit )

   IF oEdit:PosToCol() == oEdit:x2
      oEdit:nxFirst ++
      oEdit:lTextOut := .T.
   ENDIF
   edi_SetPos( oEdit, oEdit:nLine, oEdit:nPos+1 )

   RETURN Nil

STATIC FUNCTION edi_GoLeft( oEdit )

   IF oEdit:nPos > 1
      IF oEdit:PosToCol() == oEdit:x1
         IF oEdit:nxFirst > 1
            oEdit:nxFirst --
            oEdit:lTextOut := .T.
         ELSE
            RETURN Nil
         ENDIF
      ENDIF
      edi_SetPos( oEdit, oEdit:nLine, oEdit:nPos-1 )
   ENDIF

   RETURN Nil

STATIC FUNCTION edi_GoEnd( oEdit )

   LOCAL n := oEdit:nLine, nPos
   LOCAL nCol := edi_ExpandTabs( oEdit, oEdit:aText[n], 1, .T. ) + 1 //Iif( oEdit:nMode==1, 0, 1 )

   IF nCol < oEdit:nxFirst .OR. nCol - oEdit:nxFirst > oEdit:x2 - oEdit:x1
      oEdit:nxFirst := Max( 1, nCol - ( oEdit:x2 - oEdit:x1 ) + 1 )
      oEdit:lTextOut := .T.
   ENDIF
   edi_SetPos( oEdit, n, oEdit:ColToPos( oEdit:LineToRow(n), nCol - oEdit:nxFirst + oEdit:x1) )

   RETURN Nil

STATIC FUNCTION edi_ConvertCase( oEdit, lUpper )

   LOCAL s, i, nby1, nby2, nbx1, nbx2, lUtf8 := oEdit:lUtf8

   IF oEdit:nby1 < 0 .OR. oEdit:nby2 < 0
      RETURN Nil
   ENDIF

   IF oEdit:nby1 < oEdit:nby2 .OR. ( oEdit:nby1 == oEdit:nby2 .AND. oEdit:nbx1 < oEdit:nbx2 )
      nby1 := oEdit:nby1; nbx1 := oEdit:nbx1; nby2 := oEdit:nby2; nbx2 := oEdit:nbx2
   ELSE
      nby1 := oEdit:nby2; nbx1 := oEdit:nbx2; nby2 := oEdit:nby1; nbx2 := oEdit:nbx1
   ENDIF
   IF nby1 == nby2
      s := cp_Substr( lUtf8, oEdit:aText[nby1], nbx1, nbx2-nbx1 )
   ELSE
      FOR i := nby1 TO nby2
         IF i == nby1
            s := cp_Substr( lUtf8, oEdit:aText[nby1], nbx1 )
         ELSEIF i == nby2
            s += Chr(10) + cp_Left( lUtf8, oEdit:aText[i], nbx2-1 )
         ELSE
            s += oEdit:aText[i]
         ENDIF
      NEXT
   ENDIF
   oEdit:InsText( nby1, nbx1, Iif( lUpper, cp_Upper(lUtf8,s), cp_Lower(lUtf8,s) ), .T., .F. )

   RETURN Nil

STATIC FUNCTION edi_AlphaNum( nch )

   RETURN (nch >= 48 .AND. nch <= 57) .OR. (nch >= 65 .AND. nch <= 90) .OR. ;
      (nch >= 97 .AND. nch <= 122) .OR. nch == 95 .OR. nch >= 128

STATIC FUNCTION edi_NextWord( oEdit, lBigW, lEndWord, lChgPos, ny, nx )
   LOCAL nInitPos := nx, nLen, lUtf8 := oEdit:lUtf8, ch, nch
   LOCAL lOk := .F., lAlphaNum

   IF ny == Nil
      ny := oEdit:nLine
   ENDIF
   IF nx == Nil
      nInitPos := nx := oEdit:nPos
   ENDIF
   nLen := cp_Len( lUtf8, oEdit:aText[ny] )

   IF nx > nLen
      RETURN Nil
   ENDIF

   ch := cp_Substr( lUtf8, oEdit:aText[ny], nx, 1 )
   IF ch == " "
      DO WHILE ++nx <= nLen .AND. cp_Substr( lUtf8, oEdit:aText[ny], nx, 1 ) == ch; ENDDO
      lOk := Empty( lEndWord )
   ENDIF

   IF !lOk
      lAlphaNum := edi_AlphaNum( cp_Asc( lUtf8, cp_Substr(lUtf8,oEdit:aText[ny],nx,1) ) )
      DO WHILE ++nx <= nLen
         ch := cp_Substr( lUtf8, oEdit:aText[ny], nx, 1 )
         IF ( ch == " " ) .OR. ( !lBigW .AND. ;
               lAlphaNum != edi_AlphaNum( cp_Asc(lUtf8,ch) ) )
            IF !Empty( lEndWord ) .AND. nx - nInitPos > 1
               nx --
               EXIT
            ENDIF
            IF ch == " "
               DO WHILE ++nx <= nLen .AND. cp_Substr( lUtf8, oEdit:aText[ny], nx, 1 ) == ch; ENDDO
            ENDIF
            IF Empty( lEndWord )
               EXIT
            ENDIF
            lAlphaNum := edi_AlphaNum( cp_Asc( lUtf8, cp_Substr(lUtf8,oEdit:aText[ny],nx,1) ) )
         ENDIF
      ENDDO
      IF nx > nLen .AND. !Empty( lEndWord )
         nx --
      ENDIF
   ENDIF

   IF lChgPos == Nil .OR. lChgPos
      IF oEdit:PosToCol(ny,nx) >= oEdit:x2
         oEdit:nxFirst := nx + oEdit:x1 - oEdit:x2 + 3
         oEdit:lTextOut := .T.
      ENDIF
      edi_SetPos( oEdit, oEdit:nLine, nx )
   ENDIF

   RETURN nx

STATIC FUNCTION edi_PrevWord( oEdit, lBigW, lChgPos, lIn, ny, nx )
   LOCAL lUtf8 := oEdit:lUtf8
   LOCAL ch, lAlphaNum

   IF ny == Nil
      ny := oEdit:nLine
   ENDIF
   IF nx == Nil
      nx := oEdit:nPos
   ENDIF

   ch := cp_Substr( lUtf8, oEdit:aText[ny], --nx, 1 )
   IF ch == " "
      IF !Empty( lIn )
         RETURN nx
      ENDIF
      DO WHILE --nx > 1 .AND. cp_Substr( lUtf8, oEdit:aText[ny], nx, 1 ) == " "; ENDDO
   ENDIF

   lAlphaNum := edi_AlphaNum( cp_Asc( lUtf8, cp_Substr(lUtf8,oEdit:aText[ny],nx,1) ) )
   IF !Empty( lIn ) .AND. nx > 1 .AND. ;
      edi_AlphaNum( cp_Asc( lUtf8, cp_Substr(lUtf8,oEdit:aText[ny],nx-1,1) ) ) != lAlphaNum
      RETURN nx
   ENDIF
   DO WHILE --nx > 0
      IF ( ch := cp_Substr( lUtf8, oEdit:aText[ny], nx, 1 ) ) == " " .OR. ;
            ( !lBigW .AND. lAlphaNum != edi_AlphaNum( cp_Asc(lUtf8,ch) ) )
         nx ++
         EXIT
      ENDIF
   ENDDO
   nx := Max( nx, 1 )

   IF lChgPos == Nil .OR. lChgPos
      IF nx < oEdit:nxFirst
         oEdit:nxFirst := Max( nx + oEdit:x1 - oEdit:x2 + 3, 1 )
         oEdit:lTextOut := .T.
      ENDIF
      edi_SetPos( oEdit, oEdit:nLine, nx )
   ENDIF

   RETURN nx

STATIC FUNCTION edi_SaveDlg( oEdit )

   LOCAL oldc := SetColor( "N/W,N/W,,N+/BG,N/W" ), cName
   LOCAL aGets := { {11,22,0,"",48,"W+/BG","W+/BG"}, ;
      {12,29,3,.T.,1}, {12,47,3,.F.,1}, {12,63,3,.F.,1}, ;
      {15,25,2,"[Save]",8,"N/W","W+/BG",{||__KeyBoard(Chr(K_ENTER))}}, ;
      {15,58,2,"[Cancel]",10,"N/W","W+/BG",{||__KeyBoard(Chr(K_ESC))}} }

   hb_cdpSelect( "RU866" )
   @ 09, 20, 16, 72 BOX "�Ŀ����� "
   @ 14, 20 SAY "�"
   @ 14, 72 SAY "�"
   @ 14, 21 TO 14, 71
   hb_cdpSelect( oEdit:cp )

   @ 10,22 SAY "Save file as"
   @ 12, 22 SAY " Eol: ( ) Do not change ( ) Dos/Windows ( ) Unix"
   IF oEdit:lUtf8
      hb_AIns( aGets, 5, {13,24,1,oEdit:lBom,1}, .T. )
      @ 13, 23 SAY "[ ] Add BOM"
   ENDIF
   SetColor( "W+/BG" )

   IF edi_READ( aGets ) > 0
      cName := aGets[1,4]
      IF aGets[3,4]
         oEdit:cEol := Chr(13) + Chr(10)
      ELSEIF aGets[4,4]
         oEdit:cEol := Chr(10)
      ENDIF
      IF oEdit:lUtf8
         oEdit:lBom := aGets[5,4]
      ENDIF
   ENDIF

   SetColor( oldc )
   edi_SetPos( oEdit )

   RETURN cName

STATIC FUNCTION edi_Indent( oEdit, lRight )

   LOCAL i, n, nby1, nby2, nbx2, l := .F., nRow := Row(), nCol := Col()

   IF oEdit:lReadOnly .OR. oEdit:nby1 < 0 .OR. oEdit:nby2 < 0
      RETURN Nil
   ENDIF
   IF oEdit:nby1 <= oEdit:nby2
      nby1 := oEdit:nby1; nby2 := oEdit:nby2; nbx2 := oEdit:nbx2
   ELSE
      nby1 := oEdit:nby2; nby2 := oEdit:nby1; nbx2 := oEdit:nbx1
   ENDIF
   FOR i := nby1 TO nby2
      IF i == nby2 .AND. nbx2 == 1
         nby2 --
         EXIT
      ENDIF
      IF lRight
         oEdit:aText[i] := Iif( Left( oEdit:aText[i],1 ) == cTab, cTab, " " ) + oEdit:aText[i]
         l := .T.
      ELSEIF Left( oEdit:aText[i],1 ) == " " .OR. Left( oEdit:aText[i],2 ) == cTab + cTab
         oEdit:aText[i] := Substr( oEdit:aText[i], 2 )
         l := .T.
      ENDIF
      n := i - oEdit:nyFirst + 1
      IF n > 0 .AND. n < oEdit:y2-oEdit:y1
         oEdit:LineOut( n )
      ENDIF
   NEXT
   IF l
      oEdit:Undo( nby1, 0, nby2, 0, UNDO_OP_SHIFT, Iif(lRight,1,-1) )
      oEdit:lUpdated := .T.
   ENDIF
   DevPos( nRow, nCol )

   RETURN Nil

STATIC FUNCTION edi_BookMarks( oEdit, nKey, lSet )

   LOCAL arr

   IF nKey >= 97 .AND. nKey <= 122
      IF lSet
         oEdit:hBookMarks[nKey] := { oEdit:nLine, oEdit:nPos }
      ELSE
         IF hb_hHaskey( oEdit:hBookMarks, nKey )
            arr := oEdit:hBookMarks[nKey]
            oEdit:Goto( arr[1], arr[2] )
         ENDIF
      ENDIF
   ENDIF

   RETURN Nil

STATIC FUNCTION edi_Bracket( oEdit, lCalcOnly, lPairOnly )

   LOCAL nyInit, ny := oEdit:nLine, nx := oEdit:nPos
   LOCAL c, nPos := 0
   LOCAL b1 := "([{", b2 := ")]}", i, np := 0

   IF ny > Len( oEdit:aText ) .OR. nx > cp_Len( oEdit:lUtf8, oEdit:aText[ny] )
      RETURN 0
   ENDIF
   c := cp_Substr( oEdit:lUtf8, oEdit:aText[ny], nx, 1 )
   nyInit := ny
   IF ( i := At( c, b1 ) ) > 0
      IF edi_InQuo( oEdit, ny, nx ) == 0
         nPos := nx
         DO WHILE ny <= Len( oEdit:aText )
            DO WHILE ( nPos := edi_FindChNext( oEdit, ny, nPos, c, Substr( b2,i,1 ) ) ) > 0
               IF cp_Substr( oEdit:lUtf8, oEdit:aText[ny], nPos, 1 ) == c
                  np ++
               ELSEIF np > 0
                  np --
               ELSE
                  EXIT
               ENDIF
            ENDDO
            IF nPos == 0
               ny ++
            ELSE
               EXIT
            ENDIF
         ENDDO
      ENDIF
   ELSEIF ( i := At( c, b2 ) ) > 0
      IF edi_InQuo( oEdit, ny, nx ) == 0
         nPos := nx
         DO WHILE ny > 0
            DO WHILE ( nPos := edi_FindChPrev( oEdit, ny, nPos, c, Substr( b1,i,1 ) ) ) > 0
               IF cp_Substr( oEdit:lUtf8, oEdit:aText[ny], nPos, 1 ) == c
                  np ++
               ELSEIF np > 0
                  np --
               ELSE
                  EXIT
               ENDIF
            ENDDO
            IF nPos == 0
               ny --
               nPos := Iif( ny > 0, cp_Len( oEdit:lUtf8, oEdit:aText[ny] ) + 1, 1 )
            ELSE
               EXIT
            ENDIF
         ENDDO
      ENDIF
   ELSEIF Empty( lPairOnly )
      IF edi_InQuo( oEdit, ny, nx ) == 0
         nPos := edi_FindChNext( oEdit, ny, nx, ")", "]", "}" )
      ENDIF
   ENDIF
   IF Empty( lCalcOnly ) .AND. nPos > 0
      oEdit:GoTo( ny, nPos )
   ENDIF

   RETURN Iif( !Empty(lCalcOnly), Iif( ny==nyInit .OR. nPos==0, nPos, {ny,nPos} ), Nil )

STATIC FUNCTION edi_FindChNext( oEdit, nLine, nPos, ch1, ch2, ch3 )

   LOCAL c, s := oEdit:aText[nLine], cQuo, lQuo := .F., nLen := cp_Len( oEdit:lUtf8,s )

   DO WHILE ++nPos <= nLen
      c := cp_Substr( oEdit:lUtf8, s, nPos, 1 )
      IF lQuo
         IF c == cQuo
            lQuo := .F.
         ENDIF
      ELSE
        IF c == ch1 .OR. c == ch2 .OR. c == ch3
            RETURN nPos
        ELSEIF c $ ["']
            lQuo := .T.
            cQuo := c
         ENDIF
      ENDIF
   ENDDO

   RETURN 0

STATIC FUNCTION edi_FindChPrev( oEdit, nLine, nPos, ch1, ch2, ch3 )

   LOCAL c, s := oEdit:aText[nLine], cQuo, lQuo := .F., nPosQuo := edi_InQuo( oEdit, nLine, nPos )

   IF nPosQuo > 0
      IF ( ( c := cp_Substr( oEdit:lUtf8, s, nPos, 1 ) ) == ch1 ;
            .OR. c == ch2 .OR. c == ch3 )
         RETURN nPosQuo
      ELSE
         nPos := nPosQuo
      ENDIF
   ENDIF
   DO WHILE --nPos > 0
      c := cp_Substr( oEdit:lUtf8, s, nPos, 1 )
      IF lQuo
         IF c == cQuo
            lQuo := .F.
         ENDIF
      ELSE
        IF c == ch1 .OR. c == ch2 .OR. c == ch3
            RETURN nPos
        ELSEIF c $ ["']
            lQuo := .T.
            cQuo := c
         ENDIF
      ENDIF
   ENDDO

   RETURN 0

STATIC FUNCTION edi_InQuo( oEdit, nLine, nPos )

   LOCAL i := 0, c, s := oEdit:aText[nLine], cQuo, lQuo := .F., nPosQuo := 0

   DO WHILE ++i < nPos
      c := cp_Substr( oEdit:lUtf8, s, i,1 )
      IF lQuo
         IF c == cQuo
            lQuo := .F.
            nPosQuo := 0
         ENDIF
      ELSE
         IF c $ ["']
            lQuo := .T.
            cQuo := c
            nPosQuo := i
         ENDIF
      ENDIF
   ENDDO

   RETURN nPosQuo

FUNCTION edi_Col2Pos( oEdit, nLine, nCol )

   LOCAL nPos, s := oEdit:aText[nLine], nPos1 := 1, nPos2, nLenNew := 0, nAdd := 0, nLen1
   LOCAL nTabLen := oEdit:nTabLen

   DO WHILE ( nPos2 := hb_At( cTab, s, nPos1 ) ) > 0
      IF nPos2 - nPos1 > 0
         IF oEdit:lUtf8
            nLenNew += cp_Len( oEdit:lUtf8, Substr( s, nPos1, nPos2-nPos1 ) )
         ELSE
            nLenNew += ( nPos2-nPos1 )
         ENDIF
         IF nLenNew > nCol
            RETURN nCol - nAdd
         ENDIF
      ENDIF
      IF ( nLen1 := ( nTabLen - Iif( (nLen1:=((1+nLenNew) % nTabLen))==0,nTabLen,nLen1 ) + 1 ) ) > 0
         nLenNew += nLen1
         nAdd += Int(nLen1 - 0.99)
         IF nLenNew > nCol
            RETURN nPos2
         ENDIF
      ENDIF
      nPos1 := nPos2 + 1
   ENDDO

   RETURN nCol - nAdd

FUNCTION edi_ExpandTabs( oEdit, s, nFirst, lCalcOnly, nAdd )

   LOCAL sNew := "", nLenNew := 0, s1, nPos1 := 1, nPos2, nLen1
   LOCAL nTabLen := oEdit:nTabLen

   IF lCalcOnly == Nil; lCalcOnly := .F.; ENDIF
   nAdd := 0
   DO WHILE ( nPos2 := hb_At( cTab, s, nPos1 ) ) > 0
      IF nPos2 - nPos1 > 0
         IF lCalcOnly
            IF oEdit:lUtf8
               nLenNew += cp_Len( oEdit:lUtf8, Substr( s, nPos1, nPos2-nPos1 ) )
            ELSE
               nLenNew += ( nPos2-nPos1 )
            ENDIF
         ELSE
            s1 := Substr( s, nPos1, nPos2-nPos1 )
            sNew += s1
            nLenNew += cp_Len( oEdit:lUtf8, s1 )
         ENDIF
      ENDIF
      IF ( nLen1 := ( nTabLen - Iif( (nLen1:=((nFirst+nLenNew) % nTabLen))==0,nTabLen,nLen1 ) + 1 ) ) > 0
         IF !lCalcOnly
            sNew += Space( nLen1 )
         ENDIF
         nLenNew += nLen1
         nAdd += Int(nLen1 - 0.99)
      ENDIF
      nPos1 := nPos2 + 1
   ENDDO
   IF lCalcOnly
      IF oEdit:lUtf8
         nLenNew += cp_Len( oEdit:lUtf8, Substr( s, nPos1 ) )
      ELSE
         nLenNew += ( Len(s)-nPos1+1 )
      ENDIF
   ELSE
      s1 := Substr( s, nPos1 )
      sNew += s1
      nLenNew += cp_Len( oEdit:lUtf8, s1 )
   ENDIF

   RETURN Iif( lCalcOnly, Int(nLenNew), sNew )

/*
 * edi_AddWindow( oEdit, cText, cFileName, nPlace, nSpace )
 * Adds new edit window, truncates the current edit window
 * oEdit - current window
 * cText, cFilename - the data of a new window
 * nPlace: 0 - top, 1 - left, 2 - bottom, 3 - right
 * nSpace - the number of rows or columns of a new window
 */
FUNCTION edi_AddWindow( oEdit, cText, cFileName, nPlace, nSpace )

   LOCAL oNew, y1 := oEdit:y1, x1 := oEdit:x1, y2 := oEdit:y2, x2 := oEdit:x2, lv := .F.

   IF nPlace == 0
      y2 := y1 + nSpace - 1
      oEdit:y1 := y2 + 1
   ELSEIF nPlace == 1
      x2 := x1 + nSpace - 1
      oEdit:x1 := x2 + 1
      lv := .T.
   ELSEIF nPlace == 2
      y1 := y2 - nSpace
      oEdit:y2 := y1-1
   ELSEIF nPlace == 3
      x1 := x2 - nSpace
      oEdit:x2 := x1-1
      lv := .T.
      SetColor( oEdit:cColorPane )
      Scroll( y1, x1, y2, x1 )
      x1 ++
   ENDIF
   IF lv .AND. oEdit:lTopPane
      oEdit:nTopName := Max( oEdit:x2 - oEdit:x1 - Iif(oEdit:x2-oEdit:x1>54,44,37), 0 )
      y1 --
   ENDIF
   oNew := TEdit():New( cText, cFileName, y1, x1, y2, x2 )
   oNew:oParent := oEdit
   mnu_ToBuf( oEdit, Len( TEdit():aWindows ) )

   RETURN oNew

FUNCTION edi_CloseWindow( xEdit )

   LOCAL oEdit, i, o, lUpd, lv := .F., lh := .F.

   IF Valtype( xEdit ) == "C"
      xEdit := Ascan( TEdit():aWindows, {|o|o:cFileName == xEdit} )
   ENDIF
   IF Valtype( xEdit ) == "N"
      oEdit := Iif( xEdit > 0 .AND. xEdit <= Len(TEdit():aWindows), TEdit():aWindows[xEdit], Nil )
   ELSEIF Valtype( xEdit ) == "O"
      oEdit := xEdit
      xEdit := Ascan( TEdit():aWindows, {|o|o == oEdit} )
   ENDIF

   IF Valtype( oEdit ) == "O"

      FOR i := Len( oEdit:aWindows ) TO 1 STEP -1
         IF oEdit:aWindows[i]:oParent == oEdit
            edi_CloseWindow( oEdit:aWindows[i] )
         ENDIF
      NEXT

      o := oEdit
      DO WHILE !( ( o := edi_FindWindow( o, .T. ) ) == oEdit )
         lUpd := .F.
         IF oEdit:aRect[1] == o:y2 + 1
            IF o:x1 >= oEdit:x1 .AND. o:x2 <= oEdit:x2
               IF !lh
                  o:y2 := oEdit:y2
                  lUpd := .T.
                  lv := .T.
               ENDIF
            ENDIF
         ELSEIF oEdit:y2 == o:aRect[1] - 1
            IF o:x1 >= oEdit:x1 .AND. o:x2 <= oEdit:x2
               IF !lh
                  o:y1 := oEdit:y1
                  lUpd := .T.
                  lv := .T.
               ENDIF
            ENDIF
         ENDIF
         IF oEdit:x1 == o:x2 + 2
            IF o:y1 >= oEdit:y1 .AND. o:y2 <= oEdit:y2
               IF !lv
                  o:x2 := oEdit:x2
                  lUpd := .T.
                  lh := .T.
               ENDIF
            ENDIF
         ELSEIF oEdit:x2 == o:x1 - 2
            IF o:y1 >= oEdit:y1 .AND. o:y2 <= oEdit:y2
               IF !lv
                  o:x1 := oEdit:x1
                  lUpd := .T.
                  lh := .T.
               ENDIF
            ENDIF
         ENDIF
         IF lUpd
            IF o:lTopPane
               o:nTopName := Max( o:x2 - o:x1 - Iif(o:x2-o:x1>54,44,37), 0 )
            ENDIF
            o:TextOut()
         ENDIF
      ENDDO
      TEdit():aWindows[xEdit]:oParent := Nil
      hb_ADel( TEdit():aWindows, xEdit, .T. )
   ENDIF

   RETURN Nil

STATIC FUNCTION edi_WindowUpdated( oEdit )

   LOCAL i, j

   FOR i := Len( oEdit:aWindows ) TO 1 STEP -1
      IF oEdit:aWindows[i]:oParent == oEdit
         IF oEdit:aWindows[i]:lUpdated
            RETURN i
         ELSEIF ( j := edi_WindowUpdated( oEdit:aWindows[i] ) ) > 0
            RETURN j
         ENDIF
      ENDIF
   NEXT

   RETURN 0

FUNCTION edi_WindowDo( oEdit, nOp )

   LOCAL o

   DO WHILE !( ( o := edi_FindWindow( o, .T. ) ) == oEdit )

      IF nOp == 1            // Expand
      ELSEIF nOp == 2        //
      ENDIF
   ENDDO

   RETURN Nil

FUNCTION edi_FindWindow( oEdit, lNext, nRow, nCol )

   LOCAL oParent := oEdit, i, iCurr, o, op

   DO WHILE oParent:oParent != Nil; oParent := oParent:oParent; ENDDO
   iCurr := Ascan( oEdit:aWindows, {|o|o == oEdit} )

   FOR i := 1 TO Len( oEdit:aWindows )
      op := o := oEdit:aWindows[i]
      IF !( o == oEdit )
         DO WHILE op:oParent != Nil; op := op:oParent; ENDDO
         IF op == oParent
            IF Valtype( lNext ) == "L"
               IF lNext .AND. i > iCurr
                  RETURN o
               ENDIF
            ELSEIF nRow >= o:y1 .AND. nRow <= o:y2 .AND. nCol >= o:x1 .AND. nCol <= o:x2
               RETURN o
            ENDIF
         ENDIF
      ENDIF
   NEXT
   IF Valtype( lNext ) == "L"
      RETURN oParent
   ENDIF

   RETURN Nil

FUNCTION edi_MapKey( oEdit, nKey )

   LOCAl c, nPos, lUtf8

   IF nKey >= 127 .AND. !Empty(cLangMapCP) .AND. !Empty(aLangMapUpper) .AND. !Empty(aLangMapLower)
      lUtf8 := (Lower(cLangMapCP) == "utf8")
      c := hb_Translate( cp_Chr( oEdit:lUtf8, nKey ), oEdit:cp, cLangMapCP )
      IF ( nPos := cp_At( lUtf8, c, aLangMapUpper[1] ) ) > 0
         RETURN cp_Asc( oEdit:lUtf8, hb_Translate( cp_Substr(oEdit:lUtf8,aLangMapUpper[2],nPos,1), cLangMapCP, oEdit:cp ) )
      ELSEIF ( nPos := cp_At( lUtf8, c, aLangMapLower[1] ) ) > 0
         RETURN cp_Asc( oEdit:lUtf8, hb_Translate( cp_Substr(oEdit:lUtf8,aLangMapLower[2],nPos,1), cLangMapCP, oEdit:cp ) )
      ENDIF
   ENDIF

   RETURN nKey

FUNCTION cp_Chr( lUtf8, n )

   RETURN Iif( lUtf8, hb_utf8Chr( n ), Chr( n ) )

FUNCTION cp_Asc( lUtf8, s )

   RETURN Iif( lUtf8, hb_utf8Asc( s ), Asc( s ) )

FUNCTION cp_Substr( lUtf8, cString, nPos, nLen )
   RETURN Iif( lUtf8, ;
      Iif( nLen==Nil, hb_utf8Substr( cString, nPos ), hb_utf8Substr( cString, nPos, nLen ) ), ;
      Iif( nLen==Nil, Substr( cString, nPos ), Substr( cString, nPos, nLen ) ) )

FUNCTION cp_Left( lUtf8, cString, nLen )

   RETURN Iif( lUtf8, hb_utf8Left( cString, nLen ), Left( cString, nLen ) )

FUNCTION cp_Len( lUtf8, cString )

   RETURN Iif( lUtf8, hb_utf8Len( cString ), Len( cString ) )

FUNCTION cp_At( lUtf8, cFind, cLine, nStart, nEnd )
   IF lUtf8; RETURN hb_utf8At( cFind, cLine, nStart, nEnd ); ENDIF
   RETURN hb_At( cFind, cLine, nStart, nEnd )

FUNCTION cp_RAt( lUtf8, cFind, cLine, nStart, nEnd )
   IF lUtf8; RETURN hb_utf8RAt( cFind, cLine, nStart, nEnd ); ENDIF
   RETURN hb_RAt( cFind, cLine, nStart, nEnd )

FUNCTION cp_NextPos( lUtf8, cLine, nPos )
   IF lUtf8; RETURN nPos + Len( cp_Substr( lUtf8, cLine, nPos, 1 ) ); ENDIF
   RETURN nPos + 1

FUNCTION cp_Lower( lUtf8, cString )
   IF lUtf8; RETURN cedi_utf8_Lower( cString ); ENDIF
   RETURN Lower( cString )

FUNCTION cp_Upper( lUtf8, cString )
   IF lUtf8; RETURN cedi_utf8_Upper( cString ); ENDIF
   RETURN Upper( cString )
