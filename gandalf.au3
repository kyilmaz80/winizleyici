#include <File.au3>
#include <FileConstants.au3>

; author: korayy
; date:   200205
; desc:   saruman process checker
; version: 1.1

#NoTrayIcon
Const $POLL_TIME_MS = 2000
Global Const $DEBUG = True
Global Const $DEBUG_LOGFILE = @ScriptDir & "\gandalf_" & @MON & @MDAY & @YEAR & "_" & @HOUR & @MIN & @SEC & ".txt"
Global Const $SUPERVISOR_EXE_NAME = "saruman.exe"

; thread-like fonksiyonlari calistir
AdlibRegister("_StartSupervisor", $POLL_TIME_MS)

; busy wait ana program
Func _Main()
	While 1
		Sleep(500)
	WEnd
EndFunc   ;==>_Main

;debug helper function
Func _DebugPrint($sMsgString)
	ConsoleWrite($sMsgString & @CRLF)
	If $DEBUG Then
		_FileWriteLog($DEBUG_LOGFILE, $sMsgString)
	EndIf
EndFunc   ;==>_DebugPrint

;~ surekli supervizor process'e bakar
Func _StartSupervisor()
	If Not ProcessExists($SUPERVISOR_EXE_NAME) Then
		$iPID = Run(@WorkingDir & ".\" & $SUPERVISOR_EXE_NAME, @WorkingDir)
		_DebugPrint( $SUPERVISOR_EXE_NAME & "prosesi " & $iPID  & " pid si ile çalistirildi..." & @CRLF)
	EndIf
EndFunc

_Main()