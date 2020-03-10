#include <GUIConstantsEx.au3>
#include <Process.au3>
#include <File.au3>


#Region ;**** Directives ****
#AutoIt3Wrapper_OutFile="dist\saruman-test.exe"
#EndRegion ;**** Directives ****

Func Main()
	Local $LOGFILE_PATH = ".\worklog.txt"
	Local $N = 5
	Sleep(10000)
	$iPID = Run(@WorkingDir & ".\saruman.exe", @WorkingDir)
	CreateExampleWindows($N, 15000)
	Sleep(5000)
	ProcessClose($iPID)

	; Test Cases
	If Not FileExists($LOGFILE_PATH) Then
		ConsoleWriteError($LOGFILE_PATH & " bulunamadi!" & @CRLF)
		Exit(1)
	EndIf

	If Not CheckLogCount($LOGFILE_PATH, $N) Then
		ConsoleWriteError($LOGFILE_PATH & " satir sayi problemi!" & @CRLF)
		Exit(1)
	EndIf

	ConsoleWrite("TEST RESULTS OK" & @CRLF)

	Exit(0)


EndFunc   ;==>Main

Func Example($sTitle)
	; Create a GUI with various controls.
	Local $hGUI = GUICreate($sTitle)
	Local $idOK = GUICtrlCreateButton("OK", 310, 370, 85, 25)

	; Display the GUI.
	GUISetState(@SW_SHOW, $hGUI)
	Return $hGUI
EndFunc   ;==>Example

Func CreateExampleWindows($countWin, $wait)
	For $i = 1 To $countWin
		Local $hWnd = Example("Example" & $i)
		WinActivate($hWnd)
		Sleep($wait)
		GUIDelete($hWnd)
	Next
EndFunc   ;==>CreateExampleWindows

Func CheckLogCount($filePath, $countWin)
	$lineCount = _FileCountLines($filePath)
	ConsoleWrite("Line count of " & $filePath & ":" & $lineCount & @CRLF)
	If $lineCount = $countWin Then
		; Test OK
		return True
	EndIf
	return False
EndFunc

Main()
