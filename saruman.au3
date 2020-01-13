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

; author: korayy
; date:   200113
; desc:   work logger
; version: 1.11

#Region ;**** Directives ****
#AutoIt3Wrapper_Res_ProductName=WinIzleyici
#AutoIt3Wrapper_Res_Description=User Behaviour Logger
#AutoIt3Wrapper_Res_Fileversion=1.11.0.1
#AutoIt3Wrapper_Res_Fileversion_AutoIncrement=p
#AutoIt3Wrapper_Res_ProductVersion=1.11
#AutoIt3Wrapper_Res_LegalCopyright=ARYASOFT
#AutoIt3Wrapper_Res_Icon_Add=.\saruman.ico,99
#AutoIt3Wrapper_Icon=".\saruman.ico"
#EndRegion ;**** Directives ****

Const $POLL_TIME_MS = 1000
; _CaptureWindows degiskenler
Global $sLastActiveWin = ""
Global $activeWinHnd = ""
Global $sLastActiveWinHnd = ""
Global $bWindowChild = 0
Global $tFinish2 = 0
Global $sLastPIDName = ""
Global Const $BLACK_LIST_WINS = "Program Manager|"
Global Const $LOGFILE_PATH = @WorkingDir & "\worklog.txt"
Global Const $DELIM = ","
Global Const $DELIM_T = ";"
Global Const $SCREENSHOT_PATH = @WorkingDir & "\caps\" & @YEAR & @MON & @MDAY
Global $IS_SCREEN_CAP = True
Global $aFileArray[0] = []
Global Const $FSYNCBUFFER = 5
Global Const $TRAY_ICON_NAME = "saruman.ico"
Global Const $DEBUG = True
Global Const $DEBUG_LOGFILE = @ScriptDir & "\saruman_" & @MON & @MDAY & @YEAR & "_" & @HOUR & @MIN & @SEC & ".txt"


; thread-like fonksiyonları calistir
AdlibRegister("_CaptureWindows", $POLL_TIME_MS)

; busy wait ana program
Func _Main()
	setTray()
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

; tray icon degistirir
Func setTray()
	;#NoTrayIcon
	Opt("TrayMenuMode", 3) ; no default menu (Paused/Exit)
	TraySetState($TRAY_ICONSTATE_SHOW) ; Show the tray menu.
	TraySetIcon($TRAY_ICON_NAME, 99)
EndFunc   ;==>setTray

; text whitelisting
Func removeSpecialChars($str)
	Return StringRegExpReplace($str, "[^0-9,a-z,A-Z, ,\-,.,:,;,\h,\v]", "")
EndFunc   ;==>removeSpecialChars

; kullanici hareketlerini dosyaya yazar
Func AppendToLogFile($filePath, $data)
	Local $hFileOpen = FileOpen($filePath, $FO_APPEND)
	If $hFileOpen = -1 Then
		MsgBox($MB_SYSTEMMODAL, "", "Dosyaya yazma islemi yapilamadi!")
		Return False
	EndIf
	; Write data to the file using the handle returned by FileOpen.
	Local $sLastLine = _ReadFile($filePath, $FO_READ, 1, -1)

	_DebugPrint($data & " data dosyaya ekleniyor...")
	FileWriteLine($hFileOpen, $data)
	; Close the handle returned by FileOpen.
	FileClose($hFileOpen)
EndFunc   ;==>AppendToLogFile

; kullanici hareketlerini array'ye yazar
Func AppendToLogFileArr(ByRef $arr, $data)
	_DebugPrint("adding data to array...")
	_DebugPrint("data in array " & $data)
	_ArrayAdd($arr, $data)
EndFunc   ;==>AppendToLogFileArr

; normalize icin array'deki son satirla veriyi karsilastirir.
Func isLastLineSameArr(ByRef $arr, $data)
	If UBound($arr) == 0 Then
		Return False
	EndIf
	Local $lastLine = $arr[UBound($arr) - 1]
	If StringLen($lastLine) = 0 Then
		Return False
	EndIf
	$sArrayLastLine = StringSplit($lastLine, $DELIM_T)
	$sArrayData = StringSplit($data, $DELIM_T)
	Return Not StringCompare($sArrayLastLine[2], $sArrayData[2])
EndFunc   ;==>isLastLineSameArr

; kullanici hareketlerini array'e normalize yazar
Func NormalizeLastLineArr(ByRef $arr, $data)
	Local $sArrayLastLine
	Local $sArrayData
	Local $aRecords
	Local $sFileRead
	Local $str

	$sFileReadLast = $arr[UBound($arr) - 1]
	$sArrayLastLine = StringSplit($sFileReadLast, $DELIM_T)
	$sArrayData = StringSplit($data, $DELIM_T)

	$sArrayLastLine2 = $sArrayLastLine[2]
	$sArrayLastLine2Arr = StringSplit($sArrayLastLine2, $DELIM)

	$aRecords = $arr
	_ArrayPop($aRecords)
	$str = $sArrayData[1]
	For $i = 1 To UBound($sArrayLastLine2Arr) - 1
		If $i = 1 Then
			$str = $str & $DELIM_T & $sArrayLastLine2Arr[$i]
		Else
			$str = $str & $DELIM & $sArrayLastLine2Arr[$i]
		EndIf
	Next
	_ArrayAdd($aRecords, $str)
	_DebugPrint("overwriting with normalized data..." & $aRecords)
	$arr = $aRecords
EndFunc   ;==>NormalizeLastLineArr

; primitif dosya okur ve icerigini doner
Func _ReadFile($sFilePath, $FILE_MODE = $FO_READ, $bReadLine = 0, $line = 0)
	Local $hFileOpen = FileOpen($sFilePath, $FILE_MODE)
	If $hFileOpen = -1 Then
		MsgBox($MB_SYSTEMMODAL, "", "Dosyaya okuma " & $FILE_MODE & " islemi yapilamadi!")
		Return False
	EndIf

	Local $sFileRead
	; for last line $line = -1
	If $bReadLine Then
		$sFileRead = FileReadLine($hFileOpen, $line)
	Else
		$sFileRead = FileRead($hFileOpen)
	EndIf
	; Close the handle returned by FileOpen.
	FileClose($hFileOpen)
	Return $sFileRead
EndFunc   ;==>_ReadFile

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

; log dosyasina idle** ekler
Func idleToLog()
	$idleStart = _GetDatetime()
	_DebugPrint($idleStart & " Idle mode....")
	$line = $idleStart & $DELIM_T & @UserName & $DELIM & "IDLE**"
	If isLastLineSameArr($aFileArray, $line) Then
		NormalizeLastLineArr($aFileArray, $line)
	Else
		AppendToLogFileArr($aFileArray, $line)
	EndIf
	Return
EndFunc   ;==>idleToLog

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

; buffer array'deki satırları geriden dosyaya sync eder
Func SyncToFile(ByRef $arr, $filePath)
	Local $arr_copy = $arr
	_ArrayReverse($arr_copy)
	; FSYNCBUFFER kadar array dolmussa dosyaya senkronla
	If UBound($arr_copy) < $FSYNCBUFFER Then
		Return
	EndIf

	_DebugPrint("Array Buffer sync ediliyor...")
	For $i = 0 To $FSYNCBUFFER - 1
		$item = _ArrayPop($arr_copy)
		If $item <> "" Then
			AppendToLogFile($filePath, $item)
		EndIf
	Next
	$arr = $arr_copy
EndFunc   ;==>SyncToFile

;~ aktif pencere yakalayici ana program - periyodik olarak pencere davranislarini yakalar
Func _CaptureWindows()
	Local $activeWinList = WinList()
	Local $line = ""
	_DebugPrint("Entering _CaptureWindows...")

	; eger windows lock lanmissa veya aktif pencere yoksa idle kabul et
	If isWinLocked() Or Not isWindowsActive($activeWinList) Then
		If isWindowsActive = False Then _DebugPrint("Aktif pencere yok! IDLE**")
		If isWinLocked = True Then _DebugPrint("Windows Locked! IDLE**")
		idleToLog()
		Return
	EndIf

	For $i = 1 To $activeWinList[0][0]
		; butun BLACK_LIST_WINS deki pencerelerden biriyse bakilmamasi
		Local $sArray = StringSplit($BLACK_LIST_WINS, "|", $STR_ENTIRESPLIT)
		If _ArraySearch($sArray, $activeWinList[$i][0]) <> -1 Then
			Sleep(50)
			ContinueLoop
		EndIf

		If $activeWinList[$i][0] <> "" And BitAND(WinGetState($activeWinList[$i][1]), $WIN_STATE_ACTIVE) Then
			Local $sCurrentActiveWin = $activeWinList[$i][0]
			$activeWinHnd = $activeWinList[$i][1]
			; ekran goruntusu alma
			If Not FileExists($SCREENSHOT_PATH) Then
				DirCreate($SCREENSHOT_PATH)
			EndIf

			Local $iPID = WinGetProcess($activeWinHnd)
			Local $sPIDName = _ProcessGetName($iPID)
			; ilk durum
			If $sLastActiveWin == "" Then
				Global $tStart = _GetDatetime()
				_DebugPrint($tStart & $DELIM & $activeWinHnd & $DELIM & $sCurrentActiveWin & " yeni acildi ")
				; screen capture
				$screenShotFilePath = $SCREENSHOT_PATH & "\" & StringRegExpReplace($tStart, "[-:\h]", "") & ".jpg"
				ScreenCaptureWin($activeWinHnd, $screenShotFilePath)
				$line = $tStart & $DELIM_T & @UserName & $DELIM & "START**"
				AppendToLogFileArr($aFileArray, $line)
				; pencere degisirse
			ElseIf $sLastActiveWin <> "" And $sLastActiveWin <> $sCurrentActiveWin Then
				Global $tFinish = _GetDatetime()
				_DebugPrint($tFinish2 & $DELIM & $tFinish & $DELIM & " " & $sLastActiveWin & " bitti")
				_DebugPrint(_GetDatetime() & $DELIM & $activeWinHnd & " " & $sLastActiveWin & " -> " & $sCurrentActiveWin)
				$line = $tFinish & $DELIM_T & @UserName & $DELIM & $sLastPIDName & $DELIM & removeSpecialChars($sLastActiveWin)
				; screen capture
				$screenShotFilePath = $SCREENSHOT_PATH & "\" & StringRegExpReplace($tFinish, "[-:\h]", "") & ".jpg"
				ScreenCaptureWin($activeWinHnd, $screenShotFilePath)
				If isLastLineSameArr($aFileArray, $line) Then
					NormalizeLastLineArr($aFileArray, $line)
				Else
					AppendToLogFileArr($aFileArray, $line)
				EndIf
				; pencere ayni ise
			Else
				$tFinish2 = _GetDatetime()
				_DebugPrint($tFinish2 & $DELIM & $sPIDName & $DELIM_T & $activeWinHnd & " " & $sLastActiveWin & " -> " & $sCurrentActiveWin & " aynen devam")
				$iPID = WinGetProcess($activeWinHnd)
				$sPIDName = _ProcessGetName($iPID)
				$line = $tFinish2 & $DELIM_T & @UserName & $DELIM & $sPIDName & $DELIM & removeSpecialChars($sCurrentActiveWin)
				If isLastLineSameArr($aFileArray, $line) Then
					NormalizeLastLineArr($aFileArray, $line)
				Else
					AppendToLogFileArr($aFileArray, $line)
				EndIf

			EndIf
			$sLastActiveWin = $sCurrentActiveWin
			$sLastActiveWinHnd = $activeWinHnd
			$sLastPIDName = $sPIDName
		EndIf
	Next
	_DebugPrint(" ")
	SyncToFile($aFileArray, $LOGFILE_PATH)
EndFunc   ;==>_CaptureWindows

_Main()