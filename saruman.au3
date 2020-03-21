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
#include <GetOpt.au3> ; UDF v1.3

; author: korayy
; date:   200320
; desc:   work logger
; version: 1.29

#Region ;**** Directives ****
#AutoIt3Wrapper_Res_ProductName=WinIzleyici
#AutoIt3Wrapper_Res_Description=User Behaviour Logger
#AutoIt3Wrapper_Res_Fileversion=1.29.0.1
#AutoIt3Wrapper_Res_Fileversion_AutoIncrement=p
#AutoIt3Wrapper_Res_ProductVersion=1.29
#AutoIt3Wrapper_Res_LegalCopyright=ARYASOFT
#AutoIt3Wrapper_Res_Icon_Add=.\saruman.ico,99
#AutoIt3Wrapper_Icon=".\saruman.ico"
#AutoIt3Wrapper_OutFile="dist\saruman.exe"
#EndRegion ;**** Directives ****

Global $POLL_TIME_MS = 10000
; _CaptureWindows degiskenler
Global $sLastActiveWin = ""
Global $activeWinHnd = ""
Global $sLastActiveWinHnd = ""
Global $tFinish2 = 0
Global $sLastPIDName = ""
Global Const $BLACK_LIST_WINS = "Program Manager|"
Global $DBFILE_PATH = @WorkingDir & "\worklog.db"
Global $SCREENSHOT_PATH = @WorkingDir & "\caps\" & @YEAR & @MON & @MDAY
Global $IS_SCREEN_CAP = False
Global Const $TRAY_ICON_NAME = "saruman.ico"
Global $DEBUG = False
Global Const $DEBUG_LOGFILE = @ScriptDir & "\saruman_" & @MON & @MDAY & @YEAR & "_" & @HOUR & @MIN & @SEC & ".txt"
Global Const $SUPERVISOR_EXE_NAME = "gandalf.exe"
Global Const $SARUMAN_EXE_NAME = "saruman.exe"
Global $bSupervisorExists = True
Global $bCheckSupervisor = True
Global Const $PROGRAM_MANAGER = "Program Manager"
Global Const $IDLE_W_ID = 0
Global Const $IDLE_PROCESS_ID = 1
Global Const $IDLE_PID = 0
Global Const $IDLE_WIN_HANDLE = "idle"
Global Const $SETTINGS_PATH = EnvGet("APPDATA") & "\saruman"
Global Const $SETTINGS_FILE = $SETTINGS_PATH & "\settings.ini"

; ana program
Func _Main()
	saruman_exit()
	_InputInit()
	_DebugPrint("Registering _CaptureWindow() for " & $POLL_TIME_MS & " ms" & @CRLF)
	AdlibRegister("_CaptureWindows", $POLL_TIME_MS)
	; thread-like fonksiyonları calistir
	setTray()
	_DBInit()
	; busy wait ve gandalf kontrol
	While 1
		If $bCheckSuperVisor Then
			_StartSupervisor($SUPERVISOR_EXE_NAME)
		EndIf
		Sleep(500)
	WEnd
EndFunc   ;==>_Main

; getopt tarzi giris opsiyonlari alir ve set eder
Func _InputInit()

	; komut satir parametreleri verilmemisse default degerler.
	If 0 = $CmdLine[0] Then
		Return
	EndIf
	_DebugPrint("Parsing the command line options...")
	If FileExists($SETTINGS_FILE) Then
		_DebugPrint($SETTINGS_FILE & " ini read ..." & @CRLF)
		$DBFILE_PATH = IniRead($SETTINGS_FILE, "General", "DBFILE_PATH", $DBFILE_PATH)
		$POLL_TIME_MS = IniRead($SETTINGS_FILE, "General", "POLL_TIME_MS", $POLL_TIME_MS)
	EndIf

	Local $aOpts[7][3] = [ _
			['-v', '--verbose', True], _
			['-d', '--database', $DBFILE_PATH], _
			['-t', '--time', $POLL_TIME_MS], _
			['-s', '--screenshots', 1], _
			['-i', '--init', True], _
			['-c', '--checksupervisor', 1], _
			['-h', '--help', True] _
			]
	Local $dFlag = False, $vFlag = False, $tFlag = False, $sFlag = False, $iFlag = False
	Local $cFlag = False
	Local $dArg, $tArg, $cArg
	Local $errFlag = False
	Local $msg = ""

	_GetOpt_Set($aOpts) ; Set options.
	If 0 < $GetOpt_Opts[0] Then ; If there are any options...
		While 1
			; Get the next option passing a string with valid options.
			$sOpt = _GetOpt('vdtsich')
			If Not $sOpt Then ExitLoop
			Switch $sOpt
				Case '?' ; Unknown options come here. @extended is set to $E_GETOPT_UNKNOWN_OPTION
				Case ':' ; Options with missing required arguments come here. @extended is set to $E_GETOPT_MISSING_ARGUMENT
				Case 'v'
					$vFlag = True
					$msg &= "verbose flag given "
				Case 'd'
					$dFlag = True
					$dArg = $GetOpt_Arg
					$msg &= "database_path: " & $dArg & " "
				Case 't'
					$tFlag = True
					$tArg = $GetOpt_Arg
					$msg &= "time_ms: " & $tArg & " "
					If VarGetType(int($tArg)) <> "Int32" Then
						_DebugPrint("error in t option")
						$errFlag = True
					EndIf
				Case 's'
					$sFlag = True
				Case 'i'
					$iFlag = True
				Case 'c'
					$cFlag = True
					$cArg = Int($GetOpt_Arg)
					$msg &= "checksupervisor: " & $cArg & " "
					If  Not ($cArg = 0 Or $cArg = 1) Then
						_DebugPrint("error in c option")
						$errFlag = True
					EndIf
				Case 'h'
					MsgBox(0, 'saruman.exe', 'User behaviour logger' & @CRLF & _
							'Usage: ' & @CRLF & _
							' saruman.exe --help -h' & @CRLF & _
							' saruman.exe --verbose -v' & @CRLF & _
							' saruman.exe --time -t' & @CRLF & _
							' saruman.exe --screenshots -s' & @CRLF & _
							' saruman.exe --database -d' & @CRLF & _
							' saruman.exe --init -i' & @CRLF & _
							' saruman.exe --checksupervisor -c' & @CRLF & _
							'Options: ' & @CRLF & _
							' --help	            Shows help win' & @CRLF & _
							' --verbose      		Debug log to file' & @CRLF & _
							' --time=<ms>			Wait time in ms [default: 10000ms]' & @CRLF & _
							' --database=<path>		SQLite DB path' & @CRLF & _
							' --screenshots=<0|1>	Save screenshots or not' & @CRLF & _
							' --checksupervisor=<0|1>  Check supervisor gandalf or not' & @CRLF & _
							' --init=<True>			Initialize DB')
					Exit
			EndSwitch
		WEnd

		If $errFlag Then
			MsgBox($MB_ICONERROR, 'saruman.exe', 'wrong usage!')
			Exit
		EndIf

		If Not FileExists($SETTINGS_FILE) Then
			_DebugPrint($SETTINGS_PATH & " olusturuluyor..." & @CRLF)
			DirCreate($SETTINGS_PATH)
		EndIf

		If $dFlag Then
			$DBFILE_PATH = $dArg
			IniWrite($SETTINGS_FILE, "General", "DBFILE_PATH", $DBFILE_PATH)
		EndIf
		If $vFlag Then $DEBUG = True
		If $tFlag Then
			$POLL_TIME_MS = $tArg
			IniWrite($SETTINGS_FILE, "General", "POLL_TIME_MS", $POLL_TIME_MS)
		EndIf
		If $cFlag Then
			If $cArg = 1 Then
				$bCheckSupervisor = True
			Else
				$bCheckSupervisor = False
			EndIf
		EndIf
		If $sFlag Then $IS_SCREEN_CAP = True
		If $iFlag Then
			_DBInit($iFlag)
			Exit
		EndIf
		_DebugPrint("Given options: " & $msg)
	EndIf
EndFunc   ;==>_InputInit

; saruman.exe prosesi varsa exit
Func saruman_exit()
	Local $aSarumanList = ProcessList($SARUMAN_EXE_NAME)
	Local $numOfSaruman = 1

	If IsArray($aSarumanList) Then
		$numOfSaruman = $aSarumanList[0][0]
	EndIf

	If $numOfSaruman > 1 Then
		_DebugPrint("Saruman exe count > 1 Exiting...")
		Exit
	EndIf
EndFunc

; tray icon degistirir
Func setTray()
	;#NoTrayIcon
	Opt("TrayMenuMode", 3) ; no default menu (Paused/Exit)
	TraySetState($TRAY_ICONSTATE_SHOW) ; Show the tray menu.
	TraySetIcon($TRAY_ICON_NAME, 99)
EndFunc   ;==>setTray

Func _DBInit($reinit = False)
	Local $hDB ;
	_SQLite_Startup()
	_DebugPrint("_SQLite_LibVersion=" & _SQLite_LibVersion() & @CRLF)
	If @error Then Exit MsgBox(16, "SQLite Hata", "SQLite.dll yuklenemedi!")

	If FileExists($DBFILE_PATH) And $reinit = False Then
		_DebugPrint($DBFILE_PATH & " aciliyor..." & @CRLF)
		$hDB = _SQLite_Open($DBFILE_PATH)
		If @error Then Exit MsgBox(16, "SQLite Hata", "Veri tabanı açılamadı!")
	Else
		If FileExists($DBFILE_PATH) And $reinit Then
			; rename old db to a new one
			_DebugPrint($DBFILE_PATH & " sifirlaniyor..." & @CRLF)
			FileMove($DBFILE_PATH, $DBFILE_PATH & @MON & @MDAY & @YEAR & "_" & @HOUR & @MIN & @SEC)
		EndIf
		_DebugPrint($DBFILE_PATH & " db aciliyor..." & @CRLF)
		$hDB = _SQLite_Open($DBFILE_PATH)
		If @error Then Exit MsgBox(16, "SQLite Hata", "Veri tabanı açılamadı!")
		; TODO create tables
		; Yeni tablo olustur Process
		_SQLite_Exec(-1, "CREATE TABLE IF NOT EXISTS User(id INTEGER NOT NULL, name TEXT NOT NULL, PRIMARY KEY(id));")
		_SQLite_Exec(-1, "CREATE TABLE IF NOT EXISTS Process(id INTEGER NOT NULL, name TEXT NOT NULL UNIQUE, PRIMARY KEY(id));")
		_SQLite_Exec(-1, "CREATE TABLE Window (id	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, " & _
				"title	TEXT NOT NULL UNIQUE, handle TEXT, p_id INTEGER NOT NULL, " & _
				"FOREIGN KEY(p_id) REFERENCES Process(id));")
		_SQLite_Exec(-1, "CREATE TABLE IF NOT EXISTS Worklog ( " & _
				"id	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, " & _
				"p_id	INTEGER NOT NULL, " & _
				"pid	INTEGER NOT NULL DEFAULT 0," & _
				"u_id	INTEGER NOT NULL, " & _
				"w_id 	INTEGER DEFAULT 0, " & _
				"start_date TEXT NOT NULL, " & _
				"end_date TEXT NOT NULL," & _
				"idle	INTEGER DEFAULT 0, " & _
				"processed	INTEGER DEFAULT 0," & _
				"dns_processed	INTEGER DEFAULT 0," & _
				"FOREIGN KEY(p_id) REFERENCES Process(id), " & _
				"FOREIGN KEY(u_id) REFERENCES User(id), " & _
				"FOREIGN KEY(w_id) REFERENCES Window(id));")
		_SQLite_Exec(-1, "CREATE TABLE DNSClient ( " & _
				"pid	INTEGER NOT NULL DEFAULT 0, " & _
				"query_name	TEXT, " & _
				"parent_pid	INTEGER," & _
				"time_created	TEXT );")
		; idle veri ekleme
		_SQLite_Exec(-1, "INSERT INTO Process(id, name) VALUES (1,'idle');")
		_SQLite_Exec(-1, "INSERT INTO Window(id, title, handle, p_id) VALUES (" & $IDLE_W_ID & ", " & _
				_SQLite_FastEscape($IDLE_WIN_HANDLE) & ", " & _SQLite_FastEscape($IDLE_WIN_HANDLE) & _
				", " & $IDLE_PROCESS_ID & ");")
		; @UserName ekleme
		_SQLite_Exec(-1, "INSERT INTO User(id, name) VALUES (1," & _SQLite_FastEscape(@UserName) & ");")
	EndIf
	Return $hDB
EndFunc   ;==>_DBInit

;debug helper function
Func _DebugPrint($sMsgString)
	ConsoleWrite($sMsgString & @CRLF)
	If $DEBUG Then
		_FileWriteLog($DEBUG_LOGFILE, $sMsgString)
	EndIf
EndFunc   ;==>_DebugPrint


;~ surekli supervizor process'e bakar
Func _StartSupervisor($sProcessName)
	If Not ProcessExists($sProcessName) Then
		If Not FileExists(@WorkingDir & ".\" & $SUPERVISOR_EXE_NAME) Then
			; if more than one err no more log
			If $bSupervisorExists = True Then
				_DebugPrint($SUPERVISOR_EXE_NAME & " exe programi bulunamadi..." & @CRLF)
			EndIf
			$bSupervisorExists = False
			Return
		EndIf
		$iPID = Run(@WorkingDir & ".\" & $sProcessName, @WorkingDir)
		_DebugPrint($sProcessName & "prosesi " & $iPID & " pid si ile çalistirildi..." & @CRLF)
	EndIf
EndFunc   ;==>_StartSupervisor

; text blacklisting
Func removeSpecialChars($str)
	; Return StringRegExpReplace($str, "[^0-9,a-z,A-Z, ,\-,.,:,;,\h,\v]", "")
	Return StringRegExpReplace($str, "\r\n|\t", "")
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
	Local $hQuery, $idleStart
	Local $aRow
	Local $tFinish
	; init
	Local $iRes_id = -1, $iRes_w_id = -1, $iRes_idle = -1
	Local $b

	$idleStart = _GetDatetime()
	_DebugPrint($idleStart & " Idle mode....")

	$idle = _DB_GetLastWorklogIdle()
	If $idle = 0 Then
		$tFinish = $idleStart
		$b = _DB_InsertOrUpdateWorklog($IDLE_W_ID, $IDLE_PROCESS_ID, $IDLE_PID, $IDLE_WIN_HANDLE, $idleStart, $tFinish, "changed", 1)
	Else
		$tFinish = _GetDatetime()
		$b = _DB_InsertOrUpdateWorklog($IDLE_W_ID, $IDLE_PROCESS_ID, $IDLE_PID, $IDLE_WIN_HANDLE, $idleStart, $tFinish, "same", 1)
	EndIf

	If $b == False Then
		_DebugPrint("_DB_InsertOrUpdateWorklog idleToLog hata!")
	EndIf

	Return 0
EndFunc   ;==>idleToLog

Func _DB_GetCurrentUserID()
	Local $aRow
	Local $u_id

	Local $userName = @UserName

	If $SQLITE_OK <> _SQLite_QuerySingleRow(-1, "SELECT id FROM main.User WHERE name = " & _SQLite_FastEscape($userName) & ";", $aRow) Then
		_DebugPrint("_DB_GetCurrentUserID Problem: Error Code: " & _SQLite_ErrCode() & "Error Message: " & _SQLite_ErrMsg)
	EndIf

	$u_id = $aRow[0]
	Return $u_id
EndFunc   ;==>_DB_GetCurrentUserID

;~ processName proses adının  DB'deki id'sini doner
Func _DB_GetLastProcessID($processName)
	Local $aRow
	Local $p_id

	If $SQLITE_OK <> _SQLite_QuerySingleRow(-1, "SELECT id FROM main.Process WHERE name = " & _SQLite_FastEscape($processName) & ";", $aRow) Then
		_DebugPrint("_DB_GetLastProcessID Problem: Error Code: " & _SQLite_ErrCode() & "Error Message: " & _SQLite_ErrMsg)
	EndIf
	$p_id = $aRow[0]
	Return $p_id
EndFunc   ;==>_DB_GetLastProcessID

;~ $windowName window adının  DB'deki son satir id'sini doner
Func _DB_GetLastWindowID($windowName)
	Local $aRow
	Local $w_id
	If $SQLITE_OK <> _SQLite_QuerySingleRow(-1, "SELECT id FROM main.Window WHERE title = " & _SQLite_FastEscape($windowName) & ";", $aRow) Then
		_DebugPrint("_DB_GetLastWindowID Problem: Error Code: " & _SQLite_ErrCode() & "Error Message: " & _SQLite_ErrMsg)
	EndIf
	$w_id = $aRow[0]
	Return $w_id
EndFunc   ;==>_DB_GetLastWindowID

;~ Windows tablosundaki windowName ve handle a karsilik gelen id doner
Func _DB_GetWindowID($windowName, $windowHandle)
	Local $aRow
	Local $w_id
	If $SQLITE_OK <> _SQLite_QuerySingleRow(-1, "SELECT id FROM main.Window WHERE title = " & _SQLite_FastEscape($windowName) & _
			" AND handle = " & "'" & $windowHandle & "'" & ";", $aRow) Then
		_DebugPrint("_DB_GetWindowID Problem: for " & $windowHandle & " " & $windowName & " arow[0] : " & $aRow[0] & " Error Code: " & _SQLite_ErrCode() & "Error Message: " & _SQLite_ErrMsg)
	EndIf
	$w_id = $aRow[0]
	Return $w_id
EndFunc   ;==>_DB_GetWindowID

; Worklog tablosundaki en son id'yi doner
Func _DB_GetLastWorklogID()
	Local $aRow
	Local $w_id

	If $SQLITE_OK <> _SQLite_QuerySingleRow(-1, "SELECT id FROM Worklog ORDER BY id DESC LIMIT 1", $aRow) Then
		_DebugPrint("_DB_GetLastWorklogID Problem: Error Code: " & _SQLite_ErrCode() & "Error Message: " & _SQLite_ErrMsg)
		Return -1
	EndIf
	$w_id = $aRow[0]
	Return $w_id
EndFunc   ;==>_DB_GetLastWorklogID

; Worklog tablosundaki en son idle durumu doner
Func _DB_GetLastWorklogIdle()
	Local $aRow
	Local $w_id

	If $SQLITE_OK <> _SQLite_QuerySingleRow(-1, "SELECT idle FROM Worklog ORDER BY id DESC LIMIT 1", $aRow) Then
		_DebugPrint("_DB_GetLastWorklogIdle Problem: Error Code: " & _SQLite_ErrCode() & "Error Message: " & _SQLite_ErrMsg)
		Return -1
	EndIf
	$w_id = $aRow[0]
	Return $w_id
EndFunc   ;==>_DB_GetLastWorklogIdle

; Process tablosundan proses adına karşılık id döner
Func _DB_GetProcessID($processName)
	Local $aRow
	Local $p_id

	If $SQLITE_OK <> _SQLite_QuerySingleRow(-1, "SELECT id FROM main.Process WHERE name = '" & _
			_SQLite_FastEscape($processName) & "';", $aRow) Then
		_DebugPrint("_DB_GetProcessID Problem: Error Code: " & _SQLite_ErrCode() & "Error Message: " & _SQLite_ErrMsg)
	EndIf

	$p_id = $aRow[0]
	Return $p_id
EndFunc   ;==>_DB_GetProcessID


; Process tablosuna kayıt ekler ve sql exec sonucu durumunu doner
Func _DB_InsertProcess($processName)
	Local $d = _SQLite_Exec(-1, "INSERT INTO main.Process(name) VALUES (" & _SQLite_FastEscape($processName) & ");")
	Return $d
EndFunc   ;==>_DB_InsertProcess

; Window tablosuna kayıt ekler ve sql exec sonucu durumunu doner
Func _DB_InsertWindow($windowTitle, $windowHandle, $processID)
	Local $d = _SQLite_Exec(-1, "INSERT INTO main.Window(title, handle, p_id) VALUES (" & _SQLite_FastEscape($windowTitle) & "," & _
			"'" & $windowHandle & "'" & "," & $processID & ");")
	Return $d
EndFunc   ;==>_DB_InsertWindow

; Worklog tablosuna kayıt ekler ve sql exec sonucu durumunu doner
Func _DB_InsertWorklog($processID, $pid, $windowID, $start_date, $end_date, $idle)
	Local $d = _SQLite_Exec(-1, "INSERT INTO main.Worklog(p_id, pid, u_id, w_id, start_date, end_date, idle) VALUES (" & _
			$processID & ", " & $pid & ", " & _DB_GetCurrentUserID() & ", " & _
			$windowID & ", " & _SQLite_FastEscape($start_date) & ", " & _SQLite_FastEscape($end_date) & _
			", " & $idle & ");")
	Return $d
EndFunc   ;==>_DB_InsertWorklog

; Worklog tablosundaki kaydı günceller ve sql exec sonucu durumunu doner
Func _DB_UpdateWorklog($tFinish, $worklogID)
	Local $d = _SQLite_Exec(-1, "UPDATE main.Worklog SET end_date=" & _SQLite_FastEscape($tFinish) & _
			" WHERE id=" & $worklogID)
	Return $d
EndFunc   ;==>_DB_UpdateWorklog

; Worklog tablosuna eklenecek field'ın son eklenen ile aynı olup olmadigini doner
Func isLastWorklogRecordSame($window_id)
	Local $is_same = True
	Local $last_window_id = -1, $last_worklog_id = -1
	Local $hQuery

	_SQLite_QuerySingleRow(-1, "SELECT id, w_id FROM Worklog ORDER BY id DESC LIMIT 1", $hQuery)
	$last_worklog_id = $hQuery[0]
	$last_window_id = $hQuery[1]

	_DebugPrint("window_id = " & $window_id & " last_window_id = " & $last_window_id)

	If ($window_id <> $last_window_id) Or ($last_worklog_id = -1) Or ($last_worklog_id = -1) Then
		$is_same = False
	EndIf

	Return $is_same
EndFunc   ;==>isLastWorklogRecordSame

; Worklog tablosuna kaydı girer veya kaydı günceller
Func _DB_InsertOrUpdateWorklog($window_id, $process_id, $pid, $activeWinHnd, $tStart, $tFinish, $sChangedOrSame, $idle)
	; yeni kayit ise veya Son kayit degismemise
	Local $d
	If Not isLastWorklogRecordSame($window_id) Then
		_DebugPrint("Inserting " & $sChangedOrSame & " window data..." & $activeWinHnd & @CRLF)
		$d = _DB_InsertWorklog($process_id, $pid, $window_id, $tStart, $tFinish, $idle)
		If $d <> $SQLITE_OK And $d <> $SQLITE_CONSTRAINT Then
			_DebugPrint("SQL Insert Hatasi: @_DB_InsertWorklog  SQLITE hata kodu: " & $d)
			Return False
		EndIf
	Else
		Local $last_worklog_id = _DB_GetLastWorklogID()
		_DebugPrint("Normalizing last " & $sChangedOrSame & " insert with update..." & $activeWinHnd & @CRLF)
		$d = _DB_UpdateWorklog($tFinish, $last_worklog_id)
		If $d <> $SQLITE_OK And $d <> $SQLITE_CONSTRAINT Then
			_DebugPrint("SQL Update Hatasi: @_DB_UpdateWorklog  SQLITE hata kodu: " & $d)
			Return False
		EndIf
	EndIf
	Return True
EndFunc   ;==>_DB_InsertOrUpdateWorklog

;~ aktif pencere yakalayici ana program - periyodik olarak pencere davranislarini yakalar
Func _CaptureWindows()
	Local $sActiveTitle = WinGetTitle("[active]")
	Local $activeWinHnd = WinGetHandle("[active]")
	Local $iPID = WinGetProcess($activeWinHnd)
	Local $sPIDName = _ProcessGetName($iPID)
	Local $tStart = _GetDatetime()

	Local $sCurrentActiveWin = removeSpecialChars($sActiveTitle)

	_DebugPrint("Entering _CaptureWindows " & $tStart)

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
	If $d <> $SQLITE_OK And $d <> $SQLITE_CONSTRAINT Then
		_DebugPrint("SQL Insert Hatasi: @_DB_InsertProcess SQLITE hata kodu: " & $d)
		Return
	EndIf


	Local $process_id = _DB_GetLastProcessID($sPIDName)
	Local $window_id

	_DebugPrint("Inserting window data..." & $activeWinHnd & @CRLF)
	Local $d = _DB_InsertWindow($sCurrentActiveWin, $activeWinHnd, $process_id)
	If $d <> $SQLITE_OK And $d <> $SQLITE_CONSTRAINT Then
		_DebugPrint("_DB_InsertWindow Insert Hatasi: @_DB_InsertWindow  SQLITE hata kodu: " & $d)
		Return
	EndIf

	_DebugPrint("Active Win Title: " & $sActiveTitle & " @ " & $tStart)
	_DebugPrint("Active Win Handle: " & $activeWinHnd & " @ " & $tStart)

	If $sLastActiveWin == "" Then
		; ilk durum
		_DebugPrint($tStart & " " & $activeWinHnd & " " & $sCurrentActiveWin & " yeni acildi ")
		; screen capture
		If $IS_SCREEN_CAP Then
			$screenShotFilePath = $SCREENSHOT_PATH & "\" & StringRegExpReplace($tStart, "[-:\h]", "") & ".jpg"
			ScreenCaptureWin($activeWinHnd, $screenShotFilePath)
		EndIf

		; $window_id = _DB_GetWindowID($sCurrentActiveWin, $activeWinHnd)
		$window_id = _DB_GetLastWindowID($sCurrentActiveWin)
		Local $d = _DB_InsertWorklog($process_id, $iPID, $window_id, $tStart, $tStart, 0)
		If $d <> $SQLITE_OK And $d <> $SQLITE_CONSTRAINT Then
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

		; $window_id = _DB_GetWindowID($sCurrentActiveWin, $activeWinHnd)
		$window_id = _DB_GetLastWindowID($sCurrentActiveWin)
		Local $b = _DB_InsertOrUpdateWorklog($window_id, $process_id, $iPID, $activeWinHnd, $tStart, $tFinish, "changed", 0)
		If $b == False Then
			_DebugPrint("_DB_InsertOrUpdateWorklog hata!")
		EndIf
	Else
		; pencere ayni ise
		$tFinish2 = _GetDatetime()

		; $window_id = _DB_GetWindowID($sCurrentActiveWin, $activeWinHnd)
		$window_id = _DB_GetLastWindowID($sCurrentActiveWin)
		Local $b = _DB_InsertOrUpdateWorklog($window_id, $process_id, $iPID, $activeWinHnd, $tStart, $tFinish2, "same", 0)
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
