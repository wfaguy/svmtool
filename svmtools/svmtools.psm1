<#
.SYNOPSIS
    NetApp SVM Toolbox
.DESCRIPTION
    This module contains several functions to manage SVMDR, Backup and Restore Configuration...
.NOTES
    Author  : Olivier Masson, Jerome Blanchet, Mirko Van Colen
    Release : September 19th, 2018
#>

#############################################################################################
filter Skip-Null { $_|Where-Object{ $_ -ne $null } }

#############################################################################################
$Global:mutex=New-Object System.Threading.Mutex($False,"Global\LogMutex")
$Global:MOUNT_RETRY_COUNT = 100
$Global:VOLUME_TYPE="DP"
$Global:TEMPPASS="Netapp123!"

#############################################################################################
function free_mutexconsole{
    try{ 
        [void]$Global:mutexconsole.ReleaseMutex()
    }catch{
        Write-LogDebug "Failed to release mutexconsole"
    }    
}

#############################################################################################
function rotate_log {
	if( ( Test-Path $global:LOGFILE ) -eq $True )
	{
		$now=Get-Date
        $info=Get-Item $global:LOGFILE
        if($info.Length -gt $global:LOG_MAXSIZE){
            Rename-Item -Path $global:LOGFILE -NewName $($info.DirectoryName+"\"+$info.BaseName+$info.LastWriteTime.ToString("_yyyyMMdd_HHmmss")+".oldlog")
        }
        $listOldLog=Get-Item $($info.DirectoryName+"\"+$info.BaseName+"*.oldlog")
        foreach ($log in $listOldLog)
        {
            $date_log=$log.CreationTime
            #$now-$date_log
            if( ($now-$date_log).Days -gt $global:LOG_DAY2KEEP )
            {
                if($listOldLog.count -gt 1){
                    Remove-Item $log -Force -Confirm:$False
                }
            }
        }
	}
}

#############################################################################################
Function check_ToolkitVersion () {
	$ToolKitVersion = Get-NaToolkitVersion
	$Major = $ToolKitVersion.Major
	$Minor = $ToolKitVersion.Minor
	$Build = $ToolKitVersion.Build
	$Revision = $ToolKitVersion.Revision

	if( $Major -lt $Global:MIN_MAJOR ){
        Write-Host -Object "ERROR: Major = $Major Please upgrade NetApp TookKit Version to ${MIN_MAJOR}.${MIN_MINOR}.${MIN_BUILD}.${MIN_REVISION}" -ForegroundColor red
        exit 100
    }
    elseif($Minor -lt $Global:MIN_MINOR -and $Major -eq $Global:MIN_MAJOR){
        Write-Host "ERROR: Minor = $Minor Please upgrade NetApp TookKit Version to ${MIN_MAJOR}.${MIN_MINOR}.${MIN_BUILD}.${MIN_REVISION}" -ForegroundColor red
        exit 100    
    }
    elseif($Build -lt $MIN_BUILD -and $Major -eq $Global:MIN_MAJOR -and $Minor -eq $Global:MIN_MINOR){
        Write-Host "ERROR: Build = $Build Please upgrade NetApp TookKit Version to ${MIN_MAJOR}.${MIN_MINOR}.${MIN_BUILD}.${MIN_REVISION}" -ForegroundColor red
        exit 100    
    }
    elseif($Revision -lt $Global:MIN_REVISION -and $Major -eq $Global:MIN_MAJOR -and $Minor -eq $Global:MIN_MINOR -and $Build -eq $MIN_BUILD){
        Write-Host "ERROR: Revision = $Revision Please upgrade NetApp TookKit Version to ${MIN_MAJOR}.${MIN_MINOR}.${MIN_BUILD}.${MIN_REVISION}" -ForegroundColor red
        exit 100    
    }
}

#############################################################################################
Function clean_and_exit ([int]$return_code) { 
	if ( $DebugLevel -gt 0 )    { set_debug_level 0 }
	Write-LogOnly "svmtool TERMINATE by clean_and_exit`n"
        exit $return_code 
}

#############################################################################################
Function handle_error([object]$object,[string]$vserver){
	$ErrorMessage = $object.Exception.Message
	$FailedItem = $object.Exception.ItemName
	$Type = $object.Exception.GetType().FullName
	$CategoryInfo = $object.CategoryInfo
	$ErrorDetails = $object.ErrorDetails
	$Exception = $_.Exception
	$FullyQualifiedErrorId = $object.FullyQualifiedErrorId
	$InvocationInfoLine = $object.InvocationInfo.Line
	$InvocationInfoLineNumber = $object.InvocationInfo.ScriptLineNumber
	$PipelineIterationInfo = $object.PipelineIterationInfo
	$ScriptStackTrace = $object.ScriptStackTrace
	$TargetObject = $object.TargetObject
	Write-LogError  "Trap Error: [$vserver] [$ErrorMessage]"
	Write-LogDebug  "Trap Item: [$FailedItem]"
	Write-LogDebug  "Trap Type: [$Type]"
	Write-LogDebug  "Trap CategoryInfo: [$CategoryInfo]"
	Write-LogDebug  "Trap ErrorDetails: [$ErrorDetails]"
	Write-LogDebug  "Trap Exception: [$Exception]"
	Write-LogDebug  "Trap FullyQualifiedErrorId: [$FullyQualifiedErrorId]"
	Write-LogDebug  "Trap InvocationInfo: [$InvocationInfoLineNumber] [$InvocationInfoLine]"
	Write-LogDebug  "Trap PipelineIterationInfo: [$PipelineIterationInfo]"
	Write-LogDebug  "Trap ScriptStackTrace: [$ScriptStackTrace]"
	Write-LogDebug  "Trap TargetObject: [$TargetObject]"
}
#############################################################################################
function Format-ColorBrackets {
    Param(
        [Parameter(Position=0, Mandatory=$true)]
        [string] $Format,
        [switch] $FirstIsSpecial,
        [switch] $NoNewLine,
        [string] $ForceColor=""
    )
    if($Arguments -is [string]) {$Arguments = ,($Arguments)}

    $result = Select-String -Pattern '\[([^\]]*)\]' -InputObject $Format -AllMatches
    $i = 0
    $first = $true
    foreach($match in $result.Matches) {
        $group = $match.Groups[1]
        Write-Host -NoNewline $Format.Substring($i, $group.Index - $i)
        if(($first -and $FirstIsSpecial)){
            $color="green"
            $first=$false
        }else{
            $color="cyan"
        }
        if($ForceColor.length -gt 1){$color=$ForceColor}
        Write-Host $group.Value -NoNewline -ForegroundColor $color
        $i = $group.Index + $group.Length
    }
    if($i -lt $Format.Length){Write-Host -NoNewline $Format.Substring($i, $Format.Length - $i)}
    Write-Host "" -NoNewline:$NoNewLine
}
#############################################################################################
function Format-Colors {
    Param(
        [Parameter(Position=0, Mandatory=$true)]
        [string] $Format,
        [Parameter(Position=1)]
        [object] $Arguments,
        [switch] $NoNewLine
    )
    if($Arguments -is [string]) {$Arguments = ,($Arguments)}

    $result = Select-String -Pattern '\{(?:(\d+)(?::(\d|[0-9a-zA-Z]+))?)\}' -InputObject $Format -AllMatches
    $i = 0
    foreach($match in $result.Matches) {
        $group = $match.Captures[0]
        if(($i -eq 0) -and ($Format -match "^\[")){
            Format-ColorBrackets $Format.Substring($i, $group.Index - $i) -NoNewLine -FirstIsSpecial
        }else{
            Format-ColorBrackets $Format.Substring($i, $group.Index - $i) -NoNewLine
        }
        if($group.Groups[2].Success) {
            Write-Host -NoNewline -ForegroundColor $([System.ConsoleColor] $group.Groups[2].Value) $Arguments[$group.Groups[1].Value] 
        } else {
            $arg = $Arguments[[int]$group.Groups[1].Value]
            $value = $arg[0]
            $color = $arg[1]
            Write-Host -NoNewline -ForegroundColor $([System.ConsoleColor] $color) $value 
        }
        $i = $group.Index + $group.Length
    }
    if($i -lt $Format.Length){Format-ColorBrackets $Format.Substring($i, $Format.Length - $i) -NoNewline}
    Write-Host "" -NoNewline:$NoNewLine
}
#############################################################################################
Function Write-Help {
	Write-Host "use get-help svmtool.ps1 [-Full|-Examples|-Detailled|-Online]"
	Write-Host "`t`t"
	Write-Host "`t`t"
	clean_and_exit 0
}

#############################################################################################
function Write-LogDebug ([string]$mess, $type) {
		$logtime = get_timestamp
        Write-Debug "$mess"
        [void]$Global:mutex.WaitOne(200)
        if ( $NoLog -ne $True ) { Write "${logtime}: $mess" >> $global:LOGFILE }
        $Global:mutex.ReleaseMutex()
}

#############################################################################################
function Write-LogError ([string]$mess, $type) {
		$logtime = get_timestamp
        Write-Host "$mess" -F red
        [void]$Global:mutex.WaitOne(200)
        if ( $NoLog -ne $True ) { Write "${logtime}: $mess" >> $global:LOGFILE }
        $Global:mutex.ReleaseMutex()
}
#############################################################################################
function Write-LogWarn ([string]$mess, $type) {
		$logtime = get_timestamp
        #if ( $Silent -ne $True ) { Write-Host "$mess" }
        if ( $Silent -ne $True ) { Write-Warning "$mess" }
        [void]$Global:mutex.WaitOne(200)
        if ( $NoLog -ne $True ) { Write "${logtime}: $mess" >> $global:LOGFILE }
        $Global:mutex.ReleaseMutex()
}

#############################################################################################
function Write-Log ([string]$mess, $color,[switch]$colorvalues=$true,[switch]$firstValueIsSpecial) {
    #wait-debugger
    $logtime = get_timestamp
    if ( $Silent -ne $True ) { 
        if($color.count -eq 0){
            $color=(get-host).ui.rawui.ForegroundColor
        }
        if($color -eq -1){
            $color = "white"
        }
        if(-not $colorvalues){
            Write-Host "$mess" -ForegroundColor $color
        }else{
            if($mess -match "\[[^\]]*\]"){
                if($mess -match "^\["){
                    $firstValueIsSpecial = $true
                }
                Format-ColorBrackets -Format $mess -FirstIsSpecial:$firstValueIsSpecial
            }else{
                Write-Host "$mess" -ForegroundColor $color
            }
        }
    }
    [void]$Global:mutex.WaitOne(200)
    if ( $NoLog -ne $True ) { Write "${logtime}: $mess" >> $global:LOGFILE }
    $Global:mutex.ReleaseMutex()
}
#############################################################################################
function Write-LogOnly ([string]$mess, $type) {
    $logtime = get_timestamp
    [void]$Global:mutex.WaitOne(200)
    if ( $NoLog -ne $True ) { Write "${logtime}: $mess" >> $global:LOGFILE }
    $Global:mutex.ReleaseMutex()
}


#############################################################################################
function Read-HostDefault{
    Param(
        [Parameter(Position=0, Mandatory=$true)]
        [string] $question,
        [Parameter(Position=1)]
        [string] $default,
        [switch] $NotEmpty
    )

    do{
        Format-Colors -Format "$question [{0:Yellow}] : " -Arguments $default -NoNewLine
        $ans = Read-Host
        $return = if($ans -eq ""){$default}else{$ans}
    }until(([bool]$return) -or (-not $NotEmpty))
    return $return

}

#############################################################################################
function Read-HostOptions{
    Param(
        [Parameter(Position=0, Mandatory=$true)]
        [string] $question,
        [Parameter(Position=1, Mandatory=$true)]
        [string] $options,
        [string] $default
    )

    Format-Colors -Format "$question [{0:Yellow}] : " -Arguments $options -NoNewLine
    $optionlist = @($options -split "/")
    $ans = Read-Host
    while(-not ($optionlist -match $ans) -or ($ans -eq "") -or ($ans -eq $null)){
        Format-Colors "Please choose from [{0:Yellow}] : " -Arguments $options -NoNewLine
        $ans = Read-Host
    }

    return $ans
}

#############################################################################################
Function read_config_file ([string]$ConfigFile ) {

	[Hashtable]$read_vars = @{}

	$read_file = $ConfigFile	
	
        if (  ( Test-Path $read_file ) -eq $False ) {
		return $null
	}
	get-content -path $read_file | foreach-object {
                if ($_.Chars(0) -ne '#' ) {
			$key=$_.Substring(0, $_.IndexOf('='))
			$value=$_.Substring($_.IndexOf('=')+1)
			Write-LogDebug "read_config_file [$key] [$value]"
	
			if ($key.Contains("#")) {
				Write-LogDebug "read_config_file: comment: [$_]"
			} else {
				$read_vars.Add($key,$value)
			}
		}
	}
	return $read_vars	
}

#############################################################################################
Function create_config_file_cli () {
	if ((Test-Path $Global:CONFFILE) -eq $True ) {
		$read_conf = read_config_file $Global:CONFFILE
		if ( $read_conf -eq $null ){
        		Write-LogError "ERROR: read configuration file $Global:CONFFILE failed"
        		clean_and_exit 1 ;
		}
		$PRIMARY_CLUSTER=$read_conf.Get_Item("PRIMARY_CLUSTER")
		$SECONDARY_CLUSTER=$read_conf.Get_Item("SECONDARY_CLUSTER")
		$Global:SVMTOOL_DB=$read_conf.Get_Item("SVMTOOL_DB")
		$ANS=Read-HostOptions "Configuration file already exists. Do you want to recreate it ?" "y/n"
		if ( $ANS -ne 'y' ) { return }
	}
	$ANS='n'
	while ( $ANS -ne 'y' ) {

        $PRIMARY_CLUSTER = Read-HostDefault "Please Enter your default Primary Cluster Name" $PRIMARY_CLUSTER
        $SECONDARY_CLUSTER = Read-HostDefault "Please Enter your default Secondary Cluster Name" $SECONDARY_CLUSTER
		$Global:SVMTOOL_DB = Read-HostDefault "Please enter local DB directory where config files will be saved for this instance" $Global:SVMTOOL_DB
		Write-Log "Default Primary Cluster Name:        [$PRIMARY_CLUSTER]" 
		Write-Log "Default Secondary Cluster Name:      [$SECONDARY_CLUSTER]" 
		Write-Log "SVMTOOL Configuration DB directory:  [$Global:SVMTOOL_DB]" 
		Write-Log ""

        $ANS = Read-HostOptions "Apply new configuration ?" "y/n/q"
		if ( $ANS -eq 'q' ) { clean_and_exit 1 }

		write-Output "#" | Out-File -FilePath $Global:CONFFILE 
		write-Output "PRIMARY_CLUSTER=$PRIMARY_CLUSTER" | Out-File -FilePath $Global:CONFFILE -Append
		write-Output "SECONDARY_CLUSTER=$SECONDARY_CLUSTER" | Out-File -FilePath $Global:CONFFILE -Append
        write-Output "SVMTOOL_DB=$Global:SVMTOOL_DB" | Out-File -FilePath $Global:CONFFILE -Append
        write-output "INSTANCE_MODE=DR" | Out-File -FilePath $Global:CONFFILE -Append
        if ($PRIMARY_CLUSTER -eq $SECONDARY_CLUSTER) 
        { 
            $SINGLE_CLUSTER = $True
            Write-LogDebug "Detected SINGLE_CLUSTER Configuration"
        }
	}
}

#############################################################################################
Function create_vserver_config_file_cli (
	[string]$Vserver, 
	[string]$VserverDR, 
	[string]$ConfigFile)  {

	if ( $VserverDR ) {
		$myVserverDR=$VserverDR
	} 
    else {
	    if ((Test-Path $ConfigFile) -eq $True ) {
		    $read_conf = read_config_file $ConfigFile
		    if ( $read_conf -eq $null ){
        		    Write-Log "No configuration file for $Vserver "
		    }
		    $myVserverDR=$read_conf.Get_Item("VserverDR")
	    }
	    $ANS='n'
	    while ( $ANS -ne 'y' ) {
        	$myVserverDR = Read-HostDefault "Please Enter a Valid Vserver DR name for" $myVserverDR
        	$AnsQuotaDR = Read-HostOptions "Do you want to Backup Quota for $Vserver [$myVserverDR] ?" "y/n"
		    if ( $AnsQuotaDR -eq 'y' ) {
			    $AllowQuotaDR="true"
		    } else  {
			    $AllowQuotaDR="false"
		    }
		    if ( ( $Vserver -eq $myVserverDR ) -or ( $myVserverDR -eq "" ) -or ( $myVserverDR -eq $null ) ) {
		    $ANS = 'n' 
		    } else { 
			    Write-Log "Vserver DR Name :      [$myVserverDR]"
			    Write-Log "QuotaDR :              [$AllowQuotaDR]"
			    Write-Log ""
        		$ANS = Read-HostOptions "Apply new configuration ?" "y/n/q"
			    if ( $ANS -eq 'q' ) { clean_and_exit 1 }
		    }
	    }

	}
	write-Output "#" | Out-File -FilePath $ConfigFile
	write-Output "VserverDR=$myVserverDR" | Out-File -FilePath $ConfigFile -Append
	write-Output "AllowQuotaDR=$AllowQuotaDR" | Out-File -FilePath $ConfigFile -Append
}

#############################################################################################
Function set_debug_level ($debug_level) {
switch ( $debug_level ) {
        '0'     {
                $global:DebugPreference = "SilentlyContinue"
		        $global:ErrorAction = 0 
                }
        '1'     {
                Write-Host "Set Debug to Continue"
                $global:DebugPreference = "Continue"
		        $global:ErrorAction = 1 
                }
        '2'     {
                Write-Host "Set Debug to Inquire"
                $global:DebugPreference = "Inquire"
		        $global:ErrorAction = 1 
                }
        'show'  {
                Write-Host "DebugPreference: [${global:DebugPreference}]"
                }

        default {
                Write-Host "Set Debug to Default"
                $global:DebugPreference = "SilentlyContinue"
                }
        }
}

#############################################################################################
Function check_init_setup_dir() {
        if ( ( Test-Path $Global:BASEDIR -pathType container ) -eq $False ) {
                $out=new-item -Path $Global:BASEDIR -ItemType directory
                if ( ( Test-Path $Global:BASEDIR -pathType container ) -eq $False ) {
                        Write-LogError "ERROR: Unable to create new item $Global:BASEDIR"
                        return $False
                }
        }

        if ( ( Test-Path $Global:CONFDIR -pathType container ) -eq $False ) {
                $out=new-item -Path $Global:CONFDIR -ItemType directory
                if ( ( Test-Path $Global:CONFDIR -pathType container ) -eq $False ) {
                        Write-LogError "ERROR: Unable to create new item $Global:CONFDIR"
                        return $False
                }
        }
		
        if ( ( Test-Path $Global:LOGDIR -pathType container ) -eq $False ) {
                $out=new-item -Path $Global:LOGDIR -ItemType directory
                if ( ( Test-Path $Global:LOGDIR -pathType container ) -eq $False ) {
                        Write-LogError "ERROR: Unable to create new item $Global:LOGDIR"
                        return $False
                }
        }
		
		if ( ( Test-Path $Global:ROOTLOGDIR -pathType container ) -eq $False ) {
                $out=new-item -Path $Global:ROOTLOGDIR -ItemType directory
                if ( ( Test-Path $Global:ROOTLOGDIR -pathType container ) -eq $False ) {
                        Write-LogError "ERROR: Unable to create new item $Global:ROOTLOGDIR"
                        return $False
                }
        }
		
        if ( ( Test-Path $Global:CRED_CONFDIR -pathType container ) -eq $False ) {
                $out=new-item -Path $Global:CRED_CONFDIR -ItemType directory
                if ( ( Test-Path $Global:CRED_CONFDIR -pathType container ) -eq $False ) {
                        Write-LogError "ERROR: Unable to create new item $Global:CRED_CONFDIR"
                        return $False
                }
        }

}

#############################################################################################
Function import_instance_svmdr() {
    $svmdrCONFBASE="c:\Scripts\SVMDR\etc"
    $DirImport=Read-HostDefault "Please enter Directory from where to import SVMDR instances" $svmdrCONFBASE
    if ( ( Test-Path $DirImport -pathType container ) -eq $False ) 
    {
        Write-LogError "ERROR: Unable find new item $DirImport"
        return $False
    }
    $InstanceItemList=Get-ChildItem $DirImport
    $listCluster=@()
    foreach ( $InstanceItem in ( $InstanceItemList | Skip-Null ) ) {
        $Instance=$InstanceItem.Name
        $myConfDir = $Global:CONFBASEDIR + $Instance+ '\'
        $mySourceConfDir=$DirImport+ '\' + $Instance+ '\'
        Remove-Item $myConfDir -ErrorAction SilentlyContinue -Recurse -Confirm:$False -Force
        New-Item $myConfDir -ItemType "Directory"
        $mySourceConfFile=$mySourceConfDir+'svmdr.conf'
        $myDestConfFile=$myConfDir+'svmtool.conf'
        $read_conf = read_config_file $mySourceConfFile
        if ( $read_conf -ne $null )
        {
            $myPrimaryCluster=$read_conf.Get_Item("PRIMARY_CLUSTER")
            $mySecondaryCluster=$read_conf.Get_Item("SECONDARY_CLUSTER")
            $mySvmdrDB=$read_conf.Get_Item("SVMDR_DB")
            $myMode="DR"
            write-Output "#" | Out-File -FilePath $myDestConfFile
            write-Output "PRIMARY_CLUSTER=$myPrimaryCluster" | Out-File -FilePath $myDestConfFile -Append
            write-Output "SECONDARY_CLUSTER=$mySecondaryCluster" | Out-File -FilePath $myDestConfFile -Append
            write-Output "SVMTOOL_DB=$mySvmdrDB" | Out-File -FilePath $myDestConfFile -Append
            write-Output "INSTANCE_MODE=$myMode" | Out-File -FilePath $myDestConfFile -Append
        }
        $VserverItemList=Get-ChildItem $mySourceConfDir
        foreach ( $VserverItem in ( $VserverItemList | Skip-Null ) ) {
            $VserverFile = $VserverItem.Name
            $mySourceVserverFilePath=$mySourceConfDir+$VserverFile
            if ( $VserverFile -ne 'svmdr.conf' ) 
            {
                Copy-Item $mySourceVserverFilePath -Destination $myConfDir
            }
        } 
    }
    return $True
}

#############################################################################################
Function show_instance_list() {
    if ( ( Test-Path $Global:CONFBASEDIR -pathType container ) -eq $False ) 
    {
        Write-LogError "ERROR: Unable find new item $Global:CONFBASEDIR"
        return $False
    }

    Write-Log "CONFBASEDIR [$Global:CONFBASEDIR]`n"
    $InstanceItemList=Get-ChildItem $Global:CONFBASEDIR
    $listCluster=@()
    foreach ( $InstanceItem in ( $InstanceItemList | Skip-Null ) ) {
        $Instance=$InstanceItem.Name
        $myConfDir = $Global:CONFBASEDIR + $Instance + '\' 
        $myConfFile = $myConfDir + 'svmtool.conf'
        $read_conf = read_config_file $myConfFile
        if( $read_conf -eq $null){
            Write-LogWarn "Failed to read config file for instance [$Instance]"
        }
        if ( $read_conf -ne $null )
        {
            $myPrimaryCluster=$read_conf.Get_Item("PRIMARY_CLUSTER")
            $mySecondaryCluster=$read_conf.Get_Item("SECONDARY_CLUSTER")
            $mySvmdrDB=$read_conf.Get_Item("SVMTOOL_DB")
            $myMode=$read_conf.Get_Item("INSTANCE_MODE")
            $myBackupCluster=$read_conf.Get_Item("BACKUP_CLUSTER")
            if($myMode -eq "DR"){
                Write-Log "Instance [$Instance]: CLUSTER PRIMARY     [$myPrimaryCluster]" -firstValueIsSpecial
                Write-Log "Instance [$Instance]: CLUSTER SECONDARY   [$mySecondaryCluster]" -firstValueIsSpecial
                Write-Log "Instance [$Instance]: LOCAL DB            [$mySvmdrDB]" -firstValueIsSpecial
                Write-Log "Instance [$Instance]: INSTANCE MODE       [$myMode]" -firstValueIsSpecial
            }
            if($myMode -eq "BACKUP_RESTORE"){
                Write-Log "Instance [$Instance]: BACKUP CLUSTER      [$myBackupCluster]" -firstValueIsSpecial
                Write-Log "Instance [$Instance]: LOCAL DB            [$mySvmdrDB]" -firstValueIsSpecial
                Write-Log "Instance [$Instance]: INSTANCE MODE       [$myMode]"  -firstValueIsSpecial
            }
        }
        if($ResetPassword)
        {
            if(!$listCluster.Contains("$myPrimaryCluster")){$listCluster+=$myPrimaryCluster}
            if(!$listCluster.Contains("$mySecondaryCluster")){$listCluster+=$mySecondaryCluster}
        }
        if($myMode -eq "DR"){
            $VserverItemList=Get-ChildItem $myConfDir
            foreach ( $VserverItem in ( $VserverItemList | Skip-Null ) ) {
                $VserverFile = $VserverItem.Name
                if ( $VserverFile -ne 'svmtool.conf' ) 
                {
                    $myVconfFile = $myConfDir + $VserverFile
                    $read_vconf = read_config_file $myVconfFile
                    if ( $read_vconf -ne $null ) 
                    {
                        $myVserverDR=$read_vconf.Get_Item("VserverDR")
                        if ( $read_vconf -ne $null )
                        {
                            $myVserver=$VserverFile.Split('.')[0]
                            Write-Log "Instance [$Instance]: SVM DR Relation     [$myVserver -> $myVserverDR]"  -firstValueIsSpecial
                        }
                    }
                }
            }
        }
        Write-Log      
    }
    if($ResetPassword)
    {
        $excludeCDOTcred=@() 
        foreach ($cluster in ($listCluster | Skip-Null)){
            Write-LogDebug "Reset Credentials for $cluster"
            $out=get_local_cDotcred($cluster)
            $excludeCDOTcred+=$($cluster+".*")
        }
        $otherCredList=Get-ChildItem $Global:CRED_CONFDIR -Exclude $excludeCDOTcred -Filter "*cred"
        
        foreach( $otherCred in ($otherCredList | Skip-Null)){
            $ANS='n'
            $otherCredName=$otherCred.Name
            $otherCredName=$otherCredName.Replace(".cred","")
            $ANS=Read-HostOptions "Do you really want to reset Credentials for $otherCredName ?" "y/n"
            if ( $ANS -eq 'y')
            {
                Write-LogDebug "Reset Credential for $otherCredName"
                $out=get_local_cred($otherCredName)
            }
        }
    }
}
#############################################################################################
Function remove_configuration_instance( [string]$Instance ) {
Try {
	$Return = $True
	$myConfDir=$Global:CONFBASEDIR + $Instance + '\'
        if ( ( Test-Path $myConfDir -pathType container ) -eq $False ) {
		Write-LogError "ERROR: [$Instance] No such configuration, unable to delete"  -firstValueIsSpecial
		$Return = $false
	} else {
		$ANS = Read-HostOptions "Do you really want to remove this configuration instance [$Instance]" "y/n"
		if ( $ANS -eq 'y' ) {
			Write-LogDebug "Remove-Item -Recurse $myConfDir"
			Remove-Item -Recurse $myConfDir  -ErrorVariable ErrorVar
			if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Remove-Item [$myConfDir] failed [$ErrorVar]" }
		}
	}
	return $Return
}

Catch {
	handle_error $_
	return $False
}
}
#############################################################################################
Function get_timestamp {
        $timestamp= get-date -uformat "%Y_%m_%d %H:%M:%S"
        return $timestamp
}

#############################################################################################
Function get-epochdate ($epochdate) { 
	[timezone]::CurrentTimeZone.ToLocalTime(([datetime]'1/1/1970').AddSeconds($epochdate)) 
}

#############################################################################################
Function get-lag ($epochdate) {
	$Date1 = get-epochdate $epochdate
	$Date2 = Get-Date
	$CurrentLag = (New-TimeSpan -Start $Date1 -End $Date2).TotalSeconds
	return $currentLag
}

#############################################################################################
Function get_local_cred ([string]$myCredential) {

	# Manage Default cDOT Credentials
	Write-LogDebug "get_local_cred:  [$myCredential]"
	$Global:CRED_CONF_FILE=$Global:CRED_CONFDIR + $myCredential + '.cred'

	if ( $ResetPassword ) { 
        	$status = set_cred_from_cli $myCredential $Global:CRED_CONF_FILE
		if ( $status -eq $False ) {
			Write-LogError "ERROR: Unable to set your credentials for $myCredential Exit" 
        		clean_and_exit 1
		}
	}

	$cred=read_cred_from_file $Global:CRED_CONF_FILE
	if ( $cred -eq $null ) 
    {
        $status = set_cred_from_cli $myCredential $Global:CRED_CONF_FILE
		$cred=read_cred_from_file $Global:CRED_CONF_FILE
		if ( $cred -eq $null ) 
        {
			Write-LogError "ERROR: Unable to set your credentials for $myCredential Exit" 
        	clean_and_exit 1
		}
	}
	return $cred
}

#############################################################################################
Function set_cred_from_cli ([string]$myCredential, [string]$cred_file ) {
	Write-Log "Login for [$myCredential]"
	$login = Read-Host "[$myCredential] Enter login"
	$password = Read-Host "[$myCredential] Enter Password" -AsSecureString
	$cred =  New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $login,$password
		
	$save_password=$cred.Password | ConvertFrom-SecureString
	Write-Output "login=${login}" > $cred_file
	Write-Output "password=${save_password}" >> $cred_file
	return $true
}
#############################################################################################
Function connect_cluster (
	[string]$myController,
	[System.Management.Automation.PSCredential]$myCred,
	[Int32]$myTimeout) {

Try {

	#Write-LogDebug "Test-Connection -Count 1 -ComputerName $myController -Quiet"
	#if ( ( Test-Connection -Count 1 -ComputerName $myController -Quiet ) -eq $False ) {
	#	throw "ERROR: ICMP Test-Connection [$myController] failed [$ErrorVar]"
	#}
	$TimeoutMilliSeconds = $Timeout * 1000

	if ( $HTTP ) {
		Write-LogDebug "Connect-NcController $myController -Credential $myCred -HTTP -Timeout $TimeoutMilliSeconds"
		$NcController =  Connect-NcController $myController -Credential $myCred -HTTP -Timeout $TimeoutMilliSeconds  -ErrorVariable ErrorVar
	} else {
		Write-LogDebug "Connect-NcController $myController -Credential $myCred -HTTPS -Timeout $TimeoutMilliSeconds"
		$NcController =  Connect-NcController $myController -Credential $myCred -HTTPS -Timeout $TimeoutMilliSeconds  -ErrorVariable ErrorVar
	}
	if ( $? -ne $True ) { throw "ERROR: Connect-NcController failed [$ErrorVar]" }
	return $NcController 
}

Catch {
	handle_error $_ $myController
	return $false
}
}
#############################################################################################
Function set_cDotcred_from_cli ([string]$filer, [string]$cred_file ) {
Try {
        Write-Log "Login for cluster [$filer]"
        $login = Read-Host "Enter login"
        $password = Read-Host "password" -AsSecureString
        $cred =  New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $login,$password
        Write-LogDebug "connect_cluster -myController $filer -myCred $cred -myTimeout $Timeout"
        if ( ( $filer_connect=connect_cluster -myController $filer -myCred $cred -myTimeout $Timeout ) -eq $False ) {
                return $False
        } else {
                $save_password=$cred.Password | ConvertFrom-SecureString
                Write "login=${login}" > $cred_file
                Write "password=${save_password}" >> $cred_file
                Write "protocol=${protocol}" >> $cred_file
                return $true
	}
}
Catch {
	handle_error $_ $filer
	return $False
}
}

#############################################################################################
Function get_local_cDotcred ([string]$myCluster) {

	# Manage Default cDOT Credentials
	Write-LogDebug "get_cDOT_cred: Cluster: [$myCluster]"
	$Global:CRED_CONF_FILE=$Global:CRED_CONFDIR + $myCluster + '.cred'

	if ( $ResetPassword ) { 
        	$status = set_cDotcred_from_cli $myCluster $Global:CRED_CONF_FILE
		if ( $status -eq $False ) {
			Write-LogError "ERROR: Unable to set your credential for $myCluster Exit" 
        		clean_and_exit 1
		}
	}

	$cred=read_cred_from_file $Global:CRED_CONF_FILE
	if ( $cred -eq $null ) {
        	$status = set_cDotcred_from_cli $myCluster $Global:CRED_CONF_FILE
		$cred=read_cred_from_file $Global:CRED_CONF_FILE
		if ( $cred -eq $null ) {
			Write-LogError "ERROR: Unable to set your credential for $myCluster Exit" 
        		clean_and_exit 1
		}
	}
	return $cred
}


#############################################################################################
Function read_cred_from_file ([string]$cred_file) {
        [Hashtable]$read_vars = @{}

        if ((test-path $cred_file) -eq $False ) {
                Write-LogError "ERROR: no credential found for cluster" 
                return $null
        }
        get-content -path $cred_file | foreach-object {
                if ($_.Chars(0) -ne '#' ) {
                        $key, $value = $_ -split '='
                        Write-LogDebug "read_cred_from_file: [$key]"
                        $read_vars.Add($key,$value)
                }
        }
        $login=$read_vars.login
        if ($login -eq $null ) {
                Write-LogError "ERROR: login not found in $cred_file" 
                return $null
        }
        $password=$read_vars.password
        if ($password -eq $null ) {
                Write-LogError "ERROR: password not found in $cred_file" 
                return $null
        }
        $cred_password = $password | ConvertTo-SecureString
        $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $login,$cred_password
        return $cred
}

#############################################################################################
Function validate_ip_format (
	[string]$IpAddr, 
	[switch]$AllowNullIP ) {
Try {
	if ( ( $AllowNullIP -eq $True ) -and ( $IpAddr -eq "" ) ) { return $True }  
	[System.Net.IPAddress]$IpAddr | Out-Null
	return $True 
	}
Catch { 
	return $False 
	}
}

#############################################################################################
# $myIpAddr=ask_IpAddr_from_cli -myIpAddr $PrimaryAddress 
Function ask_IpAddr_from_cli ([string] $myIpAddr,[string] $workOn="") {
	$loop = $True
	While ( $loop -eq $True ) {
        #Wait-Debugger
		$AskIPAddr = Read-HostDefault "[$workOn] Please Enter a valid IP Address" $myIPAddr
		if ( ( validate_ip_format $AskIPAddr ) -eq $True ) {
				$loop = $False
				return $AskIPAddr
		}
	}
	return $AskIPAddr
}


#############################################################################################
Function ask_gateway_from_cli ([string]$myGateway,[string] $workOn="" ) {
	$loop = $True
	While ( $loop -eq $True ) {
        #Wait-Debugger
		$AskGateway = Read-HostDefault "[$workOn] Please Enter a valid Default Gateway Address" $myGateway
		if ( ( validate_ip_format -IpAddr $AskGateway -AllowNullIP ) -eq $True ) {
				$loop = $False
				return $AskGateway
		}
	}
	return $AskGateway
}

#############################################################################################
# $myNetMask=ask_NetMask_from_cli -myNetMask $PrimaryAddress
Function ask_NetMask_from_cli ([string]$myNetMask,[string] $workOn="" ) {
	$loop = $True
	While ( $loop -eq $True ) {
        #Wait-Debugger
		$AskNetMask = Read-HostDefault "[$workOn] Please Enter a valid IP NetMask" $myNetMask
		if ( ( validate_ip_format $AskNetMask ) -eq $True ) {
				$loop = $False
				return $AskNetMask
		}
	}
	return $AskNetMask
}

#############################################################################################
Function select_nodePort_from_cli ([NetApp.Ontapi.Filer.C.NcController]$myController, [string]$myNode, [string]$myQuestion,[string]$myDefault ) {
	$NodePortSelectedList = @()
 	$NodePortList=Get-NcNetPort -role data,node_mgmt -node $myNode  -Controller $myController  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNetPort failed [$ErrorVar]" }
	if ( $NodePortList -eq $null ) {
		Write-LogError "ERROR: Unable to list Ports for node $myNode $myController" 
		clean_and_exit 1
	}

	$i = 0 
	foreach ( $NodePort in ( $NodePortList | Skip-Null ) ) {
		$i++ 
		$tmpStr=$NodePort.Name
		$Link=$NodePort.LinkStatus
        $Role=$NodePort.Role
		$NodePortSelectedList += $tmpStr
		Write-Log "`t[$i] : [$NodePort] role [$Role] status [$Link]" -firstValueIsSpecial
	}

    # lets find the best default match from the list
    # lucky to have 1 on 1 ?
    $mySelectedDefault = ""
    if($NodePortSelectedList -match "$myDefault"){
        $mySelectedDefault = $myDefault
    }else{
        # no exact match - is it a vlan ?
        if($myDefault -match "[^-]+-([0-9]+)"){
            $myDefaultVlan=$Matches[1]
            # do we have a same vlan ?
            $similarVlans = ($NodePortSelectedList -match "[^-]+-$myDefaultVlan$")
            if($similarVlans){
                $mySelectedDefault=@($similarVlan)[0]
            }
        }
    }
    # still no vlan ?  Then map to a non data vlan
    if(-not $mySelectedDefault){
        $NonVlanDataPortList = @($NodePortList | ?{$_.Role = "data" -and $_.Name -notmatch "[^-]+-[0-9]+"})
        if($NonVlanDataPortList){
            $mySelectedDefault = $NonVlanDataPortList[0].Name
        }else{
            # no non-vlan data ports, lets try just non-vlan ports
            $NonVlanPortList = @($NodePortList | ?{$_.Name -notmatch "[^-]+-[0-9]+"})
            if($NonVlanPortList){
                $mySelectedDefault = $NonVlanPortList[0].Name
            }
        }
    }

    # get default index
    $myDefaultIndex = [array]::indexof($NodePortSelectedList,$mySelectedDefault)
    $myDefaultIndex++
    if($myDefaultIndex -eq 0){
        # non found, just pick the last
        $myDefaultIndex = $i
    }
	Write-Log "$myQuestion"
	$ErrNodePort = $True 
	while ( $ErrNodePort -eq $True ) {
		$ErrAns = $True 
		while ( $ErrAns -eq $True ) {
			$ans = Read-HostDefault "Select Port 1-$i" $myDefaultIndex
			if ($ans -eq "" ) { $ans = "$myDefaultIndex" }
			if ($ans -match  "^[0-9]" ) { 
				$ErrAns = $False
			}
		}
		$index=[int]$ans;$index --
        $NodePortSelected=$NodePortSelectedList[$index]
		
		if ( $NodePortSelected -ne $null ) { $ErrNodePort = $False }
	}
	return $NodePortSelected
}

#############################################################################################
Function select_node_from_cli ([NetApp.Ontapi.Filer.C.NcController]$myController, [string]$myQuestion ) {
	$NodeSelectedList = @()
 	$NodeList=Get-NcNode -Controller $myController  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNode failed [$ErrorVar]" }
	if ( $NodeList -eq $null ) {
		Write-LogError "ERROR: Unable to list nodes for Cluster $myController" 
		clean_and_exit 1
	}
	foreach ( $Node in ( $NodeList | Skip-Null ) ) {
		if ( $Node.IsNodeHealthy -eq $True ) {
			Write-LogDebug "select_node_from_cli: Select Node [$Node]"
			$tmpStr=$Node.Node
			$NodeSelectedList += $tmpStr
		}
	}
	$i = 0 
	Write-Log "$myQuestion"
	foreach ( $Node in ( $NodeSelectedList | Skip-Null ) ) {
		$i++ 
		Write-Log "`t[$i] : [$Node]" -firstValueIsSpecial
	}
	$ErrNode = $True 
	while ( $ErrNode -eq $True ) {
		$ErrAns = $True 
		while ( $ErrAns -eq $True ) {
			$ans = Read-HostDefault "Select Node 1-$i" $i
			if ($ans -match  "^[0-9]" ) { 
				$ErrAns = $False
			}
		}
		$index=[int]$ans ; $index --
		$NodeSelected=$NodeSelectedList[$index]
		if ( $NodeSelected -ne $null ) { $ErrNode = $False }
	}
	return $NodeSelected
}

#############################################################################################
Function select_data_aggr_from_cli ([NetApp.Ontapi.Filer.C.NcController]$myController, [string]$myQuestion ) {
    $ans='n'
    $ctrlName=$myController.Name
	while ( $ans -ne 'y') {	
        $AggrSelectedList = @()
        $template=Get-NcAggr -Controller $myController -Template
        Initialize-ncobjectproperty $template AggrRaidAttributes
        $template.AggrRaidAttributes.HasLocalRoot=$False
 		$AggrList=Get-NcAggr -Controller $myController -Query $template -ErrorVariable ErrorVar
		if ( $? -ne $True ) { 
            free_mutexconsole 
            throw "ERROR: Get-NcAggr failed [$ErrorVar]" }
		if ( $AggrList -eq $null ) {
            Write-LogError "ERROR: Unable list aggregates for Cluster $myController"
            free_mutexconsole
			clean_and_exit 1
        }
        if($AggrList.count -eq 1){
            $AggrSelected=$AggrList.Name
            $Size= [math]::round($AggrList.Available/1GB)
            Write-Log "[$ctrlName] only one Data Aggr available [$AggrSelected] with avail [$Size GB]"
            return $AggrSelected
        }
		$i = 0 
		Write-Log "$myQuestion"
		foreach ( $Aggr in ( $AggrList | Skip-Null ) ) {
			$i++ 
            $tmpStr=$Aggr.Name
            $Nodes=$Aggr.Nodes
            $Size= [math]::round($Aggr.Available/1GB)
            $AggrSelectedList += $tmpStr
            Write-Log "`t[$i] : [$Aggr]`t[$Nodes]`t[$Size GB]" -firstValueIsSpecial
		}
		if ( $i -eq 0 ) {
            Write-LogError "ERROR: Unable to find data aggregate for Cluster $myController" 
            free_mutexconsole
			clean_and_exit 1
		}
		$ErrAggr = $True 
		while ( $ErrAggr -eq $True ) {
			$ErrAns = $True 
			while ( $ErrAns -eq $True ) {
				$ans = Read-HostDefault "[$ctrlName] Select Aggr 1-$i" $i
				if ($ans -match  "^[0-9]" ) { 
					$ErrAns = $False
				}
			}
			$index=[int]$ans ; $index --
			$AggrSelected=$AggrSelectedList[$index]
			if ( $AggrSelected -ne $null ) { $ErrAggr = $False }
		}
		$ans=Read-HostOptions "[$ctrlName] You have selected the aggregate [$AggrSelected] ?" "y/n"
	}
	return $AggrSelected
}
#############################################################################################
# create_update_vscan_dr  
Function create_update_vscan_dr (
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [switch] $fromConfigureDR,
    [bool]$Backup,
    [bool]$Restore)
{
    Try 
    {
        $Return=$True
        Write-Log "[$workOn] Check SVM VSCAN configuration"
        Write-LogDebug "create_update_vscan_dr[$myPrimaryVserver]: start"
        if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
        if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}

        if($Restore -eq $False){
            Write-logDebug "Get-NcVscanScannerPool -VserverContext $myPrimaryVserver -Controller $myPrimaryController"
            $PrimaryScannerPoolList=Get-NcVscanScannerPool -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar 
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVscanScannerPool failed on [$myPrimaryController] [$ErrorVar]" }
        }else{
            if(Test-Path $($Global:JsonPath+"Get-NcVscanScannerPool.json")){
                $PrimaryScannerPoolList=Get-Content $($Global:JsonPath+"Get-NcVscanScannerPool.json") | ConvertFrom-Json
            }else{
                $Return=$False
                $filepath=$($Global:JsonPath+"Get-NcVscanScannerPool.json")
                Throw "ERROR: failed to read $filepath"
            }    
        }
        if($Backup -eq $True){
            $PrimaryScannerPoolList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcVscanScannerPool.json") -Encoding ASCII -Width 65535
            if( ($ret=get-item $($Global:JsonPath+"Get-NcVscanScannerPool.json") -ErrorAction SilentlyContinue) -ne $null ){
                Write-LogDebug "$($Global:JsonPath+"Get-NcVscanScannerPool.json") saved successfully"
            }else{
                Write-LogError "ERROR: Failed to save $($Global:JsonPath+"Get-NcVscanScannerPool.json")"
                $Return=$False
            }
        }
        if($Backup -eq $False){
            foreach ( $PrimaryScannerPool in ( $PrimaryScannerPoolList | Skip-Null ) ) {
                $PrimaryScannerPoolName=$PrimaryScannerPool.ScannerPool
                $PrimaryScannerPoolPolicy=$PrimaryScannerPool.ScannerPolicy
                $PrimaryScannerPoolVscanServers=$PrimaryScannerPool.Servers
                $PrimaryScannerPoolPrivUser=$PrimaryScannerPool.PrivilegedUsers
                $PrimaryScannerPoolReqTimeout=$PrimaryScannerPool.RequestTimeout
                $PrimaryScannerPoolScanQueueTimeout=$PrimaryScannerPool.ScanQueueTimeout
                $PrimaryScannerPoolSesSetupTimeout=$PrimaryScannerPool.SessionSetupTimeout
                $PrimaryScannerPoolSesTeardTimeout=$PrimaryScannerPool.SessionTeardownTimeout
                $PrimaryScannerPoolMaxSesSetupRetry=$PrimaryScannerPool.MaxSessionSetupRetries
                
                Write-logDebug "Get-NcVscanScannerPool -Name $PrimaryScannerPoolName -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                $SecondaryScannerPool = Get-NcVscanScannerPool -Name $PrimaryScannerPoolName -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVscanScannerPool failed on [$mySecondaryController] [$ErrorVar]" }
                if ( $SecondaryScannerPool -ne $null ) 
                {
                    $SecondaryScannerPoolVscanServers=$SecondaryScannerPool.Servers
                    $SecondaryScannerPoolPolicy=$SecondaryScannerPool.ScannerPolicy
                    $SecondaryScannerPoolPrivUser=$SecondaryScannerPool.PrivilegedUsers
                    $SecondaryScannerPoolReqTimeout=$SecondaryScannerPool.RequestTimeout
                    $SecondaryScannerPoolScanQueueTimeout=$SecondaryScannerPool.ScanQueueTimeout
                    $SecondaryScannerPoolSesSetupTimeout=$SecondaryScannerPool.SessionSetupTimeout
                    $SecondaryScannerPoolSesTeardTimeout=$SecondaryScannerPool.SessionTeardownTimeout
                    $SecondaryScannerPoolMaxSesSetupRetry=$SecondaryScannerPool.MaxSessionSetupRetries
                    if ( (($PrimaryScannerPoolPrivUser -ne $SecondaryScannerPoolPrivUser) `
                        -or ($PrimaryScannerPoolReqTimeout -ne $SecondaryScannerPoolReqTimeout) `
                        -or ($PrimaryScannerPoolPolicy -ne $SecondaryScannerPoolPolicy) `
                        -or ($PrimaryScannerPoolScanQueueTimeout -ne $SecondaryScannerPoolScanQueueTimeout) `
                        -or ($PrimaryScannerPoolSesSetupTimeout -ne $SecondaryScannerPoolSesSetupTimeout) `
                        -or ($PrimaryScannerPoolSesTeardTimeout -ne $SecondaryScannerPoolSesTeardTimeout) `
                        -or ($PrimaryScannerPoolMaxSesSetupRetry -ne $SecondaryScannerPoolMaxSesSetupRetry)) ) 
                    {
                        Write-Log "[$workOn] Modify Vscan Scanner Pool [$PrimaryScannerPoolName]"
                        if($fromConfigureDR -eq $True)
                        {
                            try {
                                $global:mutexconsole.WaitOne(200) | Out-Null
                            }
                            catch [System.Threading.AbandonedMutexException]{
                                #AbandonedMutexException means another thread exit without releasing the mutex, and this thread has acquired the mutext, therefore, it can be ignored
                                Write-Host -f Red "catch abandoned mutex for [$myPrimaryVserver]"
                                free_mutexconsole
                            }
                            Write-Log "[$workOn] Enter IP Address of a Vscan Server"
                            $ANS='y'
                            $num=(($SecondaryScannerPoolVscanServers.count)-1)
                            if($num -ge 0)
                            {
                                $myScannerPoolVscanServers=$SecondaryScannerPoolVscanServers   
                            }
                            else
                            {
                                $myScannerPoolVscanServers=$PrimaryScannerPoolVscanServers    
                            }
                            while($ANS -ne 'n')
                            {
                                $SecondaryScannerPoolVscanServers+=ask_IpAddr_from_cli -myIpAddr $myScannerPoolVscanServers[$num++] -workOn $workOn
                                $ANS=Read-HostOptions "[$workOn] Do you want to add another Scan Server ?" "y/n"
                            }
                            Write-LogDebug "Set-NcVscanScannerPool -Name $PrimaryScannerPoolName -ScannerPolicy $PrimaryScannerPoolPolicy -VscanServer $SecondaryScannerPoolVscanServers -RequestTimeout $PrimaryScannerPoolReqTimeout -ScanQueueTimeout $PrimaryScannerPoolScanQueueTimeout -SessionSetupTimeout $PrimaryScannerPoolSesSetupTimeout -SessionTeardownTimeout $PrimaryScannerPoolSesTeardTimeout -MaxSessionSetupRetries $PrimaryScannerPoolMaxSesSetupRetry -PrivilegedUser $PrimaryScannerPoolPrivUser -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                            $out=Set-NcVscanScannerPool -Name $PrimaryScannerPoolName -ScannerPolicy $PrimaryScannerPoolPolicy -VscanServer $SecondaryScannerPoolVscanServers -RequestTimeout $PrimaryScannerPoolReqTimeout -ScanQueueTimeout $PrimaryScannerPoolScanQueueTimeout -SessionSetupTimeout $PrimaryScannerPoolSesSetupTimeout -SessionTeardownTimeout $PrimaryScannerPoolSesTeardTimeout -MaxSessionSetupRetries $PrimaryScannerPoolMaxSesSetupRetry -PrivilegedUser $PrimaryScannerPoolPrivUser -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { 
                                $Return = $False
                                free_mutexconsole
                                throw "ERROR: Set-NcVscanScannerPool failed [$ErrorVar]" }
                                free_mutexconsole
                        }
                        else
                        {
                            Write-LogDebug "Set-NcVscanScannerPool -Name $PrimaryScannerPoolName -ScannerPolicy $PrimaryScannerPoolPolicy -RequestTimeout $PrimaryScannerPoolReqTimeout -ScanQueueTimeout $PrimaryScannerPoolScanQueueTimeout -SessionSetupTimeout $PrimaryScannerPoolSesSetupTimeout -SessionTeardownTimeout $PrimaryScannerPoolSesTeardTimeout -MaxSessionSetupRetries $PrimaryScannerPoolMaxSesSetupRetry -PrivilegedUser $PrimaryScannerPoolPrivUser -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                            $out=Set-NcVscanScannerPool -Name $PrimaryScannerPoolName -ScannerPolicy $PrimaryScannerPoolPolicy -RequestTimeout $PrimaryScannerPoolReqTimeout -ScanQueueTimeout $PrimaryScannerPoolScanQueueTimeout -SessionSetupTimeout $PrimaryScannerPoolSesSetupTimeout -SessionTeardownTimeout $PrimaryScannerPoolSesTeardTimeout -MaxSessionSetupRetries $PrimaryScannerPoolMaxSesSetupRetry -PrivilegedUser $PrimaryScannerPoolPrivUser -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcVscanScannerPool failed [$ErrorVar]" }
                        }
                    }
                } 
                else 
                {
                    try {
                        $global:mutexconsole.WaitOne(200) | Out-Null
                    }
                    catch [System.Threading.AbandonedMutexException]{
                        #AbandonedMutexException means another thread exit without releasing the mutex, and this thread has acquired the mutext, therefore, it can be ignored
                        Write-Host -f Red "catch abandoned mutex for [$myPrimaryVserver]"
                        free_mutexconsole
                    }
                    Write-Log "[$workOn] Create Vscan Scanner Pool [$PrimaryScannerPoolName]"
                    Write-Log "[$workOn] Enter IP Address of a Vscan Server"
                    $ANS='y'
                    $SecondaryScannerPoolVscanServers=@()
                    $num=0
                    while($ANS -ne 'n')
                    {
                        $SecondaryScannerPoolVscanServers+=ask_IpAddr_from_cli -myIpAddr $PrimaryScannerPoolVscanServers[$num++] -workOn $workOn
                        $ANS=Read-HostOptions "[$workOn] Do you want to add another Scan Server ?" "y/n"
                    }
                    Write-LogDebug "New-NcVscanScannerPool -Name $PrimaryScannerPoolName -RequestTimeout $PrimaryScannerPoolReqTimeout -ScanQueueTimeout $PrimaryScannerPoolScanQueueTimeout -SessionSetupTimeout $PrimaryScannerPoolSesSetupTimeout -SessionTeardownTimeout $PrimaryScannerPoolSesTeardTimeout -MaxSessionSetupRetries $PrimaryScannerPoolMaxSesSetupRetry -VscanServer $SecondaryScannerPoolVscanServers -PrivilegedUser $PrimaryScannerPoolPrivUser -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                    $out=New-NcVscanScannerPool -Name $PrimaryScannerPoolName -RequestTimeout $PrimaryScannerPoolReqTimeout -ScanQueueTimeout $PrimaryScannerPoolScanQueueTimeout -SessionSetupTimeout $PrimaryScannerPoolSesSetupTimeout -SessionTeardownTimeout $PrimaryScannerPoolSesTeardTimeout -MaxSessionSetupRetries $PrimaryScannerPoolMaxSesSetupRetry -VscanServer $SecondaryScannerPoolVscanServers -PrivilegedUser $PrimaryScannerPoolPrivUser -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ;free_mutexconsole; throw "ERROR: New-NcVscanScannerPool failed [$ErrorVar]" }
                    Write-LogDebug "Set-NcVscanScannerPool -Name $PrimaryScannerPoolName -ScannerPolicy $PrimaryScannerPoolPolicy -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                    $out=Set-NcVscanScannerPool -Name $PrimaryScannerPoolName -ScannerPolicy $PrimaryScannerPoolPolicy -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ;free_mutexconsole; throw "ERROR: Set-NcVscanScannerPool failed [$ErrorVar]" }
                    free_mutexconsole
                }
            }
        }
        if($PrimaryScannerPoolList -ne $Null)
        {
            # add OnAccessPolicy Code
            if($Restore -eq $False){
                Write-logDebug "Get-NcVscanOnAccessPolicy -VserverContext $myPrimaryVserver -Controller $myPrimaryController"
                $PrimaryOnAccessPolicyList=Get-NcVscanOnAccessPolicy -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar 
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVscanOnAccessPolicy failed on [$myPrimaryController] [$ErrorVar]" }
            }else{
                if(Test-Path $($Global:JsonPath+"Get-NcVscanOnAccessPolicy.json")){
                    $PrimaryOnAccessPolicyList=Get-Content $($Global:JsonPath+"Get-NcVscanOnAccessPolicy.json") | ConvertFrom-Json
                }else{
                    $Return=$False
                    $filepath=$($Global:JsonPath+"Get-NcVscanOnAccessPolicy.json")
                    Throw "ERROR: failed to read $filepath"
                }
            }
            if($Backup -eq $True){
                $PrimaryOnAccessPolicyList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcVscanOnAccessPolicy.json") -Encoding ASCII -Width 65535
                if( ($ret=get-item $($Global:JsonPath+"Get-NcVscanOnAccessPolicy.json") -ErrorAction SilentlyContinue) -ne $null ){
                    Write-LogDebug "$($Global:JsonPath+"Get-NcVscanOnAccessPolicy.json") saved successfully"
                }else{
                    Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcVscanOnAccessPolicy.json")"
                    $Return=$False
                }
            }
            if($Backup -eq $False){
                foreach ( $PrimaryOnAccessPolicy in ( $PrimaryOnAccessPolicyList | Skip-Null ) ) {
                    $PrimaryOnAccessPolicyName=$PrimaryOnAccessPolicy.PolicyName
                    $PrimaryOnAccessPolicyEnabled=$PrimaryOnAccessPolicy.IsPolicyEnabled
                    $PrimaryOnAccessPolicyFileExtToExclude=$PrimaryOnAccessPolicy.FileExtToExclude
                    $PrimaryOnAccessPolicyFileExtToExclude_str=[string]$PrimaryOnAccessPolicyFileExtToExclude
                    $PrimaryOnAccessPolicyFilters=$PrimaryOnAccessPolicy.Filters
                    $PrimaryOnAccessPolicyFilters_str=[string]$PrimaryOnAccessPolicyFilters
                    $PrimaryOnAccessPolicyProtocol=$PrimaryOnAccessPolicy.Protocol
                    $PrimaryOnAccessPolicyMaxFileSize=$PrimaryOnAccessPolicy.MaxFileSize
                    $PrimaryOnAccessPolicyExcludePath=$PrimaryOnAccessPolicy.PathsToExclude
                    $PrimaryOnAccessPolicyFileExcludePath_str=[string]$PrimaryOnAccessPolicyExcludePath

                    Write-logDebug "Get-NcVscanOnAccessPolicy -Name $PrimaryOnAccessPolicyName -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                    $SecondaryOnAccessPolicy = Get-NcVscanOnAccessPolicy -Name $PrimaryOnAccessPolicyName -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVscanOnAccessPolicy failed on [$mySecondaryController] [$ErrorVar]" }
                    if ( $SecondaryOnAccessPolicy -ne $null ) 
                    {
                        $SecondaryOnAccessPolicyEnabled=$SecondaryOnAccessPolicy.IsPolicyEnabled
                        $SecondaryOnAccessPolicyFileExtToExclude=$SecondaryOnAccessPolicy.FileExtToExclude
                        $SecondaryOnAccessPolicyFileExtToExclude_str=[string]$SecondaryOnAccessPolicyFileExtToExclude
                        $SecondaryOnAccessPolicyFilters=$SecondaryOnAccessPolicy.Filters
                        $SecondaryOnAccessPolicyFilters_str=[string]$SecondaryOnAccessPolicyFilters
                        $SecondaryOnAccessPolicyMaxFileSize=$SecondaryOnAccessPolicy.MaxFileSize
                        $SecondaryOnAccessPolicyExcludePath=$SecondaryOnAccessPolicy.PathsToExclude
                        $SecondaryOnAccessPolicyExcludePath_str=[string]$SecondaryOnAccessPolicyExcludePath
                        
                        if ( (($PrimaryOnAccessPolicyFilters_str -ne $SecondaryOnAccessPolicyFilters_str) `
                            -and (($PrimaryOnAccessPolicyFilters -ne $null) -and ($SecondaryOnAccessPolicyFilters -ne $null))) `
                            -or ($PrimaryOnAccessPolicyMaxFileSize -ne $SecondaryOnAccessPolicyMaxFileSize) `
                            -or (($PrimaryOnAccessPolicyExcludePath_str -ne $SecondaryOnAccessPolicyExcludePath_str) `
                            -and (($PrimaryOnAccessPolicyExcludePath -ne $null) -and ($SecondaryOnAccessPolicyExcludePath -ne $null))) `
                            -or (($PrimaryOnAccessPolicyFileExtToExclude_str -ne $SecondaryOnAccessPolicyFileExtToExclude_str) `
                            -and (($PrimaryOnAccessPolicyFileExtToExclude -ne $null) -and ($SecondaryOnAccessPolicyFileExtToExclude -ne $null))) )
                            #-or ($PrimaryOnAccessPolicyProtocol -ne $SecondaryOnAccessPolicyProtocol) ` 
                        {
                            if($PrimaryOnAccessPolicyFilters.count -eq 0 ){$PrimaryOnAccessPolicyFilters+="-"}
                            Write-Log "[$workOn] Modify VscanOnAccessPolicy [$PrimaryOnAccessPolicyName]"
                            Write-LogDebug "Set-NcVscanOnAccessPolicy -Name $PrimaryOnAccessPolicyName -Filter $PrimaryOnAccessPolicyFilters -MaxFileSize $PrimaryOnAccessPolicyMaxFileSize -ExcludePath $PrimaryOnAccessPolicyExcludePath -ExcludeExtension $PrimaryOnAccessPolicyFileExtToExclude -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar"
                            $out=Set-NcVscanOnAccessPolicy -Name $PrimaryOnAccessPolicyName `
                            -Filter $PrimaryOnAccessPolicyFilters `
                            -MaxFileSize $PrimaryOnAccessPolicyMaxFileSize `
                            -ExcludePath $PrimaryOnAccessPolicyExcludePath `
                            -ExcludeExtension $PrimaryOnAccessPolicyFileExtToExclude `
                            -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcVscanOnAccessPolicy failed [$ErrorVar]" }
                        }
                    } 
                    else 
                    {
                        if($PrimaryOnAccessPolicyFilters.count -eq 0 ){$PrimaryOnAccessPolicyFilters+="-"}
                        Write-Log "[$workOn] Create Vscan OnAccess Policy [$PrimaryOnAccessPolicyName]"
                        Write-LogDebug "New-NcVscanOnAccessPolicy -Name $PrimaryOnAccessPolicyName `
                        -Protocol $PrimaryOnAccessPolicyProtocol `
                        -Filter $PrimaryOnAccessPolicyFilters `
                        -MaxFileSize $PrimaryOnAccessPolicyMaxFileSize `
                        -ExcludePath $PrimaryOnAccessPolicyExcludePath `
                        -ExcludeExtension $PrimaryOnAccessPolicyFileExtToExclude `
                        -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                        $out=New-NcVscanOnAccessPolicy -Name $PrimaryOnAccessPolicyName `
                        -Protocol $PrimaryOnAccessPolicyProtocol `
                        -Filter $PrimaryOnAccessPolicyFilters `
                        -MaxFileSize $PrimaryOnAccessPolicyMaxFileSize `
                        -ExcludePath $PrimaryOnAccessPolicyExcludePath `
                        -ExcludeExtension $PrimaryOnAccessPolicyFileExtToExclude `
                        -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcVscanOnAccessPolicy failed [$ErrorVar]" }
                        $SecondaryOnAccessPolicyEnabled=$False
                    }
                    if($PrimaryOnAccessPolicyEnabled -ne  $SecondaryOnAccessPolicyEnabled)
                    {
                        if($PrimaryOnAccessPolicyEnabled -eq $True)
                        {
                            $template=Get-NcVscanOnAccessPolicy -Template -Controller $mySecondaryController
                            $template.IsPolicyEnabled=$True
                            Write-LogDebug "Get-NcVscanOnAccessPolicy -Query $template -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                            $policyEnabled=Get-NcVscanOnAccessPolicy -Query $template -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if($? -ne $True) { $Return = $False ; throw "ERROR: Failed to get enabled policy [$ErrorVar]" }
                            if($policyEnabled -ne $null)
                            {
                                $policyEnabledName=$policyEnabled.PolicyName
                                Write-LogDebug "Disable-NcVscanOnAccessPolicy -Name $policyEnabledName -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                                $out=Disable-NcVscanOnAccessPolicy -Name $policyEnabledName -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Disable-NcScanOnAccessPolicy failed [$ErrorVar]" }
                            }
                            
                            Write-logDebug "Enable-NcScanOnAccessPolicy -Name $PrimaryOnAccessPolicyName -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                            $out=Enable-NcVscanOnAccessPolicy -Name $PrimaryOnAccessPolicyName -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Enable-NcScanOnAccessPolicy failed [$ErrorVar]" }  
                        }
                        else
                        {
                            Write-logDebug "Disable-NcScanOnAccessPolicy -Name $PrimaryOnAccessPolicyName -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                            $out=Disable-NcVscanOnAccessPolicy -Name $PrimaryOnAccessPolicyName -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Disable-NcScanOnAccessPolicy failed [$ErrorVar]" }
                        }
                    } 
                }
            }
            if($Restore -eq $False){
                Write-logDebug "Get-NcVscanStatus -Vserver $myPrimaryVserver -Controller $myPrimaryController"
                $PrimaryVscan=Get-NcVscanStatus -Vserver $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVscanStatus failed [$ErrorVar]" }
            }else{
                if(Test-Path $($Global:JsonPath+"Get-NcVscanStatus.json")){
                    $PrimaryVscan=Get-Content $($Global:JsonPath+"Get-NcVscanStatus.json") | ConvertFrom-Json
                }else{
                    $Return=$False
                    $filepath=$($Global:JsonPath+"Get-NcVscanStatus.json")
                    Throw "ERROR: failed to read $filepath"
                }
            }
            if($Backup -eq $True){
                $PrimaryVscan | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcVscanStatus.json") -Encoding ASCII -Width 65535
                if( ($ret=get-item $($Global:JsonPath+"Get-NcVscanStatus.json") -ErrorAction SilentlyContinue) -ne $null ){
                    Write-LogDebug "$($Global:JsonPath+"Get-NcVscanStatus.json") saved successfully"
                }else{
                    Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcVscanStatus.json")"
                    $Return=$False
                }
            }
            if($Backup -eq $False){
                Write-logDebug "Get-NcVscanStatus -Vserver $mySecondaryVserver -Controller $mySecondaryController"
                $SecondaryVscan=Get-NcVscanStatus -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVscanStatus failed [$ErrorVar]" }
                if ($PrimaryVscan.Enabled -ne $SecondaryVscan.Enabled)
                {
                    if($PrimaryVscan.Enabled -eq $True)
                    {
                        Write-logDebug "Enable-NcVscan -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                        $out=Enable-NcVscan -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Enable-NcVscan failed [$ErrorVar]" }
                    }
                    else
                    {
                        Write-logDebug "Disable-NcVscan -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                        $out=Disable-NcVscan -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Disable-NcVscan failed [$ErrorVar]" }
                    }
                }
            }
        }      

        Write-LogDebug "create_update_vscan_dr[$myPrimaryVserver]: end"
        return $Return
    }
    catch
    {
        handle_error $_ $myPrimaryVserver
	    return $Return        
    }
}

#############################################################################################
# create_update_firewallpolicy_dr
Function create_update_firewallpolicy_dr(
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) 
{
    Try 
    {
        $Return=$True
        Write-Log "[$workOn] Check SVM Firewall Policy"
        Write-LogDebug "create_update_firewallpolicy_dr[$myPrimaryVserver]: start"
        if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
        if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}

        if($Restore -eq $False -and $Backup -eq $False){
            $mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar).ClusterName 
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }
        }
        if($Restore -eq $False){
            $PrimaryFirewallPolicies=Get-NcNetFirewallPolicy -Controller $myPrimaryController -Vserver $myPrimaryVserver  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNetFirewallPolicy failed [$ErrorVar]" }
        }else{
            if(Test-Path $($Global:JsonPath+"Get-NcNetFirewallPolicy.json")){
                $PrimaryFirewallPolicies=Get-Content $($Global:JsonPath+"Get-NcNetFirewallPolicy.json") | ConvertFrom-Json
            }else{
                $Return=$False
                $filepath=$($Global:JsonPath+"Get-NcNetFirewallPolicy.json")
                Throw "ERROR: failed to read $filepath"
            }    
        }
        if($Backup -eq $True){
            $PrimaryFirewallPolicies | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcNetFirewallPolicy.json") -Encoding ASCII -Width 65535
            if( ($ret=get-item $($Global:JsonPath+"Get-NcNetFirewallPolicy.json") -ErrorAction SilentlyContinue) -ne $null ){
                Write-LogDebug "$($Global:JsonPath+"Get-NcNetFirewallPolicy.json") saved successfully"
            }else{
                Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcNetFirewallPolicy.json")"
                $Return=$False
            }    
        }
        if($Backup -eq $False){
            $SecondaryFirewallPolices=Get-NcNetFirewallPolicy -Controller $mySecondaryController -Vserver $mySecondaryVserver  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNetFirewallPolicy failed [$ErrorVar]" }
            if(($SecondaryFirewallPolices.count) -gt 0){
                $differences=Compare-Object -ReferenceObject $PrimaryFirewallPolicies -DifferenceObject $SecondaryFirewallPolices -Property Policy,Service,AllowList | Sort-Object -Property SideIndicator -Descending
                foreach($diff in $differences){
                    $Policy=$diff.Policy
                    $Service=$diff.Service
                    $AllowList=$diff.AllowList
                    if($diff.SideIndicator -eq "=>"){
                        Write-Log "[$workOn] Delete Firewall Rule : [$Policy] [$Service] [$AllowList]"
                        Write-LogDebug "Remove-NcNetFirewallPolicy -Name $Policy -Vserver $mySecondaryVserver -Service $Service -AllowAddress $AllowList -Controller $mySecondaryCluster"
                        $out=Remove-NcNetFirewallPolicy -Name $Policy -Vserver $mySecondaryVserver -Service $Service -AllowAddress $AllowList -Controller $mySecondaryController  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Remove-NcNetFirewallPolicy failed [$ErrorVar]"  }
                    }elseif($diff.SideIndicator -eq "<="){
                        Write-Log "[$workOn] Create this Firewall Rule : [$Policy] [$Service] [$AllowList]"
                        $out=New-NcNetFirewallPolicy -Name $Policy -Vserver $mySecondaryVserver -Service $Service -AllowAddress $AllowList -Controller $mySecondaryController  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcNetFirewallPolicy failed [$ErrorVar]"  }
                    }
                }
            }else{
                foreach($FirPol in $PrimaryFirewallPolicies){
                    $Policy=$FirPol.Policy
                    $Service=$FirPol.Service
                    $AllowList=$FirPol.AllowList
                    Write-Log "[$workOn] Create Firewall Rule : [$Policy] [$Service] [$AllowList]"
                    $out=New-NcNetFirewallPolicy -Name $Policy -Vserver $mySecondaryVserver -Service $Service -AllowAddress $AllowList -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcNetFirewallPolicy failed [$ErrorVar]"  }
                }
            }
        }
        Write-LogDebug "create_update_firewallpolicy_dr[$myPrimaryVserver]: end"
        return $Return
    }
    catch
    {
        handle_error $_ $myPrimaryVserver
	    return $false        
    }
}

#############################################################################################
# create_update_usermapping_dr
Function get_vserver_clone(
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $DestinationVserver) 
{
    Try 
    {
        $Return=$True
        $SelectedCloneList=@()
        Write-LogDebug "get_vserver_clone[$mySecondaryController]: start"
        $cloneSearchName=$($DestinationVserver+"_clone.*")
        Write-LogDebug "Get-NcVserver -Controller $mySecondaryController -Query @{VserverType=`"data`";State=`"running`";VserverSubtype=`"default|sync_source`";VserverName=$cloneSearchName}"
        $ListClonedVserver=Get-NcVserver -Controller $mySecondaryController -Query @{VserverType="data";State="running";VserverSubtype="default|sync_source";VserverName=$cloneSearchName} -ErrorVariable ErrorVar
        if($? -ne $True ) { Write-LogDebug "ERROR: Get-NcVserver failed [$ErrorVar]"; return $null }
        foreach($ClonedVserver in $ListClonedVserver){
            $VserverCloneName=$ClonedVserver.VserverName
            $listVol=Get-NcVol -Query @{Vserver=$VserverCloneName;VolumeStateAttributes=@{IsVserverRoot=$False}} -controller $mySecondaryController
            $listClonedVserver=Get-NcVol -Query @{Vserver=$VserverCloneName;VolumeStateAttributes=@{IsVserverRoot=$False}} -controller $mySecondaryController| where-object {$_.VolumeCloneAttributes.VolumeCloneParentAttributes.Name -ne $null}
            $countVol=$listVol.count
            $countClone=$listclonedVserver.count
            if($DebugLevel){Write-LogDebug "countVol [$countVol] countClone [$countClone]"}
            if($countVol -eq $countClone){
                Write-LogDebug "Vserver [$VserverCloneName] is a Vserver Clone"
                $SelectedCloneList+=$VserverCloneName
            }
        }
        Write-LogDebug "get_vserver_clone[$mySecondaryController]: end"
        return $SelectedCloneList
    }
    catch
    {
        handle_error $_ $DestinationVserver
	    return $false        
    }
}

#############################################################################################
# create_update_usermapping_dr
Function create_update_usermapping_dr(
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) 
{
    Try 
    {
        $Return=$True
        Write-LogDebug "create_update_usermapping_dr[$myPrimaryVserver]: start"
        if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
        if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}
        
        Write-Log "[$workOn] Check User Mapping"
        if($Restore -eq $False){
            Write-LogDebug "Get-NcNameMapping -VserverContext $myPrimaryVserver -Controller $myPrimaryController"
            $PrimaryMapping=Get-NcNameMapping -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNameMapping failed [$ErrorVar]" }
        }else{
            if(Test-Path $($Global:JsonPath+"Get-NcNameMapping.json")){
                $PrimaryMapping=Get-Content $($Global:JsonPath+"Get-NcNameMapping.json") | ConvertFrom-Json
            }else{
                $Return=$False
                $filepath=$($Global:JsonPath+"Get-NcNameMapping.json")
                Throw "ERROR: failed to read $filepath"
            }    
        }
        if($Backup -eq $True){
            $PrimaryMapping | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcNameMapping.json") -Encoding ASCII -Width 65535
            if( ($ret=get-item $($Global:JsonPath+"Get-NcNameMapping.json") -ErrorAction SilentlyContinue) -ne $null ){
                Write-LogDebug "$($Global:JsonPath+"Get-NcNameMapping.json") saved successfully"
            }else{
                Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcNameMapping.json")"
                $Return=$False
            }
        }
        if($Backup -eq $False){
            foreach($Mapping in $PrimaryMapping | Sort-Object -Property Position){
                $MappingAddress=$Mapping.Address
                $MappingDirection=$Mapping.Direction
                $MappingHostname=$Mapping.Hostname
                $MappingPattern=$Mapping.Pattern
                $MappingPosition=$Mapping.Position
                $MappingReplacement=$Mapping.Replacement
                $template=Get-NcNameMapping -Template -Controller $mySecondaryController  -ErrorVariable ErrorVar
                $template.Vserver=$mySecondaryVserver
                $template.Pattern=$MappingPattern
                $template.Direction=$MappingDirection
                Write-LogDebug "Get-NcNameMapping -Query $template -Controller $mySecondaryController"
                $SecondaryMapping=Get-NcNameMapping -Query $template -Controller $mySecondaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNameMapping failed [$ErrorVar]" }
                if($SecondaryMapping.count -eq 0){
                    Write-Log "[$workOn] Add new User Mapping entry [$MappingDirection] [$MappingPosition] [$MappingPattern] [$MappingReplacement] [$MappingAddress] [$MappingHostname] on [$mySecondaryVserver]"
                    Write-LogDebug "New-NcNameMapping -Direction $MappingDirection -Position $MappingPosition -Pattern $MappingPattern -Replacement $MappingReplacement -Address $MappingAddress -Hostname $MappingHostname -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                    $out=New-NcNameMapping -Direction $MappingDirection -Position $MappingPosition -Pattern $MappingPattern -Replacement $MappingReplacement -Address $MappingAddress -Hostname $MappingHostname -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcNameMapping failed [$ErrorVar]" }
                }else{
                    $SecondaryMappingAddress=$SecondaryMapping.Address
                    $SecondaryMappingDirection=$SecondaryMapping.Direction
                    $SecondaryMappingHostname=$SecondaryMapping.Hostname
                    $SecondaryMappingPattern=$SecondaryMapping.Pattern
                    $SecondaryMappingPosition=$SecondaryMapping.Position
                    $SecondaryMappingReplacement=$SecondaryMapping.Replacement
                    if( ($SecondaryMappingAddress -ne $MappingAddress) -or ($SecondaryMappingDirection -ne $MappingDirection) -or ($SecondaryMappingHostname -ne $MappingHostname) `
                    -or ($SecondaryMappingPattern -ne $MappingPattern) -or ($SecondaryMappingPosition -ne $MappingPosition) -or ($SecondaryMappingReplacement -ne $MappingReplacement) ){
                        Write-LogDebug "Difference detected"
                        Write-LogDebug "Remove-NcNameMapping -Direction $SecondaryMappingDirection -Position $SecondaryMappingPosition -Confirm:$flase -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                        $out=Remove-NcNameMapping -Direction $SecondaryMappingDirection -Position $SecondaryMappingPosition -Confirm:$flase -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar    
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Remove-NcNameMapping failed [$ErrorVar]" }
                        Write-LogDebug "New-NcNameMapping -Direction $MappingDirection -Position $MappingPosition -Pattern $MappingPattern -Replacement $MappingReplacement -Address $MappingAddress -Hostname $MappingHostname -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                        $out=New-NcNameMapping -Direction $MappingDirection -Position $MappingPosition -Pattern $MappingPattern -Replacement $MappingReplacement -Address $MappingAddress -Hostname $MappingHostname -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcNameMapping failed [$ErrorVar]" } 
                    }   
                }
            }
        }
        Write-LogDebug "create_update_usermapping_dr[$myPrimaryVserver]: end"
        return $Return
    }
    catch
    {
        handle_error $_ $myPrimaryVserver
        return $Return        
    }
}

#############################################################################################
# create_update_localuser_dr
Function create_update_localuser_dr(
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) 
{
    Try 
    {
        $Return=$True
        Write-Log "[$workOn] Check SVM Users"
        Write-LogDebug "create_update_localuser_dr[$myPrimaryVserver]: start"
        if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
        if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}

        if($Restore -eq $False){
            Write-LogDebug "Get-NcUser -Controller $myPrimaryController -Vserver $myPrimaryVserver"
            $PrimaryUsers=Get-NcUser -Controller $myPrimaryController -Vserver $myPrimaryVserver  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR : Get-NcUser failed [$ErrorVar]" }
        }else{
            if(Test-Path $($Global:JsonPath+"Get-NcUser.json")){
                $PrimaryUsers=Get-Content $($Global:JsonPath+"Get-NcUser.json") | ConvertFrom-Json
            }else{
                $Return=$False
                $filepath=$($Global:JsonPath+"Get-NcUser.json")
                Throw "ERROR: failed to read $filepath"
            }    
        }
        if($Backup -eq $True){
            $PrimaryUsers | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcUser.json") -Encoding ASCII -Width 65535
            if( ($ret=get-item $($Global:JsonPath+"Get-NcUser.json") -ErrorAction SilentlyContinue) -ne $null ){
                Write-LogDebug "$($Global:JsonPath+"Get-NcUser.json") saved successfully"
            }else{
                Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcUser.json")"
                $Return=$False
            }
        }else{
            try {
                $global:mutexconsole.WaitOne(200) | Out-Null
            }
            catch [System.Threading.AbandonedMutexException]{
                #AbandonedMutexException means another thread exit without releasing the mutex, and this thread has acquired the mutext, therefore, it can be ignored
                Write-Host -f Red "catch abandoned mutex for [$myPrimaryVserver]"
                free_mutexconsole
            }
            Write-LogDebug "Get-NcUser -Controller $mySecondaryController -Vserver $mySecondaryVserver"
            $SecondaryUsers=Get-NcUser -Controller $mySecondaryController -Vserver $mySecondaryVserver  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR : Get-NcUser failed [$ErrorVar]" ;free_mutexconsole}
            if(($SecondaryUsers.count) -gt 0){
                $differences=Compare-Object -ReferenceObject $PrimaryUsers -DifferenceObject $SecondaryUsers -Property UserName,Application,AuthMethod,RoleName,IsLocked | Sort-Object -Property SideIndicator -Descending
                $PasswordEntered=@()
                foreach($user in $differences | where-object {$_.UserName -notin @("vsadmin","vsadmin-protocol","vsadmin-readonly","vsadmin-volume","vsadmin-backup","vsadmin-snaplock")}){
                    $Username=$user.UserName
                    $Application=$user.Application
                    $Authmet=$user.AuthMethod
                    $Rolename=$user.RoleName
                    $Islocked=$user.IsLocked
                    if($user.SideIndicator -eq "=>"){
                        Write-Log "[$workOn] Remove user [$Username] [$Application] [$Authmet] [$Rolename] [$Islocked] from [$mySecondaryVserver]"
                        Write-LogDebug "Remove-NcUser -UserName $Username -Vserver $mySecondaryVserver -Application $Application -AuthMethod $Authmet -Controller $mySecondaryController"
                        $out=Remove-NcUser -UserName $Username -Vserver $mySecondaryVserver -Application $Application -AuthMethod $Authmet -Controller $mySecondaryController  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR : Remove-NcUser failed [$ErrorVar]" ;free_mutexconsole}
                    }elseif($user.SideIndicator -eq "<="){
                        Write-Log "[$workOn] Add user [$Username] [$Application] [$Authmet] [$Rolename] [$Islocked]"
                        #Write-LogDebug "New-NcUser -UserName $Username -Vserver $mySecondaryVserver -Application $Application -AuthMethod $Authmet -Controller $mySecondaryController"
                        if($Authmet -eq "password" -and $Username -notin $PasswordEntered){
                            $passwordIsGood=$False
                            do{ 
                                Write-Log "[$workOn] user [$Username]"
                                if($Global:DefaultPass -eq $True){
                                    $passwordIsGood=$True
                                    $pwd1_text=$Global:TEMPPASS
                                    Write-Log "[$workOn] Set default password for user [$UserName]. User will have to change it at first login"   
                                }else{
                                    do{
                                        $ReEnter=$false
                                        $pass1=Read-Host "[$workOn] Please Enter Password for [$Username]" -AsSecureString
                                        $pass2=Read-Host "[$workOn] Confirm Password for [$Username]" -AsSecureString
                                        $pwd1_text = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass1))
                                        $pwd2_text = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass2))
        
                                        if ($pwd1_text -ceq $pwd2_text) {
                                            Write-LogDebug "Passwords matched"
                                        } 
                                        else{
                                            Write-Warning "[$workOn] Error passwords does not match. Please Re-Enter"
                                            $ReEnter=$True
                                        }
                                    }while($ReEnter -eq $True)
                                }
                                $password=$pwd1_text
                                Write-LogDebug "New-NcUser -UserName $Username -Role $Rolename -Vserver $mySecondaryVserver -Application $Application -AuthMethod $Authmet -Password xxxxxxxx -Controller $mySecondaryController"
                                $out=New-NcUser -UserName $Username -Role $Rolename -Vserver $mySecondaryVserver -Application $Application -AuthMethod $Authmet -Password $password -Controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { 
                                    if($ErrorVar -match "New password must be different than the old password"){
                                        Write-Warning "[$workOn] Password will not be changed`nPassword entered is already in use for user [$UserName]"
                                        $passwordIsGood=$True
                                    }elseif($ErrorVar -match "Minimum length for new password"){
                                        Write-Warning "[$workOn] $ErrorVar"
                                    }elseif($ErrorVar -match "New password must have both letters and numbers"){
                                        Write-Warning "[$workOn] $ErrorVar"
                                    }elseif($ErrorVar -match "Password does not conform to filer conventions"){
                                        Write-Warning "[$workOn] $ErrorVar"
                                    }else{
                                        throw "ERROR : Set-NcUserPassword failed on [$mySecondaryVserver] reason [$ErrorVar]"
                                        free_mutexconsole
                                    }
                                }else{
                                    $passwordIsGood=$True
                                    $PasswordEntered+=$Username
                                }
                            }while($passwordIsGood -eq $False)
                            if($Global:DefaultPass -eq $True){
                                Write-LogDebug "Invoke-NcSecurityLoginExpirePassword -Vserver $mySecondaryVserver -UserName $Username -Controller $mySecondaryController"
                                $ret=Invoke-NcSecurityLoginExpirePassword -Vserver $mySecondaryVserver -UserName $Username -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False    
                                if ( $? -ne $True ) {Write-LogDebug "Failed to expire [$Username] password"}
                            }
                        }else{
                            Write-LogDebug "New-NcUser -UserName $Username -Role $Rolename -Vserver $mySecondaryVserver -Application $Application -AuthMethod $Authmet -Controller $mySecondaryController"
                            $out=New-NcUser -UserName $Username -Role $Rolename -Vserver $mySecondaryVserver -Application $Application -AuthMethod $Authmet -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR : Get-NcUser failed [$ErrorVar]" ;free_mutexconsole}
                        }
                        if($Authmet -match "usm|publickey"){
                            Write-Log "[$workOn] With [usm or publickey] Authentication Method you need to finish user configuration direcly in ONTAP with CLI"
                        }   
                    }
                }
            }else{
                $PasswordEntered=@()
                foreach($user in $PrimaryUsers){
                    $Username=$user.UserName
                    $Application=$user.Application
                    $Authmet=$user.AuthMethod
                    $Rolename=$user.RoleName
                    $Islocked=$user.IsLocked
                    Write-Log "[$workOn] Add user [$Username] [$Application] [$Authmet] [$Rolename] [$Islocked]"
                    if($Authmet -eq "password" -and $Username -notin $PasswordEntered){ 
                        $passwordIsGood=$False
                        do{
                            Write-Log "[$workOn] user [$Username]"
                            if($Global:DefaultPass -eq $True){
                                $passwordIsGood=$True
                                $pwd1_text=$Global:TEMPPASS
                                Write-Log "[$workOn] Set default password for user [$UserName]. User will have to change it at first login"   
                            }else{
                                do{
                                    $ReEnter=$false
                                    $pass1=Read-Host "[$workOn] Please enter Password for [$Username]" -AsSecureString
                                    $pass2=Read-Host "[$workOn] Confirm Password for [$Username]" -AsSecureString
                                    $pwd1_text = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass1))
                                    $pwd2_text = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass2))

                                    if ($pwd1_text -ceq $pwd2_text) {
                                        Write-LogDebug "Passwords matched"
                                    } 
                                    else{
                                        Write-Warning "[$workOn] Error passwords do not match. Please Re-Enter"
                                        $ReEnter=$True
                                    }
                                }while($ReEnter -eq $True)
                            }
                            $password=$pwd1_text
                            Write-LogDebug "New-NcUser -UserName $Username -Role $Rolename -Vserver $mySecondaryVserver -Application $Application -AuthMethod $Authmet -Password xxxxxxxx -Controller $mySecondaryController"
                            $out=New-NcUser -UserName $Username -Role $Rolename -Vserver $mySecondaryVserver -Application $Application -AuthMethod $Authmet -Password $password -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { 
                                if($ErrorVar -match "New password must be different than the old password"){
                                    Write-Warning "[$workOn] Password will not be changed`nPassword entered is already in use for user [$UserName]"
                                    $passwordIsGood=$True
                                }elseif($ErrorVar -match "Minimum length for new password"){
                                    Write-Warning "[$workOn] $ErrorVar"
                                }elseif($ErrorVar -match "New password must have both letters and numbers"){
                                    Write-Warning "[$workOn] $ErrorVar"
                                }elseif($ErrorVar -match "Password does not conform to filer conventions"){
                                    Write-Warning "[$workOn] $ErrorVar"
                                }else{
                                    throw "ERROR : Set-NcUserPassword failed on [$mySecondaryVserver] reason [$ErrorVar]"
                                    free_mutexconsole
                                }
                            }else{
                                $passwordIsGood=$True
                                $PasswordEntered+=$Username
                            }
                        }while($passwordIsGood -eq $False)    
                    }else{
                        Write-LogDebug "New-NcUser -UserName $Username -Role $Rolename -Vserver $mySecondaryVserver -Application $Application -AuthMethod $Authmet -Controller $mySecondaryController"
                        $out=New-NcUser -UserName $Username -Role $Rolename -Vserver $mySecondaryVserver -Application $Application -AuthMethod $Authmet -Controller $mySecondaryController  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ;free_mutexconsole; throw "ERROR : New-NcUser failed [$ErrorVar]" }
                    }
                    if($Authmet -match "usm|publickey"){
                        Write-Log "[$workOn] With that kind of Authentication Method you need to finish user configuration direcly in ONTAP, with CLI"
                    }
                }
            }
            Write-LogDebug "Check Factory User unlocked"
            $user=$PrimaryUsers | where-object {$_.UserName -in @("vsadmin") -and $_.Islocked -eq $False} | Sort-Object -Unique
            Write-LogDebug "user found = [$user]"
            if($user -eq $null){
                Write-LogDebug "No Factory user unlocked to create on destination"
            }else{
                $userName=$User.UserName
                if($DebugLevel){Write-LogDebug "Check user [$userName] on [$mySecondaryVserver]"}
                $secUser=$SecondaryUsers | Where-Object {$_.UserName -eq $UserName -and $_.Islocked -eq $False}
                if($secUser -eq $null){
                    if($DebugLevel){Write-LogDebug "Need to unlock user [$userName] on [$mySecondaryVserver]"}
                    $passwordIsGood=$False
                    do{
                        Write-Log "[$workOn] user [$userName]"
                        if($Global:DefaultPass -eq $True){
                            $passwordIsGood=$True
                            $pwd1_text=$Global:TEMPPASS
                            Write-Log "[$workOn] Set default password for user [$UserName]. User will have to change it at first login"   
                        }else{
                            do{
                                $ReEnter=$false
                                $pass1=Read-Host "[$workOn] Please enter Password for [$userName]" -AsSecureString
                                $pass2=Read-Host "[$workOn] Confirm Password for [$userName]" -AsSecureString
                                $pwd1_text = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass1))
                                $pwd2_text = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass2))
                                if ($pwd1_text -ceq $pwd2_text) {
                                    Write-LogDebug "Passwords match for [$UserName]"
                                } 
                                else{
                                    Write-Warning "[$workOn] Error passwords do not match for [$UserName]. Please Re-Enter"
                                    Write-LogDebug "Error passwords do not match for user [$UserName]. Please Re-Enter"
                                    $ReEnter=$True
                                }
                            }while($ReEnter -eq $True)
                        }
                        $password=$pwd1_text
                        if($DebugLevel){Write-LogDebug "Set-NcUserPassword -UserName $userName -VserverContext $mySecondaryVserver -Password xxxxxxx -Controller $mySecondaryController"}
                        $out=Set-NcUserPassword -UserName $userName -VserverContext $mySecondaryVserver -Password $password -Controller $mySecondaryController -ErrorVariable ErrorVar
                        if($? -ne $true){
                            if($ErrorVar -match "New password must be different than the old password"){
                                Write-Warning "[$workOn] Password will not be changed`nPassword entered is already in use for user [$userName]"
                                Write-LogDebug "Password will not be changed`nPassword entered is already in use for user [$UserName]"
                                $passwordIsGood=$True
                            }elseif($ErrorVar -match "Minimum length for new password"){
                                Write-Warning "[$workOn] $ErrorVar"
                                Write-LogDebug "[$workOn] Minimum length for new password"
                            }elseif($ErrorVar -match "New password must have both letters and numbers"){
                                Write-Warning "[$workOn] $ErrorVar"
                                Write-LogDebug "[$workOn] New password must have both letters and numbers"
                            }else{
                                free_mutexconsole
                                throw "ERROR : Set-NcUserPassword failed on [$mySecondaryVserver] reason [$ErrorVar]"
                            }
                        }else{
                            $passwordIsGood=$True
                        }
                    }while($passwordIsGood -eq $False)
                    if($DebugLevel){Write-LogDebug "Unlock-NcUser -UserName $userName -Vserver $mySecondaryVserver -Controller $mySecondaryController"}
                    $out=Unlock-NcUser -UserName $userName -Vserver $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErrorVar -Confirm:$False
                    if ( $? -ne $True ) { $Return = $False ;free_mutexconsole; throw "ERROR : Unlock-NcUser failed on [$mySecondaryVserver] reason [$ErrorVar]" }  
                }
                free_mutexconsole
            }
        }
        Write-LogDebug "create_update_localuser_dr[$myPrimaryVserver]: end"
        return $Return
    }
    catch
    {
        handle_error $_ $myPrimaryVserver
	    return $Return        
    }
}

#############################################################################################
# create_update_localunixgroupanduser_dr
Function create_update_localunixgroupanduser_dr(
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) 
{
    Try 
    {
        $Return=$True
        Write-Log "[$workOn] Check SVM Name Mapping"
        Write-LogDebug "create_update_localunixgroupanduser_dr[$myPrimaryVserver]: start"
        if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
        if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}
        
        Write-Log "[$workOn] Check Local Unix User"
        if($Restore -eq $False){
            Write-LogOnly "Get-NcNameMappingUnixUser -VserverContext $myPrimaryVserver -Controller $myPrimaryController"
            $PrimaryUserList=Get-NcNameMappingUnixUser -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
        }else{
            if(Test-Path $($Global:JsonPath+"Get-NcNameMappingUnixUser.json")){
                $PrimaryUserList=Get-Content $($Global:JsonPath+"Get-NcNameMappingUnixUser.json") | ConvertFrom-Json
            }else{
                $Return=$False
                $filepath=$($Global:JsonPath+"Get-NcNameMappingUnixUser.json")
                Throw "ERROR: failed to read $filepath"
            }
        }
        if($Backup -eq $True){
            $PrimaryUserList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcNameMappingUnixUser.json") -Encoding ASCII -Width 65535
            if( ($ret=get-item $($Global:JsonPath+"Get-NcNameMappingUnixUser.json") -ErrorAction SilentlyContinue) -ne $null ){
                Write-LogDebug "$($Global:JsonPath+"Get-NcNameMappingUnixUser.json") saved successfully"
            }else{
                Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcNameMappingUnixUser.json")"
                $Return=$False
            }
        }
        if($Backup -eq $False){
            foreach($PrimaryUser in $PrimaryUserList){
                $UserFullName=$PrimaryUser.FullName
                $UserGroupId=$PrimaryUser.GroupId
                $UserId=$PrimaryUser.UserId
                $UserName=$PrimaryUser.UserName
                $template=Get-NcNameMappingUnixUser -Template -Controller $mySecondaryController
                #$template.UserId=$UserId
                #$template.GroupId=$UserGroupId
                $template.UserName=$UserName
                $template.Vserver=$mySecondaryVserver
                Write-LogDebug "Get-NcNameMappingUnixUser -Query $template -Controller $mySecondaryController"
                $SecondaryUser=Get-NcNameMappingUnixUser -Query $template -Controller $mySecondaryController  -ErrorVariable ErrorVar
                if($? -ne $True){$Return = $False; throw "ERROR : Get-NcNameMappingUnixUser [$ErrorVar]"}
                if($SecondaryUser.count -eq 0){
                    Write-Log "[$workOn] Create Local Unix User [$UserName] [$UserId] [$UserGroupId] [$UserFullName] on [$mySecondaryVserver]"
                    Write-LogDebug "New-NcNameMappingUnixUser -Name $UserName -UserId $UserId -GroupId $UserGroupId -FullName $UserFullName -SkipNameValidation -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                    $out=New-NcNameMappingUnixUser -Name $UserName -UserId $UserId -GroupId $UserGroupId -FullName $UserFullName -Confirm:$false -SkipNameValidation -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if($? -ne $True){$Return = $False; throw "ERROR : New-NcNameMappingUnixUser [$ErrorVar]"}
                }else{
                    Write-Log "[$workOn] Modify Local Unix User [$UserName] [$UserId] [$UserGroupId] [$UserFullName] on [$mySecondaryVserver]"
                    Write-LogDebug "Set-NcNameMappingUnixUser -Name $UserName -UserId $UserId -GroupId $UserGroupId -FullName $UserFullName -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                    $out=Set-NcNameMappingUnixUser -Name $UserName -UserId $UserId -GroupId $UserGroupId -FullName $UserFullName -Confirm:$false -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if($? -ne $True){$Return = $False; throw "ERROR : New-NcNameMappingUnixUser [$ErrorVar]"}
                }
            }
        }
        Write-Log "[$workOn] Check Local Unix Group"
        if($Restore -eq $False){
            Write-LogOnly "Get-NcNameMappingUnixGroup -VserverContext $myPrimaryVserver -Controller $myPrimaryController"
            $PrimaryGroupList=Get-NcNameMappingUnixGroup -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
        }else{
            if(Test-Path $($Global:JsonPath+"Get-NcNameMappingUnixGroup.json")){
                $PrimaryGroupList=Get-Content $($Global:JsonPath+"Get-NcNameMappingUnixGroup.json") | ConvertFrom-Json
            }else{
                $Return=$False
                $filepath=$($Global:JsonPath+"Get-NcNameMappingUnixGroup.json")
                Throw "ERROR: failed to read $filepath"
            }
        }
        if($Backup -eq $True){
            $PrimaryGroupList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcNameMappingUnixGroup.json") -Encoding ASCII -Width 65535
            if( ($ret=get-item $($Global:JsonPath+"Get-NcNameMappingUnixGroup.json") -ErrorAction SilentlyContinue) -ne $null ){
                Write-LogDebug "$($Global:JsonPath+"Get-NcNameMappingUnixGroup.json") saved successfully"
            }else{
                Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcNameMappingUnixGroup.json")"
                $Return=$False
            }
        }
        if($Backup -eq $False){
            foreach($PrimaryGroup in $PrimaryGroupList){
                $GroupName=$PrimaryGroup.GroupName
                $GroupId=$PrimaryGroup.GroupId
                $GroupUsers=$PrimaryGroup.Users | Sort-Object
                $GroupUser_string=$GroupUsers.UserName | Out-String
                $template=Get-NcNameMappingUnixGroup -Template -Controller $mySecondaryController
                #$template.GroupId=$GroupId
                $template.GroupName=$GroupName
                $template.Vserver=$mySecondaryVserver
                Write-LogDebug "Get-NcNameMappingUnixGroup -Query $template -Controller $mySecondaryController"
                $SecondaryGroup=Get-NcNameMappingUnixGroup -Query $template -Controller $mySecondaryController  -ErrorVariable ErrorVar
                if($? -ne $True){$Return = $False; throw "ERROR : Get-NcNameMappingUnixGroup [$ErrorVar]"}
                if($SecondaryGroup.count -eq 0){
                    Write-Log "[$workOn] Create Local Unix Group [$GroupName] [$GroupId] [$GroupUser_string] on [$mySecondaryVserver]"
                    $out=New-NcNameMappingUnixGroup -Name $GroupName -GroupId $GroupId -SkipNameValidation -Confirm:$false -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if($? -ne $True){$Return = $False; throw "ERROR : New-NcNameMappingUnixGroup [$ErrorVar]"} 
                    foreach($usertoadd in $GroupUsers){
                        $UserName=$usertoadd.UserName
                        Write-Log "[$workOn] Add User [$UserName] into Group [$GroupName] on [$mySecondaryVserver]"
                        Write-LogDebug "Add-NcNameMappingUnixGroupUser -Name $GroupName -UserName $UserName -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                        $out=Add-NcNameMappingUnixGroupUser -Name $GroupName -UserName $UserName -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                        if($? -ne $True){$Return = $False; throw "ERROR : Add-NcNameMappingUnixGroupUser [$ErrorVar]"} 
                    }
                }else{
                    $SecondaryGroupUsers=$SecondaryGroup.Users | Sort-Object
                    if(($GroupUsers.count -gt 0) -and ($SecondaryGroupUsers.count -gt 0)){
                        $Differences=Compare-Object -ReferenceObject $GroupUsers -DifferenceObject $SecondaryGroupUsers -Property UserName | Sort-Object -Property SideIndicator -Descending
                        foreach($Diff in $Differences){
                            if($Diff.SideIndicator -eq "=>"){
                                $UserToRemove=$Diff.UserName
                                Write-Log "[$workOn] Remove User [$UserToRemove] from Group [$GroupName] on [$mySecondaryVserver]"
                                Write-LogDebug "Remove-NcNameMappingUnixGroupUser -Name $GroupName -UserName $UserToRemove -VserverContext $mySecondaryVserver -Confirm:$false -Controller $mySecondaryController"
                                $out=Remove-NcNameMappingUnixGroupUser -Name $GroupName -UserName $UserToRemove -VserverContext $mySecondaryVserver -Confirm:$false -Controller $mySecondaryController  -ErrorVariable ErrorVar 
                                if($? -ne $True){$Return = $False; throw "ERROR : Remove-NcNameMappingUnixGroupUser [$ErrorVar]"}   
                            }
                            if($Diff.SideIndicator -eq "<="){
                                $UserName=$Diff.UserName
                                Write-Log "[$workOn] Add User [$UserName] into Group [$GroupName] on [$mySecondaryVserver]"
                                Write-LogDebug "Add-NcNameMappingUnixGroupUser -Name $GroupName -UserName $UserName -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                                $out=Add-NcNameMappingUnixGroupUser -Name $GroupName -UserName $UserName -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                                if($? -ne $True){$Return = $False; throw "ERROR : Add-NcNameMappingUnixGroupUser [$ErrorVar]"} 
                            }
                        }
                    }
                    if(($GroupUsers.count -gt 0) -and ($SecondaryGroupUsers.count -eq 0)){
                        foreach($UserInGroup in $GroupUsers){
                            $UserName=$UserInGroup.UserName
                            Write-Log "[$workOn] Add User [$UserName] into Group [$GroupName] on [$mySecondaryVserver]"
                            Write-LogDebug "Add-NcNameMappingUnixGroupUser -Name $GroupName -UserName $UserName -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                            $out=Add-NcNameMappingUnixGroupUser -Name $GroupName -UserName $UserName -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if($? -ne $True){$Return = $False; throw "ERROR : Add-NcNameMappingUnixGroupUser [$ErrorVar]"}
                        }    
                    }   
                }   
            }
        }
        Write-LogDebug "create_update_localunixgroupanduser_dr[$myPrimaryVserver]: end"
        return $Return
    }
    catch
    {
        handle_error $_ $myPrimaryVserver
        return $Return        
    }
}


#############################################################################################
# create_update_role_dr
Function create_update_role_dr(
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) 
{
    Try 
    {
        $Return=$True
        Write-Log "[$workOn] Check Role"
        Write-LogDebug "create_update_role_dr[$myPrimaryVserver]: start"
        if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
        if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}

        if($Backup -eq $False -and $Restore -eq $False){
            $mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController -ErrorVariable ErrorVar).ClusterName 
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }
        }
        if($Restore -eq $False){
            $template_source=Get-NcRole -Template -Controller $myPrimaryController
            $template_source.Vserver=$myPrimaryVserver
            Write-LogDebug "Get-NcRole -Query $template_source -Controller $myPrimaryController"
            $source_roles=Get-NcRole -Query $template_source -Controller $myPrimaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return=$false; throw "ERROR: Get-NcRole [$ErrorVar]" }
        }else{
            if(Test-Path $($Global:JsonPath+"Get-NcRole.json")){
                $source_roles=Get-Content $($Global:JsonPath+"Get-NcRole.json") | ConvertFrom-Json
            }else{
                $Return=$False
                $filepath=$($Global:JsonPath+"Get-NcRole.json")
                Throw "ERROR: failed to read $filepath"
            }    
        }
        if($Backup -eq $True){
            $source_roles | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcRole.json") -Encoding ASCII -Width 65535
            if( ($ret=get-item $($Global:JsonPath+"Get-NcRole.json") -ErrorAction SilentlyContinue) -ne $null ){
                Write-LogDebug "$($Global:JsonPath+"Get-NcRole.json") saved successfully"
            }else{
                Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcRole.json")"
                $Return=$False
            }    
        }else{
            $template_dest=Get-NcRole -Template -Controller $mySecondaryController
            $template_dest.Vserver=$mySecondaryVserver
            $source_roles=$source_roles | Where-Object {$_.RoleName -notin @("vsadmin","vsadmin-protocol","vsadmin-readonly","vsadmin-volume","vsadmin-backup","vsadmin-snaplock")}
            Write-LogDebug "Get-NcRole -Query $template_dest -Controller $mySecondaryController"
            $dest_roles=Get-NcRole -Query $template_dest -Controller $mySecondaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return=$false; throw  "ERROR: Get-NcRole [$ErrorVar]" }
            $dest_roles=$dest_roles | Where-Object {$_.RoleName -notin @("vsadmin","vsadmin-protocol","vsadmin-readonly","vsadmin-volume","vsadmin-backup","vsadmin-snaplock")}
            if($dest_roles -ne $null){
                foreach($role in $dest_roles){
                    $roleName=$role.RoleName
                    $roleAccessLevel=$role.AccessLevel
                    $roleCommandDirectoryName=$role.CommandDirectoryName
                    $roleQuery=$role.RoleQuery
                    $roleVserver=$mySecondaryVserver
                    Write-Log "[$workOn] Delete this role : [$roleName] [$roleAccessLevel] [$roleCommandDirectoryName] from [$roleVserver]"
                    Write-LogDebug "Remove-NcRole -Role $roleName -Vserver $roleVserver -CommandDirectory $roleCommandDirectoryName -Controller $mySecondaryCluster"
                    $out=Remove-NcRole -Role $roleName -Vserver $roleVserver -CommandDirectory $roleCommandDirectoryName -Controller $mySecondaryController -Confirm:$false -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return=$false; throw "Failed to delete role : [$roleName] [$roleAccessLevel] [$roleCommandDirectoryName] from [$roleVserver]"}
                }
            }
            foreach($role in $source_roles){
                $roleName=$role.RoleName
                $roleAccessLevel=$role.AccessLevel
                $roleCommandDirectoryName=$role.CommandDirectoryName
                $roleQuery=$role.RoleQuery
                $roleVserver=$mySecondaryVserver
                Write-Log "[$workOn] Create this role : [$roleName] [$roleAccessLevel] [$roleCommandDirectoryName] [$roleQuery] on [$roleVserver]"
                if($roleQuery.length -eq 0 -or $roleQuery.count -eq 0){
                    Write-LogDebug "Set roleQuery to null string"
                    $roleQuery=""
                }
                Write-LogDebug "New-NcRole -Role $roleName -Vserver $roleVserver -CommandDirectory $roleCommandDirectoryName -AccessLevel $roleAccessLevel -RoleQuery $roleQuery -Controller $mySecondaryCluster"
                $out=New-NcRole -Role $roleName -Vserver $roleVserver -CommandDirectory $roleCommandDirectoryName -AccessLevel $roleAccessLevel -RoleQuery $roleQuery -Controller $mySecondaryController -ErrorVariable ErrorVar 
                if ( $? -ne $True ) { $Return=$false; throw  "Failed to create role : [$roleName] [$roleAccessLevel] [$roleCommandDirectoryName] [$roleQuery] on [$roleVserver] [$ErrorVar]"}
            }
        }   
        Write-LogDebug "Check Role config differences"
        foreach($role in $source_roles.RoleName | Sort-Object -Unique ){
            if($Restore -eq $False){
                Write-LogDebug "Get-NcRoleConfig -Role $role -Vserver $myPrimaryVserver -Controller $myPrimaryController"
                $PrimaryRoleConfig=Get-NcRoleConfig -Role $role -Vserver $myPrimaryVserver -Controller $myPrimaryController -ErrorVariable ErrorVar
            }else{
                if(Test-Path $($Global:JsonPath+"Get-NcRoleConfig-"+$role+".json")){
                    $PrimaryRoleConfig=Get-Content $($Global:JsonPath+"Get-NcRoleConfig-"+$role+".json") | ConvertFrom-Json
                }else{
                    $Return=$False
                    $filepath=$($Global:JsonPath+"Get-NcRoleConfig-"+$role+".json")
                    Throw "ERROR: failed to read $filepath"
                }        
            }
            if($Backup -eq $True){
                $PrimaryRoleConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcRoleConfig-"+$role+".json") -Encoding ASCII -Width 65535
                if( ($ret=get-item $($Global:JsonPath+"Get-NcRoleConfig-"+$role+".json") -ErrorAction SilentlyContinue) -ne $null ){
                    Write-LogDebug "$($Global:JsonPath+"Get-NcRoleConfig-"+$role+".json") saved successfully"
                }else{
                    Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcRoleConfig-"+$role+".json")"
                    $Return=$False
                }
            }else{
                $PRC_Name=$PrimaryRoleConfig.RoleName
                $PRC_MinUsernameSize=$PrimaryRoleConfig.MinUsernameSize
                $PRC_RequireUsernameAlphaNumeric=$PrimaryRoleConfig.RequireUsernameAlphaNumeric
                $PRC_MinPasswordSize=$PrimaryRoleConfig.MinPasswordSize
                $PRC_RequirePasswordAlphaNumeric=$PrimaryRoleConfig.RequirePasswordAlphaNumeric
                $PRC_ChangePasswordDurationInDays=$PrimaryRoleConfig.ChangePasswordDurationInDays
                $PRC_LastPasswordsDisallowedCount=$PrimaryRoleConfig.LastPasswordsDisallowedCount
                #$PrimaryVersion=(Get-NcSystemVersionInfo -Controller $myPrimaryController).VersionTupleV
                <#if($PrimaryVersion.Major -ge 9){
                    Write-LogDebug "Source cluster runs ONTAP 9 or greater, so get extended role config"
                    $PRC_AccountExpiryTime=$PrimaryRoleConfig.AccountExpiryTime
                    $PRC_AccountInactiveLimit=$PrimaryRoleConfig.AccountInactiveLimit
                    $PRC_DelayAfterFailedLogin=$PrimaryRoleConfig.DelayAfterFailedLogin
                    $PRC_LockoutDuration=$PrimaryRoleConfig.LockoutDuration
                    $PRC_MaxFailedLoginAttempts=$PrimaryRoleConfig.MaxFailedLoginAttempts
                    $PRC_MinPasswdSpecialchar=$PrimaryRoleConfig.MinPasswdSpecialchar
                    $PRC_PasswdExpiryWarnTime=$PrimaryRoleConfig.PasswdExpiryWarnTime
                    $PRC_PasswdMinDigits=$PrimaryRoleConfig.PasswdMinDigits
                    $PRC_PasswdMinLowercaseChars=$PrimaryRoleConfig.PasswdMinLowercaseChars
                    $PRC_PasswdMinUppercaseChars=$PrimaryRoleConfig.PasswdMinUppercaseChars
                    $PRC_PasswordExpirationDuration=$PrimaryRoleConfig.PasswordExpirationDuration
                    $PRC_RequireInitialPasswordUpdate=$PrimaryRoleConfig.RequireInitialPasswordUpdate
                    $PRC_RequirePasswordAlphaNumeric=$PrimaryRoleConfig.RequirePasswordAlphaNumeric
                    $PRC_RequireUsernameAlphaNumeric=$PrimaryRoleConfig.RequireUsernameAlphaNumeric
                }#>
                Write-LogDebug "Get-NcRoleConfig -Role $role -Vserver $mySecondaryVserver -Controller $mySecondaryController"
                $SecondaryRoleConfig=Get-NcRoleConfig -Role $role -Vserver $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return=$false; throw  "Failed Get-NcRoleConfig [$ErrorVar]"}
                if($PrimaryRoleConfig -ne $null -and $SecondaryRoleConfig -ne $null){
                    $diff=Compare-Object -ReferenceObject $PrimaryRoleConfig -DifferenceObject $SecondaryRoleConfig -Property MinUsernameSize,RequireUsernameAlphaNumeric,MinPasswordSize,RequirePasswordAlphaNumeric,`
                    ChangePasswordDurationInDays,LastPasswordsDisallowedCount | Sort-Object -Property SideIndicator -Descending
                }
                if($diff){
                    Write-LogDebug "Set-NcRoleConfig -Role $PRC_Name -Vserver $mySecondaryVserver -MinUsernameSize $PRC_MinUsernameSize -MinPasswordSize $PRC_MinPasswordSize `
                    -LastPasswordsDisallowedCount $PRC_LastPasswordsDisallowedCount -ChangePasswordDurationInDays $PRC_ChangePasswordDurationInDays -RequireUsernameAlphaNumeric $PRC_RequireUsernameAlphaNumeric `
                    -RequirePasswordAlphaNumeric $PRC_RequirePasswordAlphaNumeric -Controller $mySecondaryController"
                    $out=Set-NcRoleConfig -Role $PRC_Name -Vserver $mySecondaryVserver -MinUsernameSize $PRC_MinUsernameSize -MinPasswordSize $PRC_MinPasswordSize `
                    -LastPasswordsDisallowedCount $PRC_LastPasswordsDisallowedCount -ChangePasswordDurationInDays $PRC_ChangePasswordDurationInDays -RequireUsernameAlphaNumeric $PRC_RequireUsernameAlphaNumeric `
                    -RequirePasswordAlphaNumeric $PRC_RequirePasswordAlphaNumeric -Controller $mySecondaryController -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return=$false; throw  "Failed Set-NcRoleConfigs [$ErrorVar]"}
                }
            }

        }
        Write-LogDebug "create_update_role_dr[$myPrimaryVserver]: end"
        return $Return
    }
    catch
    {
        handle_error $_ $myPrimaryVserver
        return $Return       
    }
}

#############################################################################################
# create_update_fpolicy_dr
Function create_update_fpolicy_dr(
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) 
{
    Try 
    {
        $Return=$True
        Write-Log "[$workOn] Check SVM FPolicy configuration"
        Write-LogDebug "create_update_fpolicy_dr[$myPrimaryVserver]: start"
        if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
        if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}

        if($Restore -eq $False){
            Write-LogDebug "Get-NcFpolicyExternalEngine -Vserver $myPrimaryVserver -controller $myPrimaryController"
            $PrimaryFpolicyEngineList=Get-NcFpolicyExternalEngine -Vserver $myPrimaryVserver -controller $myPrimaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcFpolicyExternalEngine failed [$ErrorVar]" }
        }else{
            if(Test-Path $($Global:JsonPath+"Get-NcFpolicyExternalEngine.json")){
                $PrimaryFpolicyEngineList=Get-Content $($Global:JsonPath+"Get-NcFpolicyExternalEngine.json") | ConvertFrom-Json
            }else{
                $Return=$False
                $filepath=$($Global:JsonPath+"Get-NcFpolicyExternalEngine.json")
                Throw "ERROR: failed to read $filepath"
            }
        }
        if($Backup -eq $True){
            $PrimaryFpolicyEngineList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcFpolicyExternalEngine.json") -Encoding ASCII -Width 65535
            if( ($ret=get-item $($Global:JsonPath+"Get-NcFpolicyExternalEngine.json") -ErrorAction SilentlyContinue) -ne $null ){
                Write-LogDebug "$($Global:JsonPath+"Get-NcFpolicyExternalEngine.json") saved successfully"
            }else{
                Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcFpolicyExternalEngine.json")"
                $Return=$False
            }
        }
        foreach ( $PrimaryFpolicyEngine in ( $PrimaryFpolicyEngineList | Skip-Null ) ) {
            if($Backup -eq $False){
                $PrimaryFpolicyEngineName=$PrimaryFpolicyEngine.EngineName
                $PrimaryFpolicyEnginePort=$PrimaryFpolicyEngine.PortNumber
                $PrimaryFpolicyEnginePrimaryServers=$PrimaryFpolicyEngine.PrimaryServers
                $PrimaryFpolicyEnginePrimaryServers_str=[string]$PrimaryFpolicyEnginePrimaryServers
                $PrimaryFpolicyEngineSecondaryServers=$PrimaryFpolicyEngine.SecondaryServers
                $PrimaryFpolicyEngineSecondaryServers_str=[string]$PrimaryFpolicyEngineSecondaryServers
                $PrimaryFpolicyEngineSslOption=$PrimaryFpolicyEngine.SslOption
                $PrimaryFpolicyEngineExternEngineType=$PrimaryFpolicyEngine.ExternEngineType
                $PrimaryFpolicyEngineRequestCancelTimeout=$PrimaryFpolicyEngine.RequestCancelTimeout
                $PrimaryFpolicyEngineRequestAbortTimeout=$PrimaryFpolicyEngine.RequestAbortTimeout
                $PrimaryFpolicyEngineStatusRequestInterval=$PrimaryFpolicyEngine.StatusRequestInterval
                $PrimaryFpolicyEngineMaxConnectionRetries=$PrimaryFpolicyEngine.MaxConnectionRetries
                $PrimaryFpolicyEngineMaxServerRequests=$PrimaryFpolicyEngine.MaxServerRequests
                $PrimaryFpolicyEngineServerProgressTimeout=$PrimaryFpolicyEngine.ServerProgressTimeout
                $PrimaryFpolicyEngineKeepAliveInterval=$PrimaryFpolicyEngine.KeepAliveInterval
                $PrimaryFpolicyEngineCertificateCommonName=$PrimaryFpolicyEngine.CertificateCommonName
                $PrimaryFpolicyEngineCertificateSerial=$PrimaryFpolicyEngine.CertificateSerial
                $PrimaryFpolicyEngineCertificateCa=$PrimaryFpolicyEngine.CertificateCa

                Write-LogDebug "Get-NcFpolicyExternalEngine -Name $PrimaryFpolicyEngineName -Vserver $mySecondaryVserver -controller $mySecondaryController"
                $SecondaryFpolicyEngine=Get-NcFpolicyExternalEngine -Name $PrimaryFpolicyEngineName -Vserver $mySecondaryVserver -controller $mySecondaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcFpolicyExternalEngine failed [$ErrorVar]" }
                if($SecondaryFpolicyEngine -ne $null)
                {
                    $SecondaryFpolicyEnginePort=$SecondaryFpolicyEngine.PortNumber
                    $SecondaryFpolicyEnginePrimaryServers=$SecondaryFpolicyEngine.PrimaryServers
                    $SecondaryFpolicyEnginePrimaryServers_str=[string]$SecondaryFpolicyEnginePrimaryServers
                    $SecondaryFpolicyEngineSecondaryServers=$SecondaryFpolicyEngine.SecondaryServers
                    $SecondaryFpolicyEngineSecondaryServers_str=[string]$SecondaryFpolicyEngineSecondaryServers
                    $SecondaryFpolicyEngineSslOption=$SecondaryFpolicyEngine.SslOption
                    $SecondaryFpolicyEngineExternEngineType=$SecondaryFpolicyEngine.ExternEngineType
                    $SecondaryFpolicyEngineRequestCancelTimeout=$SecondaryFpolicyEngine.RequestCancelTimeout
                    $SecondaryFpolicyEngineRequestAbortTimeout=$SecondaryFpolicyEngine.RequestAbortTimeout
                    $SecondaryFpolicyEngineStatusRequestInterval=$SecondaryFpolicyEngine.StatusRequestInterval
                    $SecondaryFpolicyEngineMaxConnectionRetries=$SecondaryFpolicyEngine.MaxConnectionRetries
                    $SecondaryFpolicyEngineMaxServerRequests=$SecondaryFpolicyEngine.MaxServerRequests
                    $SecondaryFpolicyEngineServerProgressTimeout=$SecondaryFpolicyEngine.ServerProgressTimeout
                    $SecondaryFpolicyEngineKeepAliveInterval=$SecondaryFpolicyEngine.KeepAliveInterval
                    $SecondaryFpolicyEngineCertificateCommonName=$SecondaryFpolicyEngine.CertificateCommonName
                    $SecondaryFpolicyEngineCertificateSerial=$SecondaryFpolicyEngine.CertificateSerial
                    $SecondaryFpolicyEngineCertificateCa=$SecondaryFpolicyEngine.CertificateCa

                    #if ( (($PrimaryFpolicyEnginePrimaryServers_str -ne $SecondaryFpolicyEnginePrimaryServers_str) `
                    #    -and (($PrimaryFpolicyEnginePrimaryServers -ne $null) -and ($SecondaryFpolicyEnginePrimaryServers -ne $null))) `
                    #    -or (($PrimaryFpolicyEngineSecondaryServers_str -ne $SecondaryFpolicyEngineSecondaryServers_str) `
                    #    -and (($PrimaryFpolicyEngineSecondaryServers -ne $null) -and ($SecondaryFpolicyEngineSecondaryServers -ne $null))) `
                    if ( ($PrimaryFpolicyEnginePort -ne $SecondaryFpolicyEnginePort) `
                        -or ($PrimaryFpolicyEngineSslOption -ne $SecondaryFpolicyEngineSslOption) `
                        -or ($PrimaryFpolicyEngineExternEngineType -ne $SecondaryFpolicyEngineExternEngineType) `
                        -or ($PrimaryFpolicyEngineRequestCancelTimeout -ne $SecondaryFpolicyEngineRequestCancelTimeout) `
                        -or ($PrimaryFpolicyEngineRequestAbortTimeout -ne $SecondaryFpolicyEngineRequestAbortTimeout) `
                        -or ($PrimaryFpolicyEngineStatusRequestInterval -ne $SecondaryFpolicyEngineStatusRequestInterval) `
                        -or ($PrimaryFpolicyEngineMaxConnectionRetries -ne $SecondaryFpolicyEngineMaxConnectionRetries) `
                        -or ($PrimaryFpolicyEngineMaxServerRequests -ne $SecondaryFpolicyEngineMaxServerRequests) `
                        -or ($PrimaryFpolicyEngineServerProgressTimeout -ne $SecondaryFpolicyEngineServerProgressTimeout) `
                        -or ($PrimaryFpolicyEngineKeepAliveInterval -ne $SecondaryFpolicyEngineKeepAliveInterval) `
                        -or ($PrimaryFpolicyEngineCertificateCommonName -ne $SecondaryFpolicyEngineCertificateCommonName) `
                        -or ($PrimaryFpolicyEngineCertificateSerial -ne $SecondaryFpolicyEngineCertificateSerial) `
                        -or ($PrimaryFpolicyEngineCertificateCa -ne $SecondaryFpolicyEngineCertificateCa) )
                    {
                        Write-Log "[$workOn] Modify Fpolicy External Engine [$PrimaryFpolicyEngineName]"
                        if($fromConfigureDR -eq $True)
                        {
                            try {
                                $global:mutexconsole.WaitOne(200) | Out-Null
                            }
                            catch [System.Threading.AbandonedMutexException]{
                                #AbandonedMutexException means another thread exit without releasing the mutex, and this thread has acquired the mutext, therefore, it can be ignored
                                Write-Host -f Red "catch abandoned mutex for [$workOn]"
                                free_mutexconsole
                            }
                            Write-Log "[$workOn] Enter IP Address of a Primary External Server"
                            $ANS='y'
                            $num=(($SecondaryFpolicyEnginePrimaryServers.count)-1)
                            if($num -ge 0)
                            {
                                $myFpolicyEnginePrimaryServers=$SecondaryFpolicyEnginePrimaryServers   
                            }
                            else
                            {
                                $myFpolicyEnginePrimaryServers=$PrimaryFpolicyEnginePrimaryServers    
                            }
                            while($ANS -ne 'n')
                            {
                                $SecondaryFpolicyEnginePrimaryServers+=ask_IpAddr_from_cli -myIpAddr $myFpolicyEnginePrimaryServers[$num++] -workOn $workOn
                                $ANS=Read-HostOptions "[$workOn] Do you want to add more Primary External Server ?" "y/n"
                            }
                            if( ($PrimaryFpolicyEngineSecondaryServers_str -ne $SecondaryFpolicyEngineSecondaryServers_str) `
                                -and (($PrimaryFpolicyEngineSecondaryServers -ne $null) -and ($SecondaryFpolicyEngineSecondaryServers -ne $null)) )
                            {
                                Write-Log "[$workOn] Enter IP Address of a Secondary External Server"
                                $ANS='y'
                                $num=(($SecondaryFpolicyEngineSecondaryServers.count)-1)
                                if($num -ge 0)
                                {
                                    $myFpolicyEngineSecondaryServers=$SecondaryFpolicyEngineSecondaryServers   
                                }
                                else
                                {
                                    $myFpolicyEngineSecondaryServers=$PrimaryFpolicyEngineSecondaryServers    
                                }
                                while($ANS -ne 'n')
                                {
                                    $SecondaryFpolicyEngineSecondaryServers+=ask_IpAddr_from_cli -myIpAddr $myFpolicyEngineSecondaryServers[$num++] -workOn $workOn
                                    $ANS=Read-HostOptions "Do you want to add more Secondary External Server ?" "y/n"
                                }        
                            }
                            free_mutexconsole
                            Write-LogDebug ""
                            if($PrimaryFpolicyEngineExternEngineType -eq "Synchronous")
                            {
                                Write-LogDebug "Set-NcFpolicyExternalEngine -Name $PrimaryFpolicyEngineName -PrimaryServer $SecondaryFpolicyEnginePrimaryServers `
                                -Port $PrimaryFpolicyEnginePort -SecondaryServer $SecondaryFpolicyEngineSecondaryServers -Synchronous -SslOption $PrimaryFpolicyEngineSslOption `
                                -RequestCancelTimeout $PrimaryFpolicyEngineRequestCancelTimeout -RequestAbortTimeout $PrimaryFpolicyEngineRequestAbortTimeout `
                                -StatusRequestInterval $PrimaryFpolicyEngineStatusRequestInterval -MaxConnectionRetries $PrimaryFpolicyEngineMaxConnectionRetries `
                                -MaxServerRequests $PrimaryFpolicyEngineMaxServerRequests -ServerProgressTimeout $PrimaryFpolicyEngineServerProgressTimeout `
                                -KeepAliveInterval $PrimaryFpolicyEngineKeepAliveInterval -CertificateCommonName $PrimaryFpolicyEngineCertificateCommonName `
                                -CertificateSerial $PrimaryFpolicyEngineCertificateSerial -CertificateCa $PrimaryFpolicyEngineCertificateCa `
                                -Controller $mySecondaryController"
                                $out=Set-NcFpolicyExternalEngine -Name $PrimaryFpolicyEngineName -PrimaryServer $SecondaryFpolicyEnginePrimaryServers `
                                -Port $PrimaryFpolicyEnginePort -SecondaryServer $SecondaryFpolicyEngineSecondaryServers -Synchronous -SslOption $PrimaryFpolicyEngineSslOption `
                                -RequestCancelTimeout $PrimaryFpolicyEngineRequestCancelTimeout -RequestAbortTimeout $PrimaryFpolicyEngineRequestAbortTimeout `
                                -StatusRequestInterval $PrimaryFpolicyEngineStatusRequestInterval -MaxConnectionRetries $PrimaryFpolicyEngineMaxConnectionRetries `
                                -MaxServerRequests $PrimaryFpolicyEngineMaxServerRequests -ServerProgressTimeout $PrimaryFpolicyEngineServerProgressTimeout `
                                -KeepAliveInterval $PrimaryFpolicyEngineKeepAliveInterval -CertificateCommonName $PrimaryFpolicyEngineCertificateCommonName `
                                -CertificateSerial $PrimaryFpolicyEngineCertificateSerial -CertificateCa $PrimaryFpolicyEngineCertificateCa `
                                -Controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcFpolicyExternalEngine failed [$ErrorVar]" } 
                            }
                            else
                            {
                                Write-LogDebug "Set-NcFpolicyExternalEngine -Name $PrimaryFpolicyEngineName -PrimaryServer $SecondaryFpolicyEnginePrimaryServers `
                                -Port $PrimaryFpolicyEnginePort -SecondaryServer $SecondaryFpolicyEnginePrimaryServers -Asynchronous -SslOption $PrimaryFpolicyEngineSslOption `
                                -RequestCancelTimeout $PrimaryFpolicyEngineRequestCancelTimeout -RequestAbortTimeout $PrimaryFpolicyEngineRequestAbortTimeout `
                                -StatusRequestInterval $PrimaryFpolicyEngineStatusRequestInterval -MaxConnectionRetries $PrimaryFpolicyEngineMaxConnectionRetries `
                                -MaxServerRequests $PrimaryFpolicyEngineMaxServerRequests -ServerProgressTimeout $PrimaryFpolicyEngineServerProgressTimeout `
                                -KeepAliveInterval $PrimaryFpolicyEngineKeepAliveInterval -CertificateCommonName $PrimaryFpolicyEngineCertificateCommonName `
                                -CertificateSerial $PrimaryFpolicyEngineCertificateSerial -CertificateCa $PrimaryFpolicyEngineCertificateCa `
                                -Controller $mySecondaryController"
                                $out=Set-NcFpolicyExternalEngine -Name $PrimaryFpolicyEngineName -PrimaryServer $SecondaryFpolicyEnginePrimaryServers `
                                -Port $PrimaryFpolicyEnginePort -SecondaryServer $SecondaryFpolicyEnginePrimaryServers -Asynchronous -SslOption $PrimaryFpolicyEngineSslOption `
                                -RequestCancelTimeout $PrimaryFpolicyEngineRequestCancelTimeout -RequestAbortTimeout $PrimaryFpolicyEngineRequestAbortTimeout `
                                -StatusRequestInterval $PrimaryFpolicyEngineStatusRequestInterval -MaxConnectionRetries $PrimaryFpolicyEngineMaxConnectionRetries `
                                -MaxServerRequests $PrimaryFpolicyEngineMaxServerRequests -ServerProgressTimeout $PrimaryFpolicyEngineServerProgressTimeout `
                                -KeepAliveInterval $PrimaryFpolicyEngineKeepAliveInterval -CertificateCommonName $PrimaryFpolicyEngineCertificateCommonName `
                                -CertificateSerial $PrimaryFpolicyEngineCertificateSerial -CertificateCa $PrimaryFpolicyEngineCertificateCa `
                                -Controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcFpolicyExternalEngine failed [$ErrorVar]" } 
                            }
                        }
                        else
                        {
                            if($PrimaryFpolicyEngineExternEngineType -eq "Synchronous")
                            {
                                Write-LogDebug "Set-NcFpolicyExternalEngine -Name $PrimaryFpolicyEngineName  `
                                -Port $PrimaryFpolicyEnginePort -Synchronous -SslOption $PrimaryFpolicyEngineSslOption `
                                -RequestCancelTimeout $PrimaryFpolicyEngineRequestCancelTimeout -RequestAbortTimeout $PrimaryFpolicyEngineRequestAbortTimeout `
                                -StatusRequestInterval $PrimaryFpolicyEngineStatusRequestInterval -MaxConnectionRetries $PrimaryFpolicyEngineMaxConnectionRetries `
                                -MaxServerRequests $PrimaryFpolicyEngineMaxServerRequests -ServerProgressTimeout $PrimaryFpolicyEngineServerProgressTimeout `
                                -KeepAliveInterval $PrimaryFpolicyEngineKeepAliveInterval -CertificateCommonName $PrimaryFpolicyEngineCertificateCommonName `
                                -CertificateSerial $PrimaryFpolicyEngineCertificateSerial -CertificateCa $PrimaryFpolicyEngineCertificateCa `
                                -Controller $mySecondaryController"
                                $out=Set-NcFpolicyExternalEngine -Name $PrimaryFpolicyEngineName  `
                                -Port $PrimaryFpolicyEnginePort -Synchronous -SslOption $PrimaryFpolicyEngineSslOption `
                                -RequestCancelTimeout $PrimaryFpolicyEngineRequestCancelTimeout -RequestAbortTimeout $PrimaryFpolicyEngineRequestAbortTimeout `
                                -StatusRequestInterval $PrimaryFpolicyEngineStatusRequestInterval -MaxConnectionRetries $PrimaryFpolicyEngineMaxConnectionRetries `
                                -MaxServerRequests $PrimaryFpolicyEngineMaxServerRequests -ServerProgressTimeout $PrimaryFpolicyEngineServerProgressTimeout `
                                -KeepAliveInterval $PrimaryFpolicyEngineKeepAliveInterval -CertificateCommonName $PrimaryFpolicyEngineCertificateCommonName `
                                -CertificateSerial $PrimaryFpolicyEngineCertificateSerial -CertificateCa $PrimaryFpolicyEngineCertificateCa `
                                -Controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcFpolicyExternalEngine failed [$ErrorVar]" } 
                            }
                            else
                            {
                                Write-LogDebug "Set-NcFpolicyExternalEngine -Name $PrimaryFpolicyEngineName  `
                                -Port $PrimaryFpolicyEnginePort -Asynchronous -SslOption $PrimaryFpolicyEngineSslOption `
                                -RequestCancelTimeout $PrimaryFpolicyEngineRequestCancelTimeout -RequestAbortTimeout $PrimaryFpolicyEngineRequestAbortTimeout `
                                -StatusRequestInterval $PrimaryFpolicyEngineStatusRequestInterval -MaxConnectionRetries $PrimaryFpolicyEngineMaxConnectionRetries `
                                -MaxServerRequests $PrimaryFpolicyEngineMaxServerRequests -ServerProgressTimeout $PrimaryFpolicyEngineServerProgressTimeout `
                                -KeepAliveInterval $PrimaryFpolicyEngineKeepAliveInterval -CertificateCommonName $PrimaryFpolicyEngineCertificateCommonName `
                                -CertificateSerial $PrimaryFpolicyEngineCertificateSerial -CertificateCa $PrimaryFpolicyEngineCertificateCa `
                                -Controller $mySecondaryController"
                                $out=Set-NcFpolicyExternalEngine -Name $PrimaryFpolicyEngineName  `
                                -Port $PrimaryFpolicyEnginePort -Asynchronous -SslOption $PrimaryFpolicyEngineSslOption `
                                -RequestCancelTimeout $PrimaryFpolicyEngineRequestCancelTimeout -RequestAbortTimeout $PrimaryFpolicyEngineRequestAbortTimeout `
                                -StatusRequestInterval $PrimaryFpolicyEngineStatusRequestInterval -MaxConnectionRetries $PrimaryFpolicyEngineMaxConnectionRetries `
                                -MaxServerRequests $PrimaryFpolicyEngineMaxServerRequests -ServerProgressTimeout $PrimaryFpolicyEngineServerProgressTimeout `
                                -KeepAliveInterval $PrimaryFpolicyEngineKeepAliveInterval -CertificateCommonName $PrimaryFpolicyEngineCertificateCommonName `
                                -CertificateSerial $PrimaryFpolicyEngineCertificateSerial -CertificateCa $PrimaryFpolicyEngineCertificateCa `
                                -Controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcFpolicyExternalEngine failed [$ErrorVar]" } 
                            }    
                        }  
                    }
                }
                else 
                {
                    try {
                        $global:mutexconsole.WaitOne(200) | Out-Null
                    }
                    catch [System.Threading.AbandonedMutexException]{
                        #AbandonedMutexException means another thread exit without releasing the mutex, and this thread has acquired the mutext, therefore, it can be ignored
                        Write-Host -f Red "catch abandoned mutex for [$workOn]"
                        free_mutexconsole
                    }
                    Write-Log "[$workOn] Create Fpolicy External Engine [$PrimaryFpolicyEngineName]"
                    Write-Log "[$workOn] Enter IP Address of a Primary External Server"
                    $ANS='y'
                    $num=(($PrimaryFpolicyEnginePrimaryServers.count)-1)
                    $myFpolicyEnginePrimaryServers=$PrimaryFpolicyEnginePrimaryServers    
                    while($ANS -ne 'n')
                    {
                        $SecondaryFpolicyEnginePrimaryServers+=ask_IpAddr_from_cli -myIpAddr $myFpolicyEnginePrimaryServers[$num++] -workOn $workOn
                        $ANS=Read-HostOptions "Do you want to add more Primary External Server ?" "y/n"
                    }
                    if( $PrimaryFpolicyEngineSecondaryServers -ne $null )
                    {
                        Write-Log "[$workOn] Enter IP Address of a Secondary External Server"
                        $ANS='y'
                        $num=(($PrimaryFpolicyEngineSecondaryServers.count)-1)
                        $myFpolicyEngineSecondaryServers=$PrimaryFpolicyEngineSecondaryServers    
                        while($ANS -ne 'n')
                        {
                            $SecondaryFpolicyEngineSecondaryServers+=ask_IpAddr_from_cli -myIpAddr $myFpolicyEngineSecondaryServers[$num++] -workOn $workOn
                            $ANS=Read-HostOptions "[$workOn] Do you want to add more Secondary External Server ?" "y/n"
                        }    
                    }
                    free_mutexconsole
                    if($PrimaryFpolicyEngineExternEngineType -eq "Synchronous")
                    {
                        Write-LogDebug "New-NcFpolicyExternalEngine -Name $PrimaryFpolicyEngineName -PrimaryServer $SecondaryFpolicyEnginePrimaryServers `
                        -Port $PrimaryFpolicyEnginePort -Synchronous -SecondaryServer $SecondaryFpolicyEngineSecondaryServers -SslOption $PrimaryFpolicyEngineSslOption `
                        -RequestCancelTimeout $PrimaryFpolicyEngineRequestCancelTimeout -RequestAbortTimeout $PrimaryFpolicyEngineRequestAbortTimeout `
                        -StatusRequestInterval $PrimaryFpolicyEngineStatusRequestInterval -MaxConnectionRetries $PrimaryFpolicyEngineMaxConnectionRetries `
                        -MaxServerRequests $PrimaryFpolicyEngineMaxServerRequests -ServerProgressTimeout $PrimaryFpolicyEngineServerProgressTimeout `
                        -KeepAliveInterval $PrimaryFpolicyEngineKeepAliveInterval -CertificateCommonName $PrimaryFpolicyEngineCertificateCommonName `
                        -CertificateSerial $PrimaryFpolicyEngineCertificateSerial -CertificateCa $PrimaryFpolicyEngineCertificateCa -VserverContext $mySecondaryVserver `
                        -Controller $mySecondaryController"
                        $out=New-NcFpolicyExternalEngine -Name $PrimaryFpolicyEngineName -PrimaryServer $SecondaryFpolicyEnginePrimaryServers `
                        -Port $PrimaryFpolicyEnginePort -Synchronous -SecondaryServer $SecondaryFpolicyEngineSecondaryServers -SslOption $PrimaryFpolicyEngineSslOption `
                        -RequestCancelTimeout $PrimaryFpolicyEngineRequestCancelTimeout -RequestAbortTimeout $PrimaryFpolicyEngineRequestAbortTimeout `
                        -StatusRequestInterval $PrimaryFpolicyEngineStatusRequestInterval -MaxConnectionRetries $PrimaryFpolicyEngineMaxConnectionRetries `
                        -MaxServerRequests $PrimaryFpolicyEngineMaxServerRequests -ServerProgressTimeout $PrimaryFpolicyEngineServerProgressTimeout `
                        -KeepAliveInterval $PrimaryFpolicyEngineKeepAliveInterval -CertificateCommonName $PrimaryFpolicyEngineCertificateCommonName `
                        -CertificateSerial $PrimaryFpolicyEngineCertificateSerial -CertificateCa $PrimaryFpolicyEngineCertificateCa `
                        -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcFpolicyExternalEngine failed [$ErrorVar]" } 
                    }
                    else
                    {
                        Write-LogDebug "New-NcFpolicyExternalEngine -Name $PrimaryFpolicyEngineName -PrimaryServer $PrimaryFpolicyEnginePrimaryServers `
                        -Port $PrimaryFpolicyEnginePort -Asynchronous -SecondaryServer $PrimaryFpolicyEngineSecondaryServers -SslOption $PrimaryFpolicyEngineSslOption `
                        -RequestCancelTimeout $PrimaryFpolicyEngineRequestCancelTimeout -RequestAbortTimeout $PrimaryFpolicyEngineRequestAbortTimeout `
                        -StatusRequestInterval $PrimaryFpolicyEngineStatusRequestInterval -MaxConnectionRetries $PrimaryFpolicyEngineMaxConnectionRetries `
                        -MaxServerRequests $PrimaryFpolicyEngineMaxServerRequests -ServerProgressTimeout $PrimaryFpolicyEngineServerProgressTimeout `
                        -KeepAliveInterval $PrimaryFpolicyEngineKeepAliveInterval -CertificateCommonName $PrimaryFpolicyEngineCertificateCommonName `
                        -CertificateSerial $PrimaryFpolicyEngineCertificateSerial -CertificateCa $PrimaryFpolicyEngineCertificateCa -VserverContext $mySecondaryVserver `
                        -Controller $mySecondaryController"
                        $out=New-NcFpolicyExternalEngine -Name $PrimaryFpolicyEngineName -PrimaryServer $PrimaryFpolicyEnginePrimaryServers `
                        -Port $PrimaryFpolicyEnginePort -Asynchronous -SecondaryServer $PrimaryFpolicyEngineSecondaryServers -SslOption $PrimaryFpolicyEngineSslOption `
                        -RequestCancelTimeout $PrimaryFpolicyEngineRequestCancelTimeout -RequestAbortTimeout $PrimaryFpolicyEngineRequestAbortTimeout `
                        -StatusRequestInterval $PrimaryFpolicyEngineStatusRequestInterval -MaxConnectionRetries $PrimaryFpolicyEngineMaxConnectionRetries `
                        -MaxServerRequests $PrimaryFpolicyEngineMaxServerRequests -ServerProgressTimeout $PrimaryFpolicyEngineServerProgressTimeout `
                        -KeepAliveInterval $PrimaryFpolicyEngineKeepAliveInterval -CertificateCommonName $PrimaryFpolicyEngineCertificateCommonName `
                        -CertificateSerial $PrimaryFpolicyEngineCertificateSerial -CertificateCa $PrimaryFpolicyEngineCertificateCa `
                        -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcFpolicyExternalEngine failed [$ErrorVar]" } 
                    }    
                }
            }
            # add code to get/create Event
            if($Restore -eq $False){
                Write-LogDebug "Get-NcFpolicyEvent -Vserver $myPrimaryVserver -Controller $myPrimaryController"
                $PrimaryFpolEvtList=Get-NcFpolicyEvent -Vserver $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcFpolicyEvent failed [$ErrorVar]" }
            }else{
                if(Test-Path $($Global:JsonPath+"Get-NcFpolicyEvent.json")){
                    $PrimaryFpolEvtList=Get-Content $($Global:JsonPath+"Get-NcFpolicyEvent.json") | ConvertFrom-Json
                }else{
                    $Return=$False
                    $filepath=$($Global:JsonPath+"Get-NcFpolicyEvent.json")
                    Throw "ERROR: failed to read $filepath"
                }
            }
            if($Backup -eq $True){
                $PrimaryFpolEvtList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcFpolicyEvent.json") -Encoding ASCII -Width 65535
                if( ($ret=get-item $($Global:JsonPath+"Get-NcFpolicyEvent.json") -ErrorAction SilentlyContinue) -ne $null ){
                    Write-LogDebug "$($Global:JsonPath+"Get-NcFpolicyEvent.json") saved successfully"
                }else{
                    Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcFpolicyEvent.json")"
                    $Return=$False
                }
            }
            foreach ( $PrimaryFpolEvt in ( $PrimaryFpolEvtList | Skip-Null ) ) {
                if($Backup -eq $False){
                    $PrimaryFpolEvtEventName=$PrimaryFpolEvt.EventName
                    $PrimaryFpolEvtFileOperations=$PrimaryFpolEvt.FileOperations
                    $PrimaryFpolEvtFileOperations_str=[string]$PrimaryFpolEvtFileOperations
                    $PrimaryFpolEvtFilterString=$PrimaryFpolEvt.FilterString
                    $PrimaryFpolEvtFilterString_str=[string]$PrimaryFpolEvtFilterString
                    $PrimaryFpolEvtProtocol=$PrimaryFpolEvt.Protocol
                    $PrimaryFpolEvtProtocol_str=[string]$PrimaryFpolEvtProtocol
                    $PrimaryFpolEvtVolumeOperation=$PrimaryFpolEvt.VolumeOperation
                    
                    Write-LogDebug "Get-NcFpolicyEvent -Name $PrimaryFpolEvtEventName -Vserver $mySecondaryVserver -Controller $mySecondaryController"
                    $SecondaryFpolEvt=Get-NcFpolicyEvent -Name $PrimaryFpolEvtEventName -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcFpolicyEvent failed [$ErrorVar]" }
                    if($SecondaryFpolEvt -ne $null)
                    {
                        $SecondaryFpolEvtFileOperations=$SecondaryFpolEvt.FileOperations
                        $SecondaryFpolEvtFileOperations_str=[string]$SecondaryFpolEvtFileOperations
                        $SecondaryFpolEvtFilterString=$SecondaryFpolEvt.FilterString
                        $SecondaryFpolEvtFilterString_str=[string]$SecondaryFpolEvtFilterString
                        $SecondaryFpolEvtProtocol=$SecondaryFpolEvt.Protocol
                        $SecondaryFpolEvtProtocol_str=[string]$SecondaryFpolEvtProtocol
                        $SecondaryFpolEvtVolumeOperation=$SecondaryFpolEvt.VolumeOperation
                        
                        if ( (($PrimaryFpolEvtFileOperations_str -ne $SecondaryFpolEvtFileOperations_str) `
                            -and (($PrimaryFpolEvtFileOperations -ne $null) -and ($SecondaryFpolEvtFileOperations -ne $null))) `
                            -or (($PrimaryFpolEvtFilterString_str -ne $SecondaryFpolEvtFilterString_str) `
                            -and (($PrimaryFpolEvtFilterString -ne $null) -and ($SecondaryFpolEvtFilterString -ne $null))) `
                            -or (($PrimaryFpolEvtProtocol_str -ne $SecondaryFpolEvtProtocol_str) `
                            -and (($PrimaryFpolEvtProtocol -ne $null) -and ($SecondaryFpolEvtProtocol -ne $null))) `
                            -or ($PrimaryFpolEvtVolumeOperation -ne $SecondaryFpolEvtVolumeOperation) )
                        {
                            Write-Log "[$workOn] Modify Fpolicy Event [$PrimaryFpolEvtEventName]"
                            Write-LogDebug "Set-NcFpolicyEvent -Name $PrimaryFpolEvtEventName -Protocol $PrimaryFpolEvtProtocol -FileOperation $PrimaryFpolEvtFileOperations `
                            -VolumeOperation $PrimaryFpolEvtVolumeOperation -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                            $out=Set-NcFpolicyEvent -Name $PrimaryFpolEvtEventName -Protocol $PrimaryFpolEvtProtocol -FileOperation $PrimaryFpolEvtFileOperations `
                            -VolumeOperation $PrimaryFpolEvtVolumeOperation -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcFpolicyEvent failed [$ErrorVar]" }
                        }
                    }
                    else 
                    {
                        Write-Log "[$workOn] Create Fpolicy Event [$PrimaryFpolEvtEventName]"
                        if($PrimaryFpolEvtVolumeOperation -eq $True)
                        {
                            Write-LogDebug "New-NcFpolicyEvent -Name $PrimaryFpolEvtEventName -Protocol $PrimaryFpolEvtProtocol -FileOperation $PrimaryFpolEvtFileOperations `
                            -Filter $PrimaryFpolEvtFilterString -VolumeOperation -VserverContext $mySecondaryVserver -controller $mySecondaryController"
                            $out=New-NcFpolicyEvent -Name $PrimaryFpolEvtEventName -Protocol $PrimaryFpolEvtProtocol -FileOperation $PrimaryFpolEvtFileOperations `
                            -Filter $PrimaryFpolEvtFilterString -VolumeOperation -VserverContext $mySecondaryVserver -controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcFpolicyEvent failed [$ErrorVar]" }
                        }
                        else 
                        {
                            Write-LogDebug "New-NcFpolicyEvent -Name $PrimaryFpolEvtEventName -Protocol $PrimaryFpolEvtProtocol -FileOperation $PrimaryFpolEvtFileOperations `
                            -Filter $PrimaryFpolEvtFilterString -VserverContext $mySecondaryVserver -controller $mySecondaryController"
                            $out=New-NcFpolicyEvent -Name $PrimaryFpolEvtEventName -Protocol $PrimaryFpolEvtProtocol -FileOperation $PrimaryFpolEvtFileOperations `
                            -Filter $PrimaryFpolEvtFilterString -VserverContext $mySecondaryVserver -controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcFpolicyEvent failed [$ErrorVar]" }      
                        }  
                    }
                
                    # add code to get/create Policy
                    Write-LogDebug "Get-NcFpolicyPolicy -Template -Controller $myPrimaryController"
                    $Template=Get-NcFpolicyPolicy -Template -Controller $myPrimaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcFpolicyPolicy failed [$ErrorVar]" }
                    $Template.EngineName=$PrimaryFpolicyEngineName
                    $Template.Events=$PrimaryFpolEvtEventName
                    $Template.Vserver=$myPrimaryVserver
                    Write-LogDebug "Get-NcFpolicyPolicy -Query $Template -Controller $myPrimaryController"
                    $PrimaryFpolPol=Get-NcFpolicyPolicy -Query $Template -Controller $myPrimaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcFpolicyPolicy failed [$ErrorVar]" }
                    if($PrimaryFpolPol -eq $null) {$Return = $Fale ; Write-LogWarn "Missing Fpolicy Policy on Primary Vserver"; continue}
                    
                    $PrimaryFpolPolName=$PrimaryFpolPol.PolicyName
                    $PrimaryFpolPolIsMandatory=$PrimaryFpolPol.IsMandatory
                    $PrimaryFpolPolAllowPrivilegedAccess=$PrimaryFpolPol.AllowPrivilegedAccess
                    $PrimaryFpolPolAllowPrivilegedUserName=$PrimaryFpolPol.PrivilegedUserName
                    $PrimaryFpolPolAllowIsPassthroughReadEnabled=$PrimaryFpolPol.IsPassthroughReadEnabled

                    Write-LogDebug "Get-NcFpolicyPolicy -Template -Controller $mySecondaryController"
                    $Template=Get-NcFpolicyPolicy -Template -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcFpolicyPolicy failed [$ErrorVar]" }
                    $Template.EngineName=$PrimaryFpolicyEngineName
                    $Template.Events=$PrimaryFpolEvtEventName
                    $Template.Vserver=$mySecondaryVserver
                    Write-LogDebug "Get-NcFpolicyPolicy -Query $Template -Controller $mySecondaryController"
                    $SecondaryFpolPol=Get-NcFpolicyPolicy -Query $Template -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcFpolicyPolicy failed [$ErrorVar]" }
                    if($SecondaryFpolPol -ne $null)
                    {
                        #$SecondaryFpolPolName=$SecondaryFpolPol.PolicyName
                        $SecondaryFpolPolIsMandatory=$SecondaryFpolPol.IsMandatory
                        $SecondaryFpolPolAllowPrivilegedAccess=$SecondaryFpolPol.AllowPrivilegedAccess
                        $SecondaryFpolPolAllowPrivilegedUserName=$SecondaryFpolPol.PrivilegedUserName
                        $SecondaryFpolPolAllowIsPassthroughReadEnabled=$SecondaryFpolPol.IsPassthroughReadEnabled
                        
                        if ( ($PrimaryFpolPolIsMandatory -ne $SecondaryFpolPolIsMandatory) `
                            -or ($PrimaryFpolPolAllowPrivilegedAccess -ne $SecondaryFpolPolAllowPrivilegedAccess) `
                            -or ($PrimaryFpolPolAllowPrivilegedUserName -ne $SecondaryFpolPolAllowPrivilegedUserName) `
                            -or ($PrimaryFpolPolAllowIsPassthroughReadEnabled -ne $SecondaryFpolPolAllowIsPassthroughReadEnabled))
                        {
                            Write-Log "[$workOn] Modify Fpolicy Policy [$PrimaryFpolPolName]"
                            Write-LogDebug "Set-NcFpolicyPolicy -Name $PrimaryFpolPolName -Event $PrimaryFpolEvtEventName -EngineName $PrimaryFpolicyEngineName `
                            -Mandatory $PrimaryFpolPolIsMandatory -AllowPrivilegedAccess $PrimaryFpolPolAllowPrivilegedAccess `
                            -PrivilegedUserName $PrimaryFpolPolAllowPrivilegedUserName -IsPassthroughReadEnabled $PrimaryFpolPolAllowIsPassthroughReadEnabled `
                            -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                            $out=Set-NcFpolicyPolicy -Name $PrimaryFpolPolName -Event $PrimaryFpolEvtEventName -EngineName $PrimaryFpolicyEngineName `
                            -Mandatory $PrimaryFpolPolIsMandatory -AllowPrivilegedAccess $PrimaryFpolPolAllowPrivilegedAccess `
                            -PrivilegedUserName $PrimaryFpolPolAllowPrivilegedUserName -IsPassthroughReadEnabled $PrimaryFpolPolAllowIsPassthroughReadEnabled `
                            -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcFpolicyPolicy failed [$ErrorVar]" }
                        }
                    }
                    else 
                    {
                        Write-Log "[$workOn] Create Fpolicy Policy [$PrimaryFpolPolName]"
                        if($PrimaryFpolPolIsMandatory -eq $True)
                        {
                            if($PrimaryFpolPolAllowPrivilegedAccess -eq $True)
                            {
                                Write-LogDebug "New-NcFpolicyPolicy -Name $PrimaryFpolPolName -Event $PrimaryFpolEvtEventName `
                                -EngineName $PrimaryFpolicyEngineName -AllowPrivilegedAccess `
                                -PrivilegedUserName $PrimaryFpolPolAllowPrivilegedUserName -IsPassthroughReadEnabled $PrimaryFpolPolAllowIsPassthroughReadEnabled `
                                -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                                $out=New-NcFpolicyPolicy -Name $PrimaryFpolPolName -Event $PrimaryFpolEvtEventName `
                                -EngineName $PrimaryFpolicyEngineName -AllowPrivilegedAccess `
                                -PrivilegedUserName $PrimaryFpolPolAllowPrivilegedUserName -IsPassthroughReadEnabled $PrimaryFpolPolAllowIsPassthroughReadEnabled `
                                -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcFpolicyPolicy failed [$ErrorVar]" } 
                            }
                            else
                            {
                                Write-LogDebug "New-NcFpolicyPolicy -Name $PrimaryFpolPolName -Event $PrimaryFpolEvtEventName `
                                -EngineName $PrimaryFpolicyEngineName -IsPassthroughReadEnabled $PrimaryFpolPolAllowIsPassthroughReadEnabled `
                                -PrivilegedUserName $PrimaryFpolPolAllowPrivilegedUserName  `
                                -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                                $out=New-NcFpolicyPolicy -Name $PrimaryFpolPolName -Event $PrimaryFpolEvtEventName `
                                -EngineName $PrimaryFpolicyEngineName -IsPassthroughReadEnabled $PrimaryFpolPolAllowIsPassthroughReadEnabled `
                                -PrivilegedUserName $PrimaryFpolPolAllowPrivilegedUserName `
                                -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcFpolicyPolicy failed [$ErrorVar]" }
                            }
                        } 
                        else
                        {
                            if($PrimaryFpolPolAllowPrivilegedAccess -eq $True)
                            {
                                Write-LogDebug "New-NcFpolicyPolicy -Name $PrimaryFpolPolName -Event $PrimaryFpolEvtEventName `
                                -EngineName $PrimaryFpolicyEngineName -AllowPrivilegedAccess `
                                -PrivilegedUserName $PrimaryFpolPolAllowPrivilegedUserName -IsPassthroughReadEnabled $PrimaryFpolPolAllowIsPassthroughReadEnabled `
                                -NonMandatory -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                                $out=New-NcFpolicyPolicy -Name $PrimaryFpolPolName -Event $PrimaryFpolEvtEventName -NonMandatory `
                                -EngineName $PrimaryFpolicyEngineName -AllowPrivilegedAccess `
                                -PrivilegedUserName $PrimaryFpolPolAllowPrivilegedUserName -IsPassthroughReadEnabled $PrimaryFpolPolAllowIsPassthroughReadEnabled `
                                -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcFpolicyPolicy failed [$ErrorVar]" } 
                            }
                            else
                            {
                                Write-LogDebug "New-NcFpolicyPolicy -Name $PrimaryFpolPolName -Event $PrimaryFpolEvtEventName `
                                -EngineName $PrimaryFpolicyEngineName -IsPassthroughReadEnabled $PrimaryFpolPolAllowIsPassthroughReadEnabled `
                                -PrivilegedUserName $PrimaryFpolPolAllowPrivilegedUserName -IsPassthroughReadEnabled $PrimaryFpolPolAllowIsPassthroughReadEnabled `
                                -NonMandatory -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                                $out=New-NcFpolicyPolicy -Name $PrimaryFpolPolName -Event $PrimaryFpolEvtEventName -NonMandatory `
                                -EngineName $PrimaryFpolicyEngineName -IsPassthroughReadEnabled $PrimaryFpolPolAllowIsPassthroughReadEnabled `
                                -PrivilegedUserName $PrimaryFpolPolAllowPrivilegedUserName `
                                -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcFpolicyPolicy failed [$ErrorVar]" }
                            }
                        }

                    }
                }
                # add code to get/create Scope
                if($Restore -eq $False){
                    Write-LogDebug "Get-NcFpolicyScope -PolicyName $PrimaryFpolPolName -Vserver $myPrimaryVserver -Controller $myPrimaryController"
                    $PrimaryFpolScope=Get-NcFpolicyScope -PolicyName $PrimaryFpolPolName -Vserver $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcFpolicyScope failed [$ErrorVar]" }
                }else{
                    if(Test-Path $($Global:JsonPath+"Get-NcFpolicyScope.json")){
                        $PrimaryFpolScope=Get-Content $($Global:JsonPath+"Get-NcFpolicyScope.json") | ConvertFrom-Json
                    }else{
                        $Return=$False
                        $filepath=$($Global:JsonPath+"Get-NcFpolicyScope.json")
                        Throw "ERROR: failed to read $filepath"
                    }
                }
                if($Backup -eq $True){
                    $PrimaryFpolScope | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcFpolicyScope.json") -Encoding ASCII -Width 65535
                    if( ($ret=get-item $($Global:JsonPath+"Get-NcFpolicyScope.json") -ErrorAction SilentlyContinue) -ne $null ){
                        Write-LogDebug "$($Global:JsonPath+"Get-NcFpolicyScope.json") saved successfully"
                    }else{
                        Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcFpolicyScope.json")"
                        $Return=$False
                    }
                }
                if($PrimaryFpolScope -eq $null) {$Return = $Fale ; Write-LogWarn "Missing Fpolicy Scope on Primary Vserver"; continue}
                if($Backup -eq $False){
                    $PrimaryFpolScopeCheckExtensionsOnDirectories=$PrimaryFpolScope.CheckExtensionsOnDirectories
                    $PrimaryFpolScopeExportPoliciesToExclude=$PrimaryFpolScope.ExportPoliciesToExclude
                    $PrimaryFpolScopeExportPoliciesToInclude=$PrimaryFpolScope.ExportPoliciesToInclude
                    $PrimaryFpolScopeFileExtensionsToExclude=$PrimaryFpolScope.FileExtensionsToExclude
                    $PrimaryFpolScopeFileExtensionsToInclude=$PrimaryFpolScope.FileExtensionsToInclude
                    $PrimaryFpolScopeSharesToExclude=$PrimaryFpolScope.SharesToExclude
                    $PrimaryFpolScopeSharesToInclude=$PrimaryFpolScope.SharesToInclude
                    $PrimaryFpolScopeVolumesToExclude=$PrimaryFpolScope.VolumesToExclude
                    $PrimaryFpolScopeVolumesToInclude=$PrimaryFpolScope.VolumesToInclude

                    Write-LogDebug "Get-NcFpolicyScope -PolicyName $PrimaryFpolPolName -Vserver $mySecondaryVserver -Controller $mySecondaryController"
                    $SecondaryFpolScope=Get-NcFpolicyScope -PolicyName $PrimaryFpolPolName -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcFpolicyScope failed [$ErrorVar]" }
                    if($SecondaryFpolScope -ne $null)
                    {
                        Write-Log "[$workOn] Modify Fpolicy Scope [$workOn]"
                        $SecondaryFpolScopeCheckExtensionsOnDirectories=$SecondaryFpolScope.CheckExtensionsOnDirectories
                        $SecondaryFpolScopeExportPoliciesToExclude=$SecondaryFpolScope.ExportPoliciesToExclude
                        $SecondaryFpolScopeExportPoliciesToInclude=$SecondaryFpolScope.ExportPoliciesToInclude
                        $SecondaryFpolScopeFileExtensionsToExclude=$SecondaryFpolScope.FileExtensionsToExclude
                        $SecondaryFpolScopeFileExtensionsToInclude=$SecondaryFpolScope.FileExtensionsToInclude
                        $SecondaryFpolScopeSharesToExclude=$SecondaryFpolScope.SharesToExclude
                        $SecondaryFpolScopeSharesToInclude=$SecondaryFpolScope.SharesToInclude
                        $SecondaryFpolScopeVolumesToExclude=$SecondaryFpolScope.VolumesToExclude
                        $SecondaryFpolScopeVolumesToInclude=$SecondaryFpolScope.VolumesToInclude

                        if( ($PrimaryFpolScope.CheckExtensionsOnDirectories -ne $SecondaryFpolScope.CheckExtensionsOnDirectories) `
                            -or ($PrimaryFpolScope.ExportPoliciesToExclude -ne $SecondaryFpolScope.ExportPoliciesToExclude) `
                            -or ($PrimaryFpolScope.ExportPoliciesToInclude -ne $SecondaryFpolScope.ExportPoliciesToInclude) `
                            -or ($PrimaryFpolScope.FileExtensionsToExclude -ne $SecondaryFpolScope.FileExtensionsToExclude) `
                            -or ($PrimaryFpolScope.FileExtensionsToInclude -ne $SecondaryFpolScope.FileExtensionsToInclude) `
                            -or ($PrimaryFpolScope.SharesToExclude -ne $SecondaryFpolScope.SharesToExclude) `
                            -or ($PrimaryFpolScope.SharesToInclude -ne $SecondaryFpolScope.SharesToInclude) `
                            -or ($PrimaryFpolScope.VolumesToExclude -ne $SecondaryFpolScope.VolumesToExclude) `
                            -or ($PrimaryFpolScope.VolumesToInclude -ne $SecondaryFpolScope.VolumesToInclude) )
                            {
                                Write-LogDebug "Set-NcFpolicyScope -PolicyName $PrimaryFpolPolName -SharesToInclude $PrimaryFpolScopeSharesToInclude `
                                -SharesToExclude $PrimaryFpolScopeSharesToExclude -VolumesToInclude $PrimaryFpolScopeVolumesToInclude `
                                -VolumesToExclude $PrimaryFpolScopeVolumesToExclude -ExportPoliciesToInclude $PrimaryFpolScopeExportPoliciesToInclude `
                                -ExportPoliciesToExclude $PrimaryFpolScopeExportPoliciesToExclude -FileExtensionsToInclude $PrimaryFpolScopeFileExtensionsToInclude `
                                -FileExtensionsToExclude $PrimaryFpolScopeFileExtensionsToExclude -CheckExtensionsOnDirectories $PrimaryFpolScopeCheckExtensionsOnDirectories `
                                -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                                $out=Set-NcFpolicyScope -PolicyName $PrimaryFpolPolName -SharesToInclude $PrimaryFpolScopeSharesToInclude `
                                -SharesToExclude $PrimaryFpolScopeSharesToExclude -VolumesToInclude $PrimaryFpolScopeVolumesToInclude `
                                -VolumesToExclude $PrimaryFpolScopeVolumesToExclude -ExportPoliciesToInclude $PrimaryFpolScopeExportPoliciesToInclude `
                                -ExportPoliciesToExclude $PrimaryFpolScopeExportPoliciesToExclude -FileExtensionsToInclude $PrimaryFpolScopeFileExtensionsToInclude `
                                -FileExtensionsToExclude $PrimaryFpolScopeFileExtensionsToExclude -CheckExtensionsOnDirectories $PrimaryFpolScopeCheckExtensionsOnDirectories `
                                -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcFpolicyScope failed [$ErrorVar]" } 
                            }
                    }
                    else
                    {
                        Write-Log "[$workOn] Create Fpolicy Scope on Secondary Vserver [$workOn]"
                        if($PrimaryFpolScopeCheckExtensionsOnDirectories -eq $True)
                        {
                            Write-LogDebug "New-NcFpolicyScope -PolicyName $PrimaryFpolPolName -SharesToInclude $PrimaryFpolScopeSharesToInclude `
                            -SharesToExclude $PrimaryFpolScopeSharesToExclude -VolumesToInclude $PrimaryFpolScopeVolumesToInclude `
                            -VolumesToExclude $PrimaryFpolScopeVolumesToExclude -ExportPoliciesToInclude $PrimaryFpolScopeExportPoliciesToInclude `
                            -ExportPoliciesToExclude $PrimaryFpolScopeExportPoliciesToExclude -FileExtensionsToInclude $PrimaryFpolScopeFileExtensionsToInclude `
                            -FileExtensionsToExclude $PrimaryFpolScopeFileExtensionsToExclude -CheckExtensionsOnDirectories `
                            -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                            $out=New-NcFpolicyScope -PolicyName $PrimaryFpolPolName -SharesToInclude $PrimaryFpolScopeSharesToInclude `
                            -SharesToExclude $PrimaryFpolScopeSharesToExclude -VolumesToInclude $PrimaryFpolScopeVolumesToInclude `
                            -VolumesToExclude $PrimaryFpolScopeVolumesToExclude -ExportPoliciesToInclude $PrimaryFpolScopeExportPoliciesToInclude `
                            -ExportPoliciesToExclude $PrimaryFpolScopeExportPoliciesToExclude -FileExtensionsToInclude $PrimaryFpolScopeFileExtensionsToInclude `
                            -FileExtensionsToExclude $PrimaryFpolScopeFileExtensionsToExclude -CheckExtensionsOnDirectories `
                            -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcFpolicyScope failed [$ErrorVar]" }
                        }
                        else
                        {
                            Write-LogDebug "New-NcFpolicyScope -PolicyName $PrimaryFpolPolName -SharesToInclude $PrimaryFpolScopeSharesToInclude `
                            -SharesToExclude $PrimaryFpolScopeSharesToExclude -VolumesToInclude $PrimaryFpolScopeVolumesToInclude `
                            -VolumesToExclude $PrimaryFpolScopeVolumesToExclude -ExportPoliciesToInclude $PrimaryFpolScopeExportPoliciesToInclude `
                            -ExportPoliciesToExclude $PrimaryFpolScopeExportPoliciesToExclude -FileExtensionsToInclude $PrimaryFpolScopeFileExtensionsToInclude `
                            -FileExtensionsToExclude $PrimaryFpolScopeFileExtensionsToExclude `
                            -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                            $out=New-NcFpolicyScope -PolicyName $PrimaryFpolPolName -SharesToInclude $PrimaryFpolScopeSharesToInclude `
                            -SharesToExclude $PrimaryFpolScopeSharesToExclude -VolumesToInclude $PrimaryFpolScopeVolumesToInclude `
                            -VolumesToExclude $PrimaryFpolScopeVolumesToExclude -ExportPoliciesToInclude $PrimaryFpolScopeExportPoliciesToInclude `
                            -ExportPoliciesToExclude $PrimaryFpolScopeExportPoliciesToExclude -FileExtensionsToInclude $PrimaryFpolScopeFileExtensionsToInclude `
                            -FileExtensionsToExclude $PrimaryFpolScopeFileExtensionsToExclude `
                            -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcFpolicyScope failed [$ErrorVar]" }    
                        }
                    }
                }
                if($Restore -eq $False){
                    # add code to get/enable Fpolicy
                    Write-LogDebug "Get-NcFpolicyStatus -Name $PrimaryFpolPolName -Vserver $myPrimaryVserver -Controller $myPrimaryController"
                    $PrimaryFpolStatus=Get-NcFpolicyStatus -Name $PrimaryFpolPolName -Vserver $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcFpolicyScope failed [$ErrorVar]" }
                }else{
                    if(Test-Path $($Global:JsonPath+"Get-NcFpolicyStatus.json")){
                        $PrimaryFpolStatus=Get-Content $($Global:JsonPath+"Get-NcFpolicyStatus.json") | ConvertFrom-Json
                    }else{
                        $Return=$False
                        $filepath=$($Global:JsonPath+"Get-NcFpolicyStatus.json")
                        Throw "ERROR: failed to read $filepath"
                    }
                }
                if($Backup -eq $True){
                    $PrimaryFpolStatus | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcFpolicyStatus.json") -Encoding ASCII -Width 65535
                    if( ($ret=get-item $($Global:JsonPath+"Get-NcFpolicyStatus.json") -ErrorAction SilentlyContinue) -ne $null ){
                        Write-LogDebug "$($Global:JsonPath+"Get-NcFpolicyStatus.json") saved successfully"
                    }else{
                        Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcFpolicyStatus.json")"
                        $Return=$False
                    }
                }
                if ($PrimaryFpolStatus -eq $null) {$Return = $Fale ; Write-LogWarn "Missing Fpolicy on Primary Vserver"; continue}
                $PrimaryFpolStatusEnabled=$PrimaryFpolStatus.Enabled
                $PrimaryFpolStatusSequenceNumber=$PrimaryFpolStatus.SequenceNumber
                if($Backup -eq $False){
                    Write-LogDebug "Get-NcFpolicyStatus -Name $PrimaryFpolPolName -Vserver $mySecondaryVserver -Controller $mySecondaryController"
                    $SecondaryFpolStatus=Get-NcFpolicyStatus -Name $PrimaryFpolPolName -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcFpolicyScope failed [$ErrorVar]" }
                    $SecondaryFpolStatusEnabled=$SecondaryFpolStatus.Enabled
                    $SecondaryFpolStatusSequenceNumber=$SecondaryFpolStatus.SequenceNumber
                    if ($PrimaryFpolStatusEnabled -ne $SecondaryFpolStatusEnabled)
                    {
                        if($PrimaryFpolStatusEnabled -eq $True)
                        {
                            Write-Log "[$workOn] Enable Fpolicy [$PrimaryFpolPolName]"
                            Write-LogDebug "Enable-NcFpolicyPolicy -Name $PrimaryFpolPolName -SequenceNumber $PrimaryFpolStatusSequenceNumber -VserverContext $mySecondaryVserver `
                            -Controller $mySecondaryController"
                            $out=Enable-NcFpolicyPolicy -Name $PrimaryFpolPolName -SequenceNumber $PrimaryFpolStatusSequenceNumber -VserverContext $mySecondaryVserver `
                            -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Enable-NcFpolicyPolicy failed [$ErrorVar]" }
                        }
                        else
                        {
                            Write-Log "[$workOn] Disable Fpolicy [$PrimaryFpolPolName]"
                            Write-LogDebug "Disable-NcFpolicyPolicy -Name $PrimaryFpolPolName -VserverContext $mySecondaryVserver `
                            -Controller $mySecondaryController"
                            $out=Disable-NcFpolicyPolicy -Name $PrimaryFpolPolName -VserverContext $mySecondaryVserver `
                            -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Enable-NcFpolicyPolicy failed [$ErrorVar]" }
                        }
                    }
                }
            }
        }
        Write-LogDebug "create_update_fpolicy_dr[$myPrimaryVserver]: end"
        return $Return
    }
    catch
    {
        handle_error $_ $myPrimaryVserver
        return $Return        
    }
}

#############################################################################################
# create_update_qospolicy_dr
Function create_update_qospolicy_dr(
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string] $workOn=$mySecondaryVserver,
    [bool] $Backup,
    [bool] $Restore,
    [switch] $ForClone) 
{
    Try 
    {
        $Return=$True
        Write-Log "[$workOn] Check SVM QOS configuration"
        Write-LogDebug "create_update_qospolicy_dr[$myPrimaryVserver]: start"
        if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
        if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}
        
        if($Restore -eq $False){
            Write-LogDebug "Get-NcQosPolicyGroup -Vserver $myPrimaryVserver -Controller $myPrimaryController"
            $PrimaryQosGroupList=Get-NcQosPolicyGroup -Vserver $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcQosPolicyGroup failed [$ErrorVar]" }
        }else{
            if(Test-Path $($Global:JsonPath+"Get-NcQosPolicyGroup.json")){
                $PrimaryQosGroupList=Get-Content $($Global:JsonPath+"Get-NcQosPolicyGroup.json") | ConvertFrom-Json
            }else{
                $Return=$False
                $filepath=$($Global:JsonPath+"Get-NcQosPolicyGroup.json")
                Throw "ERROR: failed to read $filepath"
            }
        }
        if($Backup -eq $True){
            $PrimaryQosGroupList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcQosPolicyGroup.json") -Encoding ASCII -Width 65535
            if( ($ret=get-item $($Global:JsonPath+"Get-NcQosPolicyGroup.json") -ErrorAction SilentlyContinue) -ne $null ){
                Write-LogDebug "$($Global:JsonPath+"Get-NcQosPolicyGroup.json") saved successfully"
            }else{
                Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcQosPolicyGroup.json")"
                $Return=$False
            }
        }
        if($Backup -eq $False){
            foreach ( $PrimaryQosGroup in ( $PrimaryQosGroupList | Skip-Null ) ) {
                $PrimaryQosGroupName=$PrimaryQosGroup.PolicyGroup
                $PrimaryQosGroupMaxThroughput=$PrimaryQosGroup.MaxThroughput
                $PrimaryQosGroupMinThroughput=$PrimaryQosGroup.MinThroughput
                Write-LogDebug "Get-NcQosPolicyGroup -Vserver $mySecondaryVserver -Controller $mySecondaryController"
                $SecondaryQosGroup=Get-NcQosPolicyGroup -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar    
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcQosPolicyGroup failed [$ErrorVar]" }
                if($SecondaryQosGroup -ne $null)
                {
                    $SecondaryQosGroupMaxThroughput=$SecondaryQosGroup.MaxThroughput
                    $SecondaryQosGroupMinThroughput=$SecondaryQosGroup.MinThroughput
                    if( ($PrimaryQosGroupMaxThroughput -ne $SecondaryQosGroupMaxThroughput) -or ($PrimaryQosGroupMinThroughput -ne $SecondaryQosGroupMinThroughput) )
                    {
                        if($ForClone -eq $True){
                            $QosPolicyGroupName=$PrimaryQosGroupName+"_"+($mySecondaryVserver -replace "\.","_")
                            Write-Log "[$workOn] Update QOS Policy Group [$QosPolicyGroupName]"
                            Write-LogDebug "Set-NcQosPolicyGroup -Name $QosPolicyGroupName -MaxThroughput $PrimaryQosGroupMaxThroughput -MinTroughput $PrimaryQosGroupMinThroughput -controller $mySecondaryController"
                            $out=Set-NcQosPolicyGroup -Name $QosPolicyGroupName -MaxThroughput $PrimaryQosGroupMaxThroughput -MinTroughput $PrimaryQosGroupMinThroughput -controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcQosPolicyGroup failed [$ErrorVar]" }
                        }else{
                            if($SINGLE_CLUSTER -eq $True)
                            {
                                Write-Log "[$workOn] Update QOS Policy Group [$PrimaryQosGroupName`_$workOn]"
                                Write-LogDebug "Set-NcQosPolicyGroup -Name $PrimaryQosGroupName`_$mySecondaryVserver -MaxThroughput $PrimaryQosGroupMaxThroughput -MinTroughput $PrimaryQosGroupMinThroughput -controller $mySecondaryController"
                                $out=Set-NcQosPolicyGroup -Name $($PrimaryQosGroupName+"_"+$mySecondaryVserver) -MaxThroughput $PrimaryQosGroupMaxThroughput -MinTroughput $PrimaryQosGroupMinThroughput -controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcQosPolicyGroup failed [$ErrorVar]" }
                            }
                            else
                            {
                                Write-Log "[$workOn] Update QOS Policy Group [$PrimaryQosGroupName]"
                                Write-LogDebug "Set-NcQosPolicyGroup -Name $PrimaryQosGroupName -MaxThroughput $PrimaryQosGroupMaxThroughput -MinTroughput $PrimaryQosGroupMinThroughput -controller $mySecondaryController"
                                $out=Set-NcQosPolicyGroup -Name $PrimaryQosGroupName -MaxThroughput $PrimaryQosGroupMaxThroughput -MinTroughput $PrimaryQosGroupMinThroughput -controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcQosPolicyGroup failed [$ErrorVar]" }
                            }
                        }
                    }
                }
                else
                {
                    if($ForClone -eq $True){
                        $QosPolicyGroupName=$PrimaryQosGroupName+"_"+($mySecondaryVserver -replace "\.","_")
                        Write-Log "[$workOn] Create QOS Policy Group [$QosPolicyGroupName]" 
                        Write-LogDebug "New-NcQosPolicyGroup -Name $QosPolicyGroupName -Vserver $mySecondaryVserver -MaxThroughput $PrimaryQosGroupMaxThroughput -controller $mySecondaryController"
                        $out=New-NcQosPolicyGroup -Name $QosPolicyGroupName -Vserver $mySecondaryVserver -MaxThroughput $PrimaryQosGroupMaxThroughput -controller $mySecondaryController  -ErrorVariable ErrorVar 
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcQosPolicyGroup failed [$ErrorVar]" }
                    }else{
                        if($SINGLE_CLUSTER -eq $True)
                        {
                            Write-Log "[$workOn] Create QOS Policy Group [$PrimaryQosGroupName`_$workOn]" 
                            Write-LogDebug "New-NcQosPolicyGroup -Name $PrimaryQosGroupName`_$mySecondaryVserver -Vserver $mySecondaryVserver -MaxThroughput $PrimaryQosGroupMaxThroughput -controller $mySecondaryController"
                            $out=New-NcQosPolicyGroup -Name $($PrimaryQosGroupName+"_"+$mySecondaryVserver) -Vserver $mySecondaryVserver -MaxThroughput $PrimaryQosGroupMaxThroughput -controller $mySecondaryController  -ErrorVariable ErrorVar 
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcQosPolicyGroup failed [$ErrorVar]" }
                        }
                        else
                        {
                            Write-Log "[$workOn] Create QOS Policy Group [$PrimaryQosGroupName]" 
                            Write-LogDebug "New-NcQosPolicyGroup -Name $PrimaryQosGroupName -Vserver $mySecondaryVserver -MaxThroughput $PrimaryQosGroupMaxThroughput -controller $mySecondaryController"
                            $out=New-NcQosPolicyGroup -Name $PrimaryQosGroupName -Vserver $mySecondaryVserver -MaxThroughput $PrimaryQosGroupMaxThroughput -controller $mySecondaryController  -ErrorVariable ErrorVar 
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcQosPolicyGroup failed [$ErrorVar]" }
                        }
                    }
                }
            }
        }
        if($Restore -eq $False){
            Write-LogDebug "Get-NcVserver -Name $myPrimaryVserver -Controller $myPrimaryController"
            $PrimaryQosPolicyGroupOnSVM=(Get-NcVserver -Name $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar).QosPolicyGroup
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" }
        }else{
            if(Test-Path $($Global:JsonPath+"Get-NcVserver.json")){
                $PrimaryQosPolicyGroupOnSVM=Get-Content $($Global:JsonPath+"Get-NcVserver.json") | ConvertFrom-Json
                $PrimaryQosPolicyGroupOnSVM=$PrimaryQosPolicyGroupOnSVM.QosPolicyGroup
            }else{
                $Return=$False
                $filepath=$($Global:JsonPath+"Get-NcVserver.json")
                Throw "ERROR: failed to read $filepath"
            }    
        }
        if($PrimaryQosPolicyGroupOnSVM -ne $null)
        {
            if($Backup -eq $False){
                Write-LogDebug "Get-NcVserver -Name $mySecondaryVserver -Controller $mySecondaryController"
                $SecondaryQosPolicyGroupOnSVM=(Get-NcVserver -Name $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar).QosPolicyGroup
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" }
                if($ForClone -eq $True){
                    $QosPolicyGroupName=$PrimaryQosGroupName+"_"+($mySecondaryVserver -replace "\.","_")
                    Write-logDebug "Set-NcVserver -name $mySecondaryVserver -QOsPolicyGroup $QosPolicyGroupName -Controller $mySecondaryController"
                    $out=Set-NcVserver -Name $mySecondaryVserver -QOsPolicyGroup $QosPolicyGroupName -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcVserver failed [$ErrorVar]" }     
                }else{
                    if($SINGLE_CLUSTER -eq $True)
                    {
                        $SecondaryQosPolicyGroupOnSVM=$SecondaryQosPolicyGroupOnSVM -replace "$mySecondaryVserver",""
                        if($PrimaryQosPolicyGroupOnSVM -ne $SecondaryQosPolicyGroupOnSVM)
                        {
                            Write-logDebug "Set-NcVserver -name $mySecondaryVserver -QOsPolicyGroup $PrimaryQosPolicyGroupOnSVM`_$mySecondaryVserver -Controller $mySecondaryController"
                            $out=Set-NcVserver -Name $mySecondaryVserver -QOsPolicyGroup $($PrimaryQosPolicyGroupOnSVM+"_"+$mySecondaryVserver) -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcVserver failed [$ErrorVar]" }  
                        }
                    }
                    else
                    {
                        if($PrimaryQosPolicyGroupOnSVM -ne $SecondaryQosPolicyGroupOnSVM)
                        {
                            Write-logDebug "Set-NcVserver -name $mySecondaryVserver -QOsPolicyGroup $PrimaryQosPolicyGroupOnSVM -Controller $mySecondaryController"
                            $out=Set-NcVserver -Name $mySecondaryVserver -QOsPolicyGroup $PrimaryQosPolicyGroupOnSVM -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcVserver failed [$ErrorVar]" }  
                        }
                    }
                }
            }
        }
        else 
        {
            if($Global:SelectVolume -eq $True)
            {
                $Selected=get_volumes_from_selectvolumedb $myPrimaryController $myPrimaryVserver
                if($Selected.state -ne $True)
                {
                    Write-Log "[$workOn] Failed to get Selected Volume from DB, check selectvolume.db file inside $Global:SVMTOOL_DB"
                    Write-logDebug "check_update_voldr: end with error"
                    return $False  
                }else{
                    $VolList=$Selected.volumes
                    Write-LogDebug "Get-NcVol -Name $VolList -Vserver $myPrimaryVserver -Controller $myPrimaryController"
                    $PrimaryVolList=Get-NcVol -Name $VolList -Vserver $myPrimaryVserver -Controller $myPrimaryController -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
                }    
            }else{
                if($Restore -eq $False){
                    $PrimaryVolList = Get-NcVol -Controller $myPrimaryController -Vserver $myPrimaryVserver -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" } 
                }else{
                    if(Test-Path $($Global:JsonPath+"Get-NcVol.json")){
                        $PrimaryVolList=Get-Content $($Global:JsonPath+"Get-NcVol.json") | ConvertFrom-Json
                    }else{
                        $Return=$False
                        $filepath=$($Global:JsonPath+"Get-NcVol.json")
                        Throw "ERROR: failed to read $filepath"
                    }
                } 
            }
            if($Backup -eq $False){
                $PrimaryVolWithQosList=$PrimaryVolList | Where-Object {$_.VolumeQosAttributes.PolicyGroupName -ne $null}
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
                foreach ( $PrimaryVolWithQos in ( $PrimaryVolWithQosList | Skip-Null ) ) {
                    $PrimaryVolName=$PrimaryVolWithQos.Name
                    $PrimaryVolQosName=$PrimaryVolWithQos.VolumeQosAttributes.PolicyGroupName
                    Write-LogDebug "Get-NcVol -Name $PrimaryVolName -Vserver $mySecondaryVserver -controller $mySecondaryController"
                    $mySecondaryVol=Get-NcVol -Name $PrimaryVolName -Vserver $mySecondaryVserver -controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
                    $mySecondaryVolQosName=$mySecondaryVol.VolumeQosAttributes.PolicyGroupName
                    if($ForClone -eq $True){
                        $QosPolicyGroupName=$PrimaryVolQosName+"_"+($mySecondaryVserver -replace "\.","_")
                        if($QosPolicyGroupName -ne $mySecondaryVolQosName)
                        {
                            Write-log "[$workOn] Update Qos Policy Group name [$QosPolicyGroupName] for volume [$PrimaryVolName]"
                            Write-LogDebug "Get-NcVol -Template -controller $mySecondaryController"
                            $query=Get-NcVol -Template -controller $mySecondaryController  -ErrorVariable ErrorVar 
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
                            $query.Name=$PrimaryVolName
                            $query.Vserver=$mySecondaryVserver
                            Write-LogDebug "Get-NcVol -Template -controller $mySecondaryController"
                            $attributes=Get-NcVol -Template -controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
                            Initialize-NcObjectProperty $attributes VolumeQosAttributes
                            $attributes.VolumeQosAttributes.PolicyGroupName=$QosPolicyGroupName
                            Write-LogDebug "Update-NcVol -Query `$query -Attributes `$attributes -controller $mySecondaryController"
                            $out=Update-NcVol -Query $query -Attributes $attributes -controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Update-NcVol failed [$ErrorVar]" }
                        }   
                    }else{
                        if($SINGLE_CLUSTER -eq $True)
                        {
                            $mySecondaryVolQosName=$mySecondaryVolQosName -replace "$mySecondaryVserver",""
                            if($PrimaryVolQosName -ne $mySecondaryVolQosName)
                            {
                                Write-log "[$workOn] Update Qos Policy Group name [$PrimaryVolQosName`_$workOn] for volume [$PrimaryVolName]"
                                Write-LogDebug "Get-NcVol -Template -controller $mySecondaryController"
                                $query=Get-NcVol -Template -controller $mySecondaryController  -ErrorVariable ErrorVar 
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
                                $query.Name=$PrimaryVolName
                                $query.Vserver=$mySecondaryVserver
                                Write-LogDebug "Get-NcVol -Template -controller $mySecondaryController"
                                $attributes=Get-NcVol -Template -controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
                                Initialize-NcObjectProperty $attributes VolumeQosAttributes
                                $attributes.VolumeQosAttributes.PolicyGroupName=$($PrimaryVolQosName+"_"+$mySecondaryVserver)
                                Write-LogDebug "Update-NcVol -Query `$query -Attributes `$attributes -controller $mySecondaryController"
                                $out=Update-NcVol -Query $query -Attributes $attributes -controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Update-NcVol failed [$ErrorVar]" }
                            }    
                        }
                        else
                        {
                            if($PrimaryVolQosName -ne $mySecondaryVolQosName)
                            {
                                Write-log "[$workOn] Update Qos Policy Group name [$PrimaryVolQosName] for volume [$PrimaryVolName]"
                                Write-LogDebug "Get-NcVol -Template -controller $mySecondaryController"
                                $query=Get-NcVol -Template -controller $mySecondaryController  -ErrorVariable ErrorVar 
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
                                $query.Name=$PrimaryVolName
                                $query.Vserver=$mySecondaryVserver
                                Write-LogDebug "Get-NcVol -Template -controller $mySecondaryController"
                                $attributes=Get-NcVol -Template -controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
                                Initialize-NcObjectProperty $attributes VolumeQosAttributes
                                $attributes.VolumeQosAttributes.PolicyGroupName=$PrimaryVolQosName
                                Write-LogDebug "Update-NcVol -Query `$query -Attributes `$attributes -controller $mySecondaryController"
                                $out=Update-NcVol -Query $query -Attributes $attributes -controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Update-NcVol failed [$ErrorVar]" }
                            }
                        }
                    }
                }
            }  
        }

        Write-LogDebug "create_update_qospolicy_dr[$myPrimaryVserver]: end"
        return $Return
    }
    catch
    {
        handle_error $_ $myPrimaryVserver
        return $Return        
    }
}
#############################################################################################
# create_update_cron_dr
Function create_update_cron_dr(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [bool]$Backup,
    [bool]$Restore) {
Try {
    $Return = $True 
    if($Backup -eq $False -and $Restore -eq $False){
        $ctrlName=$myPrimaryController.Name    
    }
    if($Backup -eq $True){
        $ctrlName=$myPrimaryController.Name
        Write-LogDebug "run in Backup mode [$ctrlName]"
    }
    if($Restore -eq $True){
        $ctrlName=$mySecondaryController.Name
        Write-LogDebug "run in Restore mode [$ctrlName]"
    }
    Write-LogDebug "create_update_cron_dr[$ctrlName]: start"
    Write-Log "[$ctrlName] Check Cluster Cron configuration"
    if($Restore -eq $False){
        $PrimaryCronList = Get-NcJobCronSchedule -Controller $myPrimaryController -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcJobCronSchedule failed [$ErrorVar]" }
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcJobCronSchedule.json")){
            $PrimaryCronList=Get-Content $($Global:JsonPath+"Get-NcJobCronSchedule.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcJobCronSchedule.json")
            Throw "ERROR: failed to read $filepath"
        }
    }
    if($Backup -eq $True){
        $PrimaryCronList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcJobCronSchedule.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcJobCronSchedule.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcJobCronSchedule.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcJobCronSchedule.json")"
            $Return=$False
        }
    }
    if($Backup -eq $False){
        foreach ( $Cron in ( $PrimaryCronList | Skip-Null ) ) {
            $PrimaryJobScheduleName = $Cron.JobScheduleName
            $PrimaryJobScheduleDescription = $Cron.JobScheduleDescription
            $PrimaryJobScheduleCronMonth = $Cron.JobScheduleCronMonth
            $PrimaryJobScheduleCronDayOfWeek = $Cron.JobScheduleCronDayOfWeek
            $PrimaryJobScheduleCronDay = $Cron.JobScheduleCronDay
            $PrimaryJobScheduleCronHour = $Cron.JobScheduleCronHour
            $PrimaryJobScheduleCronMinute = $Cron.JobScheduleCronMinute
            $SecondaryCron = Get-NcJobCronSchedule -Name $PrimaryJobScheduleName -Controller $mySecondaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcJobCronSchedule failed [$ErrorVar]" }
            if ( $SecondaryCron -ne $null ) {
                $SecondaryJobScheduleName = $Cron.JobScheduleName
                $SecondaryJobScheduleDescription = $Cron.JobScheduleDescription
                if ( $PrimaryJobScheduleDescription -ne $SecondaryJobScheduleDescription ) {
                    Write-LogDebug "Set-NcJobCronSchedule -Controller $mySecondaryController -Name $PrimaryJobScheduleName -Month $PrimaryJobScheduleCronMonth -Day $PrimaryJobScheduleCronDay -DayOfWeek $PrimaryJobScheduleCronDayOfWeek -Hour $PrimaryJobScheduleCronHour -Minute $PrimaryJobScheduleCronMinute  -ErrorVariable ErrorVar"
                    $out=Set-NcJobCronSchedule -Controller $mySecondaryController -Name $PrimaryJobScheduleName -Month $PrimaryJobScheduleCronMonth -Day $PrimaryJobScheduleCronDay -DayOfWeek $PrimaryJobScheduleCronDayOfWeek -Hour $PrimaryJobScheduleCronHour -Minute $PrimaryJobScheduleCronMinute  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcJobCronSchedule failed [$ErrorVar]" }
                }
            } else {
                Write-LogDebug "Set-AddJobCronSchedule -Controller $mySecondaryController -Name $PrimaryJobScheduleName -Month $PrimaryJobScheduleCronMonth -Day $PrimaryJobScheduleCronDay -DayOfWeek $PrimaryJobScheduleCronDayOfWeek -Hour $PrimaryJobScheduleCronHour -Minute $PrimaryJobScheduleCronMinute  -ErrorVariable ErrorVar"
                $out=Add-NcJobCronSchedule -Controller $mySecondaryController -Name $PrimaryJobScheduleName -Month $PrimaryJobScheduleCronMonth -Day $PrimaryJobScheduleCronDay -DayOfWeek $PrimaryJobScheduleCronDayOfWeek -Hour $PrimaryJobScheduleCronHour -Minute $PrimaryJobScheduleCronMinute  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcJobCronSchedule failed [$ErrorVar]" }
            }
        }
    }
    Write-LogDebug "create_update_cron_dr[$ctrlName]: end"
	return $Return
}
Catch {
	handle_error $_ $ctrlName
	return $Return
}
}

#############################################################################################
# create_update_snap_policy_dr
Function create_update_snap_policy_dr(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore)
{
Try {
	$Return = $True 
    Write-Log "[$workOn] Check SVM Snapshot Policy"
    Write-LogDebug "create_update_snap_policy_dr[$myPrimaryVserver]: start"
    if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
    if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}
    
    if($SINGLE_CLUSTER -eq $True){
        Write-LogDebug "SINGLE_CLUSTER detected, no need to check snapshotpolicy and rules"
        Write-LogDebug "create_update_snap_policy_dr[$myPrimaryVserver]: end"
        return $Return
    }
	
    if($Global:SelectVolume -eq $True)
    {
        $Selected=get_volumes_from_selectvolumedb $myPrimaryController $myPrimaryVserver
        if($Selected.state -ne $True)
        {
            Write-Log "[$workOn] Failed to get Selected Volume from DB, check selectvolume.db file inside $Global:SVMTOOL_DB"
            Write-logDebug "create_update_snap_policy_dr: end with error"
            return $False  
        }else{
            $SelectedVolumes=$Selected.volumes
            Write-LogDebug "Get-NcVol -Name $SelectedVolumes -Vserver $myPrimaryVserver -Controller $myPrimaryController"
            $SnapShotPolicyListPerVol=Get-NcVol -Name $SnapShotPolicyListPerVol -Vserver $myPrimaryVserver -Controller $myPrimaryController -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
        }    
    }else{
        if($Restore -eq $False){
            Write-LogDebug "Get-NcVol -Vserver $myPrimaryVserver -Controller $myPrimaryController"
            $SnapShotPolicyListPerVol = Get-NcVol -Controller $myPrimaryController -Vserver $myPrimaryVserver -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }  
        }else{
            if(Test-Path $($Global:JsonPath+"Get-NcVol.json")){
                $SnapShotPolicyListPerVol=Get-Content $($Global:JsonPath+"Get-NcVol.json") | ConvertFrom-Json
            }else{
                $Return=$False
                $filepath=$($Global:JsonPath+"Get-NcVol.json")
                Throw "ERROR: failed to read $filepath"
            }
        }
    }
	
    $SnapShotPolicyListPerVol_string=$SnapShotPolicyListPerVol | Out-String
    Write-LogDebug "SnapShotPolicyListPerVol = $SnapShotPolicyListPerVol_string"
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
    $SnapShotPolicyListName = $SnapShotPolicyListPerVol | ForEach-Object {$_.VolumeSnapshotAttributes.SnapshotPolicy} | Sort-Object -Unique
    $SnapShotPolicyListName_string = $SnapShotPolicyListName | Out-String
    Write-LogDebug "SnapShotPolicyListName =  $SnapShotPolicyListName_string" 
    foreach ( $SnapShotPolicyName in ( $SnapshotPolicyListName | Skip-Null ) ) {
        if($SnapShotPolicyName -eq "none"){continue}
        if($Restore -eq $False){
            Write-LogDebug "Get-NcSnapshotPolicy -Name $SnapShotPolicyName -Controller $myPrimaryController"
            $snapShotPolicy=Get-NcSnapshotPolicy -Name $SnapShotPolicyName -Controller $myPrimaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapshotPolicy failed [$ErrorVar]" }
        }else{
            if(Test-Path $($Global:JsonPath+"Get-NcSnapshotPolicy.json")){
                $snapShotPolicy=Get-Content $($Global:JsonPath+"Get-NcSnapshotPolicy.json") | ConvertFrom-Json
            }else{
                $Return=$False
                $filepath=$($Global:JsonPath+"Get-NcSnapshotPolicy.json")
                Throw "ERROR: failed to read $filepath"
            }
        }
        if($Backup -eq $True){
            $snapShotPolicy | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcSnapshotPolicy.json") -Encoding ASCII -Width 65535
            if( ($ret=get-item $($Global:JsonPath+"Get-NcSnapshotPolicy.json") -ErrorAction SilentlyContinue) -ne $null ){
                Write-LogDebug "$($Global:JsonPath+"Get-NcSnapshotPolicy.json") saved successfully"
            }else{
                Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcSnapshotPolicy.json")"
                $Return=$False
            }
        }
        if($Backup -eq $False){
            $snapShotPolicy_string=$snapShotPolicy | Out-String
            Write-LogDebug "snapShotPolicy = $snapShotPolicy_string"
            $SnapshotPolicySchedules = $SnapShotPolicy.SnapshotPolicySchedules
            $PolicyName = $SnapShotPolicy.Policy
            $PolicyEnabled = $SnapShotPolicy.Enabled
            Write-LogDebug "Analyze SnapshotPolicy [$PolicyName]"
            Write-LogDebug "Get-NcSnapshotPolicy -Name $PolicyName -Controller $mySecondaryController"
            $SecondarySnapshotPolicy = Get-NcSnapshotPolicy -Name $PolicyName -Controller $mySecondaryController -ErrorVariable ErrorVar    
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapshotPolicy failed [$ErrorVar]" }
            if( $SecondarySnapshotPolicy -ne $null ) 
            {
                $SecondaryPolicyEnabled=$SecondarySnapshotPolicy.Enabled
                if($SecondaryPolicyEnabled -ne $PolicyEnabled){
                    Write-LogDebug "Set-NcSnapshotPolicy -Name $PolicyName -Controller $mySecondaryController -Enabled $PolicyEnabled"
                    $out=Set-NcSnapshotPolicy -Name $PolicyName -Controller $mySecondaryController -Enabled $PolicyEnabled  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcSnapshotPolicy failed [$ErrorVar]" }
                }
                $SecondarySnapshotPolicySchedule=$SecondarySnapshotPolicy.SnapshotPolicySchedules
                Write-LogDebug "Compare-Object $SnapshotPolicySchedules $SecondarySnapshotPolicySchedule -IncludeEqual -Property Schedule"
                $Results=Compare-Object $SnapshotPolicySchedules $SecondarySnapshotPolicySchedule -IncludeEqual -Property Schedule
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Compare-Object failed [$ErrorVar]" }
                foreach($Result in $Results | Sort-Object){
                    if($Result.SideIndicator -eq "=="){
                        # identique check le reste
                        $PrimarySched=$SnapshotPolicySchedules | Where-Object {$_.Schedule -eq $Result.Schedule}
                        $SecondarySched=$SecondarySnapshotPolicySchedule | Where-Object {$_.Schedule -eq $Result.Schedule}
                        Write-LogDebug "Compare-Object $PrimarySched $SecondarySched -Property Count,Prefix,SnapmirrorLabel"
                        $DetailResults=Compare-Object $PrimarySched $SecondarySched -Property Count,Prefix,SnapmirrorLabel
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Compare-Object failed [$ErrorVar]" }
                        foreach($Detail in $DetailResults | Sort-Object){
                            if(($Detail.SideIndicator -eq "=>") -or ($Detail.SideIndicator -eq "=>")){
                                # difference sur le secondaire alors on efface et on recree ce schedule sans aller dans le detail
                                $Schedule=$Result.Schedule
                                $Count=$PrimarySched.Count
                                $SnapmirrorLabel=$PrimarySched.SnapmirrorLabel
                                if($SnapmirrorLabel -eq "-"){$SnapmirrorLabel="`n"}
                                Write-Log "[$workOn] Modify schedule [$Schedule] in Policy [$PolicyName]"
                                Write-LogDebug "Set-NcSnapshotPolicySchedule -Name $PolicyName -Schedule $Schedule -Count $Count -SnapmirrorLabel $SnapmirrorLabel -Controller $mySecondaryController"
                                $out=Set-NcSnapshotPolicySchedule -Name $PolicyName -Schedule $Schedule -Count $Count -SnapmirrorLabel $SnapmirrorLabel -Controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Add-NcSnapshotPolicySchedule failed [$ErrorVar]" }
                            }
                        }
                    }
                    elseif($Result.SideIndicator -eq "=>"){
                        # schedule a supprimer du secondary
                        if($SecondarySnapshotPolicy.TotalSchedules -eq 1){
                            # suppression dernier schedule donc suppression policy
                            $Return=$False
                            Throw "This case should not exist : delete last schedule of a snapshot policy"
                        }
                        else{
                            $Schedule=$Result.Schedule
                            Write-LogDebug "Remove-NcSnapshotPolicySchedule -Name $PolicyName -Schedule $Schedule -Controller $mySecondaryController"
                            $out=Remove-NcSnapshotPolicySchedule -Name $PolicyName -Schedule $Schedule -Controller $mySecondaryController  -ErrorVariable ErrorVar   
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Remove-NcSnapshotPolicySchedule failed [$ErrorVar]" }
                        }
                    }
                    else{
                        # schedule a ajouter sur le secondary
                        $PrimarySchedule=$SnapshotPolicySchedules | Where-Object {$_.Schedule -eq $Result.Schedule}
                        if($PrimarySchedule -eq $null){ $Return = $False ; throw "ERROR: Compare-Object failed [$ErrorVar]" }
                        $Schedule=$PrimarySchedule.Schedule
                        $Count=$PrimarySchedule.Count
                        $Prefix=$PrimarySchedule.Prefix
                        $SnapmirrorLabel=$PrimarySchedule.SnapmirrorLabel
                        Write-Log "[$workOn] Add new schedule [$Schedule] in Policy [$PolicyName]"
                        Write-LogDebug "Add-NcSnapshotPolicySchedule -Name $PolicyName -Schedule $Schedule -Count $Count -Prefix $Prefix -SnapmirrorLabel $SnapmirrorLabel -Controller $mySecondaryController"
                        $out=Add-NcSnapshotPolicySchedule -Name $PolicyName -Schedule $Schedule -Count $Count -Prefix $Prefix -SnapmirrorLabel $SnapmirrorLabel -Controller $mySecondaryController  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Add-NcSnapshotPolicySchedule failed [$ErrorVar]" }
                    }
                } 	
            }
            else # add new policy
            {
                Write-Log "[$workOn] Policy [$PolicyName] does not exist"
                Write-Log "[$workOn] Create Policy and associated rules"
                $firstSchedule=0
                foreach($SnapshotPolicySchedule in $SnapshotPolicySchedules)
                {
                    $Schedule=$SnapshotPolicySchedule.Schedule
                    $Count=$SnapshotPolicySchedule.Count
                    $Prefix=$SnapshotPolicySchedule.Prefix
                    $SnapmirrorLabel=$SnapshotPolicySchedule.SnapmirrorLabel
                    if($firstSchedule -eq 0){
                        if($SnapmirrorLabel -ne "-"){
                            Write-LogDebug "New-NcSnapshotPolicy -Name $PolicyName -Schedule $Schedule -Count $Count -Prefix $Prefix -Enabled $PolicyEnabled -SnapmirrorLabel $SnapmirrorLabel -Controller $mySecondaryController"
                            $out=New-NcSnapshotPolicy -Name $PolicyName -Schedule $Schedule -Count $Count -Prefix $Prefix -Enabled $PolicyEnabled -SnapmirrorLabel $SnapmirrorLabel -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcSnapshotPolicy failed [$ErrorVar]" }
                        }else{
                            Write-LogDebug "New-NcSnapshotPolicy -Name $PolicyName -Schedule $Schedule -Count $Count -Prefix $Prefix -Enabled $PolicyEnabled -SnapmirrorLabel \`n -Controller $mySecondaryController"
                            $out=New-NcSnapshotPolicy -Name $PolicyName -Schedule $Schedule -Count $Count -Prefix $Prefix -Enabled $PolicyEnabled -SnapmirrorLabel `n -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcSnapshotPolicy failed [$ErrorVar]" }
                        }
                        $firstSchedule++
                    }
                    else{
                        if($SnapmirrorLabel -ne "-"){
                            Write-LogDebug "Add-NcSnapshotPolicySchedule -Name $PolicyName -Schedule $Schedule -Count $Count -Prefix $Prefix -SnapmirrorLabel $SnapmirrorLabel -Controller $mySecondaryController"
                            $out=Add-NcSnapshotPolicySchedule -Name $PolicyName -Schedule $Schedule -Count $Count -Prefix $Prefix -SnapmirrorLabel $SnapmirrorLabel -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Add-NcSnapshotPolicySchedule failed [$ErrorVar]" }
                        }else{
                            Write-LogDebug "Add-NcSnapshotPolicySchedule -Name $PolicyName -Schedule $Schedule -Count $Count -Prefix $Prefix -SnapmirrorLabel \`n -Controller $mySecondaryController"
                            $out=Add-NcSnapshotPolicySchedule -Name $PolicyName -Schedule $Schedule -Count $Count -Prefix $Prefix -SnapmirrorLabel `n -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Add-NcSnapshotPolicySchedule failed [$ErrorVar]" }
                        }
                    }
                }
                
            }
        }
	}
    Write-LogDebug "create_update_snap_policy_dr[$myPrimaryVserver]: end"
	return $Return
}
Catch {
	handle_error $_ $myPrimaryVserver
	return $Return
}
}
#############################################################################################
# create_update_efficiency_policy_dr
Function create_update_efficiency_policy_dr(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) 
{
    Try 
    {
        $Return = $True 
        Write-Log "[$workOn] Check SVM Efficiency Policy"
        Write-LogDebug "create_update_efficiency_policy_dr[$myPrimaryVserver]: start"
        if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
        if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}
    
        if($Restore -eq $False){
	        $SisPolicyList = Get-NcSisPolicy -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSisPolicy failed [$ErrorVar]" }
        }else{
            if(Test-Path $($Global:JsonPath+"Get-NcSisPolicy.json")){
                $SisPolicyList=Get-Content $($Global:JsonPath+"Get-NcSisPolicy.json") | ConvertFrom-Json
            }else{
                $Return=$False
                $filepath=$($Global:JsonPath+"Get-NcSisPolicy.json")
                Throw "ERROR: failed to read $filepath"
            }    
        }
        if($Backup -eq $True){
            $SisPolicyList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcSisPolicy.json") -Encoding ASCII -Width 65535
            if( ($ret=get-item $($Global:JsonPath+"Get-NcSisPolicy.json") -ErrorAction SilentlyContinue) -ne $null ){
                Write-LogDebug "$($Global:JsonPath+"Get-NcSisPolicy.json") saved successfully"
            }else{
                Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcSisPolicy.jsonn")"
                $Return=$False
            }    
        }
        if($Backup -eq $False){
            foreach ( $SisPolicy in ( $SisPolicyList | Skip-Null ) ) {
                $PrimaryPolicyName=$SisPolicy.PolicyName
                $PrimaryPolicyDuration=$SisPolicy.Duration
                $PrimaryPolicySchedule=$SisPolicy.Schedule
                $PrimaryPolicyEnable=$SisPolicy.Enabled
                $PrimaryPolicyQosPolicy=$SisPolicy.QosPolicy
                $PrimaryPolicyType=$SisPolicy.PolicyType
                $PrimaryPolicyThreshold=$SisPolicy.ChangelogThresholdPercent
                if(($PrimaryPolicyDuration.count) -gt 0){
                    $PrimaryPolicyDurationType=$PrimaryPolicyDuration.GetType().Name | Out-String
                    Write-LogDebug "Primary Policy Duration = [$PrimaryPolicyDuration] and Type = [$PrimaryPolicyDurationType]"
                    if(($PrimaryPolicyDuration.GetType().Name) -eq "String"){
                        Write-LogDebug "Set Policy Duration [$PrimaryPolicyDuration] equal to 0"
                        $PrimaryPolicyDuration=0
                    }
                }else{
                    $PrimaryPolicyDuration=0    
                }
                Write-LogDebug "Get-NcSisPolicy -Controller $mySecondaryController -VserverContext $mySecondaryVserver -name $PrimaryPolicyName"
                $SecondaryPolicy = Get-NcSisPolicy -Controller $mySecondaryController -VserverContext $mySecondaryVserver -name $PrimaryPolicyName  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSisPolicy failed [$ErrorVar] on [$mySecondaryController] [$mySecondaryVserver]" }
                if($SecondaryPolicy -ne $null){
                    $SecondaryPolicyDuration=$SecondaryPolicy.Duration
                    $SecondaryPolicySchedule=$SecondaryPolicy.Schedule
                    $SecondaryPolicyEnable=$SecondaryPolicy.Enabled
                    $SecondaryPolicyQosPolicy=$SecondaryPolicy.QosPolicy
                    $SecondaryPolicyType=$SecondaryPolicy.PolicyType
                    $SecondaryPolicyThreshold=$SecondaryPolicy.ChangelogThresholdPercent
                    if(($SecondaryPolicyDuration.count) -gt 0){
                        $SecondaryPolicyDurationType=$SecondaryPolicyDuration.GetType().Name | Out-String
                        Write-LogDebug "Secondary Policy Duration = [$SecondaryPolicyDuration] and Type = [$SecondaryPolicyDurationType]"
                        if(($SecondaryPolicyDuration.GetType().Name) -eq "String"){
                            Write-LogDebug "Set Policy Duration [$SecondaryPolicyDuration] equal to 0"
                            $SecondaryPolicyDuration=0
                        }
                    }else{
                        $SecondaryPolicyDuration=0       
                    }
                }
                if($SecondaryPolicy -eq $null) 
                {
                    if($PrimaryPolicyName -eq "auto" -and $PrimaryPolicySchedule -eq $null -and $PrimaryPolicyQosPolicy -eq $null){
                        if($Restore -eq $True){
                            if(Test-Path $($Global:JsonPath+"Get-NcSystemVersionInfo.json")){
                                $PrimaryVersion=Get-Content $($Global:JsonPath+"Get-NcSystemVersionInfo.json") | ConvertFrom-Json
                            }else{
                                $Return=$False
                                $filepath=$($Global:JsonPath+"Get-NcSystemVersionInfo.json")
                                Throw "ERROR: failed to read $filepath"
                            }    
                        }else{
                            $PrimaryVersion=(Get-NcSystemVersionInfo -Controller $myPrimaryController).VersionTupleV    
                        }
                        if($PrimaryVersion.Major -ge 9 -and $PrimaryVersion.Minor -ge 3){
                            Write-Log "[$workOn] [auto] Efficiency Policy is factory created since ONTAP 9.3. Bypass on destination"
                            continue
                        }else{
                            $SecondaryVersion=(Get-NcSystemVersionInfo -Controller $mySecondaryController).VersionTupleV
                            if($SecondaryVersion.Major -ge 9 -and $SecondaryVersion.Minor -ge 3){
                                Write-Log "[$workOn] [auto] Efficiency Policy already exist since ONTAP 9.3 as a factory Policy."
                                continue  
                            }
                        }
                    }
                    Write-Log "[$workOn] Efficiency Policy [$PrimaryPolicyName] created"
                    if($PrimaryPolicyType -eq "threshold")
                    {
                        Write-LogDebug "create_update_efficiency_policy_dr: New-NcSisPolicy -Controller $mySecondaryController -VserverContext $mySecondaryVserver -Name $PrimaryPolicyName -ChangelogThresholdPercent $PrimaryPolicyThreshold  -PolicyType $PrimaryPolicyType -Enabled $PrimaryPolicyEnable -QosPolicy $PrimaryPolicyQosPolicy  -ErrorVariable ErrorVar"
                        $out=New-NcSisPolicy -Controller $mySecondaryController -VserverContext $mySecondaryVserver -Name $PrimaryPolicyName -ChangelogThresholdPercent $PrimaryPolicyThreshold -PolicyType $PrimaryPolicyType -Enabled $PrimaryPolicyEnable -QosPolicy $PrimaryPolicyQosPolicy  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcSisPolicy failed [$ErrorVar]" }
                    }
                    else
                    {
                        if($PrimaryPolicyDuration -gt 0){
                            Write-LogDebug "New-NcSisPolicy -Controller $mySecondaryController -VserverContext $mySecondaryVserver -Name $PrimaryPolicyName -Schedule $PrimaryPolicySchedule -DurationHours $PrimaryPolicyDuration -PolicyType $PrimaryPolicyType -Enabled $PrimaryPolicyEnable -QosPolicy $PrimaryPolicyQosPolicy"
                            $out=New-NcSisPolicy -Controller $mySecondaryController -VserverContext $mySecondaryVserver -Name $PrimaryPolicyName -Schedule $PrimaryPolicySchedule -DurationHours $PrimaryPolicyDuration -PolicyType $PrimaryPolicyType -Enabled $PrimaryPolicyEnable -QosPolicy $PrimaryPolicyQosPolicy  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcSisPolicy failed [$ErrorVar]" }
                        }else{
                            Write-LogDebug "New-NcSisPolicy -Controller $mySecondaryController -VserverContext $mySecondaryVserver -Name $PrimaryPolicyName -Schedule $PrimaryPolicySchedule -PolicyType $PrimaryPolicyType -Enabled $PrimaryPolicyEnable -QosPolicy $PrimaryPolicyQosPolicy"
                            $out=New-NcSisPolicy -Controller $mySecondaryController -VserverContext $mySecondaryVserver -Name $PrimaryPolicyName -Schedule $PrimaryPolicySchedule -PolicyType $PrimaryPolicyType -Enabled $PrimaryPolicyEnable -QosPolicy $PrimaryPolicyQosPolicy  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcSisPolicy failed [$ErrorVar]" }
                        }
                    }
                } 
                elseif (($SecondaryPolicyDuration -ne $PrimaryPolicyDuration) -or ($PrimaryPolicySchedule -ne $SecondaryPolicySchedule) -or ($PrimaryPolicyEnable -ne $SecondaryPolicyEnable) -or ($PrimaryPolicyQosPolicy -ne $SecondaryPolicyQosPolicy) -or ($PrimaryPolicyType -ne $SecondaryPolicyType) -or ($PrimaryPolicyThreshold -ne $SecondaryPolicyThreshold))
                {
                    Write-Log "[$workOn] Sis Policy [$PrimaryPolicyName] already exists with difference, will update"
                    if($SecondaryPolicyType -eq "threshold")
                    {
                        write-logDebug "Set-NcSisPolicy -controller $mySecondaryController -VserverContext $mySecondaryVserver -name $PrimaryPolicyName -ChangelogThresholdPercent $PrimaryPolicyThreshold -PolicyType $PrimaryPolicyType -Enabled $PrimaryPolicyEnable -QosPolicy $PrimaryPolicyQosPolicy  -ErrorVariable ErrorVar"
                        $out=Set-NcSisPolicy -controller $mySecondaryController -VserverContext $mySecondaryVserver -name $PrimaryPolicyName -ChangelogThresholdPercent $PrimaryPolicyThreshold -PolicyType $PrimaryPolicyType -Enabled $PrimaryPolicyEnable -QosPolicy $PrimaryPolicyQosPolicy  -ErrorVariable ErrorVar     
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcSisPolicy failed [$ErrorVar]" }
                    }
                    else
                    {
                        
                        write-logDebug "Set-NcSisPolicy -controller $mySecondaryController -VserverContext $mySecondaryVserver -name $PrimaryPolicyName -Schedule $PrimaryPolicySchedule -DurationHours $PrimaryPolicyDuration -PolicyType $PrimaryPolicyType -Enabled $PrimaryPolicyEnable -QosPolicy $PrimaryPolicyQosPolicy  -ErrorVariable ErrorVar"
                        $out=Set-NcSisPolicy -controller $mySecondaryController -VserverContext $mySecondaryVserver -name $PrimaryPolicyName -Schedule $PrimaryPolicySchedule -DurationHours $PrimaryPolicyDuration -PolicyType $PrimaryPolicyType -Enabled $PrimaryPolicyEnable -QosPolicy $PrimaryPolicyQosPolicy  -ErrorVariable ErrorVar     
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcSisPolicy failed [$ErrorVar]" }
                    }
                }
                else
                {
                    Write-Log "[$workOn] Sis Policy [$PrimaryPolicyName] already exist and identical"
                }
            }
        }
	    Write-LogDebug "create_update_efficiency_policy_dr[$myPrimaryVserver]: end"
	    return $Return
    }
    Catch 
    {
	    handle_error $_ $myPrimaryVserver
	    return $Return
    }
}
#############################################################################################
# create_update_policy_dr
Function create_update_policy_dr(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) {
Try {
    $Return = $True 
    Write-Log "[$workOn] Check SVM Export Policy"
    Write-LogDebug "create_update_policy_dr[$myPrimaryVserver]: start"
    if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
    if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}

    if($Restore -eq $False){
        $ExportPolicyList = Get-NcExportPolicy -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcExportPolicy failed [$ErrorVar]" }
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcExportPolicy.json")){
            $ExportPolicyList=Get-Content $($Global:JsonPath+"Get-NcExportPolicy.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcExportPolicy.json")
            Throw "ERROR: failed to read $filepath"
        }    
    }
    if($Backup -eq $True){
        $ExportPolicyList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcExportPolicy.json") -Encoding ASCII -Width 65535    
        if( ($ret=get-item $($Global:JsonPath+"Get-NcExportPolicy.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcExportPolicy.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcExportPolicy.json")"
            $Return=$False
        }
    }
	foreach ( $ExportPolicy in ( $ExportPolicyList | Skip-Null ) ) {
        $PolicyName=$ExportPolicy.PolicyName
        if($Backup -eq $False){
		    Write-LogDebug "create_update_policy_dr: check ExportPolicy $PolicyName"
		    $out = Get-NcExportPolicy -Controller $mySecondaryController -VserverContext $mySecondaryVserver -name $PolicyName  -ErrorVariable ErrorVar
		    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcExportPolicy failed [$ErrorVar]" }
		    if ( $out -eq $null ) {
			    Write-LogDebug "create_update_policy_dr: New-NcExportPolicy -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Name $PolicyName"
			    Write-Log "[$workOn] Export Policy [$PolicyName] create"
			    $out=New-NcExportPolicy -Controller $mySecondaryController -VserverContext $mySecondaryVserver -Name $PolicyName  -ErrorVariable ErrorVar
			    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcExportPolicy failed [$ErrorVar]" }
		    } else {
			    Write-Log "[$workOn] Export Policy [$PolicyName] already exist"
            }
        }
        if($Restore -eq $False){
		    $ExportPolicyRulesList=Get-NcExportRule -VserverContext $myPrimaryVserver -Controller $myPrimaryController -PolicyName $PolicyName  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcExportRule failed [$ErrorVar]" }
        }else{
            if(Test-Path $($Global:JsonPath+"Get-NcExportRule-"+$PolicyName+".json")){
                $ExportPolicyRulesList=Get-Content $($Global:JsonPath+"Get-NcExportRule-"+$PolicyName+".json") | ConvertFrom-Json
            }else{
                $Return=$False
                $filepath=$($Global:JsonPath+"Get-NcExportRule-"+$PolicyName+".json")
                Throw "ERROR: failed to read $filepath"
            }    
        }
        if($Backup -eq $True){
            $ExportPolicyRulesList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcExportRule-"+$PolicyName+".json") -Encoding ASCII -Width 65535    
            if( ($ret=get-item $($Global:JsonPath+"Get-NcExportRule-"+$PolicyName+".json") -ErrorAction SilentlyContinue) -ne $null ){
                Write-LogDebug "$($Global:JsonPath+"Get-NcExportRule-"+$PolicyName+".json") saved successfully"
            }else{
                Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcExportRule-"+$PolicyName+".json")"
                $Return=$False
            }
        }
        if($Backup -eq $False){
            foreach ( $ExportPolicyRule in ( $ExportPolicyRulesList | Skip-Null ) ) {
                $AnonymousUserId = $ExportPolicyRule.AnonymousUserId
                $ClientMatch = $ExportPolicyRule.ClientMatch
                $ExportChownMode = $ExportPolicyRule.ExportChownMode
                $ExportNtfsUnixSecurityOps = $ExportPolicyRule.ExportNtfsUnixSecurityOps
                $IsAllowDevIsEnabled = $ExportPolicyRule.IsAllowDevIsEnabled 
                $IsAllowSetUidEnabled = $ExportPolicyRule.IsAllowSetUidEnabled
                $Protocol = $ExportPolicyRule.Protocol
                $RoRule = $ExportPolicyRule.RoRule
                $RuleIndex = $ExportPolicyRule.RuleIndex 
                $RwRule = $ExportPolicyRule.RwRule 
                $SuperUserSecurity = $ExportPolicyRule.SuperUserSecurity 
                $IsAllowDevIsEnabledSpecified = $ExportPolicyRule.IsAllowDevIsEnabledSpecified
                $IsAllowSetUidEnabledSpecified = $ExportPolicyRule.IsAllowSetUidEnabledSpecified
                $RuleIndexSpecified = $ExportPolicyRule.RuleIndexSpecified 
                $Sc_ExportPolicyRules=Get-NcExportRule -VserverContext $mySecondaryVserver -Controller $mySecondaryController -PolicyName $PolicyName -Index $RuleIndex  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcExportRule failed [$ErrorVar]" }
                if ( $Sc_ExportPolicyRules -ne $null ) {
                    Write-LogDebug "create_update_policy_dr: Rules already Exist Remove it"
                    Write-LogDebug "Remove-NcExportRule -Policy $PolicyName -Index $RuleIndex -Vserver $mySecondaryVserver -Controller $mySecondaryController"
                    $out=Remove-NcExportRule -Policy $PolicyName -Index $RuleIndex -Vserver $mySecondaryVserver -Controller $mySecondaryController -Confirm:$False  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Remove-NcExportRule failed [$ErrorVar]" }
                } 
                Write-LogDebug "create_update_policy_dr: $RuleIndex"
                Write-LogDebug "create_update_policy_dr: New-NcExportRule -Policy $PolicyName -Index $RuleIndex  -ClientMatch $ClientMatch -ReadOnlySecurityFlavor  $RoRule -ReadWriteSecurityFlavor  $RwRule -Protocol  $Protocol -Anon  $AnonymousUserId -SuperUserSecurityFlavor $SuperUserSecurity -NtfsUnixSecurityOps $ExportNtfsUnixSecurityOps -ChownMode $ExportChownMode -Vserver $mySecondaryVserver -Controller $mySecondaryController"
                $out=New-NcExportRule -Policy $PolicyName -Index $RuleIndex  -ClientMatch $ClientMatch -ReadOnlySecurityFlavor  $RoRule -ReadWriteSecurityFlavor  $RwRule -Protocol  $Protocol -Anon  $AnonymousUserId -SuperUserSecurityFlavor $SuperUserSecurity -NtfsUnixSecurityOps $ExportNtfsUnixSecurityOps -ChownMode $ExportChownMode -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcExportRule failed [$ErrorVar]" }
                if ( $IsAllowSetUidEnabled -eq $True ) {
                    $out=Set-NcExportRule -Policy $PolicyName -Index $RuleIndex -EnableSetUid -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcExportRule failed [$ErrorVar]" }
                } else {
                    $out=Set-NcExportRule -Policy $PolicyName -Index $RuleIndex -DisableSetUi -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcExportRule failed [$ErrorVar]" }
                }
                if ( $IsAllowDevIsEnabled  -eq $True ) { 
                    $out=Set-NcExportRule -Policy $PolicyName -Index $RuleIndex -EnableDev -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcExportRule failed [$ErrorVar]" }
                } else {
                    $out=Set-NcExportRule -Policy $PolicyName -Index $RuleIndex -DisableDev -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcExportRule failed [$ErrorVar]" }
                }
            }
        }
	}
	Write-LogDebug "create_update_policy_dr[$myPrimaryVserver]: end"
	return $Return
}
Catch {
	handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
# create_update_igroupdr
Function create_update_igroupdr(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) {

Try {
    $Return = $True
    Write-Log "[$workOn] Check SVM iGroup configuration"
    Write-LogDebug "create_update_igroupdr[$myPrimaryVserver]: start"
    if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
    if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}

    if($Restore -eq $False){
        $PrimaryIgroupList = Get-NcIgroup -Vserver $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcIgroup failed [$ErrorVar]" }
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcIgroup.json")){
            $PrimaryIgroupList=Get-Content $($Global:JsonPath+"Get-NcIgroup.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcIgroup.json")
            Throw "ERROR: failed to read $filepath"
        }    
    }
    if($Backup -eq $True){
        $PrimaryIgroupList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcIgroup.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcIgroup.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcIgroup.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcIgroup.json")"
            $Return=$False
        }
    }
    if($Backup -eq $Fasle){
        if ( $PrimaryIgroupList -eq $null ) {
            Write-Log "[$workOn] No igroup found on cluster [$myPrimaryController]"
            Write-LogDebug "create_update_igroupdr[$myPrimaryVserver]: end"
            return $True
        }
        foreach ( $PrimaryIgroup in ( $PrimaryIgroupList  | Skip-Null ) ) {
            $add_initiator = $False
            $PrimaryName=$PrimaryIgroup.Name
            $PrimaryType=$PrimaryIgroup.Type
            $PrimaryProtocol=$PrimaryIgroup.Protocol
            $PrimaryPortset=$PrimaryIgroup.Portset
            $PrimaryInitiators=$PrimaryIgroup.Initiators
            $PrimaryALUA=$PrimaryIgroup.ALUA
            Write-LogDebug "igroup $PrimaryName"
            $SecondaryIgroup = Get-NcIgroup -Name $PrimaryName -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcIgroup failed [$ErrorVar]" } 
            if ( $SecondaryIgroup -eq $null ) {
                Write-LogDebug "New-NcIgroup -Name $PrimaryName -Protocol $PrimaryProtocol -Type $Type -Portset $PrimaryPortset -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                $out=New-NcIgroup -Name $PrimaryName -Protocol $PrimaryProtocol -Type $Type -Portset $PrimaryPortset -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcIgroup failed [$ErrorVar]" }
                $add_initiator = $True
            } else {
                Write-Log "[$workOn] igroup initiator [$PrimaryName] already exist"
                $SecondaryName=$SecondaryIgroup.Name
                $SecondaryType=$SecondaryIgroup.Type
                $SecondaryProtocol=$SecondaryProtocol
                $SecondaryPortset=$SecondaryIgroup.Portset
                $SecondaryInitiators=$SecondaryIgroup.Initiators
                $SecondaryALUA=$SecondaryIgroup.ALUA
                $str1 = "" ; $str2 = "" ;
                foreach ( $initiator in ( $PrimaryInitiators | Skip-Null ) ) { $str1 = $str1 + $initiator.InitiatorName }
                foreach ( $initiator in ( $SecondaryInitiators | Skip-Null) ) { $str2 = $str2 + $initiator.InitiatorName }
                if ( $str1 -ne $str2 ) {
                    foreach ( $initiator in ( $SecondaryInitiators | SKip-Null ) ) {
                        $tmpStr = $initiator.InitiatorName
                        Write-LogDebug "Remove-NcIgroupInitiator -Name $PrimaryName -Initiator $tmpStr -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                        $out=Remove-NcIgroupInitiator -Name $PrimaryName -Initiator $tmpStr -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Remove-NcIgroupInitiator failed [$ErrorVar]" }
                    }
                    $add_initiator = $True
                }
                if ( $PrimaryALUA -ne $SecondaryALUA ) {
                    $out=Set-NcIgroup -key alua False -Name $PrimaryName -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcIgroup failed [$ErrorVar]" }
                }
            }
            if ( $add_initiator -eq $True ) {
                foreach ( $initiator in ( $PrimaryInitiators | Skip-Null ) ) {
                    $tmpStr = $initiator.InitiatorName
                    Write-LogDebug "Add-NCIgroupInitiator -Name $PrimaryName -Initiator $tmpStr -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                    $out=Add-NCIgroupInitiator -Name $PrimaryName -Initiator $tmpStr -VserverContext $mySecondaryVserver -Controller $mySecondaryController
                }
            }
        }
    }
    Write-LogDebug "create_update_igroupdr[$myPrimaryVserver]: end"
	return $Return
}
Catch {
	handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
Function map_lundr (
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) {

Try {

    $Return = $True
    Write-Log "[$workOn] Check LUN Mapping"
    Write-LogDebug "map_lundr[$myPrimaryVserver]: start"
    if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
    if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}

    # Check if LUN need to be mapped
    $Global:SelectVolume=$False
    if($Backup -eq $False -and $Restore -eq $False){
        if( (Is_SelectVolumedb $myPrimaryController $mySecondaryController $myPrimaryVserver $mySecondaryVserver) -eq $True ){
            $Global:SelectVolume=$True    
        }else{
            $Global:SelectVolume=$False
        }
    }
    if($Global:SelectVolume -eq $True)
    {
        $Selected=get_volumes_from_selectvolumedb $myPrimaryController $myPrimaryVserver
        if($Selected.state -ne $True)
        {
            Write-Log "[$workOn] Failed to get Selected Volume from DB, check selectvolume.db file inside $Global:SVMTOOL_DB"
            Write-logDebug "check_update_voldr: end with error"
            return $False  
        }else{
            $VolList=$Selected.volumes
            Write-LogDebug "Get-NcLun -Volume $VolList -VserverContext $myPrimaryVserver -Controller $myPrimaryController"
            $PrimaryLunList=Get-NcLun -Volume $VolList -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
        }    
    }else{
        if($Restore -eq $False){
            Write-LogDebug "Get-NcLun -VserverContext $myPrimaryVserver -Controller $myPrimaryController"
            $PrimaryLunList = Get-NcLun -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcLun failed [$ErrorVar]" } 
        }else{
            if(Test-Path $($Global:JsonPath+"Get-NcLun.json")){
                $PrimaryLunList=Get-Content $($Global:JsonPath+"Get-NcLun.json") | ConvertFrom-Json
            }else{
                $Return=$False
                $filepath=$($Global:JsonPath+"Get-NcLun.json")
                Throw "ERROR: failed to read $filepath"
            }
        }
        if($Backup -eq $True){
            $PrimaryLunList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcLun.json") -Encoding ASCII -Width 65535
            if( ($ret=get-item $($Global:JsonPath+"Get-NcLun.json") -ErrorAction SilentlyContinue) -ne $null ){
                Write-LogDebug "$($Global:JsonPath+"Get-NcLun.json") saved successfully"
            }else{
                Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcLun.json")"
                $Return=$False
            }
        }
    }
    #if($workOn -eq "DS_HV"){wait-debugger}
	foreach ( $PrimaryLun in ( $PrimaryLunList | Skip-Null  ) ) {
		if ( $PrimaryLun.Mapped -eq $True ) {
            if($Restore -eq $False){
                $PrimaryLunPath = $PrimaryLun.Path
                $PrimaryLunMapList = Get-NcLunMap -Path $PrimaryLunPath -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcLunMap failed [$ErrorVar]" } 
            }else{
                $PrimaryLunPath_string=$PrimaryLunPath -replace "/","@"
                if(Test-Path $($Global:JsonPath+"Get-NcLunMap_"+$PrimaryLunPath_string+".json")){
                    $PrimaryLunMapList=Get-Content $($Global:JsonPath+"Get-NcLunMap_"+$PrimaryLunPath_string+".json") | ConvertFrom-Json
                }else{
                    $Return=$False
                    $filepath=$($Global:JsonPath+"Get-NcLunMap_"+$PrimaryLunPath_string+".json")
                    Throw "ERROR: failed to read $filepath"
                }
            }
            if($Backup -eq $True){
                if($PrimaryLunPath.length -gt 0){
                    $PrimaryLunPath_string=$PrimaryLunPath -replace "/","@"
                    $PrimaryLunMapList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcLunMap_"+$PrimaryLunPath_string+".json") -Encoding ASCII -Width 65535
                    if( ($ret=get-item $($Global:JsonPath+"Get-NcLunMap_"+$PrimaryLunPath_string+".json") -ErrorAction SilentlyContinue) -ne $null ){
                        Write-LogDebug "$($Global:JsonPath+"Get-NcLunMap_"+$PrimaryLunPath_string+".json") saved successfully"
                    }else{
                        Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcLunMap_"+$PrimaryLunPath_string+".json")"
                        $Return=$False
                    }
                }
            }
            if($Backup -eq $False){
                foreach ( $PrimaryLunMap in ( $PrimaryLunMapList | Skip-Null )  ) {
                    $PrimaryInitiatorGroup =  $PrimaryLunMap.InitiatorGroup
                    $PrimaryLunId =  $PrimaryLunMap.LunId
                    $SecondaryLun = Get-NcLun -Path $PrimaryLunPath -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcLun failed [$ErrorVar]" } 
                    if ( $SecondaryLun -eq $null ) {
                        Write-LogError "ERROR: The Lun [$PrimaryLunPath] doesn't exist on [$mySecondaryVserver] [$mySecondaryController]" 
                        Write-LogError "ERROR: Check your Snapmirror status and retry later" 
                        $Return = $False
                    } else {
                        $Query=Get-NcLunMap -Template -Controller $mySecondaryController
                        $Query.InitiatorGroup =  $PrimaryLunMap.InitiatorGroup
                        $Query.Path = $PrimaryLunPath
                        $SecondaryLunMap = Get-NcLunMap -Query $Query -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcLunMap failed [$ErrorVar]" } 
                        if ( $SecondaryLunMap -eq $null ) {
                            Write-Log "[$workOn] Map Lun [$PrimaryLunPath] [$workOn] [$mySecondaryController] on [$PrimaryInitiatorGroup]"
                            Write-LogDebug "Add-NcLunMap -Path $PrimaryLunPath -InitiatorGroup $PrimaryInitiatorGroup -Id $PrimaryLunId -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                            $out = Add-NcLunMap -Path $PrimaryLunPath -InitiatorGroup $PrimaryInitiatorGroup -Id $PrimaryLunId -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Add-NcLunMap failed [$ErrorVar]" }

                        } else {
                            Write-Log "[$workOn] Lun [$PrimaryLunPath] [$workOn] [$mySecondaryController] already mapped on [$PrimaryInitiatorGroup]"
                        }
                    }
                }
            }
		}
	}
    # Check if LUN need to be unmapped
    if($Backup -eq $False){
        $SecondaryLunList = Get-NcLun -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcLun failed [$ErrorVar]" } 
        foreach ( $SecondaryLun in ( $SecondaryLunList | Skip-Null  ) ) {
            if ( $SecondaryLun.Mapped -eq $True ) {
                $SecondaryLunPath = $SecondaryLun.Path
                $SecondaryLunMapList = Get-NcLunMap -Path $SecondaryLunPath -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcLunMap failed [$ErrorVar]" } 
                foreach ( $SecondaryLunMap in ( $SecondaryLunMapList | Skip-Null )  ) {
                    $SecondaryInitiatorGroup =  $SecondaryLunMap.InitiatorGroup
                    $PrimaryLun = $PrimaryLunList | where-object {$_.Path -eq $SecondaryLunPath}
                    #$PrimaryLun = Get-NcLun -Path $SecondaryLunPath -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
                    if ( $PrimaryLun -eq $null ) {
                        Write-LogError "ERROR: The PRIMARY   Lun [$SecondaryLunPath] Not exist [$myPrimaryVserver] [$myPrimaryController]" 
                        Write-LogError "ERROR: The SECONDARY Lun [$SecondaryLunPath] exist     [$mySecondaryVserver] [$mySecondaryController]" 
                        $Return = $False
                    } else {
                        #$Query=Get-NcLunMap -Template
                        #$Query.InitiatorGroup =  $SecondaryLunMap.InitiatorGroup
                        #$Query.Path = $SecondaryLunPath
                        $PrimaryLunMap = $PrimaryLunMapList | where-object {$_.InitiatorGroup -eq $SecondaryLunMap.InitiatorGroup -and $_.Path -eq $SecondaryLunPath}
                        #$PrimaryLunMap = Get-NcLunMap -Query $Query -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
                        #if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcLunMap failed [$ErrorVar]" } 
                        if ( $PrimaryLunMap -eq $null ) {
                            # Unmap the Lun from this igroup
                            Write-LogDebug "Remove-NcLunMap -Path $SecondaryLunPath -InitiatorGroup $SecondaryInitiatorGroup  -VserverContext $mySecondaryVserver -Controller $mySecondaryController -confirm:$False"
                            $out = Remove-NcLunMap -Path $SecondaryLunPath -InitiatorGroup $SecondaryInitiatorGroup  -VserverContext $mySecondaryVserver -Controller $mySecondaryController -confirm:$False 
                            if ( $? -ne $True ) {
                                Write-LogError "ERROR: Failed to unmap LUNs [$PrimaryLunPath] from [$SecondaryInitiatorGroup]" 
                                $Return = $False
                            }
                        } 
                    }
                }
            }
        }
    }
    Write-LogDebug "map_lundr[$myPrimaryVserver]: end"
	return $Return
}
Catch {
	handle_error $_ $myPrimaryVserver
	return $Return
}
}


#############################################################################################
Function set_serial_lundr (
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) 
{

    Try 
    {
        $Return = $True
        Write-Log "[$workOn] Check LUN Serial Number"
    	Write-LogDebug "set_serial_lundr[$myPrimaryVserver]: start"
        if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
        if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}

        $NeedChangeSerial = $False
        $Global:SelectVolume=$False
        if($Backup -eq $False -and $Restore -eq $False){
            if( (Is_SelectVolumedb $myPrimaryController $mySecondaryController $myPrimaryVserver $mySecondaryVserver) -eq $True ){
                $Global:SelectVolume=$True    
            }else{
                $Global:SelectVolume=$False
            }
        }
        if($Global:SelectVolume -eq $True)
        {
            $Selected=get_volumes_from_selectvolumedb $myPrimaryController $myPrimaryVserver
            if($Selected.state -ne $True)
            {
                Write-Log "[$workOn] Failed to get Selected Volume from DB, check selectvolume.db file inside $Global:SVMTOOL_DB"
                Write-logDebug "check_update_voldr: end with error"
                return $False  
            }else{
                $VolList=$Selected.volumes
                Write-LogDebug "Get-NcLun -Volume $VolList -VserverContext $myPrimaryVserver -Controller $myPrimaryController"
                $PrimaryLunList=Get-NcLun -Volume $VolList -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
            }    
        }else{
            if($Restore -eq $False){
                Write-LogDebug "Get-NcLun -VserverContext $myPrimaryVserver -Controller $myPrimaryController"
                $PrimaryLunList = Get-NcLun -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcLun failed [$ErrorVar]" } 
            }else{
                if(Test-Path $($Global:JsonPath+"Get-NcLun.json")){
                    $PrimaryLunList=Get-Content $($Global:JsonPath+"Get-NcLun.json") | ConvertFrom-Json
                }else{
                    $Return=$False
                    $filepath=$($Global:JsonPath+"Get-NcLun.json")
                    Throw "ERROR: failed to read $filepath"
                }
            }
        }
        if($Backup -eq $False){
            # Check LUN serial need to be changed  on destination
            foreach ( $PrimaryLun in ( $PrimaryLunList | Skip-Null  ) ) 
            {
                $PrimaryLunPath = $PrimaryLun.Path
                $PrimaryLunSerialNumber = $PrimaryLun.SerialNumber
                $SecondaryLun = Get-NcLun -Path $PrimaryLunPath -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcLun failed [$ErrorVar]" } 
                if ( $SecondaryLun -eq $null ) 
                {
                    Write-LogError "ERROR: The Lun [$PrimaryLunPath] doesn't exist on [$mySecondaryVserver] [$mySecondaryController]" 
                    Write-LogError "ERROR: Check your Snapmirror status and retry later" 
                    $Return = $False
                } 
                else  
                {
                    $SecondaryLunSerialNumber = $SecondaryLun.SerialNumber
                    if ( $PrimaryLunSerialNumber -ne $SecondaryLunSerialNumber ) 
                    {
                        Write-Log "[$workOn] Lun [$PrimaryLunPath] serial [$SecondaryLunSerialNumber] different [$PrimaryLunSerialNumber]"
                        $NeedChangeSerial = $True
                    }
                }
            }
        }
        if($Backup -eq $False){
            if ( $NeedChangeSerial ) 
            {
                if($Restore -eq $False -and $Backup -eq $False){
                    # Wait SnapMirror Relations
                    Write-Log "[$workOn] Wait for all relations before change LUN Serials Number"
                    if ( ( wait_snapmirror_dr -NoInteractive -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) 
                    { 
                        $Return = $False
                        throw "ERROR: wait_snapmirror_dr failed"  
                    }
                    # Break SnapMirror Relations
                    Write-Log "[$workOn] Break all relations to change LUN Serials Number"
                    Write-LogDebug "break_snapmirror_vserver_dr -NoInteractive -myController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver"
                    if ( ( break_snapmirror_vserver_dr -NoInteractive -myController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) 
                    {
                        $Return = $False
                        throw "ERROR: break_snapmirror_vserver_dr failed" 
                    }
                }
                foreach ( $PrimaryLun in ( $PrimaryLunList | Skip-Null  ) ) 
                {
                    $PrimaryLunPath = $PrimaryLun.Path
                    $PrimaryLunSerialNumber = $PrimaryLun.SerialNumber
                    $SecondaryLun = Get-NcLun -Path $PrimaryLunPath -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcLun failed [$ErrorVar]" } 
                    if ( $SecondaryLun -eq $null ) 
                    {
                        Write-LogError "ERROR: The Lun [$PrimaryLunPath] doesn't exist on [$mySecondaryVserver] [$mySecondaryController]" 
                        Write-LogError "ERROR: Check your Snapmirror status and retry later" 
                        $Return = $False
                    } 
                    else  
                    {
                        $SecondaryLunSerialNumber = $SecondaryLun.SerialNumber
                        if ( $PrimaryLunSerialNumber -ne $SecondaryLunSerialNumber ) 
                        {
                            Write-LogDebug "Set-NcLun -Path $PrimaryLunPath  -Offline -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                            $out=Set-NcLun -Path $PrimaryLunPath  -Offline -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcLunSerialNumber failed [$ErrorVar]" }
                            Write-LogDebug "Set-NcLunSerialNumber -Path $PrimaryLunPath -SerialNumber $PrimaryLunSerialNumber -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                            $out=Set-NcLunSerialNumber -Path $PrimaryLunPath -SerialNumber $PrimaryLunSerialNumber -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcLunSerialNumber failed [$ErrorVar]" }
                            Write-LogDebug "Set-NcLun -Path $PrimaryLunPath  -Online -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                            $out=Set-NcLun -Path $PrimaryLunPath  -Online -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar 
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcLun failed [$ErrorVar]" }
                        }
            
                    }
                }

            }
        }
        Write-LogDebug "set_serial_lundr[$myPrimaryVserver]: end"
    } 
    Catch 
    {
    	handle_error $_ $myPrimaryVserver
    }
	if ( $NeedChangeSerial ) 
    {
		Write-Log "[$workOn] Resync"
		Write-LogDebug "resync_vserver_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver" 
		if ( ( resync_vserver_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) 
        {
		  Write-LogError "ERROR: Resync_vserver_dr error"
		}
	}
    Write-LogDebug "set_serial_lundr: end"
	return $True
}

#############################################################################################
Function remove_igroupdr(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
	[string] $mySecondaryVserver,
    [switch] $Source) {
Try {

	$Return = $True
    if($Source -eq $False){
	    Write-LogDebug "remove_igroupdr: start"
        $mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar).ClusterName			
	    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }
	    $SecondaryIgroupList = Get-NcIgroup -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
	    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcIgroup failed [$ErrorVar]" } 
	    if ( $SecondaryIgroupList -ne $null ) {
		    foreach ( $SecondaryIgroup in ( $SecondaryIgroupList | Skip-Null ) ) {
			    $SecondaryName=$SecondaryIgroup.Name
			    $SecondaryType=$SecondaryIgroup.Type
			    $SecondaryProtocol=$SecondaryProtocol
			    $SecondaryPortset=$SecondaryIgroup.Portset
			    $SecondaryInitiators=$SecondaryIgroup.Initiators
			    $SecondaryALUA=$SecondaryIgroup.ALUA
			    Write-Log "remove igroup [$SecondaryName]"
			    foreach ( $initiator in ( $SecondaryInitiators | Skip-Null ) ) {
				    $tmpStr = $initiator.InitiatorName
				    Write-LogDebug "Remove-NcIgroupInitiator -Name $SecondaryName -Initiator $tmpStr -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
				    $out=Remove-NcIgroupInitiator -Name $SecondaryName -Initiator $tmpStr -VserverContext $mySecondaryVserver -Controller $mySecondaryController   -ErrorVariable ErrorVar -Confirm:$False
				    if ( $? -ne $True ) {
					    Write-LogError "ERROR: Failed to remove initiator $initiator from igroup $SecondaryName" 
					    $Return = $False
				    }
			    }
		    $out=Remove-NcIgroup -Name $SecondaryName -VserverContext $mySecondaryVserver -Controller $mySecondaryController   -ErrorVariable ErrorVar -Confirm:$False
		    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Remove-NcIgroup failed [$ErrorVar]" }
		    }
	    }
    }else{
        Write-LogDebug "remove_igroupdr: start"
        $myPrimaryCluster = (Get-NcCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar).ClusterName			
	    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }
	    $PrimaryIgroupList = Get-NcIgroup -Vserver $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
	    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcIgroup failed [$ErrorVar]" } 
	    if ( $PrimaryIgroupList -ne $null ) {
		    foreach ( $PrimaryIgroup in ( $PrimaryIgroupList | Skip-Null ) ) {
			    $PrimaryName=$PrimaryIgroup.Name
			    $PrimaryType=$PrimaryIgroup.Type
			    $PrimaryProtocol=$PrimaryProtocol
			    $PrimaryPortset=$PrimaryIgroup.Portset
			    $PrimaryInitiators=$PrimaryIgroup.Initiators
			    $PrimaryALUA=$PrimaryIgroup.ALUA
			    Write-Log "remove igroup [$PrimaryName]"
			    foreach ( $initiator in ( $PrimaryInitiators | Skip-Null ) ) {
				    $tmpStr = $initiator.InitiatorName
				    Write-LogDebug "Remove-NcIgroupInitiator -Name $PrimaryName -Initiator $tmpStr -VserverContext $myPrimaryVserver -Controller $myPrimaryController"
				    $out=Remove-NcIgroupInitiator -Name $PrimaryName -Initiator $tmpStr -VserverContext $myPrimaryVserver -Controller $myPrimaryController   -ErrorVariable ErrorVar -Confirm:$False
				    if ( $? -ne $True ) {
					    Write-LogError "ERROR: Failed to remove initiator $initiator from igroup $PrimaryName" 
					    $Return = $False
				    }
			    }
		    $out=Remove-NcIgroup -Name $PrimaryName -VserverContext $myPrimaryVserver -Controller $myPrimaryController   -ErrorVariable ErrorVar -Confirm:$False
		    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Remove-NcIgroup failed [$ErrorVar]" }
		    }
	    }
    }
    Write-LogDebug "remove_igroupdr: end"
	Return $Return 
}
Catch {
	handle_error $_ $myPrimaryVserver
	return $Return
}
}
#############################################################################################
# check_update_vserver 
Function check_update_vserver(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) {
Try {
	$Return = $True
    Write-Log "[$workOn] Check SVM options"
    Write-LogDebug "check_update_vserver[$myPrimaryVserver]: start"
    if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
    if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}

    if ($Restore -eq $False){
        $PrimaryVserver = Get-NcVserver -Controller $myPrimaryController -Name $myPrimaryVserver  -ErrorVariable ErrorVar 
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed for $myPrimaryVserver [$ErrorVar]" }
        if ( $PrimaryVserver -eq $null ) { $Return = $False ; throw "ERROR: Get-NcVserver failed for $myPrimaryVserver [$ErrorVar]" }
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcVserver.json")){
            $PrimaryVserver=Get-Content $($Global:JsonPath+"Get-NcVserver.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcVserver.json")
            Throw "ERROR: failed to read $filepath"
        }
    }

    if ($Backup -eq $False){
        $SecondaryVserver = Get-NcVserver -Controller $mySecondaryController -Name $mySecondaryVserver  -ErrorVariable ErrorVar 
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed for $mySecondaryVserver [$ErrorVar]" }
        if ( $SecondaryVserver -eq $null ) { $Return = $False ; throw "ERROR: Get-NcVserver failed for $mySecondaryVserver [$ErrorVar]" }

        $PrimaryLanguage = $PrimaryVserver.Language
        $SecondaryLanguage = $SecondaryVserver.Language

        $PrimaryAllowedProtocols=$PrimaryVserver.AllowedProtocols
        $SecondaryAllowedProtocols=$SecondaryVserver.AllowedProtocols

        $PrimaryRootVolumeSecurityStyle = $PrimaryVserver.RootVolumeSecurityStyle
        $SecondaryRootVolumeSecurityStyle=$SecondaryVserver.RootVolumeSecurityStyle

        # Check AllowedProtocls
        $tmpStrDiff1 = "" ; $tmpStrDiff2 = "" 
        foreach ( $Protocol in ( $PrimaryAllowedProtocols | Skip-Null ) ) {
            $tmpStrDiff1 += $Protocol
        }
        foreach ( $Protocol in ( $SecondaryAllowedProtocols | Skip-Null ) ) {
            $tmpStrDiff2 += $Protocol
        }
        if ( $tmpStrDiff1 -ne $tmpStrDiff2 ) {
            Write-LogWarn "Vserver Protocols difference: [$myPrimaryVserver] [$PrimaryAllowedProtocols] [$mySecondaryVserver] [$SecondaryAllowedProtocols] "
            Write-LogDebug "check_update_vserver: Set-NcVserver -AllowedProtocols $PrimaryAllowedProtocols -Name $mySecondaryVserver -Controller $mySecondaryController"
            $out=Set-NcVserver -AllowedProtocols $PrimaryAllowedProtocols -Name $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcVserver failed [$ErrorVar]" }
        }

        # Check and Update Vserver Parameters
        if ( $SecondaryRootVolumeSecurityStyle -ne $SecondaryRootVolumeSecurityStyle ) {
            Write-LogWarn "Not same RootVolumeSecuirtyStyle: [$myPrimaryVserver] [$SecondaryRootVolumeSecurityStyle] [$mySecondaryVserver] [$SecondaryRootVolumeSecurityStyle]"
        }
        if ( $PrimaryLanguage -ne $SecondaryLanguage  ) {
            Write-LogWarn "Vserver Language difference: [$myPrimaryVserver] [$PrimaryLanguage] [$mySecondaryVserver] [$SecondaryLanguage] " 
            Write-LogDebug "check_update_vserver: Set-NcVserver -Language $PrimaryLanguage -Name $mySecondaryVserver -Controller $mySecondaryController"
            $out=Set-NcVserver -Language $PrimaryLanguage -Name $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcVserver failed [$ErrorVar]" }
        }
    }

    # Check Name MappingSwitch
    if($Restore -eq $False){
	    $PrimaryNameServiceList= Get-NcNameServiceNsSwitch -Controller $myPrimaryController -Vserver $myPrimaryVserver  -ErrorVariable ErrorVar 
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNameService failed [$ErrorVar]" }
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcNameServiceNsSwitch.json")){
            $PrimaryNameServiceList=Get-Content $($Global:JsonPath+"Get-NcNameServiceNsSwitch.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcNameServiceNsSwitch.json")
            Throw "ERROR: failed to read $filepath"
        }
    }
    if($Backup -eq $True){
        $PrimaryNameServiceList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcNameServiceNsSwitch.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcNameServiceNsSwitch.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcNameServiceNsSwitch.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcNameServiceNsSwitch.json")"
            $Return=$False
        }
    }    
    if($Backup -eq $False){
        foreach ( $PrimaryNameService in ( $PrimaryNameServiceList ) | skip-Null ) {
            $NameServiceDatabase = $PrimaryNameService.NameServiceDatabase
            $NameServiceSources = $PrimaryNameService.NameServiceSources
            $out=Set-NcNameServiceNsSwitchSources -NameserviceDatabase $PrimaryNameService.NameServiceDatabase -NameserviceSources $PrimaryNameService.NameServiceSources -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcNameService failed [$ErrorVar]" }
        }
    }
    Write-LogDebug "check_update_vserver[$myPrimaryVserver]: end"
	return $Return 
}
Catch {
	handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
Function set_all_lif(
    [string] $myPrimaryVserver, 
	[string] $mySecondaryVserver, 
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string]$workOn=$mySecondaryVserver,
    [string] $state,
    [bool]$Backup,
    [bool]$Restore) {

    $Return=$True
    Write-LogDebug "Set all lif [$state] on [$workOn]"
    if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
    if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}
    $lifsdest=Get-NcNetInterface -vserver $mySecondaryVserver -Controller $mySecondaryController -FirewallPolicy !data
	if($lifsdest -eq $null)
	{
		$lifsdest=Get-NcNetInterface -vserver $mySecondaryVserver -Controller $mySecondaryController
    }
    if($Restore -eq $True){
        if(Test-Path $($Global:JsonPath+"Get-NcNetInterface.json")){
            $lifssource=Get-Content $($Global:JsonPath+"Get-NcNetInterface.json") | ConvertFrom-Json
            if($lifssource -eq $null){
                Write-LogDebug "No Lif on source vserver"
                return $True
            }
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcNetInterface.json")
            Throw "ERROR: failed to read $filepath"
        }
        $lifssource=$lifssource | Select-Object Address
    }
    if($Backup -eq $False -and $Restore -eq $False){
        $lifssource=Get-NcNetInterface -vserver $myPrimaryVserver -Controller $myPrimaryController | select Address
        if($lifssource -eq $null){
            Write-LogDebug "No Lif on source vserver"
            return $True
        }
    }
	$IPsource=$lifssource  | ForEach-Object {$_.Address}
	$set=$false
	foreach($lif in $lifsDest){
        $lif_name=$lif.InterfaceName
		$lif_ip=$lif.Address
		if($lif_ip -notin $IPsource){
			if($debuglevel){Write-LogDebug "Set LIF [$lif_name] into state [$state]"}
			$ret=Set-NcNetInterface -Name $lif_name -Vserver $mySecondaryVserver -Controller $mySecondaryController -AdministrativeStatus $state -ErrorVariable ErrorVar
			if($? -ne $true){
				$Return=$False
				Write-LogDebug "ERROR: failed to set lif [$lif_name] into state [$sate] reason [$ErrorVar]"
			}
			$set=$true
		}
    }
	if($set -eq $false){
        if($Restore -eq $False){
            Write-Log "[$workOn] ERROR: You need at least one lif on the destination that can communicate with Active Directory. Use ConfigureDR to create one"
            return $False
        }else{
            return $True
        }
	}else{
		return $True
	}
}

#############################################################################################
# check_update_voldr
Function check_update_voldr(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) {
Try {
	$Return = $True
    Write-Log "[$workOn] Check SVM Volumes options"
    Write-logDebug "check_update_voldr[$myPrimaryVserver]: start"
	if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
    if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}

    # Duplicate root volume exportPolicy Destination Volumes
    if($Restore -eq $False){
        $PrimaryRootVolumeName = (Get-NcVserver -Controller $myPrimaryController -Vserver $myPrimaryVserver  -ErrorVariable ErrorVar).RootVolume
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed to get RootVolume [$ErrorVar]" }    
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcVserver.json")){
            $PrimaryRootVolumeName=Get-Content $($Global:JsonPath+"Get-NcVserver.json") | ConvertFrom-Json
            $PrimaryRootVolumeName=$PrimaryRootVolumeName.RootVolume
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcVserver.json")
            Throw "ERROR: failed to read $filepath"
        }    
    }
    if ($PrimaryRootVolumeName -eq $null ) { $Return = $False ; Write-logError "root volume not found for $myPrimaryVserver" }
    if($Backup -eq $False){
        $SecondaryRootVolumeName = (Get-NcVserver -Controller $mySecondaryController -Vserver $mySecondaryVserver  -ErrorVariable ErrorVar).RootVolume
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed to get RootVolume [$ErrorVar]" } 
        if ($SecondaryRootVolumeName -eq $null ) { $Return = $False ; Write-logError "root volume not found for $mySecondaryVserver" }
    }
    if($Restore -eq $False){
        $PrimaryRootVolume = Get-NcVol -Controller $myPrimaryController -Vserver $myPrimaryVserver -Volume $PrimaryRootVolumeName  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed to get RootVolume [$ErrorVar]" }
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcVol.json")){
            $PrimaryRootVolume=Get-Content $($Global:JsonPath+"Get-NcVol.json") | ConvertFrom-Json
            $PrimaryRootVolume=$PrimaryRootVolume | Where-Object {$_.Name -eq $PrimaryRootVolumeName}
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcVol.json")
            Throw "ERROR: failed to read $filepath"
        }    
    }
	if ($PrimaryRootVolume -eq $null ) { $Return = $False ; Write-logError "root volume $PrimaryRootVolume not found for $myPrimaryVserver" }
    if($Backup -eq $False){
        $SecondaryRootVolume = Get-NcVol -Controller $mySecondaryController -Vserver $mySecondaryVserver -Volume $SecondaryRootVolumeName  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed to get RootVolume [$ErrorVar]" } 
        if ($SecondaryRootVolume -eq $null ) { $Return = $False ; Write-logError "root volume $SecondaryRootVolume not found for $mySecondaryVserver" }
    }
    if($Backup -eq $False){
        $PrimaryRootVolExportPolicy=$PrimaryRootVolume.VolumeExportAttributes.Policy
        $SecondaryRootVolExportPolicy=$SecondaryRootVolume.VolumeExportAttributes.Policy
        Write-LogDebug "PrimaryRootVolumeName [$PrimaryRootVolumeName] SecondaryRootVolumeName [$SecondaryRootVolumeName] PrimaryRootVolExportPolicy [$PrimaryRootVolExportPolicy] SecondaryRootVolExportPolicy [$SecondaryRootVolExportPolicy]" 
        if ( $PrimaryRootVolExportPolicy -ne $SecondaryRootVolExportPolicy ) {
            Write-Log "[$workOn] Secondary Root Volume [$SecondaryRootVolumeName] use a different export: modify Policy"
            $attributes = Get-NcVol -Template -Controller $mySecondaryController
            $attributes.VolumeExportAttributes=$PrimaryRootVolume.VolumeExportAttributes
            $query=Get-NcVol -Template -Controller $mySecondaryController
            $query.name=$SecondaryRootVolumeName
            $query.vserver=$mySecondaryVserver
            $query.NcController=$mySecondaryController
            $query_string=$query | Out-String
            $attributes_string=$attributes | Out-String
            Write-LogDebug "Update-NcVol -Query $query_string -Attributes $attributes_string -Controller $mySecondaryController"
            $out=Update-NcVol -Query $query -Attributes $attributes -Controller $mySecondaryController -ErrorVariable ErrorVar 
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Update-NcVol Failed: Failed to update root volume $PrimaryVolName [$ErrorVar]" }
        }
    }
     # Update Data Volumes
    if($Restore -eq $False -and $Backup -eq $False){
        if( (Is_SelectVolumedb $myPrimaryController $mySecondaryController $myPrimaryVserver $mySecondaryVserver) -eq $True ){
            $Global:SelectVolume=$True    
        }else{
            $Global:SelectVolume=$False
        }
    }else{
        $Global:SelectVolume=$False    
    }
    if($Global:SelectVolume -eq $True)
    {
        $Selected=get_volumes_from_selectvolumedb $myPrimaryController $myPrimaryVserver
        if($Selected.state -ne $True)
        {
            Write-Log "[$workOn] Failed to get Selected Volume from DB, check selectvolume.db file inside $Global:SVMTOOL_DB"
            Write-logDebug "check_update_voldr: end with error"
            return $False  
        }else{
            $VolList=$Selected.volumes
            Write-LogDebug "Get-NcVol -Name $VolList -Vserver $myPrimaryVserver -Controller $myPrimaryController"
            $PrimaryVolList=Get-NcVol -Name $VolList -Vserver $myPrimaryVserver -Controller $myPrimaryController -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
        }    
    }else{
        if($Restore -eq $False){
            Write-LogDebug "Get-NcVol -Vserver $myPrimaryVserver -Controller $myPrimaryController"
            $PrimaryVolList = Get-NcVol -Controller $myPrimaryController -Vserver $myPrimaryVserver -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" } 
        }else{
            if(Test-Path $($Global:JsonPath+"Get-NcVol.json")){
                $PrimaryVolList=Get-Content $($Global:JsonPath+"Get-NcVol.json") | ConvertFrom-Json
            }else{
                $Return=$False
                $filepath=$($Global:JsonPath+"Get-NcVol.json")
                Throw "ERROR: failed to read $filepath"
            }    
        }
    }
    if($Backup -eq $False){
        foreach ( $PrimaryVol in ( $PrimaryVolList | Skip-Null ) ) {
            Write-LogDebug "check_update_voldr: PrimaryVol [$PrimaryVol]"
            $PrimaryVolName=$PrimaryVol.Name
            $PrimaryVolStyle=$PrimaryVol.VolumeSecurityAttributes.Style
            $PrimaryVolExportPolicy=$PrimaryVol.VolumeExportAttributes.Policy
            $PrimaryVolType=$PrimaryVol.VolumeIdAttributes.Type
            $PrimaryVolLang=$PrimaryVol.VolumeLanguageAttributes.LanguageCode
            $PrimaryVolSize=$PrimaryVol.VolumeSpaceAttributes.Size
            $PrimaryVolIsSis=$PrimaryVol.VolumeSisAttributes.IsSisVolume
            $PrimaryVolSpaceGuarantee=$PrimaryVol.VolumeSpaceAttributes.SpaceGuarantee
            $PrimaryVolPercentSnapReserved=$PrimaryVol.VolumeSpaceAttributes.PercentageSnapshotReserve
            $PrimaryVolState=$PrimaryVol.State
            $PrimaryVolJunctionPath=$PrimaryVol.VolumeIdAttributes.JunctionPath
            $PrimaryVolIsInfiniteVolume=$PrimaryVol.IsInfiniteVolume
            $PrimaryVolIsVserverRoot=$PrimaryVol.VolumeStateAttributes.IsVserverRoot
            if ( ( $PrimaryVolState -eq "online" ) -and ($PrimaryVolType -eq "rw" ) -and ($PrimaryVolIsVserverRoot -eq $False ) -and ( $PrimaryVolIsInfiniteVolume -eq $False ) ) 
            {
                $SecondaryVol = Get-NcVol -Controller $mySecondaryController -Vserver $mySecondaryVserver -Volume $PrimaryVolName  -ErrorVariable ErrorVar 
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" } 
                if ( $SecondaryVol -eq $null )  
                {
                    Write-LogDebug "check_update_voldr: volume $PrimaryVol doesnt' exist" 
                    Write-LogError "ERROR: check_update_voldr: volume $PrimaryVolName do not exist vserver $mySecondaryVserver" 
                    Write-LogError "ERROR: please use DataAggr option or run ConfigureDR to create missing volumes" 
                    $Return = $False
                } 
                else 
                {
                    Write-LogDebug "check_update_voldr: volume $PrimaryVol exist" 
                    # Diff Volume Attributes
                    $SecondaryVolName=$SecondaryVol.Name
                    $SecondaryVolStyle=$SecondaryVol.VolumeSecurityAttributes.Style
                    $SecondaryVolExportPolicy=$SecondaryVol.VolumeExportAttributes.Policy
                    $SecondaryVolLang=$SecondaryVol.VolumeLanguageAttributes.LanguageCode
                    $SecondaryVolSize=$SecondaryVol.VolumeSpaceAttributes.Size
                    $SecondaryVolIsSis=$SecondaryVol.VolumeSisAttributes.IsSisVolume
                    $SecondaryVolSpaceGuarantee=$SecondaryVol.VolumeSpaceAttributes.SpaceGuarantee
                    $SecondaryVolPercentSnapReserved=$SecondaryVol.VolumeSpaceAttributes.PercentageSnapshotReserve
                    $SecondaryVolState=$SecondaryVol.State
                    $SecondaryVolJunctionPath=$SecondaryVol.VolumeIdAttributes.JunctionPath
                    $SecondaryVolIsInfiniteVolume=$SecondaryVol.IsInfiniteVolume
                    $SecondaryVolIsVserverRoot=$SecondaryVol.VolumeStateAttributes.IsVserverRoot
                    if ( $PrimaryVolLang -ne $SecondaryVolLang ) 
                    {
                        Write-LogError "ERROR: Secondary Volume [$SecondaryVolName] use different Language" 
                        $Return = $True
                    }
                    if ( $PrimaryVolExportPolicy -ne $SecondaryVolExportPolicy ) 
                    {
                        Write-Log "[$workOn] Secondary Volume [$SecondaryVolName] use a different export: modify Policy"
                        $attributes = Get-NcVol -Template -Controller $mySecondaryController
                        $attributes.VolumeExportAttributes=$PrimaryVol.VolumeExportAttributes
                        $query=Get-NcVol -Template -Controller $mySecondaryController
                        $query.name=$SecondaryVolName
                        $query.vserver=$mySecondaryVserver
                        $query.NcController=$mySecondaryController
                        $query_string=$query | Out-String
                        $attributes_string=$attributes | Out-String
                        Write-LogDebug "Update-NcVol -Query $query_string -Attributes $attributes_string -Controller $mySecondaryController"
                        $out=Update-NcVol -Query $query -Attributes $attributes -Controller $mySecondaryController -ErrorVariable ErrorVar 
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Update-NcVol Failed: Failed to update volume $SecondaryVolName [$ErrorVar]" }
                    }
                }
            }
            elseif ( ( $PrimaryVolState -eq "online" ) -and ($PrimaryVolType -eq "rw" ) -and ($PrimaryVolIsVserverRoot -eq $True ) -and ( $PrimaryVolIsInfiniteVolume -eq $False ) ) 
            {
                # Diff Volume root Attributes
                $SecondaryVol = Get-NcVol -Controller $mySecondaryController -Vserver $mySecondaryVserver -Volume $PrimaryVolName  -ErrorVariable ErrorVar 
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
                $SecondaryVolName=$SecondaryVol.Name
                $SecondaryVolStyle=$SecondaryVol.VolumeSecurityAttributes.Style
                $SecondaryVolExportPolicy=$SecondaryVol.VolumeExportAttributes.Policy
                $SecondaryVolLang=$SecondaryVol.VolumeLanguageAttributes.LanguageCode
                $SecondaryVolSize=$SecondaryVol.VolumeSpaceAttributes.Size
                $SecondaryVolIsSis=$SecondaryVol.VolumeSisAttributes.IsSisVolume
                $SecondaryVolSpaceGuarantee=$SecondaryVol.VolumeSpaceAttributes.SpaceGuarantee
                $SecondaryVolPercentSnapReserved=$SecondaryVol.VolumeSpaceAttributes.PercentageSnapshotReserve
                $SecondaryVolState=$SecondaryVol.State
                $SecondaryVolJunctionPath=$SecondaryVol.VolumeIdAttributes.JunctionPath
                $SecondaryVolIsInfiniteVolume=$SecondaryVol.IsInfiniteVolume
                $SecondaryVolIsVserverRoot=$SecondaryVol.VolumeStateAttributes.IsVserverRoot
                
                if ( $PrimaryVolPercentSnapReserved -ne $SecondaryVolPercentSnapReserved  )
                {
                    Write-Log "Secondary Volume [$PrimaryVolName] have a different Percentage for Snapshot Reserved Space: modify PercentSnapshotReserve" 
                    $attributes = Get-NcVol -Template -Controller $mySecondaryController
                    $attributes.VolumeSpaceAttributes=$PrimaryVol.VolumeSpaceAttributes
                    $query=Get-NcVol -Template -Controller $mySecondaryController
                    $query.name=$PrimaryVolName
                    $query.vserver=$mySecondaryVserver
                    $query.NcController=$mySecondaryController
                    $query_string=$query | Out-String
                    $attributes_string=$attributes | Out-String
                    Write-LogDebug "Update-NcVol -Query $query_string -Attributes $attributes_string -Controller $mySecondaryController"
                    $out=Update-NcVol -Query $query -Attributes $attributes -Controller $mySecondaryController -ErrorVariable ErrorVar 
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Update-NcVol Failed: Failed to update volume $PrimaryVolName [$ErrorVar]" }   
                }
            }
            else 
            {
                Write-Log "[$workOn] Ignore volume [$PrimaryVolName]" 
                Write-LogDebug "check_update_voldr: PrimaryVolState  [$PrimaryVolState]"
                Write-LogDebug "check_update_voldr: PrimaryVolIsVserverRoot [$PrimaryVolIsVserverRoot]"
                Write-LogDebug "check_update_voldr: PrimaryVolIsInfiniteVolume [$PrimaryVolIsInfiniteVolume]"
                Write-LogDebug "check_update_voldr:  PrimaryVolType [$PrimaryVolType]" 
            }
        }
    }
    Write-logDebug "check_update_voldr[$myPrimaryVserver]: end"
	return $Return 
}
Catch {
	handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
Function create_clone_volume_voldr(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[switch] $NoInteractive,
	[string] $myPrimaryVserver,
	[string] $mySecondaryVserver,
    [string] $workOn=$mySecondaryVserver,
    [bool] $Backup,
    [bool] $Restore) {
Try {
    Write-Log "[$workOn] Create Clones"
    $Return = $True
    Write-LogDebug "create_clone_volume_voldr[$workOn]: start"
    if ( ( $ret=analyse_junction_path -myController $mySecondaryController -myVserver $mySecondaryVserver -Dest) -ne $True ) {
        Write-LogError "ERROR: analyse_junction_path" 
        clean_and_exit 1
    }
    $myPrimaryCluster = (Get-NcCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar ).ClusterName			
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }
    $mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar ).ClusterName	
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }
    $DestinationVserverDR=($mySecondaryVserver -Split ("_clone."))[0]
    Write-LogDebug "Get-NcVol -Controller $mySecondaryController -Query @{Vserver=$DestinationVserverDR;VolumeStateAttributes=@{IsVserverRoot=$false};VolumeIdAttributes=@{Type=`"dp`"}}"
    $DestVolList = Get-NcVol -Controller $mySecondaryController -Query @{Vserver=$DestinationVserverDR;VolumeStateAttributes=@{IsVserverRoot=$false};VolumeIdAttributes=@{Type="dp"}} -ErrorVariable ErrorVar  
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
    foreach ( $DestVol in ( $DestVolList | Skip-Null ) ) {
        $DestVolName=$DestVol.Name
        $DestVolSize=$DestVol.VolumeSpaceAttributes.Size
        $DestVolJunctionPath=$DestVol.VolumeIdAttributes.JunctionPath
        if( $Global:SelectVolume -eq $True -and $NoInteractive -eq $False )
        {
            $volsizeGB=[math]::round($DestVolSize/1024/1024,2)
            $ANS=Read-HostOptions "Does volume [$DestVolName  $($volsizeGB) GB  $DestVolJunctionPath] need to be cloned on [$mySecondaryVserver] ?" "y/n"
            if ( $ANS -eq 'n' ) {
                Write-LogDebug "SelectVolume volume [$DestVolName] excluded"
                continue 
            }
            if ( $ANS -eq 'y' ){
                Write-LogDebug "SelectVolume volume [$DestVolName] included" 
                #Save_Volume_To_Selectvolumedb $myPrimaryController $mySecondaryController $myPrimaryVserver $mySecondaryVserver $PrimaryVolName  
            } 
        }
        Write-Log "[$workOn] Create Flexclone [$DestVolName] from SVM [$DestinationVserverDR]"
        $ForceCreateNewSnap=$False
        Write-LogDebug "Get-NcSnapshot -Controller $mySecondaryController -Query @{Vserver=$DestinationVserverDR;Volume=$DestVolName;Dependency=`"`!snapmirror`"}"
        $SnapshotList=Get-NcSnapshot -Controller $mySecondaryController -Query @{Vserver=$DestinationVserverDR;Volume=$DestVolName} -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapshot failed [$ErrorVar]" }
        $ParentSnapshot=$SnapshotList[-1]
        $ParentSnapshotName=$ParentSnapshot.Name
        $JunctionPath=$("/"+$DestVolName)
        Write-LogDebug "New-NcVolClone -CloneVolume $DestVolName -ParentVolume $DestVolName -VolumeType rw -Vserver $mySecondaryVserver -ParentVserver $DestinationVserverDR -VserverContext $DestinationVserverDR -ParentSnapshot $ParentSnapshotName -Controller $mySecondaryController"
        $FlexVol = New-NcVolClone -CloneVolume $DestVolName `
        -ParentVolume $DestVolName `
        -VolumeType "rw" `
        -Vserver $mySecondaryVserver `
        -ParentVserver $DestinationVserverDR `
        -VserverContext $DestinationVserverDR `
        -ParentSnapshot $ParentSnapshotName `
        -Controller $mySecondaryController `
        -ErrorVariable ErrorVar 
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcVolClone Failed to create flexclone $DestVolName [$ErrorVar]" }             
    }
    Write-LogDebug "create_clone_volume_voldr[$workOn]: end"
    return $Return  
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
Function create_volume_voldr(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[switch] $NoInteractive,
	[string] $myPrimaryVserver,
	[string] $mySecondaryVserver,
    [string] $workOn=$mySecondaryVserver,
    [bool] $Backup,
    [bool] $Restore) {
Try {
    Write-Log "[$workOn] Check SVM Volumes"
    Write-LogDebug "create_volume_voldr[$workOn]: start"
    if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
    if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}
    $Return = $True
    if($Backup -eq $False -and $Restore -eq $False){
        if ( ( $ret=analyse_junction_path -myController $mySecondaryController -myVserver $mySecondaryVserver -Dest) -ne $True ) {
            Write-LogError "ERROR: analyse_junction_path" 
            clean_and_exit 1
        }
    }
    if($Restore -eq $False){
	    $myPrimaryCluster = (Get-NcCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar ).ClusterName			
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }
    }
    if($Backup -eq $False){
        $mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar ).ClusterName			
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }
    }
	if($NoInteractive -eq $False){
        if($Global:SelectVolume -eq $True){
            if($Backup -eq $False -and $Restore -eq $False){
                $PreviousSelectVolumes=Purge_SelectVolumedb $myPrimaryController $mySecondaryController $myPrimaryVserver $mySecondaryVserver
            }else{
                $PreviousSelectVolumes=@()    
            }
        }
    }
     # Create all missing Destination Volumes
     if($Restore -eq $False){
        $PrimaryVolList = Get-NcVol -Controller $myPrimaryController -Vserver $myPrimaryVserver  -ErrorVariable ErrorVar  
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
     }else{
        if(Test-Path $($Global:JsonPath+"Get-NcVol.json")){
            $PrimaryVolList=Get-Content $($Global:JsonPath+"Get-NcVol.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcVol.json")
            Throw "ERROR: failed to read $filepath"
        }
    }
    if($Backup -eq $True){
        $PrimaryVolList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcVol.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcVol.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcVol.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcVol.json")"
            $Return=$False
        }
        $PrimarySisList = Get-NcSis -Controller $myPrimaryController -Vserver $myPrimaryVserver  -ErrorVariable ErrorVar  
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSis failed [$ErrorVar]" }
        $PrimarySisList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcSis.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcSis.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcSis.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcSis.json")"
            $Return=$False
        }
        $PrimarySisPolicyList = Get-NcSisPolicy -Controller $myPrimaryController -Vserver $myPrimaryVserver  -ErrorVariable ErrorVar  
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSisPolicy failed [$ErrorVar]" }
        $PrimarySisPolicyList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcSisPolicy.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcSisPolicy.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcSisPolicy.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcSisPolicy.json")"
            $Return=$False
        }
    } 
    if( ($Restore -eq $False -and $Backup -eq $False) -and $Global:SelectVolume -eq $False ){
        # remove selectvolume.db file for source and dest
        Write-LogDebug "No SelectVolume option so remove Select Volume DB files"
        $SVMTOOL_DB_SRC_CLUSTER=$Global:SVMTOOL_DB + '\' + $myPrimaryCluster + '.cluster'
        $SVMTOOL_DB_SRC_VSERVER=$SVMTOOL_DB_SRC_CLUSTER + '\' + $myPrimaryVserver + '.vserver'
        $SVMTOOL_DB_DST_CLUSTER=$Global:SVMTOOL_DB + '\' + $mySecondaryCluster + '.cluster'
        $SVMTOOL_DB_DST_VSERVER=$SVMTOOL_DB_DST_CLUSTER + '\' + $mySecondaryVserver + '.vserver'
        $SELECTVOL_DB_SRC_FILE=$SVMTOOL_DB_SRC_VSERVER + '\selectvolume.db'
        $SELECTVOL_DB_DST_FILE=$SVMTOOL_DB_DST_VSERVER + '\selectvolume.db'
        Write-LogDebug "Remove file [$SELECTVOL_DB_SRC_FILE] for source"
        $out=Remove-Item -Confirm:$false -Force -Path $SELECTVOL_DB_SRC_FILE -ErrorAction SilentlyContinue 
        Write-LogDebug "Remove file [$SELECTVOL_DB_DST_FILE] for destination" 
        $out=Remove-Item -Confirm:$false -Force -Path $SELECTVOL_DB_DST_FILE -ErrorAction SilentlyContinue  
    }
    foreach ( $PrimaryVol in ( $PrimaryVolList | Skip-Null ) ) {
        if($Backup -eq $False){
            Write-LogDebug "create_volume_voldr: PrimaryVol [$PrimaryVol]"
            $PrimaryVolName=$PrimaryVol.Name
            $PrimaryVolStyle=$PrimaryVol.VolumeSecurityAttributes.Style
            $PrimaryVolExportPolicy=$PrimaryVol.VolumeExportAttributes.Policy
            $PrimaryVolType=$PrimaryVol.VolumeIdAttributes.Type
            $PrimaryVolLang=$PrimaryVol.VolumeLanguageAttributes.LanguageCode
            $PrimaryVolSize=$PrimaryVol.VolumeSpaceAttributes.Size
            $PrimaryVolIsSis=$PrimaryVol.VolumeSisAttributes.IsSisVolume
            $PrimaryVolSpaceGuarantee=$PrimaryVol.VolumeSpaceAttributes.SpaceGuarantee
            $PrimaryVolSnapshotReserve=$PrimaryVol.VolumeSpaceAttributes.PercentageSnapshotReserve
            $PrimaryVolState=$PrimaryVol.State
            $PrimaryVolJunctionPath=$PrimaryVol.VolumeIdAttributes.JunctionPath
            $PrimaryVolIsInfiniteVolume=$PrimaryVol.IsInfiniteVolume
            $PrimaryVolIsVserverRoot=$PrimaryVol.VolumeStateAttributes.IsVserverRoot
            if ( ( $PrimaryVolState -eq "online" ) -and ($PrimaryVolType -eq "rw" ) -and ($PrimaryVolIsVserverRoot -eq $False ) -and ( $PrimaryVolIsInfiniteVolume -eq $False ) ) {
                if($Restore -eq $False -and $Backup -eq $False){
                    if( $Global:SelectVolume -eq $True -and $NoInteractive -eq $False )
                    {
                        $volsizeGB=[math]::round($PrimaryVolSize/1024/1024,2)
                        try {
                            $global:mutexconsole.WaitOne(200) | Out-Null
                        }
                        catch [System.Threading.AbandonedMutexException]{
                            #AbandonedMutexException means another thread exit without releasing the mutex, and this thread has acquired the mutext, therefore, it can be ignored
                            Write-Host -f Red "catch abandoned mutex for [$myPrimaryVserver]"
                            free_mutexconsole
                        }
                        $ANS=Read-HostOptions "Does volume [$PrimaryVolName  $($volsizeGB) GB  $PrimaryVolJunctionPath] need to be replicated on destination ?" "y/n"
                        if ( $ANS -eq 'n' ) {
                            Write-LogDebug "SelectVolume volume [$PrimaryVolName] excluded"
                            if($PreviousSelectVolumes.contains($PrimaryVolName)){
                                Write-Log "[$workOn] [$PrimaryVolName] was previously selected for replication"
                                $ANS=Read-HostOptions "Do you want to remove destination volume [$PrimaryVolName] and associated Snapmirror Relationship on [$mySecondaryVserver]?" "y/n"
                                if($ANS -eq 'y'){
                                    if((delete_snapmirror_relationship $myPrimaryController $mySecondaryController $myPrimaryVserver $mySecondaryVserver $PrimaryVolName) -ne $True){Write-LogError "ERROR: delete_snapmirror_relationship failed";return $false}
                                    if((umount_volume $mySecondaryController $mySecondaryVserver $PrimaryVolName) -ne $True){Write-LogError "ERROR: umount_volume failed";return $false}
                                    if((remove_volume $mySecondaryController $mySecondaryVserver $PrimaryVolName ) -ne $True){Write-LogError "ERROR: remove_volume failed";return $false}  
                                }
                            }
                            continue 
                        }
                        if ( $ANS -eq 'y' ){
                            Write-LogDebug "SelectVolume volume [$PrimaryVolName] included" 
                            Save_Volume_To_Selectvolumedb $myPrimaryController $mySecondaryController $myPrimaryVserver $mySecondaryVserver $PrimaryVolName  
                        }
                        free_mutexconsole  
                    }
                }
                $SecondaryVol = Get-NcVol -Controller $mySecondaryController -Vserver $mySecondaryVserver -Volume $PrimaryVolName  -ErrorVariable ErrorVar 
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
                if ( $SecondaryVol -eq $null )  {
                    # Create the volume
                    if ( $Global:DataAggr.length -eq 0 ) {
                        if ( $NoInteractive ) {
                            Write-LogError "ERROR: No Default Data Aggregate available for new volume on [$mySecondaryController], please use option DataAggr"
                            $Return = $False
                            return $Return 
                        }
                        else{
                            if( $Global:AlwaysChooseDataAggr -eq $true )
                            {
                                Write-LogDebug "create_volume_voldr with `$Global:AlwaysChooseDataAggr enable, ask DataAggr for volume [$PrimaryVolName]"
                                $Question = "[$mySecondaryVserver] Please Select a destination DATA aggregate for [$PrimaryVolName] on Cluster [$MySecondaryController]:"
                            }
                            else
                            {
                                $Question = "[$mySecondaryVserver] Please Select the default DATA aggregate on Cluster [$MySecondaryController]:"
                            }
                            try {
                                $global:mutexconsole.WaitOne(200) | Out-Null
                            }
                            catch [System.Threading.AbandonedMutexException]{
                                #AbandonedMutexException means another thread exit without releasing the mutex, and this thread has acquired the mutext, therefore, it can be ignored
                                Write-Host -f Red "catch abandoned mutex for [$myPrimaryVserver]"
                                free_mutexconsole
                            }
                            $Global:DataAggr = select_data_aggr_from_cli -myController $mySecondaryController -myQuestion $Question
                            free_mutexconsole
                        }
                    }
                    $Aggr = Get-NcAggr -Controller $mySecondaryController -Name $Global:DataAggr  -ErrorVariable ErrorVar 
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcAggr failed [$ErrorVar]" } 
                    if ( $Aggr -eq $null ) {
                        Write-LogError "ERROR: aggr [$Global:DataAggr] not found on [$mySecondaryController] : Exit"
                        clean_and_exit 1 
                    }
                    $Available=$Aggr.Available
                    while ( $Available -lt $PrimaryVolSize ) {
                        if ( $NoInteractive ) {
                            Write-LogError "ERROR: No space left on [$Global:DataAggr] [$mySecondaryController] for create [$PrimaryVolName]"
                            $Return = $False
                            return $Return 
                        }
                        Write-LogWarn "Unable to create volume [$PrimaryVolName] [$PrimaryVolSize]"
                        Write-LogWarn "Not enough space available in aggr [$Global:DataAggr] [$Available]"
                        $Question ="[$workOn] WARNING: Please select another Aggregate:"
                        try {
                            $global:mutexconsole.WaitOne(200) | Out-Null
                        }
                        catch [System.Threading.AbandonedMutexException]{
                            #AbandonedMutexException means another thread exit without releasing the mutex, and this thread has acquired the mutext, therefore, it can be ignored
                            Write-Host -f Red "catch abandoned mutex for [$myPrimaryVserver]"
                            free_mutexconsole
                        }
                        $Global:DataAggr = select_data_aggr_from_cli -myController $mySecondaryController -myQuestion $Question
                        free_mutexconsole
                        $Aggr = Get-NcAggr -Controller $mySecondaryController -Name $Global:DataAggr  -ErrorVariable ErrorVar 
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcAggr failed [$ErrorVar]" } 
                        $Available=$Aggr.Available
                    }
                    if($Restore -eq $False){	
                        Write-Log "[$workOn] Create new volume DR: [$PrimaryVolName]"
                        Write-LogDebug "create_volume_voldr: New-NcVol -Name $PrimaryVolName -Aggregate $Global:DataAggr -JunctionPath $null -ExportPolicy $PrimaryVolExportPolicy -SecurityStyle $PrimaryVolStyle -SpaceReserve $PrimaryVolSpaceGuarantee -SnapshotReserve $PrimaryVolSnapshotReserve -Type DP  -Language $PrimaryVolLang -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Size $PrimaryVolSize"
                        $SecondaryVol = New-NcVol -Name $PrimaryVolName -Aggregate $Global:DataAggr  -JunctionPath $null -ExportPolicy $PrimaryVolExportPolicy -SecurityStyle $PrimaryVolStyle -SpaceReserve $PrimaryVolSpaceGuarantee -SnapshotReserve $PrimaryVolSnapshotReserve -Type DP -Language $PrimaryVolLang -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Size $PrimaryVolSize  -ErrorVariable ErrorVar 
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcVol Failed: Failed to create new volume $PrimaryVolName [$ErrorVar]" }
                    }else{
                        Write-Log "[$workOn] Create new volume: [$PrimaryVolName]"
                        if($Global:VOLUME_TYPE -eq "RW"){
                            Write-LogDebug "Create RW volume"
                            Write-LogDebug "create_volume_voldr: New-NcVol -Name $PrimaryVolName -Aggregate $Global:DataAggr -JunctionPath $null -ExportPolicy $PrimaryVolExportPolicy -SecurityStyle $PrimaryVolStyle -SpaceReserve $PrimaryVolSpaceGuarantee -SnapshotReserve $PrimaryVolSnapshotReserve -Type RW -Language $PrimaryVolLang -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Size $PrimaryVolSize"
                            $SecondaryVol = New-NcVol -Name $PrimaryVolName -Aggregate $Global:DataAggr  -JunctionPath $null -ExportPolicy $PrimaryVolExportPolicy -SecurityStyle $PrimaryVolStyle -SpaceReserve $PrimaryVolSpaceGuarantee -SnapshotReserve $PrimaryVolSnapshotReserve -Type RW -Language $PrimaryVolLang -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Size $PrimaryVolSize -ErrorVariable ErrorVar 
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcVol Failed: Failed to create new volume $PrimaryVolName [$ErrorVar]" }    
                        }else{
                            Write-LogDebug "Create DP volume"
                            Write-LogDebug "create_volume_voldr: New-NcVol -Name $PrimaryVolName -Aggregate $Global:DataAggr -JunctionPath $null -ExportPolicy $PrimaryVolExportPolicy -SecurityStyle $PrimaryVolStyle -SpaceReserve $PrimaryVolSpaceGuarantee -SnapshotReserve $PrimaryVolSnapshotReserve -Type DP  -Language $PrimaryVolLang -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Size $PrimaryVolSize"
                            $SecondaryVol = New-NcVol -Name $PrimaryVolName -Aggregate $Global:DataAggr  -JunctionPath $null -ExportPolicy $PrimaryVolExportPolicy -SecurityStyle $PrimaryVolStyle -SpaceReserve $PrimaryVolSpaceGuarantee -SnapshotReserve $PrimaryVolSnapshotReserve -Type DP -Language $PrimaryVolLang -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Size $PrimaryVolSize  -ErrorVariable ErrorVar 
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcVol Failed: Failed to create new volume $PrimaryVolName [$ErrorVar]" }    
                        }
                    }
                    if($Global:AlwaysChooseDataAggr -eq $true)
                    {
                        Write-LogDebug "create_volume_voldr with `$Global:AlwaysChooseDataAggr set to True, so reuse variable `$Global:DataAggr"
                        $Global:DataAggr=""    
                    }
                } 
                else {
                    Write-Log "[$workOn] Volume [$PrimaryVolName] already exist on  [$workOn]"
                    # ADD Volume Type
                    $SecondaryVolType=$SecondaryVol.VolumeIdAttributes.Type
                    if ( $SecondaryVolType -ne "DP" -and $Restore -eq $False -and $Backup -eq $False) {
                        Write-LogError "ERROR: volume $SecondaryVol is not DP Volume"
                    }
                }
                # Diff Volume Attributes
            } 
            else {
                Write-Log "[$workOn] Ignore volume [$PrimaryVolName]"
                Write-LogDebug "create_volume_voldr: PrimaryVolState  [$PrimaryVolState]"
                Write-LogDebug "create_volume_voldr: PrimaryVolIsVserverRoot [$PrimaryVolIsVserverRoot]"
                Write-LogDebug "create_volume_voldr: PrimaryVolIsInfiniteVolume [$PrimaryVolIsInfiniteVolume]"
                Write-LogDebug "create_volume_voldr: PrimaryVolType [$PrimaryVolType]" 
            }
        }
	}
    Write-LogDebug "create_volume_voldr[$workOn]: end"
	return $Return  
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
Function remove_voldr(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
	[string] $mySecondaryVserver,
    [switch] $Source) {
Try {
	$Return = $True
	Write-LogDebug "remove_voldr: start"
    if($Source -eq $False){
        $mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar ).ClusterName			
	    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" } 

	    $SecondaryVolList = Get-NcVol -Controller $mySecondaryController -Vserver $mySecondaryVserver  -ErrorVariable ErrorVar  
	    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" } 
	    foreach ( $SecondaryVol in ( $SecondaryVolList | Skip-Null ) ) {
		    $SecondaryVolIsVserverRoot=$SecondaryVol.VolumeStateAttributes.IsVserverRoot
		    $SecondaryVolState=$SecondaryVol.State 
		    if ( $SecondaryVolIsVserverRoot -eq $False ) {
                Write-Log "[$mySecondaryVserver] Remove volume [$SecondaryVol]"
			    if ( $SecondaryVolState -ne 'offline' ) {
				    Write-LogDebug "Set-NcVol -Name  $SecondaryVol -Offline -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Confirm:$False"
				    $out = Set-NcVol -Name  $SecondaryVol -Offline -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar  -Confirm:$False
				    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcVol failed [$ErrorVar]" }
			    }
			    Write-LogDebug "Remove-NcVol -Name $SecondaryVol -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Confirm:$False"
			    $out = Remove-NcVol -Name $SecondaryVol -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar  -Confirm:$False
			    if ( $? -ne $True ) {
				    Write-LogError "ERROR: Unable to set volume [$SecondaryVol] offline" 
				    return $False	
			    }
		    }
	    }
	
	    $SecondaryVolList = Get-NcVol -Controller $mySecondaryController -Vserver $mySecondaryVserver  -ErrorVariable ErrorVar
	    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" } 
	    foreach ( $SecondaryVol in ( $SecondaryVolList | Skip-Null ) ) {
		    $SecondaryVolIsVserverRoot=$SecondaryVol.VolumeStateAttributes.IsVserverRoot
		    if ( $SecondaryVolIsVserverRoot -eq $True ) {
			    Write-Log "[$mySecondaryVserver] Remove root volume [$SecondaryVol]"
			    if ( $SecondaryVolState -ne 'offline' ) {
				    Write-LogDebug "Set-NcVol -Name  $SecondaryVol -Offline -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Confirm:$False"
				    $out = Set-NcVol -Name  $SecondaryVol -Offline -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
				    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcVol failed [$ErrorVar]" }
			    }
			    $out = Remove-NcVol -Name $SecondaryVol -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
			    if ( $? -ne $True ) {
				    Write-LogError "ERROR: Unable to set volume [$SecondaryVol] offline" 
				    return $False
			    }
		    }
	    }
    }else{
        $myPrimaryCluster = (Get-NcCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar ).ClusterName			
	    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" } 

	    $PrimaryVolList = Get-NcVol -Controller $myPrimaryController -Vserver $myPrimaryVserver  -ErrorVariable ErrorVar  
	    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" } 
	    foreach ( $PrimaryVol in ( $PrimaryVolList | Skip-Null ) ) {
		    $PrimaryVolIsVserverRoot=$PrimaryVol.VolumeStateAttributes.IsVserverRoot
		    $PrimaryVolState=$PrimaryVol.State 
		    if ( $PrimaryVolIsVserverRoot -eq $False ) {
                Write-Log "[$myPrimaryVserver] Remove volume [$PrimaryVol]"
			    if ( $PrimaryVolState -ne 'offline' ) {
				    Write-LogDebug "Set-NcVol -Name  $PrimaryVol -Offline -VserverContext $myPrimaryVserver -Controller $myPrimaryController -Confirm:$False"
				    $out = Set-NcVol -Name  $PrimaryVol -Offline -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar  -Confirm:$False
				    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcVol failed [$ErrorVar]" }
			    }
			    Write-LogDebug "Remove-NcVol -Name $PrimaryVol -VserverContext $myPrimaryVserver -Controller $myPrimaryController -Confirm:$False"
			    $out = Remove-NcVol -Name $PrimaryVol -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar  -Confirm:$False
			    if ( $? -ne $True ) {
				    Write-LogError "ERROR: Unable to set volume [$PrimaryVol] offline" 
				    return $False	
			    }
		    }
	    }
	
	    $PrimaryVolList = Get-NcVol -Controller $myPrimaryController -Vserver $myPrimaryVserver  -ErrorVariable ErrorVar
	    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" } 
	    foreach ( $PrimaryVol in ( $PrimaryVolList | Skip-Null ) ) {
		    $PrimaryVolIsVserverRoot=$PrimaryVol.VolumeStateAttributes.IsVserverRoot
		    if ( $PrimaryVolIsVserverRoot -eq $True ) {
			    Write-Log "[$myPrimaryVserver] Remove root volume [$PrimaryVol]"
			    if ( $PrimaryVolState -ne 'offline' ) {
				    Write-LogDebug "Set-NcVol -Name  $PrimaryVol -Offline -VserverContext $myPrimaryVserver -Controller $myPrimaryController -Confirm:$False"
				    $out = Set-NcVol -Name  $PrimaryVol -Offline -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar -Confirm:$False
				    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcVol failed [$ErrorVar]" }
			    }
			    $out = Remove-NcVol -Name $PrimaryVol -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar -Confirm:$False
			    if ( $? -ne $True ) {
				    Write-LogError "ERROR: Unable to set volume [$PrimaryVol] offline" 
				    return $False
			    }
		    }
	    }
    }
	return $Return 
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
    }
}

#############################################################################################
Function analyse_junction_path(
	[NetApp.Ontapi.Filer.C.NcController] $myController,
	[string] $myVserver,
	[switch] $Dest){
Try {
	$Return = $True 
    Write-LogDebug "analyse_junction_path: start"
	
	$RootVolumeName = (Get-NcVserver -Controller $myController -Vserver $myVserver  -ErrorVariable ErrorVar).RootVolume
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed to get RootVolume [$ErrorVar]" } 
	if ($RootVolumeName -eq $null ) { $Return = $False ; Write-logError "root volume not found for $myVserver" }			
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }
    if ($DebugLevel) {Write-LogDebug "Get-NcVol -Query @{Vserver=$myVserver;VolumeStateAttributes=@{IsVserverRoot=$false;State=""online""};VolumeIdAttributes=@{JunctionParentName=""$RootVolumeName""}} -Controller $myController"}
    $VolListNotNested=Get-NcVol -Query @{Vserver=$myVserver;VolumeStateAttributes=@{IsVserverRoot=$false;State="online"};VolumeIdAttributes=@{JunctionParentName="$RootVolumeName"}} -Controller $myController -ErrorVariable ErrorVar
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get NotNested Volumes failed [$ErrorVar]" }
    $Junctions=@()
    foreach ( $vol in ( $VolListNotNested | Skip-Null ) ) {
        $vol_detail = "" | Select-Object Name, JunctionPath, JunctionParent, Child, Permission, IsNested, Level, ParentPath #create customobject
        $vol_detail.Name=$vol.Name
        $vol_detail.JunctionParent=$RootVolumeName
        $vol_detail.JunctionPath=$vol.VolumeIdAttributes.JunctionPath
        $vol_detail.IsNested=$False
        $vol_detail.ParentPath=""
        $vol_detail.Level=($vol.VolumeIdAttributes.JunctionPath.split("/")).count
        if(($vol.VolumeIdAttributes.JunctionPath.split("/")).count -gt 2){
            $dir=($vol.VolumeIdAttributes.JunctionPath).split("/")[1]
        }else{
            $dir=$vol.VolumeIdAttributes.JunctionPath -replace "/",""
        }
        $vol_detail.Permission=(Read-NcDirectory -Controller $myController -VserverContext $myVserver -Path $("/vol/"+$RootVolumeName) | Where-Object {$_.Name -match $dir} | Select-Object Perm).Perm
        $volname=$vol.Name
        $perm=$vol_detail.Permission
        if ($DebugLevel) {Write-LogDebug "SVM [$myVserver] volume [$volname] Root [$RootVolumeName] dir [$dir] Perm [$perm]"}
        $vol_detail.Child=@()
        $Junctions+=$vol_detail
    }
    if ($DebugLevel) {Write-LogDebug "Get-NcVol -Query @{Vserver=$myVserver;VolumeStateAttributes=@{IsVserverRoot=$false;State=""online""};VolumeIdAttributes=@{JunctionParentName=""!$RootVolumeName"";JunctionPath=""!-,!/""}} -Controller $myController"}
    $VolListNested=Get-NcVol -Query @{Vserver=$myVserver;VolumeStateAttributes=@{IsVserverRoot=$false;State="online"};VolumeIdAttributes=@{JunctionParentName="!$RootVolumeName";JunctionPath="!-,!/"}} -Controller $myController -ErrorVariable ErrorVar
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get Nested Volumes failed [$ErrorVar]" }
    foreach ( $vol in ( $VolListNested | Skip-Null ) ) {
        $vol_detail = "" | Select-Object Name, JunctionPath, JunctionParent, Child, Permission, IsNested, Level, ParentPath #create customobject
        $vol_detail.Name=$vol.Name
        $vol_detail.JunctionParent=$vol.VolumeIdAttributes.JunctionParentName
        $vol_detail.JunctionPath=$vol.VolumeIdAttributes.JunctionPath
        $vol_detail.IsNested=$True
        $vol_detail.ParentPath=""
        $vol_detail.Level=($vol.VolumeIdAttributes.JunctionPath.split("/")).count
        $RootName=$vol_detail.JunctionParent
        $dir=($vol.VolumeIdAttributes.JunctionPath).split("/")[-1]
        $vol_detail.Permission=(Read-NcDirectory -Controller $myController -VserverContext $myVserver -Path $("/vol/"+$RootName) | Where-Object {$_.Name -match $dir} | Select-Object Perm).Perm
        $volname=$vol.Name
        $perm=$vol_detail.Permission
        if ($DebugLevel) {Write-LogDebug "SVM [$myVserver] volume [$volname] Root [$RootName] dir [$dir] Perm [$perm]"}
        $vol_detail.Child=@()
        $Junctions+=$vol_detail
    }
    foreach ($vol in $Junctions ){
        $volName=$vol.Name
        $children=$Junctions | Where-Object {$_.JunctionParent -eq $volName}
        foreach ($child in $children){
            $vol.Child+=$child.Name
        }   
    }
    foreach ($vol in $Junctions | Where-Object {$_.IsNested -eq $True}){
        $volName=$vol.Name
        $parent=$vol.JunctionParent
        $vol.ParentPath=($Junctions | Where-Object {$_.Name -eq $parent}).JunctionPath
    }
	if($Dest -eq $True){
		$script:vol_junction_dest=$Junctions
		$text=$Junctions | out-string
		if ($DebugLevel) {Write-LogDebug "vol_junction_dest = `n$text"}
	}else{
		$script:vol_junction=$Junctions
		$text=$Junctions | out-string
		if ($DebugLevel) {Write-LogDebug "vol_junction = `n$text"}
	}
    Write-LogDebug "analyse_junction_path: end"
    return $Return
}
Catch {
    handle_error $_ $myVserver
	return $Return
}
}

Function read_subdir (
    [NetApp.Ontapi.Filer.C.NcController] $myController,
    [string] $myVserver,
    [string] $Dirs,
    [string] $RootVolume,
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [string] $myPrimaryVserver)
{
    $Return=$True
    $fullpath=$("/vol/"+$RootVolume)
    foreach($dir in $Dirs.split("/")[1..$Dirs.split("/").count]){
        if($DebugLevel){Write-LogDebug "Work with dir [$dir]"}
        $fullpath+=$("/"+$dir)
        try{
            $searchPath=(Split-Path -Path $fullpath).replace('\','/')
            $PrimDirDetails=Read-NcDirectory -Path $searchPath -VserverContext $myPrimaryVserver -Controller $myPrimaryController | Where-Object {$_.Name -eq $dir}
            $PrimDirDetails | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Read-NcDirectory-"+$dir+".json") -Encoding ASCII -Width 65535
            if( ($ret=get-item $($Global:JsonPath+"Read-NcDirectory-"+$dir+".json") -ErrorAction SilentlyContinue) -ne $null ){
                Write-LogDebug "$($Global:JsonPath+"Read-NcDirectory-"+$dir+".json") saved successfully"
            }else{
                Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Read-NcDirectory-"+$dir+".json")"
                $Return=$False
            }
        }catch{
            handle_error $_ $myVserver
            return $Return    
        }
    } 
    return $Return  
}

#############################################################################################
Function mount_clone_voldr(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string] $workOn=$mySecondaryVserver,
    [string] $DestVserverDR="",
    [bool] $Backup,
    [bool] $Restore) 
{
Try {
    $Return = $True 
    Write-Log "[$workOn] Check SVM Volumes Junction-Path configuration"
    Write-LogDebug  "mount_clone_voldr[$myPrimaryVserver]: start"
    $myPrimaryCluster = (Get-NcCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar).ClusterName			
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" } 
    $mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar).ClusterName			
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" } 
    $ret=analyse_junction_path -myController $mySecondaryController -myVserver $mySecondaryVserver -Dest	
    if ($ret -ne $True){$Return=$False;Throw "ERROR : Failed to analyse_junction_path"}
    $ret=analyse_junction_path -myController $myPrimaryController -myVserver $myPrimaryVserver  	
    if ($ret -ne $True){$Return=$False;Throw "ERROR : Failed to analyse_junction_path"}
    foreach($volume in ( ($Script:vol_junction | Sort-Object -Property Level).Name ) ) {
        Write-LogDebug "mount_voldr [$volume]"
        $JunctionPath=$volume.JunctionPath
        $retry = $True ; $count = 0 
	    while ( ( $retry -eq $True ) -and ( $count -lt $MOUNT_RETRY_COUNT ) ) {
		    $count++
            $retry = $False
            Write-LogDebug "Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $DestVserverDR -DestinationVolume $volume -SourceVolume $volume -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -VserverContext $DestVserverDR -Controller $mySecondaryController"
            $relationList = Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $DestVserverDR -DestinationVolume $volume -SourceVolume $volume -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -VserverContext $DestVserverDR -Controller $mySecondaryController -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapMirror failed [$ErrorVar]" } 
            foreach ( $relation in ( $relationList | Skip-Null ) ) {
                $DestinationVolume=$relation.DestinationVolume
                Write-LogDebug "mount_voldr: work on destination volume [$DestinationVolume]"
                Write-LogDebug "Get current JunctionPath for volume [$DestinationVolume]"
                $remounted=$False
                if ( ($script:vol_junction | Where-Object {$_.Name -eq $DestinationVolume} | Measure-Object).count -eq 0 ){
                    Write-LogDebug "Volume [$DestinationVolume] does not need to be mounted in SVM namespace"
                }else{
                    $FindVolume=$script:vol_junction_dest | Where-Object {$_.Name -eq $DestinationVolume}
                    $CurrentJunctionPath=$FindVolume.JunctionPath
                    $FindVolume=$script:vol_junction | Where-Object {$_.Name -eq $DestinationVolume} 
                    $RequestedJunctionPath=$FindVolume.JunctionPath 
                    if($RequestedJunctionPath -ne $CurrentJunctionPath){
                        Write-LogDebug "Volume [$DestinationVolume] need to be remounted"
                        $remounted=$True
                    }else{
                        Write-LogDebug "Volume [$DestinationVolume] already mounted on [$CurrentJunctionPath] and Requested [$RequestedJunctionPath]"
                    }
                }
                if($remounted -eq $True){
                    Write-Log "[$workOn] Modify Junction Path for [$DestinationVolume]: from [$CurrentJunctionPath] to [$RequestedJunctionPath]"
                    $ret=umount_volume -myController $mySecondaryController -myVserver $mySecondaryVserver -myVolumeName $DestinationVolume
                    if($ret -ne $True){$Return=$False;Throw "ERROR: Failed to umount volume [$DestinationVolume] on [$mySecondaryVserver] because [$ErrorVar]"}
                    $ret=mount_volume -myController $mySecondaryController -myVserver $mySecondaryVserver -myVolumeName $DestinationVolume -myPrimaryController $myPrimaryController -myPrimaryVserver $myPrimaryVserver
                    if($ret -ne $True){$Return=$False;Throw "ERROR: Failed to mount volume [$DestinationVolume] on [$mySecondaryVserver] because [$ErrorVar]"}
                } 
            }
	    }
    }

    Write-LogDebug  "mount_clone_voldr[$myPrimaryVserver]: end"
	return $Return 
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}
#############################################################################################
Function mount_voldr(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) 
{
Try {
    $Return = $True 
    Write-Log "[$workOn] Check SVM Volumes Junction-Path configuration"
    Write-LogDebug  "mount_voldr[$myPrimaryVserver]: start"
    if($Restore -eq $False){
        $myPrimaryCluster = (Get-NcCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar).ClusterName			
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" } 
    }
    if($Backup -eq $False){
        $mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar).ClusterName			
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" } 
    }
    if($Backup -eq $False){
        $ret=analyse_junction_path -myController $mySecondaryController -myVserver $mySecondaryVserver -Dest	
        if ($ret -ne $True){$Return=$False;Throw "ERROR : Failed to analyse_junction_path"}
    }
    if($Restore -eq $False){
        $ret=analyse_junction_path -myController $myPrimaryController -myVserver $myPrimaryVserver  	
        if ($ret -ne $True){$Return=$False;Throw "ERROR : Failed to analyse_junction_path"}
    }else{
        if(Test-Path $($Global:JsonPath+"vol_junction.json")){
            $script:vol_junction=Get-Content $($Global:JsonPath+"vol_junction.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"vol_junction.json")
            Throw "ERROR: failed to read $filepath"
        }
    }
    if($Backup -eq $True){
        $script:vol_junction | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"vol_junction.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"vol_junction.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"vol_junction.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"vol_junction.json")"
            $Return=$False
        }
        $PathRead=@()
        foreach($junction in $script:vol_junction){
            $Name=$junction.Name
            $Parent=$junction.JunctionParent
            $JunctionPath=$junction.JunctionPath
            $ParentPath=$junction.ParentPath
            $IsNested=$junction.IsNested
            $ReadPath=(Split-Path -Path $JunctionPath).Replace('\','/')
            if($DebugLevel){Write-LogDebug "ReadPath is [$ReadPath] for JunctionPath [$JunctionPath] for volume [$Name] inside Parent [$Parent]"}
            if($ReadPath.Length -gt 1){
                if($DebugLevel) {Write-LogDebug "Need to Read all subdir in [$ReadPath]"}
                if($IsNested -eq $True){   
                    $RelativePathToRead=$ReadPath.replace($ParentPath,"") 
                    if($RelativePathToRead.Length -gt 1){
                        if($PathRead.contains($RelativePathToRead)){
                            Write-LogDebug("[$RelativePathToRead] already processed")
                        }else{
                            $ret=read_subdir -myController $myController -myVserver $myVserver -Dirs $RelativePathToRead -RootVolume $Parent -myPrimaryController $myPrimaryController -myPrimaryVserver $myPrimaryVserver
                            $PathRead+=$RelativePathToRead
                        }
                    }else{
                        if($DebugLevel) {Write-LogDebug "Ignore this junction Path [$ReadPath] for volume [$Name], because it will be automaticaly created"}
                    }
                }else{
                    if($PathRead.contains($ReadPath)){
                        Write-LogDebug("[$ReadPath] already processed")
                    }else{
                        $ret=read_subdir -myController $myController -myVserver $myVserver -Dirs $ReadPath -RootVolume $Parent -myPrimaryController $myPrimaryController -myPrimaryVserver $myPrimaryVserver
                        $PathRead+=$ReadPath
                    }
                }
            }else{
                if($DebugLevel) {Write-LogDebug "Ignore this junction Path [$ReadPath] for volume [$Name], because it will be automaticaly created"}    
            }
        }
        $PathRead=""
    }
    $fullpath=$("/vol/"+$RootVolume)
    foreach($volume in ( ($Script:vol_junction | Sort-Object -Property Level).Name ) ) {
        Write-LogDebug "mount_voldr [$volume]"
        $JunctionPath=$volume.JunctionPath
        $retry = $True ; $count = 0 
	    while ( ( $retry -eq $True ) -and ( $count -lt $MOUNT_RETRY_COUNT ) ) {
		    $count++
            $retry = $False
            if($Restore -eq $False -and $Backup -eq $False ){
                Write-LogDebug "Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $volume -SourceVolume $volume -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                $relationList = Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $volume -SourceVolume $volume -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapMirror failed [$ErrorVar]" } 
            }
            if($Restore -eq $True){
                if(Test-Path $($Global:JsonPath+"Get-NcVol.json")){
                    $relationList=Get-Content $($Global:JsonPath+"Get-NcVol.json") | ConvertFrom-Json
                    $relationList = $relationList | Where-Object {$_.VolumeStateAttributes.IsVserverRoot -ne $True}
                }else{
                    $Return=$False
                    $filepath=$($Global:JsonPath+"Get-NcVol.json")
                    Throw "ERROR: failed to read $filepath"
                }
            }
            if($Backup -eq $False){
                foreach ( $relation in ( $relationList | Skip-Null ) ) {
                    $MirrorState=$relation.MirrorState
                    #$SourceVolume=$relation.SourceVolume
                    if($Restore -eq $False){
                        $DestinationVolume=$relation.DestinationVolume
                        $SourceLocation=$relation.SourceLocation
                        $DestinationLocation=$relation.DestinationLocation
                        $RelationshipStatus=$relation.RelationshipStatus
                    }else{
                        $DestinationVolume=$relation.Name
                    }
                    Write-LogDebug "mount_voldr: work on destination volume [$DestinationVolume]"
                    if ( $MirrorState -eq "snapmirrored" -or $Restore -eq $True) {
                        Write-LogDebug "Get current JunctionPath for volume [$DestinationVolume]"
                        $remounted=$False
                        if ( ($script:vol_junction | Where-Object {$_.Name -eq $DestinationVolume} | Measure-Object).count -eq 0 ){
                            Write-LogDebug "Volume [$DestinationVolume] does not need to be mounted in SVM namespace"
                        }else{
                            $FindVolume=$script:vol_junction_dest | Where-Object {$_.Name -eq $DestinationVolume}
                            $CurrentJunctionPath=$FindVolume.JunctionPath
                            $FindVolume=$script:vol_junction | Where-Object {$_.Name -eq $DestinationVolume} 
                            $RequestedJunctionPath=$FindVolume.JunctionPath 
                            if($RequestedJunctionPath -ne $CurrentJunctionPath){
                                Write-LogDebug "Volume [$DestinationVolume] need to be remounted"
                                $remounted=$True
                            }else{
                                Write-LogDebug "Volume [$DestinationVolume] already mounted on [$CurrentJunctionPath] and Requested [$RequestedJunctionPath]"
                            }
                        }
                        if($remounted -eq $True){
                            Write-Log "[$workOn] Modify Junction Path for [$DestinationVolume]: from [$CurrentJunctionPath] to [$RequestedJunctionPath]"
                            $ret=umount_volume -myController $mySecondaryController -myVserver $mySecondaryVserver -myVolumeName $DestinationVolume
                            if($ret -ne $True){$Return=$False;Throw "ERROR: Failed to umount volume [$DestinationVolume] on [$mySecondaryVserver] because [$ErrorVar]"}
                            if($Restore -eq $False){
                                $ret=mount_volume -myController $mySecondaryController -myVserver $mySecondaryVserver -myVolumeName $DestinationVolume -myPrimaryController $myPrimaryController -myPrimaryVserver $myPrimaryVserver
                                if($ret -ne $True){$Return=$False;Throw "ERROR: Failed to mount volume [$DestinationVolume] on [$mySecondaryVserver] because [$ErrorVar]"}
                            }else{
                                $ret=mount_volume -myController $mySecondaryController -myVserver $mySecondaryVserver -myVolumeName $DestinationVolume -Restore
                                if($ret -ne $True){$Return=$False;Throw "ERROR: Failed to mount volume [$DestinationVolume] on [$mySecondaryVserver] because [$ErrorVar]"}    
                            }
                        }
                    } 
                    else {
                        if (  ( $MirrorState -eq "uninitialized" ) -and ( $RelationshipStatus -eq "transferring" ) ) {
                        if ( $count -eq $MOUNT_RETRY_COUNT ) { 
                                Write-LogError "ERROR: Unable to mount volume [$DestinationVolume]: Because Snapmirror relationship status is [$RelationshipStatus] [$MirrorState] " 
                                Write-LogError "ERROR: Please Retry Later" 
                                $Return = $False
                            } else {
                                $retry = $True
                            }
                            Write-Log "[$workOn] Snapmirror [$SourceLocation] [$DestinationLocation] in state [$RelationshipStatus] [$MirrorState] retry"						
                            Write-LogDebug "Wait [$count] and retry [$retry]"
                            Start-Sleep $count
                        } else {
                            $retry = $False
                            Write-LogError "ERROR: Unable to mount volume [$DestinationVolume]: Snapmirror, because relation status is [$RelationshipStatus] [$MirrorState] " 
                            $Return = $False
                        }	
                    }
                }
            }
	    }
    }
    Write-LogDebug  "mount_voldr[$myPrimaryVserver]: end"
	return $Return 
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
Function umount_voldr(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
	[string] $mySecondaryVserver,
    [switch] $Source) {

Try {
	$Return = $True

	$mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar).ClusterName			
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" } 

	Write-LogDebug "umount_voldr: start"
    if($Source -eq $False){
	    if ( ( $ret=analyse_junction_path -myController $mySecondaryController -myVserver $mySecondaryVserver -Dest) -ne $True ) {
    	    Write-LogError "ERROR: analyse_junction_path" 
		    clean_and_exit 1
	    }
        #$SecondaryVolList = Get-NcVol -Controller $mySecondaryController -Vserver $mySecondaryVserver  -ErrorVariable ErrorVar 
	    #if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" } 
	    #foreach ( $SecondaryVol in ( $SecondaryVolList | Skip-Null ) ) {
        foreach ( $SecondaryVol in ( ($Script:vol_junction_dest | Sort-Object -Descending -Property Level).Name ) ) {
		    Write-LogDebug "umount_voldr: umount volume [$SecondaryVol] on [$mySecondaryVserver] for [$mySecondaryController]"
		    # $SecondaryVolIsVserverRoot=$SecondaryVol.VolumeStateAttributes.IsVserverRoot
		    # if ( $SecondaryVolIsVserverRoot -eq $False ) {
		    # 	$out=Dismount-NcVol -Name $SecondaryVol  -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
		    # 	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Dismount-NcVol failed [$ErrorVar]" } 
		    # }
            $ret=umount_volume -myController $mySecondaryController -myVserver $mySecondaryVserver -myVolumeName $SecondaryVol
            if ($ret -ne $True){$Return=$False;Write-LogError "Failed to umount volume [$SecondaryVol] on [$mySecondaryVserver]"}
	    }
    }else{
        if ( ( $ret=analyse_junction_path -myController $myPrimaryController -myVserver $myPrimaryVserver) -ne $True ) {
    	    Write-LogError "ERROR: analyse_junction_path" 
		    clean_and_exit 1
	    }
        #$PrimaryVolList = Get-NcVol -Controller $myPrimaryController -Vserver $myPrimaryVserver  -ErrorVariable ErrorVar 
	    #if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" } 
	    #foreach ( $PrimaryVol in ( $PrimaryVolList | Skip-Null ) ) {
        foreach ( $PrimaryVol in ( ($Script:vol_junction | Sort-Object -Descending -Property Level).Name ) ) {
		    Write-LogDebug "umount_voldr: umount volume [$PrimaryVol] on [$myPrimaryVserver] for [$myPrimaryController]"
		    # $PrimaryVolIsVserverRoot=$PrimaryVol.VolumeStateAttributes.IsVserverRoot
		    # if ( $PrimaryVolIsVserverRoot -eq $False ) {
		    # 	$out=Dismount-NcVol -Name $PrimaryVol  -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
		    # 	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Dismount-NcVol failed [$ErrorVar]" } 
		    # }
            $ret=umount_volume -myController $myPrimaryController -myVserver $myPrimaryVserver -myVolumeName $PrimaryVol
            if ($ret -ne $True){$Return=$False;Write-LogError "Failed to umount volume [$PrimaryVol] on [$myPrimaryVserver]"}
	    }    
    }
	return $Return 
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}
#############################################################################################
Function check_cluster_peer(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController ) {
Try {
	$Return = $True
    if ($SINGLE_CLUSTER -eq $True) { return $Return }
	$myPrimaryCluster = (Get-NcCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar).ClusterName			
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" } 
	$mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar).ClusterName			
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" } 

	Write-LogDebug "check_cluster_peer: start"
	$PrimaryPeer=Get-NcClusterPeer -Name $mySecondaryCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcClusterPeer failed [$ErrorVar]" } 
	if ( $PrimaryPeer -eq $null ) {
		Write-LogError "ERROR: No Cluster Peer available from cluster [$myPrimaryController] to cluster [$mySecondaryController]" 
		Write-LogError "ERROR: Please check your cluster peer before using SVMDR " 
		clean_and_exit 2
	}		
	$SecondaryPeer=Get-NcClusterPeer -Name $myPrimaryCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar	
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcClusterPeer failed [$ErrorVar]" } 
	if ( $SecondaryPeer -eq $null ) {
		Write-LogError "ERROR: No Cluster Peer available from cluster [$mySecondaryController] to cluster [$myPrimaryController]" 
		Write-LogError "ERROR: Please check your cluster peer before using SVMDR " 
		clean_and_exit 2
	}

	$PrimaryAvailability=$PrimaryPeer.Availability
	$SecondaryAvailability=$SecondaryPeer.Availability

	Write-LogDebug "check_cluster_peer: PrimaryAvailability  [$PrimaryAvailability] "
	Write-LogDebug "check_cluster_peer: SecondaryAvailability [$SecondaryAvailability] "

	if ( ( $PrimaryAvailability -ne 'available' ) -or ( $SecondaryAvailability  -ne 'available' ) ) {
		Write-LogError "ERROR: Peer relation error between Clusters [$myPrimaryController] and [$mySecondaryController] " 
		Write-LogError "ERROR: Please check your cluster peer before using SVMDR "
		clean_and_exit 1
	}
	return $Return 
}
Catch {
    handle_error $_
	return $Return
}
}

#############################################################################################
Function get_vserver_peer_list(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
	[string] $mySecondaryVserver) {
Try {
	Write-LogDebug "get_vserver_peer_list: start"

	$ReturnVserverPeerList = @() 
	
	$myPrimaryCluster = (Get-NcCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar).ClusterName			
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" } 
	$mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar).ClusterName			
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" } 
	$CheckVserver = (Get-NcVserver -Vserver $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar).Vserver
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" } 
	if ( ( $CheckVserver -eq $null ) -or ( $CheckVserver -eq "" ) ) { 
		return $null
	}
	$Query=Get-NcVserverPeer -Template -Controller $myPrimaryController
	$Query.PeerCluster = $mySecondaryCluster
	$Query.Vserver=$myPrimaryVserver
	$Query.PeerState='peered'

	if ( $mySecondaryVserver ) {
		$Query.PeerVserver=$mySecondaryVserver
	}

	Write-LogDebug "Get-NcVserverPeer -Query $Query -Controller $myPrimaryController"
	$VserverPeerList=Get-NcVserverPeer -Query $Query -Controller $myPrimaryController  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserverPeer failed [$ErrorVar]" } 
	foreach ( $VserverPeer in ( $VserverPeerList | Skip-Null ) ) {
		$ReturnVserverPeerList += $VserverPeer.PeerVserver 
	}

	return $ReturnVserverPeerList 
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
Function check_create_cluster_peer(
    [NetApp.Ontapi.Filer.C.NcController]$SourceController,
	[NetApp.Ontapi.Filer.C.NcController]$PeerController
) {
Try {
    $Return = $True
    $clustername=$SourceController.Name
    Write-Log "[$clustername] Check Cluster Peering"
    Write-LogDebug "check_create_cluster_peer [$clustername]: start"
    $PeerClusterName=$PeerController.Name
    $SourceClusterName=$SourceController.Name
    Write-LogDebug "Get-NcClusterPeer -Name $PeerClusterName -Controller $SourceController"
    $ret=Get-NcClusterPeer -Name $PeerClusterName -Controller $SourceController -ErrorVariable ErrorVar 
    if ( $? -ne $True ) { Write-LogDebug "ERROR: Get-NcClusterPeer failed [$ErrorVar]"; return $False }
    if($ret -eq $null){
        Write-LogWarn "Cluster [$PeerClusterName] is not peered with Cluster [$SourceClusterName]"
        Write-LogWarn "Create Cluster Peering manualy, before running the script"
        $Return = $False
    }
    Write-LogDebug "check_create_cluster_peer[$clustername]: end"
	return $Return 
}
Catch {
    handle_error $_ $clustername
	return $Return
}
}

#############################################################################################
Function create_vserver_peer(
	[NetApp.Ontapi.Filer.C.NcController]$myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController]$mySecondaryController,
	[string]$myPrimaryVserver,
    [string]$mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) {
Try {
	$Return = $True
    Write-Log "[$workOn] Check SVM peering"
    Write-LogDebug "create_vserver_peer [$myPrimaryVserver]: start"
    if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
    if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}

    if($Backup -eq $False){
	    $mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar).ClusterName			
	    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" } 
    }
	if($Restore -eq $False -and $Backup -eq $False){
        $Peer = Get-NcVserverPeer -Vserver $myPrimaryVserver -PeerVserver $mySecondaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar	
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserverPeer failed [$ErrorVar]" } 
        if ( $Peer -eq $null ) {
            $Peer = Get-NcVserverPeer -Vserver $mySecondaryVserver  -PeerVserver $myPrimaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserverPeer failed [$ErrorVar]" } 
            if ( $Peer -eq $null ) {
                $Peer = Get-NcVserverPeer -Vserver $mySecondaryVserver  -PeerVserver $myPrimaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar	
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserverPeer failed [$ErrorVar]" } 
                Write-Log "[$workOn] create vserver peer: [$myPrimaryVserver] [$myPrimaryController] [$workOn] [$mySecondaryCluster]"
                Write-LogDebug "create_vserver_peer: New-NcVserverPeer -Vserver $myPrimaryVserver -Application snapmirror  -PeerVserver $mySecondaryVserver -PeerCluster $mySecondaryCluster -Controller $myPrimaryController"
                try{
                    if ( ($ret=check_create_cluster_peer -SourceController $myPrimaryController -PeerController $mySecondaryCluster) -eq $True){
                        $Peer=New-NcVserverPeer -Vserver $myPrimaryVserver -PeerVserver $mySecondaryVserver -Application snapmirror -PeerCluster $mySecondaryCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcVserverPeer failed [$ErrorVar]" }
                    }else {
                        $Return = $False ; Write-LogWarn "Enable to create Vserver Peering"    
                    }
                }catch{
                    Write-LogWarn "Failed to create new Vserver Peer reason [$_]"
                }
            }
        }
        $PeerState = $Peer.PeerState
        if ( $PeerState -ne "peered" ) {
            if ( $PeerState -eq "initiated" ){
                Write-LogDebug "Confirm-NcVserverPeer -Vserver $mySecondaryVserver -PeerVserver $myPrimaryVserver -Controller $mySecondaryController"
                try{
                    $out = Confirm-NcVserverPeer -Vserver $mySecondaryVserver -PeerVserver $myPrimaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) {$Return = $False;throw "ERROR: Confirm-NcVserverPeer Failed [$ErrorVar]"}
                }catch{
                    Write-LogWarn "Failed to confirm new Vserver Peer reason [$_]"
                }
            }else{
                Write-LogError "ERROR: PeerState [$PeerState] between vserver [$myPrimaryVserver] [$mySecondaryVserver]" 
                $Return = $False
            }
        }
    }
    if($Restore -eq $True){
        if(Test-Path $($Global:JsonPath+"Get-NcVserverPeer.json")){
            $PrimaryVserver=Get-Content $($Global:JsonPath+"Get-NcVserverPeer.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcVserverPeer.json")
            Throw "ERROR: failed to read $filepath"
        } 
        foreach($svmpeer in $PrimaryVserver){
            $PVserver=$svmpeer.Vserver
            $PVserverPeer=$svmpeer.PeerVserver
            $PPeerState=$svmpeer.PeerState
            $PPeerCluster=$svmpeer.PeerCluster
            $PPeerApplication=$svmpeer.Applications
            try{
                if ( ($ret=check_create_cluster_peer -SourceController $mySecondaryController -PeerController $PPeerCluster) -eq $True){
                    $ret=New-NcVserverPeer -Vserver $PVserver -PeerVserver $PVserverPeer -Application $PPeerApplication -PeerCluster $PPeerCluster -Controller $mySecondaryController -ErrorVariable ErrorVar -Confirm:$false
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcVserverPeer failed [$ErrorVar]" }
                    Write-Log "[$workOn] Don't forget to accept Vserver Peering on Cluster [$PPeerCluster] for SVM [$PVserverPeer]"
                }else{
                    $Return = $False ; Write-LogWarn "Enable to create Vserver Peering"    
                }
            }catch{
                Write-LogWarn "Failed to create new Vserver Peer relationship reason [$_]"
            }
        }   
    }
    if($Backup -eq $True){
        $Peers = Get-NcVserverPeer -VserverContext $myPrimaryVserver -PeerState @("!rejected","!suspended","!deleted") -Controller $myPrimaryController -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserverPeer failed [$ErrorVar]" }
        $Peers | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcVserverPeer.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcVserverPeer.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcVserverPeer.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcVserverPeer.json")"
            $Return=$False
        }
    }
    Write-LogDebug "create_vserver_peer[$myPrimaryVserver]: end"
	return $Return 
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
Function remove_vserver_peer(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
	[string] $mySecondaryVserver) {
Try {

	$Return  = $True

	$myPrimaryCluster = (Get-NcCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar).ClusterName			
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" } 
	$mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar).ClusterName			
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" } 

	Write-LogDebug "remove_vserver_peer: start"


	$Peer = Get-NcVserverPeer -Vserver $myPrimaryVserver  -PeerVserver $mySecondaryVserver -Controller $myPrimaryController	  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserverPeer failed [$ErrorVar]" }
	if ( $Peer -ne $null ) {
		Write-LogDebug "Remove-NcVserverPeer -Vserver $myPrimaryVserver -PeerVserver $mySecondaryVserver -Controller $myPrimaryController -Confirm:$False"	
		Remove-NcVserverPeer -Vserver $myPrimaryVserver -PeerVserver $mySecondaryVserver  -Controller $myPrimaryController  -ErrorVariable ErrorVar -Confirm:$False
		if ( $? -ne $True ) { $Return  = $False ; throw "ERROR: Remove-NcVserverPeer failed [$ErrorVar]"  }
	}

	$Peer = Get-NcVserverPeer -Vserver $mySecondaryVserver  -PeerVserver $myPrimaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar	
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserverPeer failed [$ErrorVar]" }
	if ( $Peer -ne $null ) {
		Write-LogDebug "Remove-NcVserverPeer -Vserver $mySecondaryVserver -PeerVserver $myPrimaryVserver  -Controller $mySecondaryController -Confirm:$False"
		Remove-NcVserverPeer -Vserver $mySecondaryVserver -PeerVserver $myPrimaryVserver  -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
		if ( $? -ne $True ) { $Return  = $False;  throw "ERROR: Remove-NcVserverPeer failed [$ErrorVar]"
		}
	}
	return $Return 
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}
#############################################################################################
Function set_snapmirror_schedule_dr(
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string] $mySchedule) 
{
    Try 
    {

        $Return = $True 
        Write-logDebug "set_snapmirror_schedule_dr: start"
        $myPrimaryCluster = (Get-NcCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar).ClusterName          
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }
        $mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar).ClusterName          
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }

        Write-LogDebug "Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
        $relationList = Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapmirror failed [$ErrorVar]" }
        foreach ( $relation in ( $relationList | Skip-Null ) ) {
            $MirrorState=$relation.MirrorState
            $SourceVolume=$relation.SourceVolume
            $DestinationVolume=$relation.DestinationVolume
            $SourceLocation=$relation.SourceLocation
            $DestinationLocation=$relation.DestinationLocation
            $RelationshipStatus=$relation.RelationshipStatus
            if ( $mySchedule -eq 'none' ) 
            {
                Write-LogDebug "Set-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $DestinationVolume -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $SourceVolume -Schedule   -Controller $mySecondaryController"
                $out = Set-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $DestinationVolume -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $SourceVolume -Schedule "" -Controller $mySecondaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcSnapmirror failed [$ErrorVar]" }
            } 
            else 
            {
                Write-LogDebug "Set-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $DestinationVolume -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $SourceVolume -Schedule $mySchedule -Controller $mySecondaryController"
                $out = Set-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $DestinationVolume -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $SourceVolume -Schedule $mySchedule -Controller $mySecondaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcSnapmirror failed [$ErrorVar]" }
            }
        }
        Write-logDebug "set_snapmirror_schedule_dr: end"
        return $Return 
    }
    Catch 
    {
        handle_error $_ $myPrimaryVserver
        return $Return
    }
}
#############################################################################################
Function check_snapmirror_broken_dr(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
	[string] $mySecondaryVserver) {
Try {

	$Return = $True 

	$myPrimaryCluster = (Get-NcCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar).ClusterName			
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }
	$mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar).ClusterName			
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }

	Write-LogDebug "Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
	$relationList = Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapmirror failed [$ErrorVar]" }
	foreach ( $relation in ( $relationList | Skip-Null ) ) {
		$MirrorState=$relation.MirrorState
		$SourceVolume=$relation.SourceVolume
		$DestinationVolume=$relation.DestinationVolume
		$SourceLocation=$relation.SourceLocation
		$DestinationLocation=$relation.DestinationLocation
		$RelationshipStatus=$relation.RelationshipStatus
		if ( ( $MirrorState -eq "broken-off" ) -and ( $RelationshipStatus -eq "idle" ) ) {
			Write-LogDebug "Relation [$SourceLocation] [$DestinationLocation] is [$MirrorState] [$RelationshipStatus] "
		} else {
			Write-LogError "ERROR: Relation [$SourceLocation] [$DestinationLocation] is [$MirrorState] [$RelationshipStatus]" 
			$Return = $False
		}
	}
	return $Return 
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}
#############################################################################################
Function wait_snapmirror_dr(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[switch] $NoInteractive,
	[string] $myPrimaryVserver,
	[string] $mySecondaryVserver) 
{
    Try {

    	$Return = $True 
        Write-Log "[$mySecondaryVserver] Wait SnapMirror relationships"
        Write-LogDebug "wait_snapmirror_dr[$myPrimaryVserver]: start"

    	$myPrimaryCluster = (Get-NcCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar).ClusterName			
    	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }
    	$mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar).ClusterName			
    	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }

    	Write-Log "[$mySecondaryVserver] Please wait until all snapmirror transfers terminate"

    	$loop = $True ; $count = 0 

    	while ( $loop -eq $True ) 
        {
    		$count++
    		$loop = $False
    		Write-LogDebug "Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
            $relationList = Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapmirror failed [$ErrorVar]" }
            if($relationList -eq $null){
                Write-LogDebug "No SnapMirror relationship"
                return $True
            }
    		foreach ( $relation in ( $relationList | Skip-Null ) ) 
            {
    			$MirrorState=$relation.MirrorState
    			$SourceVolume=$relation.SourceVolume
    			$DestinationVolume=$relation.DestinationVolume
    			$SourceLocation=$relation.SourceLocation
    			$DestinationLocation=$relation.DestinationLocation
    			$RelationshipStatus=$relation.RelationshipStatus
    			Write-LogDebug "Relation [$SourceLocation] [$DestinationLocation] is [$MirrorState] [$RelationshipStatus] "
    			if ( ( ( $MirrorState -eq "uninitialized" ) -or ( $MirrorState -eq "snapmirrored" ) -or ( $MirrorState -eq "broken-off" ) ) -and ( $RelationshipStatus -eq "transferring" -or $RelationshipStatus -eq "finalizing") ) 
                {
    				$loop = $True
    			} 
                elseif ( ( $MirrorState -eq "snapmirrored" ) -and ( $RelationshipStatus -eq "idle" ) ) 
                {} 
                else 
                {
    				Write-LogError "ERROR: Relation [$SourceLocation] [$DestinationLocation] is [$MirrorState] [$RelationshipStatus] " 
    				$Return = $False
    			}
    		}
    		sleep $count
    		if ( ( ! $NoInteractive ) -and ( $DebugLevel -eq 0 ) ) { Write-Host -NoNewline "." }
    	}
    	if ( ( ! $NoInteractive ) -and ( $DebugLevel -eq 0 ) ) { Write-Host "" }
    	Write-Log "[$mySecondaryVserver] All Snapmirror transfers terminated"
        Write-LogDebug "wait_snapmirror_dr[$myPrimaryVserver]: end"
    	return $Return 
    } 
    Catch 
    {
        handle_error $_ $myPrimaryVserver
    	return $Return
    }
}

#############################################################################################
Function create_snapmirror_dr(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$DDR=$False,
    [switch] $Force,
    [bool]$Backup,
    [bool]$Restore) {
Try {

    $Return = $True 
    Write-LogDebug "create_snapmirror_dr[$myPrimaryVserver]: start"
    if($Backup -eq $True -or $Restore -eq $True){
        Write-LogDebug "Backup or Restore mode does create any SnapMirror Relationship"
        Write-LogDebug "create_snapmirror_dr[$myPrimaryVserver]: end"
        return $Return
    }
    Write-Log "[$workOn] Create SVM SnapMirror configuration"
	$myPrimaryCluster = (Get-NcCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar).ClusterName			
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }
	$mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar).ClusterName			
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }
	
	Write-LogDebug "Check ONTAP version"
	$PrimaryVersion=(Get-NcSystemVersionInfo -Controller $myPrimaryController).VersionTupleV
	$SecondaryVersion=(Get-NcSystemVersionInfo -Controller $mySecondaryController).VersionTupleV
	$PrimaryVersionString=$PrimaryVersion | out-string
	$SecondaryVersionString=$SecondaryVersion | out-string
	Write-LogDebug "Primary version is $PrimaryVersionString"
	Write-LogDebug "Seconday version is $SecondaryVersionString"
	$vfrEnable=$False
	if(($PrimaryVersion.Major -ne $SecondaryVersion.Major) -or ($PrimaryVersion.Major -eq 8 -and $SecondaryVersion.Major -eq 8)){
		if($PrimaryVersion.Major -ge 9 -and $SecondaryVersion.Major -ge 9){
			$vfrEnable=$True
		}
		elseif(($PrimaryVersion.Major -eq 8 -and $PrimaryVersion.Minor -ge 3 -and $PrimaryVersion.Build -ge 2) -and ($SecondaryVersion.Major -ge 9)){
			$vfrEnable=$True
		}
		elseif(($SecondaryVersion.Major -eq 8 -and $SecondaryVersion.Minor -ge 3 -and $SecondaryVersion.Build -ge 2) -and ($PrimaryVersion.Major -ge 9)){
			$vfrEnable=$True
		}
		elseif(($PrimaryVersion.Major -eq 8 -and $PrimaryVersion.Minor -ge 3 -and $PrimaryVersion.Build -ge 2) -and ($SecondaryVersion.Major -eq 8 -and $SecondaryVersion.Minor -ge 3 -and $SecondaryVersion.Build -ge 2)){
			$vfrEnable=$True
		}
	}
    if($PrimaryVersion.Major -ge 9 -and $SecondaryVersion.Major -ge 9){
	    $vfrEnable=$True
	}
	Write-Log "[$workOn] VFR mode is set to [$vfrEnable]"
    if($Global:SelectVolume -eq $True)
    {
        $Selected=get_volumes_from_selectvolumedb $myPrimaryController $myPrimaryVserver
        if($Selected.state -ne $True)
        {
            Write-Log "[$workOn] Failed to get Selected Volume from DB, check selectvolume.db file inside $Global:SVMTOOL_DB"
            Write-logDebug "check_update_voldr: end with error"
            return $False  
        }else{
            $VolList=$Selected.volumes
            Write-LogDebug "Get-NcVol -Name $VolList -Vserver $myPrimaryVserver -Controller $myPrimaryController"
            $PrimaryVolList=Get-NcVol -Name $VolList -Vserver $myPrimaryVserver -Controller $myPrimaryController -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
        }    
    }else{
        Write-LogDebug "Get-NcVol -Vserver $myPrimaryVserver -Controller $myPrimaryController"
        $PrimaryVolList = Get-NcVol -Controller $myPrimaryController -Vserver $myPrimaryVserver -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }  
    }
	foreach ( $PrimaryVol in ( $PrimaryVolList | Skip-Null ) ) 
    {
		$PrimaryVolName=$PrimaryVol.Name
		$PrimaryVolState=$PrimaryVol.State
		$PrimaryVolType=$PrimaryVol.VolumeIdAttributes.Type
		$PrimaryVolIsVserverRoot=$PrimaryVol.VolumeStateAttributes.IsVserverRoot
		$PrimaryVolIsInfiniteVolume=$PrimaryVol.IsInfiniteVolume
			
		if ( ( $PrimaryVolState -eq "online" ) -and ( $PrimaryVolType -eq "rw" ) -and ( $PrimaryVolIsVserverRoot -eq $False ) -and ( $PrimaryVolIsInfiniteVolume -eq $False ) ) 
        {
			Write-LogDebug "Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVolName -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $PrimaryVol -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
			$relation=Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVolName -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $PrimaryVol -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
			if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapmirror failed [$ErrorVar]" }
			if ( $relation -eq $null ) 
            {
                if( ($Force -eq $False) -and ($DDR -eq $False) )
                {
                    if($vfrEnable -eq $False){
        			    Write-LogDebug "New-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVolName -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $PrimaryVolName -Controller $mySecondaryController "
        			    Write-Log "[$workOn] Create SnapMirror [${myPrimaryVserver}:$PrimaryVol] -> [${mySecondaryVserver}:$PrimaryVol]"
        			    $relation=New-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVolName -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $PrimaryVolName -Controller $mySecondaryController  -ErrorVariable ErrorVar 
        			    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcSnapmirror failed [$ErrorVar]" }
                    }else{
                        Write-LogDebug "New-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVolName -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $PrimaryVolName -Schedule hourly -type vault -policy $Global:XDPPolicy -Controller $mySecondaryController "
        			    Write-Log "[$workOn] Create VF SnapMirror [${myPrimaryVserver}:$PrimaryVol] -> [${mySecondaryVserver}:$PrimaryVol]"
        			    $relation=New-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVolName -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $PrimaryVolName -Schedule hourly -type vault -policy $Global:XDPPolicy -Controller $mySecondaryController  -ErrorVariable ErrorVar 
        			    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcSnapmirror failed [$ErrorVar]" }
                    }
        			Write-LogDebug "Invoke-NcSnapmirrorInitialize -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVol -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $PrimaryVol -Controller $mySecondaryController"
        			$relation=Invoke-NcSnapmirrorInitialize -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVol -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $PrimaryVol -Controller $mySecondaryController  -ErrorVariable ErrorVar
        			if ( $? -ne $True ) 
                    { 
        				Write-LogError "ERROR: Snapmirror Initialize failed"
        				$Return = $False
        			}
                }
                elseif($Force -eq $True -and $DDR -eq $False)
                {
                    if($vfrEnable -eq $False){
                        Write-LogDebug "New-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVolName -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $PrimaryVolName -Controller $mySecondaryController "
        			    Write-Log "[$workOn] Create SnapMirror [${myPrimaryVserver}:$PrimaryVol] -> [${mySecondaryVserver}:$PrimaryVol]"
        			    $relation=New-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVolName -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $PrimaryVolName -Controller $mySecondaryController  -ErrorVariable ErrorVar 
        			    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcSnapmirror failed [$ErrorVar]" }
                    }else{
                        Write-LogDebug "New-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVolName -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $PrimaryVolName -Schedule hourly -type vault -policy $Global:XDPPolicy -Controller $mySecondaryController "
        			    Write-Log "[$workOn] Create VF SnapMirror [${myPrimaryVserver}:$PrimaryVol] -> [${mySecondaryVserver}:$PrimaryVol]"
        			    $relation=New-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVolName -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $PrimaryVolName -Schedule hourly -type vault -policy $Global:XDPPolicy -Controller $mySecondaryController  -ErrorVariable ErrorVar 
        			    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcSnapmirror failed [$ErrorVar]" }
                    }   
                }
                elseif($DDR -eq $True)
                {
                    Write-LogDebug "Enter DRfromDR mode"
                    Write-LogDebug "Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVolName -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                    $relationDRList = Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVolName -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapmirror failed [$ErrorVar]" }
                    foreach ( $relationDR in ( $relationDRList | Skip-Null ) ) {
                        $MirrorState=$relationDR.MirrorState
                        $SourceVolume=$relationDR.SourceVolume
                        $DestinationVolume=$relationDR.DestinationVolume
                        $SourceLocation=$relationDR.SourceLocation
                        $DestinationLocation=$relationDR.DestinationLocation
                        $RelationshipStatus=$relationDR.RelationshipStatus
                        if ( ( $MirrorState -eq 'snapmirrored') -and ($RelationshipStatus -eq 'idle' ) ) 
                        {
                            Write-Log "[$workOn] Break relation [$SourceLocation] -> [$DestinationLocation]"
                            if($DebugLevel){Write-LogDebug "Invoke-NcSnapmirrorBreak -Destination $DestinationLocation -Source $SourceLocation -Controller $mySecondaryController -Confirm:$False"}
                            $out=Invoke-NcSnapmirrorBreak -Destination $DestinationLocation -Source $SourceLocation -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
                            if ( $? -ne $True ) 
                            {
                                $Return = $False ; throw "ERROR: Invoke-NcSnapmirrorBreak failed"
                            }
                            Write-Log "[$workOn] Remove relation [$SourceLocation] -> [$DestinationLocation]"
                            Write-LogDebug "Remove-NcSnapmirror -Destination $DestinationLocation -Source $SourceLocation -Controller $mySecondaryController -Confirm:$False"
                            $out=Remove-NcSnapmirror -Destination $DestinationLocation -Source $SourceLocation -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False   
                            if ( $? -ne $True ) 
                            {
                                $Return = $False ; throw "ERROR: Remove-NcSnapmirror failed"
                            }
                        } 
                        else 
                        {
                            if($MirrorState -eq 'snapmirrored')
                            {
                                Write-LogError "ERROR: The relation [$SourceLocation] [$DestinationLocation] status is [$RelationshipStatus] [$MirrorState] " 
                                $ANS=Read-HostOptions "Do you want to break this relation ?" "y/n"
                                if ( $ANS -eq 'y' ) 
                                {
                                    Write-Log "[$workOn] Break relation [$SourceLocation] -> [$DestinationLocation]"
                                    Write-LogDebug "Invoke-NcSnapmirrorBreak -Destination $DestinationLocation -Source $SourceLocation -Controller $mySecondaryController -Confirm:$False"
                                    $out=Invoke-NcSnapmirrorBreak -Destination $DestinationLocation -Source $SourceLocation -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
                                    if ( $? -ne $True ) 
                                    {
                                        $Return = $False ; throw "ERROR: Invoke-NcSnapmirrorBreak failed"
                                    }
                                
                                }
                            }
                            Write-Log "[$workOn] Remove relation [$SourceLocation] -> [$DestinationLocation]"
                            Write-LogDebug "Remove-NcSnapmirror -Destination $DestinationLocation -Source $SourceLocation -Controller $mySecondaryController -Confirm:$False"
                            $out=Remove-NcSnapmirror -Destination $DestinationLocation -Source $SourceLocation -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False   
                            if ( $? -ne $True ) 
                            {
                                $Return = $False ; throw "ERROR: Remove-NcSnapmirror failed"
                            }   
                            $Return = $True
                        }
                        if($vfrEnable -eq $False){
                            Write-LogDebug "New-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVolName -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $PrimaryVolName -Controller $mySecondaryController "
                            Write-Log "[$workOn] Create relation [${myPrimaryVserver}:$PrimaryVolName] -> [${mySecondaryVserver}:$PrimaryVolName]"
                            $relation=New-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVolName -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $PrimaryVolName -Controller $mySecondaryController  -ErrorVariable ErrorVar 
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcSnapmirror failed [$ErrorVar]" }
                        }else{
                            Write-LogDebug "New-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVolName -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $PrimaryVolName -Schedule hourly -type vault -policy $Global:XDPPolicy -Controller $mySecondaryController "
                            Write-Log "[$workOn] Create VF relation [${myPrimaryVserver}:$PrimaryVolName] -> [${mySecondaryVserver}:$PrimaryVolName]"
                            $relation=New-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVolName -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $PrimaryVolName -Schedule hourly -type vault -policy $Global:XDPPolicy -Controller $mySecondaryController  -ErrorVariable ErrorVar 
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcSnapmirror failed [$ErrorVar]" }
                        }
                        Write-Log "[$workOn] Resync relation [${myPrimaryVserver}:$PrimaryVolName] -> [${mySecondaryVserver}:$PrimaryVolName]"
                        Write-LogDebug "Invoke-NcSnapmirrorResync -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVol -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $PrimaryVol -Controller $mySecondaryController"
                        $out=Invoke-NcSnapmirrorResync -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVol -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $PrimaryVol -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
                        if ( $? -ne $True ) 
                        {
                            Write-LogError "ERROR: Snapmirror Resync failed" 
                            $Return = $False
                        }
                    }
                }
			} 
            else 
            {
				Write-Log "[$workOn] Relation [${myPrimaryController}:${myPrimaryVserver}:${PrimaryVol}] [${mySecondaryController}:${mySecondaryVserver}:${PrimaryVol}] already exist"
			}
			if ( $relation.MirrorState -eq "uninitialized" ) 
            {
				if ( $relation.Status -eq "idle" ) 
                {
					Write-LogDebug "Invoke-NcSnapmirrorInitialize -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVol -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $PrimaryVol -Controller $mySecondaryController"
					$relation=Invoke-NcSnapmirrorInitialize -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $PrimaryVol -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $PrimaryVol -Controller $mySecondaryController  -ErrorVariable ErrorVar
					if ( $? -ne $True ) 
                    { 
						Write-LogError "ERROR: Snapmirror Initialize failed"
						$Return = $False
					}
				} 
                else 
                {
					$tmp_str= $relation.Status 
					Write-LogWarn "relation [[${myPrimaryController}:${myPrimaryVserver}:${PrimaryVol}]] -> [${mySecondaryController}:${mySecondaryVserver}:${PrimaryVol}]"
					Write-LogWarn "status: [uninitiliazed] [$tmp_str]" 
					$Return = $True 
				}
			}
		}
	}	
    Write-LogDebug "create_snapmirror_dr: end"
	return $Return 
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
Function remove_snapmirror_dr (
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
	[string] $mySecondaryVserver,
    [switch] $NoRelease) {
Try {

	$Return = $True 
    Write-logDebug "remove_snapmirror_dr: start"
	$myPrimaryCluster = (Get-NcCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar).ClusterName			
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }
	$mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar).ClusterName			
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }

	Write-LogDebug "Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
	$relationList=Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapmirror failed [$ErrorVar]" }
	foreach ( $relation in ( $relationList  | Skip-Null ) ) {
			$MirrorState=$relation.MirrorState
			$SourceVolume=$relation.SourceVolume
			$DestinationVolume=$relation.DestinationVolume
			$SourceLocation=$relation.SourceLocation
			$DestinationLocation=$relation.DestinationLocation
			$MirrorState=$relation.MirrorState	
			Write-Log "remove snapmirror relation for volume [$SourceLocation] [$DestinationLocation]"
			if ( $MirrorState -eq 'snapmirrored' ) {
				Write-LogDebug "Invoke-NcSnapmirrorBreak -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume  $DestinationVolume -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver  -SourceVolume $SourceVolume  -Controller  $mySecondaryController -Confirm:$False"
				$out= Invoke-NcSnapmirrorBreak -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume  $DestinationVolume -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver  -SourceVolume $SourceVolume  -Controller  $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
				if ( $? -ne $True ) {
					Write-LogError "ERROR: Unable to Break relation [$SourceLocation] [$DestinationLocation]" 
					$Return = $True 
				}
			}
			Write-LogDebug "Remove-NcSnapmirror -SourceLocation $SourceLocation -DestinationLocation $DestinationLocation -Controller $mySecondaryController -Confirm:$False"
			$out = Remove-NcSnapmirror -SourceLocation $SourceLocation -DestinationLocation $DestinationLocation -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
			if ( $? -ne $True ) {
				Write-LogError "ERROR: Unable to remove relation [$SourceLocation] [$DestinationLocation]" 
				$Return = $True 
				return $Return
			}
	}
	
    if(!$NoRelease.IsPresent){
	    if($DebugLevel) {Write-LogDebug "Get-NcSnapmirrorDestination  -SourceVserver $myPrimaryVserver -DestinationVserver $mySecondaryVserver  -VserverContext $myPrimaryVserver -Controller $myPrimaryController"}
	    $relationList=Get-NcSnapmirrorDestination  -SourceVserver $myPrimaryVserver -DestinationVserver $mySecondaryVserver  -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
	    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapmirrorDestination failed [$ErrorVar]" }
	    foreach ( $relation in ( $relationList | Skip-Null ) ) {
			    $MirrorState=$relation.MirrorState
			    $SourceVolume=$relation.SourceVolume
			    $DestinationVolume=$relation.DestinationVolume
			    $SourceLocation=$relation.SourceLocation
			    $DestinationLocation=$relation.DestinationLocation
			    $RelationshipId=$relation.RelationshipId
			
			    Write-Log "Release Relation [$SourceLocation] [$DestinationLocation]"
			    if($DebugLevel) {Write-LogDebug "Invoke-NcSnapmirrorRelease -DestinationCluster  $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $DestinationVolume -SourceCluster  $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $SourceVolume  -RelationshipId $RelationshipId -Controller $myPrimaryController -Confirm:$False"}
			    $out = Invoke-NcSnapmirrorRelease -DestinationCluster  $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $DestinationVolume -SourceCluster  $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $SourceVolume  -RelationshipId $RelationshipId -Controller $myPrimaryController  -ErrorVariable ErrorVar -Confirm:$False
			    if ( $? -ne $True ) {
				    Write-LogError "ERROR: Unable to Release relation [$SourceLocation] [$DestinationLocation]" 
				    $Return = $True 
			    }
	    }
    }
    Write-logDebug "remove_snapmirror_dr: end"
	return $Return 
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
Function create_lif_dr(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [switch] $UpdateLif,
    [bool]$Backup,
    [bool]$Restore)
 {
Try {

    $Return = $True 
    Write-Log "[$workOn] Check SVM LIF"
    Write-LogDebug "create_lif_dr[$myPrimaryVserver]: start"
    if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
    if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}

    if($Restore -eq $False){
        $PrimaryInterfaceList = Get-NcNetInterface -Role DATA -VserverContext $myPrimaryVserver -DataProtocols cifs,nfs,none,iscsi -Controller $myPrimaryController  -ErrorVariable ErrorVar 
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNetInterface failed [$ErrorVar]" }
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcNetInterface.json")){
            $PrimaryInterfaceList=Get-Content $($Global:JsonPath+"Get-NcNetInterface.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcNetInterface.json")
            Throw "ERROR: failed to read $filepath"
        }
    }
    if($Backup -eq $True){
        $PrimaryInterfaceList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcNetInterface.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcNetInterface.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcNetInterface.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcNetInterface.json")"
            $Return=$False
        }
    } 
    foreach ( $PrimaryInterface in ( $PrimaryInterfaceList | Skip-Null ) ) {
        $myIpAddr=$null
        $myNetMask=$null
        $myGateway=$null
        $PrimaryInterfaceName=$PrimaryInterface.InterfaceName
        $PrimaryAddress=$PrimaryInterface.Address
        $PrimaryNetmask=$PrimaryInterface.Netmask
        $PrimaryCurrentPort=$PrimaryInterface.CurrentPort
        $PrimaryDataProtocols=$PrimaryInterface.DataProtocols
        $PrimaryDnsDomainName=$PrimaryInterface.DnsDomainName
        $PrimaryRole=$PrimaryInterface.Role
        $PrimaryCurrentNode=$PrimaryInterface.CurrentNode
        $PrimaryCurrentPort=$PrimaryInterface.CurrentPort
        $PrimaryRoutingGroupName=$PrimaryInterface.RoutingGroupName
        $PrimaryFirewallPolicy=$PrimaryInterface.FirewallPolicy
        $PrimaryIsAutoRevert=$PrimaryInterface.IsAutoRevert
        if($Restore -eq $False){
            $VersionTuple=(Get-NcSystemVersionInfo -Controller $myPrimaryController | Select-Object VersionTuple).VersionTuple
            if($VersionTuple.Generation -ge 9){
                Write-LogDebug "[$myPrimaryController] run ONTAP 9.X"
                Write-LogDebug "Get-NcNetRoute -Query @{Destination=0.0.0.0/0;Vserver=$myPrimaryVserver} -Controller $myPrimaryController"
                $PrimaryDefaultRoute=Get-NcNetRoute -Query @{Destination="0.0.0.0/0";Vserver=$myPrimaryVserver} -Controller $myPrimaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ){$Return = $False ; throw "ERROR: Get-NcNetRoute failed [$ErrorVar]"}
                if($Backup -eq $True){
                    $PrimaryDefaultRoute | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcNetRoute.json") -Encoding ASCII -Width 65535
                    if( ($ret=get-item $($Global:JsonPath+"Get-NcNetRoute.json") -ErrorAction SilentlyContinue) -ne $null ){
                        Write-LogDebug "$($Global:JsonPath+"Get-NcNetRoute.json") saved successfully"
                    }else{
                        Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcNetRoute.json")"
                        $Return=$False
                    }    
                }
                $PrimaryGateway=$PrimaryDefaultRoute.Gateway
            }else{
                $PrimaryDefaultRoute=Get-NcNetRoutingGroupRoute -RoutingGroup $PrimaryRoutingGroupName -Destination '0.0.0.0/0' -Vserver $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNetRoutingGroupRoute failed [$ErrorVar]" }
                if($Backup -eq $True){
                    $PrimaryDefaultRoute | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcNetRoutingGroupRoute.json") -Encoding ASCII -Width 65535
                    if( ($ret=get-item $($Global:JsonPath+"Get-NcNetRoutingGroupRoute.json") -ErrorAction SilentlyContinue) -ne $null ){
                        Write-LogDebug "$($Global:JsonPath+"Get-NcNetRoutingGroupRoute.json") saved successfully"
                    }else{
                        Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcNetRoutingGroupRoute.json")"
                        $Return=$False
                    }    
                }
                $PrimaryGateway=$PrimaryDefaultRoute.GatewayAddress
            }
        }else{
            if(Test-Path $($Global:JsonPath+"Get-NcNetRoute.json")){
                $PrimaryDefaultRoute=Get-Content $($Global:JsonPath+"Get-NcNetRoute.json") | ConvertFrom-Json
                $PrimaryGateway=$PrimaryDefaultRoute.Gateway
            }elseif(Test-Path $($Global:JsonPath+"Get-NcNetRoutingGroupRoute.json")){
                $PrimaryDefaultRoute=Get-Content $($Global:JsonPath+"Get-NcNetRoutingGroupRoute.json") | ConvertFrom-Json
                $PrimaryGateway=$PrimaryDefaultRoute.GatewayAddress
            }else{
                $Return=$False
                Throw "ERROR: neither Get-NcNetRoute.json or Get-NcNetRoutingGroupRoute.json are available in backup folder for []"        
            }       
        }
        if($Backup -eq $False){
            $SecondaryInterface  = Get-NcNetInterface -InterfaceName $PrimaryInterfaceName -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar 
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNetInterface failed [$ErrorVar]" }
            try {
                $global:mutexconsole.WaitOne(200) | Out-Null
            }
            catch [System.Threading.AbandonedMutexException]{
                Write-Host -f Red "catch abandoned mutex for [$myPrimaryVserver]"
                free_mutexconsole
            }
            if ( $SecondaryInterface -eq $null ) 
            {
                $ANS1 = 'y' ; $ANS2 = 'n'
                while ( ( $ANS1 -eq 'y' ) -and ( $ANS2 -eq 'n' ) ) 
                {
                    $LIF = '[' + $PrimaryInterfaceName + '] [' + $PrimaryAddress + '] [' + $PrimaryNetMask + '] [' + $PrimaryGateway + '] [' + $PrimaryCurrentNode + '] [' + $PrimaryCurrentPort + ']'  
                    $ANS1 = Read-HostOptions "[$mySecondaryVserver] Do you want to create the DRP LIF $LIF on cluster [$mySecondaryController] ?" "y/n"
                    if ( $ANS1 -eq 'y' ) 
                    {
                        $myIpAddr=ask_IpAddr_from_cli -myIpAddr $PrimaryAddress -workOn $workOn
                        $myNetMask=ask_NetMask_from_cli -myNetMask $PrimaryNetMask -workOn $workOn
                        $myGateway=ask_gateway_from_cli -myGateway $PrimaryGateway -workOn $workOn
                        $myNode=select_node_from_cli -myController $mySecondaryController -myQuestion "Please select secondary node for LIF [$PrimaryInterfaceName] :" 
                        $myPort=select_nodePort_from_cli -myController $mySecondaryController -myNode $myNode -myQuestion "Please select Port for LIF [$PrimaryInterfaceName] on node [$myNode] " -myDefault $PrimaryCurrentPort
                        $LIF = '[' + $PrimaryInterfaceName + '] [' + $myIpAddr + '] [' + $myNetMask +  '] [' + $myGateway + '] [' +$myNode + '] [' + $myPort + ']'					
                            $ANS2 = Read-HostOptions "[$mySecondaryVserver] Ready to create the LIF $LIF ?" "y/n"
                        if ( $ANS2 -eq 'y' ) 
                        {
                            Write-Log "[$workOn] Create the LIF $LIF"
                            if ( ( $PrimaryFirewallPolicy -eq "mgmt" ) -and ( $PrimaryDataProtocols -eq "none" ) ) 
                            {
                                Write-Log "[$workOn] LIF [$LIF] is the Administration LIF it must be in Administrative up status"
                                Write-LogDebug "New-NcNetInterface -Name $PrimaryInterfaceName -Vserver $mySecondaryVserver -Role $PrimaryRole -Node $myNode -Port $myPort -DataProtocols $PrimaryDataProtocols -FirewallPolicy $PrimaryFirewallPolicy -Address $myIpAddr -Netmask $myNetMask -DnsDomain $PrimaryDnsDomainName -AdministrativeStatus up -AutoRevert $PrimaryIsAutoRevert -Controller $mySecondaryController"
                                $SecondaryInterface=New-NcNetInterface -Name $PrimaryInterfaceName -Vserver $mySecondaryVserver  -Role $PrimaryRole -Node $myNode -Port $myPort -DataProtocols $PrimaryDataProtocols -FirewallPolicy $PrimaryFirewallPolicy -Address $myIpAddr -Netmask $myNetMask -DnsDomain $PrimaryDnsDomainName -AdministrativeStatus up -AutoRevert $PrimaryIsAutoRevert -Controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcNetInterface failed [$ErrorVar]" ; free_mutexconsole}
                            } 
                            else 
                            {
                                Write-LogDebug "New-NcNetInterface -Name $PrimaryInterfaceName -Vserver $mySecondaryVserver  -Role $PrimaryRole -Node $myNode -Port $myPort -DataProtocols $PrimaryDataProtocols -FirewallPolicy $PrimaryFirewallPolicy -Address $myIpAddr -Netmask $myNetMask -DnsDomain $PrimaryDnsDomainName -AdministrativeStatus down -AutoRevert $PrimaryIsAutoRevert  -Controller $mySecondaryController"
                                $SecondaryInterface=New-NcNetInterface -Name $PrimaryInterfaceName -Vserver $mySecondaryVserver  -Role $PrimaryRole -Node $myNode -Port $myPort -DataProtocols $PrimaryDataProtocols -FirewallPolicy $PrimaryFirewallPolicy -Address $myIpAddr -Netmask $myNetMask -DnsDomain $PrimaryDnsDomainName -AdministrativeStatus down -AutoRevert $PrimaryIsAutoRevert  -Controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcNetInterface failed [$ErrorVar]" ;free_mutexconsole}
                            }
                            Write-LogDebug "Get ONTAP version for [$mySecondaryController]"
                            Write-LogDebug "Get-NcSystemVersionInfo -Controller $mySecondaryController"
                            $VersionTuple=(Get-NcSystemVersionInfo -Controller $mySecondaryController | Select-Object VersionTuple).VersionTuple
                            if($VersionTuple.Generation -ge 9){
                                Write-LogDebug "[$mySecondaryController] run ONTAP 9.X"
                                Write-LogDebug "Get-NcNetRoute -Destination '0.0.0.0/0' -Vserver $mySecondaryVserver -Controller $mySecondaryController"
                                $NetRoute=Get-NcNetRoute -Destination '0.0.0.0/0' -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNetRoute failed [$ErrorVar]" }
                                if(($NetRoute.count) -gt 0){
                                    $Gateway=$NetRoute.Gateway
                                    Write-LogDebug "Remove-NcNetRoute -Destination '0.0.0.0/0' -Gateway $Gateway -Vserver $mySecondaryVserver -Controller $mySecondaryController"
                                    $out=Remove-NcNetRoute -Destination '0.0.0.0/0' -Gateway $Gateway -Vserver $mySecondaryVserver -Confirm:$False -Controller $mySecondaryController  -ErrorVariable ErrorVar
                                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Remove-NcNetRoute failed [$ErrorVar]" ;free_mutexconsole}
                                }
                                Write-LogDebug "New-NcNetRoute -Destination '0.0.0.0/0' -Metric 20 -Gateway $myGateway -Vserver $mySecondaryVserver -Controller $mySecondaryController"
                                $out=New-NcNetRoute -Destination '0.0.0.0/0' -Metric 20 -Gateway $myGateway -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcNetRoute failed [$ErrorVar]" ;free_mutexconsole}
                            }
                            else{
                                Write-LogDebug "[$mySecondaryController] run ONTAP 8.X"
                                Write-LogDebug "Use RoutingGroup"
                                $SecondaryRoutingGroupName=$SecondaryInterface.RoutingGroupName
                                $SecondaryDefaultRoute=Get-NcNetRoutingGroupRoute -RoutingGroup $SecondaryRoutingGroupName -Destination '0.0.0.0/0' -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNetRoutingGroupRoute failed [$ErrorVar]" ;free_mutexconsole}
                                $SecondaryGateway=$SecondaryDefaultroute.GatewayAddress
                                if ( ( $myGateway -eq $null ) -or ( $myGateway -eq "" )  ) 
                                {
                                    Write-Log "[$workOn] No default Gateway for lif [$PrimaryInterfaceName]"
                                    if ( $SecondaryGateway -ne $null  ) {
                                        $ANS3 = Read-HostOptions "[$myPrimaryVserver] Do you want to to remove default route [$SecondaryGateway] from Vserver [$mySecondaryVserver] RoutingGroup [$SecondaryRoutingGroupName] ?" "y/n"
                                        if ( $ANS3 -eq 'y' ) 
                                        {
                                            $out=Remove-NcNetRoutingGroupRoute -RoutingGroup $SecondaryRoutingGroupName -Destination '0.0.0.0/0' -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
                                            if ( $? -ne $True ) 
                                            {
                                                Write-LogError "ERROR: Failed to remove default route" 
                                                $Return = $False
                                            }	
                                        }
                                    }
                                } 
                                else 
                                {
                                    if (  $myGateway -ne $SecondaryGateway ) 
                                    {
                                        if ( $SecondaryGateway -ne $null  ) 
                                        {
                                            Write-LogDebug "Remove-NcNetRoutingGroupRoute -RoutingGroup $SecondaryRoutingGroupName -Destination '0.0.0.0/0' -Vserver $mySecondaryVserver -Controller $mySecondaryController -Confirm:$False"
                                            $out=Remove-NcNetRoutingGroupRoute -RoutingGroup $SecondaryRoutingGroupName -Destination '0.0.0.0/0' -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
                                            if ( $? -ne $True ) 
                                            {
                                                Write-LogError "ERROR: Failed to remove default route" 
                                                $Return = $False
                                            }
                                        }
                                        Write-LogDebug "New-NcNetRoutingGroupRoute -RoutingGroup $SecondaryRoutingGroupName -Destination '0.0.0.0/0' -Gateway $myGateway -Metric $PrimaryDefaultRoute.Metric -Vserver $mySecondaryVserver -Controller $mySecondaryController"
                                        $out=New-NcNetRoutingGroupRoute -RoutingGroup $SecondaryRoutingGroupName -Destination '0.0.0.0/0' -Gateway $myGateway -Metric $PrimaryDefaultRoute.Metric -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcNetRoutingGroupRoute failed [$ErrorVar]" ;free_mutexconsole}
                                    }													
                                }
                            }						
                        }
                        Write-Log "`n"
                    }
                }
            }
            else 
            {
                $Return = $True
                Write-Log "[$workOn] Network Interface [$PrimaryInterfaceName] already exist"
                $SecondaryInterface  = Get-NcNetInterface -InterfaceName $PrimaryInterfaceName -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar 
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNetInterface failed [$ErrorVar]" }
                $SecondaryInterfaceAutoReverse=$SecondaryInterface.IsAutoRevert
                if($PrimaryIsAutoRevert -ne $SecondaryInterfaceAutoReverse)
                {
                    Write-Log "[$workOn] Network Interface [$PrimaryInterfaceName] Auto Reverse is different"
                    Write-LogDebug "Set-NcNetInterface -Name $PrimaryInterfaceName -AutoRevert $PrimaryIsAutoRevert -Vserver $mySecondaryVserver -controller $mySecondaryController  -ErrorVariable ErrorVar"
                    if($PrimaryIsAutoRevert -eq $True)
                    {
                        $out = Set-NcNetInterface -Name $PrimaryInterfaceName -AutoRevert $True -Vserver $mySecondaryVserver -controller $mySecondaryController  -ErrorVariable ErrorVar
                    }
                    else
                    {
                        $out = Set-NcNetInterface -Name $PrimaryInterfaceName -AutoRevert $False -Vserver $mySecondaryVserver -controller $mySecondaryController  -ErrorVariable ErrorVar
                    }
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcNetInterface failed [$ErrorVar]" }

                }
            }
            try{
                free_mutexconsole
            }catch{
                Write-LogDebug "Failed to release mutexeconsole"
            }
        }
    }
    Write-LogDebug "create_lif_dr[$myPrimaryVserver]: end"
	return $Return 
}
    Catch 
    {
        handle_error $_ $myPrimaryVserver
	    return $Return
    }
}

#############################################################################################
Function create_update_DNS_dr(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) {
Try {
	$Return = $True
    Write-Log "[$workOn] Check SVM DNS configuration"
    Write-LogDebug "create_update_DNS_dr[$myPrimaryVserver]: start"
    if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
    if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}
    
    if($Restore -eq $False){
        $PrimaryDNS=Get-NcNetDns -Vserver $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNetDns failed [$ErrorVar]" }
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcNetDns.json")){
            $PrimaryDNS=Get-Content $($Global:JsonPath+"Get-NcNetDns.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcNetDns.json")
            Throw "ERROR: failed to read $filepath"
        }    
    }
    if($Backup -eq $True){
        $PrimaryDNS | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcNetDns.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcNetDns.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcNetDns.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcNetDns.json")"
            $Return=$False
        }
    }
	if ( $PrimaryDNS -eq $null ) {
		Write-Log "[$workOn] No DNS service found on Vserver [$myPrimaryVserver]"
        Write-LogDebug "create_update_DNS_dr[$myPrimaryVserver]: end"
		return $True
	}else{
        if($Backup -eq $False){
            $PrimaryDnsState=$PrimaryDNS.DnsState 
            $PrimaryDomains=$PrimaryDNS.Domains
            $PrimaryNameServers=$PrimaryDNS.NameServers
            $PrimaryTimeout=$PrimaryDNS.Timeout
            $PrimaryAttempts=$PrimaryDNS.Attempts
            $SecondaryDNS=Get-NcNetDns -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNetDns failed [$ErrorVar]" }
            if ( $SecondaryDNS -eq $null ) {
                if($Run_Mode -eq "ConfigureDR" -or $Run_Mode -eq "Migrate"){
                    Write-LogDebug "New-NcNetDns -Domains $PrimaryDomains -NameServers $PrimaryNameServers -State $PrimaryDnsState -TimeoutSeconds $PrimaryTimeout -Attempts $PrimaryAttempts -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                    $out=New-NcNetDns -Domains $PrimaryDomains -NameServers $PrimaryNameServers -State $PrimaryDnsState -TimeoutSeconds $PrimaryTimeout -Attempts $PrimaryAttempts -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) {
                        if($ErrorVar[0].ToString() -match "skip-config-validation"){
                            try {
                                $global:mutexconsole.WaitOne(200) | Out-Null
                            }
                            catch [System.Threading.AbandonedMutexException]{
                                #AbandonedMutexException means another thread exit without releasing the mutex, and this thread has acquired the mutext, therefore, it can be ignored
                                Write-Host -f Red "catch abandoned mutex for [$myPrimaryVserver]"
                                free_mutexconsole
                            }
                            Write-Log "[$workOn] All DNS nameserver are not available on DR"
                            Write-LogDebug "Do you want to force creation of DNS without verify config on destination?"
                            $ans=Read-HostOptions "[$myPrimaryVserver]Do you want to force creation of DNS without verify config on destination?" "y/n"
                            free_mutexconsole
                            if($ans -eq "y"){
                                Write-LogDebug "New-NcNetDns -Domains $PrimaryDomains -NameServers $PrimaryNameServers -State $PrimaryDnsState -SkipConfigValidation -TimeoutSeconds $PrimaryTimeout -Attempts $PrimaryAttempts -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                                $out=New-NcNetDns -Domains $PrimaryDomains -NameServers $PrimaryNameServers -State $PrimaryDnsState -SkipConfigValidation -TimeoutSeconds $PrimaryTimeout -Attempts $PrimaryAttempts -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcNetDns failed [$ErrorVar]" }
                            }    
                        }else{ 
                            $Return = $False
                            throw "[$myPrimaryVserver] ERROR: New-NcNetDns failed [$ErrorVar]" 
                        }
                    }  
                }else{
                    Write-LogDebug "New-NcNetDns -Domains $PrimaryDomains -NameServers $PrimaryNameServers -State $PrimaryDnsState -SkipConfigValidation -TimeoutSeconds $PrimaryTimeout -Attempts $PrimaryAttempts -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                    $out=New-NcNetDns -Domains $PrimaryDomains -NameServers $PrimaryNameServers -State $PrimaryDnsState -SkipConfigValidation -TimeoutSeconds $PrimaryTimeout -Attempts $PrimaryAttempts -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcNetDns failed [$ErrorVar]" }
                }
            }else{
                $SecondaryDnsState=$SecondaryDNS.DnsState 
                $SecondaryDomains=$SecondaryDNS.Domains
                $SecondaryNameServers=$SecondaryDNS.NameServers
                $SecondaryTimeout=$SecondaryDNS.Timeout
                $SecondaryAttempts=$SecondaryDNS.Attempts
                foreach ( $NameServer in ( $PrimaryNameServers | Skip-Null  )  ) { $str1 = $str1 + $NameServer }
                foreach ( $NameServer in ( $SecondaryNameServers | Skip-Null ) ) { $str2 = $str2 + $NameServer }
                if ( $str1 -ne $str2 ) {
                    Write-LogDebug "Set-NcNetDns -NameServers $PrimaryNameServers -SkipConfigValidation -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                    $out=Set-NcNetDns -NameServers $PrimaryNameServers -SkipConfigValidation -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcNetDns failed [$ErrorVar]" }
                }
                foreach ( $Domain in ( $PrimaryDomains | Skip-Null ) ) { $str1 = $str1 + $Domain }
                foreach ( $Domain in ( $SecondaryDomains | Skip-Null ) ) { $str2 = $str2 + $Domain }
                if ( $str1 -ne $str2 ) {
                    Write-LogDebug "Set-NcNetDns -Domains $PrimaryDomains -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                    $out=Set-NcNetDns -Domains $PrimaryDomains -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcNetDns failed [$ErrorVar]" }
                }
                if ( $PrimaryDnsState -ne $SecondaryDnsState ) {
                    Write-LogDebug "Set-NcNetDns -State $PrimaryDnsState -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                    $out=Set-NcNetDns -State $PrimaryDnsState -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcNetDns failed [$ErrorVar]" }
                }
            }
        }
	}
    Write-LogDebug "create_update_DNS_dr[$myPrimaryVserver]: end"
	return $Return 
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
Function create_update_NIS_dr(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) {
Try {
	$Return = $True
    Write-Log "[$workOn] Check SVM NIS configuration"
    Write-LogDebug "create_update_NIS_dr[$myPrimaryVserver]: start"
    if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
    if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}

    if($Restore -eq $False){
        $PrimaryNisList=Get-NcNIS -Vserver $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNIS failed [$ErrorVar]" }
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcNIS.json")){
            $PrimaryNisList=Get-Content $($Global:JsonPath+"Get-NcNIS.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcNIS.json")
            Throw "ERROR: failed to read $filepath"
        }
    }
    if($Backup -eq $True){
        $PrimaryNisList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcNIS.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcNIS.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcNIS.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcNIS.json")"
            $Return=$False
        }
    }
	if ( $PrimaryNisList -eq $null ) {
		Write-Log "[$workOn] No NIS service found on Vserver [$myPrimaryVserver]"
        Write-LogDebug "create_update_NIS_dr[$myPrimaryVserver]: end"
		return $True 
	}else{
        if($Backup -eq $False){
            foreach ( $NisServer in ( $PrimaryNisList ) | skip-Null ) {
                if ( $NisServer.IsActive -eq $True ) {
                    $PrimaryNIS=$NisServer
                }
            }
            $PrimaryNisDomain=$PrimaryNIS.NisDomain
            $PrimaryNisServers=$PrimaryNIS.NisServers
            $PrimaryIsActive=$PrimaryNIS.IsActive
            $SecondaryNisList=Get-NcNIS -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNIS failed [$ErrorVar]" }
            if ( $SecondaryNisList -eq $null ) {
                $out=New-NcNis -NisDomain $PrimaryNisDomain -Enable -NisServers $PrimaryNisServers -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcNis failed [$ErrorVar]" }

            } else {
                foreach ( $NisServer in ( $SecondaryNisList ) | skip-Null ) {
                    if ( $NisServer.IsActive -eq $True ) {
                        $SecondaryNIS=$NisServer
                    }
                }
                $SecondaryNisDomain=$SecondaryNIS.NisDomain
                $SecondaryNisServers=$SecondaryNIS.NisServers
                foreach ( $NisServer in ( $PrimaryNisServers | Skip-Null  )  ) { $str1 = $str1 + $NisServer }
                foreach ( $NisServer in ( $SecondaryNisServers | Skip-Null ) ) { $str2 = $str2 + $NisServer }
                if ( $PrimaryNisDomain -ne $SecondaryNisDomain ) {
                    $out=Remove-NcNis -NisDomain $SecondaryNisDomain -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-RemoveNis failed [$ErrorVar]" }
                    $out=New-NcNis -NisDomain $PrimaryNisDomain -Enable -NisServers $PrimaryNisServers -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcNis failed [$ErrorVar]" }
                }
                if ( $str1 -ne $str2 ) {
                    $out=Set-NcNis -NisDomain $PrimaryNisDomain -NisServers $PrimaryNisServers -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcNis failed [$ErrorVar]" }
                }
            }
        }
	}
    Write-LogDebug "create_update_NIS_dr[$myPrimaryVserver]: end"
	return $Return
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
Function compare_NFS_service (
	#[DataONTAP.C.Types.Nfs.NfsInfo] $RefNfsService, 
	#[DataONTAP.C.Types.Nfs.NfsInfo] $NfsService ) {
    [object] $RefNfsService, 
	[object] $NfsService ) {
Try {
	if ( ($RefNfsService -eq $null) -or ($NfsService -eq $null ) ) {
		Write-LogError "ERROR: compare_NFS_service null entry"
		return $true
	}
		
	$NfsServiceDiff = $False
	if ($RefNfsService.ChownMode -ne $NfsService.ChownMode ) { $NfsServiceDiff = $True }
	if ($RefNfsService.DefaultWindowsGroup -ne $NfsService.DefaultWindowsGroup ) { $NfsServiceDiff = $True }
	if ($RefNfsService.DefaultWindowsUser -ne $NfsService.DefaultWindowsUser  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.EnableEjukebox -ne $NfsService.EnableEjukebox  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsMountRootonlyEnabled -ne $NfsService.IsMountRootonlyEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsAccessEnabled  -ne $NfsService.IsNfsAccessEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsRootonlyEnabled  -ne $NfsService.IsNfsRootonlyEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv2Enabled  -ne $NfsService.IsNfsv2Enabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv3ConnectionDropEnabled  -ne $NfsService.IsNfsv3ConnectionDropEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv3Enabled  -ne $NfsService.IsNfsv3Enabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv3FsidChangeEnabled  -ne $NfsService.IsNfsv3FsidChangeEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv40AclEnabled  -ne $NfsService.IsNfsv40AclEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv40Enabled  -ne $NfsService.IsNfsv40Enabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv40MigrationEnabled  -ne $NfsService.IsNfsv40MigrationEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv40ReadDelegationEnabled  -ne $NfsService.IsNfsv40ReadDelegationEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv40ReferralsEnabled  -ne $NfsService.IsNfsv40ReferralsEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv40ReqOpenConfirmEnabled  -ne $NfsService.IsNfsv40ReqOpenConfirmEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv40WriteDelegationEnabled  -ne $NfsService.IsNfsv40WriteDelegationEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv41AclEnabled  -ne $NfsService.IsNfsv41AclEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv41AclPreserveEnabled  -ne $NfsService.IsNfsv41AclPreserveEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv41Enabled  -ne $NfsService.IsNfsv41Enabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv41MigrationEnabled  -ne $NfsService.IsNfsv41MigrationEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv41PnfsEnabled  -ne $NfsService.IsNfsv41PnfsEnabled  ) { $NfsServiceDiff = $True }
	# Deprecated if ($RefNfsService.IsNfsv41PnfsStripedVolumesEnabled  -ne $NfsService.IsNfsv41PnfsStripedVolumesEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv41ReadDelegationEnabled  -ne $NfsService.IsNfsv41ReadDelegationEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv41ReferralsEnabled  -ne $NfsService.IsNfsv41ReferralsEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv41StateProtectionEnabled  -ne $NfsService.IsNfsv41StateProtectionEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv41WriteDelegationEnabled  -ne $NfsService.IsNfsv41WriteDelegationEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv4FsidChangeEnabled  -ne $NfsService.IsNfsv4FsidChangeEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv4NumericIdsEnabled  -ne $NfsService.IsNfsv4NumericIdsEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsQtreeExportEnabled  -ne $NfsService.IsQtreeExportEnabled  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsValidateQtreeExportEnabled -ne $NfsService.IsValidateQtreeExportEnabled ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsVstorageEnabled -ne $NfsService.IsVstorageEnabled ) { $NfsServiceDiff = $True }
	if ($RefNfsService.Nfsv41ImplementationIdDomain -ne $NfsService.Nfsv41ImplementationIdDomain ) { $NfsServiceDiff = $True }
	if ($RefNfsService.Nfsv41ImplementationIdName  -ne $NfsService.Nfsv41ImplementationIdName  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.Nfsv4AclMaxAces -ne $NfsService.Nfsv4AclMaxAces ) { $NfsServiceDiff = $True }
	if ($RefNfsService.Nfsv4GraceSeconds  -ne $NfsService.Nfsv4GraceSeconds  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.Nfsv4IdDomain  -ne $NfsService.Nfsv4IdDomain  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.Nfsv4LeaseSeconds  -ne $NfsService.Nfsv4LeaseSeconds  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.Nfsv4xSessionNumSlots  -ne $NfsService.Nfsv4xSessionNumSlots  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.Nfsv4xSessionSlotReplyCacheSize  -ne $NfsService.Nfsv4xSessionSlotReplyCacheSize  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.NtfsUnixSecurityOps  -ne $NfsService.NtfsUnixSecurityOps  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.RpcsecCtxHigh -ne $NfsService.RpcsecCtxHigh ) { $NfsServiceDiff = $True }
	if ($RefNfsService.RpcsecCtxIdle  -ne $NfsService.RpcsecCtxIdle  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.EnableEjukeboxSpecified -ne $NfsService.EnableEjukeboxSpecified ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsMountRootonlyEnabledSpecified  -ne $NfsService.IsMountRootonlyEnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsAccessEnabledSpecified  -ne $NfsService.IsNfsAccessEnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsRootonlyEnabledSpecified  -ne $NfsService.IsNfsRootonlyEnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv2EnabledSpecified -ne $NfsService.IsNfsv2EnabledSpecified ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv3ConnectionDropEnabledSpecified -ne $NfsService.IsNfsv3ConnectionDropEnabledSpecified ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv3EnabledSpecified  -ne $NfsService.IsNfsv3EnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv3FsidChangeEnabledSpecified -ne $NfsService.IsNfsv3FsidChangeEnabledSpecified ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv40AclEnabledSpecified  -ne $NfsService.IsNfsv40AclEnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv40EnabledSpecified  -ne $NfsService.IsNfsv40EnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv40MigrationEnabledSpecified  -ne $NfsService.IsNfsv40MigrationEnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv40ReadDelegationEnabledSpecified  -ne $NfsService.IsNfsv40ReadDelegationEnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv40ReferralsEnabledSpecified  -ne $NfsService.IsNfsv40ReferralsEnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv40ReqOpenConfirmEnabledSpecified -ne $NfsService.IsNfsv40ReqOpenConfirmEnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv40WriteDelegationEnabledSpecified -ne $NfsService.IsNfsv40WriteDelegationEnabledSpecified ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv41AclEnabledSpecified  -ne $NfsService.IsNfsv41AclEnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv41AclPreserveEnabledSpecified  -ne $NfsService.IsNfsv41AclPreserveEnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv41EnabledSpecified  -ne $NfsService.IsNfsv41EnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv41MigrationEnabledSpecified  -ne $NfsService.IsNfsv41MigrationEnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv41PnfsEnabledSpecified  -ne $NfsService.IsNfsv41PnfsEnabledSpecified  ) { $NfsServiceDiff = $True }
	# Deprecated if ($RefNfsService.IsNfsv41PnfsStripedVolumesEnabledSpecified  -ne $NfsService.IsNfsv41PnfsStripedVolumesEnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv41ReadDelegationEnabledSpecified  -ne $NfsService.IsNfsv41ReadDelegationEnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv41ReferralsEnabledSpecified  -ne $NfsService.IsNfsv41ReferralsEnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv41StateProtectionEnabledSpecified  -ne $NfsService.IsNfsv41StateProtectionEnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv41WriteDelegationEnabledSpecified  -ne $NfsService.IsNfsv41WriteDelegationEnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv4FsidChangeEnabledSpecified  -ne $NfsService.IsNfsv4FsidChangeEnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv4NumericIdsEnabledSpecified  -ne $NfsService.IsNfsv4NumericIdsEnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsQtreeExportEnabledSpecified  -ne $NfsService.IsQtreeExportEnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsValidateQtreeExportEnabledSpecified  -ne $NfsService.IsValidateQtreeExportEnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsVstorageEnabledSpecified  -ne $NfsService.IsVstorageEnabledSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.Nfsv4AclMaxAcesSpecified  -ne $NfsService.Nfsv4AclMaxAcesSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.Nfsv4GraceSecondsSpecified  -ne $NfsService.Nfsv4GraceSecondsSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.Nfsv4LeaseSecondsSpecified  -ne $NfsService.Nfsv4LeaseSecondsSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.Nfsv4xSessionNumSlotsSpecified -ne $NfsService.Nfsv4xSessionNumSlotsSpecified ) { $NfsServiceDiff = $True }
	if ($RefNfsService.Nfsv4xSessionSlotReplyCacheSizeSpecified  -ne $NfsService.Nfsv4xSessionSlotReplyCacheSizeSpecified  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.RpcsecCtxHighSpecified -ne $NfsService.RpcsecCtxHighSpecified ) { $NfsServiceDiff = $True }
	if ($RefNfsService.RpcsecCtxIdleSpecified -ne $NfsService.RpcsecCtxIdleSpecified ) { $NfsServiceDiff = $True }
	if ($RefNfsService.GeneralAccess -ne $NfsService.GeneralAccess ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv3  -ne $NfsService.IsNfsv3  ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv4 -ne $NfsService.IsNfsv4 ) { $NfsServiceDiff = $True }
	if ($RefNfsService.IsNfsv41 -ne $NfsService.IsNfsv41 ) { $NfsServiceDiff = $True }
	return $NfsServiceDiff 
}
Catch {
    handle_error $_ 
	return $Return
}
}

#############################################################################################
Function compare_ISCSI_service (
	[DataONTAP.C.Types.Iscsi.IscsiServiceInfo] $RefIscsiService, 
	[DataONTAP.C.Types.Iscsi.IscsiServiceInfo] $IscsiService ) {
	
	if ( ($RefIscsiService -eq $null) -or ($IscsiService -eq $null ) ) {
		Write-LogError "ERROR: compare_ISCS_Service null entry" 
		return $False
	}
	
	$IscsiServiceDiff = $False
	if ( $RefIscsiService.NodeName -ne $IscsiService.NodeName) { $IscsiServiceDiff = $True }
	return $IscsiServiceDiff
}

#############################################################################################
Function create_update_NFS_dr (
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) {
Try {
	$Return = $True
    Write-Log "[$workOn] Check SVM NFS configuration"
    Write-LogDebug "create_update_NFS_dr[$myPrimaryVserver]: start"
    if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
    if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}

    if($Restore -eq $False){
        $PrimaryNfsService = Get-NcNfsService -VserverContext  $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNfsService failed [$ErrorVar]" }
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcNfsService.json")){
            $PrimaryNfsService=Get-Content $($Global:JsonPath+"Get-NcNfsService.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcNfsService.json")
            Throw "ERROR: failed to read $filepath"
        }
    }
    if($Backup -eq $True){
        $PrimaryNfsService | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcNfsService.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcNfsService.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcNfsService.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcNfsService.json")"
            $Return=$False
        }
    }
	if ( $PrimaryNfsService -eq $null ) {
		Write-Log "[$workOn] No NFS services in vserver [$myPrimaryVserver]"
        Write-LogDebug "create_update_NFS_dr[$myPrimaryVserver]: end"
		return $true
	}
	# Remove not supported NFS parameters Deprectated
	# $PrimaryNfsService.IsNfsv41PnfsStripedVolumesEnabled=$n"ll
    if($Backup -eq $False){
        $SecondaryNfsService = Get-NcNfsService -VserverContext  $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNfsService failed [$ErrorVar]" }
        if ( $SecondaryNfsService -eq $null ) {
            Write-Log "[$workOn] Add NFS services"
            Write-LogDebug "Add-NcNfsService -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
            $out = Add-NcNfsService -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar 
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Add-NcNfsService failed [$ErrorVar]" }
            $NfsService=$PrimaryNfsService
            $NfsService.NcController=""
            Write-LogDebug "Set-NcNfsService -Attributes $NfsService -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
            $out = Set-NcNfsService -Attributes $NfsService -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcNfsService failed [$ErrorVar]" }
        } else {
            if ( ( compare_NFS_service -RefNfsService $PrimaryNfsService -NfsService $SecondaryNfsService ) -eq $True ) {
                Write-Log "[$workOn] Set NFS Services Attributes"
                $NfsService=$PrimaryNfsService
                $NfsService.NcController=""
                $out = Set-NcNfsService -Attributes $NfsService -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcNfsService failed [$ErrorVar]" }
            }
        }
        Write-LogDebug "Disable-NcNfs -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Confirm:$False"
        $out=Disable-NcNfs -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
        if ( $? -ne $True ) {
            Write-LogError "ERROR: Failed to disable NFS on Vserver [$myVserver]" 
            $Return = $False
        }
    }
    Write-LogDebug "create_update_NFS_dr[$myPrimaryVserver]: end"
	return $Return 
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
Function check_update_CIFS_server_dr (
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string] $workOn=$mySecondaryVserver,
    [bool] $Backup=$False,
    [bool] $Restore=$False
) {
    Try {
	    $Return=$false

        # check first before trying sync
        if($Restore -ne $True){
            $PrimaryCifsServerInfos = Get-NcCifsServer  -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsServer failed [$ErrorVar]" }
            if ( $PrimaryCifsServerInfos -eq $null ) {
                Write-LogDebug "[$workOn] No CIFS Server in Vserver [$myPrimaryVserver]:[$myPrimaryController]"
                $cifsServerSource=$False
                if($Backup -eq $True){return $False}
            }else{$cifsServerSource=$True}
        }
        if($Backup -ne $True){
            $SecondaryCifsServerInfos = Get-NcCifsServer -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsServer failed [$ErrorVar]" }
            if ( $SecondaryCifsServerInfos -eq $null ) {
                if($cifsServerSource -eq $True){
                    Write-LogWarn "[$workOn] No CIFS Server in Vserver [$mySecondaryVserver]:[$mySecondaryController]"
                    Write-LogWarn "[$workOn] You need make sure the ConfigureDR runs successfully first."
                }
                $cifsServerDest=$False
                if($Restore -eq $True){return $False}
            }
            else{$cifsServerDest=$True}

        }else{
            $cifsServerDest=$cifsServerSource  
        }

        if($cifsServerSource -eq $False){
            return $False
        }
        if($cifsServerSource -ne $cifsServerDest)
        {
            return $False
        }else{
            return $True
        }
    }
    Catch {
        handle_error $_ $myPrimaryVserver
	    return $Return
    }
}

#############################################################################################
Function update_CIFS_server_dr (
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) {

Try {
	$Return=$True
    $RunBackup=$False
    $RunRestore=$False
    Write-Log "[$workOn] Check SVM CIFS Server options"
    Write-LogDebug "update_CIFS_server_dr[$myPrimaryVserver]: start"
    if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]";$RunBackup=$True}
    if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]";$RunRestore=$True}
    if(-not (check_update_CIFS_server_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $mySecondaryVserver -Backup $RunBackup -Restore $RunRestore)){
        Write-LogDebug "update_CIFS_server_dr: end"
        return $true
    }
    $ONTAPVersionDiff=$False
    if($Restore -eq $False){
        Write-LogDebug "Get-NcCifsOption -VserverContext $myPrimaryVserver -controller $myPrimaryController"
        $primaryOptions=Get-NcCifsOption -VserverContext $myPrimaryVserver -controller $myPrimaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsOption failed [$ErrorVar]" }
        $PrimaryVersion=(Get-NcSystemVersionInfo -Controller $myPrimaryController).VersionTupleV
        Write-LogDebug "Get-NcCifsSecurity -Vservercontext $myPrimaryVserver -Controller $myPrimaryController"
        $PrimaryCIFSsecurity=Get-NcCifsSecurity -Vservercontext $myPrimaryVserver -Controller $myPrimaryController -ErrorVariable ErrorVar
        if($? -ne $True){Throw "ERROR: Failed to get CIFS security for [$myPrimaryVserver] reason [$ErrorVar]"}
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcCifsOption.json")){
            $primaryOptions=Get-Content $($Global:JsonPath+"Get-NcCifsOption.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcCifsOption.json")
            Throw "ERROR: failed to read $filepath"
        }
        if(Test-Path $($Global:JsonPath+"Get-NcSystemVersionInfo.json")){
            $PrimaryVersion=Get-Content $($Global:JsonPath+"Get-NcSystemVersionInfo.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcSystemVersionInfo.json")
            Throw "ERROR: failed to read $filepath"
        }
        $PrimaryVersion=$PrimaryVersion.VersionTupleV
        if(Test-Path $($Global:JsonPath+"Get-NcCifsSecurity.json")){
            $PrimaryCIFSsecurity=Get-Content $($Global:JsonPath+"Get-NcCifsSecurity.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcCifsSecurity.json")
            Throw "ERROR: failed to read $filepath"
        }
    }
    if($Backup -eq $True){
        $primaryOptions | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcCifsOption.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcCifsOption.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcCifsOption.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcCifsOption.json")"
            $Return=$False
        }
        $PrimaryVersion | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcSystemVersionInfo.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcSystemVersionInfo.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcSystemVersionInfo.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcSystemVersionInfo.json")"
            $Return=$False
        }
        $PrimaryCIFSsecurity | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcCifsSecurity.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcCifsSecurity.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcCifsSecurity.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcCifsSecurity.json")"
            $Return=$False
        }
    } 
    if($Backup -eq $False){
        Write-LogDebug "Get-NcCifsOption -VserverContext $mySecondaryVserver -controller $mySecondaryController"
        $secondaryOptions=Get-NcCifsOption -VserverContext $mySecondaryVserver -controller $mySecondaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsOption failed [$ErrorVar]" }
        $Properties=$primaryOptions | Get-Member -MemberType Property | Select-Object -ExpandProperty Name
        $SecondaryVersion=(Get-NcSystemVersionInfo -Controller $mySecondaryController).VersionTupleV
        if($PrimaryVersion.Major -ne $SecondaryVersion.Major){$ONTAPVersionDiff=$True}
        foreach($Property in $Properties | Where-Object {$_ -notmatch "Vserver|NcController|Specified"}){
            $Differences=Compare-Object -ReferenceObject $primaryOptions -DifferenceObject $secondaryOptions -Property "$Property"
            #write-host $Differences
            $Differences_string=$Differences | Out-String
            foreach($Diff in $Differences){
                if($Diff.SideIndicator -eq "<="){
                    $option=$Property
                    $value=$Diff.${Property}
                    $isPrimarySpecified=$primaryOptions.$($Property+"Specified")
                    $isSecondarySpecified=$secondaryOptions.$($Property+"Specified")
                    if($ONTAPVersionDiff -eq $True){
                        if(($isSecondarySpecified -match "true") -or ($isSecondarySpecified.count -eq 0)){
                            if($value.count -eq 0){
                                Write-LogDebug "option [$option] has no value on primary, so reuse value [$value] on secondary"
                                Continue
                            }
                            if($value -match "true"){$value=$true}
                            if($value -match "false"){$value=$false}
                            if($value.count -eq 0){$value=$true}
                            $newvar=@{$option=$value}
                            try{
                                Write-Log "[$workOn] Update CIFS option [$Property] to [$value]"
                                if($DebugLevel){Write-LogDebug "CIFS option Specified on Primary : [$isPrimarySpecified] Specified on Secondary : [$isSecondarySpecified] difference : `n$Differences_string"}
                                Write-LogDebug "Set-NcCifsOption -$($option) $value -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                                $out=Set-NcCifsOption @newvar -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            }catch{
                                Write-Warning "[$myPrimaryVserver] ERROR : Failed to set CIFS option [$option] : [$ErrorVar]" 
                            }
                        }
                        if($isSecondarySpecified -match "false"){
                            Write-LogDebug "option : [$option] = [$value] is Default value on [$mySecondaryVserver], so no change"
                        }  
                    }else{
                        if($value.count -eq 0){
                            $value=($Differences | Where-Object {$_.SideIndicator -eq "=>"}).$Property
                        }
                        if($value -match "true"){$value=$true}
                        if($value -match "false"){$value=$false}
                        if($value.count -eq 0){$value=$true}
                        $newvar=@{$option=$value}
                        try{
                            Write-Log "[$workOn] Update CIFS option [$Property] to [$value]"
                            if($DebugLevel){Write-LogDebug "CIFS options difference : `n$Differences_string"}
                            Write-LogDebug "Set-NcCifsOption -$($option) $value -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                            $out=Set-NcCifsOption @newvar -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if($? -ne $True){throw "Failed to set CIFS option [$option]"}
                        }catch{
                            Write-Warning "[$myPrimaryVserver] Failed to set CIFS options reason : [$ErrorVar]" 
                        }
                    }
                }
            }
        }
        $PrimKerberosClockSkew=$PrimaryCIFSsecurity.KerberosClockSkew
        $PrimKerberosKdcTimeout=$PrimaryCIFSsecurity.KerberosKdcTimeout
        $PrimKerberosRenewAge=$PrimaryCIFSsecurity.KerberosRenewAge
        $PrimKerberosTicketAge=$PrimaryCIFSsecurity.KerberosTicketAge
        $PrimIsSigningRequired=$PrimaryCIFSsecurity.IsSigningRequired
        $PrimIsPasswordComplexityRequired=$PrimaryCIFSsecurity.IsPasswordComplexityRequired
        $PrimUseStartTlsForAdLdap=$PrimaryCIFSsecurity.UseStartTlsForAdLdap
        $PrimIsAesEncryptionEnabled=$PrimaryCIFSsecurity.IsAesEncryptionEnabled
        $PrimLmCompatibilityLevel=$PrimaryCIFSsecurity.LmCompatibilityLevel
        $PrimIsSmbEncryptionRequired=$PrimaryCIFSsecurity.IsSmbEncryptionRequired
        $PrimSessionSecurityForAdLdap=$PrimaryCIFSsecurity.SessionSecurityForAdLdap
        $PrimSmb1EnabledForDcConnections=$PrimaryCIFSsecurity.Smb1EnabledForDcConnections
        $PrimSmb2EnabledForDcConnections=$PrimaryCIFSsecurity.Smb2EnabledForDcConnections
        if($DebugLevel){Write-LogDebug "Set-NcCifsSecurity -ClockSkew $PrimKerberosClockSkew -TicketAge $PrimKerberosTicketAge -RenewAge $PrimKerberosRenewAge -KerberosKdcTimeout $PrimKerberosKdcTimeout `
        -IsSigningRequired $PrimIsSigningRequired -IsPasswordComplexityRequired $PrimIsPasswordComplexityRequired -UseStartTlsForAdLdap $PrimUseStartTlsForAdLdap `
        -IsAesEncryptionEnabled $PrimIsAesEncryptionEnabled -LmCompatibilityLevel $PrimLmCompatibilityLevel -AdminCredential $ADCred -IsSmbEncryptionRequired $PrimIsSmbEncryptionRequired `
        -SessionSecurityForAdLdap $PrimSessionSecurityForAdLdap -Smb1EnabledForDcConnections $PrimSmb1EnabledForDcConnections -Smb2EnabledForDcConnections $PrimSmb2EnabledForDcConnections `
        -VserverContext $mySecondaryVserver -Controller $mySecondaryController"}
        $SecondaryDomain=(Get-NcCifsServer -VserverContext $mySecondaryVserver -Controller $mySecondaryController).Domain
        $ADCred = get_local_cred ($SecondaryDomain)
        $out=Set-NcCifsSecurity -ClockSkew $PrimKerberosClockSkew -TicketAge $PrimKerberosTicketAge -RenewAge $PrimKerberosRenewAge -KerberosKdcTimeout $PrimKerberosKdcTimeout `
        -IsSigningRequired $PrimIsSigningRequired -IsPasswordComplexityRequired $PrimIsPasswordComplexityRequired -UseStartTlsForAdLdap $PrimUseStartTlsForAdLdap `
        -IsAesEncryptionEnabled $PrimIsAesEncryptionEnabled -LmCompatibilityLevel $PrimLmCompatibilityLevel -AdminCredential $ADCred -IsSmbEncryptionRequired $PrimIsSmbEncryptionRequired `
        -SessionSecurityForAdLdap $PrimSessionSecurityForAdLdap -Smb1EnabledForDcConnections $PrimSmb1EnabledForDcConnections -Smb2EnabledForDcConnections $PrimSmb2EnabledForDcConnections `
        -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Confirm:$False -ErrorVariable ErrorVar
        if($? -ne $True){Throw "ERROR: Failed to set CIFS security on [$mySecondaryVserver] reason [$ErrorVar]"}
        Write-LogDebug "update_CIFS_server_dr[$myPrimaryVserver]: end"
        return $Return
    }
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
Function update_qtree (
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) {
Try {
    $Return=$True
    Write-Log "[$workOn] Check Qtree"
    Write-LogDebug "update_qtree [$myPrimaryVserver]: start"
    if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
    if($Restore -eq $True -and $Global:VOLUME_TYPE){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}
    if($Restore -eq $True -and $Global:VOLUME_TYPE -eq "DP"){
        Write-Log "[$workOn] Qtree will be automaticaly created when data will be restored through SnapMirror"
        Write-Log "[$workOn] If Needed, Update Qtree Export Policy manualy, after restore the data back"
        return $True
    }
    if($Restore -eq $False){
        $PrimaryQtrees=Get-NcQtree -VserverContext $myPrimaryVserver -Controller $myPrimaryController -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcQtree failed [$ErrorVar]" }
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcQtree.json")){
            $PrimaryQtrees=Get-Content $($Global:JsonPath+"Get-NcQtree.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcQtree.json")
            Throw "ERROR: failed to read $filepath"
        }
    }
    if($Backup -eq $True){
        $PrimaryQtrees | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcQtree.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcQtree.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcQtree.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcQtree.json")"
            $Return=$False
        }
    }
    if($Backup -eq $False){
        #foreach($qtree in $PrimaryQtrees | Where-Object {($_.Qtree).Length -gt 1}){
        foreach($qtree in $PrimaryQtrees){
            if(($qtree.Qtree).Length -lt 1){
                if($DebugLevel){Write-LogDebug "skip this Qtree [$qtree]"}
                continue
            }
            $QName=$qtree.Qtree
            $ExportPolicy=$qtree.ExportPolicy
            $Volume=$qtree.Volume
            $SecStyle=$qtree.SecurityStyle
            $Mode=$qtree.Mode
            $Oplocks=$qtree.Oplocks
            if($DebugLevel){Write-LogDebug "[$myPrimaryVserver] Work on Qtree [$QName]"}
            if($DebugLevel){Write-LogDebug "Get-NcQtree -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Volume $Volume -Qtree $QName"}
            $SecQtree=Get-NcQtree -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Volume $Volume -Qtree $QName -ErrorVariable ErrorVar
            if($? -ne $True){$Return=$Fasle;Throw "ERROR: Failed to get Qtree [$QName] on [$mySecondaryVserver] reason [$ErrorVar]"}
            if($SecQtree -eq $null){
                Write-Log "[$workOn] Create Qtree [$QName] on Volume [$Volume]"
                Write-LogDebug "New-NcQtree -Volume /vol/ $Volume / $QName -Mode $Mode -SecurityStyle $SecStyle -Oplocks $Oplocks -ExportPolicy $ExportPolicy -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                $ret=New-NcQtree -Volume $("/vol/"+$Volume+"/"+$QName) -Mode $Mode -SecurityStyle $SecStyle -Oplocks $Oplocks -ExportPolicy $ExportPolicy -VserverContext $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErrorVar 
                if($? -ne $True){$Return=$Fasle;Throw "ERROR: Failed to create Qtree [$QName] on [$mySecondaryVserver] reason [$ErrorVar]"}
            }
            else{
                Write-Log "[$workOn] Modify Qtree [$QName] on Volume [$Volume]"
                if($Oplocks -eq "enabled"){
                    Write-LogDebug "Set-NcQtree -Volume /vol/ $Volume / $QName -Mode $Mode -SecurityStyle $SecStyle -EnableOplocks -ExportPolicy $ExportPolicy -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                    $out=Set-NcQtree -Volume $("/vol/"+$Volume+"/"+$QName) -Mode $Mode -SecurityStyle $SecStyle -EnableOplocks -ExportPolicy $ExportPolicy -VserverContext $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErrorVar
                    if($? -ne $True){$Return=$Fasle;Throw "ERROR: Failed to Set Qtree [$QName] on [$mySecondaryVserver] reason [$ErrorVar]"}
                }else{
                    Write-LogDebug "Set-NcQtree -Volume /vol/ $Volume / $QName -Mode $Mode -SecurityStyle $SecStyle -DisableOplocks -ExportPolicy $ExportPolicy -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                    $out=Set-NcQtree -Volume $("/vol/"+$Volume+"/"+$QName) -Mode $Mode -SecurityStyle $SecStyle -DisableOplocks -ExportPolicy $ExportPolicy -VserverContext $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErrorVar
                    if($? -ne $True){$Return=$Fasle;Throw "ERROR: Failed to Set Qtree [$QName] on [$mySecondaryVserver] reason [$ErrorVar]"}    
                }
            }
        }   
    }
    return $Return
}
Catch {
    handle_error $_ $myPrimaryVserver
    return $Return
}
}

#############################################################################################
Function update_qtree_export_policy_dr (
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) {
Try {
    $Return=$True
    Write-Log "[$mySecondaryVserver] Check Qtree Export Policy"
    Write-LogDebug "update_qtree_export_policy_dr[$myPrimaryVserver]: start"
    if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
    if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}
    if($Global:IgnoreQtreeExportPolicy -eq $True){
        Write-Log "Qtree Export Policy already synced"
        Write-LogDebug "update_qtree_export_policy_dr[$myPrimaryVserver]: end"
        return $True
    }
    if($Restore -eq $False){
        $PrimaryQtrees=Get-NcQtree -VserverContext $myPrimaryVserver -Controller $myPrimaryController -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcQtree failed [$ErrorVar]" }
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcQtree.json")){
            $PrimaryQtrees=Get-Content $($Global:JsonPath+"Get-NcQtree.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcQtree.json")
            Throw "ERROR: failed to read $filepath"
        }
    }
    if($Backup -eq $True){
        $PrimaryQtrees | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcQtree.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcQtree.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcQtree.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcQtree.json")"
            $Return=$False
        }
    }
    if($Backup -eq $False){
        foreach($qtree in $PrimaryQtrees | Where-Object {($_.Qtree).Length -gt 1}){
            $QName=$qtree.Qtree
            $ExportPolicy=$qtree.ExportPolicy
            $Volume=$qtree.Volume
            if($DebugLevel){Write-LogDebug "Work on Qtree [$QName]"}
            if($DebugLevel){Write-LogDebug "Get-NcQtree -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Volume $Volume -Qtree $QName"}
            $SecQtree=Get-NcQtree -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Volume $Volume -Qtree $QName -ErrorVariable ErrorVar
            if($? -ne $True){$Return=$Fasle;Throw "ERROR: Failed to get Qtree [$QName] on [$mySecondaryVserver] reason [$ErrorVar]"}
            if($SecQtree -eq $null){Write-Warning "Qtree [$QName] does not exist on [$mySecondaryVserver]. Please Resync relationship"}
            else{
                $SecExportPolicy=$SecQtree.ExportPolicy
                if($SecExportPolicy -ne $ExportPolicy){
                    Write-Log "Modify Export Policy on Qtree [$QName] to [$ExportPolicy] on [$mySecondaryVserver]"
                    Write-LogDebug "Set-NcQtree -Volume $volume -Qtree $QName -ExportPolicy $ExportPolicy -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                    $out=Set-NcQtree -Volume $volume -Qtree $QName -ExportPolicy $ExportPolicy -VserverContext $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErrorVar
                    if($? -ne $True){$Return=$Fasle;Throw "ERROR: Failed to Set export policy [$ExportPolicy] on Qtree [$QName] on [$mySecondaryVserver] reason [$ErrorVar]"}
                }
            }
        }
    }
    Write-LogDebug "update_qtree_export_policy_dr[$myPrimaryVserver]: end"
    return $True 
}
Catch {
    handle_error $_ $myPrimaryVserver
    return $Return
}
}

#############################################################################################
Function create_update_LDAP_dr (
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) {
Try {
    $Return=$True
    Write-Log "[$workOn] Check SVM LDAP configuration"
    Write-LogDebug "create_update_LDAP_dr[$myPrimaryVserver]: start"
    if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
    if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}

    if($Restore -eq $False){
        Write-LogDebug "Get-NcLdapConfig -vserverContext $myPrimaryVserver -Controller $myPrimaryController"
        $PrimaryLDAP=Get-NcLdapConfig -vserverContext $myPrimaryVserver -Controller $myPrimaryController -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcLdapConfig failed [$ErrorVar]" }
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcLdapConfig.json")){
            $PrimaryLDAP=Get-Content $($Global:JsonPath+"Get-NcLdapConfig.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcLdapConfig.json")
            Throw "ERROR: failed to read $filepath"
        }
    }
    if($Backup -eq $True){
        $PrimaryLDAP | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcLdapConfig.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcLdapConfig.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcLdapConfig.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcLdapConfig.json")"
            $Return=$False
        }
    }
    if ($PrimaryLDAP -ne $null){
        $PrimClient=$PrimaryLDAP.ClientConfig
        $PrimClientEnabled=$PrimaryLDAP.ClientEnabled
        Write-Log "[$workOn] LDAP client [$PrimClient] on [$myPrimaryVserver]"
        if($Restore -eq $False){
            Write-LogDebug "Get-NcLdapClient -Name $PrimClient -VserverContext $myPrimaryVserver -Controller $myPrimaryController"
            $PrimaryLDAPclient=Get-NcLdapClient -Name $PrimClient -VserverContext $myPrimaryVserver -Controller $myPrimaryController -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcLdapClient failed [$ErrorVar]" }
        }else{
            if(Test-Path $($Global:JsonPath+"Get-NcLdapClient.json")){
                $PrimaryLDAPclient=Get-Content $($Global:JsonPath+"Get-NcLdapClient.json") | ConvertFrom-Json
            }else{
                $Return=$False
                $filepath=$($Global:JsonPath+"Get-NcLdapClient.json")
                Throw "ERROR: failed to read $filepath"
            }
        }
        if($Backup -eq $True){
            $PrimaryLDAPclient | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcLdapClient.json") -Encoding ASCII -Width 65535
            if( ($ret=get-item $($Global:JsonPath+"Get-NcLdapClient.json") -ErrorAction SilentlyContinue) -ne $null ){
                Write-LogDebug "$($Global:JsonPath+"Get-NcLdapClient.json") saved successfully"
            }else{
                Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcLdapClient.json")"
                $Return=$False
            }
        }
        if ( $PrimaryLDAPclient -eq $null) {
            Write-Log "LDAP enabled but no Client configuration found on [$myPrimaryVserver]"
            Write-LogDebug "create_update_LDAP_dr: end with error"
            return $True    
        }
        $PrimaryLDAPclientSchema=$PrimaryLDAPclient.Schema
        if($Restore -eq $False){
            Write-LogDebug "Get-NcLdapClientSchema -Name $PrimaryLDAPclientSchema -VserverContext $myPrimaryVserver -Controller $myPrimaryController"
            $PrimarySchema=Get-NcLdapClientSchema -Name $PrimaryLDAPclientSchema -VserverContext $myPrimaryVserver -Controller $myPrimaryController -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcLdapClientSchema [$ErrorVar]" }
        }else{
            if(Test-Path $($Global:JsonPath+"Get-NcLdapClientSchema.json")){
                $PrimarySchema=Get-Content $($Global:JsonPath+"Get-NcLdapClientSchema.json") | ConvertFrom-Json
            }else{
                $Return=$False
                $filepath=$($Global:JsonPath+"Get-NcLdapClientSchema.json")
                Throw "ERROR: failed to read $filepath"
            }    
        }
        if($Backup -eq $True){
            $PrimarySchema | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcLdapClientSchema.json") -Encoding ASCII -Width 65535
            if( ($ret=get-item $($Global:JsonPath+"Get-NcLdapClientSchema.json") -ErrorAction SilentlyContinue) -ne $null ){
                Write-LogDebug "$($Global:JsonPath+"Get-NcLdapClientSchema.json") saved successfully"
            }else{
                Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcLdapClientSchema.json")"
                $Return=$False
            }
        }
        if ( $PrimarySchema -eq $null) {
            Write-Log "[$workOn] LDAP Schema [$PrimaryLDAPclientSchema] not found on [$myPrimaryVserver]"
            Write-LogDebug "create_update_LDAP_dr: end with error"
            return $True    
        }
        if($Backup -eq $False){
            $PrimarySchemaComment=$PrimarySchema.Comment
            $PrimarySchemaIsOwner=$PrimarySchema.IsOwner
            if( ($PrimarySchemaComment -match "(read-only)$") -or ($PrimarySchemaIsOwner -eq $True) ){
                Write-Log "[$workOn] LDAP Schema [$PrimaryLDAPclientSchema] replicated on [$mySecondaryVserver]"
                $PrimarySchemaCnGroupAttribute=$PrimarySchema.CnGroupAttribute
                $PrimarySchemaCnNetgroupAttribute=$PrimarySchema.CnNetgroupAttribute
                $PrimarySchemaEnableRfc2307bis=$PrimarySchema.EnableRfc2307bis
                $PrimarySchemaGecosAttribute=$PrimarySchema.GecosAttribute
                $PrimarySchemaGidNumberAttribute=$PrimarySchema.GidNumberAttribute
                $PrimarySchemaGroupOfUniqueNamesObjectClass=$PrimarySchema.GroupOfUniqueNamesObjectClass
                $PrimarySchemaHomeDirectoryAttribute=$PrimarySchema.HomeDirectoryAttribute
                $PrimarySchemaLoginShellAttribute=$PrimarySchema.LoginShellAttribute
                $PrimarySchemaMemberNisNetgroupAttribute=$PrimarySchema.MemberNisNetgroupAttribute
                $PrimarySchemaMemberUidAttribute=$PrimarySchema.MemberUidAttribute
                $PrimarySchemaNisMapentryAttribute=$PrimarySchema.NisMapentryAttribute
                $PrimarySchemaNisMapnameAttribute=$PrimarySchema.NisMapnameAttribute
                $PrimarySchemaNisNetgroupObjectClass=$PrimarySchema.NisNetgroupObjectClass
                $PrimarySchemaNisNetgroupTripleAttribute=$PrimarySchema.NisNetgroupTripleAttribute
                $PrimarySchemaNisObjectClass=$PrimarySchema.NisObjectClass
                $PrimarySchemaPosixAccountObjectClass=$PrimarySchema.PosixAccountObjectClass
                $PrimarySchemaPosixGroupObjectClass=$PrimarySchema.PosixGroupObjectClass
                $PrimarySchemaUserPasswordAttribute=$PrimarySchema.UserPasswordAttribute
                $PrimarySchemaUidAttribute=$PrimarySchema.UidAttribute
                $PrimarySchemaUidNumberAttribute=$PrimarySchema.UidNumberAttribute
                $PrimarySchemaUniqueMemberAttribute=$PrimarySchema.UniqueMemberAttribute
                $PrimarySchemaUserPasswordAttribute=$PrimarySchema.UserPasswordAttribute
                $PrimarySchemaWindowsAccountAttribute=$PrimarySchema.WindowsAccountAttribute
                $PrimarySchemaWindowsToUnixAttribute=$PrimarySchema.WindowsToUnixAttribute
                $PrimarySchemaWindowsToUnixNoDomainPrefix=$PrimarySchema.WindowsToUnixNoDomainPrefix
                $PrimarySchemaWindowsToUnixObjectClass=$PrimarySchema.WindowsToUnixObjectClass
                Write-LogDebug "Copy-NcLdapClientSchema -Name RFC-2307 -NewName $PrimaryLDAPclientSchema -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                $out=Copy-NcLdapClientSchema -Name RFC-2307 -NewName $PrimaryLDAPclientSchema -VserverContext $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Copy-NcLdapClientSchema [$ErrorVar]" }
                Write-LogDebug "Set-NcLdapClientSchema -Name $PrimaryLDAPclientSchema -VserverContext -VserverContext $mySecondaryVserver `
                -PosixAccount $PrimarySchemaPosixAccountObjectClass `
                -NisNetgroup $PrimarySchemaNisNetgroupObjectClass `
                -Uid $PrimarySchemaUidAttribute `
                -GidNumber $PrimarySchemaGidNumberAttribute `
                -PosixGroup $PrimarySchemaPosixGroupObjectClass `
                -UidNumber $PrimarySchemaUidNumberAttribute `
                -GroupCn $PrimarySchemaCnGroupAttribute `
                -NetGroupCn $PrimarySchemaCnNetgroupAttribute `
                -Gecos $PrimarySchemaGecosAttribute `
                -UserPassword $PrimarySchemaUserPasswordAttribute `
                -HomeDirectory $PrimarySchemaHomeDirectoryAttribute `
                -LoginShell $PrimarySchemaLoginShellAttribute `
                -MemberUid $PrimarySchemaMemberUidAttribute `
                -MemberNisNetgroup $PrimarySchemaMemberNisNetgroupAttribute `
                -NisNetgroupTriple $PrimarySchemaNisNetgroupTripleAttribute `
                -WindowsAccount $PrimarySchemaWindowsAccountAttribute `
                -EnableRfc2307bis $PrimarySchemaEnableRfc2307bis `
                -GroupOfUniqueNamesObjectClass $PrimarySchemaGroupOfUniqueNamesObjectClass `
                -UniqueMemberAttribute $PrimarySchemaUniqueMemberAttribute `
                -NisMapEntryAttribute $PrimarySchemaNisMapentryAttribute `
                -NisMapNameAttribute $PrimarySchemaNisMapnameAttribute `
                -NisObjectClass $PrimarySchemaNisObjectClass `
                -WindowsToUnixObjectClass $PrimarySchemaWindowsToUnixObjectClass `
                -WindowsToUnixAttribute $PrimarySchemaWindowsToUnixAttribute `
                -NoDomainPrefixForWindowsToUnix $PrimarySchemaWindowsToUnixNoDomainPrefix `
                -Comment $PrimarySchemaComment `
                -Controller $mySecondaryController"
                $out=Set-NcLdapClientSchema -Name $PrimaryLDAPclientSchema -VserverContext -VserverContext $mySecondaryVserver `
                -PosixAccount $PrimarySchemaPosixAccountObjectClass `
                -NisNetgroup $PrimarySchemaNisNetgroupObjectClass `
                -Uid $PrimarySchemaUidAttribute `
                -GidNumber $PrimarySchemaGidNumberAttribute `
                -PosixGroup $PrimarySchemaPosixGroupObjectClass `
                -UidNumber $PrimarySchemaUidNumberAttribute `
                -GroupCn $PrimarySchemaCnGroupAttribute `
                -NetGroupCn $PrimarySchemaCnNetgroupAttribute `
                -Gecos $PrimarySchemaGecosAttribute `
                -UserPassword $PrimarySchemaUserPasswordAttribute `
                -HomeDirectory $PrimarySchemaHomeDirectoryAttribute `
                -LoginShell $PrimarySchemaLoginShellAttribute `
                -MemberUid $PrimarySchemaMemberUidAttribute `
                -MemberNisNetgroup $PrimarySchemaMemberNisNetgroupAttribute `
                -NisNetgroupTriple $PrimarySchemaNisNetgroupTripleAttribute `
                -WindowsAccount $PrimarySchemaWindowsAccountAttribute `
                -EnableRfc2307bis $PrimarySchemaEnableRfc2307bis `
                -GroupOfUniqueNamesObjectClass $PrimarySchemaGroupOfUniqueNamesObjectClass `
                -UniqueMemberAttribute $PrimarySchemaUniqueMemberAttribute `
                -NisMapEntryAttribute $PrimarySchemaNisMapentryAttribute `
                -NisMapNameAttribute $PrimarySchemaNisMapnameAttribute `
                -NisObjectClass $PrimarySchemaNisObjectClass `
                -WindowsToUnixObjectClass $PrimarySchemaWindowsToUnixObjectClass `
                -WindowsToUnixAttribute $PrimarySchemaWindowsToUnixAttribute `
                -NoDomainPrefixForWindowsToUnix $PrimarySchemaWindowsToUnixNoDomainPrefix `
                -Comment $PrimarySchemaComment `
                -Controller $mySecondaryController -ErrorVariable ErrorVar 
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcLdapClientSchema [$ErrorVar]" }
            }else{ 
                Write-LogDebug "This is a default Schema"    
            }
            Write-LogDebug "Get-NcLdapClient -Name $PrimClient -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
            $SecondaryLDAPclient=Get-NcLdapClient -Name $PrimClient -VserverContext $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcLdapClient failed [$ErrorVar]" }
            if ($SecondaryLDAPclient -eq $null){
                $LDAPclientAdDomain=$PrimaryLDAPclient.AdDomain
                $LDAPclientAllowSsl=$PrimaryLDAPclient.AllowSsl
                $LDAPclientBaseDn=$PrimaryLDAPclient.BaseDn
                $LDAPclientBaseScope=$PrimaryLDAPclient.BaseScope
                $LDAPclientBindAsCifsServer=$PrimaryLDAPclient.BindAsCifsServer
                $LDAPclientBindDn=$PrimaryLDAPclient.BindDn
                $LDAPclientBindPassword=$PrimaryLDAPclient.BindPassword
                $LDAPclientClient=$PrimaryLDAPclient.Client
                $LDAPclientGroupDn=$PrimaryLDAPclient.GroupDn
                $LDAPclientGroupScope=$PrimaryLDAPclient.GroupScope
                $LDAPclientIsNetgroupByhostEnabled=$PrimaryLDAPclient.IsNetgroupByhostEnabled
                $LDAPclientLdapClientConfig=$PrimaryLDAPclient.LdapClientConfig
                $LDAPclientLdapServers=$PrimaryLDAPclient.LdapServers
                $LDAPclientMinBindLevel=$PrimaryLDAPclient.MinBindLevel
                $LDAPclientNetgroupByhostDn=$PrimaryLDAPclient.NetgroupByhostDn
                $LDAPclientNetgroupScope=$PrimaryLDAPclient.NetgroupScope
                $LDAPclientNetgroupDn=$PrimaryLDAPclient.NetgroupDn
                $LDAPclientNetgroupDn=$PrimaryLDAPclient.NetgroupByhostScope
                $LDAPclientObsPassword=$PrimaryLDAPclient.ObsPassword
                $LDAPclientPreferredAdServers=$PrimaryLDAPclient.PreferredAdServers
                $LDAPclientQueryTimeout=$PrimaryLDAPclient.QueryTimeout
                $LDAPclientQueryTimeoutTS=$PrimaryLDAPclient.QueryTimeoutTS
                $LDAPclientSchema=$PrimaryLDAPclient.Schema
                $LDAPclientServers=$PrimaryLDAPclient.Servers
                $LDAPclientSessionSecurity=$PrimaryLDAPclient.SessionSecurity
                $LDAPclientSkipConfigValidation=$PrimaryLDAPclient.SkipConfigValidation
                $LDAPclientUserDn=$PrimaryLDAPclient.UserDn
                $LDAPclientUserScope=$PrimaryLDAPclient.UserScope
                $LDAPclientUseStartTls=$PrimaryLDAPclient.UseStartTls
                $LDAPclientTcpPort=$PrimaryLDAPclient.TcpPort  
            }else{
                $LDAPclientAdDomain=$PrimaryLDAPclient.AdDomain
                $LDAPclientAllowSsl=$PrimaryLDAPclient.AllowSsl
                $LDAPclientBaseDn=$PrimaryLDAPclient.BaseDn
                $LDAPclientBaseScope=$PrimaryLDAPclient.BaseScope
                $LDAPclientBindAsCifsServer=$PrimaryLDAPclient.BindAsCifsServer
                $LDAPclientBindDn=$PrimaryLDAPclient.BindDn
                $LDAPclientBindPassword=$PrimaryLDAPclient.BindPassword
                $LDAPclientClient=$PrimaryLDAPclient.Client
                $LDAPclientGroupDn=$PrimaryLDAPclient.GroupDn
                $LDAPclientGroupScope=$PrimaryLDAPclient.GroupScope
                $LDAPclientIsNetgroupByhostEnabled=$PrimaryLDAPclient.IsNetgroupByhostEnabled
                $LDAPclientLdapClientConfig=$PrimaryLDAPclient.LdapClientConfig
                $LDAPclientLdapServers=$SecondaryLDAPclient.LdapServers
                $LDAPclientMinBindLevel=$PrimaryLDAPclient.MinBindLevel
                $LDAPclientNetgroupByhostDn=$PrimaryLDAPclient.NetgroupByhostDn
                $LDAPclientNetgroupScope=$PrimaryLDAPclient.NetgroupScope
                $LDAPclientNetgroupDn=$PrimaryLDAPclient.NetgroupDn
                $LDAPclientNetgroupByhostScope=$PrimaryLDAPclient.NetgroupByhostScope
                $LDAPclientObsPassword=$PrimaryLDAPclient.ObsPassword
                $LDAPclientPreferredAdServers=$SecondaryLDAPclient.PreferredAdServers
                $LDAPclientQueryTimeout=$PrimaryLDAPclient.QueryTimeout
                $LDAPclientQueryTimeoutTS=$PrimaryLDAPclient.QueryTimeoutTS
                $LDAPclientSchema=$PrimaryLDAPclient.Schema
                $LDAPclientServers=$SecondaryLDAPclient.Servers
                $LDAPclientSessionSecurity=$PrimaryLDAPclient.SessionSecurity
                $LDAPclientSkipConfigValidation=$PrimaryLDAPclient.SkipConfigValidation
                $LDAPclientUserDn=$PrimaryLDAPclient.UserDn
                $LDAPclientUserScope=$PrimaryLDAPclient.UserScope
                $LDAPclientUseStartTls=$PrimaryLDAPclient.UseStartTls
                $LDAPclientTcpPort=$PrimaryLDAPclient.TcpPort
                if($DebugLevel){Write-LogDebug "LDAP config exist on [$mySecondaryVserver] need to delete config, before delete LDAP client"}
                try{
                    Write-LogDebug "Remove-NcLdapConfig -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
                    $out=Remove-NcLdapConfig -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Confirm:$False -ErrorVariable ErrorVar
                    if($? -ne $True) {$Return = $False; throw "ERROR failed to remove LDAP config on [$mySecondaryVserver] reason [$ErrorVar]"}
                }catch{
                    $reason=$_.Exception.Message
                    Write-LogDebug "Failed Remove-NcLdapConfig reason [$reason]"
                }
                try{
                    Write-LogDebug "Remove-NcLdapClient -Name $PrimClient -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Confirm:$false"
                    $out=Remove-NcLdapClient -Name $PrimClient -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Confirm:$false -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Remove-NcLdapClient failed [$ErrorVar]" }
                }catch{
                    $reason=$_.Exception.Message
                    Write-LogDebug "Failed Remove-NcLdapClient reason [$reason]"    
                }
            }
            Write-Log "[$workOn] Configure LDAP configuration on [$mySecondaryVserver]"
            try {
                $global:mutexconsole.WaitOne(200) | Out-Null
            }
            catch [System.Threading.AbandonedMutexException]{
                #AbandonedMutexException means another thread exit without releasing the mutex, and this thread has acquired the mutext, therefore, it can be ignored
                Write-Host -f Red "catch abandoned mutex for [$myPrimaryVserver]"
                free_mutexconsole
            }
            if($LDAPclientAdDomain.length -gt 0){
                $LDAPclientAdDomain=Read-HostDefault "[$mySecondaryVserver] Enter Active Directory Domain" $LDAPclientAdDomain
                $ldapserverslist=@()
                $existingPreferedADServers=$LDAPclientPreferredAdServers
                $index=0
                do{
                    if($existingPreferedADServers.GetType().Name -match "\[\]"){
                        $previousPreferedServer=$existingPreferedADServers[$index]
                        $index++
                    }else{
                        $previousPreferedServer=$existingPreferedADServers    
                    }
                    do{
                        $ldapserver=Read-HostDefault "[$mySecondaryVserver] Enter AD Prefered LDAP server IP []" $previousPreferedServer
                    }
                    while(validate_ip_format $ldapserver)
                    $ldapserverslist+=$ldapserver
                    $ANS=Read-HostOptions "[$mySecondaryVserver] Do you want to add another AD Prefered LDAP server ?" "y/n"
                }
                while($ANS -eq "y")
                $LDAPclientADServers=$ldapserverslist
                do{
                    $ReEnter=$false
                    $pass1=Read-Host "[$mySecondaryVserver] Please Enter LDAP server Bind Password" -AsSecureString
                    $pass2=Read-Host "[$mySecondaryVserver] Please Re-Enter LDAP server Bind Password" -AsSecureString
                    $pwd1_text = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass1))
                    $pwd2_text = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass2))

                    if ($pwd1_text -ceq $pwd2_text) {
                        Write-LogDebug "Passwords matched"
                    } 
                    else{
                        Write-Warning "[$mySecondaryVserver] Error passwords does not match. Please Re-Enter"
                        $ReEnter=$True
                    }
                }while($ReEnter -eq $True)
                $LDAPclientBindPassword=$pwd1_text
                Write-LogDebug "New-NcLdapClient -Name $PrimClient -VserverContext $mySecondaryVserver `
                -Schema $LDAPclientSchema `
                -AdDomain $LDAPclientAdDomain `
                -PreferredAdServers $LDAPclientADServers `
                -TcpPort $LDAPclientTcpPort `
                -QueryTimeout $LDAPclientQueryTimeout `
                -MinBindLevel $LDAPclientMinBindLevel `
                -BindDn $LDAPclientBindDn `
                -BindPassword $pass1 `
                -BaseDn $LDAPclientBaseDn `
                -BaseScope $LDAPclientBaseScope `
                -UserDn $LDAPclientUserDn `
                -UserScope $LDAPclientUserScope `
                -GroupDn $LDAPclientGroupDn `
                -GroupScope $LDAPclientGroupScope `
                -NetGroupDn $LDAPclientNetgroupDn `
                -NetGroupScope $LDAPclientNetgroupScope `
                -IsNetgroupByHostEnabled $LDAPclientIsNetgroupByhostEnabled `
                -NetgroupByHostScope $LDAPclientNetgroupByhostScope `
                -SessionSecurity $LDAPclientSessionSecurity `
                -Controller $mySecondaryController -Confirm:$false"
                $out=New-NcLdapClient -Name $PrimClient -VserverContext $mySecondaryVserver `
                -Schema $LDAPclientSchema `
                -AdDomain $LDAPclientAdDomain `
                -PreferredAdServers $LDAPclientADServers `
                -TcpPort $LDAPclientTcpPort `
                -QueryTimeout $LDAPclientQueryTimeout `
                -MinBindLevel $LDAPclientMinBindLevel `
                -BindDn $LDAPclientBindDn `
                -BindPassword $LDAPclientBindPassword `
                -BaseDn $LDAPclientBaseDn `
                -BaseScope $LDAPclientBaseScope `
                -UserDn $LDAPclientUserDn `
                -UserScope $LDAPclientUserScope `
                -GroupDn $LDAPclientGroupDn `
                -GroupScope $LDAPclientGroupScope `
                -NetGroupDn $LDAPclientNetgroupDn `
                -NetGroupScope $LDAPclientNetgroupScope `
                -IsNetgroupByHostEnabled $LDAPclientIsNetgroupByhostEnabled `
                -NetgroupByHostScope $LDAPclientNetgroupByhostScope `
                -SessionSecurity $LDAPclientSessionSecurity `
                -Controller $mySecondaryController -Confirm:$false -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcLdapClient failed [$ErrorVar]" ;free_mutexconsole} 
            }else{
                $serverslist=@()
                $existingServers=$LDAPclientServers
                $index=0
                do{
                    if($existingServers.count -gt 0){
                        if($existingServers.GetType().Name -match "\[\]"){
                            $previousServer=$existingServers[$index]
                            $index++
                        }else{
                            $previousServer=$existingServers    
                        }
                    }else{$previsousServer=""}
                    do{
                        $server=Read-HostDefault "[$mySecondaryVserver] Enter LDAP server IP" $previousServer
                    }
                    while((validate_ip_format $server) -eq $False)
                    $serverslist+=$server
                    $ANS=Read-HostOptions "[$mySecondaryVserver] Do you want to add another LDAP server" "y/n"
                }
                while($ANS -eq "y")
                do{
                    $ReEnter=$false
                    $pass1=Read-Host "[$mySecondaryVserver] Please Enter LDAP server Bind Password" -AsSecureString
                    $pass2=Read-Host "[$mySecondaryVserver] Please Re-Enter LDAP server Bind Password" -AsSecureString
                    $pwd1_text = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass1))
                    $pwd2_text = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass2))

                    if ($pwd1_text -ceq $pwd2_text) {
                        Write-LogDebug "Passwords matched"
                    } 
                    else{
                        Write-Warning "[$mySecondaryVserver] Error passwords does not match. Please Re-Enter"
                        $ReEnter=$True
                    }
                }while($ReEnter -eq $True)
                $LDAPclientBindPassword=$pwd1_text 
                $LDAPclientServers=$serverslist
                Write-LogDebug "New-NcLdapClient -Name $PrimClient -VserverContext $mySecondaryVserver `
                -Schema $LDAPclientSchema `
                -Servers $LDAPclientServers `
                -TcpPort $LDAPclientTcpPort `
                -QueryTimeout $LDAPclientQueryTimeout `
                -MinBindLevel $LDAPclientMinBindLevel `
                -BindDn $LDAPclientBindDn `
                -BindPassword $pass1 `
                -BaseDn $LDAPclientBaseDn `
                -BaseScope $LDAPclientBaseScope `
                -UserDn $LDAPclientUserDn `
                -UserScope $LDAPclientUserScope `
                -GroupDn $LDAPclientGroupDn `
                -GroupScope $LDAPclientGroupScope `
                -NetGroupDn $LDAPclientNetgroupDn `
                -NetGroupScope $LDAPclientNetgroupScope `
                -IsNetgroupByHostEnabled $LDAPclientIsNetgroupByhostEnabled `
                -NetgroupByHostScope $LDAPclientNetgroupByhostScope `
                -SessionSecurity $LDAPclientSessionSecurity `
                -Controller $mySecondaryController -Confirm:$false"
                $out=New-NcLdapClient -Name $PrimClient -VserverContext $mySecondaryVserver `
                -Schema $LDAPclientSchema `
                -Servers $LDAPclientServers `
                -TcpPort $LDAPclientTcpPort `
                -QueryTimeout $LDAPclientQueryTimeout `
                -MinBindLevel $LDAPclientMinBindLevel `
                -BindDn $LDAPclientBindDn `
                -BindPassword $LDAPclientBindPassword `
                -BaseDn $LDAPclientBaseDn `
                -BaseScope $LDAPclientBaseScope `
                -UserDn $LDAPclientUserDn `
                -UserScope $LDAPclientUserScope `
                -GroupDn $LDAPclientGroupDn `
                -GroupScope $LDAPclientGroupScope `
                -NetGroupDn $LDAPclientNetgroupDn `
                -NetGroupScope $LDAPclientNetgroupScope `
                -IsNetgroupByHostEnabled $LDAPclientIsNetgroupByhostEnabled `
                -NetgroupByHostScope $LDAPclientNetgroupByhostScope `
                -SessionSecurity $LDAPclientSessionSecurity `
                -Controller $mySecondaryController -Confirm:$false -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcLdapClient failed [$ErrorVar]" ;free_mutexconsole}    
            }
            free_mutexconsole
            Write-LogDebug "Get-NcLdapConfig -vserver $mySecondaryVserver -controller $mySecondaryController"
            $SecondaryLdapConfig=Get-NcLdapConfig -vserver $mySecondaryVserver -controller $mySecondaryController -ErrorVariable ErrorVar
            if($? -ne $True){Throw "ERROR: Failed to get LDAP Config on [$mySecondaryVserver] reason [$ErrorVar]"}
            if($SecondaryLdapConfig -ne $null)
            {
                Write-LogDebug "Remove-NcLdapConfig -Vservercontext $mySecondaryVserver -Controller $mySecondaryController"
                $out=Remove-NcLdapConfig -Vservercontext $mySecondaryVserver -Controller $mySecondaryController -Confirm:$False -ErrorVariable ErrorVar
                if($? -ne $True){Throw "ERROR: Failed to remove LDAP Config on [$mySecondaryVserver] reason [$ErrorVar]"}
            }
            $version=Get-NcSystemVersionInfo -Controller $mySecondaryController
            if($version.VersionTupleV.Major -ge 9 -and $version.VersionTupleV.Minor -ge 3){
                if($PrimClientEnabled -eq $True){
                    Write-LogDebug "New-NcLdapConfig -ClientConfig $PrimClient -ClientEnabled $PrimClientEnabled -SkipConfigValidation -Vservercontext $mySecondaryVserver -Controller $mySecondaryController"
                    $out=New-NcLdapConfig -ClientConfig $PrimClient -ClientEnabled $PrimClientEnabled -SkipConfigValidation -Vservercontext $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErrorVar
                    if($? -ne $True){Throw "ERROR: Failed to create LDAP Config on [$mySecondaryVserver] reason [$ErrorVar]"}
                }else{
                    Write-Log "[$workOn] LDAP config not created on [$mySecondaryVserver] because it is disable on [$myPrimaryVserver]"
                }
            }else{
                Write-LogDebug "New-NcLdapConfig -ClientConfig $PrimClient -ClientEnabled $PrimClientEnabled -SkipConfigValidation -Vservercontext $mySecondaryVserver -Controller $mySecondaryController"
                $out=New-NcLdapConfig -ClientConfig $PrimClient -ClientEnabled $PrimClientEnabled -SkipConfigValidation -Vservercontext $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErrorVar
                if($? -ne $True){Throw "ERROR: Failed to create LDAP Config on [$mySecondaryVserver] reason [$ErrorVar]"}
            }
        }
    }else{
        Write-LogDebug "No LDAP configuration for SVM [$myPrimaryVserver]"
    }
    Write-LogDebug "create_update_LDAP_dr[$myPrimaryVserver]: end"
    return $True 
}
Catch {
    handle_error $_ $myPrimaryVserver
    return $Return
}
}

#############################################################################################
Function create_update_CIFS_server_dr (
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string] $workOn=$mySecondaryVserver,
    [bool] $Backup,
    [bool] $Restore,
    [switch] $ForClone) {
Try {

	$Return=$True
    Write-Log "[$workOn] Check SVM CIFS Sever configuration"
    Write-LogDebug "create_update_CIFS_server_dr[$myPrimaryVserver]: start"
    if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
    if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}

    if($Restore -eq $False){
        $PrimaryCifsServerInfos = Get-NcCifsServer  -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsServer failed [$ErrorVar]" }
        $PrimaryInterfaceList = Get-NcNetInterface -Role DATA -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar 
	    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNetInterface failed [$ErrorVar]" }
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcCifsServer.json")){
            $PrimaryCifsServerInfos=Get-Content $($Global:JsonPath+"Get-NcCifsServer.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcCifsServer.json")
            Throw "ERROR: failed to read $filepath"
        }   
        if(Test-Path $($Global:JsonPath+"Get-NcNetInterface.json")){
            $PrimaryInterfaceList=Get-Content $($Global:JsonPath+"Get-NcNetInterface.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcNetInterface.json")
            Throw "ERROR: failed to read $filepath"
        } 
    }
    if($Backup -eq $True){
        $PrimaryCifsServerInfos | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcCifsServer.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcCifsServer.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcCifsServer.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcCifsServer.json")"
            $Return=$False
        }
        $PrimaryInterfaceList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcNetInterface.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcNetInterface.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcNetInterface.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcNetInterface.json")"
            $Return=$False
        }
    }
    if($Backup -eq $False){
        if ( $PrimaryCifsServerInfos -eq $null ) {
            Write-Log "[$workOn] No CIFS Server in Vserver [$myPrimaryVserver]:[$myPrimaryController]"
            Write-LogDebug "create_update_CIFS_server_dr: end"
            return $True
        }
        $SecondaryCifsServerInfos = Get-NcCifsServer -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsServer failed [$ErrorVar]" }
        try {
            $global:mutexconsole.WaitOne(200) | Out-Null
        }
        catch [System.Threading.AbandonedMutexException]{
            #AbandonedMutexException means another thread exit without releasing the mutex, and this thread has acquired the mutext, therefore, it can be ignored
            Write-Host -f Red "catch abandoned mutex for [$myPrimaryVserver]"
            free_mutexconsole
        }
        if ( $SecondaryCifsServerInfos -eq $null ) 
        {
            Write-Log "[$workOn] Add CIFS Server in Vserver DR : [$mySecondaryVserver] [$mySecondaryController]"
            $SecondaryAuthStyle = $PrimaryCifsServerInfos.AuthStyle
            $SecondaryCifsServer = $PrimaryCifsServerInfos.CifsServer + "-DR"
            $SecondaryDefaultSite = $PrimaryCifsServerInfos.DefaultSite
            $SecondaryDomain = $PrimaryCifsServerInfos.Domain
            $SecondaryDomainWorkgroup = $PrimaryCifsServerInfos.DomainWorkgroup
            $SecondaryOrganizationalUnit = $PrimaryCifsServerInfos.OrganizationalUnit
            $ADCred = get_local_cred ($SecondaryDomain)
            if($ForClone -eq $True){
                $SecondaryCifsServer = $mySecondaryVserver
                if($SecondaryCifsServer.length -gt 15){
                    $SecondaryCifsServer=$SecondaryCifsServer -replace "_clone\.","_c."
                    if($SecondaryCifsServer.length -gt 15){
                        $SecondaryCifsServer=$SecondaryCifsServer.Substring($SecondaryCifsServer.length-15,15)    
                    }
                }
                Write-Log "[$workOn] Clone CIFS server name set to [$SecondaryCifsServer]"   
            }else{
                $ANS = 'n'
                while ( $ANS -ne 'y' ) {
                    $SecondaryCifsServer = Read-HostDefault "[$mySecondaryVserver] Please Enter your default Secondary CIFS server Name" $SecondaryCifsServer
                    if ( ( $SecondaryDomain -eq $PrimaryCifsServerInfos.Domain ) -and ( $SecondaryCifsServer -eq $PrimaryCifsServerInfos.CifsServer ) ) { 
                        Write-LogError "ERROR: Secondary CIFS server cannot use the same name has primary CIFS server in the same domain"
                    } else {
                            Write-Log "[$workOn] Default Secondary CIFS Name:      [$SecondaryCifsServer]"
                        Write-Log ""
                            $ANS = Read-HostOptions "[$workOn] Apply new configuration ?" "y/n"
                    }
                }
            }
            $myInterfaceName=""
            $SecondaryInterfaceList = Get-NcNetInterface -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNetInterface failed [$ErrorVar]" ;free_mutexconsole}
            if($SecondaryInterfaceList -ne $null)
            {
                if ( ($SecondaryInterfaceList | Where-Object {$_.OpStatus -eq "up"}).count -ge 1 )
                {
                    Write-LogDebug "create_update_CIFS_server_dr : At least one LIF is up"
                    $oneDRLIFupReady=$True
                }
                else
                {
                    Write-LogDebug "create_update_CIFS_server_dr : LIF with protocol exist but is down"
                    $myInterfacesList=$SecondaryInterfaceList | Where-Object {$_.OpStatus -eq "down" -and $_.DataProtocols -match "cifs"}
                    if($myInterfacesList -eq $null){
                        Write-Log "[$workOn] No CIFS LIF available on DR vserver"
                        Write-Log "[$workOn] Unable to register CIFS server"
                        Write-Log "[$workOn] Add a CIFS LIF an rerun ConfigureDR"
                        free_mutexconsole
                        return $False
                    }
                    $oneDRLIFupReady=$False
                    foreach ($myInterface in $myInterfacesList){
                        $duplicateIP=$False
                        $myInterfaceName=$myInterface.InterfaceName
                        $myInterfaceIP=$myInterface.Address
                        <# $PrimaryInterfaceList = Get-NcNetInterface -Role DATA -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar 
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNetInterface failed [$ErrorVar]" } #>
                        foreach ( $PrimaryInterface in ( $PrimaryInterfaceList | Where-Object {$_.OpStatus -eq "up" -and $_.DataProtocols -match "cifs"} | Skip-Null ) ) {
                            $PrimaryInterfaceName=$PrimaryInterface.InterfaceName
                            $PrimaryAddress=$PrimaryInterface.Address
                            if($PrimaryAddress -eq $myInterfaceIP){
                                $duplicateIP=$True
                                break  
                            }
                        }
                        if($duplicateIP -eq $False){
                            Write-logDebug "Set-NcNetInterface -Name $myInterfaceName -Vserver $mySecondaryVserver -AdministrativeStatus up -Controller $mySecondaryController"
                            $out=Set-NcNetInterface -Name $myInterfaceName -Vserver $mySecondaryVserver -AdministrativeStatus "up" -Controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcNetInterface up failed [$ErrorVar]" ;free_mutexconsole}    
                            $oneDRLIFupReady=$True
                            break
                        }
                    }
                    if($oneDRLIFupReady -eq $False){
                        Write-LogWarn "[$workOn] Impossible to switch DR LIF to up because of duplicate IP address with Source Vserver"
                        Write-LogWarn "[$workOn] Impossible to register CIFS server on DR Vserver"
                        Write-LogWarn "[$workOn] Configure a temporary IP address on DR Vserver to be able to register your CIFS server"
                        $ans = Read-HostOptions -question "I will wait here, so you can create that temp lif.  Is it done ?" "y/n"
                        if($ans -eq "y"){$oneDRLifupReady=$true}
                    }
                }
                if($oneDRLIFupReady -eq $True){
                    Write-logDebug "Add-NcCifsServer -Name $SecondaryCifsServer -Domain $SecondaryDomain -OrganizationalUnit $SecondaryOrganizationalUnit -DefaultSite  $SecondaryDefaultSite -AdminCredential $ADCred -Force -AdministrativeStatus down -VserverContext $mySecondaryVserver -Controller $mySecondaryController" 
                    $out = Add-NcCifsServer -Name $SecondaryCifsServer -Domain $SecondaryDomain -OrganizationalUnit $SecondaryOrganizationalUnit -DefaultSite $SecondaryDefaultSite -AdminCredential $ADCred -Force -AdministrativeStatus down -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Add-NcCifsServer failed [$ErrorVar]" ;free_mutexconsole}
                    if($myInterfaceName.Length -gt 0)
                    {
                        Write-logDebug "Set-NcNetInterface -Name $myInterfaceName -Vserver $mySecondaryVserver -AdministrativeStatus down -Controller $mySecondaryController"
                        $out=Set-NcNetInterface -Name $myInterfaceName -Vserver $mySecondaryVserver -AdministrativeStatus "down" -Controller $mySecondaryController  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcNetInterface down failed [$ErrorVar]" ;free_mutexconsole}    
                    }
                }
                else{
                    Write-Log "[$workOn] Impossible to switch DR LIF to up because of duplicate IP address with Source Vserver"
                    Write-Log "[$workOn] Impossible to register CIFS server on DR Vserver"
                    Write-Log "[$workOn] Configure a temporary IP address on DR Vserver to be able to register your CIFS server"
                    free_mutexconsole
                    return $False
                }
            }
            else
            {
                Write-Log "[$workOn] No LIF available on $mySecondaryVserver, impossible to register CIFS server"
                Write-Log "[$workOn] Create a LIF on DR with ConfigureDR"
                free_mutexconsole
                return $False    
            }
        }
        free_mutexconsole
    }
    Write-LogDebug "create_update_CIFS_server_dr: end"
	return $True 
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}


#############################################################################################
Function create_update_CIFS_shares_dr (
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) {
Try {

	$Return=$True
    $RunBackup=$False
    $RunRestore=$False
    Write-Log "[$workOn] Check SVM CIFS shares"
    Write-LogDebug "create_update_CIFS_shares_dr[$myPrimaryVserver]: start"
    if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]";$RunBackup=$True}
    if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]";$RunRestore=$True}
    if(-not (check_update_CIFS_server_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $mySecondaryVserver -Backup $RunBackup -Restore $RunRestore)){
        Write-LogDebug "create_update_CIFS_shares_dr: end"
        return $True
    }
    if($Restore -eq $False){
        $PrimaryVersion=(Get-NcSystemVersionInfo -Controller $myPrimaryController).VersionTupleV
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcSystemVersionInfo.json")){
            $PrimaryVersion=Get-Content $($Global:JsonPath+"Get-NcSystemVersionInfo.json") | ConvertFrom-Json
            $PrimaryVersion=$PrimaryVersion.VersionTupleV
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcSystemVersionInfo.json")
            Throw "ERROR: failed to read $filepath"
        }
    }
    $WinSIDCompatible=$False
    if($Backup -eq $False){
        $SecondaryVersion=(Get-NcSystemVersionInfo -Controller $mySecondaryController).VersionTupleV
        $SecondaryVersion_text=$SecondaryVersion | Out-String
        if($SecondaryVersion.Major -ge 9){
            if($SecondaryVersion.Minor -ge 3){
                $WinSIDCompatible=$True
                if($DebugLevel){Write-LogDebug "Secondary Version is [$SecondaryVersion_text] WinSIDCompatible set to True"}
            }
        }
    }
    if($Backup -eq $False -and $Restore -eq $False){
        if($WinSIDCompatible -eq $False){
        if($DebugLevel){Write-LogDebug "set_all_lif -mySecondaryVserver $mySecondaryVserver -myPrimaryVserver $myPrimaryVserver -mySecondaryController $mySecondaryController  -myPrimaryController $myPrimaryController -state up"}
            if (($ret=set_all_lif -mySecondaryVserver $mySecondaryVserver -myPrimaryVserver $myPrimaryVserver -mySecondaryController $mySecondaryController  -myPrimaryController $myPrimaryController -state up) -ne $True ) {
                    Write-LogError "ERROR: Failed to set all lif up on [$mySecondaryVserver]"
                    clean_and_exit 1
            }
        }
    }
	if(($PrimaryVersion.Major -ne $SecondaryVersion.Major) -or ($PrimaryVersion.Major -eq 8 -and $SecondaryVersion.Major -eq 8)){
		if($PrimaryVersion.Major -ge 9 -and $SecondaryVersion.Major -ge 9){
			$vfrEnable=$True
		}
		elseif(($PrimaryVersion.Major -eq 8 -and $PrimaryVersion.Minor -ge 3 -and $PrimaryVersion.Build -ge 2) -and ($SecondaryVersion.Major -ge 9)){
			$vfrEnable=$True
		}
		elseif(($SecondaryVersion.Major -eq 8 -and $SecondaryVersion.Minor -ge 3 -and $SecondaryVersion.Build -ge 2) -and ($PrimaryVersion.Major -ge 9)){
			$vfrEnable=$True
		}
		elseif(($PrimaryVersion.Major -eq 8 -and $PrimaryVersion.Minor -ge 3 -and $PrimaryVersion.Build -ge 2) -and ($SecondaryVersion.Major -eq 8 -and $SecondaryVersion.Minor -ge 3 -and $SecondaryVersion.Build -ge 2)){
			$vfrEnable=$True
		}
	}
    if($PrimaryVersion.Major -ge 9 -and $SecondaryVersion.Major -ge 9){
	    $vfrEnable=$True
	}
	if($Restore -eq $False){
        Write-LogDebug "Get-NcCifsServer -VserverContext $myPrimaryVserver -Controller $myPrimaryController"
        $PrimaryCifsServerInfos = Get-NcCifsServer -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsServer failed [$ErrorVar]" }
        $PrimaryServer=$PrimaryCifsServerInfos.CifsServer
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcCifsServer.json")){
            $PrimaryCifsServerInfos=Get-Content $($Global:JsonPath+"Get-NcCifsServer.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcCifsServer.json")
            Throw "ERROR: failed to read $filepath"
        }
    }
    if($Backup -eq $False){
        Write-LogDebug "Get-NcCifsServer -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
        $SecondaryCifsServerInfos = Get-NcCifsServer -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsServer failed [$ErrorVar]" }

        if ( $PrimaryCifsServerInfos -eq $null ) {
            Write-Log "[$workOn] No CIFS Server in Vserver [$myPrimaryVserver]:[$myPrimaryController]"
            Write-LogDebug "create_update_CIFS_shares_dr[$myPrimaryVserver]: end"
            return $True
        }

        if ( $SecondaryCifsServerInfos -eq $null ) {
            Write-LogError "ERROR: no CIFS Server in Vserver DR : [$mySecondaryVserver] [$mySecondaryController]" 
            Write-LogError "ERROR: please run ConfigureDR to create CIFS server manually" 
            return $False
        }
    }
    if($Backup -eq $False){
        # NetBiosName ONTAP 8.3
        Write-LogDebug "Check Netbios name"
        $PrimaryNetbiosAliases = $PrimaryCifsServerInfos.NetbiosAliases
        $SecondaryNetbiosAliases = $SecondaryCifsServerInfos.NetbiosAliases
        $SecondaryDomain=$SecondaryCifsServerInfos.Domain
        $ADcred=get_local_cred($SecondaryDomain)
        foreach ( $NetBiosAliase in ( $PrimaryNetbiosAliases | Skip-Null  )  ) { $str1 = $str1 + $NetBiosAliase }
        foreach ( $NetBiosAliase in ( $SecondaryNetbiosAliases | Skip-Null ) ) { $str2 = $str2 + $NetBiosAliase }
        if ( $str1 -ne $str2 ) {
            foreach ( $NetBiosAliase in ( $SecondaryNetbiosAliases | Skip-Null ) ) { 
                Write-LogDebug "Set-NcCifsServer -VserverContext $mySecondaryVserver -Domain $SecondaryDomain -AdminCredential $ADcred -Controller $mySecondaryController -RemoveNetbiosAlias $NetBiosAliase"
                $out = Set-NcCifsServer -VserverContext $mySecondaryVserver -Domain $SecondaryDomain -AdminCredential $ADcred -Controller $mySecondaryController -RemoveNetbiosAlias $NetBiosAliase  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsServer failed [$ErrorVar]" }
            }
            foreach ( $NetBiosAliase in ( $PrimaryNetbiosAliases | Skip-Null ) ) {
                Write-Log "[$mySecondaryVserver] Change NetBiosAlias to [$NetBiosAliase]"
                Write-LogDebug "Set-NcCifsServer -VserverContext $mySecondaryVserver -Domain $SecondaryDomain -AdminCredential $ADcred -Controller $mySecondaryController -AddNetbiosAlias $NetBiosAliase"
                $out = Set-NcCifsServer -VserverContext $mySecondaryVserver -Domain $SecondaryDomain -AdminCredential $ADcred -Controller $mySecondaryController -AddNetbiosAlias $NetBiosAliase  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsServer failed [$ErrorVar]" }
            }
        }
    }

    Write-LogDebug "Check CIFS Home Search Directory"
    $ReCreateCifsHomeSearch=$false
    if($Restore -eq $False){
        $CifsHomeSearchList=Get-NcCifsHomeDirectorySearchPath -Controller $myPrimaryController -VserverContext $myPrimaryVserver  -ErrorVariable ErrorVar 
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsHomeDirectorySearchPath failed [$ErrorVar]" }
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcCifsHomeDirectorySearchPath.json")){
            $CifsHomeSearchList=Get-Content $($Global:JsonPath+"Get-NcCifsHomeDirectorySearchPath.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcCifsHomeDirectorySearchPath.json")
            Throw "ERROR: failed to read $filepath"
        }
    }
    if($Backup -eq $True){
        $CifsHomeSearchList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcCifsHomeDirectorySearchPath.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcCifsHomeDirectorySearchPath.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcCifsHomeDirectorySearchPath.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcCifsHomeDirectorySearchPath.json")"
            $Return=$False
        }
    }
    if($Backup -eq $False){
        foreach ( $CifsHomeSearch in ( $CifsHomeSearchList | Skip-Null ) ){
            $myCifsHomeSearch = $CifsHomeSearch.path
            $CheckCifsHomeSearch=Get-NcCifsHomeDirectorySearchPath -Controller $mySecondaryController -VserverContext $mySecondaryVserver -Path $myCifsHomeSearch  -ErrorVariable ErrorVar
            if ( $CheckCifsHomeSearch -eq $null ) { $ReCreateCifsHomeSearch=$true }
        }
        if ( $ReCreateCifsHomeSearch -eq $true )  {
            # Remove All Cifs Home Search Dir
            $CifsHomeSearchList=Get-NcCifsHomeDirectorySearchPath -Controller $mySecondaryController -VserverContext $mySecondaryVserver  -ErrorVariable ErrorVar
            foreach ( $CifsHomeSearch in ( $CifsHomeSearchList | Skip-Null ) ) {
                $myCifsHomeSearch = $CifsHomeSearch.path
                $out=Remove-NcCifsHomeDirectorySearchPath -Controller $mySecondaryController -VserverContext $mySecondaryVserver -Path $myCifsHomeSearch  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Add-NcCifsHomeDirectorySearchPath failed [$myCifsHomeSearch] [$ErrorVar]" }
            }
            # Recreate All Cifs Home Search Dir
            if($Restore -eq $True){
                $CifsHomeSearchList=Get-Content $($Global:JsonPath+"Get-NcCifsHomeDirectorySearchPath.json") | ConvertFrom-Json
            }else{
                $CifsHomeSearchList=Get-NcCifsHomeDirectorySearchPath -Controller $myPrimaryController -VserverContext $myPrimaryVserver  -ErrorVariable ErrorVar 
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsHomeDirectorySearchPath failed [$ErrorVar]" }
            }
            foreach ( $CifsHomeSearch in ( $CifsHomeSearchList | Skip-Null ) ) {
                $myCifsHomeSearch = $CifsHomeSearch.path
                $CheckCifsHomeSearch=Get-NcCifsHomeDirectorySearchPath -Controller $mySecondaryController -VserverContext $mySecondaryVserver -Path $myCifsHomeSearch  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsHomeDirectorySearchPath failed [$ErrorVar]" }
                if ( $CheckCifsHomeSearch -eq $null ) {
                    $out=Add-NcCifsHomeDirectorySearchPath -Controller $mySecondaryController -VserverContext $mySecondaryVserver -Path $myCifsHomeSearch  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Add-NcCifsHomeDirectorySearchPath failed [$myCifsHomeSearch] [$ErrorVar]" }
                }
            }
        }
    }
    Write-LogDebug "Check CIFS shares"
    if($Restore -eq $False){
        Write-LogDebug "Get-NcCifsShare -VserverContext $myPrimaryVserver -Controller $myPrimaryController"
        $SharesListSource=Get-NcCifsShare -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
        Write-LogDebug "Get-NcCifsShareAcl -VserverContext $myPrimaryVserver -Controller $myPrimaryController"
        $PrimaryAllAclList=Get-NcCifsShareAcl -VserverContext $myPrimaryVserver -Controller $myPrimaryController -ErrorVariable ErroVar
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcCifsShare.json")){
            $SharesListSource=Get-Content $($Global:JsonPath+"Get-NcCifsShare.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcCifsShare.json")
            Throw "ERROR: failed to read $filepath"
        }
        if(Test-Path $($Global:JsonPath+"Get-NcCifsShareAcl.json")){
            $PrimaryAllAclList=Get-Content $($Global:JsonPath+"Get-NcCifsShareAcl.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcCifsShareAcl.json")
            Throw "ERROR: failed to read $filepath"
        }
    }
    if($Backup -eq $True){
        $SharesListSource | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcCifsShare.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcCifsShare.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcCifsShare.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcCifsShare.json")"
            $Return=$False
        }
        $PrimaryAllAclList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcCifsShareAcl.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcCifsShareAcl.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcCifsShareAcl.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcCifsShareAcl.json")"
            $Return=$False
        }
    }
    if($Backup -eq $False){
        $SharesListDest=Get-NcCifsShare -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar 
        if($SharesListSource -ne $null -and $SharesListDest -ne $null){
            Write-LogDebug "Check CIFS shares list"
            $diff=Compare-Object -ReferenceObject $SharesListSource -DifferenceObject $SharesListDest `
            -Property Acl,AttributeCacheTtl,Comment,DirUmask,FileUmask,ForceGroupForCreate,MaxConnectionPerShare,OfflineFilesMode,Path,ShareName,ShareProperties,SymlinkProperties,Volume,VscanFileopProfile `
            -SyncWindow 20000 -CaseSensitive -PassThru | Sort-Object -Property SideIndicator -Descending
            if($diff -ne $null){Write-LogDebug "Check CIFS shares differences [$diff]"}
            foreach($sharediff in $diff){
                $secshare=$SharesListDest | Where-Object {$_.ShareName -eq $sharediff.ShareName}
                if($sharediff.SideIndicator -eq "=>"){
                    # delete share on dest only if not in c$,admin$,ipc$
                    $sharename=$sharediff.ShareName
                    if($sharename -notin @("c$","admin$","ipc$")){
                        if($DebugLevel){Write-LogDebug "Remove Share [$sharename]"}
                        $ret=Remove-NcCifsShare -Name $sharename -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Confirm:$False -ErrorVariable ErrorVar
                        if($? -ne $true){$Return=$False;Write-Error "ERROR: Failed to remove reason [$ErrorVar]"}
                    }
                }else{
                    # modif share on dest only if in c$,admin$,ipc$
                    # or create if else
                    $PrimaryShareName=$sharediff.ShareName
                    Write-LogDebug "Working on share [$PrimaryShareName]"
                    $PrimaryAclList=$sharediff.Acl
                    $PrimaryAttributeCacheTtl=$sharediff.AttributeCacheTtl
                    $PrimaryComment=$sharediff.Comment 
                    $PrimaryDirUmask=$sharediff.DirUmask 
                    $PrimaryFileUmask=$sharediff.FileUmask
                    $PrimaryOfflineFilesMode=$sharediff.OfflineFilesMode
                    $PrimaryPath=$sharediff.Path
                    $PrimarySharePropertiesList=$sharediff.ShareProperties | Sort-Object
                    $PrimarySymlinkPropertiesList=$sharediff.SymlinkProperties | Sort-Object
                    $PrimaryVolume=$sharediff.Volume
                    $PrimaryVscanFileopProfile=$sharediff.VscanFileopProfile
                    $PrimaryMaxConnectionsPerShare=$sharediff.MaxConnectionsPerShare
                    $PrimaryForceGroupForCreate=$sharediff.ForceGroupForCreate
                    if($PrimaryDirUmask.count -eq 0){$PrimaryDirUmask=000}
                    if($PrimaryFileUmask.count -eq 0){$PrimaryFileUmask=022}
                    if($PrimarySharePropertiesList -eq $null){$PrimarySharePropertiesList=''}
                    if($PrimarySymlinkPropertiesList -eq $null){$PrimarySymlinkPropertiesList=''}
                    if($PrimaryComment -eq $null){$PrimaryComment=''}
                    if($PrimaryForceGroupForCreate -eq $null){$PrimaryForceGroupForCreate=''}
                    if($PrimaryAttributeCacheTtl -eq $null){$PrimaryAttributeCacheTtl=10}
                    if($PrimaryShareName -notin @("c$","admin$","ipc$")){
                        Write-Log "[$workOn] Create share [$PrimaryShareName]"
                        if($DebugLevel){Write-LogDebug "Add-NcCifsShare -Name  $PrimaryShareName -Path $PrimaryPath -DisablePathValidation `
                        -ShareProperties $PrimarySharePropertiesList -SymlinkProperties $PrimarySymlinkPropertiesList -Comment $PrimaryComment `
                        -OfflineFilesMode $PrimaryOfflineFilesMode -AttributeCacheTtl $PrimaryAttributeCacheTtl -VscanProfile $PrimaryVscanFileopProfile `
                        -MaxConnectionsPerShare $PrimaryMaxConnectionsPerShare -ForceGroupForCreate $PrimaryForceGroupForCreate `
                        -Vservercontext $mySecondaryVserver -Controller $mySecondaryController"}
                        $out = Add-NcCifsShare -Name  $PrimaryShareName -Path $PrimaryPath -DisablePathValidation `
                        -ShareProperties $PrimarySharePropertiesList -SymlinkProperties $PrimarySymlinkPropertiesList `
                        -Comment $PrimaryComment -OfflineFilesMode $PrimaryOfflineFilesMode -AttributeCacheTtl $PrimaryAttributeCacheTtl `
                        -VscanProfile $PrimaryVscanFileopProfile -MaxConnectionsPerShare $PrimaryMaxConnectionsPerShare `
                        -ForceGroupForCreate $PrimaryForceGroupForCreate -Vservercontext $mySecondaryVserver `
                        -Controller $mySecondaryController  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; Write-Error "ERROR: Add-NcCifsShare failed [$ErrorVar]" }
                        #$SecondaryShare=Get-NcCifsShare -Name $PrimaryShareName -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar 
                        #if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsShare failed [$ErrorVar]" }
                        $SecondaryAclList=Get-NcCifsShareAcl -Share $PrimaryShareName -VserverContext $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErroVar
                        foreach($acl in $SecondaryAclList){
                            $aclUser=$acl.UserOrGroup
                            $acltype=$acl.UserGroupType
                            if($DebugLevel){Write-LogDebug "Remove-NcCifsShareAcl -Share $PrimaryShareName -UserOrGroup $aclUser -UserGroupType $acltype `
                            -VserverContext $mySecondaryVserver -Controller $mySecondaryController"}
                            $out=Remove-NcCifsShareAcl -Share $PrimaryShareName -UserOrGroup $aclUser -UserGroupType $acltype `
                            -VserverContext $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErroVar -confirm:$False
                            if ( $? -ne $True ) { $Return = $False ; Write-Error "ERROR: Remove-NcCifsShare failed [$ErrorVar]" }
                        }
                        $PrimaryAclList=$PrimaryAllAclList | Where-Object {$_.Share -eq "$PrimaryShareName"}
                        #$PrimaryAclList=Get-NcCifsShareAcl -Share $PrimaryShareName -VserverContext $myPrimaryVserver -Controller $myPrimaryController -ErrorVariable ErroVar
                        foreach($acl in $PrimaryAclList){
                            $aclPermission=$acl.Permission    
                            $aclShare=$acl.Share
                            $aclUnixid=$acl.Unixid
                            $aclUserGroupType=$acl.UserGroupType
                            $aclUserOrGroup=$acl.UserOrGroup
                            $aclWinsid=$acl.Winsid
                            $aclUnixidSpecified=$acl.UnixidSpecified
                            if($aclUnixidSpecified -eq $true)
                            {
$request=@"
<cifs-share-access-control-create>
<permission>$aclPermission</permission>
<return-record>true</return-record>
<share>$aclShare</share>
<user-group-type>$aclUserGroupType</user-group-type>
<user-or-group>$aclUnixid</user-or-group>
</cifs-share-access-control-create>                            
"@
                                if($WinSIDCompatible -eq $True){
                                    if($DebugLevel){Write-LogDebug "Invoke-NcSystemApi -Request $request -VserverContext $mySecondaryVserver -Controller $mySecondaryController"}
                                    $out=Invoke-NcSystemApi -Request $request -VserverContext $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErrorVar
                                    if($? -ne $True){$Return=$False;Write-Error "ERROR: Failed to set acces-control for share [$aclShare] display [$out]"}
                                }else{
                                    if($DebugLevel){Write-LogDebug "Add-NcCifsShareAcl -Share $aclShare  -UserOrGroup $aclUnixid -Permission $aclPermission -UserGroupType  $aclUserGroupType -VserverContext $mySecondaryVserver -Controller $myController"}
                                    $out=Add-NcCifsShareAcl -Share $aclShare  -UserOrGroup $aclUnixid -Permission $aclPermission -UserGroupType  $aclUserGroupType -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Confirm:$False -ErrorVariable ErrorVar
                                    if ( $? -ne $True ) { $Return = $False ; Write-Error "ERROR: Add-NcCifsShareAcl failed [$ErrorVar]" }
                                }
                            }elseif($aclUserGroupType -eq "windows"){
$request=@"
<cifs-share-access-control-create>
<permission>$aclPermission</permission>
<return-record>true</return-record>
<share>$aclShare</share>
<user-group-type>$aclUserGroupType</user-group-type>
<user-or-group>$aclUserOrGroup</user-or-group>
<winsid>$aclWinsid</winsid>
</cifs-share-access-control-create>                            
"@
                                if($WinSIDCompatible -eq $True){
                                    if($DebugLevel){Write-LogDebug "Invoke-NcSystemApi -Request $request -VserverContext $mySecondaryVserver -Controller $mySecondaryController"}
                                    $out=Invoke-NcSystemApi -Request $request -VserverContext $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErrorVar
                                    if($? -ne $True){$Return=$False;Write-Error "ERROR: Failed to set acces-control for share [$aclShare] display [$out]"}
                                }else{
                                    $SecondaryServer=(Get-NcCifsServer -VserverContext $mySecondaryVserver -controller $mySecondaryController).CifsServer
                                    $domain=$aclUserOrGroup.split("\")[0]
                                    $user=$aclUserOrGroup.split("\")[1]
                                    $domain=$domain -replace $PrimaryServer,$SecondaryServer
                                    if($user -ne $null){
                                        $aclUserOrGroup= @($domain,$user) -join "\" 
                                    }else{
                                        $aclUserOrGroup=$domain    
                                    }
                                    if($DebugLevel){Write-LogDebug "Add-NcCifsShareAcl -Share $aclShare  -UserOrGroup $aclUserOrGroup -Permission $aclPermission -UserGroupType $aclUserGroupType -VserverContext $mySecondaryVserver -Controller $myController"}
                                    $out=Add-NcCifsShareAcl -Share $aclShare  -UserOrGroup $aclUserOrGroup -Permission $aclPermission -UserGroupType $aclUserGroupType -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Confirm:$False -ErrorVariable ErrorVar
                                    if ( $? -ne $True ) { $Return = $False ; Write-Error "ERROR: Add-NcCifsShareAcl failed [$ErrorVar]" }
                                }
                            }elseif($aclUserGroupType -match "unix"){
$request=@"
<cifs-share-access-control-create>
<permission>$aclPermission</permission>
<return-record>true</return-record>
<share>$aclShare</share>
<user-group-type>$aclUserGroupType</user-group-type>
<user-or-group>$aclUserOrGroup</user-or-group>
</cifs-share-access-control-create>                            
"@
                                if($WinSIDCompatible -eq $True){
                                    if($DebugLevel){Write-LogDebug "Invoke-NcSystemApi -Request $request -VserverContext $mySecondaryVserver -Controller $mySecondaryController"}
                                    $out=Invoke-NcSystemApi -Request $request -VserverContext $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErrorVar
                                    if($? -ne $True){$Return=$False;Write-Error "ERROR: Failed to set acces-control for share [$aclShare] display [$out]"}
                                }else{
                                    if($DebugLevel){Write-LogDebug "Add-NcCifsShareAcl -Share $aclShare  -UserOrGroup $aclUserOrGroup -Permission $aclPermission -UserGroupType $aclUserGroupType -VserverContext $mySecondaryVserver -Controller $myController"}
                                    $out=Add-NcCifsShareAcl -Share $aclShare  -UserOrGroup $aclUserOrGroup -Permission $aclPermission -UserGroupType $aclUserGroupType -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Confirm:$False -ErrorVariable ErrorVar
                                    if ( $? -ne $True ) { $Return = $False ; Write-Error "ERROR: Add-NcCifsShareAcl failed [$ErrorVar]" }
                                }
                            }
                        } 
                    }else{
                        # modif existing share
                        Write-Log "[$workOn] Modify share [$PrimaryShareName]"
                        if($DebugLevel){Write-LogDebug "Set-NcCifsShare -Name $PrimaryShareName -ShareProperties $PrimarySharePropertiesList `
                        -SymlinkProperties $PrimarySymlinkPropertiesList -FileUmask $PrimaryFileUmask `
                        -DirUmask $PrimaryDirUmask -Comment $PrimaryComment -AttributeCacheTtl $PrimaryAttributeCacheTtl `
                        -OfflineFilesMode $PrimaryOfflineFilesMode -VscanProfile $PrimaryVscanFileopProfile `
                        -MaxConnectionsPerShare $PrimaryMaxConnectionsPerShare -ForceGroupForCreate $PrimaryForceGroupForCreate `
                        -VserverContext $mySecondaryVserver -Controller $mySecondaryController"}
                        $out=Set-NcCifsShare -Name $PrimaryShareName -ShareProperties $PrimarySharePropertiesList `
                        -SymlinkProperties $PrimarySymlinkPropertiesList -FileUmask $PrimaryFileUmask `
                        -DirUmask $PrimaryDirUmask -Comment $PrimaryComment -AttributeCacheTtl $PrimaryAttributeCacheTtl `
                        -OfflineFilesMode $PrimaryOfflineFilesMode -VscanProfile $PrimaryVscanFileopProfile `
                        -MaxConnectionsPerShare $PrimaryMaxConnectionsPerShare -ForceGroupForCreate $PrimaryForceGroupForCreate `
                        -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Confirm:$False -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; Write-Error "ERROR: Set-NcCifsShare failed [$ErrorVar] display [$out]" }
                        if($secshare.Acl -ne $PrimaryAclList){
                            $SecondaryAclList=Get-NcCifsShareAcl -Share $PrimaryShareName -VserverContext $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErroVar
                            foreach($acl in $SecondaryAclList){
                                $aclUser=$acl.UserOrGroup
                                $acltype=$acl.UserGroupType
                                if($DebugLevel){Write-LogDebug "Remove-NcCifsShareAcl -Share $PrimaryShareName -UserOrGroup $aclUser -UserGroupType $acltype `
                                -VserverContext $mySecondaryVserver -Controller $mySecondaryController"}
                                $out=Remove-NcCifsShareAcl -Share $PrimaryShareName -UserOrGroup $aclUser -UserGroupType $acltype `
                                -VserverContext $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErroVar -confirm:$False
                                if ( $? -ne $True ) { $Return = $False ; Write-Error "ERROR: Remove-NcCifsShare failed [$ErrorVar]" }
                            }
                            Write-Log "[$workOn] Modify Acces-Control for share [$PrimaryShareName]"
                            $PrimaryAclList=$PrimaryAllAclList | Where-Object {$_.Share -eq "$PrimaryShareName"}
                            #$PrimaryAclList=Get-NcCifsShareAcl -Share $PrimaryShareName -VserverContext $myPrimaryVserver -Controller $myPrimaryController -ErrorVariable ErroVar
                            foreach($acl in $PrimaryAclList){
                                $aclPermission=$acl.Permission    
                                $aclShare=$acl.Share
                                $aclUnixid=$acl.Unixid
                                $aclUserGroupType=$acl.UserGroupType
                                $aclUserOrGroup=$acl.UserOrGroup
                                $aclWinsid=$acl.Winsid
                                $aclUnixidSpecified=$acl.UnixidSpecified
                                if($aclUnixidSpecified -eq $true)
                                {
$request=@"
<cifs-share-access-control-create>
<permission>$aclPermission</permission>
<return-record>true</return-record>
<share>$aclShare</share>
<user-group-type>$aclUserGroupType</user-group-type>
<user-or-group>$aclUnixid</user-or-group>
</cifs-share-access-control-create>                            
"@
                                    if($WinSIDCompatible -eq $True){
                                        if($DebugLevel){Write-LogDebug "Invoke-NcSystemApi -Request $request -VserverContext $mySecondaryVserver -Controller $mySecondaryController"}
                                        $out=Invoke-NcSystemApi -Request $request -VserverContext $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErrorVar
                                        if($? -ne $True){$Return=$False;Write-Error "ERROR: Failed to set acces-control for share [$aclShare] display [$out]"}
                                    }else{
                                        if($DebugLevel){Write-LogDebug "Add-NcCifsShareAcl -Share $aclShare  -UserOrGroup $aclUnixid -Permission $aclPermission -UserGroupType  $aclUserGroupType -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Confirm:$Fasle"}
                                        $out=Add-NcCifsShareAcl -Share $aclShare  -UserOrGroup $aclUnixid -Permission $aclPermission -UserGroupType  $aclUserGroupType -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Confirm:$False -ErrorVariable ErrorVar
                                        if ( $? -ne $True ) { $Return = $False ; Write-Error "ERROR: Add-NcCifsShareAcl failed [$ErrorVar]" }
                                    }
                                }elseif($aclUserGroupType -eq "windows"){
$request=@"
<cifs-share-access-control-create>
<permission>$aclPermission</permission>
<return-record>true</return-record>
<share>$aclShare</share>
<user-group-type>$aclUserGroupType</user-group-type>
<user-or-group>$aclUserOrGroup</user-or-group>
<winsid>$aclWinsid</winsid>
</cifs-share-access-control-create>                            
"@
                                    #if($aclWinsid -notmatch "S-1-1-0|S-1-5-32"){
                                        if($WinSIDCompatible -eq $True){
                                            if($DebugLevel){Write-LogDebug "Invoke-NcSystemApi -Request $request -VserverContext $mySecondaryVserver -Controller $mySecondaryController"}
                                            $out=Invoke-NcSystemApi -Request $request -VserverContext $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErrorVar
                                            if($? -ne $True){$Return=$False;Write-Error "ERROR: Failed to set acces-control for share [$aclShare] display [$out]"}
                                        }else{
                                            $SecondaryServer=(Get-NcCifsServer -VserverContext $mySecondaryVserver -controller $mySecondaryController).CifsServer
                                            $domain=$aclUserOrGroup.split("\")[0]
                                            $user=$aclUserOrGroup.split("\")[1]
                                            $domain=$domain -replace $PrimaryServer,$SecondaryServer
                                            if($user -ne $null){
                                                $aclUserOrGroup= @($domain,$user) -join "\" 
                                            }else{
                                                $aclUserOrGroup=$domain    
                                            }
                                            if($DebugLevel){Write-LogDebug "Add-NcCifsShareAcl -Share $aclShare  -UserOrGroup $aclUserOrGroup -Permission $aclPermission -UserGroupType  $aclUserGroupType -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Confirm:$Fasle"}
                                            $out=Add-NcCifsShareAcl -Share $aclShare  -UserOrGroup $aclUserOrGroup -Permission $aclPermission -UserGroupType  $aclUserGroupType -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Confirm:$False -ErrorVariable ErrorVar
                                            if ( $? -ne $True ) { $Return = $False ; Write-Error "ERROR: Add-NcCifsShareAcl failed [$ErrorVar]" }
                                        }
                                    #}else{
                                    #    if($DebugLevel){Write-LogDebug "Ignore ACL [$aclUserOrGroup]"}
                                    #}
                                }elseif($aclUserGroupType -match "unix"){
$request=@"
<cifs-share-access-control-create>
<permission>$aclPermission</permission>
<return-record>true</return-record>
<share>$aclShare</share>
<user-group-type>$aclUserGroupType</user-group-type>
<user-or-group>$aclUserOrGroup</user-or-group>
</cifs-share-access-control-create>                            
"@
                                    if($WinSIDCompatible -eq $True){
                                        if($DebugLevel){Write-LogDebug "Invoke-NcSystemApi -Request $request -VserverContext $mySecondaryVserver -Controller $mySecondaryController"}
                                        $out=Invoke-NcSystemApi -Request $request -VserverContext $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErrorVar
                                        if($? -ne $True){$Return=$False;Write-Error "ERROR: Failed to set acces-control for share [$aclShare] display [$out]"}
                                    }else{
                                        if($DebugLevel){Write-LogDebug "Add-NcCifsShareAcl -Share $aclShare  -UserOrGroup $aclUserOrGroup -Permission $aclPermission -UserGroupType $aclUserGroupType -VserverContext $mySecondaryVserver -Controller $myController"}
                                        $out=Add-NcCifsShareAcl -Share $aclShare  -UserOrGroup $aclUserOrGroup -Permission $aclPermission -UserGroupType $aclUserGroupType -VserverContext $mySecondaryVserver -Controller $mySecondaryController -Confirm:$False -ErrorVariable ErrorVar
                                        if ( $? -ne $True ) { $Return = $False ; Write-Error "ERROR: Add-NcCifsShareAcl failed [$ErrorVar]" }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        if($WinSIDCompatible -eq $False){
            if (($ret=set_all_lif -mySecondaryVserver $mySecondaryVserver -myPrimaryVserver $myPrimaryVserver -mySecondaryController $mySecondaryController  -myPrimaryController $myPrimaryController -state down) -ne $True ) {
                    Write-LogError "ERROR: Failed to set all lif up on [$mySecondaryVserver]"
                    clean_and_exit 1
            }
        }
    }
    Write-LogDebug "create_update_CIFS_shares_dr[$myPrimaryVserver]: end"
	return $True
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
Function create_update_ISCSI_dr(
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) {
Try {
	$Return  = $True 
    Write-Log "[$workOn] Check SVM iSCSI configuration"
    Write-LogDebug "create_update_ISCSI_dr[$myPrimaryVserver]: start"
    if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]"}
    if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]"}

    if($Restore -eq $False){
        $PrimaryIscsiService = Get-NcIscsiService -VserverContext  $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcIscsiService failed [$ErrorVar]" }
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcIscsiService.json")){
            $PrimaryIscsiService=Get-Content $($Global:JsonPath+"Get-NcIscsiService.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcIscsiService.json")
            Throw "ERROR: failed to read $filepath"
        }
    }
    if($Backup -eq $True){
        $PrimaryIscsiService | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcIscsiService.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcIscsiService.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcIscsiService.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcIscsiService.json")"
            $Return=$False
        }
    }
	if ( $PrimaryIscsiService -eq $null ) {
		Write-Log "[$workOn] No ISCSI services in vserver [$myPrimaryVserver]"
        Write-LogDebug "create_update_ISCSI_dr: end"
		return $true
	}
    if($Backup -eq $False){
        $SecondaryIscsiService = Get-NcIscsiService -VserverContext  $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcIscsiService failed [$ErrorVar]" }
        if ( $SecondaryIscsiService -eq $null ) {
            Write-Log "[$workOn] Add ISCSI services in vserver [$mySecondaryVserver]"
            $out = Add-NcIscsiService -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar 
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Add-NcIscsiService failed [$ErrorVar]" }
            $out = Disable-NcIscsi -VserverContext  $mySecondaryVserver -Controller  $mySecondaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Disable-NcIscsi failed [$ErrorVar]" }
            $out = Set-NcIscsiNodeName -Name $PrimaryIscsiService.NodeName -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcIscsiNodeName failed [$ErrorVar]" }
        } else {
            if ( ( compare_ISCSI_service -RefIscsiService $PrimaryIscsiService -IscsiService $SecondaryIscsiService ) -eq $True ) {
                Write-Log "[$workOn] Set ISCSI Services Attributes on [$mySecondaryVserver]"
                $out = Disable-NcIscsi -VserverContext  $mySecondaryVserver -Controller  $mySecondaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) {
                    Write-LogError "ERROR: Failed to disable ISCSI services in [$mySecondaryVserver]" 
                    $Return  = $False
                }
                $out = Set-NcIscsiNodeName -Name $PrimaryIscsiService.NodeName -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcIscsiNodeName failed [$ErrorVar]" }
            }
        }
    }
    Write-LogDebug "create_update_ISCSI_dr[$myPrimaryVserver]: end"
	return $Return 
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
Function display_clone_vserver(
    [NetApp.Ontapi.Filer.C.NcController] $myController,
    [DataONTAP.C.Types.Vserver.VserverInfo] $myVserver
){
    $SecondaryRootVolume = $myVserver.RootVolume
    $SecondaryRootVolumeSecurityStyle = $myVserver.RootVolumeSecurityStyle
    $SecondaryLanguage = $myVserver.Language
    $SecondaryAllowedProtocols=$myVserver.AllowedProtocols
    $SecondaryNameMappingSwitch=$myVserver.NameMappingSwitch
    $SecondaryNameServerSwitch=$myVserver.NameServerSwitch
    $SecondaryComment=$myVserver.Comment 
    $SecondaryRootVolumeAggregate=$myVserver.RootVolumeAggregate
    Format-ColorBrackets "Cluster Name           : [$myController]" -ForceColor "darkgreen"
    Format-ColorBrackets "Vserver Name           : [$myVserver]" -ForceColor "darkgreen"
    Format-ColorBrackets "Vserver Root Volume    : [$SecondaryRootVolume]" -ForceColor "darkgreen"
    Format-ColorBrackets "Vserver Root Security  : [$SecondaryRootVolumeSecurityStyle]" -ForceColor "darkgreen"
    Format-ColorBrackets "Vserver Language       : [$SecondaryLanguage]" -ForceColor "darkgreen"
    Format-ColorBrackets "Vserver Protocols      : [$SecondaryAllowedProtocols]" -ForceColor "darkgreen"
    $SecondaryNameServiceList= Get-NcNameServiceNsSwitch -Controller $myController -Vserver $myVserver  -ErrorVariable ErrorVar 
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNameService failed [$ErrorVar]" }
    foreach ( $SecondaryNameService in ( $SecondaryNameServiceList ) | skip-Null ) {
        $NameServiceDatabase = $SecondaryNameService.NameServiceDatabase
        $NameServiceSources = $SecondaryNameService.NameServiceSources
        Format-ColorBrackets "Vserver NsSwitch       : [$NameServiceDatabase] [$NameServiceSources]" -ForceColor "darkgreen"
    }
    $SecondaryInterfaceList = Get-NcNetInterface -Role DATA -VserverContext $myVserver -Controller $myController  -ErrorVariable ErrorVar 
    foreach ( $SecondaryInterface in ( $SecondaryInterfaceList | Skip-Null ) ) {
        $SecondaryInterfaceName=$SecondaryInterface.InterfaceName
        $SecondaryAddress=$SecondaryInterface.Address
        $SecondaryNetmask=$SecondaryInterface.Netmask
        $SecondaryCurrentPort=$SecondaryInterface.CurrentPort
        $SecondaryDataProtocols=$SecondaryInterface.DataProtocols
        $SecondaryDnsDomainName=$SecondaryInterface.DnsDomainName
        $SecondaryRole=$SecondaryInterface.Role
        $SecondaryStatus=$SecondaryInterface.OpStatus
        $SecondaryCurrentNode=$SecondaryInterface.CurrentNode
        $SecondaryCurrentPort=$SecondaryInterface.CurrentPort
        $SecondaryRoutingGroupName=$SecondaryInterface.RoutingGroupName
        if($SecondaryRoutingGroupName.length -gt 1){
            $SecondaryDefaultRoute=Get-NcNetRoutingGroupRoute -RoutingGroup $SecondaryRoutingGroupName -Destination '0.0.0.0/0' -Vserver $myVserver -Controller $myController  -ErrorVariable ErrorVar
            $SecondaryGateway=$SecondaryDefaultRoute.GatewayAddress
        }else{
            $DefaultRoute=Get-NcNetRoute -Destination "0.0.0.0/0" -Vserver $myVserver -Controller $myController  -ErrorVariable ErrorVar
            $SecondaryGateway=$DefaultRoute.Gateway    
        }
        $LIF = '['  + $SecondaryStatus + '] [' + $SecondaryInterfaceName + '] [' + $SecondaryAddress + '] [' + $SecondaryNetMask + '] [' + $SecondaryGateway + '] [' + $SecondaryCurrentNode + '] [' + $SecondaryCurrentPort + ']' 
        Format-ColorBrackets "Logical Interface      : $LIF" -ForceColor "darkgreen"
    }
    # Verify if NFS service is Running if yes the stop it
    $NfsService = Get-NcNfsService -VserverContext  $myVserver -Controller $myController  -ErrorVariable ErrorVar
    if ( $NfsService -eq $null ) {
        Format-ColorBrackets "NFS Services           : [no]" -ForceColor "darkgreen"
    } else {
        if ( $NfsService.GeneralAccess -eq $True ) {
            Format-ColorBrackets "NFS Services           : [up]" -ForceColor "darkgreen"
        } else {
            Format-ColorBrackets "NFS Services           : [down]" -ForceColor "darkgreen"
        }
    }
    # Verify if CIFS Service is Running if yes stop it
    $CifService = Get-NcCifsServer  -VserverContext  $myVserver -Controller $myController  -ErrorVariable ErrorVar
    if ( $CifService -eq $null ) {
        Format-ColorBrackets "CIFS Services          : [no]" -ForceColor "darkgreen"
    } else {
        if ( $CifService.AdministrativeStatus -eq 'up' ) {
            Format-ColorBrackets "CIFS Services          : [up]" -ForceColor "darkgreen"
        } else {
            Format-ColorBrackets "CIFS Services          : [down]" -ForceColor "darkgreen"
        }
    }
    # Verify if ISCSI service is Running if yes the stop it
    $IscsiService = Get-NcIscsiService -VserverContext  $myVserver -Controller $myController  -ErrorVariable ErrorVar
    if ( $IscsiService -eq $null ) {
        Format-ColorBrackets "ISCSI Services         : [no]" -ForceColor "darkgreen"
    } else {
        if ( $IscsiService.IsAvailable -eq $True ) {
            Format-ColorBrackets "ISCSI Services         : [up]" -ForceColor "darkgreen"
        } else {
            Format-ColorBrackets "ISCSI Services         : [down]" -ForceColor "darkgreen"
        }
    }
    Write-Host ""    
}

#############################################################################################
Function show_vserver_dr (
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [switch] $MSID) 
{
    Try 
    {
        if ( ( $myPrimaryController -eq $null ) -and ( $mySecondaryController -eq $null ) ) { return }
        if ( $myPrimaryController -ne $null ) 
        {
            $myPrimaryCluster = (Get-NcCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar).ClusterName
            $PrimaryVserver = Get-NcVserver -Controller $myPrimaryController -Name $myPrimaryVserver  -ErrorVariable ErrorVar  
        }
        if ( $mySecondaryController -ne $null ) 
        {
            $mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar).ClusterName
            $SecondaryVserver = Get-NcVserver -Controller $mySecondaryController -Name $mySecondaryVserver  -ErrorVariable ErrorVar 
        }
        if ( $PrimaryVserver -eq $null ) 
        {
            Write-Host "ERROR: $myPrimaryVserver not found" -F red
        } 
        else  
        {
            if( (Is_SelectVolumedb $myPrimaryController $mySecondaryController $myPrimaryVserver $mySecondaryVserver) -eq $True ){
                $SelectVolumeConf=$True    
            }else{
                $SelectVolumeConf=$False
            }
            $PrimaryRootVolume = $PrimaryVserver.RootVolume
            $PrimaryRootVolumeSecurityStyle = $PrimaryVserver.RootVolumeSecurityStyle
            $PrimaryLanguage = $PrimaryVserver.Language
            $PrimaryAllowedProtocols=$PrimaryVserver.AllowedProtocols
            $PrimaryNameMappingSwitch=$PrimaryVserver.NameMappingSwitch
            $PrimaryNameServerSwitch=$PrimaryVserver.NameServerSwitch
            $PrimaryComment=$PrimaryVserver.Comment
            $PrimaryRootVolumeAggregate=$PrimaryVserver.RootVolumeAggregate
            Write-Host "PRIMARY SVM      :"
            Write-Host "------------------"
            Format-ColorBrackets "Cluster Name           : [$myPrimaryController]"
            Format-ColorBrackets "Vserver Name           : [$PrimaryVserver]"
            Format-ColorBrackets "Vserver Root Volume    : [$PrimaryRootVolume]"
            Format-ColorBrackets "Vserver Root Security  : [$PrimaryRootVolumeSecurityStyle]"
            Format-ColorBrackets "Vserver Language       : [$PrimaryLanguage]"
            Format-ColorBrackets "Vserver Protocols      : [$PrimaryAllowedProtocols]"
            $PrimaryNameServiceList= Get-NcNameServiceNsSwitch -Controller $myPrimaryController -Vserver $myPrimaryVserver  -ErrorVariable ErrorVar 
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNameService failed [$ErrorVar]" }
            foreach ( $PrimaryNameService in ( $PrimaryNameServiceList ) | skip-Null ) {
                $NameServiceDatabase = $PrimaryNameService.NameServiceDatabase
                $NameServiceSources = $PrimaryNameService.NameServiceSources
                Format-ColorBrackets "Vserver NsSwitch       : [$NameServiceDatabase] [$NameServiceSources]"
            }
            $PrimaryInterfaceList = Get-NcNetInterface -Role DATA -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar 
            foreach ( $PrimaryInterface in ( $PrimaryInterfaceList  | Skip-Null ) ) {
                $PrimaryInterfaceName=$PrimaryInterface.InterfaceName
                $PrimaryAddress=$PrimaryInterface.Address
                $PrimaryNetmask=$PrimaryInterface.Netmask
                $PrimaryCurrentPort=$PrimaryInterface.CurrentPort
                $PrimaryDataProtocols=$PrimaryInterface.DataProtocols
                $PrimaryDnsDomainName=$PrimaryInterface.DnsDomainName
                $PrimaryRole=$PrimaryInterface.Role
                $PrimaryStatus=$PrimaryInterface.OpStatus
                $PrimaryCurrentNode=$PrimaryInterface.CurrentNode
                $PrimaryCurrentPort=$PrimaryInterface.CurrentPort
                $PrimaryRoutingGroupName=$PrimaryInterface.RoutingGroupName
                if($PrimaryRoutingGroupName.length -gt 1){
                    $PrimaryDefaultRoute=Get-NcNetRoutingGroupRoute -RoutingGroup $PrimaryRoutingGroupName -Destination '0.0.0.0/0' -Vserver $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
                    $PrimaryGateway=$PrimaryDefaultRoute.GatewayAddress
                }else{
                    $DefaultRoute=Get-NcNetRoute -Destination "0.0.0.0/0" -Vserver $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
                    $PrimaryGateway=$DefaultRoute.Gateway
                }
                $LIF = '['  + $PrimaryStatus + '] [' + $PrimaryInterfaceName + '] [' + $PrimaryAddress + '] [' + $PrimaryNetMask + '] [' + $PrimaryGateway + '] [' + $PrimaryCurrentNode + '] [' + $PrimaryCurrentPort + ']'
                Format-ColorBrackets "Logical Interface      : $LIF"
            }

            # Verify if NFS service is Running if yes the stop it
            $NfsService = Get-NcNfsService -VserverContext  $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
            if ( $NfsService -eq $null )
            {
                Format-ColorBrackets "NFS Services           : [no]"
            } 
            else 
            {
                if ( $NfsService.GeneralAccess -eq $True ) 
                {
                    Format-ColorBrackets "NFS Services           : [up]"
                } 
                else 
                {
                    Format-ColorBrackets "NFS Services           : [down]"
                }
            }
            # Verify if CIFS Service is Running if yes stop it
            $CifService = Get-NcCifsServer  -VserverContext  $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
            if ( $CifService -eq $null ) 
            {
                Format-ColorBrackets "CIFS Services          : [no]"
            } 
            else 
            {
                if ( $CifService.AdministrativeStatus -eq 'up' ) 
                {
                    Format-ColorBrackets "CIFS Services          : [up]"
                } 
                else 
                {
                    Format-ColorBrackets "CIFS Services          : [down]"
                }
            }
            # Verify if ISCSI service is Running if yes the stop it
            $IscsiService = Get-NcIscsiService -VserverContext  $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
            if ( $IscsiService -eq $null ) 
            {
                Format-ColorBrackets "ISCSI Services         : [no]"
            } 
            else 
            {
                if ( $IscsiService.IsAvailable -eq $True ) 
                {
                    Format-ColorBrackets "ISCSI Services         : [up]"
                } 
                else 
                {
                    Format-ColorBrackets "ISCSI Services         : [down]"
                }
            }
            Write-Host ""
        }

        if ( $SecondaryVserver -eq $null ) 
        {
            Write-Host "ERROR: vserverDR $mySecondaryVserver does not exist"  -F red
            clean_and_exit 1
        } 
        else 
        {
            $SecondaryRootVolume = $SecondaryVserver.RootVolume
            $SecondaryRootVolumeSecurityStyle = $SecondaryVserver.RootVolumeSecurityStyle
            $SecondaryLanguage = $SecondaryVserver.Language
            $SecondaryAllowedProtocols=$SecondaryVserver.AllowedProtocols
            $SecondaryNameMappingSwitch=$SecondaryVserver.NameMappingSwitch
            $SecondaryNameServerSwitch=$SecondaryVserver.NameServerSwitch
            $SecondaryComment=$SecondaryVserver.Comment 
            $SecondaryRootVolumeAggregate=$SecondaryVserver.RootVolumeAggregate
            Write-Host "SECONDARY SVM (DR)   :"
            Write-Host "----------------------"
            Format-ColorBrackets "Cluster Name           : [$mySecondaryController]"
            Format-ColorBrackets "Vserver Name           : [$SecondaryVserver]"
            Format-ColorBrackets "Vserver Root Volume    : [$SecondaryRootVolume]"
            Format-ColorBrackets "Vserver Root Security  : [$SecondaryRootVolumeSecurityStyle]"
            Format-ColorBrackets "Vserver Language       : [$SecondaryLanguage]"
            Format-ColorBrackets "Vserver Protocols      : [$SecondaryAllowedProtocols]"
            $SecondaryNameServiceList= Get-NcNameServiceNsSwitch -Controller $mySecondaryController -Vserver $mySecondaryVserver  -ErrorVariable ErrorVar 
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNameService failed [$ErrorVar]" }
            foreach ( $SecondaryNameService in ( $SecondaryNameServiceList ) | skip-Null ) {
                $NameServiceDatabase = $SecondaryNameService.NameServiceDatabase
                $NameServiceSources = $SecondaryNameService.NameServiceSources
                Format-ColorBrackets "Vserver NsSwitch       : [$NameServiceDatabase] [$NameServiceSources]"
            }
            $SecondaryInterfaceList = Get-NcNetInterface -Role DATA -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar 
            foreach ( $SecondaryInterface in ( $SecondaryInterfaceList | Skip-Null ) ) {
                $SecondaryInterfaceName=$SecondaryInterface.InterfaceName
                $SecondaryAddress=$SecondaryInterface.Address
                $SecondaryNetmask=$SecondaryInterface.Netmask
                $SecondaryCurrentPort=$SecondaryInterface.CurrentPort
                $SecondaryDataProtocols=$SecondaryInterface.DataProtocols
                $SecondaryDnsDomainName=$SecondaryInterface.DnsDomainName
                $SecondaryRole=$SecondaryInterface.Role
                $SecondaryStatus=$SecondaryInterface.OpStatus
                $SecondaryCurrentNode=$SecondaryInterface.CurrentNode
                $SecondaryCurrentPort=$SecondaryInterface.CurrentPort
                $SecondaryRoutingGroupName=$SecondaryInterface.RoutingGroupName
                if($SecondaryRoutingGroupName.length -gt 1){
                    $SecondaryDefaultRoute=Get-NcNetRoutingGroupRoute -RoutingGroup $SecondaryRoutingGroupName -Destination '0.0.0.0/0' -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    $SecondaryGateway=$SecondaryDefaultRoute.GatewayAddress
                }else{
                    $DefaultRoute=Get-NcNetRoute -Destination "0.0.0.0/0" -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
                    $SecondaryGateway=$DefaultRoute.Gateway    
                }
                $LIF = '['  + $SecondaryStatus + '] [' + $SecondaryInterfaceName + '] [' + $SecondaryAddress + '] [' + $SecondaryNetMask + '] [' + $SecondaryGateway + '] [' + $SecondaryCurrentNode + '] [' + $SecondaryCurrentPort + ']' 
                Format-ColorBrackets "Logical Interface      : $LIF"
            }
            # Verify if NFS service is Running if yes the stop it
            $NfsService = Get-NcNfsService -VserverContext  $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
            if ( $NfsService -eq $null ) {
                Format-ColorBrackets "NFS Services           : [no]"
            } else {
                if ( $NfsService.GeneralAccess -eq $True ) {
                    Format-ColorBrackets "NFS Services           : [up]"
                } else {
                    Format-ColorBrackets "NFS Services           : [down]"
                }
            }
            # Verify if CIFS Service is Running if yes stop it
            $CifService = Get-NcCifsServer  -VserverContext  $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
            if ( $CifService -eq $null ) {
                Format-ColorBrackets "CIFS Services          : [no]"
            } else {
                if ( $CifService.AdministrativeStatus -eq 'up' ) {
                    Format-ColorBrackets "CIFS Services          : [up]"
                } else {
                    Format-ColorBrackets "CIFS Services          : [down]"
                }
            }
            # Verify if ISCSI service is Running if yes the stop it
            $IscsiService = Get-NcIscsiService -VserverContext  $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
            if ( $IscsiService -eq $null ) {
                Format-ColorBrackets "ISCSI Services         : [no]"
            } else {
                if ( $IscsiService.IsAvailable -eq $True ) {
                    Format-ColorBrackets "ISCSI Services         : [up]"
                } else {
                    Format-ColorBrackets "ISCSI Services         : [down]"
                }
            }
            Write-Host ""
        }
        Write-Host "VOLUME LIST : "
        Write-Host "--------------"
        if($SelectVolumeConf){
            Write-Host "Warning : This configuration does not replicate all volumes (SelectVolume mode)" -F DarkYellow
        }
        if ( $PrimaryVserver -ne $null ) 
        {
            if($Global:SelectVolume -eq $True)
            {
                $Selected=get_volumes_from_selectvolumedb $myPrimaryController $myPrimaryVserver
                if($Selected.state -ne $True)
                {
                    Write-Log "Failed to get Selected Volume from DB, check selectvolume.db file inside $Global:SVMTOOL_DB"
                    Write-logDebug "check_update_voldr: end with error"
                    return $False  
                }else{
                    $VolList=$Selected.volumes
                    Write-LogDebug "Get-NcVol -Name $VolList -Vserver $myPrimaryVserver -Controller $myPrimaryController"
                    $PrimaryVolList=Get-NcVol -Name $VolList -Vserver $myPrimaryVserver -Controller $myPrimaryController -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
                }    
            }else{
                Write-LogDebug "Get-NcVol -Vserver $myPrimaryVserver -Controller $myPrimaryController"
                $PrimaryVolList = Get-NcVol -Controller $myPrimaryController -Vserver $myPrimaryVserver -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }  
            }
            foreach ($PrimaryVol in ( $PrimaryVolList | Skip-Null | ? { $_.VolumeStateAttributes.IsVserverRoot -ne $True  } ) ) {
                Write-LogDebug "show_vserver_dr: PrimaryVol [$PrimaryVol]"
                $PrimaryVolName=$PrimaryVol.Name
                $PrimaryVolStyle=$PrimaryVol.VolumeSecurityAttributes.Style
                $PrimaryVolExportPolicy=$PrimaryVol.VolumeExportAttributes.Policy
                $PrimaryVolType=$PrimaryVol.VolumeIdAttributes.Type
                $PrimaryVolLang=$PrimaryVol.VolumeLanguageAttributes.LanguageCode
                $PrimaryVolSize=$PrimaryVol.VolumeSpaceAttributes.Size
                $PrimaryVolIsSis=$PrimaryVol.VolumeSisAttributes.IsSisVolume
                $PrimaryVolSpaceGuarantee=$PrimaryVol.VolumeSpaceAttributes.SpaceGuarantee
                $PrimaryVolState=$PrimaryVol.State
                $PrimaryVolJunctionPath=$PrimaryVol.VolumeIdAttributes.JunctionPath
                $PrimaryVolIsInfiniteVolume=$PrimaryVol.IsInfiniteVolume
                $PrimaryVolIsVserverRoot=$PrimaryVol.VolumeStateAttributes.IsVserverRoot
                $PrimaryVolMSID=$PrimaryVol.VolumeIdAttributes.Msid
                if ( $SecondaryVserver -eq $null ) {
                    $PrimaryVolAttr="${PrimaryVolName}:${PrimaryVolStyle}:${PrimaryVolLang}:${PrimaryVolExportPolicy}:${PrimaryVolJunctionPath}"
                    Format-ColorBrackets "Primary:   [$PrimaryVolAttr]"
                    Write-Host "Secondary: [$SecondaryVolAttr]`n" -F red
                } 
                else  
                {
                    $SecondaryVol = Get-NcVol -Controller $mySecondaryController -Vserver $mySecondaryVserver -Volume $PrimaryVolName  -ErrorVariable ErrorVar
                    $SecondaryVolName=$SecondaryVol.Name
                    $SecondaryVolStyle=$SecondaryVol.VolumeSecurityAttributes.Style
                    $SecondaryVolExportPolicy=$SecondaryVol.VolumeExportAttributes.Policy
                    $SecondaryVolLang=$SecondaryVol.VolumeLanguageAttributes.LanguageCode
                    $SecondaryVolSize=$SecondaryVol.VolumeSpaceAttributes.Size
                    $SecondaryVolIsSis=$SecondaryVol.VolumeSisAttributes.IsSisVolume
                    $SecondaryVolSpaceGuarantee=$SecondaryVol.VolumeSpaceAttributes.SpaceGuarantee
                    $SecondaryVolState=$SecondaryVol.State
                    $SecondaryVolType=$SecondaryVol.VolumeIdAttributes.Type
                    $SecondaryVolJunctionPath=$SecondaryVol.VolumeIdAttributes.JunctionPath
                    $SecondaryVolIsInfiniteVolume=$SecondaryVol.IsInfiniteVolume
                    $SecondaryVolIsVserverRoot=$SecondaryVol.VolumeStateAttributes.IsVserverRoot
                    $SecondaryVolMSID=$SecondaryVol.VolumeIdAttributes.Msid
                    $PrimaryVolAttr="${PrimaryVolName}:${PrimaryVolStyle}:${PrimaryVolLang}:${PrimaryVolExportPolicy}:${PrimaryVolJunctionPath}"
                    $SecondaryVolAttr="${SecondaryVolName}:${SecondaryVolStyle}:${SecondaryVolLang}:${SecondaryVolExportPolicy}:${SecondaryVolJunctionPath}"
                    if($MSID.IsPresent){
                        if ( ($PrimaryVolAttr -eq $SecondaryVolAttr) -and ( $SecondaryVolMSID -eq $PrimaryVolMSID) ) 
                        {
                            Format-ColorBrackets "Primary:   [$PrimaryVolAttr] [$PrimaryVolType] [$PrimaryVolMSID]"
                            Format-ColorBrackets "Secondary: [$SecondaryVolAttr] [$SecondaryVolType] [$SecondaryVolMSID]`n"
                        }
                        else{
                            Format-ColorBrackets "Primary:   [$PrimaryVolAttr] [$PrimaryVolType] [$PrimaryVolMSID]" 
                            Write-Host  "Secondary: [$SecondaryVolAttr] [$SecondaryVolType] [$SecondaryVolMSID]`n" -F yellow
                        }
                    } 
                    elseif ($PrimaryVolAttr -eq $SecondaryVolAttr)
                    {
                        Format-ColorBrackets "Primary:   [$PrimaryVolAttr] [$PrimaryVolType]" 
                        Format-ColorBrackets "Secondary: [$SecondaryVolAttr] [$SecondaryVolType]`n"
                    }else{
                        Format-ColorBrackets "Primary:   [$PrimaryVolAttr] [$PrimaryVolType]" 
                        Write-Host  "Secondary: [$SecondaryVolAttr] [$SecondaryVolType]`n" -F yellow
                    }
                }
            }
        } 
        elseif ( $SecondaryVserver -ne $null ) 
        {
            Write-LogDebug "Get-NcVol -Controller $mySecondaryController -Vserver $mySecondaryVserver"
            $SecondaryVolList = Get-NcVol -Controller $mySecondaryController -Vserver $mySecondaryVserver  -ErrorVariable ErrorVar 
            foreach ($SecondaryVol in ( $SecondaryVolList | Skip-Null | ? { $_.VolumeStateAttributes.IsVserverRoot -ne $True  } ) ) {
                Write-LogDebug "show_vserver_dr: SecondaryVol [$SecondaryVol]"
                $SecondaryVolName=$SecondaryVol.Name
                $SecondaryVolStyle=$SecondaryVol.VolumeSecurityAttributes.Style
                $SecondaryVolExportPolicy=$SecondaryVol.VolumeExportAttributes.Policy
                $SecondaryVolType=$SecondaryVol.VolumeIdAttributes.Type
                $SecondaryVolLang=$SecondaryVol.VolumeLanguageAttributes.LanguageCode
                $SecondaryVolSize=$SecondaryVol.VolumeSpaceAttributes.Size
                $SecondaryVolIsSis=$SecondaryVol.VolumeSisAttributes.IsSisVolume
                $SecondaryVolSpaceGuarantee=$SecondaryVol.VolumeSpaceAttributes.SpaceGuarantee
                $SecondaryVolState=$SecondaryVol.State
                $SecondaryVolJunctionPath=$SecondaryVol.VolumeIdAttributes.JunctionPath
                $SecondaryVolIsInfiniteVolume=$SecondaryVol.IsInfiniteVolume
                $SecondaryVolIsVserverRoot=$SecondaryVol.VolumeStateAttributes.IsVserverRoot
                $SecondaryVolAttr="${SecondaryVolName}:${SecondaryVolStyle}:${SecondaryVolLang}:${SecondaryVolExportPolicy}:${SecondaryVolJunctionPath}"
                Format-ColorBrackets "Secondary:   [$SecondaryVolAttr] [$SecondaryVolType]"
            }
        }  
        else 
        {
            Write-Host "ERROR: No volume found" -F red
        }
        Write-Host ""
        Write-Host "SNAPMIRROR LIST :"
        Write-Host "-----------------"
        if ( $SecondaryVserver -ne $null ) 
        {
            Write-LogDebug "Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
            $relationList = Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
            foreach ( $relation in ( $relationList | Skip-Null ) ) {
                $MirrorState=$relation.MirrorState
                $SourceVolume=$relation.SourceVolume
                $DestinationVolume=$relation.DestinationVolume
                $SourceLocation=$relation.SourceLocation
                $DestinationLocation=$relation.DestinationLocation
                $RelationshipStatus=$relation.RelationshipStatus
                $RelationHealth=$relation.IsHealthy
                $RelationType=$relation.RelationshipType
                $RelationPolicy=$relation.Policy
                if ($RelationType -eq "extended_data_protection") {
                    $Type="XDP"
                }else{
                    $Type="DP"
                }
                $LastTransferEndTimestamp=$relation.LastTransferEndTimestamp
                $LagTime=$relation.LagTime
                $SmSchedule=$relation.Schedule
                $LagTimeDate=(Get-Date).AddSeconds(-$LagTime)
                $tmp_str = ""  
                if ( $Lag ) { $tmp_str = $tmp_str + "[$LagTimeDate]"  }
                if ( $Global:Schedule -eq $True ) { $tmp_str = $tmp_str + "[$SmSchedule]"  }
                if ($RelationHealth -eq $True)
                {
                    $rel=[string]::Format("Status relation {0,-30} {1,-30} {2,-3} {3,-20} {4,-10} {5,-15} {6,-30}",$("["+$SourceLocation+"]"),`
                    $("["+$DestinationLocation+"]"),`
                    $("["+$Type+"]"),`
                    $("["+$RelationPolicy+"]"),`
                    $("["+$RelationshipStatus+"]"),`
                    $("["+$MirrorState+"]"),`
                    $tmp_str)
                    Format-ColorBrackets $rel
                }
                else
                {
                    $rel=[string]::Format("Status relation {0,-30} {1,-30} {2,-3} {3,-20} {4,-10} {5,-15} [Not Healthy] {6,-30}",$("["+$SourceLocation+"]"),`
                    $("["+$DestinationLocation+"]"),`
                    $("["+$Type+"]"),`
                    $("["+$RelationPolicy+"]"),`
                    $("["+$RelationshipStatus+"]"),`
                    $("["+$MirrorState+"]"),`
                    $tmp_str)
                    Write-Host $rel -F red
                }
            }
        }
        Write-Host "`nREVERSE SNAPMIRROR LIST :"
        Write-Host "---------------------------"
        if ( $PrimaryVserver -ne $null ) 
        {
            Write-LogDebug "Get-NcSnapmirror -DestinationCluster $myPrimaryCluster -DestinationVserver $myPrimaryVserver -SourceCluster $mySecondaryCluster -SourceVserver $mySecondaryVserver -VserverContext $myPrimaryVserver -Controller $myPrimaryController"
            $relationList = Get-NcSnapmirror -DestinationCluster $myPrimaryCluster -DestinationVserver $myPrimaryVserver -SourceCluster $mySecondaryCluster -SourceVserver $mySecondaryVserver -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
            foreach ( $relation in ( $relationList | Skip-Null ) ) {
                $MirrorState=$relation.MirrorState
                $SourceVolume=$relation.SourceVolume
                $DestinationVolume=$relation.DestinationVolume
                $SourceLocation=$relation.SourceLocation
                $DestinationLocation=$relation.DestinationLocation
                $RelationshipStatus=$relation.RelationshipStatus
                $RelationType=$relation.RelationshipType
                $RelationPolicy=$relation.Policy
                if($RelationType -eq "extended_data_protection"){
                    $Type="XDP"
                }else{
                    $Type="DP"
                }
                $ReverseRelationHealth=$relation.IsHealthy
                $LastTransferEndTimestamp=$relation.LastTransferEndTimestamp
                $SmSchedule=$relation.Schedule
                $LagTime =$relation.LagTime
                $LagTimeDate=(Get-Date).AddSeconds(-$LagTime)
                $tmp_str = ""  
                if ( $Lag ) { $tmp_str = $tmp_str + "[$LagTimeDate]"  }
                if ( $Schedule ) { $tmp_str = $tmp_str + "[$SmSchedule]"  }
                if ($ReverseRelationHealth -eq $True)
                {
                    $rel=[string]::Format("Status relation {0,-30} {1,-30} {2,-3} {3,-20} {4,-10} {5,-15} {6,-30}",$("["+$SourceLocation+"]"),`
                    $("["+$DestinationLocation+"]"),`
                    $("["+$Type+"]"),`
                    $("["+$RelationPolicy+"]"),`
                    $("["+$RelationshipStatus+"]"),`
                    $("["+$MirrorState+"]"),`
                    $tmp_str)
                    Format-ColorBrackets $rel
                }
                else
                {
                    $rel=[string]::Format("Status relation {0,-30} {1,-30} {2,-3} {3,-20} {4,-10} {5,-15} [Not Healthy] {6,-30}",$("["+$SourceLocation+"]"),`
                    $("["+$DestinationLocation+"]"),`
                    $("["+$Type+"]"),`
                    $("["+$RelationPolicy+"]"),`
                    $("["+$RelationshipStatus+"]"),`
                    $("["+$MirrorState+"]"),`
                    $tmp_str)
                    Write-Host $rel -F red
                }
            }
        }
        # search for cloned vserver and display them
        Write-Host "`nCLONED SVM         LIST :"
        Write-Host "---------------------------"
        Write-LogDebug "search for cloned vserver"
        if ( ( $CloneVserverList=get_vserver_clone -DestinationVserver ($SecondaryVserver.VserverName) -mySecondaryController $mySecondaryController) -eq $null ){
            Write-LogDebug "No Vserver Clone from [$VserverDR] found on Cluster [$SECONDARY_CLUSTER]" 
        }
        foreach ($CloneVserver in $CloneVserverList){
            $myClone=Get-NcVserver -Name $CloneVserver -Controller $mySecondaryController
            display_clone_vserver -myController $mySecondaryController -myVserver $myClone
        }
    }
    Catch 
    {
    handle_error $_ $myPrimaryVserver
    }
}

#############################################################################################
function log{
    param(
        [string]$msg,
        [string]$color = "Cyan",
        [string]$status = " .. ",
        [switch]$onlyToFile = $false
    )
    if(-not $silent -and -not $onlyToFile){
        if($status){
            $statusColor = "white"
            if($status -eq "OK"){
                $status = " OK "
                $statusColor = "green"
            }
            if($status -eq "FAIL"){
                $statusColor = "YELLOW"
            }
            write-host "[" -NoNewline -ForegroundColor white
            write-host $status -NoNewline -ForegroundColor $statusColor
            write-host "] " -NoNewline -ForegroundColor white
 
        }
        Write-Host -ForegroundColor $color "$action"
    }
    $timestamp = get-date -uformat "%Y_%m_%d %H:%M:%S"
    $mtx = New-Object System.Threading.Mutex($false, "LogfileMutex")
    [void]$mtx.WaitOne()
    Write-Output "${timestamp}: $msg" >> $global:LOGFILE
    $mtx.ReleaseMutex()
}

#############################################################################################
function check_create_dir{
    param(
        # Parameter help description
        [Parameter(Mandatory=$True)]
        [string]
        $FullPath,
        [Parameter(Mandatory=$True)]
        [string]
        $Vserver
    )
    if($debuglevel){Write-Log "[$Vserver] FullPath = [$FullPath]"} 
    $Path=Split-Path $FullPath
    if($debuglevel){Write-Log "[$Vserver] Path = [$Path]"}
    if(Test-Path $Path){
        return $True
    }else{
        if($debuglevel){Write-Log "[$Vserver] Create directory [$Path]"}
        New-Item -Path $Path -ItemType "directory" -ErrorAction "silentlycontinue" | Out-Null
        return $True
    }
}

#############################################################################################
Function create_clonevserver_dr (
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string] $workOn=$mySecondaryVserver){
Try {
	$Return = $True
    $runBackup=$False
    $runRestore=$False
    Write-Log "[$workOn] Check SVM configuration"
    Write-LogDebug "create_clonevserver_dr [$myPrimaryVserver]: start"
    # create clone SVM
    $PrimaryVserver = Get-NcVserver -Controller $myPrimaryController -Name $myPrimaryVserver  -ErrorVariable ErrorVar  
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" }
    if ( $null -eq $PrimaryVserver ) {
        Write-LogError "ERROR: Vserver $myPrimaryVserver not found" 
        clean_and_exit 1
    }
    $PrimaryRootVolume = $PrimaryVserver.RootVolume
    $PrimaryRootVolumeSecurityStyle = $PrimaryVserver.RootVolumeSecurityStyle
    $PrimaryLanguage = $PrimaryVserver.Language
    $PrimaryAllowedProtocols=$PrimaryVserver.AllowedProtocols
    $PrimaryComment=$($PrimaryVserver.Comment+"clone environment")
    if($Global:RootAggr.length -eq 0){
        $Question = "[$mySecondaryVserver] Please Select root aggregate on Cluster [$MySecondaryController]:"
        $Global:RootAggr = select_data_aggr_from_cli -myController $mySecondaryController -myQuestion $Question
    }
    Write-LogDebug "Get-NcAggr -Controller $mySecondaryController -Name $Global:RootAggr"
    $out = Get-NcAggr -Controller $mySecondaryController -Name $Global:RootAggr  -ErrorVariable ErrorVar
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcAggr failed [$ErrorVar]" ;free_mutexconsole}
    if ( $out -eq $null ) {
        Write-LogError "ERROR: aggregate [$Global:RootAggr] not found on cluster [$mySecondaryController]" 
        Write-LogError "ERROR: exit" 
        clean_and_exit 1 
    }
    Write-Log "[$workOn] create Clone vserver : [$PrimaryRootVolume] [$PrimaryLanguage] [$mySecondaryController] [$Global:RootAggr]"
    Write-LogDebug "create_clonevserver_dr: New-NcVserver -Name $mySecondaryVserver -RootVolume $PrimaryRootVolume -RootVolumeSecurityStyle $PrimaryRootVolumeSecurityStyle -Comment $PrimaryComment -Language $PrimaryLanguage -NameServerSwitch file -Controller $mySecondaryController -RootVolumeAggregate $Global:RootAggr"
    $NewVserver=New-NcVserver -Name $mySecondaryVserver -RootVolume $PrimaryRootVolume -RootVolumeSecurityStyle $PrimaryRootVolumeSecurityStyle -Comment $PrimaryComment -Language $PrimaryLanguage -NameServerSwitch file -Controller $mySecondaryController -RootVolumeAggregate $Global:RootAggr  -ErrorVariable ErrorVar
    if ( $? -ne $True ) {
        Write-LogError "ERROR: Failed to create vserver $mySecondaryVserver on $mySecondaryController"  
        Write-LogError "ERROR: exit" 
        clean_and_exit 1
    }
    Write-LogDebug "create_clonevserver_dr: Set-NcVserver -Name $mySecondaryVserver -AllowedProtocols $PrimaryAllowedProtocols -Controller $mySecondaryController"
    $NewVserver=Set-NcVserver -AllowedProtocols $PrimaryAllowedProtocols -Name $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
    if ( $? -ne $True ) {
        Write-LogError "ERROR: Failed to modify vserver $mySecondaryVserver on $mySecondaryController"  
        Write-LogError "ERROR: exit" 
        clean_and_exit 1
    }
    $SecondaryVserver = Get-NcVserver -Controller $mySecondaryController -Name $mySecondaryVserver  -ErrorVariable ErrorVar 
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" }
    if ( $SecondaryVserver -eq $null ) {
        Write-LogError "ERROR: Failed Get vserver information $mySecondaryVserver on $mySecondaryController"  
        Write-LogError "ERROR: exit" 
        clean_and_exit 1
    }
    if ( ( $ret=check_update_vserver -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed check update vserver" ; $Return = $False }
    if ( ( $ret=create_update_cron_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -Backup $runBackup -Restore $runRestore) -ne $True ) {Write-LogError "ERROR: create_update_cron_dr"}
    if ( ( $ret=create_update_policy_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create all policy" ; $Return = $False }
    if ( ( $ret=create_update_efficiency_policy_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create all Efficiency policy" ; $Return = $False }
    if ( ( $ret=create_update_firewallpolicy_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create all Firewall policy" ; $Return = $False }
    if ( ( $ret=create_update_role_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create all Role"}
    if ( ( $ret=create_lif_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create all LIF" ; $Return = $True }
    if ( ( $ret=create_update_localuser_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create all local user"}
    if ( ( $ret=create_update_localunixgroupanduser_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create all Local Unix User and Group"}
    if ( ( $ret=create_update_usermapping_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create User Mapping"}
    if ( ( $ret=create_update_DNS_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create DNS service" ; $Return = $False }
    if ( ( $ret=create_update_LDAP_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create LDAP config" ; $Return = $False }
    if ( ( $ret=create_update_NIS_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create NIS service" ; $Return = $False }
    if ( ( $ret=create_update_NFS_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create NFS service" ; $Return = $False }
    if ( ( $ret=create_update_ISCSI_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create iSCSI service" ; $Return = $False }
    if ( ( $ret=create_update_CIFS_server_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore -ForClone) -ne $True ) {	Write-LogError "ERROR: create_update_CIFS_server_dr" ; $Return = $False } 
    $ret=update_CIFS_server_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore
    if ( $? -ne $True ) {
        Write-LogWarn "Some CIFS options has not been set on [$workOn]"    
    }
    if ( ( $ret=create_update_igroupdr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create all igroups" ; $Return = $False }
    if ( ( $ret=create_update_vscan_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -fromConfigureDR -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create Vscan config" ; $Return = $False }
    if ( ( $ret=create_update_fpolicy_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -fromConfigureDR -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create Fpolicy config" ; $Return = $False }
	$ret=create_clone_volume_voldr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver  -workOn $workOn  -Backup $runBackup -Restore $runRestore
    if ( $ret.count -gt 0 ) {
        if ($ret[0] -ne $True ) { Write-LogError "ERROR: Failed to create all volumes" ; $Return = $False }
    }else{
        if ($ret -ne $True ) { Write-LogError "ERROR: Failed to create all volumes" ; $Return = $False }
    }
    if ( ( $ret=check_update_voldr  -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: check_update_voldr failed";  $Return = $False }
    if ( ( $ret=create_update_qospolicy_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore -ForClone) -ne $True ) { Write-LogError "ERROR: create_update_qospolicy_dr" ; $Return = $False }
    if ( ( $ret=create_update_snap_policy_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) {Write-LogError "ERROR: create_update_snap_policy_dr"}
    $DestinationVserverDR=($mySecondaryVserver -Split ("_clone."))[0]
    if ( ( $ret=mount_clone_voldr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -DestVserverDR $DestinationVserverDR -workOn $workOn -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to mount all volumes " ; $Return = $False }
    if (($ret=set_all_lif -mySecondaryVserver $mySecondaryVserver -myPrimaryVserver $myPrimaryVserver -mySecondaryController $mySecondaryController  -myPrimaryController $myPrimaryController -workOn $workOn  -state up -Backup $runBackup -Restore $runRestore) -ne $True ) {
        Write-LogError "ERROR: Failed to set all lif up on [$mySecondaryVserver]"
        $Return=$False
    }
    if ( ( $ret=update_cifs_usergroup -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) {
        Write-LogError "ERROR: update_cifs_usergroup failed" 
        $Return=$False			
    }
    if ( ( $ret=create_update_CIFS_shares_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: create_update_CIFS_share" ; $Return = $False }
    if ( ( $ret=map_lundr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to map all LUNs " ; $Return = $False }
    if ( ( $ret=set_serial_lundr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-Log "ERROR: Failed to change LUN serial Numbers" ; $Return = $False} 
    if(($ret=update_qtree -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True) {Write-Log "ERROR Failed to update all Qtree"; $Return = $False}
    Write-LogDebug "create_clonevserver_dr [$myPrimaryVserver]: end"
    return $Return 
} Catch {
    handle_error $_ $myPrimaryVserver
	return $False
}
}

#############################################################################################
Function create_vserver_dr (
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string] $workOn=$mySecondaryVserver,
    [bool] $DDR,
    [switch] $Backup,
    [switch] $Restore){
Try {
	$Return = $True
    $runBackup=$False
    $runRestore=$False
    Write-Log "[$workOn] Check SVM configuration"
    Write-LogDebug "create_vserver_dr[$myPrimaryVserver]: start"
    if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]";$runBackup=$True}
    if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]";$runRestore=$True}

    if($Restore -eq $False){
        $PrimaryVserver = Get-NcVserver -Controller $myPrimaryController -Name $myPrimaryVserver  -ErrorVariable ErrorVar  
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" }
        if ( $null -eq $PrimaryVserver ) {
            Write-LogError "ERROR: Vserver $myPrimaryVserver not found" 
            clean_and_exit 1
        }
    }
    else{
        # Read JSON file for this SVM
        if(Test-Path $($Global:JsonPath+"Get-NcVserver.json")){
            $PrimaryVserver=Get-Content $($Global:JsonPath+"Get-NcVserver.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcVserver.json")
            Throw "ERROR: failed to read $filepath"
        }
        $mySecondaryVserver=$myPrimaryVserver
    }
    if($Backup -eq $True){
        $PrimaryVserver | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcVserver.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcVserver.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcVserver.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcVserver.json")"
        }
    }

    if($Backup -eq $False){
        $PrimaryRootVolume = $PrimaryVserver.RootVolume
        $PrimaryRootVolumeSecurityStyle = $PrimaryVserver.RootVolumeSecurityStyle
        $PrimaryLanguage = $PrimaryVserver.Language
        $PrimaryAllowedProtocols=$PrimaryVserver.AllowedProtocols
        $PrimaryComment=$PrimaryVserver.Comment
        $SecondaryVserver = Get-NcVserver -Controller $mySecondaryController -Name $mySecondaryVserver  -ErrorVariable ErrorVar 
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" }
        if ( $SecondaryVserver -ne $null ) 
        {
            Write-Log "[$mySecondaryVserver] already exist on $mySecondaryController"
            $SecondaryRootVolume = $SecondaryVserver.RootVolume
            $SecondaryRootVolumeSecurityStyle = $SecondaryVserver.RootVolumeSecurityStyle
            $SecondaryLanguage = $SecondaryVserver.Language
            $SecondaryAllowedProtocols=$SecondaryVserver.AllowedProtocols
            $SecondaryNameMappingSwitch=$SecondaryVserver.NameMappingSwitch
            $SecondaryNameServerSwitch=$SecondaryVserver.NameServerSwitch
            $SecondaryComment=$SecondaryVserver.Comment	
            $SecondaryRootVolumeAggregate=$SecondaryVserver.RootVolumeAggregate
        } 
        else 
        {
            try {
                $global:mutexconsole.WaitOne(200) | Out-Null
            }
            catch [System.Threading.AbandonedMutexException]{
                #AbandonedMutexException means another thread exit without releasing the mutex, and this thread has acquired the mutext, therefore, it can be ignored
                Write-Host -f Red "catch abandoned mutex for [$myPrimaryVserver]"
                free_mutexconsole
            }
            Write-Log "[$workOn] Create new vserver"
            if ( $Global:RootAggr.length -eq 0 ) {
                #$mySecondaryVserver
                $Question = "[$mySecondaryVserver] Please Select root aggregate on Cluster [$MySecondaryController]:"
                $Global:RootAggr = select_data_aggr_from_cli -myController $mySecondaryController -myQuestion $Question
            }
            Write-LogDebug "Get-NcAggr -Controller $mySecondaryController -Name $Global:RootAggr"
            $out = Get-NcAggr -Controller $mySecondaryController -Name $Global:RootAggr  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcAggr failed [$ErrorVar]" ;free_mutexconsole}
            if ( $out -eq $null ) {
                Write-LogError "ERROR: aggregate [$Global:RootAggr] not found on cluster [$mySecondaryController]" 
                Write-LogError "ERROR: exit" 
                free_mutexconsole
                clean_and_exit 1 
            }
            free_mutexconsole
            Write-Log "[$workOn] create vserver dr: [$PrimaryRootVolume] [$PrimaryLanguage] [$mySecondaryController] [$Global:RootAggr]"
            Write-LogDebug "create_vserver_dr: New-NcVserver -Name $mySecondaryVserver -RootVolume $PrimaryRootVolume -RootVolumeSecurityStyle $PrimaryRootVolumeSecurityStyle -Comment $PrimaryComment -Language $PrimaryLanguage -NameServerSwitch file -Controller $mySecondaryController -RootVolumeAggregate $Global:RootAggr"
            $NewVserver=New-NcVserver -Name $mySecondaryVserver -RootVolume $PrimaryRootVolume -RootVolumeSecurityStyle $PrimaryRootVolumeSecurityStyle -Comment $PrimaryComment -Language $PrimaryLanguage -NameServerSwitch file -Controller $mySecondaryController -RootVolumeAggregate $Global:RootAggr  -ErrorVariable ErrorVar
            if ( $? -ne $True ) {
                Write-LogError "ERROR: Failed to create vserver $mySecondaryVserver on $mySecondaryController"  
                Write-LogError "ERROR: exit" 
                clean_and_exit 1
            }
            Write-LogDebug "create_vserver_dr: Set-NcVserver -Name $mySecondaryVserver -AllowedProtocols $PrimaryAllowedProtocols -Controller $mySecondaryController"
            $NewVserver=Set-NcVserver -AllowedProtocols $PrimaryAllowedProtocols -Name $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) {
                Write-LogError "ERROR: Failed to modify vserver $mySecondaryVserver on $mySecondaryController"  
                Write-LogError "ERROR: exit" 
                clean_and_exit 1
            }
            $SecondaryVserver = Get-NcVserver -Controller $mySecondaryController -Name $mySecondaryVserver  -ErrorVariable ErrorVar 
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" }
            if ( $SecondaryVserver -eq $null ) {
                Write-LogError "ERROR: Failed Get vserver information $mySecondaryVserver on $mySecondaryController"  
                Write-LogError "ERROR: exit" 
                clean_and_exit 1
            } else {
                $SecondaryRootVolume = $SecondaryVserver.RootVolume
                $SecondaryRootVolumeSecurityStyle = $SecondaryVserver.RootVolumeSecurityStyle
                $SecondaryLanguage = $SecondaryVserver.Language
                $SecondaryAllowedProtocols=$SecondaryVserver.AllowedProtocols
                $SecondaryNameMappingSwitch=$SecondaryVserver.NameMappingSwitch
                $SecondaryNameServerSwitch=$SecondaryVserver.NameServerSwitch
                $SecondaryComment=$SecondaryVserver.Comment	
                $SecondaryRootVolumeAggregate=$SecondaryVserver.RootVolumeAggregate
            } 
        }
    }
    if ( ( $ret=check_update_vserver -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed check update vserver" ; $Return = $False }
    if ( ( $ret=create_vserver_peer -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create vserver peer" ; $Return = $False }
    if ( ( $ret=create_update_cron_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -Backup $runBackup -Restore $runRestore) -ne $True ) {Write-LogError "ERROR: create_update_cron_dr"}
    if ( ( $ret=create_update_policy_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create all policy" ; $Return = $False }
    if ( ( $ret=create_update_efficiency_policy_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create all Efficiency policy" ; $Return = $False }
    if ( ( $ret=create_update_firewallpolicy_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create all Firewall policy" ; $Return = $False }
    if ( ( $ret=create_update_role_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create all Role"}
    if ( ( $ret=create_lif_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create all LIF" ; $Return = $True }
    if ( ( $ret=create_update_localuser_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create all local user"}
    if ( ( $ret=create_update_localunixgroupanduser_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create all Local Unix User and Group"}
    if ( ( $ret=create_update_usermapping_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create User Mapping"}
    if ( ( $ret=create_update_DNS_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create DNS service" ; $Return = $False }
    if ( ( $ret=create_update_LDAP_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create LDAP config" ; $Return = $False }
    if ( ( $ret=create_update_NIS_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create NIS service" ; $Return = $False }
    if ( ( $ret=create_update_NFS_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create NFS service" ; $Return = $False }
    if ( ( $ret=create_update_ISCSI_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create iSCSI service" ; $Return = $False }
    if ( ( $ret=create_update_CIFS_server_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) {	Write-LogError "ERROR: create_update_CIFS_server_dr" ; $Return = $False } 
    $ret=update_CIFS_server_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore
    if ( $? -ne $True ) {
        Write-LogWarn "Some CIFS options has not been set on [$workOn]"    
    }
    if ( ( $ret=create_update_igroupdr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create all igroups" ; $Return = $False }
    if ( ( $ret=create_update_vscan_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -fromConfigureDR -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create Vscan config" ; $Return = $False }
    if ( ( $ret=create_update_fpolicy_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -fromConfigureDR -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create Fpolicy config" ; $Return = $False }
	$ret=create_volume_voldr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver  -workOn $workOn  -Backup $runBackup -Restore $runRestore
    if ( $ret.count -gt 0 ) {
        if ($ret[0] -ne $True ) { Write-LogError "ERROR: Failed to create all volumes" ; $Return = $False }
    }else{
        if ($ret -ne $True ) { Write-LogError "ERROR: Failed to create all volumes" ; $Return = $False }
    }
	if ( ( $ret=check_update_voldr  -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: check_update_voldr failed";  $Return = $False }
    if ( ( $ret=create_update_qospolicy_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore -ForClone) -ne $True ) { Write-LogError "ERROR: create_update_qospolicy_dr" ; $Return = $False }
	if ( ( $ret=create_snapmirror_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn -DDR $DDR -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to create all snapmirror relations " ; $Return = $False }
	if ( ( $ret=create_update_snap_policy_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) {Write-LogError "ERROR: create_update_snap_policy_dr"}
	if($Backup -eq $False -and $Restore -eq $False){
        $ASK_WAIT=Read-HostOptions "[$mySecondaryVserver] Do you want to wait the end of snapmirror transfers and mount all volumes and map LUNs $mySecondaryVserver now ?" "y/n"
    }else{
        $ASK_WAIT='y'
    }
    if ( $ASK_WAIT -eq 'y' ) {
        if($Backup -eq $False -and $Restore -eq $False){
            if ( ( $ret=wait_snapmirror_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver) -ne $True ) { Write-LogError "ERROR: Failed snapmirror relations bad status " ; $Return = $False }
        }
        #Wait-Debugger
        if ( ( $ret=mount_voldr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver  -workOn $workOn -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to mount all volumes " ; $Return = $False }
        #Wait-Debugger
        if($Backup -eq $False){
            if (($ret=set_all_lif -mySecondaryVserver $mySecondaryVserver -myPrimaryVserver $myPrimaryVserver -mySecondaryController $mySecondaryController  -myPrimaryController $myPrimaryController -workOn $workOn  -state up -Backup $runBackup -Restore $runRestore) -ne $True ) {
                Write-LogError "ERROR: Failed to set all lif up on [$mySecondaryVserver]"
                $Return=$False
            }
        }
        #Wait-Debugger
        if ( ( $ret=update_cifs_usergroup -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) {
			Write-LogError "ERROR: update_cifs_usergroup failed" 
			$Return=$False			
		}
		if($Backup -eq $False -and $Restore -eq $False){
            if (($ret=set_all_lif -mySecondaryVserver $mySecondaryVserver -myPrimaryVserver $myPrimaryVserver -mySecondaryController $mySecondaryController  -myPrimaryController $myPrimaryController -workOn $workOn  -state down -Backup $runBackup -Restore $runRestore) -ne $True ) {
                Write-LogError "ERROR: Failed to set all lif down on [$mySecondaryVserver]"
                $Return=$False
            }
        }
		if ( ( $ret=create_update_CIFS_shares_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: create_update_CIFS_share" ; $Return = $False }
		if ( ( $ret=map_lundr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-LogError "ERROR: Failed to map all LUNs " ; $Return = $False }
		if ( ( $ret=set_serial_lundr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True ) { Write-Log "ERROR: Failed to change LUN serial Numbers" ; $Return = $False} 
    }
    # ajouter ici en mode Backup ou Restore only : la sauvegarde des qtree present avec toutes leurs options
    if($Backup -eq $True -or $Restore -eq $True){
        #wait-debugger
        if(($ret=update_qtree -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $workOn  -Backup $runBackup -Restore $runRestore) -ne $True) {Write-Log "ERROR Failed to update all Qtree"; $Return = $False}
    }
    #if($Backup -eq $False -and $Restore -eq $False){
    #    if ( ( $ret=update_qtree_export_policy_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -Backup $runBackup -Restore $runRestore) -ne $True ) {Write-Log "ERROR Failed to modify all Qtree Export Policy" ; $Return = $False}
    #}
    if($Backup -eq $False -and $Restore -eq $False){
        if ( ( $ret=update_msid_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver) -ne $True ) { Write-LogError "ERROR: Failed to update MSID for all volumes " ; $Return = $False }
        Write-Warning "Do not forget to run UpdateDR (with -DataAggr option) frequently to update SVM DR and mount all new volumes"
    }
    Write-LogDebug "create_vserver_dr [$myPrimaryVserver]: end"
    return $Return 
} Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
Function update_msid_dr (
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
    [string] $mySecondaryVserver ) {

Try {
    $Return=$True
    Write-LogDebug "update_msid_dr: start"
    $NcCluster = Get-NcCluster -Controller $myPrimaryController
    $SourceCluster = $NcCluster.ClusterName
    $NcCluster = Get-NcCluster -Controller $mySecondaryController
    $DestinationCluster = $NcCluster.ClusterName
    $isMCC=Test-NcMetrocluster -Controller $mySecondaryController -ErrorVariable ErrorVar
    if($isMCC = $True){
        Write-LogDebug "MSID Preserve is not compatible with MCC as destination"
        return $True
    }
    Write-LogDebug "Check ONTAP version"
	$PrimaryVersion=(Get-NcSystemVersionInfo -Controller $myPrimaryController).VersionTupleV
	$SecondaryVersion=(Get-NcSystemVersionInfo -Controller $mySecondaryController).VersionTupleV
	$PrimaryVersionString=$PrimaryVersion | out-string
	$SecondaryVersionString=$SecondaryVersion | out-string
	Write-LogDebug "Primary version is $PrimaryVersionString"
	Write-LogDebug "Seconday version is $SecondaryVersionString"
	$vfrEnable=$False
	if(($PrimaryVersion.Major -ne $SecondaryVersion.Major) -or ($PrimaryVersion.Major -eq 8 -and $SecondaryVersion.Major -eq 8)){
		if($PrimaryVersion.Major -ge 9 -and $SecondaryVersion.Major -ge 9){
			$vfrEnable=$True
		}
		elseif(($PrimaryVersion.Major -eq 8 -and $PrimaryVersion.Minor -ge 3 -and $PrimaryVersion.Build -ge 2) -and ($SecondaryVersion.Major -ge 9)){
			$vfrEnable=$True
		}
		elseif(($SecondaryVersion.Major -eq 8 -and $SecondaryVersion.Minor -ge 3 -and $SecondaryVersion.Build -ge 2) -and ($PrimaryVersion.Major -ge 9)){
			$vfrEnable=$True
		}
		elseif(($PrimaryVersion.Major -eq 8 -and $PrimaryVersion.Minor -ge 3 -and $PrimaryVersion.Build -ge 2) -and ($SecondaryVersion.Major -eq 8 -and $SecondaryVersion.Minor -ge 3 -and $SecondaryVersion.Build -ge 2)){
			$vfrEnable=$True
		}
	}
    if($PrimaryVersion.Major -ge 9 -and $SecondaryVersion.Major -ge 9){
	    $vfrEnable=$True
	}
    if($DebugLevel){Write-LogDebug "VFR mode is set to [$vfrEnable]"}

    Write-LogDebug "Get-NcVol -Query @{Vserver=$mySecondaryVserver;VolumeStateAttributes=@{IsVserverRoot=$false;State="online"}} -Controller $mySecondaryController"
    $VolList=Get-NcVol -Query @{Vserver=$mySecondaryVserver;VolumeStateAttributes=@{IsVserverRoot=$false;State="online"}} -Controller $mySecondaryController -ErrorVariable ErrorVar
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
    foreach ( $vol in ( $VolList  | Skip-Null ) ) {
        $VolName=$vol.Name
        $DestMSID=$vol.VolumeIdAttributes.Msid
        $SourceVol=Get-NcVol -Name $VolName -Vserver $myPrimaryVserver -Controller $myPrimaryController -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
        $SourceMSID=$SourceVol.VolumeIdAttributes.Msid
        if($DestMSID -ne $SourceMSID){
            Write-LogDebug "MSID missmatch detected"
            Write-LogDebug "Invoke-NcSnapmirrorQuiesce -DestinationCluster $DestinationCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $VolName -Controller $mySecondaryController -Confirm:$False"
            $ret=Invoke-NcSnapmirrorQuiesce -DestinationCluster $DestinationCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $VolName -Controller $mySecondaryController -Confirm:$False -ErrorVariable ErrorVar
            if ( $? -ne $True ) { Write-LogError "ERROR: Invoke-NcSnapmirrorQuiesce failed [$ErrorVar]" }
            Write-LogDebug "Invoke-NcSnapmirrorBreak -DestinationCluster $DestinationCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $VolName -Controller $mySecondaryController -Confirm:$False"
            $ret=Invoke-NcSnapmirrorBreak -DestinationCluster $DestinationCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $VolName -Controller $mySecondaryController -Confirm:$False -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Invoke-NcSnapmirrorBreak failed [$ErrorVar]" }
            Write-LogDebug "Remove-NcSnapmirror -DestinationCluster $DestinationCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $VolName -SourceCluster $SourceCluster -SourceVserver $myPrimaryVserver -SourceVolume $VolName -Controller $mySecondaryController -Confirm:$False"
            $ret=Remove-NcSnapmirror -DestinationCluster $DestinationCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $VolName -SourceCluster $SourceCluster -SourceVserver $myPrimaryVserver -SourceVolume $VolName -Controller $mySecondaryController -Confirm:$False -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Remove-NcSnapmirror failed [$ErrorVar]" }
            if ( ( $ret=restamp_msid -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -volume $vol) -ne $True) {
                Write-LogError "ERROR: restamp_msid failed"
                $Return = $False
                throw "ERROR: restamp_msid failed"
            }
            
            if($vfrEnable -eq $False){
                Write-LogDebug "New-NcSnapmirror -DestinationCluster $DestinationCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $VolName -SourceCluster $SourceCluster -SourceVserver $myPrimaryVserver -SourceVolume $VolName -Controller $mySecondaryController "
                $relation=New-NcSnapmirror -DestinationCluster $DestinationCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $VolName -SourceCluster $SourceCluster -SourceVserver $myPrimaryVserver -SourceVolume $VolName -Controller $mySecondaryController  -ErrorVariable ErrorVar 
                if ( $? -ne $True ) { $Return = $False ; Write-LogError "ERROR: New-NcSnapmirror failed [$ErrorVar]" }
            }else{
                Write-LogDebug "New-NcSnapmirror -DestinationCluster $DestinationCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $VolName -SourceCluster $SourceCluster -SourceVserver $myPrimaryVserver -SourceVolume $VolName -Schedule hourly -type vault -policy $XDPPolicy -Controller $mySecondaryController "
                $relation=New-NcSnapmirror -DestinationCluster $DestinationCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $VolName -SourceCluster $SourceCluster -SourceVserver $myPrimaryVserver -SourceVolume $VolName -Schedule hourly -type vault -policy $XDPPolicy -Controller $mySecondaryController  -ErrorVariable ErrorVar 
                if ( $? -ne $True ) { $Return = $False ; Write-LogError "ERROR: New-NcSnapmirror failed [$ErrorVar]" }
            }
            Write-LogDebug "Invoke-NcSnapmirrorResync -DestinationCluster $DestinationCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $VolName -SourceCluster $SourceCluster -SourceVserver $myPrimaryVserver -SourceVolume $VolName -Controller $mySecondaryController"
            $out=Invoke-NcSnapmirrorResync -DestinationCluster $DestinationCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $VolName -SourceCluster $SourceCluster -SourceVserver $myPrimaryVserver -SourceVolume $VolName -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
            if ( $? -ne $True ) { $Return=$False;Write-LogError "ERROR: Snapmirror Resync failed" }
        }
    }
    Write-LogDebug "update_msid_dr: end"
    return $Return 
} Catch {
    handle_error $_ $myPrimaryVserver
    return $Return
}
}

#############################################################################################
Function restamp_msid (
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [DataONTAP.C.Types.Volume.VolumeAttributes] $volume ) {

Try {
    $Return=$True
    Write-logDebug "restamp_msid: start"
    $NcCluster = Get-NcCluster -Controller $myPrimaryController
    $SourceCluster = $NcCluster.ClusterName
    $NcCluster = Get-NcCluster -Controller $mySecondaryController
    $DestinationCluster = $NcCluster.ClusterName
    $isMCC=Test-NcMetrocluster -Controller $mySecondaryController -ErrorVariable ErrorVar
    if($isMCC = $True){
        Write-LogDebug "MSID Preserve is not compatible with MCC as destination"
        return $True
    }
    if ($DebugLevel) {Write-LogDebug "Get-NcVserver -Vserver $mySecondaryVserver -Controller $mySecondaryController"}
    $DestVserver=Get-NcVserver -Vserver $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErrorVar
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" }
    if($DestVserver.IsConfigLockedForChanges -eq $True){
        if ($DebugLevel) {Write-logDebug "Unlock-NcVserver -Vserver $mySecondaryVserver -Force -Confirm:$False -Controller $mySecondaryController"}
        $ret=Unlock-NcVserver -Vserver $mySecondaryVserver -Force -Confirm:$False -Controller $mySecondaryController -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Unlock-NcVserver failed [$ErrorVar]" }
    }
    if($volume.Count -eq 0){
        if ($DebugLevel) {Write-LogDebug "Get-NcVol -Query @{Vserver=$mySecondaryVserver;VolumeStateAttributes=@{IsVserverRoot=$false;State="online"}} -Controller $mySecondaryController"}
        $VolList=Get-NcVol -Query @{Vserver=$mySecondaryVserver;VolumeStateAttributes=@{IsVserverRoot=$false;State="online"}} -Controller $mySecondaryController -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
    }else{
        $VolList=$volume
    }
    foreach ( $vol in ( $VolList  | Skip-Null ) ) {
        $VolName=$vol.Name
        $JunctionPath=$vol.VolumeIdAttributes.JunctionPath
        $destMSID=$vol.VolumeIdAttributes.Msid
        if ($DebugLevel) {Write-LogDebug "Get-NcVol -Vserver $myPrimaryVserver -Name $VolName -Controller $myPrimaryController"}
        $sourceVol=Get-NcVol -Vserver $myPrimaryVserver -Name $VolName -Controller $myPrimaryController -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
        $sourceMSID=$sourceVol.VolumeIdAttributes.Msid
		
        if($destMSID -ne $sourceMSID){
            Write-Log "[$mySecondaryVserver] Restamp MSID for volume [$VolName]"
            #Write-logDebug "Dismount-NcVol -Name $VolName -VserverContext $mySecondaryVserver -Force -Confirm:$False -Controller $mySecondaryController"
            #$ret=Dismount-NcVol -Name $VolName -VserverContext $mySecondaryVserver -Force -Confirm:$False -Controller $mySecondaryController -ErrorVariable ErrorVar
            #if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Dismount-NcVol failed [$ErrorVar]" }
            $ret=analyse_junction_path -myController $mySecondaryController -myVserver $mySecondaryVserver -Dest    
            if ($ret -ne $True){$Return=$False;Throw "ERROR : Failed to analyse_junction_path"}
            umount_volume -myController $mySecondaryController -myVserver $mySecondaryVserver -myVolumeName $VolName
            $QOSPolModified=$False
            $QOSPolicyGroup=$vol.VolumeQosAttributes.PolicyGroupName
            if($QOSPolicyGroup.Length -gt 0){
                $template=Get-NcVol -Template -Controller $mySecondaryController -ErrorVariable ErrorVar
                $template.Name=$VolName
                $templace.Vserver=$mySecondaryVserver
                $attrib=Get-NcVol -Template -Controller $mySecondaryController -ErrorVariable ErrorVar
                Initialize-NcObjectProperty $attrib VolumeQosAttributes
                $attrib.VolumeQosAttributes.PolicyGroupName="-"
                if ($DebugLevel) {Write-LogDebug "Remove QOS Policy Group [$QOSPolicyGroup] for volume [$VolName]"}
                $ret=Update-NcVol -Query $template -Attributes $attrib -Controller $mySecondaryController -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Update-NcVol failed [$ErrorVar]" }
                $QOSPolModified=$True
            }
            Write-logDebug "Invoke-NcSsh -Command ""set diag; debug vserverdr restamp-volume-msid -vserver $mySecondaryVserver -volume $VolName -new-msid $sourceMSID -msid $destMSID"" -Controller $mySecondaryController"
            $ret=Invoke-NcSsh -Command "set diag; debug vserverdr restamp-volume-msid -vserver $mySecondaryVserver -volume $VolName -new-msid $sourceMSID -msid $destMSID" -Controller $mySecondaryController -Timeout 60000 -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Invoke-NcSsh failed [$ErrorVar]" }
            $detailInvoke=$ret | Out-String
            $onelinedetailInvoke=$detailInvoke -replace "`r`n"," "
            if ($DebugLevel) {Write-LogDebug "Restamp MSID return :"}
            if ($DebugLevel) {Write-logDebug "$detailInvoke"}
            $restampSucceeded=$False
            if($onelinedetailInvoke -match "Successfully.+restamped.+MSID.+for.+volume"){
                $restampSucceeded=$True    
            }
            # $invokeReturn=$detailInvoke.split("`n")
            # $restampSucceeded=$False
            # for($i=0;$i -lt $invokeReturn.count;$i++){
            #     if($invokeReturn[$i] -match "Successfully restamped MSID for volume "){
            #         $restampSucceeded=$True
            #         break
            #     }
            # }
            if($restampSucceeded -eq $True){
                Write-log "[$mySecondaryVserver] Volume [$VolName] MSID modified from [$destMSID] to [$sourceMSID]"
            }else{
                Write-Warning "Failed to modifed MSID for volume [$VolName]."
                Write-Warning "Reason : `r`n$detailInvoke"
                $Return=$False
            }

            if ($DebugLevel) {Write-LogDebug "Get-NcVserver -Vserver $mySecondaryVserver -Controller $mySecondaryController"}
            $DestVserver=Get-NcVserver -Vserver $mySecondaryVserver -Controller $mySecondaryController -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" }
            if($DestVserver.IsConfigLockedForChanges -eq $True){
                if ($DebugLevel) {Write-logDebug "Unlock-NcVserver -Vserver $mySecondaryVserver -Force -Confirm:$False -Controller $mySecondaryController"}
                $ret=Unlock-NcVserver -Vserver $mySecondaryVserver -Force -Confirm:$False -Controller $mySecondaryController -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Unlock-NcVserver failed [$ErrorVar]" }
            }
    		
            if($QOSPolModified -eq $True){
                $attrib.VolumeQosAttributes.PolicyGroupName=$QOSPolicyGroup
                if ($DebugLevel) {Write-LogDebug "Redefine QOS Policy Group [$QOSPolicyGroup] for Volume [$VolName]"}
                $ret=Update-NcVol -Query $template -Attributes $attrib -Controller $mySecondaryController -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Update-NcVol failed [$ErrorVar]" }
            }

            #if($JunctionPath.Length -gt 0){
            #    Write-logDebug "Mount-NcVol -Name $VolName -VserverContext $mySecondaryVserver -JunctionPath $JunctionPath -Controller $mySecondaryController"
            #    $ret=Mount-NcVol -Name $VolName -VserverContext $mySecondaryVserver -JunctionPath $JunctionPath -Controller $mySecondaryController -ErrorVariable ErrorVar
            #    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Mount-NcVol failed [$ErrorVar]" }
            #}
            $ret=analyse_junction_path -myController $myPrimaryController -myVserver $myPrimaryVserver      
            if ($ret -ne $True){$Return=$False;Throw "ERROR : Failed to analyse_junction_path"}
            $ret=mount_volume -myController $mySecondaryController -myVserver $mySecondaryVserver -myVolumeName $VolName -myPrimaryController $myPrimaryController -myPrimaryVserver $myPrimaryVserver
            if($ret -ne $True){$Return = $False; Throw "ERROR : Failed to mount volume [$VolName] on [$mySecondaryVserver]"}
        }else{
            if ($DebugLevel) {Write-LogDebug "Skip volume [$VolName] because MSID [$destMSID] is already equal to source MSID [$sourceMSID]"}
        }
    }
    Write-logDebug "restamp_msid: end" 
    return $Return
}catch{
    handle_error $_ $myPrimaryVserver
    return $Return
}
}

#############################################################################################
Function remove_vserver_source (
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
	[string] $mySecondaryVserver ) {

Try {	
	$Return = $false
    Write-LogDebug "remove_vserver_source: start"
	$out = Get-NcVserver  -Name $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar 
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" }
	if ( $out -eq $null ) {
		Write-LogWarn "Vserver [$myPrimaryVserver] does not exist" 
		Write-LogWarn "exit"
		return $true
	}

	# Remove Reverse Relation if required
	# if ( ( remove_snapmirror_dr -myPrimaryController $mySecondaryController -mySecondaryController $myPrimaryController -myPrimaryVserver $mySecondaryVserver -mySecondaryVserver $myPrimaryVserver	 ) -ne $True ) { 
	# Write-LogError "ERROR: remove_snapmirror_dr failed"
	# clean_and_exit 1
	# }

	# # Remove Relation 
	# if ( ( remove_snapmirror_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver	) -ne $True ) {
	# 	Write-LogError "ERROR: remove_snapmirror_dr failed" 
	# 	return $false
	# }


	if ( ( remove_vserver_peer -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) {
		Write-LogError "ERROR: remove_vserver_peer failed" 
		return $false
	}

	if ( ( umount_voldr -myPrimaryController $mySecondaryController -mySecondaryController $myPrimaryController -myPrimaryVserver $mySecondaryVserver -mySecondaryVserver $myPrimaryVserver ) -ne $True ) {
		Write-LogError "ERROR: umount_voldr failed" 
		return $false
	}
	if ( ( remove_voldr -myPrimaryController $mySecondaryController -mySecondaryController $myPrimaryController -myPrimaryVserver $mySecondaryVserver -mySecondaryVserver $myPrimaryVserver ) -ne $True ) {
		Write-LogError "ERROR: remove_voldr failed" 
		return $false
	}
	if ( ( remove_igroupdr -myPrimaryController $mySecondaryController -mySecondaryController $myPrimaryController -myPrimaryVserver $mySecondaryVserver -mySecondaryVserver $myPrimaryVserver ) -ne $True ) {
		Write-LogError "ERROR: remove_igroupdr failed" 
		return $false
	}

	$myCifsServer = Get-NcCifsServer -VserverContext  $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsServer failed [$ErrorVar]" }
	if ( $myCifsServer -ne $null ) { 
		$out=Stop-NcCifsServer -VserverContext  $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar -Confirm:$False
		$out=Remove-NcCifsServer -VserverContext  $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar -Confirm:$False
		if ( $? -ne $True ) {
			Write-LogError "ERROR: Failed to Remove Service CIFS" 
			return $false
		}
	}

	$out = Get-NcVserver  -Name $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar 
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" }
	if ( $out.State -ne "stopped" ) {
		$out = Stop-NcVserver -Name $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar -Confirm:$False
		if ( $? -ne $True ) {
			Write-LogError "ERROR: Unable to stop  Vserver [$myPrimaryVserver]" 
		}
	}

	$out = Get-NcVserver  -Name $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar 
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" }
	if ( $out -ne $null ) {
		Remove-NcVserver -Name $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar  -confirm:$False
		if ( $? -ne $True ) {
			Write-LogError "ERROR: Unable to Remove  vserver [$myPrimaryVserver]" 
			return $false
		}
	}
    Write-LogDebug "remove_vserver_source: end"
	return $true 

}
catch{
    handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
Function remove_vserver_clone_dr (
        [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
		[string] $mySecondaryVserver ) {
Try {
    Write-LogDebug "remove_vserver_clone_dr: start"	
	$Return = $true
    $out = Get-NcVserver  -Name $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar 
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" }
	if ( $out -eq $null ) {
		Write-LogWarn "Vserver [$mySecondaryVserver] does not exist" 
		Write-LogWarn "exit"
		return $true
	}
	if ( ( umount_voldr -mySecondaryController $mySecondaryController -mySecondaryVserver $mySecondaryVserver) -ne $True ) {
		Write-LogError "ERROR: umount_voldr failed" 
		return $false
	}
	if ( ( $ret=remove_voldr -mySecondaryController $mySecondaryController -mySecondaryVserver $mySecondaryVserver) -ne $True ) {
		Write-LogError "ERROR: remove_voldr failed" 
		return $false
	}
	if ( ( $ret=remove_igroupdr -mySecondaryController $mySecondaryController -mySecondaryVserver $mySecondaryVserver) -ne $True ) {
		Write-LogError "ERROR: remove_igroupdr failed" 
		return $false
    }
	$myCifsServer = Get-NcCifsServer -VserverContext  $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsServer failed [$ErrorVar]" }
	if ( $myCifsServer -ne $null ) { 
        Write-Log "[$mySecondaryVserver] Remove CIFS server"
		$out=Stop-NcCifsServer -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
		$out=Remove-NcCifsServer -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
		if ( $? -ne $True ) {
			Write-LogError "ERROR: Failed to Remove Service CIFS" 
			return $false
		}
	}
	$out = Get-NcVserver  -Name $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar 
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" }
	if ( $out.State -ne "stopped" ) {
        Write-Log "[$mySecondaryVserver] Stop SVM"
		$out = Stop-NcVserver -Name $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
		if ( $? -ne $True ) {
			Write-LogError "ERROR: Unable to stop  Vserver [$mySecondaryVserver]" 
		}
	}
	$out = Get-NcVserver  -Name $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar 
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" }
	if ( $out -ne $null ) {
        Write-Log "[$mySecondaryVserver] Remove SVM"
		$out=Remove-NcVserver -Name $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar  -confirm:$False
		if ( $? -ne $True ) {
			Write-LogError "ERROR: Unable to Remove  vserver [$mySecondaryVserver]" 
			return $false
		}
	}
    Write-LogDebug "remove_vserver_clone_dr: end"	
    return $Return
}
Catch {
    handle_error $_ $mySecondaryVserver
	return $Return
}
}

#############################################################################################
Function remove_vserver_dr (
        [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
        [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
		[string] $myPrimaryVserver,
		[string] $mySecondaryVserver ) {
Try {
    Write-LogDebug "remove_vserver_dr: start"	
	$Return = $true
	$out = Get-NcVserver  -Name $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar 
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" }
	if ( $out -eq $null ) {
		Write-LogWarn "Vserver [$mySecondaryVserver] does not exist" 
		Write-LogWarn "exit"
		return $true
	}

	$ANS=Read-HostOptions "Do you really want to delete SVM_DR [$mySecondaryVserver] from secondary cluster  [$mySecondaryController] ?" "y/n"
	if ( $ANS -ne 'y' ) {
		return $true
	}

	# Remove Reverse Relation if required
	if ( ( remove_snapmirror_dr -myPrimaryController $mySecondaryController -mySecondaryController $myPrimaryController -myPrimaryVserver $mySecondaryVserver -mySecondaryVserver $myPrimaryVserver	 ) -ne $True ) { 
	Write-LogError "ERROR: remove_snapmirror_dr failed"
	clean_and_exit 1
	}

	# Remove Relation 
	if ( ( remove_snapmirror_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver	) -ne $True ) {
		Write-LogError "ERROR: remove_snapmirror_dr failed" 
		return $false
	}


	if ( ( remove_vserver_peer -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) {
		Write-LogError "ERROR: remove_vserver_peer failed" 
		return $false
	}

	if ( ( umount_voldr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver) -ne $True ) {
		Write-LogError "ERROR: umount_voldr failed" 
		return $false
	}
	if ( ( $ret=remove_voldr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver) -ne $True ) {
		Write-LogError "ERROR: remove_voldr failed" 
		return $false
	}
	if ( ( $ret=remove_igroupdr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver) -ne $True ) {
		Write-LogError "ERROR: remove_igroupdr failed" 
		return $false
	}

	$myCifsServer = Get-NcCifsServer -VserverContext  $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsServer failed [$ErrorVar]" }
	if ( $myCifsServer -ne $null ) { 
		$out=Stop-NcCifsServer -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
		$out=Remove-NcCifsServer -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
		if ( $? -ne $True ) {
			Write-LogError "ERROR: Failed to Remove Service CIFS" 
			return $false
		}
	}

	$out = Get-NcVserver  -Name $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar 
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" }
	if ( $out.State -ne "stopped" ) {
		$out = Stop-NcVserver -Name $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
		if ( $? -ne $True ) {
			Write-LogError "ERROR: Unable to stop  Vserver [$mySecondaryVserver]" 
		}
	}

	$out = Get-NcVserver  -Name $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar 
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" }
	if ( $out -ne $null ) {
		$out=Remove-NcVserver -Name $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar  -confirm:$False
		if ( $? -ne $True ) {
			Write-LogError "ERROR: Unable to Remove  vserver [$mySecondaryVserver]" 
			return $false
		}
	}
    Write-LogDebug "remove_vserver_dr: end"
	return $true 
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
Function get_last_snapshot (
	[NetApp.Ontapi.Filer.C.NcController] $myController,
	[string] $myVserver, 
	[string] $myVolume ) {

	$SnapList=Get-NcSnapshot  -Volume $myVolume -Vserver $myVserver -Controller $myController  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapshot failed [$ErrorVar]" }
	$i=0 ; foreach ( $snap in $SnapList) { $i++ } ; $i--
	$LastSnapName=$SnapList[$i].Name
	return $LastSnapName
}

#############################################################################################
Function update_snapmirror_vserver (
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
	[string] $mySecondaryVserver, 
	[boolean] $UseLastSnapshot ) {
Try {
	$Return = $True

	$myPrimaryCluster = (Get-NcCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar).ClusterName			
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }
	$mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar).ClusterName			
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }

	Write-LogDebug "update_snapmirror_vserver: start"
	if ( $mySecondaryVserver -eq $null -or $mySecondaryVserver -eq "" ) {
		Write-LogError "ERROR: update_snapmirror_vserver null entry" 
		clean_and_exit 2
	}
	Write-LogDebug "Get-NcSnapmirror -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
	$relationList = Get-NcSnapmirror -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapMrirror failed [$ErrorVar]" }
	if ( ( $relationList -eq $null ) -or ( $relationList.count -eq 0 ) ) {
		Write-Log "[$mySecondaryVserver] No Snapmirror relation [$myPrimaryVserver]->[$mySecondaryVserver]"
		return $True
	}
	foreach ( $relation in ( $relationList | Skip-Null ) ) {
		$MirrorState=$relation.MirrorState
		$SourceVolume=$relation.SourceVolume
		$DestinationVolume=$relation.DestinationVolume
		$SourceLocation=$relation.SourceLocation
		$DestinationLocation=$relation.DestinationLocation
		$RelationshipStatus=$relation.RelationshipStatus
		if ( ( $MirrorState -eq 'snapmirrored') -and ($RelationshipStatus -eq 'idle' ) ) {
			Write-Log "[$mySecondaryVserver] Update relation [$SourceLocation] [$DestinationLocation]" 
			if ( $UseLastSnapshot -eq $True ) {
				$LastSnapName=get_last_snapshot -myController  $myPrimaryController  -myVserver $myPrimaryVserver -myVolume $SourceVolume
				if ( $LastSnapName -eq $null ) {
					Write-LogError "ERROR: Unable to fin last snapshot for [$SourceVolume] [$PrimaryVserver] [$PrimaryCluster]" 
				} else {
					Write-LogDebug "Invoke-NcSnapmirrorUpdate -Destination $DestinationLocation -Source $SourceLocation -SourceSnapshot $LastSnapName -Controller $mySecondaryController"
					$out=Invoke-NcSnapmirrorUpdate -Destination $DestinationLocation -Source $SourceLocation -SourceSnapshot $LastSnapName -Controller $mySecondaryController  -ErrorVariable ErrorVar 
				}
			} else {
				Write-LogDebug "Invoke-NcSnapmirrorUpdate -Destination $DestinationLocation -Source $SourceLocation -Controller $mySecondaryController"
				$out=Invoke-NcSnapmirrorUpdate -Destination $DestinationLocation -Source $SourceLocation -Controller $mySecondaryController  -ErrorVariable ErrorVar 
			}
			if ( $? -ne $True ) {
				Write-LogError "ERROR: Snapmirror update failed: [$SourceLocation] [$DestinationLocation]"
			}
		} else { 
			Write-LogError "ERROR: The relation [$SourceLocation] [$DestinationLocation] status is [$RelationshipStatus] [$MirrorState] " 
			$Return = $False
		}
	}

	Write-LogDebug "Get-NcSnapmirror -SourceCluster $myPrimaryCluster -DestinationCluster $mySecondaryCluster -SourceVserver $myPrimaryVserver -DestinationVserver $mySecondaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
	$relationList = Get-NcSnapmirror -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapmirror failed [$ErrorVar]" }
	foreach ( $relation in ( $relationList | Skip-Null ) ) {
		$MirrorState=$relation.MirrorState
		$SourceVolume=$relation.SourceVolume
		$DestinationVolume=$relation.DestinationVolume
		$SourceLocation=$relation.SourceLocation
		$DestinationLocation=$relation.DestinationLocation
		$RelationshipStatus=$relation.RelationshipStatus
		$LastTransferEndTimestamp=$relation.LastTransferEndTimestamp
		$LAG = get-lag ($LastTransferEndTimestamp)
		Write-Log "[$mySecondaryVserver] Status relation [$SourceLocation] [$DestinationLocation]:[$RelationshipStatus] [$MirrorState] [$LAG]"
	}
    Write-LogDebug "update_snapmirror_vserver: end"
	return $Return 
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
Function break_snapmirror_vserver_dr (
	[NetApp.Ontapi.Filer.C.NcController] $myController,
	[switch] $NoInteractive,
	[string] $myPrimaryVserver, 
	[string] $mySecondaryVserver ) {
Try {
	
	$Return = $True

	$myCluster = (Get-NcCluster -Controller $myController  -ErrorVariable ErrorVar).ClusterName			
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }

	Write-LogDebug "break_snapmirror_vserver_dr: start"

	if ( $myPrimaryVserver -eq $null -or $myPrimaryVserver -eq "" ) {
		$Return = $False
		throw "ERROR: break_snapmirror_vserver_dr myPrimaryVserver is null" 
	}

	if ( $mySecondaryVserver -eq $null -or $mySecondaryVserver -eq "" ) {
		$Return = $False
		throw "ERROR: break_snapmirror_vserver_dr mySecondaryVserver is null" 
	}
	Write-LogDebug "Get-NcSnapmirror -DestinationCluster $myCluster -SourceVserver $myPrimaryVserver -DestinationVserver $mySecondaryVserver -VserverContext $mySecondaryVserver -Controller $myController"
	$relationList = Get-NcSnapmirror -DestinationCluster $myCluster -SourceVserver $myPrimaryVserver -DestinationVserver $mySecondaryVserver -VserverContext $mySecondaryVserver -Controller $myController  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapmirror failed [$ErrorVar]" }
	foreach ( $relation in ( $relationList | Skip-Null ) ) 
    {
		$MirrorState=$relation.MirrorState
		$SourceVolume=$relation.SourceVolume
		$DestinationVolume=$relation.DestinationVolume
		$SourceLocation=$relation.SourceLocation
		$DestinationLocation=$relation.DestinationLocation
		$RelationshipStatus=$relation.RelationshipStatus
		if ( ( $MirrorState -eq 'snapmirrored') -and ($RelationshipStatus -eq 'idle' ) ) 
        {
			Write-Log "[$mySecondaryVserver] Break relation [$SourceLocation] [$DestinationLocation]" -f red
			Write-LogDebug "Invoke-NcSnapmirrorBreak -Destination $DestinationLocation -Source $SourceLocation -Controller $myController -Confirm:$False"
			$out=Invoke-NcSnapmirrorBreak -Destination $DestinationLocation -Source $SourceLocation -Controller $myController  -ErrorVariable ErrorVar -Confirm:$False
			if ( $? -ne $True ) 
            {
				$Return = $False ; throw "ERROR: Invoke-NcSnapmirrorBreak failed"
			}	
		} 
        else 
        {
			Write-LogError "ERROR: The relation [$SourceLocation] [$DestinationLocation] status is [$RelationshipStatus] [$MirrorState] " 
			if ( $NoInteractive ) { $Return = $False } 
            else 
            {
				$ANS=Read-HostOptions "[$mySecondaryVserver] Do you want to break this relation ?" "y/n"
				if ( $ANS -eq 'y' ) 
                {
					Write-LogDebug "Invoke-NcSnapmirrorBreak -Destination $DestinationLocation -Source $SourceLocation -Controller $myController -Confirm:$False"
					$out=Invoke-NcSnapmirrorBreak -Destination $DestinationLocation -Source $SourceLocation -Controller $myController  -ErrorVariable ErrorVar -Confirm:$False
				}	
				$Return = $False
			}
		}
        if ( $Global:ForceActivate -eq $True )
        {
            Write-LogDebug "Remove-NcSnapmirror -Destination $DestinationLocation -Source $SourceLocation -Controller $myController -Confirm:$False"
            $out=Remove-NcSnapmirror -Destination $DestinationLocation -Source $SourceLocation -Controller $myController  -ErrorVariable ErrorVar -Confirm:$False   
            if ( $? -ne $True ) 
            {
                $Return = $False ; throw "ERROR: Remove-NcSnapmirror failed"
            }

        }
	}
} Catch {
    handle_error $_ $myPrimaryVserver
}
    Write-LogDebug "break_snapmirror_vserver_dr: end"
	return $Return 
}

#############################################################################################
Function migrate_lif (
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
	[string] $mySecondaryVserver) {
try{    
    $Return = $True

    $myPrimaryCluster = (Get-NcCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar).ClusterName			
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }
	$mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar).ClusterName			
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }

	Write-LogDebug "migrate_lif: start"
    Write-LogDebug "Get lif available on [$mySecondaryVserver]"
    Write-LogDebug "Get-NcNetInterface -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
    $availableLIF=Get-NcNetInterface -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
    if ( $? -ne $True ) 
    {
        $Return = $False ; throw "ERROR: Get-NcNetInterface failed [$ErrorVar]"
    }
    foreach ( $LIF in ( $availableLIF | Skip-Null ) ) 
    {
        $LIFname=$LIF.InterfaceName
        Write-LogDebug "Get LIF information from [$myPrimaryVserver]"
        Write-LogDebug "Get-NcNetInterface -Name $LIFName -VserverContext $myPrimaryVserver -Controller $myPrimaryController"
        $LIFinformation=Get-NcNetInterface -Name $LIFName -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) 
        {
            $Return = $False ; throw "ERROR: Get-NcNetInterface failed [$ErrorVar]"
        }
        if($LIFinformation -ne $null){
            $LIFaddress=$LIFinformation.Address
            $LIFnetmask=$LIFinformation.Netmask
            Write-Log "[$mySecondaryVserver] Set [$LIFname] down on [$myPrimaryVserver]"
            Write-LogDebug "Set-NcNetInterface -Name $LIFname -AdministrativeStatus down -Vserver $myPrimaryVserver -Controller $myPrimaryController"
            $out=Set-NcNetInterface -Name $LIFname -AdministrativeStatus down -Vserver $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) 
            {
                $Return = $False ; throw "ERROR: Set-NcNetInterface failed [$ErrorVar]"
            }
            Write-Log "[$mySecondaryVserver] Set [$LIFname] up with address [$LIFaddress] and netmask [$LIFnetmask] on [$mySecondaryVserver]"
            Write-LogDebug "Set-NcNetInterface -Name $LIFname -AdministrativeStatus up -Vserver $mySecondaryVserver -Controller $mySecondaryController"
            $out=Set-NcNetInterface -Name $LIFname -Address $LIFaddress -Netmask $LIFnetmask -AdministrativeStatus up -Vserver $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True )
            {
                $Return = $False ; throw "ERROR: Set-NcNetInterface failed [$ErrorVar]"    
            }
        }
    }
    Write-LogDebug "Get Default route on [$myPrimaryVserver]"
    Write-LogDebug "Get-NcNetRoute -Query @{Destination=0.0.0.0/0;Vserver=$myPrimaryVserver} -Controller $myPrimaryController"
    $defaultPrimaryRoute=Get-NcNetRoute -Query @{Destination="0.0.0.0/0";Vserver=$myPrimaryVserver} -Controller $myPrimaryController  -ErrorVariable ErrorVar
    if ( $? -ne $True )
    {
        $Return = $False ; throw "ERROR: Get-NcNetRoute failed [$ErrorVar]"    
    }
    Write-LogDebug "Get Default route on [$mySecondaryVserver]"
    Write-LogDebug "Get-NcNetRoute -Query @{Destination=0.0.0.0/0;Vserver=$mySecondaryVserver} -Controller $mySecondaryController"
    $defaultSecondaryRoute=Get-NcNetRoute -Query @{Destination="0.0.0.0/0";Vserver=$mySecondaryVserver} -Controller $mySecondaryController  -ErrorVariable ErrorVar
    if ( $? -ne $True )
    {
        $Return = $False ; throw "ERROR: Get-NcNetRoute failed [$ErrorVar]"    
    }
    $PrimaryGW=$defaultPrimaryRoute.Gateway
    $PrimaryMetric=$defaultPrimaryRoute.Metric
    $SecondaryGW=$defaultSecondaryRoute.Gateway
    if($PrimaryGW -ne $SecondaryGW){
        Write-LogDebug "Add Primary Gateway [$PrimaryGW] on [$mySecondaryVserver]"
        Write-LogDebug "New-NcNetRoute -Destination 0.0.0.0/0 -Gateway $PrimaryGW -Metric $PrimaryMetric -vserverContext $mySecondaryVserver -Controller $mySecondaryController"
        $out=New-NcNetRoute -Destination "0.0.0.0/0" -Gateway $PrimaryGW -Metric $PrimaryMetric -vserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcNetRoute failed [$ErrorVar]" }
        Write-LogDebug "Remove Secondary Gateway [$SecondaryGW] on [$mySecondaryVserver]"
        Write-LogDebug "Remove-NcNetRoute -Destination 0.0.0.0/0 -Gateway $SecondaryGW -VserverContext $mySecondaryVserver -controller $mySecondaryController"
        $out=Remove-NcNetRoute -Destination 0.0.0.0/0 -Gateway $SecondaryGW -VserverContext $mySecondaryVserver -controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
    }
} 
Catch {
    handle_error $_ $myPrimaryVserver
}
    Write-LogDebug "migrate_lif: end"
	return $Return 
}

#############################################################################################
Function migrate_cifs_server (
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
	[string] $mySecondaryVserver,
    [switch] $NoInteractive) {
try{    
    $Return = $True
    Write-LogDebug "migrate_cifs_server: start"
    $myPrimaryCluster = (Get-NcCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar).ClusterName			
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }
	$mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar).ClusterName			
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }

    Write-LogDebug "Get-NcCifsServer -VserverContext $myPrimaryVserver -Controller $myPrimaryController"
	$serverExist=Get-NcCifsServer -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsServer failed [$ErrorVar]" }
    if($serverExist -eq $null){Write-LogDebug "No CIFS server, skip"; return $Return}
    else{
        if($NotInteractive -eq $False){
            $ANS=Read-HostOptions "Set CIFS server down on [$myPrimaryVserver]. Do you want to continue ?" "y/n"
            if($ANS -ne 'y'){Write-LogDebug "Exit Migrate CIFS server: Not ready";return $False}
        }
        Write-LogDebug "Get-NcCifsServer -VserverContext $myPrimaryVserver -Controller $myPrimaryController"
        $PrimaryCIFSserver=Get-NcCifsServer -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
        $PrimaryCIFSidentity=$PrimaryCIFSserver.CIFSServer
        $PrimaryCIFSdomain=$PrimaryCIFSserver.Domain
        $ADCred=get_local_cred($PrimaryCIFSdomain)
        Write-Log "Set CIFS server down on [$myPrimaryVserver]"
        Write-LogDebug "Set-NcCifsServer -AdministrativeStatus down -Domain $PrimaryCIFSdomain -AdminCredential $ADCred -VserverContext $myPrimaryVserver -controller $myPrimaryController"
        $out=Set-NcCifsServer -AdministrativeStatus down -Domain $PrimaryCIFSdomain -AdminCredential $ADCred -VserverContext $myPrimaryVserver -controller $myPrimaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcCifsServer failed [$ErrorVar]" }
        Write-Log "Set CIFS server up on [$mySecondaryVserver] with identity of [$myPrimaryVserver] : [$PrimaryCIFSidentity]"
        Write-LogDebug "Set-NcCifsServer -AdministrativeStatus up -ForceAccountOverwrite -CifsServer $PrimaryCIFSidentity -Domain $PrimaryCIFSdomain -AdminCredential $ADCred -VserverContext $mySecondaryVserver -controller $mySecondaryController"
        $out=Set-NcCifsServer -AdministrativeStatus up -ForceAccountOverwrite -CifsServer $PrimaryCIFSidentity -Domain $PrimaryCIFSdomain -AdminCredential $ADCred -VserverContext $mySecondaryVserver -controller $mySecondaryController  -ErrorVariable ErrorVar  -Confirm:$False
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcCifsServer failed [$ErrorVar]" }
    }

} Catch {
    handle_error $_ $myPrimaryVserver
}
    Write-LogDebug "migrate_cifs_server: end"
	return $Return 
}

#############################################################################################
Function update_cifs_usergroup (
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
	[string] $mySecondaryVserver,
    [switch] $NoInteractive,
    [string]$workOn=$mySecondaryVserver,
    [bool]$Backup,
    [bool]$Restore) {
try{    
    $Return = $True
    $RunBackup=$False
    $RunRestore=$False
    Write-Log "[$workOn] Update CIFS Local User & Local Group"
    Write-LogDebug "update_cifs_usergroup[$myPrimaryVserver]: start"
    if($Backup -eq $True){Write-LogDebug "run in Backup mode [$myPrimaryVserver]";$RunBackup=$True}
    if($Restore -eq $True){Write-LogDebug "run in Restore mode [$myPrimaryVserver]";$RunRestore=$True}
    if(-not (check_update_CIFS_server_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -workOn $mySecondaryVserver -Backup $RunBackup -Restore $RunRestore)){
        Write-LogDebug "update_cifs_usergroup: end"
        return $True
    }
    Write-LogDebug "[$workOn] Set Lif up to authenticate user" 
    Write-LogDebug "[$workOn] Get-NcCifsLocalUser -VserverContext $mySecondaryVserver -controller $mySecondaryController"
    if($Restore -eq $False){
        Write-LogDebug "Get-NcCifsServer -VserverContext $myPrimaryVserver -controller $myPrimaryController"
        $PrimaryCifs=Get-NcCifsServer -VserverContext $myPrimaryVserver -controller $myPrimaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsServer failed [$ErrorVar]" }
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcCifsServer.json")){
            $PrimaryCifs=Get-Content $($Global:JsonPath+"Get-NcCifsServer.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcCifsServer.json")
            Throw "ERROR: failed to read $filepath"
        }
    }
    if($Backup -eq $False){
        $SecondaryUserList=Get-NcCifsLocalUser -VserverContext $mySecondaryVserver -controller $mySecondaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsLocalUser failed [$ErrorVar]" }
    }
    $UserKeeped=@()
    $PrimaryCifsServer=$PrimaryCifs.CifsServer
    if($Backup -eq $False){
        Write-LogDebug "Get-NcCifsServer -VserverContext $mySecondaryVserver -controller $mySecondaryController"
        $SecondaryCifs=Get-NcCifsServer -VserverContext $mySecondaryVserver -controller $mySecondaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsServer failed [$ErrorVar]" }
        $SecondaryCifsServer=$SecondaryCifs.CifsServer
        foreach($SecondaryUser in $SecondaryUserList | Skip-Null){
            $SecondaryUserName=$SecondaryUser.UserName
            try {
                $global:mutexconsole.WaitOne(200) | Out-Null
            }
            catch [System.Threading.AbandonedMutexException]{
                #AbandonedMutexException means another thread exit without releasing the mutex, and this thread has acquired the mutext, therefore, it can be ignored
                Write-Host -f Red "catch abandoned mutex for [$myPrimaryVserver]"
                free_mutexconsole
            }
            try{
                $ans='n'
                if($NoInteractive -eq $False){
                    $ans=Read-HostOptions "[$mySecondaryVserver] Do you want to reset Password for User [$SecondaryUserName] on [$mySecondaryVserver]?" "y/n"
                }
                if($ans -eq 'n'){
                    if($PrimaryCifsServer -ne $SecondaryCifsServer){$SecondaryUserName=$SecondaryUserName -replace $SecondaryCifsServer,$PrimaryCifsServer}
                    $UserKeeped+=$SecondaryUserName
                }else{
                    Write-LogDebug "Remove-NcCifsLocalUser -UserName $SecondaryUserName -VserverContext $mySecondaryVserver -controller $mySecondaryController"
                    try{
                        $out=Remove-NcCifsLocalUser -UserName $SecondaryUserName -VserverContext $mySecondaryVserver -controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False -EA stop
                        if ( $? -ne $True ) { Write-LogDebug "ERROR: Remove-NcCifsLocalUser failed [$ErrorVar]" }
                    }catch{
                        $ErrorMessage = $_.Exception.Message
                        $ErrorDetails = $_.ErrorDetails
                        Write-LogDebug "[$mySecondaryVserver] failed to delete Cifs Local User [$ErrorMessage : $ErrorDetails]"
                    }
                }
            }catch{
                Write-LogDebug "Cannot remove local CIFS user [$SecondaryUserName] on [$mySecondaryVserver]"
            }
            free_mutexconsole 
        }
    }
    if($Restore -eq $False){
        Write-LogDebug "Get-NcCifsLocalUser -VserverContext $myPrimaryVserver -controller $myPrimaryController"
        $PrimaryUserList=Get-NcCifsLocalUser -VserverContext $myPrimaryVserver -controller $myPrimaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsLocalUser failed [$ErrorVar]" }
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcCifsLocalUser.json")){
            $PrimaryUserList=Get-Content $($Global:JsonPath+"Get-NcCifsLocalUser.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcCifsLocalUser.json")
            Throw "ERROR: failed to read $filepath"
        }
    }
    if($Backup -eq $True){
        $PrimaryUserList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcCifsLocalUser.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcCifsLocalUser.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcCifsLocalUser.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcCifsLocalUser.json")"
            $Return=$False
        }
    }
    if($Backup -eq $False){
        foreach($User in $PrimaryUserList | Where-Object {$_.UserName -notin $UserKeeped} | Skip-Null){
            $UserName=$User.UserName

            $UserDisabled=$User.Disabled
            $UserDescription=$User.Description
            $UserFullname=$User.FullName
            if($PrimaryCifsServer -ne $SecondaryCifsServer){$UserName=$UserName -replace $PrimaryCifsServer,$SecondaryCifsServer}
            if($UserFullname.length -eq 0 -or $UserFullname.count -eq 0){$UserFullname=""}
            if(($UserDescription -match "Built-in") -eq $True){
                write-logdebug "Get-NcCifsLocalUser -VserverContext $mySecondaryVserver -controller $mySecondaryController"
                $SecondaryBuiltin=Get-NcCifsLocalUser -VserverContext $mySecondaryVserver -controller $mySecondaryController -ErrorVariable ErrorVar | Where-Object {$_.Description -match "Built-in"}
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsLocalUser failed [$ErrorVar]" }
                $UserName=$SecondaryBuiltin.UserName
                try {
                    $global:mutexconsole.WaitOne(200) | Out-Null
                }
                catch [System.Threading.AbandonedMutexException]{
                    #AbandonedMutexException means another thread exit without releasing the mutex, and this thread has acquired the mutext, therefore, it can be ignored
                    Write-Host -f Red "catch abandoned mutex for [$myPrimaryVserver]"
                    free_mutexconsole
                }
                do{
                    $modok=$True
                    Write-Log "[$workOn] CIFS Local User [$UserName]"
                    if($Global:DefaultPass -eq $True){
                        $pass1=ConvertTo-SecureString $Global:TEMPPASS -AsPlainText -Force
                        Write-Log "[$workOn] Set default password for user [$UserName]. Change it asap"  
                    }else{
                        do{
                            $ReEnter=$False
                            $pass1=Read-Host "[$workOn] Please enter Password for CIFS Local User [$UserName]" -AsSecureString
                            $pass2=Read-Host "[$workOn] Confirm Password for CIFS Local User [$UserName]" -AsSecureString
                            $pwd1_text = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass1))
                            $pwd2_text = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass2))
        
                            if ($pwd1_text -ceq $pwd2_text) {
                                Write-LogDebug "Passwords matched"
                            } 
                            else{
                                Write-Warning "[$workOn] Error passwords does not match. Please Re-Enter"
                                $ReEnter=$True
                            }
                        }while($ReEnter -eq $True)
                    }
                    $password=$pass1
                    try{
                        Write-LogDebug "Set-NcCifsLocalUser -UserName $UserName -Password XXXXXXXXXX -VserverContext $mySecondaryVserver -controller $mySecondaryController"
                        $out=Set-NcCifsLocalUser -UserName $UserName -Password $password -VserverContext $mySecondaryVserver -controller $mySecondaryController  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; free_mutexconsole;throw "ERROR: Set-NcCifsLocalUser failed [$ErrorVar]" }
                        Write-LogDebug "Set-NcCifsLocalUser -UserName $UserName -FullName $UserFullname -Description $UserDescription -IsAccountDisable $UserDisabled -VserverContext $mySecondaryVserver -controller $mySecondaryController"
                        $out=Set-NcCifsLocalUser -UserName $UserName -FullName $UserFullname -Description $UserDescription -IsAccountDisable $UserDisabled -VserverContext $mySecondaryVserver -controller $mySecondaryController  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; free_mutexconsole;throw "ERROR: Set-NcCifsLocalUser failed [$ErrorVar]" }
                    }catch{
                        Write-Warning "[$workOn] Impossible to modify CIFS local user [$UserName] on [$mySecondaryVserver] reason [$_.Description]"
                        $modok=$False
                    }
                }while($modok -eq $False)
                free_mutexconsole
            }else{
                try {
                    $global:mutexconsole.WaitOne(200) | Out-Null
                }
                catch [System.Threading.AbandonedMutexException]{
                    #AbandonedMutexException means another thread exit without releasing the mutex, and this thread has acquired the mutext, therefore, it can be ignored
                    Write-Host -f Red "catch abandoned mutex for [$workOn]"
                    free_mutexconsole
                }
                do{
                    $addok=$true
                    Write-Log "[$workOn] Please Enter password for CIFS Local User [$UserName]"
                    if($Global:DefaultPass -eq $True){
                        $pass1=ConvertTo-SecureString $Global:TEMPPASS -AsPlainText -Force
                        Write-Log "[$workOn] Set default password for user [$UserName]. Change it asap" 
                    }else{
                        do{
                            $ReEnter=$false
                            $pass1=Read-Host "[$workOn] Please enter Password for CIFS Local User [$UserName]" -AsSecureString
                            $pass2=Read-Host "[$workOn] Confirm Password for CIFS Local User [$UserName]" -AsSecureString
                            $pwd1_text = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass1))
                            $pwd2_text = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass2))
        
                            if ($pwd1_text -ceq $pwd2_text) {
                                Write-LogDebug "Passwords matched"
                            } 
                            else{
                                Write-Warning "[$workOn] Error passwords does not match. Please Re-Enter"
                                $ReEnter=$True
                            }
                        }while($ReEnter -eq $True)
                    }
                    $password=$pass1
                    if($UserDisabled -eq $True){
                        try{
                            Write-LogDebug "New-NcCifsLocalUser -UserName $UserName -Password XXXXXXXXXX -FullName $UserFullname -Description $UserDescription -Disable -VserverContext $mySecondaryVserver -controller $mySecondaryController"
                            $out=New-NcCifsLocalUser -UserName $UserName -Password $password -FullName $UserFullname -Description $UserDescription -Disable -VserverContext $mySecondaryVserver -controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; free_mutexconsole;throw "ERROR: New-NcCifsLocalUser failed [$ErrorVar]" }
                        }catch{
                            Write-Warning "[$workOn] Impossible to create new CIFS local user [$UserName] on [$mySecondaryVserver] reason [$ErrorVar]"
                            $addok=$false
                        }
                    }else{
                        try{
                            Write-LogDebug "New-NcCifsLocalUser -UserName $UserName -Password XXXXXXXXXX -FullName $UserFullname -Description $UserDescription -VserverContext $mySecondaryVserver -controller $mySecondaryController"
                            $out=New-NcCifsLocalUser -UserName $UserName -Password $password -FullName $UserFullname -Description $UserDescription -VserverContext $mySecondaryVserver -controller $mySecondaryController  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; free_mutexconsole;throw "ERROR: New-NcCifsLocalUser failed [$ErrorVar]" }
                        }catch{
                            Write-Warning "[$workOn] Impossible to create new CIFS local user [$UserName] on [$mySecondaryVserver] reason [$ErrorVar]"
                            $addok=$false
                        }
                    }
                }while($addok -eq $false)
                free_mutexconsole
            }

        }
    }
    if($Backup -eq $False){
        Write-LogDebug "Get-NcCifsLocalGroup -VserverContext $mySecondaryVserver -controller $mySecondaryController"
        $SecondaryGroupList=Get-NcCifsLocalGroup -VserverContext $mySecondaryVserver -controller $mySecondaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsLocalGroup failed [$ErrorVar]" }
        foreach($SecondaryGroup in $SecondaryGroupList | Skip-Null){
            $SecondaryGroupName=$SecondaryGroup.GroupName
            $notremoved=$False
            try{
                Write-LogDebug "Remove-NcCifsLocalGroup -GroupName $SecondaryGroupName -VserverContext $mySecondaryVserver -controller $mySecondaryController"
                $out=Remove-NcCifsLocalGroup -GroupName $SecondaryGroupName -VserverContext $mySecondaryVserver -Controller $mySecondaryController -ErrorAction SilentlyContinue -ErrorVariable ErrorVar -Confirm:$False
                if ( $? -ne $True ) { 
                    Write-LogDebug "ERROR: Remove-NcCifsLocalGroup failed [$ErrorVar]" 
                    if(($ErrorVar | Out-String) -match "Cannot delete the BUILTIN group"){$notremoved=$True}
                }
            }catch{
                Write-LogDebug "Group [$SecondaryGroupName] not remove from [$mySecondaryVserver], reason [$ErrorVar]"
                $notremoved=$True
            }
            if($notremoved -eq $True){
                Write-LogDebug "Get-NcCifsLocalGroupMember -Name $SecondaryGroupName -VserverContext $mySecondaryVserver -controller $mySecondaryController"
                $SecondaryMemberList=Get-NcCifsLocalGroupMember -Name $SecondaryGroupName -VserverContext $mySecondaryVserver -controller $mySecondaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsLocalGroupMermber failed [$ErrorVar]" }
                foreach($SecondaryMember in $SecondaryMemberList | Skip-Null){
                    $SecondaryMemberName=$SecondaryMember.Member
                    try{
                        Write-LogDebug "Remove-NcCifsLocalGroupMember -Name $SecondaryGroupName -Member $SecondaryMemberName -VserverContext $mySecondaryVserver -controller $mySecondaryController"
                        $out=Remove-NcCifsLocalGroupMember -Name $SecondaryGroupName -Member $SecondaryMemberName -VserverContext $mySecondaryVserver -controller $mySecondaryController -ErrorAction SilentlyContinue -ErrorVariable ErrorVar -Confirm:$False
                        if ( $? -ne $True ) { Write-LogDebug "ERROR: Remove-NcCifsLocalGroupMember failed [$ErrorVar]" }
                    }catch{
                        Write-LogDebug "unable to remove Member [$SecondaryMemberName] from [$SecondaryGroupName] on [$mySecondaryVserver]"
                    }
                }        
            }
        }
    }
    if($Restore -eq $False){
        Write-LogDebug "Get-NcCifsLocalGroup -VserverContext $myPrimaryVserver -controller $myPrimaryController"
        $PrimaryGroupList=Get-NcCifsLocalGroup -VserverContext $myPrimaryVserver -controller $myPrimaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsLocalGroup failed [$ErrorVar]" }
    }else{
        if(Test-Path $($Global:JsonPath+"Get-NcCifsLocalGroup.json")){
            $PrimaryGroupList=Get-Content $($Global:JsonPath+"Get-NcCifsLocalGroup.json") | ConvertFrom-Json
        }else{
            $Return=$False
            $filepath=$($Global:JsonPath+"Get-NcCifsLocalGroup.json")
            Throw "ERROR: failed to read $filepath"
        }
    }
    if($Backup -eq $True){
        $PrimaryGroupList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcCifsLocalGroup.json") -Encoding ASCII -Width 65535
        if( ($ret=get-item $($Global:JsonPath+"Get-NcCifsLocalGroup.json") -ErrorAction SilentlyContinue) -ne $null ){
            Write-LogDebug "$($Global:JsonPath+"Get-NcCifsLocalGroup.json") saved successfully"
        }else{
            Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcCifsLocalGroup.json")"
            $Return=$False
        }
        foreach($PrimaryGroup in $PrimaryGroupList | Skip-Null){
            $PrimaryGroupName=$PrimaryGroup.GroupName
            Write-LogDebug "Get-NcCifsLocalGroupMember -Name $PrimaryGroupName -VserverContext $myPrimaryVserver -controller $myPrimaryController"
            $PrimaryMemberList=Get-NcCifsLocalGroupMember -Name $PrimaryGroupName -VserverContext $myPrimaryVserver -controller $myPrimaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsLocalGroupMermber failed [$ErrorVar]" }
            $PrimaryGroupName_string=$PrimaryGroupName -replace "\\","_"
            $PrimaryMemberList | ConvertTo-Json -Depth 5 | Out-File -FilePath $($Global:JsonPath+"Get-NcCifsLocalGroupMember-"+$PrimaryGroupName_string+".json") -Encoding ASCII -Width 65535
            if( ($ret=get-item $($Global:JsonPath+"Get-NcCifsLocalGroupMember-"+$PrimaryGroupName_string+".json") -ErrorAction SilentlyContinue) -ne $null ){
                Write-LogDebug "$($Global:JsonPath+"Get-NcCifsLocalGroupMember-"+$PrimaryGroupName_string+".json") saved successfully"
            }else{
                Write-LogError "ERROR: Failed to saved $($Global:JsonPath+"Get-NcCifsLocalGroupMember-"+$PrimaryGroupName_string+".json")"
                $Return=$False
            }
        }
    }
    if($Backup -eq $False){
        foreach($PrimaryGroup in $PrimaryGroupList | Skip-Null){
            $PrimaryGroupName=$PrimaryGroup.GroupName
            $PrimaryGroupDescription=$PrimaryGroup.Description
            Write-LogDebug "Get-NcCifsLocalGroup -Name $PrimaryGroupName -VserverContext $mySecondaryVserver -controller $mySecondaryController"
            $SecondaryGroup=Get-NcCifsLocalGroup -Name $PrimaryGroupName -VserverContext $mySecondaryVserver -controller $mySecondaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsLocalGroup failed [$ErrorVar]" }
            if($SecondaryGroup -eq $null){
                try{
                    Write-LogDebug "New-NcCifsLocalGroup -Name $PrimaryGroupName -Descritption $PrimaryGroupDescription -VserverContext $mySecondaryVserver -controller $mySecondaryController" 
                    $out=New-NcCifsLocalGroup -Name $PrimaryGroupName -Descritption $PrimaryGroupDescription -VserverContext $mySecondaryVserver -controller $mySecondaryController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { Write-LogDebug "ERROR: New-NcCifsLocalGroup failed [$ErrorVar]" }
                }catch{
                    Write-LogDebug "Cannot create Group [$PrimaryGroupName] on [$mySecondaryVserver], reason [$ErrorVar]"
                }
            }
            if($Restore -eq $False){
                Write-LogDebug "Get-NcCifsLocalGroupMember -Name $PrimaryGroupName -VserverContext $myPrimaryVserver -controller $myPrimaryController"
                $PrimaryMemberList=Get-NcCifsLocalGroupMember -Name $PrimaryGroupName -VserverContext $myPrimaryVserver -controller $myPrimaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsLocalGroupMermber failed [$ErrorVar]" }
            }else{
                $PrimaryGroupName_string=$PrimaryGroupName -replace "\\","_"
                if(Test-Path $($Global:JsonPath+"Get-NcCifsLocalGroupMember-"+$PrimaryGroupName_string+".json")){
                    $PrimaryMemberList=Get-Content $($Global:JsonPath+"Get-NcCifsLocalGroupMember-"+$PrimaryGroupName_string+".json") | ConvertFrom-Json
                }else{
                    $Return=$False
                    $filepath=$($Global:JsonPath+"Get-NcCifsLocalGroupMember-"+$PrimaryGroupName_string+".json")
                    Throw "ERROR: failed to read $filepath"
                }    
            }
            foreach($PrimaryMember in $PrimaryMemberList | Skip-Null){
                $PrimaryMemberName=$PrimaryMember.Member
                if($PrimaryCifsServer -ne $SecondaryCifsServer){$PrimaryMemberName=$PrimaryMemberName -replace $PrimaryCifsServer,$SecondaryCifsServer}
                try{
                    Write-LogDebug "Add-NcCifsLocalGroupMember -Name $PrimaryGroupName -Member $PrimaryMemberName -VserverContext $mySecondaryVserver -controller $mySecondaryController"
                    $out=Add-NcCifsLocalGroupMember -Name $PrimaryGroupName -Member $PrimaryMemberName -VserverContext $mySecondaryVserver -controller $mySecondaryController -ErrorAction SilentlyContinue -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { Write-LogDebug "ERROR: Add-NcCifsLocalGroupMember failed [$ErrorVar]" }
                }catch{
                    Write-LogDebug "Member [$PrimaryMemberName] already exist in [$PrimaryGroupName] on [$mySecondaryVserver]"
                }
            }   
    
        }
    }
    Write-LogDebug "update_cifs_usergroup[$myPrimaryVserver]: end"
    return $True
} Catch {
    handle_error $_ $myPrimaryVserver
}
    Write-LogDebug "update_cifs_usergroup: end"
	return $Return 
}

#############################################################################################
Function update_vserver_dr (
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
	[string] $mySecondaryVserver,
    [bool] $DDR,
    [boolean] $UseLastSnapshot ) {
	$Return = $True
	Write-LogDebug "update_vserver_dr: start"
	if ( ( check_update_vserver -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) { Write-LogError "ERROR: Failed check update vserver" ; return $False }
	if ( $Global:DataAggr.length -gt 1 ) {
		Write-LogDebug "update_vserver_dr: Create required new volumes $mySecondaryController Vserver $Vserver"
		if ( ( create_volume_voldr -NoInteractive -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) { Write-LogError "ERROR: Failed to create all volumes" ; return $False }

		Write-LogDebug "update_vserver_dr: Create required new snapmirror relations $mySecondaryController Vserver $Vserver"
		if ( ( create_snapmirror_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -DDR $DDR ) -ne $True ) { Write-LogError "ERROR: Failed to create all snapmirror relations " ; return $False }

		Write-LogDebug "update_vserver_dr: Wait new Snapmirror transfer terminate $mySecondaryController Vserver $Vserver"
		if ( ( wait_snapmirror_dr -NoInteractive -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) { Write-LogError "ERROR: Failed snapmirror relations bad status " ; return $False }
	}
	Write-LogDebug "update_vserver_dr: Update Snapmirror Controller $mySecondaryController Vserver $Vserver"
	if ( ( update_snapmirror_vserver -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -UseLastSnapshot $UseLastSnapshot ) -ne $True ) {
		Write-LogError "ERROR: update_snapmirror_vserver failed" 
		return  $False
	}
	Write-LogDebug "update_vserver_dr: Update igroup"
	if ( ( create_update_igroupdr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) {
		Write-LogError "ERROR: create_update_igroupdr failed" 
		$Return = $False
	}
	Write-LogDebug "update_vserver_dr: Update policy"
	if ( ( create_update_policy_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver )  -ne $True ) {
		Write-LogError "ERROR: create_update_policy_dr failed" 
		$Return = $False
	}
    Write-LogDebug "update_vserver_dr: Update efficiency policy"
	if ( ( create_update_efficiency_policy_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver )  -ne $True ) {
		Write-LogError "ERROR: create_update_efficiency_policy_dr failed" 
		$Return = $False
	}
    Write-LogDebug "update_vserver_dr: Update firewall policy"
    if ( ( create_update_firewallpolicy_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver) -ne $True ) { 
        Write-LogError "ERROR: Failed to create all Firewall policy" 
        $Return = $False 
    }
    #Write-LogDebug "update_vserver_dr: Update lif dr"
	#if ( ( create_lif_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) {
    #    Write-LogError "ERROR: create_lif_dr failed" 
	#	$Return = $True
    #}
    #Write-LogDebug "update_vserver_dr: Update local user dr"
    #if ( ( create_update_localuser_dr  -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) { 
    #    Write-LogError "ERROR: Failed to create all LIF"
    #    $Return = $True 
    #}
    Write-LogDebug "update_vserver_dr: Update local Unix User & Group"
    if ( ( create_update_localunixgroupanduser_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) { 
        Write-LogError "ERROR: Failed to create all Local Unix User and Group"
        $Return = $True 
    }
    if ( ( create_update_usermapping_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) { 
        Write-LogError "ERROR: Failed to create User Mapping"
        $Return = $True
    }
    Write-LogDebug "update_vserver_dr: Update Vscan dr"
	if ( ( create_update_vscan_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) { 
        Write-LogError "ERROR: create_update_vscan_dr failed" 
        $Return = $False 
    }
    Write-LogDebug "update_vserver_dr: Update Fpolicy dr"
	if ( ( create_update_fpolicy_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) { 
        Write-LogError "ERROR: create_update_fpolicy_dr failed" 
        $Return = $False 
    }
	Write-LogDebug "update_vserver_dr: Check Destination Volumes"
	if ( ( check_update_voldr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) {
		Write-LogError "ERROR: check_update_voldr failed" 
		$Return = $False
	}
	Write-LogDebug "update_vserver_dr: mount all volume"
	if ( ( mount_voldr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) {
		Write-LogError "ERROR: mount_voldr Failed failed" 
		$Return = $False
	}
	if ( ( create_update_DNS_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) { 
		Write-LogError "ERROR: create_update_DNS_dr failed" 
		$Return = $False 
	}
	if ( ( create_update_NIS_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) { 
		Write-LogError "ERROR: create_update_NIS_dr failed" 
		$Return = $False 
	}
	if ( ( create_update_NFS_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) {
		Write-LogError "ERROR: create_update_NFS_dr failed" 
		$Return = $False 
	}
	if ( ( create_update_ISCSI_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) {
		Write-LogError "ERROR: create_update_ISCSI_dr failed" 
		$Return = $False 
	}
	if ( ( create_update_CIFS_shares_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) {
		Write-LogError "ERROR: create_update_CIFS_share failed" 
		$Return = $False 
	}
	if ( ( map_lundr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) { 
		Write-LogError "ERROR: Failed to map all LUNs failed" 
		$Return = $False 
	}
	if ( ( set_serial_lundr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) { 
		Write-Log "ERROR: Failed to change LUN serial Numbers"  
		$Return = $False 
	}
    if ( ( create_update_qospolicy_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) { 
        Write-LogError "ERROR: create_update_qospolicy_dr"
        $Return = $False 
    }
    if ( ( create_update_role_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver) -ne $True ) {
		Write-LogError "ERROR: create_update_role_dr"
	}
    if ( ( $ret=update_qtree_export_policy_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) {Write-Log "ERROR Failed to modify all Qtree Export Policy" ; $Return = $False}
    Write-LogDebug "update_vserver_dr: end"
	return $Return
}

#############################################################################################
Function disable_network_protocol_vserver_dr (
	[NetApp.Ontapi.Filer.C.NcController] $myController,
	[string] $myVserver ) {
Try {

	$Return = $True	

	Write-LogDebug "disable_network_protocol_vserver_dr: start"

	$ANS=Read-HostOptions "Ready to disable all Network Services in SVM [$myVserver] from  cluster [$myController] ?" "y/n"
	if ( $ANS -ne 'y' ) {
		return $Return
	}
	
	$Return = $True
	
	# Verify if ISCSI service is Running if yes the stop it
	$IscsiService = Get-NcIscsiService -VserverContext  $myVserver -Controller $myController  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcIscsiService failed [$ErrorVar]" }
	if ( $IscsiService -eq $null ) {
		Write-Log "[$myVserver] No ISCSI services in vserver"
	} else {
		if ( $IscsiService.IsAvailable -eq $True ) {
			Write-LogDebug "Disable-NcIscsi -VserverContext $myVserver -Controller $myController -Confirm:$False"
			$out=Disable-NcIscsi -VserverContext $myVserver -Controller $myController  -ErrorVariable ErrorVar -Confirm:$False
			if ( $? -ne $True ) {
				Write-LogError "ERROR: Failed to disable iSCSI on Vserver [$myVserver]" 
				$Return = $False
			}
		}
		
	}
	
	# Verify if NFS service is Running if yes the stop it
	$NfsService = Get-NcNfsService -VserverContext  $myVserver -Controller $myController  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNfsService failed [$ErrorVar]" }
	if ( $NfsService -eq $null ) {
		Write-Log "[$myVserver] No NFS services in vserver"
	} else {
		if ( $NfsService.GeneralAccess -eq $True ) {
			Write-LogDebug "Disable-NcNfs -VserverContext $myVserver -Controller $myController -Confirm:$False"
			$out=Disable-NcNfs -VserverContext $myVserver -Controller $myController  -ErrorVariable ErrorVar -Confirm:$False
			if ( $? -ne $True ) {
				Write-LogError "ERROR: Failed to disable NFS on Vserver [$myVserver]" 
				$Return = $False
			}
		}
		
	}
	
	# Verify if CIFS Service is Running if yes stop it
	$CifService = Get-NcCifsServer  -VserverContext  $myVserver -Controller $myController  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsServer failed [$ErrorVar]" }
	if ( $CifService -eq $null ) {
		Write-Log "[$myVserver] No CIFS services in vserver"
	} else {
		if ( $CifService.AdministrativeStatus -eq 'up' ) {
			Write-LogDebug "stop-NcCifsServer -VserverContext $myVserver -Controller $myController -Confirm:$False"
			$out=Stop-NcCifsServer -VserverContext $myVserver -Controller $myController  -ErrorVariable ErrorVar -Confirm:$False
			if ( $? -ne $True ) {
				Write-LogError "ERROR: Failed to disable CIFS on Vserver [$myVserver]" 
				$Return = $False
			}
		}
	}
	
	# Stop All NetWork Interface
	$InterfaceList = Get-NcNetInterface -Role DATA -VserverContext $myVserver -Controller $myController  -ErrorVariable ErrorVar 
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNetInterface failed [$ErrorVar]" }
	foreach ( $Interface in ( $InterfaceList | Skip-Null ) ) {
			$InterfaceName=$Interface.InterfaceName
			$PrimaryFirewallPolicy=$Interface.FirewallPolicy
			$PrimaryDataProtocols=$Interface.DataProtocols
			if ( ( $PrimaryFirewallPolicy -eq "mgmt" ) -and ( $PrimaryDataProtocols -eq "none" ) ) {
				Write-LogDebug "Interface [$InterfaceName] is a management Interface must not be down"
			} else {
				Write-LogDebug "Set-NcNetInterface  -Name $InterfaceName -AdministrativeStatus down -Vserver $myVserver -Controller $myController"
				$out = Set-NcNetInterface -Name $InterfaceName -AdministrativeStatus down -Vserver $myVserver -Controller $myController  -ErrorVariable ErrorVar
			}
			if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcNetInterface failed [$ErrorVar]" }
			if ( $? -ne $True ) { 
				Write-LogError "ERROR: Failed to start stop interface [$InterfaceName] " 
				$Return = $False 
			}
	}
    Write-LogDebug "disable_network_protocol_vserver_dr: end"
	return $Return 
}
Catch {
    handle_error $_ $myVserver
	return $Return
}
}
#############################################################################################
Function enable_network_protocol_vserver_dr (
	[NetApp.Ontapi.Filer.C.NcController] $myController,
	[string] $myVserver ) {
Try {
	$Return = $True
    Write-logDebug "enable_network_protocol_vserver_dr: start"
	# Start all Network Interfaces
	$InterfaceList = Get-NcNetInterface -Role DATA -VserverContext $myVserver -Controller $myController  -ErrorVariable ErrorVar 
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNetInterface failed [$ErrorVar]" }
	foreach ( $Interface in ( $InterfaceList | Skip-Null ) ) {
			$InterfaceName=$Interface.InterfaceName
			Write-LogDebug "Set-NcNetInterface  -Name $InterfaceName -AdministrativeStatus up -Vserver $myVserver -Controller $myController"
			$out = Set-NcNetInterface -Name $InterfaceName -AdministrativeStatus up -Vserver $myVserver -Controller $myController  -ErrorVariable ErrorVar
			if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcNetInterface failed [$ErrorVar]" }	
	}
	
	# Verify if ISCSI service is Running 
	$IscsiService = Get-NcIscsiService -VserverContext  $myVserver -Controller $myController  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcIscsiService failed [$ErrorVar]" }
	if ( $IscsiService -eq $null ) {
		Write-Log "[$myVserver] No ISCSI services in vserver"
	} else {
		if ( $IscsiService.IsAvailable -ne $True ) {
			Write-LogDebug "Enable-NcIscsi -VserverContext $myVserver -Controller $myController"
			$out=Enable-NcIscsi -VserverContext $myVserver -Controller $myController  -ErrorVariable ErrorVar -Confirm:$False
			if ( $? -ne $True ) {
				Write-LogError "ERROR: Failed to enable iSCSI on Vserver [$myVserver]" 
				$Return = $False
			}
		}
		
	}
	
	# Verify if NFS service is Running 
	$NfsService = Get-NcNfsService -VserverContext  $myVserver -Controller $myController  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNfsService failed [$ErrorVar]" }
	if ( $NfsService -eq $null ) {
		Write-Log "[$myVserver] No NFS services in vserver"
	} else {
		if ( $NfsService.GeneralAccess -ne $True ) {
			Write-LogDebug "Enable-NcNfs -VserverContext $myVserver -Controller $myController"
			$out=Enable-NcNfs -VserverContext $myVserver -Controller $myController  -ErrorVariable ErrorVar -Confirm:$False
			if ( $? -ne $True ) {
				Write-LogError "ERROR: Failed to enable NFS on Vserver [$myVserver]" 
				$Return = $False
			}
		}
		
	}
	
	# Verify if CIFS Service is Running 
	$CifService = Get-NcCifsServer  -VserverContext  $myVserver -Controller $myController  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsServer failed [$ErrorVar]" }
	if ( $CifService -eq $null ) {
		Write-Log "[$myVserver] No CIFS services in vserver"
	} else {
		if ( $CifService.AdministrativeStatus -ne 'up' ) {
			Write-LogDebug "start-NcCifsServer -VserverContext $myVserver -Controller $myController"
			$out=start-NcCifsServer -VserverContext $myVserver -Controller $myController  -ErrorVariable ErrorVar -Confirm:$False
			if ( $? -ne $True ) {
				Write-LogError "ERROR: Failed to enable CIFS on Vserver [$myVserver]" 
				$Return = $False
			}
		}
	}
    Write-logDebug "enable_network_protocol_vserver_dr: end"
	return $Return 
}
Catch {
    handle_error $_ $myVserver
	return $Return
}
}
#############################################################################################
Function activate_vserver_dr (
	[NetApp.Ontapi.Filer.C.NcController] $myController,
	[string] $myPrimaryVserver , 
	[string] $mySecondaryVserver ) {
	
	$Return = $True
	Write-LogDebug "activate_vserver_dr: start"
	
	$ANS=Read-HostOptions "Do You really want to activate SVM [$mySecondaryVserver] from cluster [$myController] ?" "y/n"
	if ( $ANS -ne 'y' ) {
        Write-LogDebug "activate_vserver_dr: end"
		clean_and_exit 1
	}
	
	if ( ( break_snapmirror_vserver_dr -myController $myController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver ) -ne $True ) {
		Write-LogError "ERROR: Unable to break all relations from Vserver $mySecondaryVserver $myController"
		$Return = $False
	}

	if ( ( enable_network_protocol_vserver_dr -myController $myController -myVserver $mySecondaryVserver ) -ne $True ) {
		Write-LogError "ERROR: Unable to Start all NetWork Protocols in Vserver $mySecondaryVserver $myController"
		$Return = $False
	}
    Write-LogDebug "activate_vserver_dr: end"
	return $Return
}

#############################################################################################
Function resync_reverse_vserver_dr (
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver ,
	[string] $mySecondaryVserver ) 
{
    Try { 

	    $Return = $True 

	    $myPrimaryCluster = (Get-NcCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar).ClusterName			
	    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }
	    $mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar).ClusterName			
	    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }

	    Write-LogDebug "resync_reverse_vserver_dr: start"

	    Write-LogDebug "Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
	    $relationList = Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapmirror failed [$ErrorVar]" }
        if ( $Global:ForceRecreate -and ( $relationList -eq $null ) )
        {
            if ( ( create_snapmirror_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -Force -DDR $False ) -ne $True ) 
            { 
                Write-LogError "ERROR: Failed to recreate all snapmirror relations "
                return $False
            }
            Write-LogDebug "Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
	        $relationList = Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapmirror failed [$ErrorVar]" }          
	    }
	    foreach ( $relation in ( $relationList | Skip-Null ) ) 	{
		    $MirrorState=$relation.MirrorState
		    $SourceVolume=$relation.SourceVolume
            $SourceCluster=$relation.SourceCluster
            $DestinationCluster=$relation.DestinationCluster
		    $DestinationVolume=$relation.DestinationVolume
            $SourceVserver=$relation.SourceVserver
            $DestinationVserver=$relation.DestinationVserver
		    $SourceLocation=$relation.SourceLocation
		    $DestinationLocation=$relation.DestinationLocation
		    $RelationshipStatus=$relation.RelationshipStatus
			$RelationshipType=$relation.RelationshipType
            $RelationshipSchedule=$relationship.Schedule
            if($Global:ForceRecreate)
            {
                Write-LogDebug "Get-NcSnapmirror -DestinationLocation $SourceLocation -Controller $myPrimaryController"
                $existingRelationShip=Get-NcSnapmirror -DestinationLocation $SourceLocation -Controller $myPrimaryController  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapmirror failed [$ErrorVar]" }
                if($existingRelationShip -ne $null)
                {
                    $existingRelationShipDestVolume=$existingRelationShip.DestinationVolume
                    $existingRelationShipDestVserver=$existingRelationShip.DestinationVserver
                    Write-LogDebug "Remove-NcSnapmirror -DestinationVserver $existingRelationShipDestVserver -DestinationVolume $existingRelationShipDestVolume -controller $myPrimaryController"
                    $out=Remove-NcSnapmirror -DestinationVserver $existingRelationShipDestVserver -DestinationVolume $existingRelationShipDestVolume -controller $myPrimaryController  -ErrorVariable ErrorVar -Confirm:$False   
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Remove-NcSnapmirror failed [$ErrorVar]" } 
                }
            }

		    if ( ( $MirrorState -eq 'broken-off' ) -and ($RelationshipStatus -eq 'idle' ) ) 
            {
			    Write-LogDebug "Get-NcSnapmirror -SourceLocation $DestinationLocation -DestinationLocation $SourceLocation -Controller $myPrimaryController"
			    $reverseRelation=Get-NcSnapmirror -SourceLocation $DestinationLocation -DestinationLocation $SourceLocation -Controller $myPrimaryController  -ErrorVariable ErrorVar
			    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapmirror failed [$ErrorVar]" }
			    if ( $reverseRelation -ne $null ) 
                {
                    $ReverseRelationshipStatus=$reverseRelation.RelationshipStatus
				    $ReverseMirrorState=$reverseRelation.MirrorState
                    $ReverseHealth=$reverseRelation.IsHealthy
				    Write-Log "Reverse Relation [$DestinationLocation] [$SourceLocation] already exist [$ReverseRelationshipStatus] [$ReverseMirrorState]" 
				    if ( ( $ReverseRelationshipStatus -ne 'idle' ) -and ( $ReverseMirrorState -ne 'snapmirrored' ) ) 
                    {
					    Write-LogWarn "Reverse Relation status is [$ReverseRelationshipStatus] [$ReverseMirrorState], must be broken before resync reverse"
					    $Return = $False
				    }
                    if ($ReverseHealth -eq $False)
                    {
                        Write-LogWarn "Reverse Relation is not Healthy [$ReverseRelationshipStatus] [$ReverseMirrorState] Please check on controller [$myPrimaryController]"
					    $Return = $False    
                    }
				    Write-Log "Resync Relation [$DestinationLocation] [$SourceLocation]"
				    Write-LogDebug "Invoke-NcSnapmirrorResync -Source $DestinationLocation -Destination $SourceLocation  -Controller $myPrimaryController"
				    $out=Invoke-NcSnapmirrorResync -Source $DestinationLocation -Destination $SourceLocation -Controller $myPrimaryController  -ErrorVariable ErrorVar
				    if ( $? -ne $True ){Write-LogError "ERROR: snapmirror Resync Failed";$Return = $False}
			    } 
                else 
                {
                    if($RelationshipType -eq "extended_data_protection")
                    {
                        Write-Log "Create Reverse VF SnapMirror [${DestinationCluster}://${DestinationVserver}/$DestinationVolume] -> [${SourceCluster}://${SourceVserver}/$SourceVolume]"
                        Write-LogDebug "New-NcSnapmirror -Type XDP -policy $XDPPolicy -Schedule hourly -DestinationCluster $SourceCluster -DestinationVserver $SourceVserver -DestinationVolume $SourceVolume -SourceCluster $DestinationCluster -SourceVserver $DestinationVserver -SourceVolume $DestinationVolume -Controller $myPrimaryController "
        			    $relation=New-NcSnapmirror -Type vault -policy $XDPPolicy -Schedule hourly -DestinationCluster $SourceCluster -DestinationVserver $SourceVserver -DestinationVolume $SourceVolume -SourceCluster $DestinationCluster -SourceVserver $DestinationVserver -SourceVolume $DestinationVolume -Controller $myPrimaryController  -ErrorVariable ErrorVar 
        			    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcSnapmirror failed [$ErrorVar]" }
                        Write-Log "Reverse resync [${DestinationCluster}://${DestinationVserver}/$DestinationVolume] -> [${SourceCluster}://${SourceVserver}/$SourceVolume]"
                        Write-LogDebug "Invoke-NcSnapmirrorResync -Source $DestinationLocation -Destination $SourceLocation  -Controller $myPrimaryController"
				        $out=Invoke-NcSnapmirrorResync -Source $DestinationLocation -Destination $SourceLocation -Controller $myPrimaryController  -ErrorVariable ErrorVar
				        if ( $? -ne $True ){Write-LogError "ERROR: snapmirror Resync Failed";$Return = $False}
                    }else{
                        Write-Log "Create Reverse SnapMirror [${DestinationCluster}://${DestinationVserver}/$DestinationVolume] -> [${SourceCluster}://${SourceVserver}/$SourceVolume]"
                        if($RelationshipSchedule -ne $null){
                            Write-LogDebug "New-NcSnapmirror -Type DP -Policy DPDefault -Schedule $RelationshipSchedule -DestinationCluster $SourceCluster -DestinationVserver $SourceVserver -DestinationVolume $SourceVolume -SourceCluster $DestinationCluster -SourceVserver $DestinationVserver -SourceVolume $DestinationVolume -Controller $myPrimaryController "
        			        $relation=New-NcSnapmirror -Type dp -Policy DPDefault -Schedule $RelationshipSchedule -DestinationCluster $SourceCluster -DestinationVserver $SourceVserver -DestinationVolume $SourceVolume -SourceCluster $DestinationCluster -SourceVserver $DestinationVserver -SourceVolume $DestinationVolume -Controller $myPrimaryController  -ErrorVariable ErrorVar 
        			        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcSnapmirror failed [$ErrorVar]" }
                        }else{
                            Write-LogDebug "New-NcSnapmirror -Type DP -Policy DPDefault -DestinationCluster $SourceCluster -DestinationVserver $SourceVserver -DestinationVolume $SourceVolume -SourceCluster $DestinationCluster -SourceVserver $DestinationVserver -SourceVolume $DestinationVolume -Controller $myPrimaryController "
        			        $relation=New-NcSnapmirror -Type dp -Policy DPDefault -DestinationCluster $SourceCluster -DestinationVserver $SourceVserver -DestinationVolume $SourceVolume -SourceCluster $DestinationCluster -SourceVserver $DestinationVserver -SourceVolume $DestinationVolume -Controller $myPrimaryController  -ErrorVariable ErrorVar 
        			        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcSnapmirror failed [$ErrorVar]" }
                        }
                        Write-Log "Reverse resync [${DestinationCluster}://${DestinationVserver}/$DestinationVolume] -> [${SourceCluster}://${SourceVserver}/$SourceVolume]"
                        Write-LogDebug "Invoke-NcSnapmirrorResync -Source $DestinationLocation -Destination $SourceLocation  -Controller $myPrimaryController"
				        $out=Invoke-NcSnapmirrorResync -Source $DestinationLocation -Destination $SourceLocation -Controller $myPrimaryController  -ErrorVariable ErrorVar
				        if ( $? -ne $True ){Write-LogError "ERROR: snapmirror Resync Failed";$Return = $False}    
                    }
                    <#else{
				        $ReverseRelationshipStatus=$reverseRelation.RelationshipStatus
				        $ReverseMirrorState=$reverseRelation.MirrorState
                        $ReverseHealth=$reverseRelation.IsHealthy
				        Write-Log "Reverse Relation [$DestinationLocation] [$SourceLocation] already exist [$ReverseRelationshipStatus] [$ReverseMirrorState]" 
				        if ( ( $ReverseRelationshipStatus -ne 'idle' ) -and ( $ReverseMirrorState -ne 'snapmirrored' ) ) 
                        {
					        Write-LogWarn "WARNING: Reverse Relation status is [$ReverseRelationshipStatus] [$ReverseMirrorState]"
					        $Return = $False
				        }
                        if ($ReverseHealth -eq $False)
                        {
                            Write-LogWarn "WARNING: Reverse Relation is not Healthy [$ReverseRelationshipStatus] [$ReverseMirrorState] Please check on controller [$mySecondaryController]"
					        $Return = $False    
                        }
                    }#>
			    }
		    } 
            else 
            {
			    Write-LogError "ERROR: The relation [$SourceLocation] [$DestinationLocation] status is [$RelationshipStatus] [$MirrorState]" 
			    $Return = $False
		    }
	    }
	    return $Return 
    }
    Catch 
    {
        handle_error $_ $myPrimaryVserver
	    return $Return
    }
}

#############################################################################################
Function resync_vserver_dr (
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
	[NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
	[string] $myPrimaryVserver,
	[string] $mySecondaryVserver ) 
{
    Try 
    {
    	$Return = $True

    	$myPrimaryCluster = (Get-NcCluster -Controller $myPrimaryController  -ErrorVariable ErrorVar).ClusterName			
    	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }
    	$mySecondaryCluster = (Get-NcCluster -Controller $mySecondaryController  -ErrorVariable ErrorVar).ClusterName			
    	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCluster failed [$ErrorVar]" }
        if($Global:ForceRecreate)
        {
            #Write-Log "Recreate relationship from $myPrimaryVserver to $mySecondaryVserver"
            if ( ( create_snapmirror_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver -Force -DDR $False ) -ne $True ) 
            { 
                Write-LogError "ERROR: Failed to recreate all snapmirror relations "
                return $False
            }
        }
    	Write-LogDebug "Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
    	$relationList = Get-NcSnapmirror -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController  -ErrorVariable ErrorVar
    	if ( $? -ne $True ) 
        { $Return = $False ; throw "ERROR: Get-NcSnapmirror failed [$ErrorVar]" }
    	foreach ( $relation in ( $relationList | Skip-Null ) ) 
        {
    		$MirrorState=$relation.MirrorState
    		$SourceVolume=$relation.SourceVolume
    		$DestinationVolume=$relation.DestinationVolume
    		$SourceLocation=$relation.SourceLocation
    		$DestinationLocation=$relation.DestinationLocation
    		$RelationshipStatus=$relation.RelationshipStatus
            $RelationHealth=$relation.IsHealthy
    		
    		if ( ( $MirrorState -eq 'broken-off' ) -and ($RelationshipStatus -eq 'idle' ) ) 
            {
    			Write-Log "Resync relationship [$SourceLocation] [$DestinationLocation] "
    			Write-LogDebug "Invoke-NcSnapmirrorResync -Source $SourceLocation -Destination $DestinationLocation  -Controller $mySecondaryController"
    			$out=Invoke-NcSnapmirrorResync -Source $SourceLocation -Destination $DestinationLocation  -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
    			if ( $? -ne $True ) 
                {
    				Write-LogError "ERROR: Snapmirror Resync failed" 
    				$Return = $False
    			}
    		} 
            elseif ( ( $MirrorState -eq 'snapmirrored' ) -and ( ( $RelationshipStatus -eq 'idle' ) -or (( $RelationshipStatus -eq 'transferring' ) -and ( $MirrorState -eq 'broken-off') ) ) ) 
            {
    			Write-Log "The relation [$SourceLocation] [$DestinationLocation] status is [$RelationshipStatus] [$MirrorState] " 
    		} 
            elseif ( $RelationHealth -eq $False )
            {
                Write-LogWarn "The relation [$SourceLocation] [$DestinationLocation] is not healthy, check status"
            }
            else 
            {
    			Write-LogError "ERROR: The relation [$SourceLocation] [$DestinationLocation] status is [$RelationshipStatus] [$MirrorState] " 
    			$Return = $False
    		}			
        }
        return $Return
    }
    Catch 
    {
        handle_error $_ $myPrimaryVserver
    	return $Return
    }
}

#############################################################################################
Function svmdr_db_check (
	[NetApp.Ontapi.Filer.C.NcController] $myController,
	[string]$myVserver, 
	[string]$myVolume) {
Try {
	$Return = $True
    Write-LogDebug "svmdr_db_check: start"
	Write-LogDebug "svmdr_db_check: [$Global:SVMTOOL_DB]"

        if ( ( Test-Path $Global:SVMTOOL_DB -pathType container ) -eq $false ) {
                $out=New-Item -Path $Global:SVMTOOL_DB -ItemType directory
                if ( ( Test-Path $Global:SVMTOOL_DB -pathType container ) -eq $false ) {
                        Write-LogError "ERROR: Unable to create new item $Global:SVMTOOL_DB" 
                        Write-LogDebug "svmdr_db_check: end"
                        return $False
                }
        }
  	if ( $myVserver -eq $null ) { $myVserver = "*" }
  	if ( $myVolume -eq $null ) { $myVolume  = "*" } 

  	$Source=$myVserver + ':' + $myVolume 

  	$NcCluster = Get-NcCluster -Controller $myController
  	$SourceCluster = $NcCluster.ClusterName

    Write-LogDebug "Get-NcSnapmirrorDestination  -SourceVserver $myVserver -VserverContext $myVserver -Controller $myController"
    $relationlist=Get-NcSnapmirrorDestination  -SourceVserver $myVserver -VserverContext $myVserver -Controller $myController  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapmirrorDestination failed [$ErrorVar]" } 
  	if ( $relationlist -eq $null ) {
		Write-LogDebug "svmdr_db_check: SnapMirror No Relations found" ;
        Write-LogDebug "svmdr_db_check: end"
		return $True 
  	}
  	foreach ( $relation in $relationlist ) {
		$SourceVolume = $relation.SourceVolume
		$SourceVserver = $relation.SourceVserver
		$DestinationVolume = $relation.DestinationVolume
		$DestinationVserver = $relation.DestinationVserver
		$DestinationLocation = $relation.DestinationLocation
		$RelationshipType =$relation.RelationshipType
		if ( ( $RelationshipType -eq "data_protection" ) -and ( $SourceVserver -ne $DestinationVserver  )  ) {
			$NcVserverPeer=Get-NcVserverPeer -Controller $myController -Vserver $SourceVserver -PeerVserver $DestinationVserver 
			$DestinationCluster=$NcVserverPeer.PeerCluster
			Write-LogDebug "svmdr_db_check: [$SourceVserver] [$SourceVolume] -> [$DestinationCluster] [$DestinationVserver] [$DestinationVolume] [$RelationshipType]" ;
			$SVMTOOL_DB_SRC_CLUSTER=$Global:SVMTOOL_DB + '\' + $SourceCluster + '.cluster'
			$SVMTOOL_DB_SRC_VSERVER=$SVMTOOL_DB_SRC_CLUSTER + '\' +$SourceVserver + '.vserver'

        		if ( ( Test-Path $SVMTOOL_DB_SRC_CLUSTER -pathType container ) -eq $false ) {
                		$out=new-item -Path $SVMTOOL_DB_SRC_CLUSTER -ItemType directory
                		if ( ( Test-Path $SVMTOOL_DB_SRC_CLUSTER -pathType container ) -eq $false ) {
                        		Write-LogError "ERROR: Unable to create new item $SVMTOOL_DB_SRC_CLUSTER" 
                        		return $False
                		}
        		}

        		if ( ( Test-Path $SVMTOOL_DB_SRC_VSERVER -pathType container ) -eq $false ) {
                		$out=new-item -Path $SVMTOOL_DB_SRC_VSERVER -ItemType directory
                		if ( ( Test-Path $SVMTOOL_DB_SRC_VSERVER -pathType container ) -eq $false ) {
                        		Write-LogError "ERROR: Unable to create new item $SVMTOOL_DB_SRC_VSERVER" 
                        		return $False
                		}
        		}

			$SVMTOOL_DB_DST_CLUSTER=$Global:SVMTOOL_DB + '\' + $DestinationCluster + '.cluster'
			$SVMTOOL_DB_DST_VSERVER=$SVMTOOL_DB_DST_CLUSTER + '\' +$DestinationVserver + '.vserver'

        		if ( ( Test-Path $SVMTOOL_DB_DST_CLUSTER -pathType container ) -eq $false ) {
                		$out=new-item -Path $SVMTOOL_DB_DST_CLUSTER -ItemType directory
                		if ( ( Test-Path $SVMTOOL_DB_DST_CLUSTER -pathType container ) -eq $false ) {
                        		Write-LogError "ERROR: Unable to create new item $SVMTOOL_DB_DST_CLUSTER" 
                        		return $False
                		}
        		}

        		if ( ( Test-Path $SVMTOOL_DB_DST_VSERVER -pathType container ) -eq $false ) {
                		$out=new-item -Path $SVMTOOL_DB_DST_VSERVER -ItemType directory
                		if ( ( Test-Path $SVMTOOL_DB_DST_VSERVER -pathType container ) -eq $false ) {
                        		Write-LogError "ERROR: Unable to create new item $SVMTOOL_DB_DST_VSERVER" 
                        		return $False
                		}
        		}
		}
	}
    Write-LogDebug "svmdr_db_check: end"
	return $Return
}
Catch {
    handle_error $_ $myVserver
	return $Return
    }
}

#############################################################################################
Function create_subdir (
    [NetApp.Ontapi.Filer.C.NcController] $myController,
    [string] $myVserver,
    [string] $Dirs,
    [string] $RootVolume,
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [string] $myPrimaryVserver,
    [switch] $Restore)
{
    $Return=$True
    $fullpath=$("/vol/"+$RootVolume)
    foreach($dir in $Dirs.split("/")[1..$Dirs.split("/").count]){
        if($DebugLevel){Write-LogDebug "Work with dir [$dir]"}
        $fullpath+=$("/"+$dir)
        try{
            if($DebugLevel){Write-LogDebug "Get dir detail for path [$fullpath] on [$myVserver]"}
            try{
                $DirDetails=Read-NcDirectory -Path $fullpath -VserverContext $myVserver -Controller $myController -ErrorAction SilentlyContinue
            }catch{
                $DirDetails=$null
            }
            if($DirDetails -eq $null){
                if($DebugLevel){Write-LogDebug "Get dir detail for path [$fullpath] on [$myPrimaryVserver]"}
                $searchPath=(Split-Path -Path $fullpath).replace('\','/')
                if($Restore -eq $False){
                    $PrimDirDetails=Read-NcDirectory -Path $searchPath -VserverContext $myPrimaryVserver -Controller $myPrimaryController | Where-Object {$_.Name -eq $dir}
                }else{
                    if(Test-Path $($Global:JsonPath+"Read-NcDirectory-"+$dir+".json")){
                        $PrimDirDetails=Get-Content $($Global:JsonPath+"Read-NcDirectory-"+$dir+".json") | ConvertFrom-Json
                    }else{
                        $Return=$False
                        $filepath=$($Global:JsonPath+"Read-NcDirectory-"+$dir+".json")
                        Throw "ERROR: failed to read $filepath"
                    }    
                }
                $PrimDirPerm=$PrimDirDetails.Perm
                $PrimDirType=$PrimDirDetails.Type
                if($PrimDirType -eq "directory"){
                    if($DebugLevel){Write-LogDebug "Create Sub Directory [$dir] on Secondary Vserver [$myVserver] inside volume [$RootVolume] at Path [$fullpath] with Perm [$PrimDirPerm]"}
                    Write-LogDebug "New-NcDirectory -Controller $myController -VserverContext $mySecondaryVserver -Permission $PrimDirPerm -Path $fullpath"
                    $out=New-NcDirectory -Controller $mySecondaryController -VserverContext $mySecondaryVserver -Permission $PrimDirPerm -Path $fullpath -ErrorVariable ErrorVar -Confirm:$False
                    if($? -ne $True) { $Return = $False ; Throw "ERROR : Failed to create Sub Directory [$dir] on volume [$Root] on SVM [$myVserver] Reason : [$ErrorVar]" } 
                }elseif($PrimDirType -eq "symlink"){
                    if($DebugLevel){Write-LogDebug "Create SymLink [$dir] on Secondary Vserver [$myVserver] inside volume [$RootVolume] with target [$fullpath]"}
                    Write-LogError "Create symlink manually"
                    ## $out=New-NcSymLink -Controller $mySecondaryController -VserverContext $mySecondaryVserver -Permission $PrimDirPerm -Path $fullpath -ErrorVariable ErrorVar -Confirm:$False
                    ## if($? -ne $True) { $Return = $False ; Throw "ERROR : Failed to create Sub Directory [$dir] on volume [$Root] on SVM [$myVserver] Reason : [$ErrorVar]" }    
                }
            }else{
                if($DebugLevel){Write-LogDebug "directory [$searchPath] aleready exist"}
            }
        }catch{
            handle_error $_ $myVserver
            return $Return    
        }
    } 
    return $Return  
}

#############################################################################################
Function mount_volume (
    [NetApp.Ontapi.Filer.C.NcController] $myController,
    [string] $myVserver,
    [string] $myVolumeName,
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [string] $myPrimaryVserver,
    [switch] $Restore) 
{
    
    $Return = $True 
    Write-logDebug "mount_volume: start $myVolumeName"
    $RootVolume = (Get-NcVserver -Controller $myController -Vserver $myVserver  -ErrorVariable ErrorVar).RootVolume
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed to get RootVolume [$ErrorVar]" } 
	if ($RootVolume -eq $null ) { $Return = $False ; Write-logError "root volume not found for [$myVserver]" }
    $FindVolume=$script:vol_junction | Where-Object {$_.Name -eq $myVolumeName}
    $Parent=$FindVolume.JunctionParent
    $JunctionPath=$FindVolume.JunctionPath
    $ParentPath=$FindVolume.ParentPath
    $Permission=$FindVolume.Permission
    $ParentPath=$FindVolume.ParentPath
    $IsNested=$FindVolume.IsNested
    $PathLevel=$FindVolume.Level
    if ($DebugLevel) {Write-LogDebug "volume [$myVolumeName] Parent [$Parent] JunctionPath [$JunctionPath] Perm [$Permission] RootVol [$RootVolume] Level [$PathLevel] ParentPath [$ParentPath]"}
    $mountpath=(Get-NcVol -Name $myVolumeName -Vserver $myVserver -Controller $myController).VolumeIdAttributes.JunctionPath
    if($mountpath -ne $null){
        if ($DebugLevel) {Write-LogDebug "Volume [$myVolumeName] is mounted under [$mountpath]"}
        if($mountpath -eq $JunctionPath){
            Write-LogDebug "Volume [$myVolumeName] is correctly mounted"
            Write-logDebug "mount_volume: end $myVolumeName"
            return $True
        }
    if($DebugLevel){Write-LogDebug "First need to unmount volume [$myVolumeName] from [$mountpath] on [$myVserver]"}
    if ($DebugLevel) {Write-logDebug "Dismount-NcVol -Name $myVolumeName -VserverContext $myVserver -Controller $myController"}
    $out=Dismount-NcVol -Name $myVolumeName -VserverContext $myVserver -Controller $myController -Force -Confirm:$False -ErrorVariable ErrorVar
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Dismount-NcVol [$myVolumeName] failed [$ErrorVar]" }        
    }
    try{
        if ($DebugLevel) {Write-LogDebug "Now will mount volume [$myVolumeName]"}
        $voltype="rw"
        if($Parent -ne $RootVolume){
            $volType=(Get-NcVol -Controller $myController -Vserver $myVserver -Volume $myVolumeName).VolumeIdAttributes.Type
            if($volType -eq "dp" -and $Restore -eq $False){
                if ($DebugLevel) {Write-LogDebug "Need to break the associated SM relationship with [$myVolumeName] before beeing able to create a directory inside this volume"}
                $out=Invoke-NcSnapmirrorBreak -Controller $myController -Confirm:$false -DestinationVserver $myVserver -DestinationVolume $myVolumeName
                if($? -ne $True){throw "ERROR: Failed to break SM destination [$myVserver]:[$myVolumeName] on [$myController] reason [$ErrorVar]"}
            }
        }
        $CreatePath=(Split-Path -Path $JunctionPath).Replace('\','/')
        if($DebugLevel){Write-LogDebug "CreatePath is [$CreatePath] for JunctionPath [$JunctionPath] for volume [$myVolumeName] inside Parent [$Parent]"}
        if($CreatePath.Length -gt 1){
            if($DebugLevel) {Write-LogDebug "Need to Create all subdir in [$CreatePath]"}
            if($FindVolume.IsNested -eq $True){   
                $RelativePathToCreate=$CreatePath.replace($ParentPath,"") 
                if($RelativePathToCreate.Length -gt 1){
                    if($Restore -eq $False){
                        if ($DebugLevel) {Write-LogDebug "Treat subdir for a nested volume`nNeed to Create [$RelativePathToCreate] inside volume [$Parent]"}
                        if(($ret=create_subdir -myController $myController -myVserver $myVserver -Dirs $RelativePathToCreate -RootVolume $Parent -myPrimaryController $myPrimaryController -myPrimaryVserver $myPrimaryVserver) -ne $True) {
                            Return $False
                            Throw "ERROR: Failed to create all subidr [$RelativePathToCreate] in [$Parent]"
                        }
                    }else{
                        if ($DebugLevel) {Write-LogDebug "Treat subdir for a nested volume`nNeed to Create [$RelativePathToCreate] inside volume [$Parent]"}
                        if(($ret=create_subdir -myController $myController -myVserver $myVserver -Dirs $RelativePathToCreate -RootVolume $Parent -Restore) -ne $True) {
                            Return $False
                            Throw "ERROR: Failed to create all subidr [$RelativePathToCreate] in [$Parent]"
                        }    
                    }
                }else{
                    if($DebugLevel){Write-LogDebug "Don't need to create [$CreatePath], already present"}
                }
            }else{
                if($Restore -eq $False){
                    if ($DebugLevel) {Write-LogDebug "Treat subdir`nNeed to Create [$CreatePath] inside volume [$Parent]"}
                    if(($ret=create_subdir -myController $myController -myVserver $myVserver -Dirs $CreatePath -RootVolume $Parent -myPrimaryController $myPrimaryController -myPrimaryVserver $myPrimaryVserver) -ne $True) {
                        Return $False
                        Throw "ERROR: Failed to create all subidr [$CreatePath] in [$Parent]"
                    }
                }else{
                    if ($DebugLevel) {Write-LogDebug "Treat subdir`nNeed to Create [$CreatePath] inside volume [$Parent]"}
                    if(($ret=create_subdir -myController $myController -myVserver $myVserver -Dirs $CreatePath -RootVolume $Parent -Restore) -ne $True) {
                        Return $False
                        Throw "ERROR: Failed to create all subidr [$CreatePath] in [$Parent]"
                    }    
                }
            }  
        }
        try{
            Write-logDebug "Mount-NcVol -Name $myVolumeName -JunctionPath $JunctionPath -VserverContext $myVserver -Controller $myController"
            $out=Mount-NcVol -Name $myVolumeName -JunctionPath $JunctionPath -VserverContext $myVserver -Controller $myController -ErrorVariable ErrorVar
            if ( $? -ne $True ) {throw "ERROR: Mount-NcVol [$myVolumeName] failed [$ErrorVar]" } 
        }catch{
            #wait-debugger
            $ErrorMessage = $_.Exception.Message
            Write-LogDebug "Catch Mount-NcVol Failed to mount trap [$ErrorMessage]"
        }
        if($voltype -eq "dp" -and $Restore -eq $False){
            if ($DebugLevel) {Write-LogDebug "resync snapmirror previously broken"}
            $ret=Invoke-NcSnapmirrorResync -DestinationVserver $myVserver -DestinationVolume $myVolumeName -Controller $myController -Confirm:$False -ErrorVariable ErrorVar  
            if($? -ne $True){throw "ERROR: Failed to resync SM destination [$myVserver]:[$myVolumeName] on [$myController] reason [$ErrorVar]"}  
        }
        #$ret=analyse_junction_path -myController $mySecondaryController -myVserver $mySecondaryVserver -Dest
        $ret=analyse_junction_path -myController $myController -myVserver $myVserver -Dest
        if ($ret -ne $True){$Return=$False;Throw "ERROR : Failed to analyse_junction_path"}
        Write-logDebug "mount_volume: end $myVolumeName"
        return $Return  
    }catch{
        handle_error $_ $myVserver
        return $Return    
    }                 
    Write-logDebug "mount_volume: end $myVolumeName"
    return $Return
}

#############################################################################################
Function umount_volume (
    [NetApp.Ontapi.Filer.C.NcController] $myController,
    [string] $myVserver,
    [string] $myVolumeName) {

    $Return = $True 
    Write-logDebug "umount_volume: start $myVolumeName"
    if ( ($script:vol_junction_dest | Where-Object {$_.Name -eq $myVolumeName} | Measure-Object).count -eq 0 ){
        if ($DebugLevel) {Write-LogDebug "Volume [$myVolumeName] is not mounted in Namespace"}
    }else{
        $volume=$script:vol_junction_dest | Where-Object {$_.Name -eq $myVolumeName}
        $volumeName=$volume.Name
        if ($DebugLevel) {Write-logDebug "Dismount-NcVol -Name $volumeName -VserverContext $myVserver -Controller $myController"}
        $out=Dismount-NcVol -Name $volumeName -VserverContext $myVserver -Controller $myController -Force -Confirm:$False -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Dismount-NcVol [$volumeName] failed [$ErrorVar]" }
        # $script:vol_junction_dest | Where-Object {$_.Name -eq $myVolumeName} | foreach{
            # $Children=$_.Child
            # foreach ($child in $Children){
            #     $ret=umount_volume -myController $myController -myVserver $myVserver -myVolumeName $child
            #     if($ret -ne $True){$Return=$False;Throw "ERROR : Failed to umount volume [$child] on [$myVserver]"}
            # }
            # try{
            #     Write-logDebug "Dismount-NcVol -Name $myVolumeName -VserverContext $myVserver -Controller $myController"
            #     $out=Dismount-NcVol -Name $myVolumeName -VserverContext $myVserver -Controller $myController -Force -Confirm:$False -ErrorVariable ErrorVar
            #     if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Dismount-NcVol [$myVolumeName] failed [$ErrorVar]" }
            #     Write-logDebug "umount_volume: end"
            #     $ret=analyse_junction_path -myController $mySecondaryController -myVserver $mySecondaryVserver -Dest	
            #     if ($ret -ne $True){$Return=$False;Throw "ERROR : Failed to analyse_junction_path"}
            #     return $Return
            # }catch{
            #     $ErrorMessage = $_.Exception.Message
            #     $FailedItem = $_.Exception.ItemName
            #     $Type = $_.Exception.GetType().FullName
            #     $CategoryInfo = $_.CategoryInfo
            #     $ErrorDetails = $_.ErrorDetails
            #     $Exception = $_.Exception
            #     $FullyQualifiedErrorId = $_.FullyQualifiedErrorId
            #     $InvocationInfoLine = $_.InvocationInfo.Line
            #     $InvocationInfoLineNumber = $_.InvocationInfo.ScriptLineNumber
            #     $PipelineIterationInfo = $_.PipelineIterationInfo
            #     $ScriptStackTrace = $_.ScriptStackTrace
            #     $TargetObject = $_.TargetObject
            #     Write-LogError  "Trap Error: [$myPrimaryVserver] [$ErrorMessage]"
            #     Write-LogDebug  "Trap Item: [$FailedItem]"
            #     Write-LogDebug  "Trap Type: [$Type]"
            #     Write-LogDebug  "Trap CategoryInfo: [$CategoryInfo]"
            #     Write-LogDebug  "Trap ErrorDetails: [$ErrorDetails]"
            #     Write-LogDebug  "Trap Exception: [$Exception]"
            #     Write-LogDebug  "Trap FullyQualifiedErrorId: [$FullyQualifiedErrorId]"
            #     Write-LogDebug  "Trap InvocationInfo: [$InvocationInfoLineNumber] [$InvocationInfoLine]"
            #     Write-LogDebug  "Trap PipelineIterationInfo: [$PipelineIterationInfo]"
            #     Write-LogDebug  "Trap ScriptStackTrace: [$ScriptStackTrace]"
            #     Write-LogDebug  "Trap TargetObject: [$TargetObject]"
            #     return $Return    
            # }
        # }
    }
    Write-logDebug "umount_volume: end $myVolumeName"
    return $Return
}

#############################################################################################
Function remove_volume (
    [NetApp.Ontapi.Filer.C.NcController] $myController,
    [string] $myVserver,
    [string] $myVolumeName) {
Try {
        $Return = $True 
        Write-logDebug "remove_volume: start"
        Write-Log "Remove volume [$myVolumeName] from [$myVserver]"
        Write-logDebug "Get-NcVol -Controller $myController -Vserver $myVserver -Name $myVolumeName"
        $SecondaryVol=Get-NcVol -Controller $myController -Vserver $myVserver -Name $myVolumeName -ErrorVariable ErrorVar 
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
        if($SecondaryVol -ne $null){  
            $SecondaryVolState=$SecondaryVol.State
            if ( $SecondaryVolState -ne 'offline' ) {
                Write-LogDebug "Set-NcVol -Name $SecondaryVol -Offline -VserverContext $myVserver -Controller $myController -Confirm:$False"
                $out = Set-NcVol -Name $SecondaryVol -Offline -VserverContext $myVserver -Controller $myController -ErrorVariable ErrorVar  -Confirm:$False
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcVol failed [$ErrorVar]" }
            }
            Write-LogDebug "Remove-NcVol -Name $SecondaryVol -VserverContext $myVserver -Controller $myController -Confirm:$False"
            $out = Remove-NcVol -Name $SecondaryVol -VserverContext $myVserver -Controller $myController -ErrorVariable ErrorVar  -Confirm:$False
            if ( $? -ne $True ) {
                Write-LogError "ERROR: Unable to set volume [$SecondaryVol] offline" 
                return $False   
            }
        }else{
            Write-LogDebug "volume [$myVolumeName] does not exist on [$myVserver]"
        }
        Write-logDebug "remove_volume: end"
        return $Return
    }catch{
        handle_error $_ $myVserver
        return $Return
    }
}

#############################################################################################
Function delete_snapmirror_relationship (
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
    [string] $mySecondaryVserver,
    [string] $PrimaryVolumeName) {
Try {

    $Return = $True 
    Write-logDebug "delete_snapmirror_relationship: start"
    $NcCluster = Get-NcCluster -Controller $myPrimaryController
    $SourceCluster = $NcCluster.ClusterName
    $NcCluster = Get-NcCluster -Controller $mySecondaryController
    $DestinationCluster = $NcCluster.ClusterName
    Write-LogDebug "Get-NcSnapmirror -DestinationCluster $DestinationCluster -DestinationVserver $mySecondaryVserver -SourceCluster $SourceCluster -SourceVserver $myPrimaryVserver -VserverContext $mySecondaryVserver -SourceVolume $PrimaryVolumeName -Controller $mySecondaryController"
    $relationList=Get-NcSnapmirror -DestinationCluster $DestinationCluster -DestinationVserver $mySecondaryVserver -SourceCluster $SourceCluster -SourceVserver $myPrimaryVserver -VserverContext $mySecondaryVserver -SourceVolume $PrimaryVolumeName -Controller $mySecondaryController  -ErrorVariable ErrorVar
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapmirror failed [$ErrorVar]" }
    foreach ( $relation in ( $relationList  | Skip-Null ) ) {
            $MirrorState=$relation.MirrorState
            $SourceVolume=$relation.SourceVolume
            $DestinationVolume=$relation.DestinationVolume
            $SourceLocation=$relation.SourceLocation
            $DestinationLocation=$relation.DestinationLocation
            $MirrorState=$relation.MirrorState  
            Write-Log "Remove snapmirror relation for volume [$SourceLocation] [$DestinationLocation]"
            if ( $MirrorState -eq 'snapmirrored' ) {
                Write-LogDebug "Invoke-NcSnapmirrorBreak -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume  $DestinationVolume -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver  -SourceVolume $SourceVolume  -Controller  $mySecondaryController -Confirm:$False"
                $out= Invoke-NcSnapmirrorBreak -DestinationCluster $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume  $DestinationVolume -SourceCluster $myPrimaryCluster -SourceVserver $myPrimaryVserver  -SourceVolume $SourceVolume  -Controller  $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
                if ( $? -ne $True ) {
                    Write-LogError "ERROR: Unable to Break relation [$SourceLocation] [$DestinationLocation]" 
                    $Return = $True 
                }
            }
            Write-LogDebug "Remove-NcSnapmirror -SourceLocation $SourceLocation -DestinationLocation $DestinationLocation -Controller $mySecondaryController -Confirm:$False"
            $out = Remove-NcSnapmirror -SourceLocation $SourceLocation -DestinationLocation $DestinationLocation -Controller $mySecondaryController  -ErrorVariable ErrorVar -Confirm:$False
            if ( $? -ne $True ) {
                Write-LogError "ERROR: Unable to remove relation [$SourceLocation] [$DestinationLocation]" 
                $Return = $True 
                return $Return
            }
    }
    Write-LogDebug "Get-NcSnapmirrorDestination  -SourceVserver $myPrimaryVserver -DestinationVserver $mySecondaryVserver -SourceVolume $PrimaryVolumeName -VserverContext $myPrimaryVserver -Controller $myPrimaryController"
    $relationList=Get-NcSnapmirrorDestination  -SourceVserver $myPrimaryVserver -DestinationVserver $mySecondaryVserver -SourceVolume $PrimaryVolumeName -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapmirrorDestination failed [$ErrorVar]" }
    foreach ( $relation in ( $relationList | Skip-Null ) ) {
            $MirrorState=$relation.MirrorState
            $SourceVolume=$relation.SourceVolume
            $DestinationVolume=$relation.DestinationVolume
            $SourceLocation=$relation.SourceLocation
            $DestinationLocation=$relation.DestinationLocation
            $RelationshipId=$relation.RelationshipId
            
            Write-Log "Release [$SourceLocation] [$DestinationLocation] Relationship"
            Write-LogDebug "Invoke-NcSnapmirrorRelease -DestinationCluster  $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $DestinationVolume -SourceCluster  $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $SourceVolume  -RelationshipId $RelationshipId -Controller $myPrimaryController -Confirm:$False"
            $out = Invoke-NcSnapmirrorRelease -DestinationCluster  $mySecondaryCluster -DestinationVserver $mySecondaryVserver -DestinationVolume $DestinationVolume -SourceCluster  $myPrimaryCluster -SourceVserver $myPrimaryVserver -SourceVolume $SourceVolume  -RelationshipId $RelationshipId -Controller $myPrimaryController  -ErrorVariable ErrorVar -Confirm:$False
            if ( $? -ne $True ) {
                Write-LogError "ERROR: Unable to Release relation [$SourceLocation] [$DestinationLocation]" 
                $Return = $True 
            }
    }
    Write-logDebug "delete_snapmirror_relationship: end"
    return $Return
    }catch{
        handle_error $_ $myPrimaryVserver
        return $Return
    }
}

#############################################################################################
Function svmdr_db_switch_datafiles (
	[NetApp.Ontapi.Filer.C.NcController] $myController,
    [string] $myVserver,
    [switch] $Backup) {
Try {
    $Return = $True
    Write-Log "[$myVserver] Switch Datafiles"
    Write-LogDebug "svmdr_db_switch_datafiles: start"
    Write-LogDebug "svmdr_db_switch_datafiles: [$Global:SVMTOOL_DB]"
    if ( ( Test-Path $Global:SVMTOOL_DB -pathType container ) -eq $false ) {
            $out=new-item -Path $Global:SVMTOOL_DB -ItemType directory
            if ( ( Test-Path $Global:SVMTOOL_DB -pathType container ) -eq $false ) {
                    Write-LogError "ERROR: Unable to create new item $Global:SVMTOOL_DB" 
                    return $false
            }
    }
    $NcCluster = Get-NcCluster -Controller $myController
    $SourceCluster = $NcCluster.ClusterName
    $switch_time=get-date -uformat "%Y%m%d%H%M%S"
    if($Backup.IsPresent){
        $NcVserver=Get-NcVserver -Vserver $myVserver -Controller $myController -ErrorVariable ErrorVar 
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" } 
        $Policy = $NcVserver.QuotaPolicy
        Write-LogDebug "svmdr_db_switch_datafiles: Policy [$Policy]"

        $SVMTOOL_DB_SRC_CLUSTER=$Global:JsonPath + '\' + $SourceCluster + '.cluster'
        $SVMTOOL_DB_SRC_VSERVER=$SVMTOOL_DB_SRC_CLUSTER + '\' + $myVserver + '.vserver'

        $QUOTA_DB_FILE=$SVMTOOL_DB_SRC_VSERVER + '\quotarules.' + $Policy
        $QUOTA_DB_FILE_SWITCH=$QUOTA_DB_FILE + '.' + $switch_time
        if ((Test-Path $QUOTA_DB_FILE) -eq $True ) { 
            Write-LogDebug "svmdr_db_switch_datafiles: switch [$QUOTA_DB_FILE_SWITCH]" ;
            Rename-Item $QUOTA_DB_FILE $QUOTA_DB_FILE_SWITCH
        }
        $QUOTA_DB_FILE=$SVMTOOL_DB_SRC_VSERVER + '\quotarules.' + $Policy + '.err' 
        $QUOTA_DB_FILE_SWITCH=$QUOTA_DB_FILE + '.' + $switch_time
        if ((Test-Path $QUOTA_DB_FILE) -eq $True ) { 
            Write-LogDebug "svmdr_db_switch_datafiles: [$QUOTA_DB_FILE_SWITCH]" ;
            Rename-Item $QUOTA_DB_FILE $QUOTA_DB_FILE_SWITCH
        }
        $VOL_DB_FILE=$SVMTOOL_DB_SRC_VSERVER + '\volume.options'
        $VOL_DB_FILE_SWITCH=$VOL_DB_FILE + '.' + $switch_time
        if ((Test-Path $VOL_DB_FILE) -eq $True ) { 
            Write-LogDebug "svmdr_db_switch_datafiles: switch [$VOL_DB_FILE_SWITCH]" ;
            Rename-Item $VOL_DB_FILE $VOL_DB_FILE_SWITCH
        }
        Write-LogDebug "svmdr_db_switch_datafiles: end"
        return $Return
    }else{
       $relationlist=Get-NcSnapmirrorDestination  -SourceVserver $myVserver -VserverContext $myVserver -Controller $myController  -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapmirrorDestination failed [$ErrorVar]" } 
        if ( $relationlist -eq $null ) { 
            Write-LogDebug "svmdr_db_switch_datafiles: SnapMirror No Relations found"
            return $True
        }
        foreach ( $relation in $relationlist ) {
            $SourceVolume = $relation.SourceVolume
            $SourceVserver = $relation.SourceVserver
            $DestinationVolume = $relation.DestinationVolume
            $DestinationVserver = $relation.DestinationVserver
            $DestinationLocation = $relation.DestinationLocation
            $RelationshipType =$relation.RelationshipType
            if ( ( $RelationshipType -eq "data_protection" -or $RelationshipType -eq "extended_data_protection") -and ( $SourceVserver -ne $DestinationVserver  )  ) {
                $NcVserverPeer=Get-NcVserverPeer -Controller $myController -Vserver $SourceVserver -PeerVserver $DestinationVserver  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserverPeer failed [$ErrorVar]" } 
                $DestinationCluster=$NcVserverPeer.PeerCluster
                Write-LogDebug "svmdr_db_switch_datafiles: [$SourceVserver] [$SourceVolume] -> [$DestinationCluster] [$DestinationVserver] [$DestinationVolume] [$RelationshipType]" ;
                $NcVserver=Get-NcVserver -Vserver $SourceVserver -Controller $myController  -ErrorVariable ErrorVar 
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" } 
                $Policy = $NcVserver.QuotaPolicy
                Write-LogDebug "svmdr_db_switch_datafiles: Policy [$Policy]"

                $SVMTOOL_DB_SRC_CLUSTER=$Global:SVMTOOL_DB + '\' + $SourceCluster + '.cluster'
                $SVMTOOL_DB_SRC_VSERVER=$SVMTOOL_DB_SRC_CLUSTER + '\' +$SourceVserver + '.vserver'

                $QUOTA_DB_FILE=$SVMTOOL_DB_SRC_VSERVER + '\quotarules.' + $Policy
                $QUOTA_DB_FILE_SWITCH=$QUOTA_DB_FILE + '.' + $switch_time
                if ((Test-Path $QUOTA_DB_FILE) -eq $True ) { 
                    Write-LogDebug "svmdr_db_switch_datafiles: switch [$QUOTA_DB_FILE_SWITCH]" ;
                    Rename-Item $QUOTA_DB_FILE $QUOTA_DB_FILE_SWITCH
                }
                $QUOTA_DB_FILE=$SVMTOOL_DB_SRC_VSERVER + '\quotarules.' + $Policy + '.err' 
                $QUOTA_DB_FILE_SWITCH=$QUOTA_DB_FILE + '.' + $switch_time
                if ((Test-Path $QUOTA_DB_FILE) -eq $True ) { 
                    Write-LogDebug "svmdr_db_switch_datafiles: [$QUOTA_DB_FILE_SWITCH]" ;
                    Rename-Item $QUOTA_DB_FILE $QUOTA_DB_FILE_SWITCH
                }
                $VOL_DB_FILE=$SVMTOOL_DB_SRC_VSERVER + '\volume.options'
                $VOL_DB_FILE_SWITCH=$VOL_DB_FILE + '.' + $switch_time
                if ((Test-Path $VOL_DB_FILE) -eq $True ) { 
                    Write-LogDebug "svmdr_db_switch_datafiles: switch [$VOL_DB_FILE_SWITCH]" ;
                    Rename-Item $VOL_DB_FILE $VOL_DB_FILE_SWITCH
                }
                $SVMTOOL_DB_DST_CLUSTER=$Global:SVMTOOL_DB + '\' + $DestinationCluster + '.cluster'
                $SVMTOOL_DB_DST_VSERVER=$SVMTOOL_DB_DST_CLUSTER + '\' +$DestinationVserver + '.vserver'
                $QUOTA_DB_FILE=$SVMTOOL_DB_DST_VSERVER + '\quotarules.' + $Policy
                $QUOTA_DB_FILE_SWITCH=$QUOTA_DB_FILE + '.' + $switch_time
                if ((Test-Path $QUOTA_DB_FILE) -eq $True ) { 
                    Write-LogDebug "svmdr_db_switch_datafiles: switch [$QUOTA_DB_FILE_SWITCH]" ;
                    Rename-Item $QUOTA_DB_FILE $QUOTA_DB_FILE_SWITCH
                }
                $QUOTA_DB_FILE=$SVMTOOL_DB_DST_VSERVER + '\quotarules.' + $Policy + '.err' 
                $QUOTA_DB_FILE_SWITCH=$QUOTA_DB_FILE + '.' + $switch_time
                if ((Test-Path $QUOTA_DB_FILE) -eq $True ) { 
                    Write-LogDebug "svmdr_db_switch_datafiles: [$QUOTA_DB_FILE_SWITCH]" ;
                    Rename-Item $QUOTA_DB_FILE $QUOTA_DB_FILE_SWITCH
                }
                $VOL_DB_FILE=$SVMTOOL_DB_DST_VSERVER + '\volume.options'
                $VOL_DB_FILE_SWITCH=$VOL_DB_FILE + '.' + $switch_time
                if ((Test-Path $VOL_DB_FILE) -eq $True ) { 
                    Write-LogDebug "svmdr_db_switch_datafiles: switch [$VOL_DB_FILE_SWITCH]" ;
                    Rename-Item $VOL_DB_FILE $VOL_DB_FILE_SWITCH
                }
            }
        }	
        Write-LogDebug "svmdr_db_switch_datafiles: end"
        return $Return
    }
}
Catch {
    handle_error $_ $myVserver
	return $Return
}
}

#############################################################################################
Function save_quota_rules_to_quotadb (
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
    [string] $mySecondaryVserver) {
Try {
	$Return = $True
    Write-Log "[$mySecondaryVserver] Save Quota rules"
	Write-LogDebug "save_quota_rules_to_quotadb: Start"
	if ( ( svmdr_db_check -myController $myPrimaryController -myVserver $myPrimaryVserver ) -eq $false ) {
        	Write-LogError "ERROR: Failed to access quotadb" 
		return $False
  	}

	$NcCluster = Get-NcCluster -Controller $myPrimaryController
	$SourceCluster = $NcCluster.ClusterName
    $AllQuotaList=Get-NcQuota -Controller $myPrimaryController -VserverContext $myPrimaryVserver -ErrorVariable ErrorVar 
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcQuota failed [$ErrorVar]" } 
    $AllPeerList=Get-NcVserverPeer -Controller $myPrimaryController -Vserver $SourceVserver -ErrorVariable ErrorVar 
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserverPeer failed [$ErrorVar]" }
	Write-logDebug "Get-NcSnapmirrorDestination -SourceVserver $myPrimaryVserver -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar"
	$relationlist=Get-NcSnapmirrorDestination -SourceVserver $myPrimaryVserver -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapmirrorDestination failed [$ErrorVar]" }
	foreach ( $relation in $relationlist ) {
		$SourceVolume = $relation.SourceVolume
		$SourceVserver = $relation.SourceVserver
		$DestinationVolume = $relation.DestinationVolume
		$DestinationVserver = $relation.DestinationVserver
		$DestinationLocation = $relation.DestinationLocation
		$RelationshipType =$relation.RelationshipType
		if ( ( $RelationshipType -eq "data_protection" -or $RelationshipType -eq "extended_data_protection" ) -and ( $SourceVserver -ne $DestinationVserver  )  ) {
            $NcVserverPeer=$AllPeerList | Where-Object {$_.PeerVserver -eq $DestinationVserver}
	  		$DestinationCluster=$NcVserverPeer.PeerCluster
	  		Write-LogDebug "save_quota_rules_to_quotadb: [$SourceVserver] [$SourceVolume] -> [$DestinationCluster] [$DestinationVserver] [$DestinationVolume] [$RelationshipType]" ;
			$SVMTOOL_DB_SRC_CLUSTER=$Global:SVMTOOL_DB + '\' + $SourceCluster + '.cluster'
			$SVMTOOL_DB_SRC_VSERVER=$SVMTOOL_DB_SRC_CLUSTER + '\' +$SourceVserver + '.vserver'
			$SVMTOOL_DB_DST_CLUSTER=$Global:SVMTOOL_DB + '\' + $DestinationCluster + '.cluster'
            $SVMTOOL_DB_DST_VSERVER=$SVMTOOL_DB_DST_CLUSTER + '\' + $DestinationVserver + '.vserver'
            if($Global:CorrectQuotaError -eq $True){
                check_quota_rules -myController $myPrimaryController -myVserver $Vserver -myVolume $SourceVolume 
            }
            $NcQuotaList=$AllQuotaList | where-object {$_.Volume -eq $SourceVolume}
			if ( $NcQuotaList -ne $null ) {
                foreach ( $quota in $NcQuotaList ) {
                    $NcController = $quota.NcController
                    $Vserver = $quota.Vserver
                    $Volume = $quota.Volume
                    $Qtree = $quota.Qtree
                    $QuotaType = $quota.QuotaType
                    $QuotaTarget = $quota.QuotaTarget
                    $QuotaError = $quota.QuotaError
                    $DiskLimit = $quota.DiskLimit
                    $FileLimit = $quota.FileLimit
                    $SoftDiskLimit = $quota.SoftDiskLimit
                    $SoftFileLimit = $quota.SoftFileLimit
                    $Threshold = $quota.Threshold
                    $Policy = $quota.Policy
                    if ( $QuotaError ) {
                        $Detail=$QuotaError.Detail
                        $Errno=$QuotaError.Errno
                        $Reason=$QuotaError.Reason
                        $QUOTA_DB_DST_FILE=$SVMTOOL_DB_DST_VSERVER + '\quotarules.' + $Policy + '.err'
                        $QUOTA_DB_SRC_FILE=$SVMTOOL_DB_SRC_VSERVER + '\quotarules.' + $Policy + '.err'
                        Write-LogError  "ERROR: Quota: [$Vserver] [$Volume] [$Qtree] [$QuotaTarget]: Error [$Errno] [$Detail] [$Reason]" 
                        $Return = $False
                    } else {
                        #
                        $QUOTA_DB_DST_FILE=$SVMTOOL_DB_DST_VSERVER + '\quotarules.' + $Policy
                        $QUOTA_DB_SRC_FILE=$SVMTOOL_DB_SRC_VSERVER + '\quotarules.' + $Policy
                    }
                    $SourceQuotaTarget = $QuotaTarget
                    if ( $QuotaType -eq 'tree' ) {
                        $DestinationQuotaTarget = $QuotaTarget| ForEach-Object { $_ -replace $SourceVolume, $DestinationVolume }
                    } else {
                        $DestinationQuotaTarget = $QuotaTarget
                    }
                    Write-LogDebug "save_quota_rules_to_quotadb: file [$QUOTA_DB_SRC_FILE]"
                    write-Output "${SourceCluster}:${SourceVserver}:${SourceVolume}:${Qtree}:${QuotaType}:${SourceQuotaTarget}:${DiskLimit}:${FileLimit}:${SoftDiskLimit}:${SoftFileLimit}:${Threshold}" | Out-File -FilePath $QUOTA_DB_SRC_FILE -Append
                    Write-LogDebug "save_quota_rules_to_quotadb: file [$QUOTA_DB_DST_FILE]"
                    write-Output "${DestinationCluster}:${DestinationVserver}:${DestinationVolume}:${Qtree}:${QuotaType}:${DestinationQuotaTarget}:${DiskLimit}:${FileLimit}:${SoftDiskLimit}:${SoftFileLimit}:${Threshold}" | Out-File -FilePath $QUOTA_DB_DST_FILE -Append
                }
            }
        }
 	}
  	Write-LogDebug "save_quota_rules_to_quotadb: Terminate"
  	Return $Return
}
Catch {
    handle_error $_ $myPrimaryVserver
	return $Return
}
}

#############################################################################################
Function get_volumes_from_selectvolumedb (
    [NetApp.Ontapi.Filer.C.NcController] $myController,
    [string] $myVserver) 
{
    Try 
    {
        [hashtable]$Return = @{}
        $Return.state=$True
        Write-LogDebug "get_volumes_from_selectvolumedb: start"
        $NcCluster = Get-NcCluster -Controller $myController
        $SourceCluster = $NcCluster.ClusterName
        $SVMTOOL_DB_SRC_CLUSTER=$Global:SVMTOOL_DB + '\' + $SourceCluster + '.cluster'
        $SVMTOOL_DB_SRC_VSERVER=$SVMTOOL_DB_SRC_CLUSTER + '\' + $myVserver + '.vserver'
        $SELECTVOL_DB_SRC_FILE=$SVMTOOL_DB_SRC_VSERVER + '\selectvolume.db'
        if ( ( Test-Path $SELECTVOL_DB_SRC_FILE ) -eq $false ) {
            Write-LogError "ERROR: Unable to find $SELECTVOL_DB_SRC_FILE"
            Write-LogDebug "get_volumes_from_selectvolumedb:: end with error" 
            $Return.state=$False
            return $Return
        }
        $SelectVolumesList=Get-Content $SELECTVOL_DB_SRC_FILE | sort -Unique
        Write-LogDebug "SelectVolumesList [$SelectVolumesList]"
        Write-LogDebug "get_volumes_from_selectvolumedb: end"
        $Return.volumes=$SelectVolumesList
        Return $Return
    }
    Catch 
    {
        handle_error $_ $myVserver
        return $Return
    }
}


#############################################################################################
Function Is_SelectVolumedb (
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $SourceVserver,
    [string] $DestinationVserver) 
{
    Try 
    {
        Write-LogDebug "Is_SelectVolumedb: start"
        $NcCluster = Get-NcCluster -Controller $myPrimaryController
        $SourceCluster = $NcCluster.ClusterName
        $NcCluster = Get-NcCluster -Controller $mySecondaryController
        $DestinationCluster = $NcCluster.ClusterName
        $SVMTOOL_DB_SRC_CLUSTER=$Global:SVMTOOL_DB + '\' + $SourceCluster + '.cluster'
        $SVMTOOL_DB_SRC_VSERVER=$SVMTOOL_DB_SRC_CLUSTER + '\' + $SourceVserver + '.vserver'
        $SVMTOOL_DB_DST_CLUSTER=$Global:SVMTOOL_DB + '\' + $DestinationCluster + '.cluster'
        $SVMTOOL_DB_DST_VSERVER=$SVMTOOL_DB_DST_CLUSTER + '\' +$DestinationVserver + '.vserver'
        $SELECTVOL_DB_SRC_FILE=$SVMTOOL_DB_SRC_VSERVER + '\selectvolume.db'
        $SELECTVOL_DB_DST_FILE=$SVMTOOL_DB_DST_VSERVER + '\selectvolume.db' 
        if( (( Test-Path $SELECTVOL_DB_SRC_FILE ) -eq $true) -or (( Test-Path $SELECTVOL_DB_DST_FILE ) -eq $true) ) {
            Write-LogDebug "Config with SelectVolumeDB present"
            Write-LogDebug "Is_SelectVolumedb: end"
            return $true
        }else{
            Write-LogDebug "Config without SelectVolumeDB present"
            Write-LogDebug "Is_SelectVolumedb: end"
            return $False   
        }    
    }catch{
        handle_error $_ $SourceVserver
    	return $Return
    }
}

#############################################################################################
Function Purge_SelectVolumedb (
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $SourceVserver,
    [string] $DestinationVserver) 
{
    Try 
    {
        Write-LogDebug "Purge_SelectVolumedb: start"
        $NcCluster = Get-NcCluster -Controller $myPrimaryController
        $SourceCluster = $NcCluster.ClusterName
        $NcCluster = Get-NcCluster -Controller $mySecondaryController
        $DestinationCluster = $NcCluster.ClusterName
        $SVMTOOL_DB_SRC_CLUSTER=$Global:SVMTOOL_DB + '\' + $SourceCluster + '.cluster'
        $SVMTOOL_DB_SRC_VSERVER=$SVMTOOL_DB_SRC_CLUSTER + '\' + $SourceVserver + '.vserver'
        $SVMTOOL_DB_DST_CLUSTER=$Global:SVMTOOL_DB + '\' + $DestinationCluster + '.cluster'
        $SVMTOOL_DB_DST_VSERVER=$SVMTOOL_DB_DST_CLUSTER + '\' +$DestinationVserver + '.vserver'
        $SELECTVOL_DB_SRC_FILE=$SVMTOOL_DB_SRC_VSERVER + '\selectvolume.db'
        $SELECTVOL_DB_DST_FILE=$SVMTOOL_DB_DST_VSERVER + '\selectvolume.db' 
        if( ( Test-Path $SELECTVOL_DB_SRC_FILE ) -eq $true ) {
            $PreviousSelectVolumes=Get-Content $SELECTVOL_DB_SRC_FILE
            Write-LogDebug "Remove existing db [$SELECTVOL_DB_SRC_FILE]"
            $out=Remove-Item $SELECTVOL_DB_SRC_FILE -Confirm:$false -ErrorVariable ErrorVar
        }
        if( ( Test-Path $SELECTVOL_DB_DST_FILE ) -eq $true ) {
            $PreviousSelectVolumes=Get-Content $SELECTVOL_DB_DST_FILE
            Write-LogDebug "Remove existing db [$SELECTVOL_DB_DST_FILE]"
            $out=Remove-Item $SELECTVOL_DB_DST_FILE -Confirm:$false -ErrorVariable ErrorVar
        }
        Write-LogDebug "Get-NcSnapmirror -DestinationCluster $DestinationCluster -DestinationVserver $DestinationVserver -SourceCluster $SourceCluster -SourceVserver $SourceVserver -VserverContext $mySecondaryVserver -Controller $mySecondaryController"
	    $PreviousRelationship=Get-NcSnapmirror -DestinationCluster $DestinationCluster -DestinationVserver $DestinationVserver -SourceCluster $SourceCluster -SourceVserver $SourceVserver -VserverContext $DestinationVserver -Controller $mySecondaryController -ErrorVariable ErrorVar
	    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapmirror failed [$ErrorVar]" }
        Write-LogDebug "Get-NcVol -Vserver $DestinationVserver -Controller $mySecondaryController"
        $out=Get-NcVol -Vserver $DestinationVserver -Controller $mySecondaryController -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
        if($out -ne $null){
            $ExistingVolumesOnDest=($out).Name
        }else{
            $ExistingVolumesOnDest=$null
        }
        if($ExistingVolumesOnDest -eq $null){
            if($PreviousRelationship -ne $null){
                $PreviousRelationship=$PreviousRelationship.SourceVolume
                Write-LogDebug "PreviousRelationship [$PreviousRelationship]"
                Write-LogDebug "Purge_SelectVolumedb: end"
                return $PreviousRelationship
            }
            Write-LogDebug "PreviousSelectVolumes [$PreviousSelectVolumes]"
            Write-LogDebug "Purge_SelectVolumedb: end"
            return $PreviousSelectVolumes
        }else{
            Write-LogDebug "ExistingVolumesOnDest [$ExistingVolumesOnDest]"
            Write-LogDebug "Purge_SelectVolumedb: end"
            return $ExistingVolumesOnDest
        }
           
    }catch{
        handle_error $_ $SourceVserver
    	return $Return
    }
}

#############################################################################################
Function Save_Volume_To_Selectvolumedb (
    [NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $SourceVserver,
    [string] $DestinationVserver,
    [string] $volumeName) 
{
    Try 
    {
        $Return = $True
        Write-LogDebug "Save_Volume_To_Selectvolumedb: start"
        $NcCluster = Get-NcCluster -Controller $myPrimaryController
        $SourceCluster = $NcCluster.ClusterName
        $NcCluster = Get-NcCluster -Controller $mySecondaryController
        $DestinationCluster = $NcCluster.ClusterName
        $SVMTOOL_DB_SRC_CLUSTER=$Global:SVMTOOL_DB + '\' + $SourceCluster + '.cluster'
        $SVMTOOL_DB_SRC_VSERVER=$SVMTOOL_DB_SRC_CLUSTER + '\' + $SourceVserver + '.vserver'

        if ( ( Test-Path $SVMTOOL_DB_SRC_CLUSTER -pathType container ) -eq $false ) {
                $out=new-item -Path $SVMTOOL_DB_SRC_CLUSTER -ItemType directory
                if ( ( Test-Path $SVMTOOL_DB_SRC_CLUSTER -pathType container ) -eq $false ) {
                        Write-LogError "ERROR: Unable to create new item $SVMTOOL_DB_SRC_CLUSTER" 
                        return $False
                }
        }

        if ( ( Test-Path $SVMTOOL_DB_SRC_VSERVER -pathType container ) -eq $false ) {
                $out=new-item -Path $SVMTOOL_DB_SRC_VSERVER -ItemType directory
                if ( ( Test-Path $SVMTOOL_DB_SRC_VSERVER -pathType container ) -eq $false ) {
                        Write-LogError "ERROR: Unable to create new item $SVMTOOL_DB_SRC_VSERVER" 
                        return $False
                }
        }

        $SVMTOOL_DB_DST_CLUSTER=$Global:SVMTOOL_DB + '\' + $DestinationCluster + '.cluster'
        $SVMTOOL_DB_DST_VSERVER=$SVMTOOL_DB_DST_CLUSTER + '\' +$DestinationVserver + '.vserver'

        if ( ( Test-Path $SVMTOOL_DB_DST_CLUSTER -pathType container ) -eq $false ) {
                $out=new-item -Path $SVMTOOL_DB_DST_CLUSTER -ItemType directory
                if ( ( Test-Path $SVMTOOL_DB_DST_CLUSTER -pathType container ) -eq $false ) {
                        Write-LogError "ERROR: Unable to create new item $SVMTOOL_DB_DST_CLUSTER" 
                        return $False
                }
        }

        if ( ( Test-Path $SVMTOOL_DB_DST_VSERVER -pathType container ) -eq $false ) {
                $out=new-item -Path $SVMTOOL_DB_DST_VSERVER -ItemType directory
                if ( ( Test-Path $SVMTOOL_DB_DST_VSERVER -pathType container ) -eq $false ) {
                        Write-LogError "ERROR: Unable to create new item $SVMTOOL_DB_DST_VSERVER" 
                        return $False
                }
        }

        $SELECTVOL_DB_SRC_FILE=$SVMTOOL_DB_SRC_VSERVER + '\selectvolume.db'
        $SELECTVOL_DB_DST_FILE=$SVMTOOL_DB_DST_VSERVER + '\selectvolume.db'
        Write-LogDebug "Save_Volume_To_Selectvolumedb: file [$SELECTVOL_DB_SRC_FILE] volume [$volumeName]"
        write-Output "$volumeName" | Out-File -FilePath $SELECTVOL_DB_SRC_FILE -Append -NoClobber
        Write-LogDebug "Save_Volume_To_Selectvolumedb: file [$SELECTVOL_DB_DST_FILE] volume [$volumeName]"
        write-Output "$volumeName" | Out-File -FilePath $SELECTVOL_DB_DST_FILE -Append -NoClobber

        Write-LogDebug "Save_Volume_To_Selectvolumedb: end"

        Return $Return
    }
    Catch 
    {
        handle_error $_ $SourceVserver
    	return $Return
    }
}

#############################################################################################
Function save_vol_options_to_voldb (
	[NetApp.Ontapi.Filer.C.NcController] $myController,
    [string] $myVserver,
    [switch] $Backup) 
{
    Try 
    {
        Write-Log "[$myVserver] Save volumes options"
    	$Return = $True
    	Write-LogDebug "save_vol_options_to_voldb: start"
    	if ( ( svmdr_db_check -myController $myController -myVserver $myVserver ) -eq $false ) {
    		Write-LogError "ERROR: Failed to access quotadb" 
            Write-LogDebug "save_vol_options_to_voldb: end"
    		return $False
    	}
    	$NcCluster = Get-NcCluster -Controller $myController
    	$SourceCluster = $NcCluster.ClusterName
    	Write-LogDebug "Get-NcSnapmirrorDestination -SourceVserver $myVserver -VserverContext $myVserver -Controller $myController"
    	$relationlist=Get-NcSnapmirrorDestination -SourceVserver $myVserver -VserverContext $myVserver -Controller $myController  -ErrorVariable ErrorVar
    	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapmirrorDestination failed [$ErrorVar]" }
        #$count_delete_SRC=0
        #$count_delete_DST=0
    	foreach ( $relation in $relationlist ) {
    		$SourceVolume = $relation.SourceVolume
    		$SourceVserver = $relation.SourceVserver
    		$DestinationVolume = $relation.DestinationVolume
    		$DestinationVserver = $relation.DestinationVserver
    		$DestinationLocation = $relation.DestinationLocation
    		$RelationshipType = $relation.RelationshipType
    		if ( ( $RelationshipType -eq "data_protection" -or $RelationshipType -eq "extended_data_protection" ) -and ( $SourceVserver -ne $DestinationVserver  )  ) 
            {
    			$NcVserverPeer=Get-NcVserverPeer -Controller $myController -Vserver $SourceVserver -PeerVserver $DestinationVserver  -ErrorVariable ErrorVar 
    			if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserverPeer failed [$ErrorVar]" } 
    			$DestinationCluster=$NcVserverPeer.PeerCluster
    			Write-LogDebug "save_vol_options_to_voldb: [$SourceVserver] [$SourceVolume] -> [$DestinationCluster] [$DestinationVserver] [$DestinationVolume] [$RelationshipType]" ;
    			$SVMTOOL_DB_SRC_CLUSTER=$Global:SVMTOOL_DB + '\' + $SourceCluster + '.cluster'
    			$SVMTOOL_DB_SRC_VSERVER=$SVMTOOL_DB_SRC_CLUSTER + '\' +$SourceVserver + '.vserver'
    			$SVMTOOL_DB_DST_CLUSTER=$Global:SVMTOOL_DB + '\' + $DestinationCluster + '.cluster'
    			$SVMTOOL_DB_DST_VSERVER=$SVMTOOL_DB_DST_CLUSTER + '\' + $DestinationVserver + '.vserver'
                try{
                    $out=New-Item -ItemType Directory -Path $SVMTOOL_DB_SRC_VSERVER -Force  -ErrorVariable ErrorVar
                }catch{
                    Write-LogDebug "cannot create [$SVMTOOL_DB_SRC_VSERVER], reason [$ErrorVar]"    
                }
                try{
                    $out=New-Item -ItemType Directory -Path $SVMTOOL_DB_DST_VSERVER -Force  -ErrorVariable ErrorVar
                }catch{
                    Write-LogDebug "cannot create [$SVMTOOL_DB_DST_VSERVER], reason [$ErrorVar]"    
                }
    			$VOL_DB_SRC_FILE=$SVMTOOL_DB_SRC_VSERVER + '\volume.options'
    			$VOL_DB_DST_FILE=$SVMTOOL_DB_DST_VSERVER + '\volume.options'
     			# Create all missing Destination Volumes
                Write-logDebug "Get-NcVol -Name $SourceVolume -Controller $myController -Vserver $myVserver"
    			$PrimaryVol = Get-NcVol -Name $SourceVolume -Controller $myController -Vserver $myVserver  -ErrorVariable ErrorVar 
    			if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" } 
    			$PrimaryVolName=$PrimaryVol.Name
    			$PrimaryVolStyle=$PrimaryVol.VolumeSecurityAttributes.Style
    			$PrimaryVolExportPolicy=$PrimaryVol.VolumeExportAttributes.Policy
    			$PrimaryVolType=$PrimaryVol.VolumeIdAttributes.Type
    			$PrimaryVolLang=$PrimaryVol.VolumeLanguageAttributes.LanguageCode
    			$PrimaryVolSize=$PrimaryVol.VolumeSpaceAttributes.Size
    			$PrimaryVolIsSis=$PrimaryVol.VolumeSisAttributes.IsSisVolume
    			$PrimaryVolSpaceGuarantee=$PrimaryVol.VolumeSpaceAttributes.SpaceGuarantee
    			$PrimaryVolState=$PrimaryVol.State
    			$PrimaryVolJunctionPath=$PrimaryVol.VolumeIdAttributes.JunctionPath
    			$PrimaryVolIsInfiniteVolume=$PrimaryVol.IsInfiniteVolume
    			$PrimaryVolSnapshotPolicy=$PrimaryVol.VolumeSnapshotAttributes.SnapshotPolicy
                $PrimarySisSchedule=""
                $PrimarySisPolicy=""
                $PrimarySisState=""
                if ($PrimaryVolIsSis -eq $True)
                {
                    $PrimaryVol = Get-NcSis -Name $SourceVolume -Controller $myController -Vserver $myVserver  -ErrorVariable ErrorVar 
    			    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
                    $PrimarySisSchedule=$PrimaryVol.Schedule
                    $PrimarySisPolicy=$PrimaryVol.Policy
                    $PrimarySisState=$PrimaryVol.State   
                }
    			Write-LogDebug "save_vol_options_to_voldb: file [$VOL_DB_SRC_FILE]"
                <#if( (Test-Path $VOL_DB_SRC_FILE) -eq $True -and $count_delete_SRC -eq 0)
                { 
                    Remove-Item -path $VOL_DB_SRC_FILE | out-null
                    $count_delete_SRC++
                }#>
    			write-Output "${PrimaryVolName}:${PrimaryVolSnapshotPolicy}:${PrimarySisPolicy}:${PrimarySisSchedule}:${PrimarySisState}" | Out-File -FilePath $VOL_DB_SRC_FILE -Append -NoClobber
                <#if( (Test-Path $VOL_DB_DST_FILE) -eq $True -and $count_delete_DST -eq 0)
                { 
                    Remove-Item -path $VOL_DB_DST_FILE | out-null
                    $count_delete_DST++
                }#>
    			Write-LogDebug "save_vol_options_to_voldb: file [$VOL_DB_DST_FILE]"
    			write-Output "${PrimaryVolName}:${PrimaryVolSnapshotPolicy}:${PrimarySisPolicy}:${PrimarySisSchedule}:${PrimarySisState}" | Out-File -FilePath $VOL_DB_DST_FILE -Append -NoClobber
    	 	}
      	}
    	Write-LogDebug "save_vol_options_to_voldb: end"
    	Return $Return
    }
    Catch 
    {
        handle_error $_ $myVserver
    	return $Return
    }
}

#############################################################################################
Function set_vol_options_from_voldb (
	[NetApp.Ontapi.Filer.C.NcController] $myController,
	[string] $myVserver,
    [switch] $NoCheck,
    [switch] $Restore,
    [string] $CloneDR="") 
{
    Try 
    {
    	$Return = $true
        Write-logDebug "set_vol_options_from_voldb: start"
        if($Restore.IsPresent -or $Restore -eq $True){
            if(Test-Path $($Global:JsonPath+"Get-NcVserver.json")){
                $PrimaryVserver=Get-Content $($Global:JsonPath+"Get-NcVserver.json") | ConvertFrom-Json
            }else{
                $Return=$False
                $filepath=$($Global:JsonPath+"Get-NcVserver.json")
                Throw "ERROR: failed to read $filepath"
            }
            if(Test-Path $($Global:JsonPath+"Get-NcVol.json")){
                $PrimaryVolumes=Get-Content $($Global:JsonPath+"Get-NcVol.json") | ConvertFrom-Json
            }else{
                $Return=$False
                $filepath=$($Global:JsonPath+"Get-NcVol.json")
                Throw "ERROR: failed to read $filepath"
            }
            if(Test-Path $($Global:JsonPath+"Get-NcSis.json")){
                $PrimarySis=Get-Content $($Global:JsonPath+"Get-NcSis.json") | ConvertFrom-Json
            }else{
                $Return=$False
                $filepath=$($Global:JsonPath+"Get-NcSis.json")
                Throw "ERROR: failed to read $filepath"
            }
            foreach($vol in $PrimaryVolumes | Where-object {$_.Name -ne $PrimaryVserver.RootVolume}){
                $VolName=$vol.Name
                $VolSnapshotPolicy=$vol.VolumeSnapshotAttributes.SnapshotPolicy
                $VolSisPolicy=($PrimarySis | Where-Object {$_.Path -eq $("/vol/"+$VolName)}).Policy
                $VolSisSchedule=($PrimarySis | Where-Object {$_.Path -eq $("/vol/"+$VolName)}).Schedule
                $VolSisState=($PrimarySis | Where-Object {$_.Path -eq $("/vol/"+$VolName)}).State
                Write-LogDebug "Volume Options [$VolName] SnapshotPolicy [$VolSnapshotPolicy] SisPolicy [$VolSisPolicy] SisSchedule [$VolSisSchedule]"
                if($VolSisPolicy.length -eq 0 -and $VolSisSchedule.length -eq 0){
                    Write-LogDebug "Ignore volume [$VolName]"
                    continue
                }
                $myVol = Get-NcVol -Controller $myController -Vserver $myVserver -Volume $VolName  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
                if ( $myVol -ne $null ) 
                {
                    $myVolSnapshotPolicy=$myVol.VolumeSnapshotAttributes.SnapshotPolicy
                    if ( ($VolSnapshotPolicy -ne $myVolSnapshotPolicy) -and ($Global:ForceUpdateSnapPolicy -eq $True) ) 
                    {
                        Write-LogDebug "Current SnapshotPolicy for [$VolName] is [$myVolSnapshotPolicy], need this one [$VolSnapshotPolicy]"
                        $attributes = Get-NcVol -Template -controller $myController
                        $mySnapshotAttributes= New-Object "DataONTAP.C.Types.Volume.VolumeSnapshotAttributes"
                        $mySnapshotAttributes.SnapshotPolicy= $VolSnapshotPolicy
                        $attributes.VolumeSnapshotAttributes=$mySnapshotAttributes
                        $tmpStr=$attributes.VolumeSnapshotAttributes.SnapshotPolicy
                        Write-LogDebug "attributes[$tmpStr]"
                        $query=Get-NcVol -Template -controller $myController
                        $query.name=$VolName
                        $query.vserver=$myVserver
                        $query.NcController=$myController
                        Write-LogDebug "Update-NcVol -Controller $myController -Query `$query -Attributes `$attributes"
                        Write-Log "[$myVserver] Update Snapshot Policy [$VolSnapshotPolicy] on volume [$VolName]"
                        $out=Update-NcVol -Controller $myController -Query $query -Attributes $attributes  -ErrorVariable ErrorVar 
                        if ( $? -ne $True ) { $Return = $False ; Write-LogError "ERROR: Update-NcVol Failed: Failed to update volume  $VolName [$ErrorVar]" }
                        $message=$out.FailureList.ErrorMessage
                        if ( $out.FailureCount -ne 0 ) { $Return = $False ; Write-LogError "ERROR: Update-NcVol failed to update volume [$VolName] [$message]" }
                    }
                    if ($VolSisState -eq "enabled"){
                        Write-LogDebug "Enable-NcSis -Name $VolName -VserverContext $myVserver -controller $myController"
                        Write-Log "[$myVserver] Enable Efficiency on volume [$VolName]"
                        $ret=Enable-NcSis -Name $VolName -VserverContext $myVserver -controller $myController -ErrorVariable ErrorVar 
                        if ( $? -ne $True ) { $Return = $False ; Write-LogDebug "ERROR: Enable-NcSis Failed to update volume  $VolName [$ErrorVar]" } 
                    }
                    if ($VolSisState -eq "disabled"){
                        Write-LogDebug "Disable-NcSis -Name $VolName -VserverContext $myVserver -controller $myController"
                        Write-Log "[$myVserver] Disable Efficiency on volume [$VolName]"
                        $ret=Disable-NcSis -Name $VolName -VserverContext $myVserver -controller $myController -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; Write-LogDebug "ERROR: Disable-NcSis Failed to update volume  $VolName [$ErrorVar]" }
                    }
                    if ( $VolSisSchedule -eq "-" -and $VolSisPolicy.length -gt 0 )
                    {
                        Write-LogDebug "Get-NcSis -Name $VolName -Vserver $myVserver -Controller $myController  -ErrorVariable ErrorVar"
                        $SisInfo=Get-NcSis -Name $VolName -Vserver $myVserver -Controller $myController  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; Write-LogError "ERROR: Get-NcSis Failed for volume  $VolName [$ErrorVar]" }
                        if($SisInfo -eq $null){$myVolSisPolicy=""}else{
                            $myVolSisPolicy=$SisInfo.Policy
                        }
                        if ($myVolSisPolicy -ne $VolSisPolicy)
                        {
                            Write-LogDebug "Current Efficiency Policy [$VolName] [$myVolSisPolicy], need [$VolSisPolicy]"
                            Write-LogDebug "Set-NcSis -name $VolName -VserverContext $myVserver -controller $myController -policy $VolSisPolicy  -ErrorVariable ErrorVar"
                            Write-Log "[$myVserver] Set Efficiency Policy [$VolSisPolicy] on volume [$VolName]"
                            $out=Set-NcSis -name $VolName -VserverContext $myVserver -controller $myController -policy $VolSisPolicy  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; Write-LogError "ERROR: Set-NcSis Failed to update volume  $VolName [$ErrorVar]" }
                        }      
                    }
                    if ($VolSisPolicy.length -eq 0 -and $VolSisSchedule -ne "-")
                    {
                        Write-LogDebug "Get-NcSis -Name $VolName -Vserver $myVserver -Controller $myController  -ErrorVariable ErrorVar"
                        $SisInfo=Get-NcSis -Name $VolName -Vserver $myVserver -Controller $myController  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; Write-LogError "ERROR: Get-NcSis Failed for volume  $VolName [$ErrorVar]" }
                        if($SisInfo -eq $null){$myVolSisSchedule=""}else{
                            $myVolSisSchedule=$SisInfo.Schedule
                        }
                        if($myVolSisSchedule -ne $VolSisSchedule)
                        {
                            Write-LogDebug "Current Efficiency Schedule [$VolName] [$myVolSisSchedule], need [$VolSisSchedule]"
                            Write-LogDebug "Set-NcSis -name $VolName -VserverContext $myVserver -controller $myController -schedule $VolSisSchedule  -ErrorVariable ErrorVar"
                            Write-Log "[$myVserver] Set Efficiency Schedule [$VolSisSchedule] on volume [$VolName]"
                            $out=Set-NcSis -name $VolName -VserverContext $myVserver -controller $myController -schedule $VolSisSchedule  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; Write-LogDebug "ERROR: Set-NcSis Failed: Failed to update volume  $VolName [$ErrorVar]"}       
                        }
                    }
                }
            }
        }elseif($CloneDR.length -gt 1){
            $VolumeListToRestartQuota= @()
            if ( $myVserver -eq $null ) { $myVserver = "*" }
            Write-Log "[$CloneDR] Set volumes options from SVMTOOL_DB [$Global:SVMTOOL_DB]"
            if ( $myVolume -eq $null ) { $myVolume  = "*" }
            $NcCluster = Get-NcCluster -Controller $myController
            $ClusterName = $NcCluster.ClusterName
            Write-LogDebug "set_vol_options_from_voldb: ClusterName [$ClusterName]"
            $SVMTOOL_DB_CLUSTER=$Global:SVMTOOL_DB + '\' + $ClusterName  + '.cluster'
            if ( ( Test-Path $SVMTOOL_DB_CLUSTER -pathType container ) -eq $false ) 
            {
                Write-LogError "ERROR: Cluster [$ClusterName] not found in SVMTOOL_DB [$Global:SVMTOOL_DB]" 
                return $false
            }
            if ( ( Test-Path $SVMTOOL_DB_CLUSTER/$myVserver.vserver -pathType container ) -eq $false ) 
            {
                Write-LogError "ERROR: Vserver [$ClusterName] [$myVserver] not found in SVMTOOL_DB [$Global:SVMTOOL_DB]"
                return $false
            }
            Write-LogDebug "set_vol_options_from_voldb: SVMTOOL_DB_CLUSTER [$SVMTOOL_DB_CLUSTER]"
            $VserverListItem = Get-Item "${SVMTOOL_DB_CLUSTER}/${myVserver}.vserver"
            if ( $VserverListItem -eq $null ) 
            {
                Write-Warning "No Vserver File found in SVMTOOL_DB_CLUSTER [$SVMTOOL_DB_CLUSTER]"  
            } 
            else 
            {
                foreach ( $VserverItem in  ( $VserverListItem  | Skip-Null ) ) 
                {
                    $VserverItemName=$VserverItem.Name
                    $VserverName=$VserverItemName.Split('.')[0] 
                    $VOL_DB_VSERVER=$SVMTOOL_DB_CLUSTER + '\' + $VserverItemName
                    $VOL_DB_FILE=$VOL_DB_VSERVER + '\volume.options'
                    Write-LogDebug "set_vol_options_from_voldb: read VOL_DB_FILE for Cluster [$ClusterName] Vserver [$VserverName] [$VOL_DB_FILE]"
                    if ( ( Test-Path $VOL_DB_FILE  )  -eq $false ) 
                    {
                        Write-Warning "No Volumes files found for Cluster [$ClusterName] Vserver [$VserverName]"  
                    } 
                    else 
                    {
                        $CheckVserver=Get-NcVserver -Controller $myController -Name $CloneDR
                        if ( $CheckVserver -eq $null ) 
                        {
                            Write-LogError "ERROR: [$ClusterName] [$CloneDR] no such vserver" 
                            $Return = $false
                        } 
                        else 
                        {
                            Get-Content $VOL_DB_FILE | Select-Object -uniq | foreach {
                                $VolName=$_.split(':')[0]
                                $VolSnapshotPolicy=$_.split(':')[1]
                                $VolSisPolicy=$_.split(':')[2]
                                $VolSisSchedule=$_.split(':')[3]
                                $VolSisState=$_.split(':')[4]
                                Write-LogDebug "Volume Options [$VolName] SnapshotPolicy [$VolSnapshotPolicy] SisPolicy [$VolSisPolicy] SisSchedule [$VolSisSchedule]"
                                if($VolSisPolicy.length -eq 0 -and $VolSisSchedule.length -eq 0){
                                    Write-LogDebug "Ignore volume [$VolName]"
                                    continue
                                }
                                $myVol = Get-NcVol -Controller $myController -Vserver $CloneDR -Volume $VolName  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
                                if ( $myVol -ne $null ) 
                                {
                                    $myVolSnapshotPolicy=$myVol.VolumeSnapshotAttributes.SnapshotPolicy
                                    Write-LogDebug "Current SnapshotPolicy for [$VolName] is [$myVolSnapshotPolicy], need this one [$VolSnapshotPolicy]"
                                    if ( ($VolSnapshotPolicy -ne $myVolSnapshotPolicy) -and $Global:ForceUpdateSnapPolicy.IsPresent) 
                                    {
                                        $attributes = Get-NcVol -Template -Controller $myController
                                        $mySnapshotAttributes= New-Object "DataONTAP.C.Types.Volume.VolumeSnapshotAttributes"
                                        $mySnapshotAttributes.SnapshotPolicy= $VolSnapshotPolicy
                                        $attributes.VolumeSnapshotAttributes=$mySnapshotAttributes
                                        $tmpStr=$attributes.VolumeSnapshotAttributes.SnapshotPolicy
                                        Write-LogDebug "attributes[$tmpStr]"
                                        $query=Get-NcVol -Template -Controller $myController
                                        $query.name=$VolName
                                        $query.vserver=$CloneDR
                                        $query.NcController=$myController
                                        Write-LogDebug "Update-NcVol -Controller $myController -Query `$query -Attributes `$attributes"
                                        Write-Log "[$CloneDR] Update Snapshot Policy [$VolSnapshotPolicy] on volume [$VolName]"
                                        $out=Update-NcVol -Controller $myController -Query $query -Attributes $attributes  -ErrorVariable ErrorVar 
                                        if ( $? -ne $True ) { $Return = $False ; Write-LogError "ERROR: Update-NcVol Failed: Failed to update volume  $VolName [$ErrorVar]" }
                                        $message=$out.FailureList.ErrorMessage
                                        if ( $out.FailureCount -ne 0 ) { $Return = $False ; Write-LogError "ERROR: Update-NcVol Failed: Failed to update volume [$VolName] [$message]" }
                                    }
                                    Write-LogDebug "Enable-NcSis -Name $VolName -VserverContext $CloneDR -controller $myController"
                                    #Write-Log "[$CloneDR] Enable Efficiency on volume [$VolName]"
                                    $ret=Enable-NcSis -Name $VolName -VserverContext $CloneDR -controller $myController -ErrorVariable ErrorVar 
                                    if ( $? -ne $True ) { $Return = $False ; write-logdebug "ERROR: Enable-NcSis Failed to update volume  $VolName [$ErrorVar]" }
                                    if ( $VolSisSchedule -eq "-" -and $VolSisPolicy.length -gt 0 )
                                    {
                                        Write-LogDebug "Get-NcSis -Name $VolName -Vserver $CloneDR -Controller $myController  -ErrorVariable ErrorVar"
                                        $SisInfo=Get-NcSis -Name $VolName -Vserver $CloneDR -Controller $myController  -ErrorVariable ErrorVar
                                        if ( $? -ne $True ) { $Return = $False ; Write-LogError "ERROR: Get-NcSis Failed for volume  $VolName [$ErrorVar]"}
                                        if($SisInfo -eq $null){$myVolSisPolicy=""}else{
                                            $myVolSisPolicy=$SisInfo.Policy
                                        }
                                        if ($myVolSisPolicy -ne $VolSisPolicy)
                                        {
                                            Write-LogDebug "Current Efficiency Policy [$VolName] [$myVolSisPolicy] [$VolSisPolicy]"
                                            Write-LogDebug "Set-NcSis -name $VolName -VserverContext $CloneDR -controller $myController -policy $VolSisPolicy  -ErrorVariable ErrorVar"
                                            Write-Log "[$CloneDR] Set Efficiency Policy [$VolSisPolicy] on volume [$VolName]"
                                            $out=Set-NcSis -name $VolName -VserverContext $CloneDR -controller $myController -policy $VolSisPolicy  -ErrorVariable ErrorVar
                                            if ( $? -ne $True ) { $Return = $False ; write-logdebug "ERROR: Set-NcSis Failed: Failed to update volume  $VolName [$ErrorVar]"}
                                        }   
                                    }
                                    if ($VolSisPolicy.length -eq 0 -and $VolSisSchedule -ne "-")
                                    {
                                        Write-LogDebug "Get-NcSis -Name $VolName -Vserver $CloneDR -Controller $myController  -ErrorVariable ErrorVar"
                                        $SisInfo=Get-NcSis -Name $VolName -Vserver $CloneDR -Controller $myController  -ErrorVariable ErrorVar
                                        if ( $? -ne $True ) { $Return = $False ; Write-LogError "ERROR: Get-NcSis Failed for volume  $VolName [$ErrorVar]"}
                                        if($SisInfo -eq $null){$myVolSisSchedule=""}else{
                                            $myVolSisSchedule=$SisInfo.Schedule
                                        }
                                        if($myVolSisSchedule -ne $VolSisSchedule)
                                        {
                                            Write-LogDebug "Current Efficiency Schedule [$VolName] [$myVolSisSchedule] [$VolSisSchedule]"
                                            Write-LogDebug "Set-NcSis -name $VolName -VserverContext $CloneDR -controller $myController -schedule $VolSisSchedule  -ErrorVariable ErrorVar"
                                            Write-Log "[$CloneDR] Set Efficiency Schedule [$VolSisSchedule] on volume [$VolName]"
                                            $out=Set-NcSis -name $VolName -VserverContext $CloneDR -controller $myController -schedule $VolSisSchedule  -ErrorVariable ErrorVar
                                            if ( $? -ne $True ) { $Return = $False ; write-logdebug "ERROR: Set-NcSis Failed: Failed to update volume  $VolName [$ErrorVar]" }       
                                        }
                                    }
                                    if ($VolSisState -eq "enabled"){
                                        Write-LogDebug "Enable-NcSis -Name $VolName -VserverContext $CloneDR -controller $myController"
                                        Write-Log "[$CloneDR] Enable Efficiency on volume [$VolName]"
                                        $ret=Enable-NcSis -Name $VolName -VserverContext $CloneDR -controller $myController -ErrorVariable ErrorVar 
                                        if ( $? -ne $True ) { $Return = $False ; write-logdebug "ERROR: Enable-NcSis Failed to update volume  $VolName [$ErrorVar]" } 
                                    }
                                    if ($VolSisState -eq "disabled"){
                                        Write-LogDebug "Disable-NcSis -Name $VolName -VserverContext $CloneDR -controller $myController"
                                        Write-Log "[$CloneDR] Disable Efficiency on volume [$VolName]"
                                        $ret=Disable-NcSis -Name $VolName -VserverContext $CloneDR -controller $myController -ErrorVariable ErrorVar
                                        if ( $? -ne $True ) { $Return = $False ; write-logdebug "ERROR: Disable-NcSis Failed to update volume  $VolName [$ErrorVar]" }
                                    }
                                }
                            }   
                        }
                    }
                }
            }
        }else{
            $VolumeListToRestartQuota= @()
            if($NoCheck -eq $False){
                if ( ( svmdr_db_check -myController $myController -myVserver $myVserver ) -eq $false ) 
                {
                    Write-LogError "ERROR: Failed to access quotadb" 
                    return $False
                }
            }
            if ( $myVserver -eq $null ) { $myVserver = "*" }
            Write-Log "[$myVserver] Set volumes options from SVMTOOL_DB [$Global:SVMTOOL_DB]"
            if ( $myVolume -eq $null ) { $myVolume  = "*" }
            $NcCluster = Get-NcCluster -Controller $myController
            $ClusterName = $NcCluster.ClusterName
            Write-LogDebug "set_vol_options_from_voldb: ClusterName [$ClusterName]"
            $SVMTOOL_DB_CLUSTER=$Global:SVMTOOL_DB + '\' + $ClusterName  + '.cluster'
            if ( ( Test-Path $SVMTOOL_DB_CLUSTER -pathType container ) -eq $false ) 
            {
                Write-LogError "ERROR: Cluster [$ClusterName] not found in SVMTOOL_DB [$Global:SVMTOOL_DB]" 
                return $false
            }
            if ( ( Test-Path $SVMTOOL_DB_CLUSTER/$myVserver.vserver -pathType container ) -eq $false ) 
            {
                Write-LogError "ERROR: Vserver [$ClusterName] [$myVserver] not found in SVMTOOL_DB [$Global:SVMTOOL_DB]"
                return $false
            }
            Write-LogDebug "set_vol_options_from_voldb: SVMTOOL_DB_CLUSTER [$SVMTOOL_DB_CLUSTER]"
            $VserverListItem = Get-Item "${SVMTOOL_DB_CLUSTER}/${myVserver}.vserver"
            if ( $VserverListItem -eq $null ) 
            {
                Write-Warning "No Vserver File found in SVMTOOL_DB_CLUSTER [$SVMTOOL_DB_CLUSTER]"  
            } 
            else 
            {
                foreach ( $VserverItem in  ( $VserverListItem  | Skip-Null ) ) 
                {
                    $VserverItemName=$VserverItem.Name
                    $VserverName=$VserverItemName.Split('.')[0] 
                    $VOL_DB_VSERVER=$SVMTOOL_DB_CLUSTER + '\' + $VserverItemName
                    $VOL_DB_FILE=$VOL_DB_VSERVER + '\volume.options'
                    Write-LogDebug "set_vol_options_from_voldb: read VOL_DB_FILE for Cluster [$ClusterName] Vserver [$VserverName] [$VOL_DB_FILE]"
                    if ( ( Test-Path $VOL_DB_FILE  )  -eq $false ) 
                    {
                        Write-Warning "No Volumes files found for Cluster [$ClusterName] Vserver [$VserverName]"  
                    } 
                    else 
                    {
                        $CheckVserver=Get-NcVserver -Controller $myController -Name $VserverName
                        if ( $CheckVserver -eq $null ) 
                        {
                            Write-LogError "ERROR: [$ClusterName] [$myVserver] no such vserver" 
                            $Return = $false
                        } 
                        else 
                        {
                            Get-Content $VOL_DB_FILE | Select-Object -uniq | foreach {
                                $VolName=$_.split(':')[0]
                                $VolSnapshotPolicy=$_.split(':')[1]
                                $VolSisPolicy=$_.split(':')[2]
                                $VolSisSchedule=$_.split(':')[3]
                                $VolSisState=$_.split(':')[4]
                                Write-LogDebug "Volume Options [$VolName] SnapshotPolicy [$VolSnapshotPolicy] SisPolicy [$VolSisPolicy] SisSchedule [$VolSisSchedule]"
                                if($VolSisPolicy.length -eq 0 -and $VolSisSchedule.length -eq 0){
                                    Write-LogDebug "Ignore volume [$VolName]"
                                    continue
                                }
                                $myVol = Get-NcVol -Controller $myController -Vserver $myVserver -Volume $VolName  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVol failed [$ErrorVar]" }
                                if ( $myVol -ne $null ) 
                                {
                                    $myVolSnapshotPolicy=$myVol.VolumeSnapshotAttributes.SnapshotPolicy
                                    Write-LogDebug "Current SnapshotPolicy for [$VolName] is [$myVolSnapshotPolicy], need this one [$VolSnapshotPolicy]"
                                    if ( ($VolSnapshotPolicy -ne $myVolSnapshotPolicy) -and $Global:ForceUpdateSnapPolicy.IsPresent) 
                                    {
                                        $attributes = Get-NcVol -Template -Controller $myController
                                        $mySnapshotAttributes= New-Object "DataONTAP.C.Types.Volume.VolumeSnapshotAttributes"
                                        $mySnapshotAttributes.SnapshotPolicy= $VolSnapshotPolicy
                                        $attributes.VolumeSnapshotAttributes=$mySnapshotAttributes
                                        $tmpStr=$attributes.VolumeSnapshotAttributes.SnapshotPolicy
                                        Write-LogDebug "attributes[$tmpStr]"
                                        $query=Get-NcVol -Template -Controller $myController
                                        $query.name=$VolName
                                        $query.vserver=$myVserver
                                        $query.NcController=$myController
                                        Write-LogDebug "Update-NcVol -Controller $myController -Query `$query -Attributes `$attributes"
                                        Write-Log "[$myVserver] Update Snapshot Policy [$VolSnapshotPolicy] on volume [$VolName]"
                                        $out=Update-NcVol -Controller $myController -Query $query -Attributes $attributes  -ErrorVariable ErrorVar 
                                        if ( $? -ne $True ) { $Return = $False ; Write-LogError "ERROR: Update-NcVol Failed: Failed to update volume  $VolName [$ErrorVar]" }
                                        $message=$out.FailureList.ErrorMessage
                                        if ( $out.FailureCount -ne 0 ) { $Return = $False ; Write-LogError "ERROR: Update-NcVol Failed: Failed to update volume [$VolName] [$message]" }
                                    }
                                    if ($VolSisState -eq "enabled"){
                                        Write-LogDebug "Enable-NcSis -Name $VolName -VserverContext $myVserver -controller $myController"
                                        Write-Log "[$myVserver] Enable Efficiency on volume [$VolName]"
                                        $ret=Enable-NcSis -Name $VolName -VserverContext $myVserver -controller $myController -ErrorVariable ErrorVar 
                                        if ( $? -ne $True ) { $Return = $False ; write-logdebug "ERROR: Enable-NcSis Failed to update volume  $VolName [$ErrorVar]" } 
                                    }
                                    if ($VolSisState -eq "disabled"){
                                        Write-LogDebug "Disable-NcSis -Name $VolName -VserverContext $myVserver -controller $myController"
                                        Write-Log "[$myVserver] Disable Efficiency on volume [$VolName]"
                                        $ret=Disable-NcSis -Name $VolName -VserverContext $myVserver -controller $myController -ErrorVariable ErrorVar
                                        if ( $? -ne $True ) { $Return = $False ; write-logdebug "ERROR: Disable-NcSis Failed to update volume  $VolName [$ErrorVar]" }
                                    }
                                    if ( $VolSisSchedule -eq "-" -and $VolSisPolicy.length -gt 0 )
                                    {
                                        Write-LogDebug "Get-NcSis -Name $VolName -Vserver $myVserver -Controller $myController  -ErrorVariable ErrorVar"
                                        $SisInfo=Get-NcSis -Name $VolName -Vserver $myVserver -Controller $myController  -ErrorVariable ErrorVar
                                        if ( $? -ne $True ) { $Return = $False ; Write-LogError "ERROR: Get-NcSis Failed for volume  $VolName [$ErrorVar]"}
                                        if($SisInfo -eq $null){$myVolSisPolicy=""}else{
                                            $myVolSisPolicy=$SisInfo.Policy
                                        }
                                        if ($myVolSisPolicy -ne $VolSisPolicy)
                                        {
                                            Write-LogDebug "Current Efficiency Policy [$VolName] [$myVolSisPolicy] [$VolSisPolicy]"
                                            Write-LogDebug "Set-NcSis -name $VolName -VserverContext $myVserver -controller $myController -policy $VolSisPolicy  -ErrorVariable ErrorVar"
                                            Write-Log "[$myVserver] Set Efficiency Policy [$VolSisPolicy] on volume [$VolName]"
                                            $out=Set-NcSis -name $VolName -VserverContext $myVserver -controller $myController -policy $VolSisPolicy  -ErrorVariable ErrorVar
                                            if ( $? -ne $True ) { $Return = $False ; write-logdebug "ERROR: Set-NcSis Failed: Failed to update volume  $VolName [$ErrorVar]"}
                                        }   
                                    }
                                    if ($VolSisPolicy.length -eq 0 -and $VolSisSchedule -ne "-")
                                    {
                                        Write-LogDebug "Get-NcSis -Name $VolName -Vserver $myVserver -Controller $myController  -ErrorVariable ErrorVar"
                                        $SisInfo=Get-NcSis -Name $VolName -Vserver $myVserver -Controller $myController  -ErrorVariable ErrorVar
                                        if ( $? -ne $True ) { $Return = $False ; Write-LogError "ERROR: Get-NcSis Failed for volume  $VolName [$ErrorVar]"}
                                        if($SisInfo -eq $null){$myVolSisSchedule=""}else{
                                            $myVolSisSchedule=$SisInfo.Schedule
                                        }
                                        if($myVolSisSchedule -ne $VolSisSchedule)
                                        {
                                            Write-LogDebug "Current Efficiency Schedule [$VolName] [$myVolSisSchedule] [$VolSisSchedule]"
                                            Write-LogDebug "Set-NcSis -name $VolName -VserverContext $myVserver -controller $myController -schedule $VolSisSchedule  -ErrorVariable ErrorVar"
                                            Write-Log "[$myVserver] Set Efficiency Schedule [$VolSisSchedule] on volume [$VolName]"
                                            $out=Set-NcSis -name $VolName -VserverContext $myVserver -controller $myController -schedule $VolSisSchedule  -ErrorVariable ErrorVar
                                            if ( $? -ne $True ) { $Return = $False ; write-logdebug "ERROR: Set-NcSis Failed: Failed to update volume  $VolName [$ErrorVar]" }       
                                        }
                                    }
                                }
                            }   
                        }
                    }
                }
            }
        }
        Write-logDebug "set_vol_options_from_voldb: end"
        return $Return
    }
    Catch 
    {
        handle_error $_ $myVserver
    	return $Return
    }
}

#############################################################################################
Function save_shareacl_options_to_shareacldb (
	[NetApp.Ontapi.Filer.C.NcController] $myPrimaryController,
    [NetApp.Ontapi.Filer.C.NcController] $mySecondaryController,
    [string] $myPrimaryVserver,
	[string] $mySecondaryVserver,
    [string] $ShareName,
    [switch] $CreateEmpty) 
{
    Try 
    {
    	$Return = $True

    	Write-LogDebug "save_shareacl_options_to_shareacldb: start"
    	$NcCluster = Get-NcCluster -Controller $myPrimaryController
    	$SourceCluster = $NcCluster.ClusterName

    	Write-LogDebug "Get-NcSnapmirrorDestination -SourceVserver $myPrimaryVserver -VserverContext $myPrimaryVserver -Controller $myPrimaryController"
    	$relationlist=Get-NcSnapmirrorDestination -SourceVserver $myPrimaryVserver -VserverContext $myPrimaryVserver -Controller $myPrimaryController  -ErrorVariable ErrorVar | sort-object -unique SourceVserver,DestinationVserver,RelationShipType
    	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcSnapmirrorDestination failed [$ErrorVar]" }
        #$count_delete_SRC=0
        #$count_delete_DST=0
    	foreach ( $relation in $relationlist ){
    		$SourceVserver = $relation.SourceVserver
    		$DestinationVserver = $relation.DestinationVserver
    		$RelationshipType = $relation.RelationshipType
    		if ( ( $RelationshipType -eq "data_protection" -or $RelationshipType -eq "extended_data_protection" ) -and ( $SourceVserver -ne $DestinationVserver )  ) 
            {
    			$NcVserverPeer=Get-NcVserverPeer -Controller $myPrimaryController -Vserver $SourceVserver -PeerVserver $DestinationVserver  -ErrorVariable ErrorVar 
    			if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserverPeer failed [$ErrorVar]" } 
    			$DestinationCluster=$NcVserverPeer.PeerCluster
    			$SVMTOOL_DB_SRC_CLUSTER=$Global:SVMTOOL_DB + '\' + $SourceCluster + '.cluster'
    			$SVMTOOL_DB_SRC_VSERVER=$SVMTOOL_DB_SRC_CLUSTER + '\' +$SourceVserver + '.vserver'
    			$SVMTOOL_DB_DST_CLUSTER=$Global:SVMTOOL_DB + '\' + $DestinationCluster + '.cluster'
    			$SVMTOOL_DB_DST_VSERVER=$SVMTOOL_DB_DST_CLUSTER + '\' + $DestinationVserver + '.vserver'
    			$SHAREACL_DB_SRC_FILE=$SVMTOOL_DB_SRC_VSERVER + '\shareacl.options'
    			$SHAREACL_DB_DST_FILE=$SVMTOOL_DB_DST_VSERVER + '\shareacl.options'
                if($CreateEmpty -eq $True){
					Write-LogDebug "Create Empty Share ACL DB"
                    try{
						Write-LogDebug "New-Item -ItemType Directory -Path $SVMTOOL_DB_SRC_VSERVER -Force"
                        $out=New-Item -ItemType Directory -Path $SVMTOOL_DB_SRC_VSERVER -Force  -ErrorVariable ErrorVar
                    }catch{
                        Write-LogDebug "cannot create [$SVMTOOL_DB_SRC_VSERVER], reason [$ErrorVar]"    
                    }
                    try{
						Write-LogDebug "New-Item -ItemType Directory -Path $SVMTOOL_DB_DST_VSERVER -Force"
                        $out=New-Item -ItemType Directory -Path $SVMTOOL_DB_DST_VSERVER -Force  -ErrorVariable ErrorVar
                    }catch{
                        Write-LogDebug "cannot create [$SVMTOOL_DB_DST_VSERVER], reason [$ErrorVar]"    
                    }
                    foreach($ShareAclFilename in ($SHAREACL_DB_SRC_FILE,$SHAREACL_DB_DST_FILE)){
                        if( (Test-Path $ShareAclFilename) -eq $False){
							Write-LogDebug "New-Item $ShareAclFilename -ItemType file"
                            $out=New-Item $ShareAclFilename -ItemType "file"
                        }
                    }
                    Write-LogDebug "save_shareacl_options_to_shareacldb: end"
                    return $True   
                }
				if ( ( Test-Path $SVMTOOL_DB_SRC_CLUSTER -pathType container ) -eq $false ) {
                		$out=new-item -Path $SVMTOOL_DB_SRC_CLUSTER -ItemType directory
                		if ( ( Test-Path $SVMTOOL_DB_SRC_CLUSTER -pathType container ) -eq $false ) {
                        		Write-LogError "ERROR: Unable to create new item $SVMTOOL_DB_SRC_CLUSTER" 
                        		return $False
                		}
        		}

        		if ( ( Test-Path $SVMTOOL_DB_SRC_VSERVER -pathType container ) -eq $false ) {
                		$out=new-item -Path $SVMTOOL_DB_SRC_VSERVER -ItemType directory
                		if ( ( Test-Path $SVMTOOL_DB_SRC_VSERVER -pathType container ) -eq $false ) {
                        		Write-LogError "ERROR: Unable to create new item $SVMTOOL_DB_SRC_VSERVER" 
                        		return $False
                		}
        		}
				if ( ( Test-Path $SVMTOOL_DB_DST_CLUSTER -pathType container ) -eq $false ) {
                		$out=new-item -Path $SVMTOOL_DB_DST_CLUSTER -ItemType directory
                		if ( ( Test-Path $SVMTOOL_DB_DST_CLUSTER -pathType container ) -eq $false ) {
                        		Write-LogError "ERROR: Unable to create new item $SVMTOOL_DB_DST_CLUSTER" 
                        		return $False
                		}
        		}

        		if ( ( Test-Path $SVMTOOL_DB_DST_VSERVER -pathType container ) -eq $false ) {
                		$out=new-item -Path $SVMTOOL_DB_DST_VSERVER -ItemType directory
                		if ( ( Test-Path $SVMTOOL_DB_DST_VSERVER -pathType container ) -eq $false ) {
                        		Write-LogError "ERROR: Unable to create new item $SVMTOOL_DB_DST_VSERVER" 
                        		return $False
                		}
        		}
     			# Create/Update ShareAcl DB
                Write-LogDebug "save_shareacl_options_to_shareacldb: file [$SHAREACL_DB_SRC_FILE] looking for ShareAcl for ShareName [$ShareName]"
				Write-LogDebug "Get Live CIFS share ACL for share [$ShareName]"
                Write-LogDebug "Get-NcCifsShareACL -VserverContext $SourceVserver -controller $myPrimaryController -Share $ShareName  -ErrorVariable ErrorVar"
                $PrimaryAclList_LIVE = Get-NcCifsShareACL -VserverContext $SourceVserver -controller $myPrimaryController -Share $ShareName  -ErrorVariable ErrorVar 
			    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsShareACL failed [$ErrorVar]" }
                $ShareAclList_LIVE=New-Object System.Collections.ArrayList($null)
			    foreach ( $PrimaryAcl_LIVE in ( $PrimaryAclList_LIVE | Skip-Null ) ) {
                    $PrimaryUserOrGroup = $PrimaryAcl_LIVE.UserOrGroup
				    $PrimaryPermission = $PrimaryAcl_LIVE.Permission
                    $ShareAclData=$($ShareName+";"+$PrimaryUserOrGroup+";"+$PrimaryPermission)
                    #if( ($PrimaryUserOrGroup -ne "Everyone") -and ($PrimaryUserOrGroup -notmatch "BUILTIN") )
                    #{
					Write-LogDebug "Store LIVE CIFS acl [$ShareAclData] in array"
                    $out=$ShareAclList_LIVE.Add($ShareAclData)           
                    #}
                }
                foreach($ShareAclFilename in ($SHAREACL_DB_SRC_FILE,$SHAREACL_DB_DST_FILE)){
                    if((Test-Path $ShareAclFilename) -eq $True){
                        $temp=Get-Content $ShareAclFilename
                        $ShareAclList_TEMP=New-Object System.Collections.ArrayList($null)
                        if(($temp.count) -gt 1)
                        {
                            $out=$ShareAclList_TEMP.AddRange($temp)
                        }
                        elseif(($temp.count) -eq 1)
                        {
                            $out=$ShareAclList_TEMP.Add($temp)    
                        }
                        $Acl_to_remove=@()
                        foreach($Acl in $ShareAclList_TEMP){
							$ShareName_Found=$Acl.split(";")[0]
                            if(($Acl.split(";")[0]) -eq $ShareName)
                            {
								Write-LogDebug "found sharename [$ShareName_Found] in [$ShareAclFilename]"
								Write-LogDebug "so will remove it to replace with LIVE values"
                                $Acl_to_remove+=$Acl
                            }
                        }
                        foreach($Acl in $Acl_to_remove){
                            Write-LogDebug "Remove ShareAcl Data [$Acl] for share [$ShareName] from file [$ShareAclFilename]"
                            $out=$ShareAclList_TEMP.Remove($Acl)
                        }
                        Write-LogDebug "Update ShareAcl for ShareName [$ShareName] with Live data : $ShareAclList_LIVE"
                        $out=$ShareAclList_TEMP.AddRange($ShareAclList_LIVE)
                        $ShareAclList_TEMP | Out-File -FilePath $ShareAclFilename -Width 2000
                    }
                    else{
                        Write-LogDebug "Add ShareAcl for ShareName [$ShareName] with Live data : $ShareAclList_LIVE"
                        $ShareAclList_LIVE | Out-File -FilePath $ShareAclFilename -Width 2000        
                    }  
                }
				Write-LogDebug "ShareAcl for share [$ShareName] updated"
				Write-LogDebug "Break Loop"
				break
            }else{
				Write-LogDebug "Unknonw RelationShip Type = [$RelationshipType] or SourceVserver [$SourceVserver] = DestVserver [$DestinationVserver]"
			}
        }
    	Write-LogDebug "save_shareacl_options_to_shareacldb: end"
    	Return $Return
    }
    Catch 
    {
        handle_error $_ $myPrimaryVserver
    	return $Return
    }
}

#############################################################################################
Function set_shareacl_options_from_shareacldb (
	[NetApp.Ontapi.Filer.C.NcController]$myController,
	[string]$myVserver,
    [switch]$NoCheck ) 
{
    Try 
    {
    	$Return = $true
        Write-logDebug "set_shareacl_options_from_shareacldb: start"
    	#$VolumeListToRestartQuota= @()
        if($NoCheck -eq $False){
            if ( ( svmdr_db_check -myController $myController -myVserver $myVserver ) -eq $false ) 
            {
                Write-LogError "ERROR: Failed to access quotadb" 
                return $False
            }
        }

    	if ( $myVserver -eq $null ) {Write-LogDebug "Missing Vserver name";return $False}
    	
    	$NcCluster = Get-NcCluster -Controller $myController
    	$ClusterName = $NcCluster.ClusterName
    	Write-LogDebug "Set ShareAcl options for vserver [$myVserver] from SVMTOOL_DB [$Global:SVMTOOL_DB] for ClusterName [$ClusterName]"

    	$SVMTOOL_DB_CLUSTER=$Global:SVMTOOL_DB + '\' + $ClusterName  + '.cluster'

    	if ( ( Test-Path $SVMTOOL_DB_CLUSTER -pathType container ) -eq $false ) 
        {
    	 	Write-LogError "ERROR: Cluster [$ClusterName] found in SVMTOOL_DB [$Global:SVMTOOL_DB]" 
    		return $false
    	}

    	if ( ( Test-Path $SVMTOOL_DB_CLUSTER/$myVserver.vserver -pathType container ) -eq $false ) 
        {
      		Write-LogError "ERROR: Vserver [$ClusterName] [$myVserver] not found in SVMTOOL_DB [$Global:SVMTOOL_DB]"
    		return $false
    	}
    	Write-LogDebug "SVMTOOL_DB_CLUSTER [$SVMTOOL_DB_CLUSTER]"
    	$VserverListItem = Get-Item "${SVMTOOL_DB_CLUSTER}/${myVserver}.vserver"
    	if ( $VserverListItem -eq $null ) 
        {
    		Write-Warning "No Vserver File found in SVMTOOL_DB_CLUSTER [$SVMTOOL_DB_CLUSTER]"  
    	} 
        else 
        {
    		foreach ( $VserverItem in  ( $VserverListItem  | Skip-Null ) ) 
            {
    			$VserverItemName=$VserverItem.Name
    			$VserverName=$VserverItemName.Split('.')[0] 
    			$SHAREACL_DB_VSERVER=$SVMTOOL_DB_CLUSTER + '\' + $VserverItemName
    			$SHAREACL_DB_FILE=$SHAREACL_DB_VSERVER + '\shareacl.options'
      			Write-LogDebug "Read SHAREACL_DB_FILE for Cluster [$ClusterName] Vserver [$VserverName] : [$SHAREACL_DB_FILE]"
    			if ( ( Test-Path $SHAREACL_DB_FILE  )  -eq $false ) 
                {
    				Write-Log "[$myVserver] No ShareAcl files found for Cluster [$ClusterName]"
    			} 
                else 
                {
    				$CheckVserver=Get-NcVserver -Controller $myController -Name $VserverName
    				if ( $CheckVserver -eq $null ) 
                    {
    		  			Write-LogError "ERROR: [$ClusterName] [$myVserver] no such vserver" 
    					$Return = $false
    				} 
                    else 
                    {
    					$temp=Get-Content $SHAREACL_DB_FILE
                        if($temp.count -eq 0){Write-LogDebug "Empty Share ACL DB. No Share ACL to manage";Write-logDebug "set_shareacl_options_from_shareacldb: end";return $True}
                        Write-LogDebug "Share ACL DB [$temp]"
                        $ShareAclList_DB=New-Object System.Collections.ArrayList($null)
                        if(($temp.count) -gt 1)
                        {
                            $out=$ShareAclList_DB.AddRange($temp)
                        }
                        else
                        {
                            $out=$ShareAclList_DB.Add($temp)    
                        }
                        $ShareList=$ShareAclList_DB | foreach{$_.split(";")[0]} | sort -Unique
                        Write-LogDebug "ShareList [$ShareList]"
                        foreach($Share in $ShareList){
                            $AclList_from_File=$ShareAclList_DB | sls $($Share.Replace("$","\$")+";")
                            Write-LogDebug "AclList_from_File [$AclList_from_File]"
                            Write-LogDebug "Get-NcCifsShareACL -VserverContext $myVserver -controller $myController -Share $Share  -ErrorVariable ErrorVar"
        					$ShareAclList_LIVE = Get-NcCifsShareACL -VserverContext $myVserver -controller $myController -Share $Share  -ErrorVariable ErrorVar 
			                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsShareACL failed [$ErrorVar]" }
        					if ( $ShareAclList_LIVE -ne $null ) 
                            {
                                foreach ( $ShareAcl_LIVE in $ShareAclList_LIVE ) {
                                    $UserOrGroup=$ShareAcl_LIVE.UserOrGroup
                                    $Permission=$ShareAcl_LIVE.Permission
                                    #if( ($UserOrGroup -ne "Everyone") -and ($UserOrGroup -ne "BUILTIN\Administrators") )
                                    #{
			                            Write-LogDebug "Remove-NcCifsShareAcl -Share $Share -UserOrGroup $UserOrGroup -VserverContext $myVserver -Controller $myController -Confirm:$false"
				                        $out=Remove-NcCifsShareAcl -Share $Share -UserOrGroup $UserOrGroup -VserverContext $myVserver -Controller $myController  -ErrorVariable ErrorVar -Confirm:$false
				                        if ( $? -ne $True ) {
					                        Write-LogError "ERROR: Failed to remove ACL: [$PrimaryShareName] [$UserOrGroup]" 
					                        $Return = $false
				                        }
                                        
                                    #}   
		                        }
                            }
                            foreach ( $Acl_from_File in $AclList_from_File){
                                $UserOrGroup=$Acl_from_File.ToString().split(";")[1]
                                $Permission=$Acl_from_File.ToString().split(";")[2]
                                Write-Log "Add CIFS ACL [$Share] [$UserOrGroup] [$Permission]"
				                Write-LogDebug "Add-NcCifsShareAcl -Share $Share  -UserOrGroup $UserOrGroup -Permission $Permission -VserverContext $myVserver -Controller $myController"
				                $out=Add-NcCifsShareAcl -Share $Share -UserOrGroup $UserOrGroup  -Permission  $Permission -VserverContext $myVserver -Controller $myController  -ErrorVariable ErrorVar
				                if ( $? -ne $True ) { $Return = $False ; Write-LogError "ERROR: Add-NcCifsShareAcl failed [$ErrorVar]" }    
                            }
    				    }   
    			    }
    		    }
      	    }
        }
        Write-logDebug "set_shareacl_options_from_shareacldb: end"
        return $Return
    }
    Catch 
    {
        handle_error $_ $myVserver
    	return $Return
    }
}

#############################################################################################
Function restore_quota (
	[NetApp.Ontapi.Filer.C.NcController] $myController,
	[string] $myVserver, 
	[string] $myPolicy="default")
{
    Try 
    {
        $Return=$True
        Write-LogDebug "restore_quota: start"
        $VolumeListToRestartQuota= @()
        if(Test-Path $($Global:JsonPath+"Get-NcVol.json")){
            $VolumeList=Get-Content $($Global:JsonPath+"Get-NcVol.json") | ConvertFrom-Json
        }else{
            $filepath=$($Global:JsonPath+"Get-NcVol.json")
            Write-LogDebug "ERROR: failed to read $filepath"
            return $False
        }
        if(Test-Path $($Global:JsonPath+"Get-NcQuotaPolicy.json")){
            $QuotaPolicyList=Get-Content $($Global:JsonPath+"Get-NcQuotaPolicy.json") | ConvertFrom-Json
        }else{
            $filepath=$($Global:JsonPath+"Get-NcQuotaPolicy.json")
            Write-LogDebug "ERROR: failed to read $filepath"
            return $False
        }
        if(Test-Path $($Global:JsonPath+"Get-NcQuota.json")){
            $QuotaRulesList=Get-Content $($Global:JsonPath+"Get-NcQuota.json") | ConvertFrom-Json
        }else{
            $filepath=$($Global:JsonPath+"Get-NcQuota.json")
            Write-LogDebug "ERROR: failed to read $filepath"
            return $False
        }
        if(Test-Path $($Global:JsonPath+"Get-NcVserver.json")){
            $SourceVserver=Get-Content $($Global:JsonPath+"Get-NcVserver.json") | ConvertFrom-Json
        }else{
            $filepath=$($Global:JsonPath+"Get-NcVserver.json")
            Write-LogDebug "ERROR: failed to read $filepath"
            return $False
        }
        $DestVserver=Get-NcVserver -Controller $myController -Name $myVserver -ErrorVariable ErrorVar
        if ( $? -ne $True ) { Write-LogDebug "ERROR: Get-NcVserver failed [$ErrorVar]" ; return $False}
        if ( $DestVserver -eq $null ) 
        {
            Write-LogError "ERROR: [$ClusterName] [$myVserver] no such vserver" 
            return $False
        }
        $QuotaPolicyDest=$DestVserver.QuotaPolicy
        $QuotaPolicySource=$SourceVserver.QuotaPolicy
        Write-LogDebug "Dest Vserver [$myVserver] use Quota Policy [$QuotaPolicyDest]"
        if($QuotaPolicyDest -ne $QuotaPolicySource){
            Write-Log "[$myVserver] Modify Quota Policy from [$QuotaPolicyDest] to [$QuotaPolicySource]"
            Write-LogDebug "Get-NcQuotaPolicy -VserverContext $myVserver -PolicyName $QuotaPolicySource -controller $myController"
            $checkQuotaPolicy=Get-NcQuotaPolicy -VserverContext $myVserver -PolicyName $QuotaPolicySource -controller $myController -ErrorVariable ErrorVar
            if($? -ne $True){ return $False; throw "ERROR: Get-NcQuotaPolicy failed [$ErrorVar]"}
            #$checkQuotaPolicy=$QuotaPolicyList | Where-Object {$_.PolicyName -eq $QuotaPolicySource}
            if ($checkQuotaPolicy -eq $null){
                Write-Log "[$myVserver] Create Quota Policy [$QuotaPolicySource] on Vserver"
                Write-LogDebug "New-NcQuotaPolicy -PolicyName $QuotaPolicySource -Vserver $myVserver -Controller $myController"
                $ret=New-NcQuotaPolicy -PolicyName $QuotaPolicySource -Vserver $myVserver -Controller $myController -ErrorVariable ErrorVar
                if ( $? -ne $True ) { Write-LogDebug "ERROR: New-NcQuotaPolicy failed [$ErrorVar]" ; $Return = $False }
            }
            Write-LogDebug "Set-NcVserver -Name $myVserver -QuotaPolicy $QuotaPolicySource -Controller $myController"
            $ret=Set-NcVserver -Name $myVserver -QuotaPolicy $QuotaPolicySource -Controller $myController -ErrorVariable ErrorVar
            if ( $? -ne $True ) { Write-LogDebug "ERROR: Set-NcVserver failed [$ErrorVar]" ; $Return = $False }  
        }
        foreach($quota in $QuotaRulesList){
            $ClusterName=$myController.Name
            $Vserver=$myVserver
            $Volume=$quota.Volume
            $Qtree=$quota.Qtree
            $myPolicy=$quota.Policy
            $QuotaType=$quota.QuotaType
            $QuotaTarget=$quota.QuotaTarget
            $DiskLimit=$quota.DiskLimit
            $FileLimit=$quota.FileLimit
            $SoftDiskLimit=$quota.SoftDiskLimit
            $SoftFileLimit=$quota.SoftFileLimit
            $Threshold=$quota.Threshold
            Write-LogDebug "create_quota_rules_from_quotadb: ${ClusterName}:${Vserver}:${Volume}:${Qtree}:${QuotaType}:${QuotaTarget}:${DiskLimit}:${FileLimit}:${SoftDiskLimit}:${SoftFileLimit}:${Threshold}:${myPolicy}"
            Write-LogDebug "create_quota_rules_from_quotadb: volume informations [${ClusterName}] [${Vserver}] [${Volume}]"
            $VOL=$VolumeList | where-Object {$_.Name -eq $Volume}
            if ( $VOL.VolumeMirrorAttributes.IsDataProtectionMirror -eq $True ) 
            {
                Write-LogError "ERROR: unable to set quota on volume [$Vserver] [$Volume] is DataProtectionMirror" 
                $Return = $false
            } 
            else 
            { 
                $NcQuotaParamList=@{}
                $Opts = ""  
                if ( $DiskLimit -ne '-' ) 
                {
                    $size = $DiskLimit + 'k'
                    $Opts = $Opts + '-DiskLimit ' + $size + ' '
                    $NcQuotaParam = @{DiskLimit=$size}
                    $NcQuotaParamList=$NcQuotaParamList + $NcQuotaParam
                }
                if ( $SoftDiskLimit -ne '-' ) 
                {
                    $size = $SoftDiskLimit + 'k'
                    $Opts = $Opts + '-SoftDiskLimit ' + $size + ' '
                    $NcQuotaParam = @{SoftDiskLimit=$size}
                    $NcQuotaParamList=$NcQuotaParamList + $NcQuotaParam
                }
                if ( $FileLimit -ne '-' ) 
                {
                    $Opts = $Opts + '-FileLimit ' + $FileLimit + ' '
                    $NcQuotaParam = @{FileLimit=$FileLimit}
                    $NcQuotaParamList=$NcQuotaParamList + $NcQuotaParam
                }
                if ( $SoftFileLimit -ne '-' ) 
                {
                    $Opts = $Opts + '-SoftFileLimit ' + $SoftFileLimit + ' '
                    $NcQuotaParam = @{SoftFileLimit=$SoftFileLimit}
                    $NcQuotaParamList=$NcQuotaParamList + $NcQuotaParam
                }
                if ( $Threshold -ne '-' ) 
                {
                    $size = $Threshold + 'k'
                    $Opts = $Opts + '-Threshold ' + $size + ' '
                    $NcQuotaParam = @{Threshold=$size}
                    $NcQuotaParamList=$NcQuotaParamList + $NcQuotaParam
                }
                switch ($QuotaType) 
                {
                    'tree' 
                    {
                        #if ( $QuotaTarget -eq '*' ) { $QuotaTarget='/vol/' + $Volume }
                        $Query=Get-NcQuota -Template -Controller $myController
                        $Query.QuotaTarget = $QuotaTarget
                        $Query.Volume = $Volume
                        $Query.Vserver = $Vserver
                        $Query.QuotaType= 'tree'  
                        $Query.Policy=$myPolicy
                        $QuotaList=Get-NcQuota -Controller $myController -Query $Query
                        foreach ( $Quota in ( $QuotaList | Skip-Null ) ) {
                            if ( ( $Query.QuotaTarget -eq $Quota.QuotaTarget ) ) 
                            {
                                if ( $QuotaTarget -eq '*' ) { $QuotaTarget='/vol/' + $Volume }
                                Write-LogDebug "Remove-NcQuota -Controller $myController -Vserver $Vserver -Path $QuotaTarget -Policy $myPolicy"
                                try{
                                    $Output=Remove-NcQuota -Controller $myController -Vserver $Vserver -Path $QuotaTarget -Policy $myPolicy  -ErrorVariable ErrorVar
                                    if ( $? -ne $True ) { $Return = $False ; write-logDebug "ERROR: Remove-NcQuota failed [$ErrorVar]" } 
                                }catch{
                                    $ErrorMessage = $object.Exception.Message
                                    Write-LogDebug "Remove-NcQuota Failed reason [$ErrorMessage]"
                                }
                            }
                        }
                        if ( $QuotaTarget -eq '*' ) { $QuotaTarget='/vol/' + $Volume }
                        try{
                            Write-LogDebug "Add-NcQuota -Controller $myController -Vserver $Vserver -Path $QuotaTarget $Opts -Policy $myPolicy"
                            $Output=Add-NcQuota -Controller $myController -Vserver $Vserver -Path $QuotaTarget @NcQuotaParamList -Policy $myPolicy  -ErrorVariable ErrorVar
                            if ( $? -ne $True -and $ErrorVar -ne "duplicate entry" ) { Write-LogDebug "Add-NcQuota failed on a duplicate entry [$ErrorVar]"; $Return = $False }
                            $VolumeListToRestartQuota+=$Vserver + ':' + $Volume
                        }catch{
                            $ErrorMessage = $_.Exception.Message
                            Write-Warning "Failed to create quota tree rule [$Opts] on target [$QuotaTarget] because [$ErrorMessage]"
                            Write-LogDebug "Failed to create quota tree rule [$Opts] on target [$QuotaTarget] because [$ErrorMessage]"  
                        }
                    }
                    'user' 
                    {
                        $Query=Get-NcQuota -Template -Controller $myController
                        $Query.QuotaTarget = $QuotaTarget
                        $Query.Volume = $Volume
                        $Query.Vserver = $Vserver
                        if ( $Qtree -ne "" ) { $Query.Qtree = $Qtree }
                        $Query.QuotaType= 'user'
                        $Query.Policy=$myPolicy
                        $QuotaList=Get-NcQuota -Controller $myController -Query $Query  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcQuota failed [$ErrorVar]" }
                        foreach ( $Quota in ( $QuotaList | Skip-Null ) ) {
                            if ( ( $Query.QuotaTarget -eq $Quota.QuotaTarget ) -and ( $Query.Qtree -eq $Quota.Qtree ) ) 
                            {
                                Write-LogDebug "Remove-NcQuota -User $QuotaTarget -Volume $Volume -Controller $myController -Vserver $Vserver -Qtree $Qtree -Policy $myPolicy"
                                try{
                                    $Output=Remove-NcQuota -User $QuotaTarget -Volume $Volume -Controller $myController -Vserver $Vserver -Qtree $Qtree -Policy $myPolicy  -ErrorVariable ErrorVar 
                                    if ( $? -ne $True ) { $Return = $False ; write-logDebug "ERROR: Remove-NcQuota failed [$ErrorVar]" }
                                }catch{
                                    $ErrorMessage = $object.Exception.Message
                                    Write-LogDebug "Remove-NcQuota Failed reason [$ErrorMessage]"    
                                }
                            }
                        }
                        try{
                            Write-LogDebug "Add-NcQuota -User $QuotaTarget -Volume $Volume -Controller $myController -Vserver $Vserver -Qtree $Qtree $Opts -Policy $myPolicy"
                            $Output=Add-NcQuota -User $QuotaTarget -Volume $Volume -Controller $myController -Vserver $Vserver -Qtree $Qtree @NcQuotaParamList -Policy $myPolicy  -ErrorVariable ErrorVar
                            if ( $? -ne $True -and $ErrorVar -ne "duplicate entry" ) {Write-LogDebug "Add-NcQuota failed on a duplicate entry [$ErrorVar]"; $Return = $False }
                            $VolumeListToRestartQuota+=$Vserver + ':' + $Volume
                        }catch{
                            $ErrorMessage = $_.Exception.Message
                            Write-Warning "Failed to create quota user rule [$Opts] on target [$Qtree] because [$ErrorMessage]"
                            Write-LogDebug "Failed to create quota user rule [$Opts] on target [$Qtree] because [$ErrorMessage]"
                        }
                    }
                    'group' 
                    {
                        $Query=Get-NcQuota -Template -Controller $myController
                        $Query.QuotaTarget = $QuotaTarget
                        $Query.Volume = $Volume
                        $Query.Qtree = $Qtree
                        $Query.Vserver = $Vserver
                        $Query.QuotaType= 'group'
                        $Query.Policy=$myPolicy
                        $QuotaList=Get-NcQuota -Controller $myController -Query $Query  -ErrorVariable ErrorVar
                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcQuota failed [$ErrorVar]" }
                        foreach ( $Quota in ( $QuotaList | Skip-Null ) ) {
                            if ( ( $Query.QuotaTarget -eq $Quota.QuotaTarget ) ) 
                            {
                                Write-LogDebug "Remove-NcQuota -Group $QuotaTarget -Volume $Volume -Controller $myController -Vserver $Vserver -Qtree $Qtree -Policy $myPolicy"
                                try{
                                    $Output=Remove-NcQuota -Group $QuotaTarget -Volume $Volume -Controller $myController -Vserver $Vserver -Qtree $Qtree -Policy $myPolicy  -ErrorVariable ErrorVar
                                    if ( $? -ne $True ) { $Return = $False ; Write-LogDebug "ERROR: Remove-NcQuota failed [$ErrorVar]" }
                                }catch{
                                    $ErrorMessage = $object.Exception.Message
                                    Write-LogDebug "Remove-NcQuota Failed reason [$ErrorMessage]"     
                                }
                            }
                        }
                        try{
                            Write-LogDebug "Add-NcQuota -Group $QuotaTarget -Volume $Volume -Controller $myController -Vserver $Vserver -Qtree $Qtree $Opts -Policy $myPolicy"
                            $Output=Add-NcQuota -Group $QuotaTarget -Volume $Volume -Controller $myController -Vserver $Vserver -Qtree $Qtree @NcQuotaParamList -Policy $myPolicy  -ErrorVariable ErrorVar
                            if ( $? -ne $True -and $ErrorVar -ne "duplicate entry" ) {Write-LogDebug "Add-NcQuota failed on a duplicate entry [$ErrorVar]"; $Return = $False }
                            $VolumeListToRestartQuota+=$Vserver + ':' + $Volume
                        }catch{
                            $ErrorMessage = $_.Exception.Message
                            Write-Warning "Failed to create quota group rule [$Opts] on target [$Qtree] because [$ErrorMessage]"
                            Write-LogDebug "Failed to create quota group rule [$Opts] on target [$Qtree] because [$ErrorMessage]"
                        }
                    }
                    default 
                    {
                        Write-LogError "ERROR: $QuotaType Unknown Type" 
                        $Return = $false
                    }
                }
            }
        }
        restart_quota_vol_from_list -myController $myController -myVserver $myVserver -myVolumeList $VolumeListToRestartQuota
        Write-LogDebug "restore_quota: end"
        return $Return
    }
    Catch 
    {
        handle_error $_ $myVserver
	    return $Return
    }
}

#############################################################################################
Function create_quota_rules_from_quotadb (
	[NetApp.Ontapi.Filer.C.NcController] $myController,
	[string] $myVserver, 
    [string] $myPolicy="default",
    [string] $CloneDR="",
    [switch] $NoCheck)
{
    Try 
    {
	    $Return = $true
        Write-LogDebug "create_quota_rules_from_quotadb: start"
	    $VolumeListToRestartQuota= @()
	    if($NoCheck -eq $False){
            if ( ( svmdr_db_check -myController $myController -myVserver $myVserver ) -eq $false ) 
            {
                Write-LogError "ERROR: Failed to access quotadb" 
                return $False
            }
        }
        if ( $myVserver -eq $null ) { $myVserver = "*" }
        if ( $myVolume -eq $null ) { $myVolume  = "*" }
        $NcCluster = Get-NcCluster -Controller $myController
        $ClusterName = $NcCluster.ClusterName
        Write-LogDebug "create_quota_rules_from_quotadb: ClusterName [$ClusterName]"
        if($CloneDR.legnth -gt 1){
            Write-Log "[$CloneDR] Create Quota policy rules from SVMTOOL_DB [$Global:SVMTOOL_DB]"
        }else{
            Write-Log "[$myVserver] Create Quota policy rules from SVMTOOL_DB [$Global:SVMTOOL_DB]"
        }
        $SVMTOOL_DB_CLUSTER=$Global:SVMTOOL_DB + '\' + $ClusterName  + '.cluster'
        if ( ( Test-Path $SVMTOOL_DB_CLUSTER -pathType container ) -eq $false ) 
        {
            Write-LogError "ERROR: Cluster [$ClusterName] found in SVMTOOL_DB [$Global:SVMTOOL_DB]" 
            return $false
        }
        if ( ( Test-Path $SVMTOOL_DB_CLUSTER/$myVserver.vserver -pathType container ) -eq $false ) 
        {
            Write-LogError "ERROR: Vserver [$ClusterName] [$myVserver] not found in SVMTOOL_DB [$Global:SVMTOOL_DB]"
            return $false
        }
        Write-LogDebug "create_quota_rules_from_quotadb: SVMTOOL_DB_CLUSTER [$SVMTOOL_DB_CLUSTER]"
        $VserverListItem = Get-Item "${SVMTOOL_DB_CLUSTER}/${myVserver}.vserver"
        if ( $VserverListItem -eq $null ) 
        {
            Write-Warning "Not Vserver File found in SVMTOOL_DB_CLUSTER [$SVMTOOL_DB_CLUSTER]"  
        } 
        else 
        {
            foreach ( $VserverItem in  ( $VserverListItem  | Skip-Null ) ) {
                $VserverItemName=$VserverItem.Name
                $VserverName=$VserverItemName.Split('.')[0] 
                $QUOTA_DB_VSERVER=$SVMTOOL_DB_CLUSTER + '\' + $VserverItemName
                $QUOTA_DB_FILE=$QUOTA_DB_VSERVER + '\quotarules.' + $myPolicy
                $available_QUOTA_DB_FILE=(Get-Item $($QUOTA_DB_VSERVER + '\quotarules*') | Sort-Object -Property LastWriteTime)[-1]
                if($available_QUOTA_DB_FILE -eq $null -or $available_QUOTA_DB_FILE.length -eq 0){
                    Write-Warning "No quota activated on any Vserver's volume" 
                    Write-LogDebug "WARNING: No quota activated on any Vserver's volume"
                    Write-LogDebug "create_quota_rules_from_quotadb: end"
                    return $True    
                }else{
                    $QUOTA_DB_FILE=$available_QUOTA_DB_FILE.FullName
                    $myPolicy=$available_QUOTA_DB_FILE.Name.split(".")[-1]
                }
                Write-LogDebug "create_quota_rules_from_quotadb: read QUOTA_DB_FILE for Cluster [$ClusterName] Vserver [$VserverName] Policy [$myPolicy] "
                if ( ( Test-Path $QUOTA_DB_FILE  )  -eq $false ) 
                {
                    Write-Warning "No quota activated on any Vserver's volume" 
                    Write-LogDebug "WARNING: No quota activated on any Vserver's volume" 
                } 
                else 
                {
                    if($CloneDR.length -gt 1){
                        $SVM=$CloneDR
                    }else{
                        $SVM=$myVserver
                    }
                    $CheckVserver=Get-NcVserver -Controller $myController -Name $SVM
                    if ( $CheckVserver -eq $null ) 
                    {
                        
                        Write-LogError "ERROR: [$ClusterName] [$SVM] no such vserver" 
                        $Return = $false
                    } 
                    else 
                    {
                        $actualQuotaPolicy=$CheckVserver.QuotaPolicy
                        Write-LogDebug "Vserver [$SVM] use Quota Policy [$actualQuotaPolicy]"
                        if($actualQuotaPolicy -ne $myPolicy){
                            Write-Log "[$SVM] Modify Quota Policy"
                            Write-LogDebug "Get-NcQuotaPolicy -VserverContext $SVM -PolicyName $myPolicy"
                            $checkQuotaPolicy=Get-NcQuotaPolicy -VserverContext $SVM -PolicyName $myPolicy -Controller $myController -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcQuotaPolicy failed [$ErrorVar]" }
                            if ($checkQuotaPolicy -eq $null){
                                Write-Log "[$SVM] Need to create Quota Policy [$myPolicy]"
                                Write-LogDebug "New-NcQuotaPolicy -PolicyName $myPolicy -Vserver $SVM -Controller $myController"
                                $ret=New-NcQuotaPolicy -PolicyName $myPolicy -Vserver $SVM -Controller $myController -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: New-NcQuotaPolicy failed [$ErrorVar]" }
                            }
                            Write-LogDebug "Set-NcVserver -Name $SVM -QuotaPolicy $myPolicy -Controller $myController"
                            $ret=Set-NcVserver -Name $SVM -QuotaPolicy $myPolicy -Controller $myController -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Set-NcVserver failed [$ErrorVar]" }  
                        }
                        Get-Content $QUOTA_DB_FILE | Select-Object -uniq | ForEach-Object {
                            Write-LogDebug "[$_]"
                            $ClusterName=$_.split(':')[0]
                            if($CloneDR.length -eq 0){
                                $SVM=$_.split(':')[1]
                            }
                            $Volume=$_.split(':')[2]
                            $Qtree=$_.split(':')[3]
                            $QuotaType=$_.split(':')[4]
                            $QuotaTarget=$_.split(':')[5]
                            $DiskLimit=$_.split(':')[6]
                            $FileLimit=$_.split(':')[7]
                            $SoftDiskLimit=$_.split(':')[8]
                            $SoftFileLimit=$_.split(':')[9]
                            $Threshold=$_.split(':')[10]
                            Write-LogDebug "create_quota_rules_from_quotadb: ${ClusterName}:${SVM}:${Volume}:${Qtree}:${QuotaType}:${QuotaTarget}:${DiskLimit}:${FileLimit}:${SoftDiskLimit}:${SoftFileLimit}:${Threshold}"
                            Write-LogDebug "create_quota_rules_from_quotadb: volume informations [${ClusterName}] [${SVM}] [${Volume}]"
                            $VOL=Get-NcVol -Controller $myController -Vserver $SVM -Name $Volume
                            if ( $VOL.VolumeMirrorAttributes.IsDataProtectionMirror -eq $True ) 
                            {
                                Write-LogError "ERROR: unable to set quota on volume [$SVM] [$Volume] because it's a DataProtectionMirror volume" 
                                $Return = $false
                            } 
                            else 
                            { 
                                $NcQuotaParamList=@{}
                                $Opts = ""  
                                if ( $DiskLimit -ne '-' ) 
                                {
                                    $size = $DiskLimit + 'k'
                                    $Opts = $Opts + '-DiskLimit ' + $size + ' '
                                    $NcQuotaParam = @{DiskLimit=$size}
                                    $NcQuotaParamList=$NcQuotaParamList + $NcQuotaParam
                                }
                                if ( $SoftDiskLimit -ne '-' ) 
                                {
                                    $size = $SoftDiskLimit + 'k'
                                    $Opts = $Opts + '-SoftDiskLimit ' + $size + ' '
                                    $NcQuotaParam = @{SoftDiskLimit=$size}
                                    $NcQuotaParamList=$NcQuotaParamList + $NcQuotaParam
                                }
                                if ( $FileLimit -ne '-' ) 
                                {
                                    $Opts = $Opts + '-FileLimit ' + $FileLimit + ' '
                                    $NcQuotaParam = @{FileLimit=$FileLimit}
                                    $NcQuotaParamList=$NcQuotaParamList + $NcQuotaParam
                                }
                                if ( $SoftFileLimit -ne '-' ) 
                                {
                                    $Opts = $Opts + '-SoftFileLimit ' + $SoftFileLimit + ' '
                                    $NcQuotaParam = @{SoftFileLimit=$SoftFileLimit}
                                    $NcQuotaParamList=$NcQuotaParamList + $NcQuotaParam
                                }
                                if ( $Threshold -ne '-' ) 
                                {
                                    $size = $Threshold + 'k'
                                    $Opts = $Opts + '-Threshold ' + $size + ' '
                                    $NcQuotaParam = @{Threshold=$size}
                                    $NcQuotaParamList=$NcQuotaParamList + $NcQuotaParam
                                }
                                switch ($QuotaType) 
                                {
                                    'tree' 
                                    {
                                        #if ( $QuotaTarget -eq '*' ) { $QuotaTarget='/vol/' + $Volume }
                                        $Query=Get-NcQuota -Template -Controller $myController
                                        $Query.QuotaTarget = $QuotaTarget
                                        $Query.Volume = $Volume
                                        $Query.Vserver = $SVM
                                        $Query.QuotaType= 'tree'  
                                        $Query.Policy=$myPolicy
                                        $QuotaList=Get-NcQuota -Controller $myController -Query $Query
                                        foreach ( $Quota in ( $QuotaList | Skip-Null ) ) {
                                            if ( ( $Query.QuotaTarget -eq $Quota.QuotaTarget ) ) 
                                            {
                                                if ( $QuotaTarget -eq '*' ) { $QuotaTarget='/vol/' + $Volume }
                                                Write-LogDebug "Remove-NcQuota -Controller $myController -Vserver $SVM -Path $QuotaTarget -Policy $myPolicy"
                                                $Output=Remove-NcQuota -Controller $myController -Vserver $SVM -Path $QuotaTarget -Policy $myPolicy  -ErrorVariable ErrorVar
                                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Remove-NcQuota failed [$ErrorVar]" } 
                                            }
                                        }
                                        if ( $QuotaTarget -eq '*' ) { $QuotaTarget='/vol/' + $Volume }
                                        try{
                                            Write-LogDebug "Add-NcQuota -Controller $myController -Vserver $SVM -Path $QuotaTarget $Opts -Policy $myPolicy"
                                            $Output=Add-NcQuota -Controller $myController -Vserver $SVM -Path $QuotaTarget @NcQuotaParamList -Policy $myPolicy  -ErrorVariable ErrorVar
                                            if ( $? -ne $True -and $ErrorVar -ne "duplicate entry" ) { Write-LogDebug "Add-NcQuota failed on a duplicate entry"; $Return = $False ; throw "ERROR: Add-NcQuota failed [$ErrorVar]" }
                                            $VolumeListToRestartQuota+=$SVM + ':' + $Volume
                                        }catch{
                                            $ErrorMessage = $_.Exception.Message
                                            Write-Warning "Failed to create quota tree rule [$opts] on target [$QuotaTarget] because [$ErrorMessage]"
                                            Write-LogDebug "Failed to create quota tree rule [$opts] on target [$QuotaTarget] because [$ErrorMessage]"  
                                        }
                                    }
                                    'user' 
                                    {
                                        $Query=Get-NcQuota -Template -Controller $myController
                                        $Query.QuotaTarget = $QuotaTarget
                                        $Query.Volume = $Volume
                                        $Query.Vserver = $SVM
                                        if ( $Qtree -ne "" ) { $Query.Qtree = $Qtree }
                                        $Query.QuotaType= 'user'
                                        $Query.Policy=$myPolicy
                                        $QuotaList=Get-NcQuota -Controller $myController -Query $Query  -ErrorVariable ErrorVar
                                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcQuota failed [$ErrorVar]" }
                                        foreach ( $Quota in ( $QuotaList | Skip-Null ) ) {
                                            if ( ( $Query.QuotaTarget -eq $Quota.QuotaTarget ) -and ( $Query.Qtree -eq $Quota.Qtree ) ) 
                                            {
                                                Write-LogDebug "Remove-NcQuota -User $QuotaTarget -Volume $Volume -Controller $myController -Vserver $SVM -Qtree $Qtree -Policy $myPolicy"
                                                $Output=Remove-NcQuota -User $QuotaTarget -Volume $Volume -Controller $myController -Vserver $SVM -Qtree $Qtree -Policy $myPolicy  -ErrorVariable ErrorVar 
                                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Remove-NcQuota failed [$ErrorVar]" }
                                            }
                                        }
                                        try{
                                            Write-LogDebug "Add-NcQuota -User $QuotaTarget -Volume $Volume -Controller $myController -Vserver $SVM -Qtree $Qtree $Opts -Policy $myPolicy"
                                            $Output=Add-NcQuota -User $QuotaTarget -Volume $Volume -Controller $myController -Vserver $SVM -Qtree $Qtree @NcQuotaParamList -Policy $myPolicy  -ErrorVariable ErrorVar
                                            if ( $? -ne $True -and $ErrorVar -ne "duplicate entry" ) {Write-LogDebug "Add-NcQuota failed on a duplicate entry"; $Return = $False ; throw "ERROR: Add-NcQuota failed [$ErrorVar]" }
                                            $VolumeListToRestartQuota+=$SVM + ':' + $Volume
                                        }catch{
                                            $ErrorMessage = $_.Exception.Message
                                            Write-Warning "Failed to create quota user rule [$opts] on target [$Qtree] because [$ErrorMessage]"
                                            Write-LogDebug "Failed to create quota user rule [$opts] on target [$Qtree] because [$ErrorMessage]"
                                        }
                                    }
                                    'group' 
                                    {
                                        $Query=Get-NcQuota -Template -Controller $myController
                                        $Query.QuotaTarget = $QuotaTarget
                                        $Query.Volume = $Volume
                                        $Query.Qtree = $Qtree
                                        $Query.Vserver = $SVM
                                        $Query.QuotaType= 'group'
                                        $Query.Policy=$myPolicy
                                        $QuotaList=Get-NcQuota -Controller $myController -Query $Query  -ErrorVariable ErrorVar
                                        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcQuota failed [$ErrorVar]" }
                                        foreach ( $Quota in ( $QuotaList | Skip-Null ) ) {
                                            if ( ( $Query.QuotaTarget -eq $Quota.QuotaTarget ) ) 
                                            {
                                                Write-LogDebug "Remove-NcQuota -Group $QuotaTarget -Volume $Volume -Controller $myController -Vserver $SVM -Qtree $Qtree -Policy $myPolicy"
                                                $Output=Remove-NcQuota -Group $QuotaTarget -Volume $Volume -Controller $myController -Vserver $SVM -Qtree $Qtree -Policy $myPolicy  -ErrorVariable ErrorVar
                                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Remove-NcQuota failed [$ErrorVar]" }
                                            }
                                        }
                                        try{
                                            Write-LogDebug "Add-NcQuota -Group $QuotaTarget -Volume $Volume -Controller $myController -Vserver $SVM -Qtree $Qtree $Opts -Policy $myPolicy"
                                            $Output=Add-NcQuota -Group $QuotaTarget -Volume $Volume -Controller $myController -Vserver $SVM -Qtree $Qtree @NcQuotaParamList -Policy $myPolicy  -ErrorVariable ErrorVar
                                            if ( $? -ne $True -and $ErrorVar -ne "duplicate entry" ) {Write-LogDebug "Add-NcQuota failed on a duplicate entry"; $Return = $False ; throw "ERROR: Add-NcQuota failed [$ErrorVar]" }
                                            $VolumeListToRestartQuota+=$SVM + ':' + $Volume
                                        }catch{
                                            $ErrorMessage = $_.Exception.Message
                                            Write-Warning "Failed to create quota group rule [$opts] on target [$Qtree] because [$ErrorMessage]"
                                            Write-LogDebug "Failed to create quota group rule [$opts] on target [$Qtree] because [$ErrorMessage]"
                                        }
                                    }
                                    default 
                                    {
                                        Write-LogError "ERROR: $QuotaType Unknown Type" 
                                        $Return = $false
                                    }
                                }
                            }
                        }
                    }
                }
            }
            # Restart Quota on Corrected volumes
            restart_quota_vol_from_list  -myController $myController -myVserver $SVM -myVolumeList $VolumeListToRestartQuota
        }
        Write-LogDebug "create_quota_rules_from_quotadb: end"
        return $Return
    }
    Catch 
    {
        handle_error $_ $myVserver
	    return $Return
    }
}

#############################################################################################
Function restart_quota_vol_from_list (
	[NetApp.Ontapi.Filer.C.NcController] $myController,
	[string]$myVserver, 
	[array]$myVolumeList ) {
Try {
    $Return = $True
    Write-logDebug "restart_quota_vol_from_list: start"
    # Restart Quota on Corrected volumes	
    if ( $myVolumeList -ne $null ) { 
        $myVolumeList | Select-Object -uniq | ForEach-Object {
            $Vserver=$_.split(':')[0]
            $Volume=$_.split(':')[1]
            $status=Get-NcQuotaStatus -Controller $myController -Vserver $myVserver -Volume $Volume
            if ( $status -eq $null ) {
                Write-LogError "ERROR: Unable to get quota status for volume [$Vserver] [$Volume]"
            } else {
                $VolQuotaStatus=$status.Status
                if ( $VolQuotaStatus -eq 'on' ) { 
                    Write-LogDebug "restart_quota_vol_from_list: Disable-NcQuota -Vserver $Vserver -Volume $Volume"
                    if ( $DebugLevel ) { Write-Host -NoNewLine "Disable quota on [$Vserver] Volume [$Volume]" }
                    $Output=Disable-NcQuota -Controller $myController -Vserver $myVserver -Volume $Volume  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Disable-NcQuota failed [$ErrorVar]" }
                }
                $isTimeOut = $false
                $StartTime=Get-date
                while ( ( $VolQuotaStatus -ne 'off' ) -and ( $isTimeOut -eq $false ) ) {
                    $status=Get-NcQuotaStatus -Controller $myController -Vserver $myVserver -Volume $Volume  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcQuotaStatus failed [$ErrorVar]" }
                    $VolQuotaStatus=$status.Status
                    $CurrentTime=Get-date
                    $TimeoutTime = ($CurrentTime - $StartTime).TotalSeconds
                    Write-LogDebug "restart_quota_vol_from_list: Quota Status [$Vserver] [$Volume]: [$VolQuotaStatus] [$TimeoutTime]" 
                    if ( $TimeOutTime -gt $Global:STOP_TIMEOUT ) {
                        $isTimeOut=$true
                        Write-LogError "WARNING: Stop quota volume [$Vserver] [$Volume] timeout"
                    }	
                    if ( $DebugLevel ) { Write-Host -NoNewLine '.' }
                    Start-Sleep 2 
                }
                if ( $DebugLevel ) { Write-Host '.' }
                if ( $DebugLevel ) { Write-Host -NoNewLine "[$Vserver] Enable quota on Volume [$Volume]" }
                Write-LogDebug "restart_quota_vol_from_list: Enable-NcQuota -Vserver $Vserver -Volume $Volume"
                Start-Sleep 5 
                $isTimeOut = $false
                $StartTime=Get-date
                $Output=Enable-NcQuota -Controller $myController -Vserver $myVserver -Volume $Volume  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Enable-NcQuota failed [$ErrorVar]" }
                $status=Get-NcQuotaStatus -Controller $myController -Vserver $Vserver -Volume $Volume  -ErrorVariable ErrorVar
                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcQuotaStatus failed [$ErrorVar]" }
                $VolQuotaStatus=$status.Status
                $StartTime=Get-date
                while ( ( $VolQuotaStatus -ne 'on') -and ( $isTimeOut -eq $false ) ) {
                    $status=Get-NcQuotaStatus -Controller $myController -Vserver $myVserver -Volume $Volume  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcQuotaStatus failed [$ErrorVar]" }
                    $VolQuotaStatus=$status.Status
                    $CurrentTime=Get-date
                    $TimeoutTime = ($CurrentTime - $StartTime).TotalSeconds
                    Write-LogDebug "restart_quota_vol_from_list: Quota Status [$Vserver] [$Volume]: [$VolQuotaStatus] [$TimeoutTime]" 
                    if ( $TimeOutTime -gt $Global:START_TIMEOUT ) {
                        $isTimeOut=$true
                        Write-LogError "WARNING: Start quota volume [$Vserver] [$Volume] timeout"
                    }
                    if ( $DebugLevel ) { Write-Host -NoNewLine '.' }
                    Start-Sleep 2 
                }
                if ( $DebugLevel ) { Write-Host '.' }
            }
        }
    }
    Write-logDebug "restart_quota_vol_from_list: end"
    return $Return
}
Catch {
    handle_error $_ $myVserver
	return $Return
}
}

#############################################################################################
Function check_quota_rules (
	[NetApp.Ontapi.Filer.C.NcController] $myController,
	[string]$myVserver, 
	[string]$myVolume) {
Try {
	$Return = $true
    Write-LogDebug "check_quota_rules: start"
	$VolumeListToRestartQuota= @()
	if ( $myVserver -eq $null ) { $myVserver = "*" }
	if ( $myVolume -eq $null ) { $myVolume  = "*" }
	$NcQuotaList=Get-NcQuota -Controller $myController -Vserver $myVserver -Volume $myVolume -ErrorVariable ErrorVar
	if ( $NcQuotaList -eq $null ) { 
		Write-LogDebug "check_quota_rules: No Quota found for volume [$myVserver] [$myVolume]" ;
		return $false
    }
    $VolQuotaStatus=Get-NcQuotaStatus -Controller $myController -Vserver $myVserver -Volume $myVolume -ErrorVariable ErrorVar
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcQuotaStatus failed [$ErrorVar]" }
	Write-LogDebug "check_quota_rules:[Vserver] [volume] [Qtree] [QuotaType] [QuotaTarget] [DiskLimit] [FileLimit] [SoftDiskLimit] [SoftFileLimit] [Threshold] [Policy]"
	foreach ( $quota in $NcQuotaList ) {
        $DiskLimit = $quota.DiskLimit
        $FileLimit = $quota.FileLimit
        $Threshold = $quota.Threshold
        $NcController = $quota.NcController
        $Policy = $quota.Policy
        $QuotaError = $quota.QuotaError
        $QuotaTarget = $quota.QuotaTarget
        $QuotaType = $quota.QuotaType
        $SoftDiskLimit = $quota.SoftDiskLimit
        $SoftFileLimit = $quota.SoftFileLimit
        $Volume = $quota.Volume
        $Qtree = $quota.Qtree
        $Vserver = $quota.Vserver
        Write-LogDebug "check_quota_rules:[$Vserver] [$volume] [$Qtree] [$QuotaType] [$QuotaTarget] [$DiskLimit] [$FileLimit] [$SoftDiskLimit] [$SoftFileLimit] [$Threshold] [$Policy]"
        if ( $VolQuotaStatus.Status -ne 'on' ) {
            if ( $Global:CorrectQuotaError -and ($Global:IgnoreQuotaOff -eq $False ) ) {
                $VolumeListToRestartQuota+=$Vserver + ':' + $Volume
            } else {
                Write-LogError "The Quota is disable on volume [${Vserver}:${volume}] quota [$QuotaTarget] [$QtreeName]"
                $Return = $false
            }
        }
        if ( $QuotaError ) {
            $Detail=$QuotaError.Detail
            $Errno=$QuotaError.Errno
            $Reason=$QuotaError.Reason
            if ( $QuotaType -eq "tree" ) {
                $QtreeName = $QuotaTarget | ForEach-Object { $_.Split('/')[3]; }
            } else  {
                $QtreeName = $Qtree
            }
            $isQtreeReasonError="Qtree " + $QtreeName + " does not exist"
            $Quota_Error_isQtree=$False
            if ($Reason -eq $isQtreeReasonError ) {
                $Quota_Error_isQtree=$True
            }	 
            Write-LogError "ERROR: [$Vserver] [$Volume] [$Errno] [$Detail] [$Reason]" 
            Write-LogDebug "check_quota_rules:[VolQuotaStatus [$Volume] [$VolQuotaStatus]"
            if ( $VolQuotaStatus -ne 'on' ) { 
                Write-LogError "The Quota is disable on volume [${Vserver}:${volume}]: Unable find method to Correct the Quota error [$QuotaTarget] [$QtreeName]"
                $Return = $false
            }
            if ( $Global:CorrectQuotaError -and ( $VolQuotaStatus -eq 'on' ) ) {
                $ReasonIsSecDUserNotFound = "Unable to find Windows account " + '"' + $QuotaTarget + '"' + ". Reason: SecD Error: entry not found."
                Write-LogDebug "check_quota_rules: ReasonIsSecDUserNotFound [$ReasonIsSecDUserNotFound]"
                Write-LogDebug "check_quota_rules: Reason                   [$Reason]"
                if ( ( $Errno -eq 13050 ) -and ( $Reason -eq $ReasonIsSecDUserNotFound ) ) {
                    $AllowDeleteQuotaInError = $True 
                    Write-LogDebug "check_quota_rules: AllowDeleteQuotaInError [$AllowDeleteQuotaInError]" 
                } else {
                    # Run Quota Report to correct the Quota 
                    # Build the Quota Query
                    $query=Get-NcQuotaReport -Template -Controller $myController
                    $query.NcController=$myController.name
                    $query.Vserver=$Vserver
                    $query.Volume=$Volume
                    $query.QuotaType="tree"
                    if ( $QuotaType -eq "tree" ) { 
                        $query.QuotaTarget=$QuotaTarget 
                    } else {
                        $query.QuotaTarget="/vol/" + $Volume + "/" + $Qtree
                    }
                    $QueryString=$query.NcController + "," + $query.NcController + "," + $query.Volume + "," + $query.QuotaType + "," + $query.QuotaTarget
                    Write-LogDebug "check_quota_rules: Run Get-NcQuotaReport with query [$QueryString] "
                    $NcQuotaReportList = Get-NcQuotaReport -Query $query -Controller $myController  -ErrorVariable ErrorVar
                    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcQuotaReport failed [$ErrorVar]" }
                    $QuotaReportStatus = $? 
                    if ( $QuotaReportStatus -ne $True ) {
                        Write-LogError "Get-NcQuotaReport Failed to get Report: Unable to Know" 
                        $Return = $False ;
                    }
                    if ( $NcQuotaReportList -eq $null ) {
                        Write-LogError "No Quota Report Found for Volume $Volume"
                        $Return = $False ;
                    } else {
                    foreach ( $NcQuotaReport in $NcQuotaReportList ) {
                        $NcQuotaReportVolume=$NcQuotaReport.Volume
                        $NcQuotaReportQtree=$NcQuotaReport.Qtree
                        $NcQuotaReportTarget=$NcQuotaReport.QuotaTarget
                        $NcQuotaReportSpecifier=$NcQuotaReport.QuotaTarget.split('/')[3]
                        Write-LogDebug "check_quota_rules:NcQuotaReportVolume   [$NcQuotaReportVolume]"
                        Write-LogDebug "check_quota_rules:NcQuotaReportQtree    [$NcQuotaReportQtree]"
                        Write-LogDebug "check_quota_rules:NcQuotaReportTarget   [$NcQuotaReportSpecifier]"
                        Write-LogDebug "check_quota_rules:NcQuotaReportSpecifier[$NcQuotaReportSpecifier]"
                        if ( ( $NcQuotaReportVolume -eq $Volume ) -and ( $NcQuotaReportSpecifier -eq  $QtreeName ) -and ( $Quota_Error_isQtree ) ) {
                            $QuotaErrorFound = $True
                            Write-host "Found Quota error: [$Vserver] [$NcQuotaReportVolume] [$NcQuotaReportQtree] [$NcQuotaReportTarget]"
                            $NcQuotaParamList=@{}
                            $Opts = ""  
                            if ( $DiskLimit -ne '-' ) {
                                $size = $DiskLimit + 'k'
                                $Opts = $Opts + '-DiskLimit ' + $size + ' '
                                $NcQuotaParam = @{DiskLimit=$size}
                                $NcQuotaParamList=$NcQuotaParamList + $NcQuotaParam
                            }
                            if ( $SoftDiskLimit -ne '-' ) {
                                $size = $SoftDiskLimit + 'k'
                                $Opts = $Opts + '-SoftDiskLimit ' + $size + ' '
                                $NcQuotaParam = @{SoftDiskLimit=$size}
                                $NcQuotaParamList=$NcQuotaParamList + $NcQuotaParam
                            }
                            if ( $FileLimit -ne '-' ) {
                                $Opts = $Opts + '-FileLimit ' + $FileLimit + ' '
                                $NcQuotaParam = @{FileLimit=$FileLimit}
                                $NcQuotaParamList=$NcQuotaParamList + $NcQuotaParam
                            }
                            if ( $SoftFileLimit -ne '-' ) {
                                $Opts = $Opts + '-SoftFileLimit ' + $SoftFileLimit + ' '
                                $NcQuotaParam = @{SoftFileLimit=$SoftFileLimit}
                                $NcQuotaParamList=$NcQuotaParamList + $NcQuotaParam
                            }
                            if ( $Threshold -ne '-' ) {
                                $size = $Threshold + 'k'
                                $Opts = $Opts + '-Threshold ' + $size + ' '
                                $NcQuotaParam = @{Threshold=$size}
                                $NcQuotaParamList=$NcQuotaParamList + $NcQuotaParam
                            }
        
                        switch ($QuotaType) {
                            'tree' {
                                Write-LogWarn "Correct Quota error tree: [$Vserver]: replace [$NcQuotaReportTarget] to [$NcQuotaReportQtree] "
                                $OldPath=$NcQuotaReportTarget
                                $NewPath='/vol/' + $Volume + '/' + $NcQuotaReportQtree
                                Write-LogDebug "check_quota_rules: Remove-NcQuota -Controller $myController -Vserver $Vserver -Path $OldPath -Policy $Policy"
                                Write-LogDebug "check_quota_rules: Add-NcQuota -Controller $myController -Vserver $Vserver -Path $NewPath $Opts -Policy $Policy"
                                $Output=Remove-NcQuota -Controller $myController -Vserver $Vserver -Path $OldPath -Policy $Policy
                                $Output=Add-NcQuota -Controller $myController -Vserver $Vserver -Path $NewPath @NcQuotaParamList -Policy $Policy
                                $VolumeListToRestartQuota+=$Vserver + ':' + $Volume
                                }
                            'user' {
                                Write-LogWarn "Correct Quota error user: [$Vserver]: replace [$NcQuotaReportSpecifier] to [$NcQuotaReportQtree] "
                                Write-LogDebug "check_quota_rules: Remove-NcQuota -User $QuotaTarget -Volume $Volume -Controller $myController -Vserver $Vserver -Qtree $NcQuotaReportSpecifier -Policy $Policy"
                                Write-LogDebug "check_quota_rules: Add-NcQuota -User $QuotaTarget -Volume $Volume -Controller $myController -Vserver $Vserver -Qtree $NcQuotaReportQtree $Opts -Policy $Policy"
                                $Output=Remove-NcQuota -User $QuotaTarget -Volume $Volume -Controller $myController -Vserver $Vserver -Qtree "$NcQuotaReportSpecifier" -Policy $Policy  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Remove-NcQuota failed [$ErrorVar]" }
                                $Output=Add-NcQuota -User $QuotaTarget -Volume $Volume -Controller $myController -Vserver $Vserver -Qtree $NcQuotaReportQtree @NcQuotaParamList -Policy $Policy  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Add-NcQuota failed [$ErrorVar]" }
                                $VolumeListToRestartQuota+=$Vserver + ':' + $Volume
                                }
                            'group' {
                                Write-Log "Correct quota error group: [$Vserver]: replace [$NcQuotaReportSpecifier] to [$NcQuotaReportQtree] "
                                Write-LogDebug "check_quota_rules: Remove-NcQuota -Group $QuotaTarget -Volume $Volume -Controller $myController -Vserver $Vserver -Qtree $NcQuotaReportSpecifier -Policy $Policy"
                                Write-LogDebug "check_quota_rules: Add-NcQuota -Group $QuotaTarget -Volume $Volume -Controller $myController -Vserver $Vserver -Qtree $NcQuotaReportQtree $Opts -Policy $Policy"
                                $Output=Remove-NcQuota -Group $QuotaTarget -Volume $Volume -Controller $myController -Vserver $Vserver -Qtree "$NcQuotaReportSpecifier" -Policy $Policy  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Remove-NcQuota failed [$ErrorVar]" }
                                $Output=Add-NcQuota -Group $QuotaTarget -Volume $Volume -Controller $myController -Vserver $Vserver -Qtree $NcQuotaReportQtree @NcQuotaParamList -Policy $Policy  -ErrorVariable ErrorVar
                                if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Add-NcQuota failed [$ErrorVar]" }
                                $VolumeListToRestartQuota+=$Vserver + ':' + $Volume
                                }
                            default {
                                Write-LogError "ERROR: $QuotaType Unknown Type" 
                                }
                            }
                        }
                    }
                    }
                }
                if ( $QuotaErrorFound -ne $True ) {
                    if ( ( $Global:ForceDeleteQuota -eq $True ) -and  ( ( $QuotaReportStatus -eq $True ) -or ( $AllowDeleteQuotaInError -eq $True ) )  ) {
                        #Force Delete Code
                        switch ($QuotaType) {
                        'tree' {
                            $OldPath='/vol/' + $Volume + '/' + $QtreeName
                            Write-LogWarn "Remove quota tree [$OldPath] from [$Vserver]"
                            Write-LogDebug "check_quota_rules: Remove-NcQuota -Controller $myController -Vserver $Vserver -Path $OldPath -Policy $Policy"
                            $Output=Remove-NcQuota -Controller $myController -Vserver $Vserver -Path $OldPath -Policy $Policy  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Remove-NcQuota failed [$ErrorVar]" }
                        }
                        'user' { 
                            Write-LogWarn "Remove quota user [$QuotaTarget] from [$Vserver] [$Volume] [$QtreeName]"
                            Write-LogDebug "check_quota_rules: Remove-NcQuota -User $QuotaTarget -Volume $Volume -Controller $myController -Vserver $Vserver -Qtree $QtreeName -Policy $Policy"
                            Remove-NcQuota -User $QuotaTarget -Volume $Volume -Controller $myController -Vserver $Vserver -Qtree "$QtreeName" -Policy $Policy  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Remove-NcQuota failed [$ErrorVar]" }
                        }
                        'group' {
                            Write-LogWarn "Remove quota group [$QuotaTarget] from [$Vserver] [$Volume] [$QtreeName]"
                            Write-LogDebug "check_quota_rules: Remove-NcQuota -Group $QuotaTarget -Volume $Volume -Controller $myController -Vserver $Vserver -Qtree $QtreeName -Policy $Policy"
                            Remove-NcQuota -Group $QuotaTarget -Volume $Volume -Controller $myController -Vserver $Vserver -Qtree "$QtreeName" -Policy $Policy  -ErrorVariable ErrorVar
                            if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Remove-NcQuota failed [$ErrorVar]" }
                        }
                        default {
                            Write-LogError "ERROR: $QuotaType Unknown Type" 
                            }
                        }
                    } else {
                        Write-LogError "ERROR: Quota report error not found [${Vserver}:${volume}]: Unable to Correct the Quota on [$QuotaTarget] [$QtreeName]"
                    }
                }
            }
        } 
   	}
	# Restart Quota on Corrected volumes	
	restart_quota_vol_from_list  -myController $myController -myVserver $myVserver -myVolumeList $VolumeListToRestartQuota 
    Write-LogDebug "check_quota_rules: end"
	return $Return 
}
Catch {
    handle_error $_ $myVserver
	return $Return
}
}