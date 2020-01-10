if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
{
    Write-Host "please run elevated user"
    Start-Sleep -s 5
    exit
    
}

$url="http://35.156.50.195/esbackup/winizleyici.zip"
$file ="winizleyici.zip"
$output = $env:APPDATA+"\Aryasoft"
$destFile = $output+"\winizleyici.zip"

Set-ExecutionPolicy Bypass -Force -CurrentUser


function Install(){
    New-Item -ItemType Directory -Force -Path $output
    Download
    while($true)
    {
        if(test-path $destFile)
        {
            Expand-Archive $destFile -DestinationPath $output
            rm $destFile
            break
        }
    }

    cd $output
    .\winizleyici\install-service-filebeat.ps1
    Write-Host -BackgroundColor Green -ForegroundColor White "******************"
    Write-Host -BackgroundColor Green -ForegroundColor White "Install Completed"
    Write-Host -BackgroundColor Green -ForegroundColor White "******************"
}

function Download(){
    (New-Object System.Net.WebClient).DownloadFile($url, $destFile)
    Write-Host -BackgroundColor Green -ForegroundColor White "Download Completed"
}

function StartP(){
     cd $output
    .\winizleyici\saruman.exe
    #Start-Service filebeat
    Write-Host -BackgroundColor Green -ForegroundColor White "Started"
}

function Stop(){
    kill -Name saruman
    Stop-Service filebeat
    Write-Host -BackgroundColor Green -ForegroundColor Red "Stopped"
}


function Uninstall(){
    cd $output
    .\winizleyici\uninstall-service-filebeat.ps1 
    cd ..
    rm Aryasoft -Force -Recurse
    Write-Host -BackgroundColor Green -ForegroundColor Red "Uninstall Completed"
}


Install
StartP



#Stop
#Uninstall
