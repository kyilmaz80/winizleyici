#include <MsgBoxConstants.au3>
#include <FileConstants.au3>
#include <Date.au3>
#include <AutoItConstants.au3>
#include <Array.au3>
#include <WinAPIFiles.au3>
#include <WinAPISysWin.au3>

; author: korayy
; date:   191106
; desc:   work logger
; version: 1.0

Const $POLL_TIME_MS = 1000
Const $CLICK_POLL_TIME_MS = 150
; _CaptureMouseClicks degiskenler
Global $click_timer = 0
; _CaptureWindows degiskenler
Global $lastActiveWin = ""
Global $g_tStruct = DllStructCreate($tagPOINT)
Global $activeWinHnd = ""
Global $lastActiveWinHnd = ""
Global $bWindowChild = 0
Global $tFinish2 = 0
Global Const $BLACK_LIST_WINS = "Program Manager|"
Global Const $LOGFILE_PATH = @WorkingDir & "\worklog.txt"
Global $winActivityDict = ObjCreate('Scripting.Dictionary')


; thread-like fonksiyonları calistir
AdlibRegister("_CaptureWindows", $POLL_TIME_MS)
AdlibRegister("_CaptureMouseClicks", $CLICK_POLL_TIME_MS)

; busy wait ana program
Func _Main()
   While 1
	  Sleep(1000)
   Wend
EndFunc

; kullanici hareketlerini dosyaya yazar
Func AppendToLogFile($filePath, $hostName, $windowName, $endTime)
   Local $hFileOpen = FileOpen($filePath, $FO_APPEND)
   If $hFileOpen = -1 Then
	  MsgBox($MB_SYSTEMMODAL, "", "Dosyaya yazma islemi yapilamadi!")
	  Return False
   EndIf

   ; Write data to the file using the handle returned by FileOpen.
   FileWriteLine($hFileOpen, $endTime & ": " & $hostName & ";" & $windowName & " " & @CRLF)
   ; Close the handle returned by FileOpen.
   FileClose($hFileOpen)
EndFunc


; primitif dosya okur ve icerigini doner
Func _ReadFile($sFilePath, $FILE_MODE=$FO_READ, $bReadLine=0, $line=0)
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
   return $sFileRead
EndFunc

; yyyy-mm-dd hh:mm:ss formatinda veya epoch formatinda guncel tarih zaman doner
Func _GetDatetime($bTimestamp = False)
   $timestamp = _DateDiff('s', "1970/01/01 00:00:00", _NowCalc())
   $timedate = StringReplace(_NowCalc(), "/", "-")
   If $bTimestamp Then
	  return $timestamp
   EndIf
   return $timedate
EndFunc

;~ periyodik olarak pencere davranislarini yakalar
;~ aktif pencere yakalayici
Func _CaptureWindows()
   Local $activeWinList = WinList()
   ConsoleWrite("Entering _CaptureWindows" & @CRLF)
   ; butun BLACK_LIST_WINS deki pencerelerden biriyse bakilmamasi
   For $i = 1 To $activeWinList[0][0]
	  Local $sArray = StringSplit($BLACK_LIST_WINS, "|", $STR_ENTIRESPLIT)
	  If _ArraySearch( $sArray, $activeWinList[$i][0] ) <> -1 Then
		 Sleep(50)
		 ContinueLoop
	  EndIf

	  ; TODO mouse click count add parent of windows to Log

	  If $activeWinList[$i][0] <> "" And BitAND(WinGetState($activeWinList[$i][1]), $WIN_STATE_ACTIVE) Then
		 Local $curActiveWin = $activeWinList[$i][0]
		 $activeWinHnd = $activeWinList[$i][1]
		 ; ilk durum
		 If $lastActiveWin == "" Then
			Global $tStart = _GetDatetime()
			ConsoleWrite($tStart & ","  &  $activeWinHnd & ";"& $curActiveWin & " yeni acildi " & @CRLF )
;~ 			AppendToLogFile($LOGFILE_PATH, @ComputerName, $curActiveWin & " " & $activeWinHnd, $tStart)
			AppendToLogFile($LOGFILE_PATH, @ComputerName, "START**", $tStart)
		 ; pencere degisirse
		 ElseIf $lastActiveWin <> "" And $lastActiveWin <> $curActiveWin Then
			Global $tFinish = _GetDatetime()
			ConsoleWrite($tFinish2 & ","  & $tFinish & ","  & " -> " & $lastActiveWin & " bitti" & @CRLF )
			ConsoleWrite(_GetDatetime() & ","  & $activeWinHnd & " " &  $lastActiveWin & " -> " & $curActiveWin & @CRLF )
			AppendToLogFile($LOGFILE_PATH, @ComputerName, $lastActiveWin & ";" & $lastActiveWinHnd, $tFinish)
;~ 			AppendToLogFile($LOGFILE_PATH, @ComputerName, $curActiveWin & ";" & $activeWinHnd, $tFinish)
		 ; pencere ayni ise
		 Else
			$tFinish2 = _GetDatetime()
			ConsoleWrite($tFinish2 & "," & $activeWinHnd & " "  & $lastActiveWin & " -> " & $curActiveWin & " aynen devam" & @CRLF )
			; Mouse events
			Local $key = String($activeWinHnd)
			If $winActivityDict.count <> 0 and $winActivityDict.exists($key) Then
			   ConsoleWrite($activeWinHnd  & " penceresinde " & $winActivityDict.Item($key) & " olayi..." & @CRLF)
			   AppendToLogFile($LOGFILE_PATH, @ComputerName, $curActiveWin & ";" & $activeWinHnd & ";" & $winActivityDict.Item($key), $tFinish2)
			Else
			   AppendToLogFile($LOGFILE_PATH, @ComputerName, $curActiveWin & ";" & $activeWinHnd)
			EndIf
			; TODO: normalize etmek gerek! Pencere degismeden en son log yazilmadigi icin surekli eklemek gerekiyor...

		 EndIf
		 $lastActiveWin = $curActiveWin
		 $lastActiveWinHnd = $activeWinHnd
	  EndIf
   Next
EndFunc

;~ hexkey de belirtilen tuşa/mouse'a basilmis mi kontrol eder
Func _IsPressed($HexKey)
   Local $AR
   $HexKey = '0x' & $HexKey
   $AR = DllCall("user32","int","GetAsyncKeyState","int",$HexKey)
   If NOT @Error And BitAND($AR[0],0x8000) = 0x8000 Then Return 1
   Return 0
EndFunc

; periyodik olarak fare klik davranislarini yakalar
; TODO: log lamaya eklenebilir
Func _CaptureMouseClicks()
   ConsoleWrite("Entering _CaptureMouseClicks" & @CRLF)
   $click_timer = 0
   While $click_timer < 10000
	  If _IsPressed('01') or  _IsPressed('02') or  _IsPressed('04') Then

		 ; Update the X and Y elements with the X and Y co-ordinates of the mouse.
		 DllStructSetData($g_tStruct, "x", MouseGetPos(0))
		 DllStructSetData($g_tStruct, "y", MouseGetPos(1))

         Local $hWnd = _WinAPI_WindowFromPoint($g_tStruct) ; Retrieve the window handle.
		 ; is window below mouse pointer child of active window handle
		 $bWindowChild = _WinAPI_IsChild($hWnd, $activeWinHnd)
		 If $activeWinHnd Then
			;ConsoleWrite("Is window below mouse: " & $hWnd & " child of parent: " &  $activeWinHnd & " : " & $bWindowChild & @CRLF)
			ConsoleWrite( "Window parent handle: " & $activeWinHnd & " " & _GetDatetime() &  " mouse clicked on parent @ x,y:" & $g_tStruct.X & "," & $g_tStruct.Y  & @CRLF)
			; Mouse hareket sayilarini istatistik amacli toplama ve basit bir sozlukte kaydetme
			Local $key = String($activeWinHnd)
			If $winActivityDict.exists($key) Then
			   Local $value = $winActivityDict.Item($key)
			   Local $arr = StringSplit($value, "-")
			   Local $count = $arr[2]
			   $count = $count + 1
			   $winActivityDict.Item($key) = "MouseClicked-" & $count
			Else
			   $winActivityDict.Add($key, "MouseClicked-1")
			EndIf
		 Else
			ConsoleWrite( "Window handle: " & $hWnd & " " & _GetDatetime() &  " mouse clicked @ x,y:" & $g_tStruct.X & "," & $g_tStruct.Y  & @CRLF)
		 EndIf
		 Sleep(100)
	  EndIf
	  $click_timer = $click_timer + 0.1 ; busy wait
   WEnd
EndFunc

_Main()