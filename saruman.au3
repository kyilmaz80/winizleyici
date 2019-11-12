#include <MsgBoxConstants.au3>
#include <FileConstants.au3>
#include <Date.au3>
#include <AutoItConstants.au3>
#include <Array.au3>
#include <WinAPIFiles.au3>
#include <WinAPISysWin.au3>
#include <Process.au3>
#include <File.au3>


; author: korayy
; date:   191112
; desc:   work logger
; version: 1.3

Const $POLL_TIME_MS = 1000
; _CaptureWindows degiskenler
Global $sLastActiveWin = ""
Global $g_tStruct = DllStructCreate($tagPOINT)
Global $activeWinHnd = ""
Global $sLastActiveWinHnd = ""
Global $bWindowChild = 0
Global $tFinish2 = 0
Global $sLastPIDName = ""
Global Const $BLACK_LIST_WINS = "Program Manager|"
Global Const $LOGFILE_PATH = @WorkingDir & "\worklog.txt"

; thread-like fonksiyonları calistir
AdlibRegister("_CaptureWindows", $POLL_TIME_MS)

; busy wait ana program
Func _Main()
   While 1
	  Sleep(500)
   Wend
EndFunc

; kullanici hareketlerini dosyaya yazar
Func AppendToLogFile($filePath, $data)
   Local $hFileOpen = FileOpen($filePath, $FO_APPEND)
   If $hFileOpen = -1 Then
	  MsgBox($MB_SYSTEMMODAL, "", "Dosyaya yazma islemi yapilamadi!")
	  Return False
   EndIf
   ; Write data to the file using the handle returned by FileOpen.
   FileWriteLine($hFileOpen, $data)
   ; Close the handle returned by FileOpen.
   FileClose($hFileOpen)
EndFunc

; normalize icin dosyadaki son satirla veriyi karsilastirir.
Func isLastLineSame($filePath, $data)
   Local $lastLine = _ReadFile($filePath,$FO_READ, 1,-1)
   If StringLen($lastLine) = 0 Then
	  Return False
   EndIf
   ; ConsoleWrite("Last Line: " & $lastLine &  @CRLF )
   ; ConsoleWrite("Data: " & $data  &  @CRLF)
   $sArrayLastLine = StringSplit($lastLine, ";")
   $sArrayData =  StringSplit($data, ";")
   return not StringCompare($sArrayLastLine[2], $sArrayData[2])
EndFunc

; kullanici hareketlerini dosyaya yazar
Func NormalizeLastLine($filePath, $data)
   Local $sArrayLastLine
   Local $sArrayData
   Local $aRecords
   Local $sFileRead
   Local $str

   $sFileRead = _ReadFile($filePath,$FO_READ, 1, -1)
   $sArrayLastLine = StringSplit($sFileRead, ";")
   $sArrayData =  StringSplit($data, ";")

   $sArrayLastLine2 = $sArrayLastLine[2]
   $sArrayLastLine2Arr = StringSplit($sArrayLastLine2, ",")

   $aRecords = FileReadToArray($filePath)
   _ArrayPop($aRecords)
   ;~ _ArrayAdd($aRecords, $sArrayData[1] & ";" & $sArrayLastLine2Arr[1] & "," & $sArrayLastLine2Arr[2]  & "," & $sArrayLastLine2Arr[3])
   $str = $sArrayData[1]
   For $i=1 to UBound($sArrayLastLine2Arr) - 1
	  If $i = 1 Then
		 $str = $str & ";" & $sArrayLastLine2Arr[$i]
	  Else
		 $str = $str & "," & $sArrayLastLine2Arr[$i]
	  EndIf
   Next
   ConsoleWrite("STR: " & $str & @CRLF)
    _ArrayAdd($aRecords,$str)
   ConsoleWrite("overwriting with normalized data..." & $aRecords & @CRLF)
   _FileWriteFromArray($filePath, $aRecords)
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

; windows lock kontrolu
Func isWinLocked()
   If ProcessExists("LogonUI.exe") Then
	  Return True
   Else
	  Return False
   EndIf
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
   Local $line = ""
   ConsoleWrite("Entering _CaptureWindows" & @CRLF)

   If isWinLocked() Then
	  ConsoleWrite("Windows Locked! Idle mode....")
	  $idleStart = _GetDatetime()
	  $line = $idleStart & ";" & @ComputerName & "," & "IDLE**"
	  If isLastLineSame($LOGFILE_PATH, $line) Then
		 NormalizeLastLine($LOGFILE_PATH, $line)
	  Else
		 AppendToLogFile($LOGFILE_PATH, $line)
	  EndIf
	  Return
   EndIf

   For $i = 1 To $activeWinList[0][0]
      ; butun BLACK_LIST_WINS deki pencerelerden biriyse bakilmamasi
	  Local $sArray = StringSplit($BLACK_LIST_WINS, "|", $STR_ENTIRESPLIT)
	  If _ArraySearch( $sArray, $activeWinList[$i][0] ) <> -1 Then
		 Sleep(50)
		 ContinueLoop
	  EndIf

	  If $activeWinList[$i][0] <> "" And BitAND(WinGetState($activeWinList[$i][1]), $WIN_STATE_ACTIVE) Then
		 Local $sCurrentActiveWin = $activeWinList[$i][0]
		 $activeWinHnd = $activeWinList[$i][1]
		 Local $iPID = WinGetProcess($activeWinHnd)
		 Local $sPIDName = _ProcessGetName($iPID)
		 ; ilk durum
		 If $sLastActiveWin == "" Then
			Global $tStart = _GetDatetime()
			ConsoleWrite($tStart & ","  &  $activeWinHnd & ","& $sCurrentActiveWin & " yeni acildi " & @CRLF )
			$line = $tStart & ";" & @ComputerName & "," & "START**"
			AppendToLogFile($LOGFILE_PATH, $line)
		 ; pencere degisirse
		 ElseIf $sLastActiveWin <> "" And $sLastActiveWin <> $sCurrentActiveWin Then
			Global $tFinish = _GetDatetime()
			ConsoleWrite($tFinish2 & ","  & $tFinish & ","  & " -> " & $sLastActiveWin & " bitti" & @CRLF )
			ConsoleWrite(_GetDatetime() & ","  & $activeWinHnd & " " &  $sLastActiveWin & " -> " & $sCurrentActiveWin & @CRLF )
			$line =  $tFinish & ";" & @ComputerName & "," & $sLastPIDName  & "," & $sLastActiveWin
			If isLastLineSame($LOGFILE_PATH, $line) Then
			   NormalizeLastLine($LOGFILE_PATH, $line)
			Else
			   AppendToLogFile($LOGFILE_PATH, $line)
			EndIf
		 ; pencere ayni ise
		 Else
			$tFinish2 = _GetDatetime()
			ConsoleWrite($tFinish2 & "," & $sPIDName  & ";" & $activeWinHnd & " "  & $sLastActiveWin & " -> " & $sCurrentActiveWin & " aynen devam" & @CRLF )
			$iPID = WinGetProcess($activeWinHnd)
			$sPIDName = _ProcessGetName($iPID)
			$line = $tFinish2 & ";" & @ComputerName & "," & $sPIDName  & "," & $sCurrentActiveWin

			If isLastLineSame($LOGFILE_PATH, $line) Then
			   NormalizeLastLine($LOGFILE_PATH, $line)
			Else
			   AppendToLogFile($LOGFILE_PATH, $line)
			EndIf

		 EndIf
		 $sLastActiveWin = $sCurrentActiveWin
		 $sLastActiveWinHnd = $activeWinHnd
		 $sLastPIDName = $sPIDName
	  EndIf
   Next
EndFunc

_Main()