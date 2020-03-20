#include <GUIConstantsEx.au3>
#include <Process.au3>
#include <File.au3>
#include <Date.au3>
#include <SQLite.au3>
#include <SQLite.dll.au3>


#Region ;**** Directives ****
#AutoIt3Wrapper_OutFile="dist\saruman-test.exe"
#EndRegion ;**** Directives ****

Global $DEBUG_LOGFILE = ".\worklog-test-" & @MON & @MDAY & @YEAR & "_" & @HOUR & @MIN & @SEC & ".txt"
Global $DEBUG = True
Global $hnd
Func Main()
	; Local $TESTDB_FILE = ".\worklog-test-" & @MON & @MDAY & @YEAR & "_" & @HOUR & @MIN & @SEC & ".db"
	Local $TESTDB_FILE = "worklog-test.db"

	If FileExists($TESTDB_FILE) Then
		FileDelete($TESTDB_FILE)
	EndIf

	WinMinimizeAll()

	Local $time1 = _GetDatetime()

	_DebugPrint("Test " & $time1 & " de basladi...")

	Local $N = 5
	Local $POLL_TIME_MS = 4000
	Sleep(1000)

	If Not FileExists("saruman.exe") Then
		_DebugPrint("saruman.exe bulunamadi")
		Exit(1)
	EndIf

;~ 	$CMD = "saruman.exe -d:" & $TESTDB_FILE & " -t:" & $POLL_TIME_MS  & " -c:0 -v"
    $CMD = "saruman.exe -d:" & $TESTDB_FILE & " -c:0 -v"

;~ 	$CMD = "C:\Users\Koray\Documents\kodlar\autoit\sqlite_branch\winizleyici\dist\saruman.exe -d:" & $TESTDB_FILE & _
;~ 			" -t:" & $POLL_TIME_MS  & " -c:0 -v"
;~ 	$CMD = "saruman.exe -v "
	_DebugPrint($CMD & " " & @WorkingDir & " dizininden calistiriliyor...")
	$iPID = Run($CMD, @WorkingDir)
	_DebugPrint("saruman.exe bekleniyor..")
	ProcessWait("saruman.exe")
	_DebugPrint("Pencereler hazirlaniyor...")
	CreateExampleWindows($N, 13000)
	ProcessClose($iPID)

	$hnd = DB_Open($TESTDB_FILE)

	; Test Cases
	If Not FileExists($TESTDB_FILE) Then
		_DebugPrint($TESTDB_FILE & " bulunamadi!" & @CRLF)
		Exit(1)
	EndIf

	If Not CheckLogCount($N) Then
		_DebugPrint($TESTDB_FILE & " Worklog satir sayi problemi!" & @CRLF)
		Exit(1)
	EndIf

	If Not CheckWinCount($N) Then
		_DebugPrint($TESTDB_FILE & " Window satir sayi problemi!" & @CRLF)
		Exit(1)
	EndIf

	_SQLite_Close($hnd)

	Local $time2 = _GetDatetime()

	_DebugPrint("Test " & $time2 & " de bitti...")
	_DebugPrint("TEST RESULTS OK" & @CRLF)

	Exit(0)

EndFunc   ;==>Main

; yyyy-mm-dd hh:mm:ss formatinda veya epoch formatinda guncel tarih zaman doner
Func _GetDatetime($bTimestamp = False)
	$timestamp = _DateDiff('s', "1970/01/01 00:00:00", _NowCalc())
	$timedate = StringReplace(_NowCalc(), "/", "-")
	If $bTimestamp Then
		Return $timestamp
	EndIf
	Return $timedate
EndFunc   ;==>_GetDatetime

Func DB_GetWindowCount()
	Local $aRow
	Local $SQL_WINDOW = "SELECT count(*) FROM Window Where title like 'Example%'"

	If $SQLITE_OK <> _SQLite_QuerySingleRow($hnd, $SQL_WINDOW, $aRow) Then
		_DebugPrint("_DB_GetLastWorklogID Problem: Error Code: " & _SQLite_ErrCode() & "Error Message: " & _SQLite_ErrMsg)
		Return -1
	EndIf
	$w_id = $aRow[0]
	Return $w_id
EndFunc

Func DB_GetWorklogCount()
	Local $aRow
	Local $SQL_WORKLOG = "SELECT Count(*) from Worklog INNER JOIN Window ON Worklog.w_id = Window.id Where Window.Title LIKE 'Example%'"

	If $SQLITE_OK <> _SQLite_QuerySingleRow($hnd, $SQL_WORKLOG, $aRow) Then
		_DebugPrint("_DB_GetLastWorklogID Problem: Error Code: " & _SQLite_ErrCode() & "Error Message: " & _SQLite_ErrMsg)
		Return -1
	EndIf
	$w_id = $aRow[0]
	Return $w_id
EndFunc

Func DB_Open($DBFILE_PATH)

	Local $hDB
	_SQLite_Startup()

	_DebugPrint("_SQLite_LibVersion=" & _SQLite_LibVersion() & @CRLF)
	If @error Then Exit MsgBox(16, "SQLite Hata", "SQLite.dll yuklenemedi!")
	$hDB = _SQLite_Open($DBFILE_PATH)
	If @error Then Exit MsgBox(16, "SQLite Hata", "Veri tabanı açılamadı!")

	Return $hDB

EndFunc

;debug helper function
Func _DebugPrint($sMsgString)
	ConsoleWrite($sMsgString & @CRLF)
	If $DEBUG Then
		_FileWriteLog($DEBUG_LOGFILE, $sMsgString)
	EndIf
EndFunc   ;==>_DebugPrint

Func Example($sTitle)
	; Create a GUI with various controls.
	Local $t
	Local $hGUI = GUICreate($sTitle)
	Local $idOK = GUICtrlCreateButton("OK", 310, 370, 85, 25)

	$t = _GetDatetime()
	_DebugPrint("Window " & $sTitle & " " & $t & " zamaninda olusturuldu")

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

Func CheckLogCount($countWin)
	Local $w_count = DB_GetWorklogCount()
	If $w_count = $countWin Then
		return True
	EndIf
	return False
EndFunc

Func CheckWinCount($countWin)
	Local $w_count = DB_GetWindowCount()
	If $w_count = $countWin Then
		return True
	EndIf
	return False
EndFunc

Main()
