/***
*
*       Errorsys.prg
*
*  Standard Clipper error handler
*
*  Copyright (c) 1990-1993, Computer Associates International, Inc.
*  All rights reserved.
*
*  Compile:  /m /n /w
*
*/

#include "error.ch"

// put messages to STDERR
#command ? <list,...>   =>  ?? Chr(13) + Chr(10) ; ?? <list>
#command ?? <list,...>  =>  OutErr(<list>)

// used below
#define NTRIM(n)                ( LTrim(Str(n)) )

STATIC LogInitialPath := ""

/***
*       ErrorSys()
*
*       Note:  automatically executes at startup
*/

PROC ErrorSys()

   Errorblock( { | e | DefError( e ) } )
   LogInitialPath := "\" + Curdir() + Iif( Empty( Curdir() ), "", "\" )
RETURN

/***
*       DefError()
*/
STATIC FUNC DefError( e )

LOCAL i, cMessage, aOptions, nChoice

   // by default, division by zero yields zero
   IF ( e:genCode == EG_ZERODIV )
      RETURN ( 0 )
   END

   // for network open error, set NETERR() and subsystem default
   IF ( e:genCode == EG_OPEN .AND. e:osCode == 32 .AND. e:canDefault )

      Neterr( .t. )
      RETURN ( .f. )                    // NOTE

   END

   // for lock error during APPEND BLANK, set NETERR() and subsystem default
   IF ( e:genCode == EG_APPENDLOCK .AND. e:canDefault )

      Neterr( .t. )
      RETURN ( .f. )                    // NOTE

   END

   // build error message
   cMessage := ErrorMessage( e )

   // build options array
   // aOptions := {"Break", "Quit"}
   aOptions := { "Quit" }

   IF ( e:canRetry )
      Aadd( aOptions, "Retry" )
   END

   IF ( e:canDefault )
      Aadd( aOptions, "Default" )
   END

   // put up alert box
   nChoice := 0
   WHILE ( nChoice == 0 )

      IF ( Empty( e:osCode ) )
         nChoice := Alert( cMessage, aOptions )

      ELSE
         nChoice := Alert( cMessage + ;
                           ";(DOS Error " + NTRIM( e:osCode ) + ")", ;
                           aOptions )
      END

      IF ( nChoice == NIL )
         EXIT
      END

   END

   IF ( !Empty( nChoice ) )

      // do as instructed
      IF ( aOptions[ nChoice ] == "Break" )
         BREAK( e )

      ELSEIF ( aOptions[ nChoice ] == "Retry" )
         RETURN ( .t. )

      ELSEIF ( aOptions[ nChoice ] == "Default" )
         RETURN ( .f. )

      END

   END

   // display message and traceback
   IF ( !Empty( e:osCode ) )
      cMessage += " (DOS Error " + NTRIM( e:osCode ) + ") "
   END

   SET DEFAULT TO
   SET DEVICE TO PRINTER
   SET PRINTER TO "apps.err" ADDITIVE
   @  1,  0 SAY " "                                                                                    
   @  2,  0 SAY Iif( Type( "mnam" ) = "C", m->mnam, "" ) + ' ' + Dtoc( Date() ) + ' ' + Time()         
   @  3,  0 SAY cMessage                                                                               
   i := 2
   WHILE ( !Empty( Procname( i ) ) )
      @ i + 2, 0 SAY "Called from " + Trim( Procname( i ) ) + ;         
              "(" + NTRIM( Procline( i ) ) + ")  "

      i ++
   END
   SET DEVICE TO SCREEN
   // give up
   Errorlevel( 1 )
   QUIT

RETURN ( .f. )

/***
*       ErrorMessage()
*/
FUNC ErrorMessage( e )

LOCAL cMessage

   // start error message
   cMessage := IF( e:severity > ES_WARNING, "Error ", "Warning " )

   // add subsystem name if available
   IF ( Valtype( e:subsystem ) == "C" )
      cMessage += e:subsystem()
   ELSE
      cMessage += "???"
   END

   // add subsystem's error code if available
   IF ( Valtype( e:subCode ) == "N" )
      cMessage += ( "/" + NTRIM( e:subCode ) )
   ELSE
      cMessage += "/???"
   END

   // add error description if available
   IF ( Valtype( e:description ) == "C" )
      cMessage += ( "  " + e:description )
   END

   // add either filename or operation
   IF ( !Empty( e:filename ) )
      cMessage += ( ": " + e:filename )

   ELSEIF ( !Empty( e:operation ) )
      cMessage += ( ": " + e:operation )

   END

RETURN ( cMessage )

