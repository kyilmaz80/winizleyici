#include <AutoItConstants.au3>
#include <Array.au3>
#include <Date.au3>
#include <File.au3>
#include <FileConstants.au3>
#include <GDIPlus.au3>
#include <MsgBoxConstants.au3>
#include <Process.au3>
#include <ScreenCapture.au3>
#include <WinAPI.au3>
#include <WinAPIHObj.au3>
#include <WinAPIFiles.au3>
#include <WinAPISysWin.au3>
#include <TrayConstants.au3>
#include <SQLite.au3>
#include <SQLite.dll.au3>

; author: korayy
; date:   200222
; desc:   work logger
; version: 1.20

#Region ;**** Directives ****
#AutoIt3Wrapper_Res_ProductName=WinIzleyici
#AutoIt3Wrapper_Res_Description=User Behaviour Logger
#AutoIt3Wrapper_Res_Fileversion=1.19.0.2
#AutoIt3Wrapper_Res_Fileversion_AutoIncrement=p
#AutoIt3Wrapper_Res_ProductVersion=1.19
#AutoIt3Wrapper_Res_LegalCopyright=ARYASOFT
#AutoIt3Wrapper_Res_Icon_Add=.\saruman.ico,99
#AutoIt3Wrapper_Icon=".\saruman.ico"
#EndRegion ;**** Directives ****

Const $POLL_TIME_MS = 2000
; _CaptureWindows degiskenler
Global $sLastActiveWin = ""
Global $activeWinHnd = ""
Global $sLastActiveWinHnd = ""
Global $bWindowChild = 0
Global $tFinish2 = 0
Global $sLastPIDName = ""
Global Const $BLACK_LIST_WINS = "Program Manager|"
Global Const $DBFILE_PATH = @WorkingDir & "\worklog.db"
Global Const $DELIM = ","
Global Const $DELIM_T = ";"
Global Const $SCREENSHOT_PATH = @WorkingDir & "\caps\" & @YEAR & @MON & @MDAY
Global $IS_SCREEN_CAP = False
Global $aFileArray[0] = []
;~ Global Const $FSYNCBUFFER = 5
Global Const $TRAY_ICON_NAME = "saruman.ico"
Global Const $DEBUG = True
Global Const $DEBUG_LOGFILE = @ScriptDir & "\saruman_" & @MON & @MDAY & @YEAR & "_" & @HOUR & @MIN & @SEC & ".txt"
Global Const $SUPERVISOR_EXE_NAME = "gandalf.exe"
Global Const $PROGRAM_MANAGER = "Program Manager"

; thread-like fonksiyonları calistir
AdlibRegister("_CaptureWindows", $POLL_TIME_MS)

; busy wait ana program
Func _Main()
	setTray()
	_DBInit()
	While 1
		_StartSupervisor($SUPERVISOR_EXE_NAME)
		Sleep(500)
	WEnd
EndFunc   ;==>_Main

Func _DBInit()
	Local $hDB;
	_SQLite_Startup()
	_DebugPrint("_SQLite_LibVersion=" & _SQLite_LibVersion() & @CRLF)
	If @error Then Exit MsgBox(16, "SQLite Hata", "SQLite.dll yukelenemedi!")
	If FileExists($DBFILE_PATH) Then
		_DebugPrint($DBFILE_PATH & " aciliyor..." & @CRLF)
		$hDB = _SQLite_Open($DBFILE_PATH)
		If @error Then Exit MsgBox(16, "SQLite Hata", "Veri tabanı açılamadı!")
	Else
		$hDB = _SQLite_Open($DBFILE_PATH)
		If @error Then Exit MsgBox(16, "SQLite Hata", "Veri tabanı açılamadı!")
		; TODO create tables
		; Yeni tablo olustur Process
		_SQLite_Exec(-1, "CREATE TABLE IF NOT EXISTS User(id INTEGER NOT NULL, name TEXT NOT NULL, PRIMARY KEY(id));")
		_SQLite_Exec(-1, "CREATE TABLE IF NOT EXISTS Process(id INTEGER NOT NULL, name TEXT NOT NULL UNIQUE, PRIMARY KEY(id));")
		_SQLite_exec(-1, "CREATE TABLE Window (id	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, " & _
	                     "title	TEXT NOT NULL UNIQUE, handle TEXT, p_id INTEGER NOT NULL, " & _
	                     "FOREIGN KEY(p_id) REFERENCES Process(id));")
		_SQLite_Exec(-1, "CREATE TABLE IF NOT EXISTS Worklog ( " & _
	                     "id	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, " & _
	                     "p_id	INTEGER NOT NULL, " & _
	                     "u_id	INTEGER NOT NULL, " & _
						 "w_id 	INTEGER DEFAULT 0, " & _
						 "start_date TEXT NOT NULL, " & _
						 "end_date TEXT NOT NULL," & _
	                     "idle	INTEGER DEFAULT 0, " & _
						 "processed	INTEGER DEFAULT 0," & _
						 "FOREIGN KEY(p_id) REFERENCES Process(id), " & _
	                     "FOREIGN KEY(u_id) REFERENCES User(id), " & _
						 "FOREIGN KEY(w_id) REFERENCES Window(id));")
	    ; idle veri ekleme
		_SQLite_Exec(-1, "INSERT INTO Process(id, name) VALUES (1,'idle');")
		_SQLite_Exec(-1, "INSERT INTO Window(id, title, handle, p_id) VALUES (0, 'idle', 'idle', 1);")
		; SQL injetion korumali @UserName
		_SQLite_Exec(-1, "INSERT INTO User(id, name) VALUES (1," & _SQLite_FastEscape(@UserName) & ");")
	EndIf
	Return $hDB
EndFunc

;debug helper function
Func _DebugPrint($sMsgString)
	ConsoleWrite($sMsgString & @CRLF)
	If $DEBUG Then
		_FileWriteLog($DEBUG_LOGFILE, $sMsgString)
	EndIf
EndFunc   ;==>_DebugPrint

; tray icon degistirir
Func setTray()
	;#NoTrayIcon
	Opt("TrayMenuMode", 3) ; no default menu (Paused/Exit)
	TraySetState($TRAY_ICONSTATE_SHOW) ; Show the tray menu.
	TraySetIcon($TRAY_ICON_NAME, 99)
EndFunc   ;==>setTray

;~ surekli supervizor process'e bakar
Func _StartSupervisor($sProcessName)
	If Not ProcessExists($sProcessName) Then
		If Not FileExists(@WorkingDir & ".\" & $SUPERVISOR_EXE_NAME) Then
			_DebugPrint( $SUPERVISOR_EXE_NAME & " exe programi bulunamadi..." & @CRLF)
			Return
		EndIf
		$iPID = Run(@WorkingDir & ".\" & $sProcessName, @WorkingDir)
		_DebugPrint( $sProcessName & "prosesi " & $iPID  & " pid si ile çalistirildi..." & @CRLF)
	EndIf
EndFunc

; text whitelisting
Func removeSpecialChars($str)
	Return StringRegExpReplace($str, "[^0-9,a-z,A-Z, ,\-,.,:,;,\h,\v]", "")
EndFunc   ;==>removeSpecialChars

; windows rdp kontrol
Func IsRDP()
	If @OSVersion == "WIN_10" Then
		Return StringInStr(EnvGet('SESSIONNAME'), "RDP") > 0
	Else
		; FIXME Win7 icin test
		Return EnvGet('SESSIONNAME') == ''
	EndIf
EndFunc   ;==>IsRDP

; windows lock kontrolu
Func isWinLocked()
	If Not IsRDP() And ProcessExists("LogonUI.exe") Then
		Return True
	Else
		Return False
	EndIf
EndFunc   ;==>isWinLocked

; yyyy-mm-dd hh:mm:ss formatinda veya epoch formatinda guncel tarih zaman doner
Func _GetDatetime($bTimestamp = False)
	$timestamp = _DateDiff('s', "1970/01/01 00:00:00", _NowCalc())
	$timedate = StringReplace(_NowCalc(), "/", "-")
	If $bTimestamp Then
		Return $timestamp
	EndIf
	Return $timedate
EndFunc   ;==>_GetDatetime

; verilen pencereler winList listesinde aktif pencere durumu doner
Func isWindowsActive($aList)
	Local $sArray = StringSplit($BLACK_LIST_WINS, "|", $STR_ENTIRESPLIT)
	Local $bActive = False
	For $i = 1 To $aList[0][0]
		If _ArraySearch($sArray, $aList[$i][0]) <> -1 Then
			ContinueLoop
		EndIf
		If $aList[$i][0] <> "" And BitAND(WinGetState($aList[$i][1]), $WIN_STATE_ACTIVE) Then
			_DebugPrint("Active WinTitle: " & $aList[$i][0])
			_DebugPrint("Active WinHandle: " & $aList[$i][1])
			$bActive = True
			ExitLoop
		EndIf
	Next
	Return $bActive
EndFunc   ;==>isWindowsActive

;~ verilen pencerenin ekran görüntüsünü yakalar
Func ScreenCaptureWin($winHandle, $fileCapturePath)
	If Not $IS_SCREEN_CAP Then
		Return
	EndIf
	_GDIPlus_Startup()
	Local $hIA = _GDIPlus_ImageAttributesCreate() ;create an ImageAttribute object
	Local $tColorMatrix = _GDIPlus_ColorMatrixCreateGrayScale() ;create grayscale color matrix
	_GDIPlus_ImageAttributesSetColorMatrix($hIA, 0, True, $tColorMatrix) ;set negative color matrix
	; Capture window
	$hBitmap = _ScreenCapture_CaptureWnd("", $activeWinHnd)
	$hImage = _GDIPlus_BitmapCreateFromHBITMAP($hBitmap)
	_DebugPrint($fileCapturePath & " dosya yaziliyor...")
	_GDIPlus_ImageSaveToFile($hImage, $fileCapturePath)
	; Clean up resources
	_GDIPlus_ImageDispose($hImage)
	_WinAPI_DeleteObject($hBitmap)
	_GDIPlus_Shutdown()
EndFunc   ;==>ScreenCaptureWin

Func idleToLog()
	; TODO: degistirilecek.
	Local $hQuery, $idleStart
	Local $aRow
	; init
	Local $iRes_id = -1, $iRes_w_id = -1, $iRes_idle = -1

	$idleStart = _GetDatetime()
	_DebugPrint($idleStart & " Idle mode....")
	; TODO: check last insert sql
;~ 	_SQLite_Query(-1, "SELECT id, w_id, idle FROM Worklog ORDER BY id DESC LIMIT 1", $hQuery)
	If $SQLITE_OK  <> _SQLite_QuerySingleRow(-1, "SELECT id, w_id, idle FROM Worklog ORDER BY id DESC LIMIT 1", $hQuery) Then
		_DebugPrint("Sqlite Error: " &  _SQLite_ErrMsg())
		Return
	EndIf

	$iRes_id = $hQuery[0]
	$iRes_w_id = $hQuery[1]
	$iRes_idle = $hQuery[2]

	; yeni kayit ise veya Son kayit idle degilse
	If ($iRes_idle = -1 And $iRes_w_id = -1) Or _
		($iRes_idle = 0 And $iRes_w_id <> 0) Then
		_DebugPrint("Inserting idle data..." & @CRLF)
		_SQLite_Exec(-1, "INSERT INTO main.Worklog(p_id, u_id, timestamp, idle) VALUES (1, " & _DB_GetCurrentUserID() & _
              		", " & _SQLite_FastEscape($idleStart)  &", 1);")
	Else
		; else update the last records' timestamp
		If $iRes_id = -1 Then
			_DebugPrint("Last Insert Id bulunamadi. Worklog idle guncellenemedi!")
		Else
			_DebugPrint("Normalizing last idle insert with update..." & @CRLF)
			_SQLite_Exec(-1, "UPDATE main.Worklog SET timestamp=" & _SQLite_FastEscape($idleStart) & " WHERE id=" & $iRes_id)
		EndIf
	EndIf
	Return 0
EndFunc

Func _DB_GetCurrentUserID()
	Local $aRow
	Local $u_id

	Local $userName = @UserName

	If $SQLITE_OK <> _SQLite_QuerySingleRow(-1, "SELECT id FROM main.User WHERE name = "&  _SQLite_FastEscape($userName) &";", $aRow) Then
		_DebugPrint("_DB_GetCurrentUserID Problem: Error Code: " & _SQLite_ErrCode() & "Error Message: " & _SQLite_ErrMsg)
	EndIf

	$u_id = $aRow[0]
	Return $u_id
EndFunc

;~ processName proses adının  DB'deki id'sini doner
Func _DB_GetLastProcessID($processName)
	Local $aRow
	Local $p_id

	If $SQLITE_OK  <> _SQLite_QuerySingleRow(-1, "SELECT id FROM main.Process WHERE name = "&  _SQLite_FastEscape($processName) &";", $aRow) Then
		_DebugPrint("_DB_GetLastProcessID Problem: Error Code: " & _SQLite_ErrCode() & "Error Message: " & _SQLite_ErrMsg)
	EndIf
	$p_id = $aRow[0]
	Return $p_id
EndFunc

;~ $windowName window adının  DB'deki son satir id'sini doner
Func _DB_GetLastWindowID($windowName)
	Local $aRow
	Local $w_id
	If $SQLITE_OK  <> _SQLite_QuerySingleRow(-1, "SELECT id FROM main.Window WHERE title = "& _SQLite_FastEscape($windowName) &";", $aRow) Then
		_DebugPrint("_DB_GetLastWindowID Problem: Error Code: " & _SQLite_ErrCode() & "Error Message: " & _SQLite_ErrMsg)
	EndIf
	$w_id = $aRow[0]
	Return $w_id
EndFunc

;~ Windows tablosundaki windowName ve handle a karsilik gelen id doner
Func _DB_GetWindowID($windowName, $windowHandle)
	Local $aRow
	Local $w_id
	If $SQLITE_OK  <> _SQLite_QuerySingleRow(-1, "SELECT id FROM main.Window WHERE title = " & _SQLite_FastEscape($windowName) & _
		 " AND handle = " & "'"  & $windowHandle & "'"  & ";", $aRow) Then
		_DebugPrint("_DB_GetWindowID Problem: for " & $windowHandle & " arow[0] : " & $aRow[0] & " Error Code: " & _SQLite_ErrCode() & "Error Message: " & _SQLite_ErrMsg)
	EndIf
	$w_id = $aRow[0]
	Return $w_id
EndFunc

; Worklog tablosundaki en son id'yi doner
Func _DB_GetLastWorklogID()
	Local $aRow
	Local $w_id

	If $SQLITE_OK  <> _SQLite_QuerySingleRow(-1, "SELECT id FROM Worklog ORDER BY id DESC LIMIT 1", $aRow) Then
		_DebugPrint("_DB_GetLastWorklogID Problem: Error Code: " & _SQLite_ErrCode() & "Error Message: " & _SQLite_ErrMsg)
		Return -1
	EndIf
	$w_id = $aRow[0]
	Return $w_id
EndFunc

; Process tablosundan proses adına karşılık id döner
Func _DB_GetProcessID($processName)
	Local $aRow
	Local $p_id

	If $SQLITE_OK  <> _SQLite_QuerySingleRow(-1, "SELECT id FROM main.Process WHERE name = '" & _
		_SQLite_FastEscape($processName) & "';", $aRow) Then
		_DebugPrint("_DB_GetProcessID Problem: Error Code: " & _SQLite_ErrCode() & "Error Message: " & _SQLite_ErrMsg)
	EndIf

	$p_id = $aRow[0]
	Return $p_id
EndFunc

; Process tablosuna kayıt ekler ve sql exec sonucu durumunu doner
Func _DB_InsertProcess($processName)
	Local $d = _SQLite_Exec(-1, "INSERT INTO main.Process(name) VALUES (" & _SQLite_FastEscape($processName) & ");")
	Return $d
EndFunc

; Window tablosuna kayıt ekler ve sql exec sonucu durumunu doner
Func _DB_InsertWindow($windowTitle, $windowHandle, $processID)
	Local $d = _SQLite_Exec(-1, "INSERT INTO main.Window(title, handle, p_id) VALUES (" & _SQLite_FastEscape($windowTitle) & "," & _
		"'" & $windowHandle & "'" & "," & $processID & ");")
	Return $d
EndFunc

; Worklog tablosuna kayıt ekler ve sql exec sonucu durumunu doner
Func _DB_InsertWorklog($processID, $windowID, $start_date, $end_date)
	Local $d =_SQLite_Exec(-1, "INSERT INTO main.Worklog(p_id, u_id, w_id, start_date, end_date ) VALUES (" & _
							$processID & ", " & _DB_GetCurrentUserID()  & ", " & _
							$windowID  &", " & _SQLite_FastEscape($start_date) & ", " &  _SQLite_FastEscape($end_date)  & ");")
	Return $d
EndFunc

; Worklog tablosundaki kaydı günceller ve sql exec sonucu durumunu doner
Func _DB_UpdateWorklog($tFinish, $worklogID)
	Local $d = _SQLite_Exec(-1, "UPDATE main.Worklog SET end_date=" & _SQLite_FastEscape($tFinish)  & _
			  " WHERE id=" & $worklogID)
	Return $d
EndFunc

; Worklog tablosuna eklenecek field'ın son eklenen ile aynı olup olmadigini doner
Func isLastWorklogRecordSame($window_id)
	Local $is_same = True
	Local $last_window_id = -1, $last_worklog_id = -1
	Local $hQuery

	_SQLite_QuerySingleRow(-1, "SELECT id, w_id FROM Worklog ORDER BY id DESC LIMIT 1", $hQuery)
	$last_worklog_id = $hQuery[0]
	$last_window_id = $hQuery[1]

	_DebugPrint("window_id = " & $window_id & " last_window_id = " & $last_window_id)

	If ($window_id <> $last_window_id ) Or ($last_worklog_id = -1) Or ($last_worklog_id = -1)  Then
		$is_same = False
	EndIf

	Return $is_same
EndFunc

; Worklog tablosuna kaydı girer veya kaydı günceller
Func _DB_InsertOrUpdateWorklog($window_id, $process_id, $activeWinHnd, $tStart, $tFinish, $sChangedOrSame)
	; yeni kayit ise veya Son kayit degismemise
	Local $d
	If Not isLastWorklogRecordSame($window_id) Then
		_DebugPrint("Inserting " & $sChangedOrSame & " window data..." & $activeWinHnd & @CRLF)
		$d = _DB_InsertWorklog($process_id, $window_id, $tStart, $tFinish)
		If $d <> $SQLITE_OK  And $d <> $SQLITE_CONSTRAINT Then
			_DebugPrint("SQL Insert Hatasi: @_DB_InsertWorklog  SQLITE hata kodu: " & $d)
			Return False
		EndIf
	Else
		Local $last_worklog_id = _DB_GetLastWorklogID()
		_DebugPrint("Normalizing last " & $sChangedOrSame & " insert with update..." & $activeWinHnd & @CRLF)
		$d = _DB_UpdateWorklog($tFinish, $last_worklog_id)
		If $d <> $SQLITE_OK  And $d <> $SQLITE_CONSTRAINT Then
			_DebugPrint("SQL Update Hatasi: @_DB_UpdateWorklog  SQLITE hata kodu: " & $d)
			Return False
		EndIf
	EndIf
	Return True
EndFunc

;~ aktif pencere yakalayici ana program - periyodik olarak pencere davranislarini yakalar
Func _CaptureWindows()
	Local $sActiveTitle = WinGetTitle("[active]")
	Local $activeWinHnd = WinGetHandle("[active]")
	Local $iPID = WinGetProcess($activeWinHnd)
	Local $sPIDName = _ProcessGetName($iPID)

	Local $sCurrentActiveWin = removeSpecialChars($sActiveTitle)

	_DebugPrint("Entering _CaptureWindows...")

	; eger windows lock lanmissa veya aktif pencere yoksa idle kabul et
	If isWinLocked() Or $sActiveTitle = $PROGRAM_MANAGER Then
		If isWinLocked = True Then _DebugPrint("Windows Locked! IDLE**")
		idleToLog()
		Return
	EndIf

	; pencere boşsa işlem yapma
	If $sActiveTitle == "" Then
		_DebugPrint("Bos win title es geciliyor...")
		Return
	EndIf

	; aktif olmayan pencere varsa işlem yapma
	If Not WinActive($activeWinHnd) Then
		_DebugPrint("Aktif olmayan " & $sActiveTitle & " title  " & $activeWinHnd & " handle es geciliyor...")
		Return
	EndIf

	; gorulen ilk process Process tablosuna eklenir.
	Local $d = _DB_InsertProcess($sPIDName)
	If $d <> $SQLITE_OK  And $d <> $SQLITE_CONSTRAINT Then
		_DebugPrint("SQL Insert Hatasi: @_DB_InsertProcess SQLITE hata kodu: " & $d)
		Return
	EndIf

	Local $tStart = _GetDatetime()
	Local $process_id = _DB_GetLastProcessID($sPIDName)
	Local $window_id

	_DebugPrint("Inserting window data..." & $activeWinHnd & @CRLF)
	Local $d = _DB_InsertWindow($sCurrentActiveWin, $activeWinHnd, $process_id)
	If $d <> $SQLITE_OK  And $d <> $SQLITE_CONSTRAINT Then
		_DebugPrint("_DB_InsertWindow Insert Hatasi: @_DB_InsertWindow  SQLITE hata kodu: " & $d)
		Return
	EndIf

	_DebugPrint("Active Win Title: " &  $sActiveTitle & " @ " & $tStart)
	_DebugPrint("Active Win Handle: " & $activeWinHnd & " @ " & $tStart)

	If $sLastActiveWin == "" Then
		; ilk durum
		_DebugPrint($tStart & $DELIM & $activeWinHnd & $DELIM & $sCurrentActiveWin & " yeni acildi ")
		; screen capture
		If $IS_SCREEN_CAP Then
			$screenShotFilePath = $SCREENSHOT_PATH & "\" & StringRegExpReplace($tStart, "[-:\h]", "") & ".jpg"
			ScreenCaptureWin($activeWinHnd, $screenShotFilePath)
		EndIf

		$window_id = _DB_GetWindowID($sCurrentActiveWin, $activeWinHnd)
		Local $d = _DB_InsertWorklog($process_id, $window_id, $tStart, $tStart)
		If $d <> $SQLITE_OK  And $d <> $SQLITE_CONSTRAINT Then
			_DebugPrint("_DB_InsertWorklog Insert Hatasi: @_DB_InsertWorklog  SQLITE hata kodu: " & $d)
			Return
		EndIf
	ElseIf $sLastActiveWin <> "" And $sLastActiveWin <> $sCurrentActiveWin Then
		; pencere degismisse
		Global $tFinish = _GetDatetime()
		; screen capture
		If $IS_SCREEN_CAP Then
			$screenShotFilePath = $SCREENSHOT_PATH & "\" & StringRegExpReplace($tFinish, "[-:\h]", "") & ".jpg"
			ScreenCaptureWin($activeWinHnd, $screenShotFilePath)
		EndIf

		$window_id = _DB_GetWindowID($sCurrentActiveWin, $activeWinHnd)
		Local $b = _DB_InsertOrUpdateWorklog($window_id, $process_id, $activeWinHnd, $tStart, $tFinish, "changed")
		If $b == False Then
			_DebugPrint("_DB_InsertOrUpdateWorklog hata!")
		EndIf
	Else
		; pencere ayni ise
		$tFinish2 = _GetDatetime()

		$window_id = _DB_GetWindowID($sCurrentActiveWin, $activeWinHnd)
		Local $b = _DB_InsertOrUpdateWorklog($window_id, $process_id, $activeWinHnd, $tStart, $tFinish2, "same")
		If $b == False Then
			_DebugPrint("_DB_InsertOrUpdateWorklog hata!")
		EndIf
	EndIf

	$sLastActiveWin = $sCurrentActiveWin
	$sLastActiveWinHnd = $activeWinHnd
	$sLastPIDName = $sPIDName

	_DebugPrint(" ")
EndFunc   ;==>_CaptureWindows


_Main()