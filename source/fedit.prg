
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

#define SHIFT_PRESSED 0x010000
#define CTRL_PRESSED  0x020000
#define ALT_PRESSED   0x040000
#define MAX_CBOARDS         10

REQUEST HB_CODEPAGE_RU866, HB_CODEPAGE_RU1251, HB_CODEPAGE_RUKOI8, HB_CODEPAGE_FR850
REQUEST HB_CODEPAGE_FRWIN, HB_CODEPAGE_FRISO, HB_CODEPAGE_UTF8
REQUEST QOUT, MAXCOL, MAXROW
REQUEST HB_TOKENPTR

STATIC aMenuMain := { {"Exit",@mnu_Exit(),Nil,"Esc,F10"}, {"Save",@mnu_Save(),Nil,"F2"}, ;
   {"Save as",@mnu_Save(),.T.,"Shift-F2"}, ;
   {"Mark block",@mnu_F3(),Nil,"F3"}, {"Search&GoTo",@mnu_Sea_Goto(),{11,40},">"}, ;
   {"Change mode",@mnu_ChgMode(),Nil,"Ctrl-Z"}, ;
   {"Codepage",@mnu_CPages(),Nil,">"}, {"Syntax",@mnu_Syntax(),{16,40},"F4 >"}, ;
   {"Plugins",@mnu_Plugins(),Nil,"F11 >"}, {"Windows",@mnu_Windows(),{16,40},"F12 >"} }

STATIC aKeysMove := { K_UP, K_DOWN, K_LEFT, K_RIGHT, K_PGDN, K_PGUP, K_HOME, K_END, K_CTRL_PGUP, K_CTRL_PGDN }

STATIC aLangExten := { {"prg", ".prg"}, {"c", ".c.cpp"}, {"go", ".go"}, ;
   {"php",".php"}, {"js",".js"}, {"xml",".xml.fb2.htm.html"} }
STATIC cLangMapCP, aLangMapUpper, aLangMapLower
STATIC aMenu_CB
STATIC aPlugins := {}
STATIC aLangs
STATIC lCase_Sea

CLASS TEdit

   CLASS VAR aCPages    SHARED INIT { "RU866", "RU1251", "FR850", "FRWIN", "FRISO", "UTF8" }
   CLASS VAR aWindows   SHARED
   CLASS VAR nCurr      SHARED
   CLASS VAR cLauncher  SHARED INIT ""
   CLASS VAR lReadIni   SHARED INIT .F.
   CLASS VAR options    SHARED INIT { => }
   CLASS VAR aCmdHis    SHARED INIT {}
   CLASS VAR aSeaHis    SHARED INIT {}
   CLASS VAR aCBoards   SHARED
   CLASS VAR aHiliAttrs SHARED INIT { "W+/B", "W+/B", "GR+/B", "W/B" }

   DATA   aRect       INIT { 0,0,24,79 }
   DATA   y1, x1, y2, x2
   DATA   cColor      INIT "BG+/B"
   DATA   cColorSel   INIT "N/W"
   DATA   cColorPane  INIT "N/BG"
   DATA   cFileName   INIT ""
   DATA   cp, cpInit
   DATA   nxFirst, nyFirst
   DATA   aText
   DATA   nMode
   DATA   nDopMode    INIT 0
   DATA   cSyntaxType

   DATA   lBorder     INIT .F.
   DATA   lTopPane    INIT .T.
   DATA   nTopName    INIT 36

   DATA   lCtrlTab    INIT .T.
   DATA   lReadOnly   INIT .F.
   DATA   lUtf8       INIT .F.
   DATA   lUpdated    INIT .F.
   DATA   lIns        INIT .T.
   DATA   lShiftKey   INIT .F.

   DATA   nCol, nRow
   DATA   lF3         INIT .F.
   DATA   nby1        INIT -1
   DATA   nby2        INIT -1
   DATA   nbx1, nbx2
   DATA   lTextOut    INIT .F.

   DATA   lShow
   DATA   lClose      INIT .F.
   DATA   cEol

   DATA   funSave
   DATA   oHili
   DATA   hBookMarks

   METHOD New( cText, cFileName, y1, x1, y2, x2, cColor )
   METHOD Edit()
   METHOD TextOut( n1, n2 )
   METHOD LineOut( nLine )
   METHOD onKey( nKeyExt )
   METHOD WriteTopPane( lFull )
   METHOD Search( cSea, lCase, lNext, ny, nx )
   METHOD GoTo( ny, nx, nSele )
   METHOD ToString( cEol )
   METHOD Save( cFileName )
   METHOD Undo( nLine1, nPos1, nLine2, nPos2, nOper, cText )
   METHOD Highlighter( oHili )

ENDCLASS

METHOD New( cText, cFileName, y1, x1, y2, x2, cColor ) CLASS TEdit

   LOCAL i, cExt

   IF !::lReadIni
      edi_ReadIni( hb_DirBase() + "hbedit.ini" )
   ENDIF
   IF !Empty( cFileName )
      ::cFileName := cFileName
   ENDIF
   ::aRect[1] := Iif( y1==Nil, ::aRect[1], y1 )
   ::aRect[2] := Iif( x1==Nil, ::aRect[2], x1 )
   ::aRect[3] := Iif( y2==Nil, ::aRect[3], y2 )
   ::aRect[4] := Iif( x2==Nil, ::aRect[4], x2 )
   ::cColor := Iif( Empty(cColor), ::cColor, cColor )
   ::nxFirst := ::nyFirst := ::nRow := ::nCol := 1

   IF Empty( cText )
      ::aText := { "" }
      ::cEol := Chr(13) + Chr(10)
   ELSE
      ::aText := hb_ATokens( cText, Chr(10) )
      ::cEol := Iif( Right( ::aText[1],1 ) == Chr(13), Chr(13) + Chr(10), Chr(10) )
   ENDIF

   ::cp := ::cpInit := hb_cdpSelect()
   IF hb_hGetDef( TEdit():options, "syntax", .F. )
      cExt := Lower( hb_fnameExt(cFileName) )
      FOR i := 1 TO Len(aLangExten)
         IF cExt $ aLangExten[i,2] .AND. hb_hHaskey(aLangs,aLangExten[i,1])
            mnu_SyntaxOn( Self, aLangExten[i,1] )
            EXIT
         ENDIF
      NEXT
   ENDIF

   ::hBookMarks := hb_Hash()

   IF ::aWindows == Nil
      ::aWindows := {}
   ENDIF
   Aadd( ::aWindows, Self )

   RETURN Self

METHOD Edit() CLASS TEdit

   LOCAL cScBuf := Savescreen( 0, 0, 24, 79 )
   LOCAL i, nKeyExt

   hb_cdpSelect( ::cp )
   ::nCurr := Ascan( ::aWindows, {|o|o==Self} )
   ::nMode := 0

   SetCursor( SC_NONE )
   SetColor( ::cColor )
   ::y1 := ::aRect[1]; ::x1 := ::aRect[2]; ::y2 := ::aRect[3]; ::x2 := ::aRect[4]
   IF ::lBorder
      @ ::y1, ::x1, ::y2, ::x2 BOX "�Ŀ����� "
      ::y1 ++; ::x1 ++; ::y2 --; ::x2 --
   ENDIF
   ::nTopName := Max( ::x2 - ::x1 - 44, 0 )
   IF ::lTopPane
      ::y1 ++
      DevPos( ::y1, ::x1 )
      ::WriteTopPane( .T. )
      SetColor( ::cColor )
   ENDIF
   Scroll( ::y1, ::x1, ::y2, ::x2 )

   ::TextOut()

   DevPos( ::y1, ::x1 )
   ::lShow := .T.
   DO WHILE ::lShow
      SetCursor( Iif( ::lIns, SC_NORMAL, SC_SPECIAL1 ) )
      nKeyExt := Inkey( 0, HB_INKEY_ALL + HB_INKEY_EXT )
      SetCursor( SC_NONE )
      ::onKey( nKeyExt )
   ENDDO

   hb_cdpSelect( ::cpInit )
   Restscreen( 0, 0, 24, 79, cScBuf )

   IF ::lClose
      i := Ascan( ::aWindows, {|o|o==Self} )
      hb_ADel( ::aWindows, i, .T. )
   ENDIF

   RETURN Nil

METHOD TextOut( n1, n2 ) CLASS TEdit

   LOCAL i, nKol := ::y2 -::y1 + 1, x := Col(), y := Row()

   IF n1 == Nil; n1 := 1; ENDIF
   IF n2 == Nil; n2 := nKol; ENDIF

   FOR i := n1 TO n2
      ::LineOut( i )
   NEXT
   DevPos( y, x )

   RETURN Nil

METHOD LineOut( nLine ) CLASS TEdit

   LOCAL n := nLine + ::nyFirst - 1, nWidth := ::x2 - ::x1 + 1, nLen
   LOCAL lSel := .F., nby1, nby2, nbx1, nbx2, xs1, xs2
   LOCAL aStru, i

   IF n <= Len( ::aText )
      IF Right( ::aText[n],1 ) == Chr(13)
         ::aText[n] := cp_Left( ::lUtf8, ::aText[n], cp_Len( ::lUtf8, ::aText[n])-1 )
      ENDIF

      DevPos( ::y1 + nLine - 1, ::x1 )
      nLen := Max( 0, Min( nWidth, cp_Len( ::lUtf8,::aText[n])-::nxFirst+1 ) )

      DispBegin()
      IF nLen > 0
         DevOut( cp_Substr( ::lUtf8, ::aText[n], ::nxFirst, nLen ) )
      ENDIF

      IF !Empty( ::oHili ) .AND. hb_hGetDef( TEdit():options, "syntax", .F. )
         ::oHili:Do( n )
         aStru := ::oHili:aLineStru
         IF ::oHili:nItems > 0
            FOR i := 1 TO ::oHili:nItems
               IF aStru[i,2] >= ::nxFirst .AND. aStru[i,3] > 0
                  nbx1 := Max( ::nxFirst, aStru[i,1] ); nbx2 := aStru[i,2]
                  DevPos( ::y1 + nLine - 1, nbx1 -::nxFirst )
                  SetColor( ::aHiliAttrs[aStru[i,3]] )
                  DevOut( cp_Substr( ::lUtf8, ::aText[n], nbx1, nbx2-nbx1+1 ) )
               ENDIF
            NEXT
         ENDIF
      ENDIF
      IF ::nby1 >= 0 .AND. ::nby2 >= 0
         IF ::nby1 < ::nby2 .OR. ( ::nby1 == ::nby2 .AND. ::nbx1 < ::nbx2 )
            nby1 := ::nby1; nbx1 := ::nbx1; nby2 := ::nby2; nbx2 := ::nbx2
         ELSE
            nby1 := ::nby2; nbx1 := ::nbx2; nby2 := ::nby1; nbx2 := ::nbx1
         ENDIF
         lSel := ( n >= nby1 .AND. n <= nby2 ) .AND. !( nby1 == nby2 .AND. nbx1 == nbx2 )
      ENDIF
      SetColor( ::cColor )
      IF lSel
         nbx1 := Iif( n > nby1, 1, nbx1 )
         nbx2 := Iif( n < nby2, cp_Len(::lUtf8,::aText[n])+1, nbx2 )
         DevPos( ::y1 + nLine - 1, nbx1 -::nxFirst )
         SetColor( ::cColorSel )
         DevOut( cp_Substr( ::lUtf8, ::aText[n], nbx1, nbx2-nbx1 ) )
         SetColor( Iif( n < nby2, ::cColorSel, ::cColor ) )
      ENDIF
      IF nLen < nWidth
         Scroll( ::y1 + nLine - 1, ::x1 + nLen, ::y1 + nLine - 1, ::x2 )
      ENDIF
      SetColor( ::cColor )
      DispEnd()
   ELSE
      Scroll( ::y1 + nLine - 1, ::x1, ::y1 + nLine - 1, ::x2 )
   ENDIF
   RETURN Nil

METHOD onKey( nKeyExt ) CLASS TEdit

   LOCAL nKey := hb_keyStd(nKeyExt), i, n, nCol := Col(), nRow := Row()
   LOCAL s, lShift, lCtrl := .F., lNoDeselect := .F., lSkip := .F.

   ::nCol := nCol; ::nRow := nRow
   n := nRow - ::y1 + ::nyFirst
   ::lTextOut := .F.

   IF ::nDopMode == 109     // m
      edi_BookMarks( Self, nKey, .T. )
      ::nDopMode := 0
      lSkip := .T.
   ELSEIF ::nDopMode == 39  // '
      edi_BookMarks( Self, nKey, .F. )
      ::nDopMode := 0
      lSkip := .T.
   ENDIF

   IF !lSkip
      lShift := ( hb_BitAnd( nKeyExt, SHIFT_PRESSED ) != 0 .AND. Ascan( aKeysMove, nkey ) != 0 )
      IF lShift
         IF !::lShiftKey
            ::nby1 := ::nRow - ::y1 + ::nyFirst
            ::nbx1 := ::nCol - ::x1 + ::nxFirst
            ::lShiftKey := .T.
         ENDIF
      ELSE
         ::lShiftKey := .F.
      ENDIF
      IF hb_BitAnd( nKeyExt, ALT_PRESSED ) != 0
         IF nKey == K_ALT_F7
            mnu_SeaNext( Self, .F. )

         ELSEIF nKey == K_ALT_F8
            mnu_GoTo( Self )
            ::lTextOut := .T.

         ENDIF
      ENDIF
      IF hb_BitAnd( nKeyExt, CTRL_PRESSED ) != 0

         lCtrl := .T.
         IF nKey == K_CTRL_INS .OR. nKey == 3       // Ctrl-Ins or Ctrl-c
            IF !Empty( s := Text2cb( Self ) )
               hb_gtInfo( HB_GTI_CLIPBOARDDATA, TEdit():aCBoards[1,1] := s )
               TEdit():aCBoards[1,2] := Nil
            ENDIF

         ELSEIF nKey == 22                          // Ctrl-v
            IF !::lReadOnly
               cb2Text( Self )
            ENDIF

         ELSEIF nKey == K_CTRL_Z .AND. hb_keyVal( nKeyExt ) == 90
            mnu_ChgMode( Self )

         ELSEIF nKey == K_CTRL_Y
            IF !::lReadOnly .AND. n > 0 .AND. n <= Len( ::aText )
               hb_ADel( ::aText, n, .T. )
               ::lTextOut := .T.
               ::Undo( n ) //, nPos1, nLine2, nPos2, nOper, cText )
               ::lUpdated := .T.
            ENDIF

         ELSEIF nKey == K_CTRL_A
            IF !::lF3
               ::nby1 := ::nbx1 := 1
               ::nby2 := Len( ::aText )
               ::nbx2 := cp_Len( ::lUtf8, ::aText[Len(::aText)] )
               ::lF3 := .T.
            ENDIF

         ELSEIF nKey == K_CTRL_TAB
            IF ::lCtrlTab
               ::lShow := .F.
               ::nCurr ++
            ENDIF

         ELSEIF nKey == K_CTRL_PGUP
            ::lTextOut := (::nyFirst>1 .OR. ::nxFirst>1)
            ::nxFirst := ::nyFirst := 1
            DevPos( ::y1, ::x1 )

         ELSEIF nKey == K_CTRL_PGDN
            IF Len( ::aText ) > ::y2-::y1+1
               ::nxFirst := 1
               ::nyFirst := Len( ::aText ) - (::y2-::y1)
               ::lTextOut := .T.
               DevPos( ::y2, Min( nCol,cp_Len( ::lUtf8,ATail(::aText))+1 ) )
            ELSE
               DevPos( Len(::aText)+::y1-1, Min( nCol,cp_Len( ::lUtf8,ATail(::aText))+1 ) )
            ENDIF

         ELSEIF nKey == K_CTRL_D
            mnu_Exit( Self )

         ELSEIF nKey == K_CTRL_RIGHT .AND. hb_keyVal( nKeyExt ) == 16
            edi_NextWord( Self )

         ELSEIF nKey == K_CTRL_LEFT .AND. hb_keyVal( nKeyExt ) == 15
            edi_PrevWord( Self )

         ENDIF
      ELSE
         IF ( nKey >= K_SPACE .AND. nKey <= 255 ) .OR. ( ::lUtf8 .AND. nKey > 3000 )
            IF !::lReadOnly
               IF ::nby1 >= 0 .AND. ::nby2 >= 0
                  nKey := edi_MapKey( Self, nKey )
                  IF nKey == 85   // U  Convert to upper case
                     edi_ConvertCase( Self, .T. )
                     ::Undo( Min(::nby1,::nby2) )
                     ::lUpdated := .T.
                     ::lTextOut := ( ::nby1 != ::nby2 )
                     lNoDeselect := .T.
                  ELSEIF nKey == 117   // u Convert to lower case
                     ::Undo( n )
                     edi_ConvertCase( Self, .F. )
                     ::lUpdated := .T.
                     ::lTextOut := ( ::nby1 != ::nby2 )
                     lNoDeselect := .T.
                  ELSEIF nKey == 119   // w Move to the next word
                     edi_NextWord( Self )
                     nKey := K_RIGHT
                  ELSEIF nKey == 101   // e Move to the end of word
                     edi_NextWord( Self, .T. )
                     nKey := K_RIGHT
                  ELSEIF nKey == 98    // b Move to the previous word
                     edi_PrevWord( Self )
                     nKey := K_LEFT
                  ELSEIF nKey == 100   // d Deletes selection
                     mnu_DelSelected( Self )
                  ELSEIF nKey == 121   // y Copy to clipboard
                     IF !Empty( s := Text2cb( Self ) )
                        hb_gtInfo( HB_GTI_CLIPBOARDDATA, TEdit():aCBoards[1,1] := s )
                        TEdit():aCBoards[1,2] := Nil
                     ENDIF
                  ELSEIF nKey == 62    // > Shift lines right
                     edi_Indent( Self, .T. )
                     lNoDeselect := .T.
                  ELSEIF nKey == 60    // > Shift lines left
                     edi_Indent( Self, .F. )
                     lNoDeselect := .T.
                  ENDIF
               ELSEIF ::nMode == 1
                  nKey := edi_MapKey( Self, nKey )
                  IF nKey == 119   // w Move to the next word
                     edi_NextWord( Self )
                  ELSEIF nKey == 101   // e Move to the end of word
                     edi_NextWord( Self, .T. )
                  ELSEIF nKey == 98    // b Move to the previous word
                     edi_PrevWord( Self )
                  ELSEIF nKey == 118   // v Start selection
                     mnu_F3( Self )
                     nKey := K_RIGHT
                  ELSEIF nKey == 109 .OR. nKey == 39  // m - set bookmark, ' - goto bookmark
                     ::nDopMode := nKey
                  ENDIF
               ELSE
                  IF ( i := (nCol - ::x1 + ::nxFirst - cp_Len(::lUtf8,::aText[n])) ) > 0
                     ::aText[n] += Space( i-1 ) + cp_Chr(::lUtf8,nKey)
                  ELSE
                    ::aText[n] := cp_Left( ::lUtf8, ::aText[n], nCol-::x1+::nxFirst-1 ) + cp_Chr(::lUtf8,nKey) + ;
                       cp_Substr( ::lUtf8, ::aText[n], nCol-::x1+::nxFirst+Iif(::lIns,0,1) )
                  ENDIF
                  IF nCol == ::x2
                     ::nxFirst ++
                     ::lTextOut := .T.
                  ELSE
                     ::LineOut( nRow - ::y1 + 1 )
                     DevPos( nRow, nCol+1 )
                  ENDIF
                  ::Undo( n )
                  ::lUpdated := .T.
               ENDIF
            ENDIF

         ELSEIF nKey == K_ENTER
            IF !::lReadOnly
               nCol := nCol - ::x1 + ::nxFirst
               s := ""
               IF hb_hGetDef( TEdit():options, "autoindent", .F. )
                  i := 0
                  DO WHILE cp_Substr( ::lUtf8, ::aText[n], i+1, 1 ) == " "; i++; ENDDO
                  IF i > 0
                     s := Space( i )
                  ENDIF
               ENDIF
               hb_AIns( ::aText, n+1, s + cp_Substr( ::lUtf8, ::aText[n],nCol ), .T. )
               ::aText[n] := cp_Left( ::lUtf8, ::aText[n], nCol-1 )
               ::nxFirst := 1
               IF nRow == ::y2
                  ::nyFirst ++
                  DevPos( nRow, ::x1 )
               ELSE
                  DevPos( nRow+1, ::x1 )
               ENDIF
               ::lTextOut := .T.
               ::Undo( n )
               ::lUpdated := .T.
            ENDIF

         ELSEIF nKey == K_DEL
            IF !::lReadOnly
               IF ::nby1 >= 0 .AND. ::nby2 >= 0
                  IF hb_BitAnd( nKeyExt, SHIFT_PRESSED ) != 0 .AND. !Empty( s := Text2cb( Self ) )
                     hb_gtInfo( HB_GTI_CLIPBOARDDATA, TEdit():aCBoards[1,1] := s )
                     TEdit():aCBoards[1,2] := Nil
                  ENDIF
                  mnu_DelSelected( Self )
               ELSE
                  IF nCol == cp_Len( ::lUtf8, ::aText[n] ) - ::nxFirst + 1
                     IF n < Len( ::aText )
                        ::aText[n] := ::aText[n] + ::aText[n+1]
                        hb_ADel( ::aText, n+1, .T. )
                        ::lTextOut := .T.
                     ENDIF
                  ELSE
                     ::aText[n] := cp_Left( ::lUtf8, ::aText[n], nCol-::x1+::nxFirst-1 ) + ;
                        cp_Substr( ::lUtf8, ::aText[n], nCol-::x1+::nxFirst+1 )
                     ::LineOut( nRow - ::y1 + 1 )
                  ENDIF
               ENDIF
               DevPos( nRow, nCol )
               ::Undo( n )
               ::lUpdated := .T.
            ENDIF

         ELSEIF nKey == K_BS
            IF !::lReadOnly
               IF ::nby1 >= 0 .AND. ::nby2 >= 0
                  IF hb_BitAnd( nKeyExt, SHIFT_PRESSED ) != 0 .AND. !Empty( s := Text2cb( Self ) )
                     hb_gtInfo( HB_GTI_CLIPBOARDDATA, TEdit():aCBoards[1,1] := s )
                     TEdit():aCBoards[1,2] := Nil
                  ENDIF
                  mnu_DelSelected( Self )
               ELSE
                  IF nCol == ::x1
                     IF n > 1
                        ::onKey( K_UP )
                        ::onKey( K_END )
                        ::aText[n-1] := ::aText[n-1] + ::aText[n]
                        hb_ADel( ::aText, n, .T. )
                        ::lTextOut := .T.
                     ENDIF
                  ELSE
                     ::aText[n] := cp_Left( ::lUtf8, ::aText[n], nCol-::x1+::nxFirst-2 ) + ;
                        cp_Substr( ::lUtf8, ::aText[n], nCol-::x1+::nxFirst )
                     ::LineOut( nRow - ::y1 + 1 )
                     DevPos( nRow, nCol-1 )
                  ENDIF
               ENDIF
               ::Undo( n )
               ::lUpdated := .T.
            ENDIF

         ELSEIF nKey == K_TAB
            IF !::lReadOnly
            ENDIF

         ELSEIF nKey == K_INS
            IF hb_BitAnd( nKeyExt, SHIFT_PRESSED ) != 0
               IF !::lReadOnly
                  cb2Text( Self )
               ENDIF
            ELSE
               ::lIns := !::lIns
            ENDIF

         ELSEIF nKey == K_UP
            IF nRow == ::y1
               IF ::nyFirst > 1
                  ::nyFirst --
                  ::lTextOut := .T.
               ENDIF
            ELSE
               DevPos( nRow-1, Col() )
            ENDIF

         ELSEIF nKey == K_DOWN
            IF nRow - ::y1 + ::nyFirst < Len(::aText)
               IF nRow < ::y2
                  DevPos( nRow+1, Col() )
               ELSE
                  ::nyFirst ++
                  ::lTextOut := .T.
               ENDIF
            ENDIF

         ELSEIF nKey == K_LEFT
            IF nCol == ::x1
               IF ::nxFirst > 1
                  ::nxFirst --
                  ::lTextOut := .T.
               ENDIF
            ELSE
               DevPos( Row(), nCol-1 )
            ENDIF

         ELSEIF nKey == K_RIGHT
            IF nCol == ::x2
               ::nxFirst ++
               ::lTextOut := .T.
            ELSE
               DevPos( Row(), nCol+1 )
            ENDIF

         ELSEIF nKey == K_HOME
            IF ::nxFirst > 1
               ::nxFirst := 1
               ::lTextOut := .T.
            ENDIF
            DevPos( Row(), ::x1 )

         ELSEIF nKey == K_END
            nCol := cp_Len( ::lUtf8, ::aText[n] ) - ::nxFirst + 1
            IF nCol <= 0 .OR. nCol > ::x2 - ::x1
               ::nxFirst := Max( 1, cp_Len( ::lUtf8, ::aText[n] ) - ( ::x2 - ::x1 ) + 1 )
               ::lTextOut := .T.
               DevPos( Row(), Iif( nCol <= 0, cp_Len( ::lUtf8, ::aText[n] ) - ::nxFirst + 1, ::x2 ) )
            ELSE
               DevPos( Row(), nCol )
            ENDIF

         ELSEIF nKey == K_PGUP
            i := 1
            DO WHILE i <= ::y2 - ::y1
               IF ( nRow := Row() ) == ::y1
                  IF ::nyFirst > 1
                     ::nyFirst --
                     ::lTextOut := .T.
                  ENDIF
               ELSE
                  DevPos( nRow-1, Col() )
               ENDIF
               i ++
            ENDDO

         ELSEIF nKey == K_PGDN
            i := 1
            DO WHILE ( nRow := Row() ) - ::y1 + ::nyFirst < Len(::aText) .AND. i <= ::y2 - ::y1
               IF nRow < ::y2
                  DevPos( nRow+1, Col() )
               ELSE
                  ::nyFirst ++
                  ::lTextOut := .T.
               ENDIF
               i ++
            ENDDO

         ELSEIF nKey == K_LBUTTONDOWN
            nCol := MCol()
            nRow := MRow()
            IF ::lTopPane .AND. nRow == ::y1-1 .AND. nCol < 8
               FMenu( Self, aMenuMain )
               ::lTextOut := .T.
            ELSEIF nRow >= ::y1 .AND. nRow <= ::y2 .AND. nCol >= ::x1 .AND. nCol <= ::x2
               IF nRow - ::y1 + ::nyFirst > Len(::aText)
                  nRow := Len(::aText) - ::nyFirst + ::y1
               ENDIF
               DevPos( nRow, nCol )
            ENDIF

         ELSEIF nKey == K_ALT_TAB
            ::lShow := .F.
            ::nCurr --

         ELSEIF nKey == K_F1
            mnu_Help( Self )
            DevPos( ::nRow, ::nCol )

         ELSEIF nKey == K_F2
            ::Save()

         ELSEIF nKey == K_SH_F2
            mnu_Save( Self, .T. )

         ELSEIF nKey == K_F3
            mnu_F3( Self )
            nKey := K_RIGHT

         ELSEIF nKey == K_F4
            mnu_Syntax( Self, {8, 32} )
            ::lTextOut := .T.

         ELSEIF nKey == K_F7
            mnu_Search( Self )
            ::lTextOut := .T.

         ELSEIF nKey == K_F9
            FMenu( Self, aMenuMain )
            ::lTextOut := .T.
            DevPos( ::nRow, ::nCol )

         ELSEIF nKey == K_F10 .OR. nKey == K_ESC
            IF ::nMode == 1 .AND. nKey == K_ESC
               mnu_ChgMode( Self, .T. )
            ELSE
               mnu_Exit( Self )
            ENDIF

         ELSEIF nKey == K_F11
            mnu_Plugins( Self )
            ::lTextOut := .T.

         ELSEIF nKey == K_F12
            mnu_Windows( Self, {7, 22} )
            ::lTextOut := .T.

         ELSEIF nKey == K_SH_F7
            mnu_SeaNext( Self, .T. )

         ELSEIF nKey == K_SH_F8
            mnu_cPages( Self )
            ::lTextOut := .T.
         ENDIF
      ENDIF

      IF ::lF3 .AND. nKey != K_MOUSEMOVE .AND. Ascan( aKeysMove, nKey ) == 0
         ::lF3 := .F.
      ENDIF
      IF (::lF3 .OR. lShift)
         IF !( lCtrl .AND. nKey == K_CTRL_A)
            ::nby2 := Row() - ::y1 + ::nyFirst
            ::nbx2 := Col() - ::x1 + ::nxFirst
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

   ::nCol := Col(); ::nRow := Row()
   ::WriteTopPane()

   RETURN Nil

METHOD WriteTopPane( lFull ) CLASS TEdit

   LOCAL y := ::y1 - 1, nCol := ::nCol, nRow := ::nRow
   LOCAL cLen := Ltrim(Str(Len(::aText))), nchars := Len(cLen)

   IF ::lTopPane
      SetColor( ::cColorPane )
      IF !Empty( lFull )
         Scroll( y, ::x1, y, ::x2 )
         DevPos( y, ::x1 )
         DevOut( "F9-menu " + NameShortcut( ::cFileName, ::nTopName, '~' ) )
      ELSE
         Scroll( y, ::x1 + 8 + ::nTopName, y, ::x2 )
      ENDIF
      DevPos( y, ::x1 + 8 + ::nTopName + 2 )
      DevOut( Iif( ::lUpdated, "* ", "  " ) + Lower( ::cp ) )
      DevPos( y, ::x1 + 8 + ::nTopName + 10 )
      DevOut( PAdl(Ltrim(Str(nRow-::y1+::nyFirst)),nchars) + "/" + cLen )
      DevPos( y, ::x1 + 8 + ::nTopName + 10 + nchars*2 + 3 )
      DevOut( "[" + Ltrim(Str(nCol-::x1+::nxFirst)) + "]" )     
      DevPos( y, ::x2 - 5 )
      DevOut( Iif( ::nDopMode>0, Chr(::nDopMode)+" ", "  " ) )
      SetColor( "W+/N" )
      IF ::lF3 .OR. (::nby1 >= 0 .AND. ::nby2 >= 0)
         DevOut( "Sele" )
      ELSE
         DevOut( Iif( ::nMode == 0, "Edit", Iif( ::nMode == 1, " Vim", " Cmd" ) ) )
      ENDIF
      SetColor( ::cColor )
      DevPos( nRow, nCol )
   ENDIF

   RETURN Nil

METHOD Search( cSea, lCase, lNext, ny, nx ) CLASS TEdit

   LOCAL lRes := .F., i, nLen := Len( ::aText ), nPos, s

   IF !lCase
      cSea := cp_Lower( ::lUtf8, cSea )
   ENDIF
   IF lNext
      s := cp_Substr( ::lUtf8, ::aText[ny], nx, cp_Len(::lUtf8,cSea) )
      IF cSea == Iif( lCase, s, cp_Lower( ::lUtf8,s ) )
         nx ++
      ENDIF
      FOR i := ny TO nLen
         s := Iif( lCase, ::aText[i], cp_Lower( ::lUtf8, ::aText[i] ) )
         IF ( nPos := cp_At( ::lUtf8, cSea, s, Iif( i == ny, nx, 1 ) ) ) > 0
            lRes := .T.; ny := i; nx := nPos
            EXIT
         ENDIF
      NEXT
   ELSE
      s := cp_Substr( ::lUtf8, ::aText[ny], nx, cp_Len(::lUtf8,cSea) )
      IF cSea == Iif( lCase, s, cp_Lower( ::lUtf8,s ) )
         nx --
      ENDIF
      FOR i := ny TO 1 STEP -1
         s := Iif( lCase, ::aText[i], cp_Lower( ::lUtf8, ::aText[i] ) )
         IF ( nPos := cp_RAt( ::lUtf8, cSea, s, 1, Iif( i == ny, nx, cp_Len(::lUtf8,::aText[i]) ) ) ) > 0
            lRes := .T.; ny := i; nx := nPos 
            EXIT
         ENDIF
      NEXT
   ENDIF

   RETURN lRes

METHOD GoTo( ny, nx, nSele ) CLASS TEdit

   LOCAL lTextOut := .F., nRowOld

   IF nx == Nil; nx := 1; ENDIF
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

   SetColor( ::cColor )
   IF lTextOut
      ::TextOut()
   ELSEIF nSele != Nil .AND. nSele > 0
      IF ( nRowOld := (::nRow - ::y1 + 1) ) > 0
         ::LineOut( nRowOld )
      ENDIF
      ::LineOut( ny - ::nyFirst + 1 )
   ENDIF
   ::WriteTopPane()
   DevPos( ::nRow := (ny - ::nyFirst + ::y1), ::nCol := (nx - ::nxFirst + ::x1) )

   RETURN Nil

METHOD ToString( cEol ) CLASS TEdit

   LOCAL i, s := ""

   IF Empty( cEol )
      cEol := ::cEol
   ENDIF
   FOR i := 1 TO Len( ::aText )
      s += Iif( Right(::aText[i],1) == Chr(13), Left(::aText[i],Len(::aText[i])-1), ::aText[i] ) + cEol
   NEXT

   RETURN s

METHOD Save( cFileName ) CLASS TEdit

   IF cFileName == Nil
      cFileName := ::cFileName
   ENDIF
   IF Empty( cFileName )
      cFileName := edi_FileName( Self )
      ::lTextOut := .T.
   ENDIF

   IF Empty( cFileName )
      RETURN Nil
   ELSE
      IF Empty( hb_fnameDir( cFileName ) )
         cFileName := edi_CurPath() + cFileName
      ENDIF
      ::cFileName := cFileName
   ENDIF

   IF Empty( ::funSave )
      hb_MemoWrit( cFileName, ::ToString() )
   ELSE
      ::funsave:exec( cFileName, ::ToString() )
   ENDIF
   ::lUpdated := .F.

   RETURN Nil

METHOD Undo( nLine1, nPos1, nLine2, nPos2, nOper, cText ) CLASS TEdit

   IF !Empty( ::oHili )
      ::oHili:UpdSource( nLine1 )
   ENDIF
   
   RETURN Nil

METHOD Highlighter( oHili ) CLASS TEdit

   IF oHili == Nil
      ::oHili := Nil
   ELSE
      ::oHili := oHili:Set( Self )
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

   LOCAL s := "", i, nby1, nby2, nbx1, nbx2

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
            IF i == nby1
               s += cp_Substr( oEdit:lUtf8, oEdit:aText[i], nbx1 ) + Chr(10)
            ELSEIF i == nby2
               s += cp_Left( oEdit:lUtf8, oEdit:aText[i], nbx2-1 )
            ELSE
               s += oEdit:aText[i] + oEdit:cEol
            ENDIF
         NEXT
      ENDIF
   ENDIF

   RETURN s

STATIC FUNCTION cb2Text( oEdit )

   LOCAL arr, n := oEdit:nRow - oEdit:y1 + oEdit:nyFirst
   LOCAL i, lMulti := .F., s := hb_gtInfo( HB_GTI_CLIPBOARDDATA )

   TEdit():aCBoards[1,1] := s
   TEdit():aCBoards[1,2] := Nil
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
      IF ( i := FMenu( oEdit, aMenu_CB ) ) != Nil
         s := TEdit():aCBoards[i,1]
         IF !Empty( TEdit():aCBoards[i,2] ) .AND. !( TEdit():aCBoards[i,2] == oEdit:cp )
            s := hb_Translate( s, TEdit():aCBoards[i,2], oEdit:cp )
         ENDIF
      ENDIF
      oEdit:lTextOut := .T.
   ENDIF

   IF Chr(10) $ s
      arr := hb_ATokens( s, Chr(10) )
      s := cp_Substr( oEdit:lUtf8, oEdit:aText[n], oEdit:nCol-oEdit:x1+oEdit:nxFirst )
      oEdit:aText[n] := cp_Left( oEdit:lUtf8, oEdit:aText[n], oEdit:nCol-oEdit:x1+oEdit:nxFirst-1 ) + arr[1]
      FOR i := 2 TO Len(arr)-1
         hb_AIns( oEdit:aText, n+i-1, arr[i], .T. )
      NEXT
      hb_AIns( oEdit:aText, n+i-1, arr[i] + s, .T. )
      oEdit:lTextOut := .T.
   ELSE
      oEdit:aText[n] := cp_Left( oEdit:lUtf8, oEdit:aText[n], oEdit:nCol-oEdit:x1+oEdit:nxFirst-1 ) + s + ;
         cp_Substr( oEdit:lUtf8, oEdit:aText[n], oEdit:nCol-oEdit:x1+oEdit:nxFirst )
      oEdit:nCol += cp_Len( oEdit:lUtf8, s )
      IF oEdit:nCol > oEdit:x2
         oEdit:nxFirst += oEdit:nCol
         oEdit:lTextOut := .T.
      ELSE
         oEdit:LineOut( oEdit:nRow - oEdit:y1 + 1 )
         DevPos( oEdit:nRow, oEdit:nCol )
      ENDIF
   ENDIF
   oEdit:Undo( n )
   oEdit:lUpdated := .T.

   RETURN Nil

STATIC FUNCTION cbDele( oEdit )

   LOCAL i, n, nby1, nby2, nbx1, nbx2, ncou := 0

   IF oEdit:nby1 >= 0 .AND. oEdit:nby2 >= 0
      IF oEdit:nby1 < oEdit:nby2 .OR. ( oEdit:nby1 == oEdit:nby2 .AND. oEdit:nbx1 < oEdit:nbx2 )
         nby1 := oEdit:nby1; nbx1 := oEdit:nbx1; nby2 := oEdit:nby2; nbx2 := oEdit:nbx2
      ELSE
         nby1 := oEdit:nby2; nbx1 := oEdit:nbx2; nby2 := oEdit:nby1; nbx2 := oEdit:nbx1
      ENDIF
      IF nby1 == nby2
         oEdit:aText[nby1] := Left( oEdit:aText[nby1], nbx1-1 ) + Substr( oEdit:aText[nby1], nbx2 )
         IF nby1 >= oEdit:nyFirst .AND. nby1 < oEdit:nyFirst + (oEdit:y2 - oEdit:y1 + 1)
            oEdit:LineOut( nby1 - oEdit:nyFirst + 1 )
         ENDIF
      ELSE
         IF nbx1 > 1
            oEdit:aText[nby1] := Left( oEdit:aText[nby1], nbx1-1 )
            n := nby1 + 1
         ELSE
            ADel( oEdit:aText, nby1 )
            n := nby1
            ncou ++
         ENDIF
         FOR i := nby1+1 TO nby2-1
            ADel( oEdit:aText, n )
            ncou ++
         NEXT
         oEdit:aText := ASize( oEdit:aText, Len(oEdit:aText) - ncou )
         oEdit:aText[nby1+1] := Substr( oEdit:aText[nby1+1], nbx2 )
         IF ( i := oEdit:nby1 - oEdit:nyFirst + 1 ) > 0 .AND. i < (oEdit:y2-oEdit:y1+1)
            DevPos( oEdit:nRow := (oEdit:nby1-oEdit:nyFirst+1-oEdit:y1), oEdit:nCol := (oEdit:nbx1-oEdit:nxFirst+1-oEdit:x1) )
         ELSE
            oEdit:nyFirst := oEdit:nby1
            DevPos( oEdit:nRow := 1, oEdit:nCol := oEdit:nbx1 )
         ENDIF
         oEdit:nby1 := oEdit:nby2 := -1
         oEdit:TextOut()
      ENDIF
      oEdit:Undo( nby1 )
      oEdit:lUpdated := .T.
   ENDIF
   RETURN Nil

FUNCTION edi_ReadIni( xIni )

   LOCAL hIni, aIni, nSect, aSect, arr, s, n, i, cTemp
   LOCAL lIncSea := .F., lAutoIndent := .F., lSyntax := .T., ncmdhis := 20, nseahis := 20
   LOCAL hHili

   TEdit():lReadIni := .T.
   hIni := Iif( Valtype( xIni ) == "C", hb_iniRead( xIni ), xIni )

   SetBlink( .F. )
   aLangs := hb_Hash()

   IF !Empty( hIni )
      aIni := hb_hKeys( hIni )
      FOR nSect := 1 TO Len( aIni )
         IF Upper(aIni[nSect]) == "OPTIONS"
            IF !Empty( aSect := hIni[ aIni[nSect] ] )
               hb_hCaseMatch( aSect, .F. )
               IF hb_hHaskey( aSect, "incsearch" ) .AND. !Empty( cTemp := aSect[ "incsearch" ] )
                  lIncSea := ( Lower(cTemp) == "on" )
               ENDIF
               IF hb_hHaskey( aSect, "autoindent" ) .AND. !Empty( cTemp := aSect[ "autoindent" ] )
                  lAutoIndent := ( Lower(cTemp) == "on" )
               ENDIF
               IF hb_hHaskey( aSect, "syntax" ) .AND. !Empty( cTemp := aSect[ "syntax" ] )
                  lSyntax := ( Lower(cTemp) == "on" )
               ENDIF
               IF hb_hHaskey( aSect, "cmdhismax" ) .AND. !Empty( cTemp := aSect[ "cmdhismax" ] )
                  ncmdhis :=  Val(cTemp)
               ENDIF
               IF hb_hHaskey( aSect, "seahismax" ) .AND. !Empty( cTemp := aSect[ "seahismax" ] )
                  nseahis :=  Val(cTemp)
               ENDIF
               IF hb_hHaskey( aSect, "langmap_cp" ) .AND. !Empty( cTemp := aSect[ "langmap_cp" ] )
                  IF Ascan( TEdit():aCPages, cTemp ) > 0
                     cLangMapCP := cTemp
                  ENDIF
               ENDIF
               IF hb_hHaskey( aSect, "langmap_upper" ) .AND. !Empty( cTemp := aSect[ "langmap_upper" ] )
                  aLangMapUpper := hb_aTokens( cTemp )
               ENDIF
               IF hb_hHaskey( aSect, "langmap_lower" ) .AND. !Empty( cTemp := aSect[ "langmap_lower" ] )
                  aLangMapLower := hb_aTokens( cTemp )
               ENDIF
            ENDIF
         ELSEIF Upper(aIni[nSect]) == "KEYBOARD"
            IF !Empty( aSect := hIni[ aIni[nSect] ] )
               hb_hCaseMatch( aSect, .F. )
            ENDIF
         ELSEIF Upper(aIni[nSect]) == "PLUGINS"
            IF !Empty( aSect := hIni[ aIni[nSect] ] )
               hb_hCaseMatch( aSect, .F. )
               arr := hb_hKeys( aSect )
               aPlugins := {}
               FOR i := 1 TO Len( arr )
                  s := aSect[ arr[i] ]
                  IF ( n := At( ",", s ) ) > 0
                     cTemp := AllTrim( Left( s,n-1 ) )
                     IF File( hb_DirBase() + "plugins" + hb_ps() + cTemp )
                        s := Substr( s, n+1 )
                        IF ( n := At( ",", s ) ) > 0
                           Aadd( aPlugins, { cTemp, Substr( s, n+1 ), AllTrim( Left( s,n-1 ) ), Nil } )
                        ENDIF
                     ENDIF
                  ENDIF
               NEXT
            ENDIF
         ELSEIF Upper(aIni[nSect]) == "HILIGHT"
            IF !Empty( aSect := hIni[ aIni[nSect] ] )
               hb_hCaseMatch( aSect, .F. )
               IF hb_hHaskey( aSect, "commands" ) .AND. !Empty( cTemp := aSect[ "commands" ] )
                  TEdit():aHiliAttrs[1] := cTemp
               ENDIF
               IF hb_hHaskey( aSect, "funcs" ) .AND. !Empty( cTemp := aSect[ "funcs" ] )
                  TEdit():aHiliAttrs[2] := cTemp
               ENDIF
               IF hb_hHaskey( aSect, "quotes" ) .AND. !Empty( cTemp := aSect[ "quotes" ] )
                  TEdit():aHiliAttrs[3] := cTemp
               ENDIF
               IF hb_hHaskey( aSect, "comments" ) .AND. !Empty( cTemp := aSect[ "comments" ] )
                  TEdit():aHiliAttrs[4] := cTemp
               ENDIF
            ENDIF
         ELSEIF Left( Upper(aIni[nSect]),5 ) == "LANG_"
            IF !Empty( aSect := hIni[ aIni[nSect] ] )
               hb_hCaseMatch( aSect, .F. )
               hHili := aLangs[ Lower(Substr(aIni[nSect],6)) ] := hb_hash()
               IF hb_hHaskey( aSect, "commands" ) .AND. !Empty( cTemp := aSect[ "commands" ] )
                  hHili["commands"] := cTemp
               ENDIF
               IF hb_hHaskey( aSect, "funcs" ) .AND. !Empty( cTemp := aSect[ "funcs" ] )
                  hHili["funcs"] := cTemp
               ENDIF
               IF hb_hHaskey( aSect, "scomm" ) .AND. !Empty( cTemp := aSect[ "scomm" ] )
                  hHili["scomm"] := cTemp
               ENDIF
               IF hb_hHaskey( aSect, "mcomm" ) .AND. !Empty( cTemp := aSect[ "mcomm" ] )
                  hHili["mcomm"] := cTemp
               ENDIF
               IF hb_hHaskey( aSect, "case" ) .AND. !Empty( cTemp := aSect[ "case" ] )
                  hHili["case"] := ( Lower(cTemp) == "on" )
               ENDIF
            ENDIF
         ENDIF
      NEXT
   ENDIF

   TEdit():options["incsearch"]  := lIncSea
   TEdit():options["cmdhismax"]  := ncmdhis
   TEdit():options["seahismax"]  := nseahis
   TEdit():options["autoindent"] := lAutoIndent
   TEdit():options["syntax"] := lSyntax

   TEdit():aCBoards := Array( MAX_CBOARDS,2 )
   FOR i := 1 TO MAX_CBOARDS
      TEdit():aCBoards[i,1] := TEdit():aCBoards[i,2] := ""
   NEXT

   //IF !hb_hHaskey( aLangs, "prg" )
   //   hHili := aLangs["prg"] := hb_hash()
   //   hHili["commands"] := "and case class data do else elseif end endcase enddo endif exit for func function if local loop method next or private proc procedure public request return set seek skip static use while"
   //   hHili["funcs"] := "aadd abs adel aeval afill ains alert alias alltrim array asc ascan asize asort at bof chr col ctod curdir date day dtoc dtos empty eof eval fclose fcreate ferase file fopen found fread fseek fwrite isalpha isdigit islower left len recno right set str stuff substr updated upper val valtype year"
   //   hHili["scomm"] := "//"
   //   hHili["mcomm"] := "/* */"
   //   hHili["case"] := .F.
   //ENDIF

   RETURN Nil

FUNCTION mnu_Help( oEdit )

   LOCAL oHelp := TEdit():New( MemoRead(hb_DirBase() + "hbedit.help"), "Help", ;
         oEdit:aRect[1], oEdit:aRect[2], oEdit:aRect[3], oEdit:aRect[4] )

   oHelp:lReadOnly := .T.
   oHelp:lCtrlTab  := .F.
   oHelp:Edit()

   RETURN Nil

FUNCTION mnu_Exit( oEdit )

   LOCAL nRes := 2

   IF oEdit:lUpdated
      nRes := Alert( "File has been modified. Save?", { "Yes", "No", "Cancel" } )
   ENDIF
   IF nRes == 1 .OR. nRes == 2
      IF nRes == 1
         oEdit:Save()
      ENDIF
      oEdit:lShow := .F.
      oEdit:lClose := .T.
   ENDIF
   RETURN Nil

FUNCTION mnu_CPages( oEdit )

   LOCAL iRes
   STATIC aMenu_cps := { {"cp866",,1}, {"cp1251",,2}, {"fr850",,3}, {"frwin",,4}, {"friso",,5}, {"utf8",,6} }

   IF ( iRes := FMenu( oEdit, aMenu_cps, 13, 40 ) ) != Nil
      oEdit:cp := oEdit:aCPages[iRes]
      hb_cdpSelect( oEdit:cp )
      oEdit:lUtf8 := ( iRes == 6 )
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

FUNCTION mnu_Windows( oEdit, aXY )

   LOCAL aMenu := { {"New",@mnu_NewWin(),Nil} }, i, nCurr := 1

   FOR i := 1 TO Len( oEdit:aWindows )
      IF oEdit:aWindows[i] == oEdit
         nCurr := i + 1
      ENDIF
      AAdd( aMenu, {NameShortcut(oEdit:aWindows[i]:cFileName,30,'~'),@mnu_OpenWin(),i} )
   NEXT
   IF !Empty( oEdit:cLauncher )
      AAdd( aMenu, {oEdit:cLauncher,@mnu_OpenWin(),0} )
   ENDIF

   FMenu( oEdit, aMenu, aXY[1], aXY[2],,,,, nCurr )

   RETURN Nil

FUNCTION mnu_NewWin( oEdit, cText, cFileName )

   LOCAL oNew := TEdit():New( cText, cFileName, oEdit:aRect[1], oEdit:aRect[2], oEdit:aRect[3], oEdit:aRect[4])

   oNew:funSave := oEdit:funSave
   oEdit:lShow := .F.
   oEdit:nCurr := Len( oEdit:aWindows )

   RETURN Nil

FUNCTION mnu_OpenWin( oEdit, n )

   oEdit:lShow := .F.
   oEdit:nCurr := n

   RETURN Nil

FUNCTION mnu_Save( oEdit, lAs )

   LOCAL cFileName, cPath

   IF !Empty( lAs )
      cFileName := edi_FileName( oEdit )
      oEdit:lTextOut := .T.
      IF !Empty( cFileName ) .AND. Empty( hb_fnameDir(cFileName) ) ;
            .AND. !Empty( cPath := hb_fnameDir(oEdit:cFileName) )
         cFileName := cPath + cFileName
      ENDIF
   ENDIF

   oEdit:Save( cFileName )

   RETURN Nil

FUNCTION mnu_F3( oEdit )

   LOCAL i

   IF oEdit:nby1 >= 0 .AND. oEdit:nby2 >= 0
      oEdit:lF3 := .T.
   ENDIF
   IF !oEdit:lF3
      oEdit:nby1 := oEdit:nRow - oEdit:y1 + oEdit:nyFirst
      oEdit:nbx1 := oEdit:nCol - oEdit:x1 + oEdit:nxFirst
      oEdit:nby2 := oEdit:nbx2 := -1
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
      FOR i := 1 TO MAX_CBOARDS
         aMenu_CB[i,1] := cp_Left( oEdit:lUtf8, TEdit():aCBoards[i,1], 32 )
         IF !Empty( TEdit():aCBoards[i,2] ) .AND. !( TEdit():aCBoards[i,2] == oEdit:cp )
            aMenu_CB[i,1] := hb_Translate( aMenu_CB[i,1], TEdit():aCBoards[i,2], oEdit:cp )
         ENDIF
      NEXT
      IF ( i := FMenu( oEdit, aMenu_CB ) ) != Nil
         TEdit():aCBoards[i,1] := Text2cb( oEdit )
         TEdit():aCBoards[i,2] := oEdit:cp
         IF i == 1
            hb_gtInfo( HB_GTI_CLIPBOARDDATA, TEdit():aCBoards[1,1] )
         ENDIF
      ENDIF
      oEdit:lTextOut := .T.
   ENDIF

   RETURN Nil

FUNCTION mnu_DelSelected( oEdit )

   IF !oEdit:lReadOnly
      cbDele( oEdit )
   ENDIF

   RETURN Nil

FUNCTION mnu_Sea_goto( oEdit, aXY )

   LOCAL aMenu := { {"Search",@mnu_Search(),Nil,"F7"}, {"Next",@mnu_SeaNext(),.T.,"Shift-F7"}, ;
      {"Previous",@mnu_SeaNext(),.F.,"Alt-F7"}, {"Go to",@mnu_GoTo(),Nil,"Alt-F8"} }

   FMenu( oEdit, aMenu, aXY[1], aXY[2] )

   RETURN Nil

FUNCTION mnu_Search( oEdit )

   LOCAL oldc := SetColor( "N/W,N/W,,,N/W" ), lRes, i
   LOCAL aGets := { {11,22,0,"",33,"W+/BG","W+/BG"}, ;
      {11,55,2,"[^]",3,"N/W","W+/RB",{||mnu_SeaHist(oEdit,aGets[1])}}, ;
      {12,23,1,.T.,1}, {12,43,1,.F.,1}, ;
      {14,25,2,"[Search]",10,"N/W","W+/BG",{||__KeyBoard(Chr(K_ENTER))}}, ;
      {14,40,2,"[Cancel]",10,"N/W","W+/BG",{||__KeyBoard(Chr(K_ENTER))}} }
   LOCAL cSearch, lCase, lBack := .F.
   LOCAL ny := oEdit:nRow - oEdit:y1 + oEdit:nyFirst, nx := oEdit:nCol - oEdit:x1 + oEdit:nxFirst  

   hb_cdpSelect( "RU866" )
   @ 09, 20, 15, 60 BOX "�Ŀ����� "
   hb_cdpSelect( oEdit:cp )

   @ 10,22 SAY "Search for"
   @ 12, 22 SAY "[ ] Case sensitive"
   @ 12, 42 SAY "[ ] Backward"

   IF !Empty( TEdit():aSeaHis )
      //aGets[1,4] := TEdit():aSeaHis[1]
      aGets[3,4] := lCase_Sea
   ENDIF
   lRes := edi_READ( aGets, oEdit:lUtf8 )

   IF lRes
      cSearch := Trim( aGets[1,4] )
      lCase := aGets[3,4]
      lBack := aGets[4,4]
      IF ( i := Ascan( TEdit():aSeaHis, {|cs|cs==cSearch} ) ) > 0
         ADel( TEdit():aSeaHis, i )
         hb_AIns( TEdit():aSeaHis, 1, cSearch, .F. )
      ELSE
         hb_AIns( TEdit():aSeaHis, 1, cSearch, Len(TEdit():aSeaHis)<hb_hGetDef(TEdit():options,"seahismax",10) )
      ENDIF
      IF oEdit:Search( cSearch, lCase_Sea := lCase, !lBack, @ny, @nx )
         oEdit:GoTo( ny, nx, 0 )
      ENDIF
   ENDIF

   SetColor( oldc )
   DevPos( oEdit:nRow, oEdit:nCol )

   RETURN Nil

FUNCTION mnu_SeaHist( oEdit, aGet )

   LOCAL aMenu, i, bufc
   IF !Empty( TEdit():aSeaHis )
      aMenu := Array( Len(TEdit():aSeaHis) )
      FOR i := 1 TO Len(aMenu)
         aMenu[i] := { TEdit():aSeaHis[i], Nil, i }
      NEXT
      bufc := SaveScreen( 12, 22, 12 + Min(6,Len(aMenu)+1), 55 )
      IF !Empty( i := FMenu( oEdit, aMenu, 12, 22, 12 + Min(6,Len(aMenu)+1), 55 ) )
         aGet[4] := TEdit():aSeaHis[i]
         ShowGetItem( aGet, .F., oEdit:lUtf8 )
      ENDIF
      RestScreen( 12, 22, 12 + Min(6,Len(aMenu)+1), 55, bufc )
      __KeyBoard(Chr(K_UP))
   ENDIF

   RETURN Nil

FUNCTION mnu_SeaNext( oEdit, lNext )

   LOCAL ny := oEdit:nRow - oEdit:y1 + oEdit:nyFirst, nx := oEdit:nCol - oEdit:x1 + oEdit:nxFirst

   IF !Empty( TEdit():aSeaHis ) .AND. oEdit:Search( TEdit():aSeaHis[1], lCase_Sea, lNext, @ny, @nx )
      oEdit:GoTo( ny, nx, 0 )
   ENDIF

   RETURN Nil

FUNCTION mnu_GoTo( oEdit )

   LOCAL oldc := SetColor( "N/W,W+/BG" )
   LOCAL aGets := { {11,32,0,"",16} }, ny, lRes

   hb_cdpSelect( "RU866" )
   @ 09, 30, 12, 50 BOX "�Ŀ����� "
   hb_cdpSelect( oEdit:cp )

   @ 10,32 SAY "Go to position"
   SetColor( "W+/BG" )

   lRes := edi_READ( aGets, oEdit:lUtf8 )

   IF lRes .AND. (ny := Val(aGets[1,4]) ) > 0 .AND. ny <= Len(oEdit:aText)
      oEdit:GoTo( ny, 1, 0 )
   ENDIF

   SetColor( oldc )
   DevPos( oEdit:nRow, oEdit:nCol )

   RETURN Nil

FUNCTION mnu_Plugins( oEdit )

   LOCAL aMenu := {}, i

   FOR i := 1 TO Len( aPlugins )
      IF Empty( aPlugins[i,3] ) .OR. aPlugins[i,3] == oEdit:cSyntaxType
         AAdd( aMenu, { aPlugins[i,2], Nil, Nil} )
      ENDIF
   NEXT
   IF !Empty( aMenu )
      IF ( i := FMenu( oEdit, aMenu ) ) > 0
         IF Empty( aPlugins[i,4] )
            aPlugins[i,4] := hb_hrbLoad( hb_DirBase() + "plugins" + hb_ps() + aPlugins[i,1] )
         ENDIF
         IF !Empty( aPlugins[i,4] )
            hb_hrbDo( aPlugins[i,4], oEdit )
         ENDIF
      ENDIF
   ENDIF

   RETURN Nil

FUNCTION mnu_ChgMode( oEdit, lBack )

   SetColor( "N/W+" )
   Scroll( oEdit:y1-1, oEdit:x1, oEdit:y1-1, oEdit:x2 )
   Inkey( 0.2 )
   DevPos( oEdit:nRow, oEdit:nCol )

   IF !Empty( lBack )
      oEdit:nMode := 0
      oEdit:WriteTopPane( .T. )
   ELSE
      IF oEdit:nMode == 0
         oEdit:nMode := 1
         oEdit:WriteTopPane( .T. )
      ELSEIF oEdit:nMode == 1
         oEdit:nMode := 2
         oEdit:WriteTopPane( .T. )
         mnu_CmdLine( oEdit )
      ENDIF
   ENDIF

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
      oEdit:aText[nby1] := cp_Left( lUtf8,oEdit:aText[nby1],nbx1-1 ) + ;
          Iif( lUpper, cp_Upper(lUtf8,s), cp_Lower(lUtf8,s) ) + ;
         cp_Substr( lUtf8, oEdit:aText[nby1], nbx2 )
   ELSE
      FOR i := nby1 TO nby2
         IF i == nby1
            s := cp_Substr( lUtf8, oEdit:aText[nby1], nbx1 )
            oEdit:aText[i] := cp_Left( lUtf8,oEdit:aText[nby1],nbx1-1 ) + ;
               Iif( lUpper, cp_Upper(lUtf8,s), cp_Lower(lUtf8,s) )
         ELSEIF i == nby2
            s := cp_Left( lUtf8, oEdit:aText[i], nbx2-1 )
            oEdit:aText[i] := Iif( lUpper, cp_Upper(lUtf8,s), cp_Lower(lUtf8,s) ) + ;
               cp_Substr( lUtf8, oEdit:aText[i], nbx2 )
         ELSE
            oEdit:aText[i] := Iif( lUpper, cp_Upper(lUtf8,oEdit:aText[i]), cp_Lower(lUtf8,oEdit:aText[i]) )
         ENDIF
      NEXT
   ENDIF

   RETURN Nil

STATIC FUNCTION edi_NextWord( oEdit, lEndWord )
   LOCAL ny, nx, nRow := Row(), nCol := Col(), nLen

   ny := nRow - oEdit:y1 + oEdit:nyFirst
   nx := nCol - oEdit:x1 + oEdit:nxFirst
   nLen := cp_Len( oEdit:lUtf8, oEdit:aText[ny] )

   IF nx > nLen
      RETURN Nil
   ENDIF
   DO WHILE ++nx <= nLen
      IF cp_Substr( oEdit:lUtf8, oEdit:aText[ny], nx, 1 ) == " "
         IF !Empty( lEndWord ) .AND. nx - (nCol - oEdit:x1 + oEdit:nxFirst) > 1
            nx --
            EXIT
         ENDIF
         DO WHILE ++nx <= nLen .AND. cp_Substr( oEdit:lUtf8, oEdit:aText[ny], nx, 1 ) == " "; ENDDO
         IF Empty( lEndWord )
            EXIT
         ENDIF
      ENDIF
   ENDDO
   IF nx - oEdit:nxFirst + oEdit:x1 >= oEdit:x2
      oEdit:nxFirst := nx + oEdit:x1 - oEdit:x2 - 3
   ENDIF
   DevPos( nRow, oEdit:nCol := ( nx - oEdit:nxFirst + oEdit:x1 ) )

   RETURN Nil

STATIC FUNCTION edi_PrevWord( oEdit )
   LOCAL ny, nx, nRow := Row(), nCol := Col()

   ny := nRow - oEdit:y1 + oEdit:nyFirst
   nx := nCol - oEdit:x1 + oEdit:nxFirst

   IF cp_Substr( oEdit:lUtf8, oEdit:aText[ny], nx-1, 1 ) == " "
      DO WHILE --nx > 1 .AND. cp_Substr( oEdit:lUtf8, oEdit:aText[ny], nx, 1 ) == " "; ENDDO
   ENDIF
   DO WHILE --nx >= 0
      IF nx == 0 .OR. cp_Substr( oEdit:lUtf8, oEdit:aText[ny], nx, 1 ) == " "
         nx ++
         EXIT
      ENDIF
   ENDDO
   IF nx - oEdit:nxFirst + oEdit:x1 >= oEdit:x2
      oEdit:nxFirst := nx + oEdit:x1 - oEdit:x2 - 3
   ENDIF
   DevPos( nRow, oEdit:nCol := ( nx - oEdit:nxFirst + oEdit:x1 ) )

   RETURN Nil

STATIC FUNCTION edi_FileName( oEdit )

   LOCAL oldc := SetColor( "N/W,W+/BG" )
   LOCAL aGets := { {11,22,0,"",36} }, cName

   hb_cdpSelect( "RU866" )
   @ 09, 20, 13, 60 BOX "�Ŀ����� "
   hb_cdpSelect( oEdit:cp )

   @ 10,22 SAY "Save file as"
   SetColor( "W+/BG" ) 

   IF edi_READ( aGets, oEdit:lUtf8 )
      cName := aGets[1,4]
   ENDIF

   SetColor( oldc )
   DevPos( oEdit:nRow, oEdit:nCol )

   RETURN cName

STATIC FUNCTION edi_Indent( oEdit, lRight )

   LOCAL i, n, nby1, nby2, nbx2

   IF oEdit:nby1 < 0 .OR. oEdit:nby2 < 0
      RETURN Nil
   ENDIF
   IF oEdit:nby1 <= oEdit:nby2
      nby1 := oEdit:nby1; nby2 := oEdit:nby2; nbx2 := oEdit:nbx2
   ELSE
      nby1 := oEdit:nby2; nby2 := oEdit:nby1; nbx2 := oEdit:nbx1
   ENDIF
   FOR i := nby1 TO nby2
      IF i == nby2 .AND. nbx2 == 1
         LOOP
      ENDIF
      IF lRight
         oEdit:aText[i] := " " + oEdit:aText[i]
      ELSEIF Left( oEdit:aText[i],1 ) == " "
         oEdit:aText[i] := Substr( oEdit:aText[i], 2 )
      ENDIF
      n := i - oEdit:nyFirst + 1
      IF n > 0 .AND. n < oEdit:y2-oEdit:y1
         oEdit:LineOut( n )
      ENDIF
   NEXT
   oEdit:Undo( nby1 )
   oEdit:lUpdated := .T.

   RETURN Nil

STATIC FUNCTION edi_BookMarks( oEdit, nKey, lSet )

   LOCAL arr

   IF lSet
      oEdit:hBookMarks[nKey] := { oEdit:nRow - oEdit:y1 + oEdit:nyFirst, oEdit:nCol - oEdit:x1 + oEdit:nxFirst }
   ELSE
      IF hb_hHaskey( oEdit:hBookMarks, nKey )
         arr := oEdit:hBookMarks[nKey]
         oEdit:Goto( arr[1], arr[2] )
      ENDIF
   ENDIF

   RETURN Nil

STATIC FUNCTION edi_CurPath()

   LOCAL cPrefix

#ifdef __PLATFORM__UNIX
   cPrefix := '/'
#else
   cPrefix := hb_curDrive() + ':\'
#endif

   RETURN cPrefix + CurDir() + hb_ps()

STATIC FUNCTION edi_MapKey( oEdit, nKey )

   LOCAl c, nPos

   IF nKey >= 127 .AND. !Empty(cLangMapCP) .AND. !Empty(aLangMapUpper) .AND. !Empty(aLangMapLower)
      c := hb_Translate( cp_Chr( oEdit:lUtf8, nKey ), oEdit:cp, cLangMapCP )
      IF ( nPos := cp_At( oEdit:lUtf8, c, aLangMapUpper[1] ) ) > 0
         RETURN cp_Asc( oEdit:lUtf8, hb_Translate( cp_Substr(oEdit:lUtf8,aLangMapUpper[2],nPos,1), cLangMapCP, oEdit:cp ) )
      ELSEIF ( nPos := cp_At( oEdit:lUtf8, c, aLangMapLower[1] ) ) > 0
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
   IF lUtf8; RETURN cString; ENDIF
   RETURN Lower( cString )

FUNCTION cp_Upper( lUtf8, cString )
   IF lUtf8; RETURN cString; ENDIF
   RETURN Upper( cString )
