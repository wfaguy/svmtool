<#
.SYNOPSIS
    The svmdr script allow to manage DR relationship at SVM level
.DESCRIPTION
    This script create and manage Disaster Recovery SVM for ONTAP cluster
.PARAMETER Vserver
    Vserver Name of the source Vserver
.PARAMETER Instance
    Instance Name which will associate two cluster for a DR scenario
    An instance could manage one or several SVM DR relationship inside the corresponding cluster
.PARAMETER RootAggr
    Optional argument
    Allow to set a default aggregate for SVM root volume creation
    Used only with ConfigureDR option
.PARAMETER DataAggr
    Optional argument
    Allow to set a default aggregate for all SVM data volume creation
    Used only with ConfigureDR, UpdateDR, UpdateReverse arguments
.PARAMETER MirrorSchedule
    Optional argument
    Allow to set a SnapMirror automatic update schedule for Source to DR relationship 
.PARAMETER MirrorScheduleReverse
    Optional argument
    Allow to set a SnapMirror automatic update schedule for DR to Source relationship 
.PARAMETER ListInstance
	Display all Instance available and configured
.PARAMETER ImportInstance
	Import SVMDR script instances
.PARAMETER RemoveInstance
    Allow to remove a previously configured instance
    -RemoveInstance <instance name>
.PARAMETER Setup
    Used with Instance to create a new instance
    -Instance <instance name> -Setup
.PARAMETER Help
    Display help message
.PARAMETER ResetPassword
    Optional argument
    Allow to reset all password stored for all instances 
.PARAMETER HTTP
    Optional argument
    Allow to connect controller with HTTP instead of HTTPS
.PARAMETER ConfigureDR
    Allow to Create (or update) a SVM DR relationship
    -Instance <instance name> -Vserver <vserver source name> -ConfigureDR
.PARAMETER ShowDR
    Allow to display all informations for a particular SVM DR relationship
    -Instance <instance name> -Vserver <vserver source name> -ShowDR [-Lag] [-schedule]
    Optional parameters:
        Lag      : allow to display lag beetween last transfert
        Schedule : allow to display automatic schedule set on SnapMirror relationship
.PARAMETER DeleteDR
    Allow to delete a SVM DR relationship, by deleting all data and object associated to the DR SVM
    -Instance <instance name> -Vserver <vserver source name> -DeleteDR
.PARAMETER DeleteSource
    During Migrate procedure, you could choose not to delete source SVM
    In this case, souce SVM is only stopped
    Once everything has been test and validate on destination, you could safely delete the source SVM,
    by running DeleteSource step
.PARAMETER RemoveDRconf
    Delete configuration files for a particular SVM DR relationship
    -Instance <instance name> -Vserver <vserver source name> -RemoveDRconf
.PARAMETER UpdateDR
    Allow to update data and metadata for a particular SVM DR relationship
    -Instance <instance name> -Vserver <vserver source name> -UpdateDR
.PARAMETER Backup
    Backup Cluster/SVM configuration into JSON files
    Without specifying any Vserver, will backup all SVM availables
	-Backup <Cluster Name> [-Vserver <SVM name>] [-RecreateConf]
	-RecreateConf : Force recreate Backup configuration directory for selected Cluster
.PARAMETER Restore
	Restore Cluster/SVM configuration from JSON files
	Without specifying any Vserver, will list available SVM and propose to choose one to Restore
	-Restore <Cluster Name> [-Vserver <SVM name>] [-SelectBackupDate] [-Destination]
	-Vserver : Choose one SVM to restore. By Default restore all SVM available in Backup folder
	-SelectBackupDate : Ask script to display all dates availables and prompt user to choose a date to restore. 
						By default select last data available in backup folder
	-Destination : Destination Cluster where to restore selected SVM.
	               If not specified, script will ask for
.PARAMETER Migrate
    Allow to migrate a source SVM to destination SVM
    ConfigureDR and UpdateDR should have already being successfull
    Will cleanly delete source SVM and start dest SVM with source identity
    -Instance <instance name> -Vserver <vserver source name> -Migrate
.PARAMETER CreateQuotaDR
    Allow to recreate all quota rules on the DR SVM
	-Instance <instance name> -Vserver <vserver source name> -CreateQuotaDR
	PS: SnapMirror relationship must be broken
.PARAMETER ReCreateQuota
    Allow to recreate all quota rules on the source SVM
    -Instance <instance name> -Vserver <vserver source name> -ReCreateQuota
.PARAMETER CorrectQuotaError
    Optional argument
    Allow to Correct Source Quota Error before to save replicate the Quota rules configuration in SVMTOOL_DB
	Used with ConfigureDR, UpdateDR and UpdateReverse
.PARAMETER IgnoreQtreeExportPolicy
    Optional argument
    Allow to not check Qtree Export Policy during an UpdateDR
    This option greatly reduces cutover window.
    This can only be used during the last UpdateDR, when activity has been shutdown on source and before the ActivateDR.
    Obviously, a previous UpdateDR should be run without this argument in order to sync all Qtree Export Policy.
	This penultimate UpdateDR will be launched (normaly without this argument) right after freezing all creation/modification/deletion of qtree, 
	but by keeping an activity on source platform.
.PARAMETER IgnoreQuotaOff
    Optional argument
    Allow to ignore a volume for which quota are currently set to off
    Used with ConfigureDR, UpdateDR and UpdateReverse
.PARAMETER LastSnapshot
    Optional argument
    Allow to use the last snapshot available to update SnapMirror relationship
.PARAMETER UpdateReverse
    Allow to update data and metadata during a DR test or crash un reverse order, from DR to source
    -Instance <instance name> -Vserver <vserver source name> -UpdateReverse
.PARAMETER CleanReverse
    Remove all broken Reverse SnapMirror relationship (after DR test or crash)
    -Instance <instance name> -Vserver <vserver source name> -CleanReverse
.PARAMETER Resync
    Force a manual update of all data only for a particular DR relationship 
    -Instance <instance name> -Vserver <vserver source name> -Resync
.PARAMETER ActivateDR
    Allow to activate a DR SVM for test or after a real crash on the source
    -Instance <instance name> -Vserver <vserver source name> -ActivateDR [-ForceActivate]
.PARAMETER ForceActivate
    Mandatory argument in case of disaster in Source site
    Used only with ActivateDR when source site is unjoinable
.PARAMETER ForceDeleteQuota
    Optional argument
    Allow to forcibly delete a quota rules in error
    Used with ConfigureDR, UpdateDR and UpdateReverse
.PARAMETER ForceRecreate
    Optional argument used only in double DR scenario or during Source creation after disaster
    Allow to forcibly recreate a SnapMirror relationship
    Used with ReaActivate, Resync and ResyncReverse
.PARAMETER AlwaysChooseDataAggr
    Optional argument used to always ask to choose a Data Aggregate to store each Data volume
    Used with ConfigureDR only
.PARAMETER SelectVolume
    Optional argument used to choose for each source volume if it needs to be replicated on SVM DR or not
    Used with ConfigureDR only
.PARAMETER ResyncReverse
    Force a manual update of all data only for a particular DR relationship in reverse order, DR SVM to Source SVM 
    -Instance <instance name> -Vserver <vserver source name> -ResyncReverse
.PARAMETER ReActivate
    Allow to reactivate a source SVM following a test or real crash managed with an ActivateDR
    -Instance <instance name> -Vserver <vserver source name> -ReActivate
.PARAMETER Version
    Display version of the script
.PARAMETER DRfromDR
    Optional argument used only in double DR scenario
    Allow to create the second DR relationship for a particular instance and SVM
    Used only with ConfigureDR
.PARAMETER XDPPolicy
    Optional argument to specify a particular SnapMirror policy to use when creates XDP relationship
    By defaut, it use MirrorAllSnapshots policy
	The specified Policy must already exists in ONTAP and be correctly configured
.PARAMETER DebugLevel
	Increase verbosity level
.PARAMETER RW
	Only in Restore mode, this option will allow to create RW volume instead of default DP volume
	This cas be used when you want to restore/clone an SVM conf, but don't need to or can't restore data back through SnapMirror
.INPUTS
    None. You cannot pipe objects to this script
.OUTPUTS
    Only display result of operations
.LINK
    https://github.com/oliviermasson/svmtool
.EXAMPLE
    svmtool.ps1 -Instance test -Setup

    Create a new instance named test
.EXAMPLE
    svmtool.ps1 -Instance test -Vserver svm_source -ConfigureDR

    Configure a SVM DR relationship for SVM svm_source in the instance test
    And create all necessary DR objects
.EXAMPLE
    svmtool.ps1 -Instance test -Vserver svm_source -ConfigureDR -AlwaysChooseDataAggr -SelectVolume

    Configure a SVM DR relationship for SVM svm_source in the instance test
    Request user to select which volume will be replicated and which not
    Ask for each volume on which destination aggregate it will be provisionned
.EXAMPLE
   svmtool.ps1 -Instance test -Vserver svm_source -UpdateDR
   
   Set and Update all data and metadata for the DR SVM associated with source SVM svm_source
.EXAMPLE
    svmtool.ps1 -Instance test -Vserver svm_source -ActivateDR
    
    Activate the DR SVM associated with source SVM svm_source
    Access will be allowed on DR SVM
.EXAMPLE
    svmtool.ps1 -Instance test -Vserver svm_source -ResyncReverse
    
    Following an ActivateDR, create a reverse SnapMirror relationship from DR to source and erase data only on source SVM
.EXAMPLE
    svmtool.ps1 -Instance test -Vserver svm_source -UpdateReverse

    Following a ResyncReverse, push all metadata modifications achieved on DR SVM to source SVM
.EXAMPLE
    svmtool.ps1 -Instance test -Vserver svm_source -ReActivate

	Following an ActivateDR, restart production on source SVM
.EXAMPLE
	svmtool.ps1 -Backup clusterA [-Vserver <svm name>]

	Backup all SVM on clusterA.
	If Backup&Restore Instance associated to clusterA does not exist, the script will create it.
	All SVM will be backed up in separate folder inside the directory chosen for this instance
	If you want to recreate the instance for clusterA, add -Recreateconf
	If you want to only Backup a particular SVM, add -Vserver <svm name>
.EXAMPLE
	svmtool.ps1 -Restore clusterA [-Vserver <svm name>] -Destination clusterB [-RW] [-SelectBackupDate] 

	Restore all SVM available from the Backup folder defined in the clusterA Backup&Restore instance to clusterB
	If you need to restore a particular SVM, just -add -Vserver <svm name>
	By default, the script will automaticaly restore from the most recent backup folder available for each SVM
	If you want to restore from a particular date, just add -SelectBackupDate, and the script will display all dates available
	for each SVM and prompt you to chose the date you want
	By default, the script restore all volume as Data-Protection type (DP) volume. 
	In order to allow you to restore data inside this volumes from a SnapMirror/SnapVault previous backup.
	If you don't have a SnapMirror/SnapVault backup or will restore data back with another method,
	or because you only need to recreate the "envelop" fo the SVM (to clone an environment by example), just add -RW to the command line
	In that case, all volumes will be restored as Read/Write (RW) volume.
.NOTES
    Author  : Olivier Masson
    Version : August 25th, 2018
#>
[CmdletBinding(HelpURI="https://github.com/oliviermasson/svmtool")]
Param (
	#[int32]$Debug = 0,
    [string]$Vserver,
	[string]$Instance,
	[string]$RootAggr,
	[string]$DataAggr,
	[string]$MirrorSchedule,
    [string]$MirrorScheduleReverse,
	[switch]$ListInstance,
	[switch]$ImportInstance,
	[string]$RemoveInstance,
	[switch]$Setup,
	[switch]$Help,
	[switch]$ResetPassword,
	[switch]$HTTP,
    [switch]$ConfigureDR,
	[string]$Backup,
	[string]$Restore,
	[string]$Destination="",
	[switch]$ShowDR,
	[switch]$Lag,
	[switch]$Schedule,
	[switch]$DeleteDR,
	[switch]$RemoveDRConf,
	[switch]$UpdateDR,
    [switch]$DeleteSource,
    [switch]$Migrate,
	[switch]$CreateQuotaDR,
	[switch]$ReCreateQuota,
	[switch]$CorrectQuotaError,
	[switch]$IgnoreQtreeExportPolicy,
	[switch]$IgnoreQuotaOff,
	[switch]$LastSnapshot,
	[switch]$UpdateReverse,
	[switch]$CleanReverse,
	[switch]$Resync,
	[switch]$ActivateDR,
	[switch]$ForceActivate,
	[switch]$ForceDeleteQuota,
    [switch]$ForceRecreate,
	[switch]$ResyncReverse,
	[switch]$ReActivate,
	[switch]$Version,
	[switch]$NoLog,
    [switch]$Silence,
    [switch]$Recreateconf,
	[switch]$InternalTest,
    [switch]$AlwaysChooseDataAggr,
	[switch]$SelectVolume,
	[switch]$SelectBackupDate,
    [switch]$DRfromDR,
    [switch]$MSID,
    [string]$XDPPolicy="MirrorAllSnapshots",
	[switch]$DebugLevel,
	[switch]$RW,
	[Int32]$Timeout = 60
	#[Int32]$ErrorAction = 0
)

#############################################################################################
# Minimum Netapp Supported TK
#############################################################################################
$Global:MIN_MAJOR = 4
$Global:MIN_MINOR = 3
$Global:MIN_BUILD = 0
$Global:MIN_REVISION = 0
#############################################################################################
$Global:RELEASE="0.0.3"
$Global:BASEDIR='C:\Scripts\SVMTOOL'
$Global:CONFBASEDIR=$BASEDIR + '\etc\'
$Global:STOP_TIMEOUT=360
$Global:START_TIMEOUT=360
$Global:SINGLE_CLUSTER = $False
$Global:LOG_DAY2KEEP=30        # keep log file for maxium 30 days
$Global:LOG_MAXSIZE=104857600  # set log file maximum size to 100MB
$DebugPreference="SilentlyContinue"
$VerbosePreference="SilentlyContinue"
$ErrorActionPreference="SilentlyContinue"
$Global:BACKUPALLSVM=$False
$Global:NumberOfLogicalProcessor = (Get-WmiObject Win32_Processor).NumberOfLogicalProcessors
$Global:maxJobs=100
$Global:XDPPolicy=$XDPPolicy

if ( ( $Instance -eq $null ) -or ( $Instance -eq "" ) ) {
    if ($Backup.Length -eq 0 -and $Restore.Length -eq 0){
        $Global:CONFDIR=$Global:CONFBASEDIR + 'default\'
    }elseif($Backup.Length -gt 0){
        $Global:CONFDIR=$Global:CONFBASEDIR + $Backup + '\'
	}elseif($Restore.Length -gt 0){
        $Global:CONFDIR=$Global:CONFBASEDIR + $Restore + '\'
    }
} else  {
	$Global:CONFDIR=$Global:CONFBASEDIR + $Instance + '\'
}

$Global:CONFFILE=$Global:CONFDIR + 'svmtool.conf'

$Global:ROOTLOGDIR=($Global:BASEDIR + '\log\')

if($Backup -ne "") {
	$Global:ROOTLOGDIR=($Global:ROOTLOGDIR + $Backup + '\')
	if(Test-Path $Global:ROOTLOGDIR -eq $False){
        New-Item -Path $Global:ROOTLOGDIR -ItemType "directory" -ErrorAction "silentlycontinue" | Out-Null
    }		
}

if($Restore -ne "") {
	$Global:ROOTLOGDIR=($Global:ROOTLOGDIR + $Restore + '\')
	if(Test-Path $Global:ROOTLOGDIR -eq $False){
        New-Item -Path $Global:ROOTLOGDIR -ItemType "directory" -ErrorAction "silentlycontinue" | Out-Null
    }
}

if($Vserver -ne "" -and ($Backup -eq "" -and $Restore -eq "")) {
	$Global:LOGDIR=($Global:ROOTLOGDIR + $Vserver + '\')
} else {
	$Global:LOGDIR = $Global:ROOTLOGDIR
}

$Global:LOGFILE=$LOGDIR + "svmtool.log"
$Global:CRED_CONFDIR=$BASEDIR  + "\cred\"
$Global:MOUNT_RETRY_COUNT = 100

#############################################################################################
# MAIN
#############################################################################################
$scriptDir=($PSCmdlet.SessionState.Path.CurrentLocation).Path
$Path=$env:PSModulePath.split(";")
if($Path -notcontains $scriptDir){
    $Path+=$scriptDir
    $Path=[string]::Join(";",$Path)
    [System.Environment]::SetEnvironmentVariable('PSModulePath',$Path)
}
remove-module -Name svmtools -ErrorAction SilentlyContinue
$module=import-module svmtools -PassThru
if ( $module -eq $null ) {
        Write-Error "ERROR: Failed to load module SVMTOOLS"
        exit 1
}
if(!($env:PSModulePath -match "NetApp PowerShell Toolkit")){
    $env:PSModulePath=$($env:PSModulePath+";C:\Program Files (x86)\NetApp\NetApp PowerShell Toolkit\Modules")
}
$module=import-module -Name DataONTAP -PassThru
if ( $module -eq $null ) {
        Write-LogError "ERROR: DataONTAP module not found" 
        clean_and_exit 1
}

rotate_log
check_ToolkitVersion 

if ( ( check_init_setup_dir ) -eq $False ) {
        Write-LogError "ERROR: Failed to create new folder item: exit" 
        clean_and_exit 1
}
$Global:mutexconsole = New-Object System.Threading.Mutex($false, "Global\BackupMutex")
Write-LogOnly ""
Write-LogOnly "SVMTOOL START"
if ( $Help ) { Write-Help }
if ( $Version ) {
	$ModuleVersion=(Get-Module -Name svmtools).Version
	$ModuleVersion=$ModuleVersion.ToString()
	Write-Log "Script Version [$RELEASE]"
	Write-Log "Module Version [$ModuleVersion]"
	Clean_and_exit 0 
}
#set_debug_level $DebugLevel
Write-LogDebug "BASEDIR      [$BASEDIR]"
Write-LogDebug "CONFDIR      [$CONFDIR]"
Write-LogDebug "LOGDIR       [$LOGDIR]"
Write-LogDebug "LOGFILE      [$LOGFILE]"
Write-LogDebug "CRED_CONFDIR [$CRED_CONFDIR]"
Write-LogDebug "CONFFILE     [$CONFFILE]"
Write-LogDebug "VERSION      [$RELEASE]"
Write-LogDebug "Vserver      [$Vserver]"
Write-LogDebug "DebugLevel   [$DebugLevel]"
Write-LogDebug "RW           [$RW]"

if ( $ListInstance ) {
	show_instance_list
	clean_and_exit 0
}

if($ImportInstance){
	if(($ret=import_instance_svmdr) -eq $True){
		clean_and_exit 0
	}else{
		clean_and_exit 1	
	}
	
}

if ( $RemoveInstance ) {
	if ( ( remove_configuration_instance $RemoveInstance ) -eq $True ) {
		clean_and_exit 0
	} else {
		clean_and_exit 1
	}
}

if ( $Setup ) {
	create_config_file_cli
	if ( ! $Vserver ) {
		clean_and_exit 1
	}
}

if ( $Backup ) {
    $Run_Mode="Backup"
    Write-Log "SVMTOOL Run Backup"
    if ((Test-Path $CONFFILE) -eq $True ) {
		Write-Log "use Config File [$CONFFILE]"
		$read_conf = read_config_file $CONFFILE ;
		if ( $read_conf -eq $null ){
        		Write-LogError "ERROR: read configuration file $CONFFILE failed"
        		clean_and_exit 1 ;
        }
        $SVMTOOL_DB=$read_conf.Get_Item("SVMTOOL_DB")
        if($RecreateConf -eq $True){
            $ANS=Read-Host "Configuration file already exist. Do you want to recreate it ? [y/n]"
            if ( $ANS -ne 'y' ) { $RecreateConf=$False }
        }
    }
    if($RecreateConf -eq $True -or (Test-Path $CONFFILE) -eq $False){
		Write-Log "Create new Config File"
        $ANS='n'
        while ( $ANS -ne 'y' ) {
            $ReadInput = Read-Host "Please enter Backup directory where configuration will be backup [$SVMTOOL_DB]"
            if(!$ReadInput -and $SVMTOOL_DB.Length -gt 0){Write-LogDebug "Keep previous value [$SVMTOOL_DB]"}
            elseif (($ReadInput) -ne "" ) { $SVMTOOL_DB=$ReadInput }
            Write-Log "SVMTOOL Backup directory:  [$SVMTOOL_DB]"
            Write-Log ""
                $ANS = Read-Host "Apply new configuration ? [y/n/q]"
            if ( $ANS -eq 'q' ) { clean_and_exit 1 }
            write-Output "#" | Out-File -FilePath $CONFFILE  
			write-Output "SVMTOOL_DB=$SVMTOOL_DB\$Backup" | Out-File -FilePath $CONFFILE -Append 
			write-output "INSTANCE_MODE=BACKUP_RESTORE" | Out-File -FilePath $CONFFILE -Append
			write-output "BACKUP_CLUSTER=$Backup" | Out-File -FilePath $CONFFILE -Append  
        }
    }elseif($SVMTOOL_DB.Length -gt 0){
        Write-Log "Backup will be done inside [$SVMTOOL_DB]"
    }
    if($Vserver.length -eq 0){ 
        Write-LogDebug "No SVM selected. Will backup all SVM on Cluster [$Backup]"
        $BACKUPALLSVM=$True
    }else{
        Write-Log "Backup SVM [$Vserver] on Cluster [$Backup]"
    }

    $myCred=get_local_cDotcred ($Backup)
    $tmp_str=$MyCred.UserName
	Write-LogDebug "Connect to cluster [$Backup] with login [$tmp_str]"
	Write-LogDebug "connect_cluster -myController $Backup -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcPrimaryCtrl =  connect_cluster -myController $Backup -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$Backup]" 
		clean_and_exit 1
    }
    if($BACKUPALLSVM -eq $True){
        $AllSVM=Get-NcVserver -Query @{VserverType="data";VserverSubtype="!sync_destination,!dp_destination"} -Controller $NcPrimaryCtrl -ErrorVariable ErrorVar 
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" }
        if($AllSVM){
            $SVMList=$AllSVM.Vserver
        }else{
            Write-Log "ERROR: No active SVM available on Cluster [$Backup]"
            clean_and_exit 1
        }
    }else{
        $SVMList=@($Vserver)   
    }
	$iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $RunspacePool_Backup=[runspacefactory]::CreateRunspacePool(1, $NumberOfLogicalProcessor, $iss, $Host)
    $RunspacePool_Backup.Open()
    [System.Collections.ArrayList]$jobs = @()
    $SVMcount=($SVMList | Measure-Object -Sum).Count
	$Jobs_Backup = @()
	$stopwatch=[system.diagnostics.stopwatch]::StartNew()
	$numJobBackup=0
	$BackupDate=Get-Date -UFormat "%Y%m%d%H%M%S"
    foreach($svm in $SVMList){
		$svm_status=Get-NcVserver -Vserver $svm -Controller $NcPrimaryCtrl -ErrorVariable ErrorVar
		$svm_status=$svm_status.OperationalState
		if($svm_status -eq "stopped"){
			Write-LogWarn "[$svm] can't be saved because it is in `"stopped`" state"
			continue
		}
		Write-Log "Create Backup Job for [$svm]" "Blue"
        $codeBackup=[scriptblock]::Create({
            param(
                [Parameter(Mandatory=$True)]
                [string]
                $script_path,
                [Parameter(Mandatory=$True)]
                [NetApp.Ontapi.Filer.C.NcController]
                $myPrimaryController,
                [Parameter(Mandatory=$True)]
                [string]
                $myPrimaryVserver,
                [Parameter(Mandatory=$True)]
				[string]
				$SVMTOOL_DB,
                [Parameter(Mandatory=$True)]
                [System.Threading.WaitHandle]
				$mutexconsole,
                [Parameter(Mandatory=$True)]
                [String]
				$BackupDate,
				[Parameter(Mandatory=$True)]
				[String]
				$LOGFILE,
				[Parameter(Mandatory=$False)]
				[boolean]
				$DebugLevel
			)
			$scriptDir=($PSCmdlet.SessionState.Path.CurrentLocation).Path
			$Path=$env:PSModulePath.split(";")
			if($Path -notcontains $scriptDir){
				$Path+=$scriptDir
				$Path=[string]::Join(";",$Path)
				[System.Environment]::SetEnvironmentVariable('PSModulePath',$Path)
			}
			$module=import-module svmtools -PassThru
			if ( $module -eq $null ) {
					Write-Error "ERROR: Failed to load module SVMTOOLS"
					exit 1
			}
			$Global:mutexconsole=$mutexconsole
			$dir=split-path -Path $LOGFILE -Parent
			$file=split-path -Path $LOGFILE -Leaf
			$Global:LOGFILE=($dir+'\'+$myPrimaryVserver+'\'+$file)
			check_create_dir -FullPath $global:LOGFILE -Vserver $myPrimaryVserver
			Write-Log "[$myPrimaryVserver] Log File is [$global:LOGFILE]"
			rotate_log
			$Global:SVMTOOL_DB=$SVMTOOL_DB
			$Global:JsonPath=$($SVMTOOL_DB+"\"+$myPrimaryVserver+"\"+$BackupDate+"\")
			Write-Log "[$myPrimaryVserver] Backup Folder is [$Global:JsonPath]"
			check_create_dir -FullPath $($Global:JsonPath+"backup.json") -Vserver $myPrimaryVserver
			Write-Log "[$myPrimaryVserver] Backup Folder after check_create_dir is [$Global:JsonPath]"
            if ( ( $ret=create_vserver_dr -myPrimaryController $myPrimaryController -workOn $myPrimaryVserver -Backup -myPrimaryVserver $myPrimaryVserver -DDR $False)[-1] -ne $True ){
				Write-LogDebug "create_vserver_dr return False [$ret]"
				return $False
			}
			Write-LogDebug "create_vserver_dr correctly finished [$ret]"
            return $True
        })
        $BackupJob=[System.Management.Automation.PowerShell]::Create()
        ## $createVserverBackup=Get-Content Function:\create_vserver_dr -ErrorAction Stop
        ## $codeBackup=$createVserverBackup.Ast.Body.Extent.Text
        [void]$BackupJob.AddScript($codeBackup)
        [void]$BackupJob.AddParameter("script_path",$scriptDir)
        [void]$BackupJob.AddParameter("myPrimaryController",$NcPrimaryCtrl)
        [void]$BackupJob.AddParameter("myPrimaryVserver",$svm)
		[void]$BackupJob.AddParameter("SVMTOOL_DB",$SVMTOOL_DB)
		[void]$BackupJob.AddParameter("mutexconsole",$Global:mutexconsole)
		[void]$BackupJob.AddParameter("BackupDate",$BackupDate)
		[void]$BackupJob.AddParameter("LOGFILE",$Global:LOGFILE)
		[void]$BackupJob.AddParameter("DebugLevel",$DebugLevel)
		$BackupJob.RunspacePool=$RunspacePool_Backup
		#wait-debugger
		#$Object = New-Object 'System.Management.Automation.PSDataCollection[psobject]'
        $Handle=$BackupJob.BeginInvoke()
        $JobBackup = "" | Select-Object Handle, Thread, Name
        $JobBackup.Handle=$Handle
        $JobBackup.Thread=$BackupJob
		$JobBackup.Name=$svm
		<# if($JobBackup.Thread.InvocationStateInfo.State -eq "Failed"){
			$reason=$JobBackup.Thread.InvocationStateInfo.Reason
			Write-LogDebug "ERROR: Failed to invoke Backup Job [$svm] Reason: $reason"
			clean_and_exit 1
		}
		if($JobBackup.Thread.Streams.Error -ne $null){
			$reason=$JobBackup.Thread.Stream.Error
			Write-LogDebug "ERROR: Failed to invoke Backup Job [$svm] Reason: $reason"
			clean_and_exit 1
		} #>
		$Jobs_Backup+=$JobBackup
		$numJobBackup++
	}
    While (($Jobs_Backup | Where-Object {$_.Handle.IsCompleted -eq $True} | Measure-Object).Count -ne $numJobBackup){
        $JobRemain=$Jobs_Backup | Where-Object {$_.Handle.IsCompleted -eq $False}
		$Remaining=""
		$Remaining=$JobRemain.Name
		If ($Remaining.Length -gt 80){
			$Remaining = $Remaining.Substring(0,80) + "..."
		}
		$numberRemaining=($JobRemain | Measure-Object).Count
		if($numberRemaining -eq $null -or $numberRemaining -eq 0){
			$JobRemain
		}
		$percentage=[math]::round((($numJobBackup-$numberRemaining) / $numJobBackup) * 100)
		Write-Progress `
			-id 1 `
			-Activity "Waiting for all $numJobBackup Jobs to finish..." `
			-PercentComplete (((($Jobs_Backup.Count)-$numberRemaining) / $Jobs_Backup.Count) * 100) `
			-Status "$($($($Jobs_Backup | Where-Object {$_.Handle.IsCompleted -eq $False})).count) remaining task(s) : $Remaining [$percentage% done]"
	}
	ForEach ($JobBackup in $($Jobs_Backup | Where-Object {$_.Handle.IsCompleted -eq $True})){
        $jobname=$JobBackup.Name
        if($DebugLevel){Write-log "$jobname finished" "Blue"}
        $result_Backup=$JobBackup.Thread.EndInvoke($JobBackup.Handle)
		if($result_Backup.count -gt 0){
			$ret=$result_Backup[-1]
		}else{
			$ret=$result_Backup
		}
		if($ret -ne $True){
			Write-LogError "ERROR: Backup for SVM [$jobname]"
			Write-LogError "Check log"
		}
        #Write-LogDebug "result Backup Job [$jobname] = $result_Backup"
    }
    $RunspacePool_Backup.Close()
	$RunspacePool_Backup.Dispose()

    # end 
    $stopwatch.stop()
    Write-Log $("Finished - Script ran for {0}" -f $stopwatch.Elapsed.toString())
    clean_and_exit 0
}

if ( $Restore ) {
    $Run_Mode="Restore"
    Write-LogOnly "SVMTOOL Run Restore"
    if ((Test-Path $CONFFILE) -eq $True ) {
		$read_conf = read_config_file $CONFFILE
		if ( $read_conf -eq $null ){
        		Write-LogError "ERROR: read configuration file $CONFFILE failed"
        		clean_and_exit 1
        }
        $SVMTOOL_DB=$read_conf.Get_Item("SVMTOOL_DB")
    }
    if($SVMTOOL_DB.Length -gt 0){
        Write-Log "Restore from Cluster [$Restore] from Backup Folder [$SVMTOOL_DB]"
    }else{
		Write-Error "ERROR: No Backup Folder configured, check configuration file [$CONFFILE] for item [SVMTOOL_DB]"
		clean_and_exit 1
	}
    $RESTOREALLSVM=$False
    if($Vserver.Length -eq 0){ 
        Write-Log "No SVM selected, will restore all SVM availables in Backup folder for Cluster [$Restore]"
        $RESTOREALLSVM=$True
    }else{
        Write-LogDebug "Restore SVM [$Vserver] from Backup for Cluster [$Restore]"
	}
	if($Destination.length -lt 1){
		$Destination=$Restore
		Write-LogDebug "No Destination specified. Will restore on source Cluster [$Destination]"
	}else{
		Write-LogDebug "Will restore on new Cluster [$Destination]"	
	}
    $myCred=get_local_cDotcred ($Destination)
    $tmp_str=$MyCred.UserName
	Write-LogDebug "Connect to cluster [$Destination] with login [$tmp_str]"
	Write-LogDebug "connect_cluster -myController $Destination -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcSecondaryCtrl =  connect_cluster -myController $Destination -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$Destination]" 
		clean_and_exit 1
    }
    if($RESTOREALLSVM -eq $True){
		if(($ALLSVM=(Get-ChildItem $SVMTOOL_DB).Name) -eq $null){
			$Return = $False ; throw "ERROR: Get-ChildItem failed for [$SVMTOOL_DB]`nERROR: no Backup available"
		}
        if($AllSVM){
            $SVMList=$AllSVM
        }
    }else{
		if((Test-Path $SVMTOOL_DB) -eq $null){
			$Return = $False ; throw "ERROR: no Backup available for [$Restore] inside [$SVMTOOL_DB]"	
		}else{
			$SVMList=@($Vserver)
		}
    }
    #Loop to backup all SVM in List . Loop in RunspacePool
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $RunspacePool_Restore=[runspacefactory]::CreateRunspacePool(1, $NumberOfLogicalProcessor, $iss, $Host)
    $RunspacePool_Restore.Open()
    [System.Collections.ArrayList]$jobs = @()
    $stopwatch=[system.diagnostics.stopwatch]::StartNew()
    $SVMcount=($SVMList | Measure-Object -Sum).Count
	$Jobs_Restore = @()
	$numJobRestore=0
    foreach($svm in $SVMList){
		Write-Log "Select Backup Date for [$svm]"
		$BackupAvailable=Get-ChildItem $($SVMTOOL_DB+"\"+$svm) | Sort-Object -Property CreationTime
		if($BackupAvailable -eq $null){
			Write-Error "ERROR: No Backup available for [$svm]"
			next
		}else{
			$ans=$null
			if($SelectBackupDate -eq $True){
				$listBackupAvailable=($BackupAvailable | select-object Name).Name
				while($ans -eq $null){
					Write-Host "Select a Backup Date for [$svm] : "
					$i=1
					foreach($date in $listBackupAvailable){
						$numFiles=(Get-ChildItem $($SVMTOOL_DB+"\"+$svm+"\"+$date+"\") | Measure-Object).Count
						$datetime=[datetime]::parseexact($date,"yyyyMMddHHmmss",$null)
						Write-Host "`t$i : [$datetime] [$numFiles Files]"
						$i++
					}
					$Query="Please select Backup from (1.."+($i-1)+") ["+($i-1)+"] ?"
					$ans=Read-Host $Query
					if($ans.length -eq 0){$ans=$listBackupAvailable.count}
					$ans=[int]$ans/1
					if(($ans -notmatch "[0-9]") -or ($ans -lt 1 -or $ans -gt $listBackupAvailable.count)){Write-Warning "Bad input";$ans=$null}
				}
				$date=$listBackupAvailable[$ans-1]
			}else{
				# display lastbackup automatically selected for each SVM (with #files inside folder)
				$LastBackup=$BackupAvailable[-1]
				$date=$LastBackup.Name
				$datetime=[datetime]::parseexact($date,"yyyyMMddHHmmss",$null)
				$numFiles=(Get-ChildItem $($SVMTOOL_DB+"\"+$svm+"\"+$date+"\") | Measure-Object).Count
				Write-Log "[$svm] Last Backup date is [$datetime] with [$numFiles Files]"
			}
		}
		$JsonPath=$($SVMTOOL_DB+"\"+$svm+"\"+$date+"\")
		Write-Log "Create Restore Job for [$svm] from [$JsonPath]"
		#Write-Log "RW [$RW] DebugLevel [$DebugLevel]"
		#Write-Log "JSON path [$JsonPath]"
		$codeRestore=[scriptblock]::Create({
            param(
                [Parameter(Mandatory=$True)][string]$script_path,
                [Parameter(Mandatory=$True)][string]$SourceVserver,
				[Parameter(Mandatory=$True)][string]$SVMTOOL_DB,
                [Parameter(Mandatory=$True)][System.Threading.WaitHandle]$mutexconsole,
                [Parameter(Mandatory=$True)][String]$JsonPath,
				[Parameter(Mandatory=$True)][String]$LOGFILE,
				[Parameter(Mandatory=$True)][NetApp.Ontapi.Filer.C.NcController]$DestinationController,
				[Parameter(Mandatory=$True)][string]$VOLTYPE,
				[Parameter(Mandatory=$False)][boolean]$DebugLevel
            )
            $scriptDir=($PSCmdlet.SessionState.Path.CurrentLocation).Path
			$Path=$env:PSModulePath.split(";")
			if($Path -notcontains $scriptDir){
				$Path+=$scriptDir
				$Path=[string]::Join(";",$Path)
				[System.Environment]::SetEnvironmentVariable('PSModulePath',$Path)
			}
			$module=import-module svmtools -PassThru
			if ( $module -eq $null ) {
					Write-Error "ERROR: Failed to load module SVMTOOLS"
					exit 1
			}
			$Global:mutexconsole=$mutexconsole
			$dir=split-path -Path $LOGFILE -Parent
			$file=split-path -Path $LOGFILE -Leaf
			$Global:LOGFILE=($dir+'\'+$SourceVserver+'\'+$file)
			check_create_dir -FullPath $global:LOGFILE -Vserver $SourceVserver
			$Global:SVMTOOL_DB=$SVMTOOL_DB
			$Global:JsonPath=$JsonPath
			$Global:VOLUME_TYPE=$VOLTYPE
			check_create_dir -FullPath $Global:JsonPath -Vserver $SourceVserver
			$DestinationCluster=$DestinationController.Name
			Write-LogDebug ""
			Write-LogDebug "Restore [$SourceVserver] on Cluster [$DestinationCluster]"
			Write-LogDebug "LOGFILE [$Global:LOGFILE]"
			Write-LogDebug "SVMTOOL_DB [$Global:SVMTOOL_DB]"
			Write-LogDebug "JsonPath [$Global:JsonPath]"
			Write-LogDebug "SourceVserver [$SourceVserver]"
			Write-LogDebug "DestinationController [$DestinationController]"
			Write-LogDebug "VOLUME_TYPE [$Global:VOLUME_TYPE]"
            if ( ( $ret=create_vserver_dr -myPrimaryVserver $SourceVserver -mySecondaryController $DestinationController -workOn $SourceVserver -mySecondaryVserver $SourceVserver -Restore -DDR $False )[-1] -ne $True ){
                return $False
            }
            return $True
        })
        $RestoreJob=[System.Management.Automation.PowerShell]::Create()
        ## $createVserverVackup=Get-Content Function:\create_vserver_dr -ErrorAction Stop
        ## $codeRestore=$createVserverVackup.Ast.Body.Extent.Text
        [void]$RestoreJob.AddScript($codeRestore)
        [void]$RestoreJob.AddParameter("script_path",$scriptDir)
        [void]$RestoreJob.AddParameter("SourceVserver",$svm)
		[void]$RestoreJob.AddParameter("SVMTOOL_DB",$SVMTOOL_DB)
		[void]$RestoreJob.AddParameter("mutexconsole",$Global:mutexconsole)
		[void]$RestoreJob.AddParameter("JsonPath",$JsonPath)
		[void]$RestoreJob.AddParameter("LOGFILE",$Global:LOGFILE)
		[void]$RestoreJob.AddParameter("DestinationController",$NcSecondaryCtrl)
		if($RW -eq $True){
			[void]$RestoreJob.AddParameter("VOLTYPE","RW")
		}else{
			[void]$RestoreJob.AddParameter("VOLTYPE","DP")
		}
		[void]$RestoreJob.AddParameter("DebugLevel",$DebugLevel)
		$RestoreJob.RunspacePool=$RunspacePool_Restore
        $Handle=$RestoreJob.BeginInvoke()
        $JobRestore = "" | Select-Object Handle, Thread, Name, Log
        $JobRestore.Handle=$Handle
        $JobRestore.Thread=$RestoreJob
		$JobRestore.Name=$svm
		$dir=split-path -Path $Global:LOGFILE -Parent
		$file=split-path -Path $Global:LOGFILE -Leaf
		$LOGJOB=($dir+'\'+$svm+'\'+$file)
		$JobRestore.Log=$LOGJOB
		if($JobRestore.Thread.InvocationStateInfo.State -eq "Failed"){
			$reason=$JobRestore.Thread.InvocationStateInfo.Reason
			Write-LogDebug "ERROR: Failed to invoke Restore Job [$svm] Reason: [$reason]"
			clean_and_exit 1
		}
		if($JobRestore.Thread.Streams.Error -ne $null){
			$reason=$JobRestore.Thread.Stream.Error
			Write-LogDebug "ERROR: Failed to invoke Restore Job [$svm] Reason: [$reason]"
			clean_and_exit 1
		}
		$Jobs_Restore+=$JobRestore
		$numJobRestore++
    }
	While (@($Jobs_Restore | Where-Object {$_.Handle.IsCompleted -eq $True} | Measure-Object).Count -ne $numJobRestore){
        $JobRemain=$Jobs_Restore | Where-Object {$_.Handle.IsCompleted -eq $False}
		$Remaining=""
		$Remaining=$JobRemain.Name
		If ($Remaining.Length -gt 80){
			$Remaining = $Remaining.Substring(0,80) + "..."
		}
		$numberRemaining=($JobRemain | Measure-Object).Count
		if($numberRemaining -eq $null -or $numberRemaining -eq 0){
			$JobRemain
		}
		$percentage=[math]::round((($numJobRestore-$numberRemaining) / $numJobRestore) * 100)
		Write-Progress `
			-id 1 `
			-Activity "Waiting for all $numJobRestore Jobs to finish..." `
			-PercentComplete (((($Jobs_Restore.Count)-$numberRemaining) / $Jobs_Restore.Count) * 100) `
			-Status "$($($($Jobs_Restore | Where-Object {$_.Handle.IsCompleted -eq $False})).count) remaining : $Remaining [$percentage% done]"
	}
	ForEach ($JobRestore in $($Jobs_Restore | Where-Object {$_.Handle.IsCompleted -eq $True})){
        $jobname=$JobRestore.Name
        Write-logDebug "$jobname finished"
        $result_Restore=$JobRestore.Thread.EndInvoke($JobRestore.Handle)
		if($result_Restore.count -gt 0){
			$ret=$result_Restore[-1]
		}else{
			$ret=$result_Restore
		}
		if($ret -ne $True){
			Write-LogError "ERROR: Restore for SVM [$jobname]:[$ret]:[$result_Restore]"
			$LOGPATH=$JobRestore.Log
			Write-LogError "Check log [$LOGPATH]"
		}
        #Write-LogDebug "result Restore Job [$jobname] = $result_Restore"
    }
    $RunspacePool_Restore.Close()
	$RunspacePool_Restore.Dispose()
    # end 
    $stopwatch.stop()
    Write-Log $("Finished - Script ran for {0}" -f $stopwatch.Elapsed.toString())
    clean_and_exit 0
}

if ( ( Test-Path $CONFFILE ) -eq $False )  {
        Write-LogError "ERROR: instance [$instance] not found please run setup option" 
	clean_and_exit 1
}

if ( ( $Vserver -eq $null ) -or ( $Vserver -eq "" ) ) { 
	Write-LogError "ERROR: Missing an argument for parameter 'Vserver'" 
	Write-LogError "ERROR: Please run svmdr -help for information" 
	Clean_and_exit 1 
}

# Read configuration file
$read_conf = read_config_file $CONFFILE ;
if ( $read_conf -eq $null ){
        Write-LogError "ERROR: read configuration file $CONFFILE failed" 
        clean_and_exit 1 ;
}

$PRIMARY_CLUSTER=$read_conf.Get_Item("PRIMARY_CLUSTER") ;
if ( $PRIMARY_CLUSTER -eq $Null ) {
	Write-LogError "ERROR: unable to find PRIMARY_CLUSTER in $CONFFILE"
        clean_and_exit 1 ;
}
$SECONDARY_CLUSTER=$read_conf.Get_Item("SECONDARY_CLUSTER") ;
if ( $SECONDARY_CLUSTER -eq $Null ) {
	Write-LogError "ERROR: unable to find SECONDARY_CLUSTER in $CONFFILE"
        clean_and_exit 1 ;
}

if ($PRIMARY_CLUSTER -eq $SECONDARY_CLUSTER) 
{ 
    $SINGLE_CLUSTER = $True
    Write-LogDebug "Detected SINGLE_CLUSTER Configuration"
}

# Read Vserver configuration file
$VCONFFILE=$CONFDIR + $Vserver + '.conf'
if ($RemoveDRconf) {
    $Run_Mode="RemoveDRconf"
	Write-LogOnly "SVMDR RemoveDRconf"
	if ((Test-Path $VCONFFILE ) -eq $True ) {
		Remove-Item $VCONFFILE
	}
        clean_and_exit 1 ;
}

Write-LogDebug "VCONFFILE [$VCONFFILE]"
$read_vconf = read_config_file $VCONFFILE

if ( ( $Setup ) -or ( $read_vconf -eq $null ) ) {
	$myCred=get_local_cDotcred ($PRIMARY_CLUSTER) 
	$tmp_str=$MyCred.UserName
	Write-LogDebug "Connect to cluster [$PRIMARY_CLUSTER] with login [$tmp_str]"
	Write-LogDebug "connect_cluster -myController $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcPrimaryCtrl =  connect_cluster -myController $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$PRIMARY_CLUSTER]" 
        	clean_and_exit 1 ;
	}
	$myCred=get_local_cDotcred ($SECONDARY_CLUSTER) 
	Write-LogDebug "connect_cluster -myController $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcSecondaryCtrl =  connect_cluster -myController $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$SECONDARY_CLUSTER]" 
        	clean_and_exit 1 ;
	}
	$VserverPeerList= get_vserver_peer_list -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver
	if ( $VserverPeerList ) {
		Write-Log "$Vserver has already existing vserver peer to the cluster [$NcSecondaryCtrl]"
		foreach ( $VserverPeer in $VserverPeerList ) {
			Write-Log "[$Vserver] -> [$VserverPeer]"
		}
	}
	create_vserver_config_file_cli -Vserver $Vserver -ConfigFile $VCONFFILE
	$read_vconf = read_config_file $VCONFFILE
	if ( $read_vconf -eq $null ){
		Write-LogError "ERROR: Failed to create $VCONFFILE "
		clean_and_exit 2
	}
	if ( ! $ConfigureDR ) {
		clean_and_exit 0
	}
}

$VserverDR=$read_vconf.Get_Item("VserverDR")
if ( $Vserver -eq $Null ) {
	Write-LogError "ERROR: unable to find VserverDR in $VCONFFILE"
        clean_and_exit 1 ;
}
$AllowQuotaDR=$read_vconf.Get_Item("AllowQuotaDR")
$SVMTOOL_DB=$read_conf.Get_Item("SVMTOOL_DB")
$Global:SVMTOOL_DB=$SVMTOOL_DB
$Global:CorrectQuotaError=$CorrectQuotaError
$Global:ForceDeleteQuota=$ForceDeleteQuota
$Global:ForceActivate=$ForceActivate
$Global:ForceRecreate=$ForceRecreate
$Global:AlwaysChooseDataAggr=$AlwaysChooseDataAggr
$Global:SelectVolume=$SelectVolume
$Global:IgnoreQtreeExportPolicy=$IgnoreQtreeExportPolicy
$Global:AllowQuotaDr=$AllowQuotaDr
$Global:IgnoreQuotaOff=$IgnoreQuotaOff

Write-LogDebug "PRIMARY_CLUSTER:            		 [$PRIMARY_CLUSTER]" 
Write-LogDebug "SECONDARY_CLUSTER:          		 [$SECONDARY_CLUSTER]" 
Write-LogDebug "VSERVER                     		 [$Vserver]" 
Write-LogDebug "VSERVER DR                  		 [$VserverDR]" 
Write-LogDebug "QUOTA DR                    		 [$Global:AllowQuotaDr]" 
Write-LogDebug "SVMTOOL DB                           [$Global:SVMTOOL_DB]"
Write-LogDebug "OPTION IgnoreQuotaOff       		 [$Global:IgnoreQuotaOff]"
Write-LogDebug "OPTION CorrectQuotaError    		 [$Global:CorrectQuotaError]"
Write-LogDebug "OPTION ForceDelete          		 [$Global:ForceDeleteQuota]"
Write-LogDebug "OPTION ForceActivate        		 [$Global:ForceActivate]"
Write-LogDebug "OPTION ForceRecreate        		 [$Global:ForceRecreate]"
Write-LogDebug "OPTION AlwaysChooseDataAggr 		 [$Global:AlwaysChooseDataAggr]"
Write-LogDebug "OPTION SelectVolume         		 [$Global:SelectVolume]"
Write-LogDebug "OPTION IgnoreQtreeExportPolicy       [$Global:IgnoreQtreeExportPolicy]"

if ( $ShowDR ) {
    $Run_Mode="ShowDR"
	Write-LogOnly "SVMDR ShowDR"
	# Connect to the Cluster
	$myCred=get_local_cDotcred ($PRIMARY_CLUSTER) 
	$tmp_str=$MyCred.UserName
	Write-LogDebug "Connect to cluster [$PRIMARY_CLUSTER] with login [$tmp_str]"
	Write-LogDebug "connect_cluster -myController $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcPrimaryCtrl =  connect_cluster -myController $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$PRIMARY_CLUSTER]" 
		$NcPrimaryCtrl =  $null
	}
	$myCred=get_local_cDotcred ($SECONDARY_CLUSTER) 
	Write-LogDebug "connect_cluster -myController $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcSecondaryCtrl =  connect_cluster -myController $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$SECONDARY_CLUSTER]" 
		$NcSecondaryCtrl = $null
	}
	Write-LogDebug "show_vserver_dr -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR"
	$ret=show_vserver_dr -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR
	clean_and_exit 0
}

if ( $ConfigureDR ) {
    $Run_Mode="ConfigureDR"
	Write-LogOnly "SVMDR ConfigureDR"
	# Connect to the Cluster
	$myCred=get_local_cDotcred ($PRIMARY_CLUSTER) 
	$tmp_str=$MyCred.UserName
	Write-LogDebug "Connect to cluster [$PRIMARY_CLUSTER] with login [$tmp_str]"
	Write-LogDebug "connect_cluster -myController $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcPrimaryCtrl =  connect_cluster -myController $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$PRIMARY_CLUSTER]" 
        	clean_and_exit 1
	}
	$myCred=get_local_cDotcred ($SECONDARY_CLUSTER) 
	Write-LogDebug "connect_cluster -myController $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcSecondaryCtrl =  connect_cluster -myController $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$SECONDARY_CLUSTER]" 
        	clean_and_exit 1
	}
    $DestVserver=Get-NcVserver -Vserver $VserverDR -Controller $NcSecondaryCtrl -ErrorVariable ErrorVar
    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcVserver failed [$ErrorVar]" }
    if($DestVserver.IsConfigLockedForChanges -eq $True){
        if ($DebugLevel) {Write-logDebug "Unlock-NcVserver -Vserver $VserverDR -Force -Confirm:$False -Controller $NcSecondaryCtrl"}
        $ret=Unlock-NcVserver -Vserver $VserverDR -Force -Confirm:$False -Controller $NcSecondaryCtrl -ErrorVariable ErrorVar
        if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Dest Vserver [$VserverDR] has its config locked. Unlock-NcVserver failed [$ErrorVar]" }
    }
	if ( ( $ret=check_cluster_peer -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl ) -ne $True ) {
		Write-LogError "ERROR: check_cluster_peer" 
		clean_and_exit 1
	}
	if ( $XDPPolicy -ne "MirrorAllSnapshots" ){
		$ret=Get-NcSnapmirrorPolicy -Name $XDPPolicy -Controller $NcSecondaryCtrl -ErrorVariable ErrorVar
		if( $? -ne $True -or $ret.count -eq 0 ){
			Write-LogDebug "XDPPolicy [$XDPPolicy] does not exist on [$SECONDARY_CLUSTER]. Will use MirrorAllSnapshots as default Policy"
            Write-Warning "XDPPolicy [$XDPPolicy] does not exist on [$SECONDARY_CLUSTER]. Will use [MirrorAllSnapshots] as default Policy for all XDP relationships"
			$XDPPolicy="MirrorAllSnapshots"
		}
	}
    if($DRfromDR.IsPresent){
		if ( ( $ret=create_vserver_dr -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR -DDR $True -XDPPolicy $XDPPolicy)[-1] -ne $True ) {
			clean_and_exit 1
		}
	}else{
		if ( ( $ret=create_vserver_dr -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR -DDR $False -XDPPolicy $XDPPolicy)[-1] -ne $False ) {
			clean_and_exit 1
		}
	}
	

  	if ( ( $ret=svmdr_db_switch_datafiles -myController $NcPrimaryCtrl -myVserver $Vserver ) -eq $false ) {
        	Write-LogError "ERROR: Failed to switch SVMTOOL_DB datafiles" 
        	clean_and_exit 1
  	}
    # Verify if CIFS Service is Running if yes stop it
	$CifService = Get-NcCifsServer  -VserverContext  $VserverDR -Controller $NcSecondaryCtrl  -ErrorVariable ErrorVar
	if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcCifsServer failed [$ErrorVar]" }
	if ( $CifService -eq $null ) {
		Write-Log "No CIFS services in vserver [$VserverDR]"
	} else {
		if ( $CifService.AdministrativeStatus -eq 'up' ) {
			Write-LogDebug "stop-NcCifsServer -VserverContext $VserverDR -Controller $NcSecondaryCtrl -Confirm:$False"
			$out=Stop-NcCifsServer -VserverContext $VserverDR -Controller $NcSecondaryCtrl  -ErrorVariable ErrorVar -Confirm:$False
			if ( $? -ne $True ) {
				Write-LogError "ERROR: Failed to disable CIFS on Vserver [$VserverDR]" 
				$Return = $False
			}
		}
	}
	if ( ( $ret=save_vol_options_to_voldb -myController $NcPrimaryCtrl -myVserver $Vserver ) -ne $True ) {
		Write-LogError "ERROR: save_vol_options_to_voldb failed"
		clean_and_exit 1
	}

	Write-LogDebug "AllowQuotaDR [$AllowQuotaDr]"
	if ( $AllowQuotaDR -eq "True" ) {
		Write-Log "[$VserverDR] Save quota policy rules to SVMTOOL_DB [$SVMTOOL_DB]" 
		if ( ( $ret=save_quota_rules_to_quotadb -myPrimaryController $NcPrimaryCtrl -myPrimaryVserver $Vserver -mySecondaryController $NcSecondaryCtrl -mySecondaryVserver $VserverDR ) -ne $True ) {
 			Write-LogError "ERROR: save_quota_rules_to_quotadb failed"
 			clean_and_exit 1
		}
	}
	clean_and_exit 0
}

if ( $DeleteDR ) {
    $Run_Mode="DeleteDR"
	Write-LogOnly "SVMDR DeleteDR"
	# Connect to the Cluster
	$myCred=get_local_cDotcred ($PRIMARY_CLUSTER) 
	$tmp_str=$MyCred.UserName
	Write-LogDebug "Connect to cluster [$PRIMARY_CLUSTER] with login [$tmp_str]"
	Write-LogDebug "connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcPrimaryCtrl =  connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$PRIMARY_CLUSTER]" 
        	clean_and_exit 1
	}
	$myCred=get_local_cDotcred ($SECONDARY_CLUSTER) 
	Write-LogDebug "connect_cluster $SECONDARY_CLUSTER -myCred $MyCred  -myTimeout $Timeout"
	if ( ( $NcSecondaryCtrl =  connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$SECONDARY_CLUSTER]" 
        	clean_and_exit 1
	}
    # if ( ( $ret=analyse_junction_path -myController $NcPrimaryCtrl -myVserver $Vserver ) -ne $True ) {
    	# Write-LogError "ERROR: analyse_junction_path" 
		# clean_and_exit 1
	# }
	if ( ( $ret=remove_vserver_dr -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR ) -eq $False ) {
		Write-LogError "ERROR: remove_vserver_dr: Unable to remove Vserver [$VserverDR]" 
		clean_and_exit 1
	}
	clean_and_exit 0
}

if($Migrate){
    $Run_Mode="Migrate"
    Write-LogOnly "SVMDR Migrate"
    # Connect to the Cluster
	$myCred=get_local_cDotcred ($PRIMARY_CLUSTER) 
	$tmp_str=$MyCred.UserName
	Write-LogDebug "Connect to cluster [$PRIMARY_CLUSTER] with login [$tmp_str]"
	Write-LogDebug "connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcPrimaryCtrl =  connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$PRIMARY_CLUSTER]" 
        	clean_and_exit 1
	}
	$PrimaryClusterName=$NcPrimaryCtrl.Name
	$myCred=get_local_cDotcred ($SECONDARY_CLUSTER) 
	Write-LogDebug "connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcSecondaryCtrl =  connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$SECONDARY_CLUSTER]" 
        	clean_and_exit 1
	}
	$SecondaryClusterName=$NcSecondaryCtrl.Name
	# if ( ( $ret=analyse_junction_path -myController $NcPrimaryCtrl -myVserver $Vserver ) -ne $True ) {
    	# Write-LogError "ERROR: analyse_junction_path" 
		# clean_and_exit 1
	# }
    Write-Warning "SVM DR script does not manage FCP configuration and SYMLINK"
    Write-Warning "You will have to backup and recreate all these configurations manually after the Migrate step"
    Write-Warning "Files Locks are not migrated during the Migration process"
    $ASK_WAIT=Read-Host "Does all Client have cleanly saves their jobs [$Vserver] ? [y/n]"
    if($ASK_WAIT -eq 'y'){
        Write-LogDebug "Client ready to migrate. User choose to continue migration procedure"
		Write-Log "[$VserverDR] Run last UpdateDR"
		if ( ( $ret=create_update_cron_dr -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl ) -ne $True ) {
			Write-LogError "ERROR: create_update_cron_dr"
		}
		if ( ( $ret=create_update_snap_policy_dr -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR) -ne $True ) {
			Write-LogError "ERROR: create_update_snap_policy_dr"
		}

		if ( ( $ret=check_cluster_peer -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl ) -ne $True ) {
			Write-LogError "ERROR: check_cluster_peer failed"
			clean_and_exit 1
		}

		# if ( $LastSnapshot ) {
				# $UseLastSnapshot = $True
		# } else {
				# $UseLastSnapshot = $False
		# }
		if ( ( $ret=update_cifs_usergroup -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR -NoInteractive) -ne $True ) {
			    Write-LogError "ERROR: update_cifs_usergroup failed"   
		}
		if($DRfromDR.IsPresent){
			if ( ($ret=update_vserver_dr -myDataAggr $DataAggr -UseLastSnapshot $UseLastSnapshot -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR -DDR $True) -ne $True ) {
				Write-LogError "ERROR: update_vserver_dr failed" 
				clean_and_exit 1
			}
		}else{
			if ( ($ret=update_vserver_dr -myDataAggr $DataAggr -UseLastSnapshot $UseLastSnapshot -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR -DDR $False) -ne $True ) {
				Write-LogError "ERROR: update_vserver_dr failed" 
				clean_and_exit 1
			}
		}
		

		# if ( $MirrorSchedule ) {
			# Write-LogDebug "Flag MirrorSchedule"
		# }
		if ( ( $ret=wait_snapmirror_dr -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR ) -ne $True ) 
		{ 
			Write-LogError  "ERROR: wait_snapmirror_dr failed"  
		}

		if ( ( $ret=break_snapmirror_vserver_dr -myController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR ) -ne $True ) {
			Write-LogError "ERROR: Unable to break all relations from Vserver [$VserverDR] on [$SecondaryClusterName]"
			clean_and_exit 1
		}
		# Remove Reverse SnapMirror Relationship if exist
		if ( ( $ret=remove_snapmirror_dr -myPrimaryController $NcSecondaryCtrl -mySecondaryController $NcPrimaryCtrl -myPrimaryVserver $VserverDR -mySecondaryVserver $Vserver	 ) -ne $True ) { 
			Write-LogError "ERROR: remove_snapmirror_dr failed"
			clean_and_exit 1
		}
		# Remove SnapMirror Relationship 
		if ( ( $ret=remove_snapmirror_dr -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR -NoRelease) -ne $True ) {
			Write-LogError "ERROR: remove_snapmirror_dr failed" 
			clean_and_exit 1
		}
		# Restamp MSID destination volume
		if ( ( $ret=restamp_msid -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDr) -ne $True) {
			Write-LogError "ERROR: restamp_msid failed"
			clean_and_exit 1
		}
        $ASK_MIGRATE=Read-Host "IP and Services will switch now for [$Vserver]. Ready to go ? [y/n]"
        if($ASK_MIGRATE -eq 'y'){
		    if ( ( $ret=migrate_lif -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR) -ne $True ) {
			    Write-LogError "ERROR: migrate_lif failed"
			    clean_and_exit 1
		    }

		    if ( ( $ret=migrate_cifs_server -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR -NoInteractive) -ne $True ) {
			    Write-LogError "ERROR: migrate_cifs_server failed"
			    clean_and_exit 1
		    }
		    if (($ret=set_all_lif -mySecondaryVserver $VserverDR -myPrimaryVserver $Vserver -mySecondaryController $NcSecondaryCtrl  -myPrimaryController $NcPrimaryCtrl -state up) -ne $True ) {
				Write-LogError "ERROR: Failed to set all lif up on [$VserverDR]"
				clean_and_exit 1
			}
            #if (($ret=set_all_lif -myVserver $VserverDR -myController $NcSecondaryCtrl -state down) -ne $True ) {
            #    Write-LogError "ERROR: Failed to set all lif down on [$VserverDR]"
            #    clean_and_exit 1
            #}
		    # Verify if NFS service is Running 
		    Write-LogDebug "Get-NcNfsService -VserverContext $VserverDR -Controller $NcSecondaryCtrl"
		    $NfsService = Get-NcNfsService -VserverContext $VserverDR -Controller $NcSecondaryCtrl  -ErrorVariable ErrorVar
		    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcNfsService failed [$ErrorVar]" }
		    if ( $NfsService -eq $null ) {
			    Write-Log "No NFS services in vserver [$VserverDR]"
		    } else {
			    if ( $NfsService.GeneralAccess -ne $True ) {
				    Write-Log "Enable NFS on Vserver [$VserverDR]"
				    Write-LogDebug "Enable-NcNfs -VserverContext $VserverDR -Controller $NcSecondaryCtrl"
				    $out=Enable-NcNfs -VserverContext $VserverDR -Controller $NcSecondaryCtrl  -ErrorVariable ErrorVar -Confirm:$False
				    if ( $? -ne $True ) {
					    Write-warning "ERROR: Failed to enable NFS on Vserver [$VserverDR] [ErrorVar]"
					    Write-LogError "ERROR: Failed to enable NFS on Vserver [$VserverDR]" 
				    }
                    Write-LogDebug "Disable-NcNfs -VserverContext $VserverDR -Controller $NcPrimaryCtrl"
				    $out=Disable-NcNfs -VserverContext $Vserver -Controller $NcPrimaryCtrl  -ErrorVariable ErrorVar -Confirm:$False
				    if ( $? -ne $True ) {
					    Write-warning "ERROR: Failed to disable NFS on Vserver [$VserverDR] [ErrorVar]"
					    Write-LogError "ERROR: Failed to disable NFS on Vserver [$VserverDR]" 
				    }
			    }
		    }

		    # Verify if ISCSI service is Running 
		    Write-LogDebug "Get-NcIscsiService -VserverContext $VserverDR -Controller $NcSecondaryCtrl"
		    $IscsiService = Get-NcIscsiService -VserverContext $VserverDR -Controller $NcSecondaryCtrl  -ErrorVariable ErrorVar
		    if ( $? -ne $True ) { $Return = $False ; throw "ERROR: Get-NcIscsiService failed [$ErrorVar]" }
		    if ( $IscsiService -eq $null ) {
			    Write-Log "No iSCSI services in Vserver [$VserverDR]"
		    } else {
			    if ( $IscsiService.IsAvailable -ne $True ) {
				    Write-Log "Enable iSCSI service on Vserver [$VserverDR]"
				    Write-LogDebug "Enable-NcIscsi -VserverContext $VserverDR -Controller $NcSecondaryCtrl"
				    $out=Enable-NcIscsi -VserverContext $VserverDR -Controller $NcSecondaryCtrl  -ErrorVariable ErrorVar -Confirm:$False
				    if ( $? -ne $True ) {
					    Write-warning "ERROR: Failed to enable iSCSI on Vserver [$VserverDR] [ErrorVar]"
					    Write-LogError "ERROR: Failed to enable iSCSI on Vserver [$VserverDR] [ErrorVar]" 
				    }
			    }
		    }
		    Write-Log "Vserver [$Vserver] has been migrated on destination cluster [$SecondaryClusterName]"
		    Write-Log "Users can now connect on destination"
            if ( ( $ret=set_vol_options_from_voldb -myController $NcSecondaryCtrl -myVserver $VserverDR -NoCheck) -ne $True ) {
                Write-LogError "ERROR: set_vol_options_from_voldb failed"
            }
            #if ( ( $ret=set_shareacl_options_from_shareacldb -myController $NcSecondaryCtrl -myVserver $VserverDR -NoCheck) -ne $True ) {
            #    Write-LogError "ERROR: set_shareacl_options_from_shareacldb"
            #}
            if ( $AllowQuotaDR -eq "True" ) {
                if ( ( $ret=create_quota_rules_from_quotadb -myController $NcSecondaryCtrl -myVserver $VserverDR -NoCheck ) -ne $True ) {
                    Write-LogError "ERROR: create_quota_rules_from_quotadb failed"
                }
            }
		    $ASK_WAIT2=Read-Host "Do you want to delete Vserver [$Vserver] on source cluster [$PrimaryClusterName]? [y/n]"        
            if($ASK_WAIT2 -eq 'y'){

                if ( ( $ret=remove_snapmirror_dr -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR) -ne $True ) {
			        Write-LogError "ERROR: remove_snapmirror_dr failed" 
			        clean_and_exit 1
		        }

                if ( ( remove_vserver_peer -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR ) -ne $True ) {
		            Write-LogError "ERROR: remove_vserver_peer failed" 
		            return $false
	            }

		        Write-Log "Rename Vserver [$VserverDR] to [$Vserver]"
		        Write-LogDebug "Rename-NcVserver -Name $VserverDR -NewName $Vserver -Controller $NcSecondaryCtrl"
		        $out=Rename-NcVserver -Name $VserverDR -NewName $Vserver -Controller $NcSecondaryCtrl  -ErrorVariable ErrorVar
		        if ( $? -ne $True ) { throw "ERROR: Rename-NcVserver failed [$ErrorVar]"} 
			    Write-Log "Vserver [$Vserver] will be deleted on cluster [$PrimaryClusterName]"
			    if ( ( $ret=remove_vserver_source -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR ) -eq $False ) {
		            Write-LogError "ERROR: remove_vserver_dr: Unable to remove vserver [$VserverDR]" 
		            clean_and_exit 1
	            }
                Write-Log "SVM [$Vserver] completely removed on [$PrimaryClusterName]"
                clean_and_exit 0
            }else{
                Write-Log "User choose not to delete source Vserver [$Vserver] on cluster [$PrimaryClusterName]"
			    Write-Log "Vserver [$Vserver] will only be stopped on [$PrimaryClusterName]"
                Write-Log "In this case the SVM object name on [$SecondaryClusterName] is still [$VserverDR]"
                Write-Log "But CIFS identity is correclty migrated to [$Vserser]"
                Write-Log "Final rename will be done when [DeleteSource] step will be executed, once you are ready to completely delete [$Vserver] on [$PrimaryClusterName]"
			    Write-LogDebug "Stop-NcVserver -Name $Vserver -Controller $NcPrimaryCtrl -Confirm:$False"
			    $ret=Stop-NcVserver -Name $Vserver -Controller $NcPrimaryCtrl -Confirm:$False -ErrorVariable ErrorVar
			    if ( $? -ne $True ) 
			    {
				    throw "ERROR: Stop-NcVerser failed [$ErrorVar]"
				    clean_and_exit 1
			    } 
            }
        }else{
            Write-Log "Migration process has been stopped by user"
            Write-Log "You could restart the [Migrate] step when ready"
            Write-Log "Or resynchronize your DR by running a [Resync -ForceRecreate] then a [ConfigureDR] step"
        }
    }else{
        Write-LogDebug "Client not ready for Migrate"
		Write-Log "Migration canceled"
        clean_and_exit 1
    }
	clean_and_exit 0
}

if( $DeleteSource ) {
    $Run_Mode="DeleteSrouce"
    Write-LogOnly "SVMDR DeleteSource"
    # Connect to the Cluster
	$myCred=get_local_cDotcred ($PRIMARY_CLUSTER) 
	$tmp_str=$MyCred.UserName
	Write-LogDebug "Connect to cluster [$PRIMARY_CLUSTER] with login [$tmp_str]"
	Write-LogDebug "connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcPrimaryCtrl =  connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$PRIMARY_CLUSTER]" 
        	clean_and_exit 1
	}
	$PrimaryClusterName=$NcPrimaryCtrl.Name
	$myCred=get_local_cDotcred ($SECONDARY_CLUSTER) 
	Write-LogDebug "connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcSecondaryCtrl =  connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$SECONDARY_CLUSTER]" 
        	clean_and_exit 1
	}
	$SecondaryClusterName=$NcSecondaryCtrl.Name
    $SourceVserver=Get-NcVserver -Name $Vserver -Controller $NcPrimaryCtrl -ErrorVariable ErrorVar
    if($? -ne $True){Write-LogError "ERROR : SVM [$Vserver] does not exist on [$PrimaryClusterName]";clean_and_exit 1}
    $SourceState=$SourceVserver.State

    $DestVserver=Get-NcVserver -Name $VserverDR -Controller $NcSecondaryCtrl -ErrorVariable ErrorVar
    if($? -ne $True){Write-LogError "ERROR : SVM [$Vserver] does not exist on [$SecondaryClusterName]";clean_and_exit 1}
    $DestState=$DestVserver.State
    if($SourceState -ne "stopped" -or $DestState -ne "running"){
        Write-Log "ERROR : SVM [$Vserver] not correctly migrated to destination [$SecondaryClusterName]. Failed to delete on source"
        clean_and_exit 1
    }else{
        Write-Warning "Delete Source SVM could not be interrupted or rollback"
        $ASK_WAIT=Read-Host "Do you want to completely delete [$Vserver] on [$PrimaryClusterName]? [y/n]"
        if($ASK_WAIT -eq 'y'){
            if ( ( $ret=remove_snapmirror_dr -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR) -ne $True ) {
			    Write-LogError "ERROR: remove_snapmirror_dr failed" 
			    clean_and_exit 1
		    }

            if ( ( remove_vserver_peer -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR ) -ne $True ) {
		        Write-LogError "ERROR: remove_vserver_peer failed" 
		        return $false
	        }

		    Write-Log "Rename Vserver [$VserverDR] to [$Vserver]"
		    Write-LogDebug "Rename-NcVserver -Name $VserverDR -NewName $Vserver -Controller $NcSecondaryCtrl"
		    $out=Rename-NcVserver -Name $VserverDR -NewName $Vserver -Controller $NcSecondaryCtrl  -ErrorVariable ErrorVar
		    if ( $? -ne $True ) { throw "ERROR: Rename-NcVserver failed [$ErrorVar]"} 
		    Write-Log "Vserver [$Vserver] will be deleted on cluster [$PrimaryClusterName]"
		    if ( ( $ret=remove_vserver_source -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR ) -eq $False ) {
		        Write-LogError "ERROR: remove_vserver_dr: Unable to remove vserver [$VserverDR]" 
		        clean_and_exit 1
	        }
            Write-Log "SVM [$Vserver] completely deleted on [$PrimaryClusterName]"
            clean_and_exit 0
        }else{
            Write-Log "SVM [$Vserver] will not be deleted on [$PrimaryClusterName]"
            clean_and_exit 0
        }
    }
}

if ( $UpdateDR ) {
    $Run_Mode="UpdateDR"
	Write-LogOnly "SVMDR UpdateDR"
	# Connect to the Cluster
	$myCred=get_local_cDotcred ($PRIMARY_CLUSTER) 
	$tmp_str=$MyCred.UserName
	Write-LogDebug "Connect to cluster [$PRIMARY_CLUSTER] with login [$tmp_str]"
	Write-LogDebug "connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcPrimaryCtrl =  connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$PRIMARY_CLUSTER]" 
        	clean_and_exit 1
	}
	$myCred=get_local_cDotcred ($SECONDARY_CLUSTER) 
	Write-LogDebug "connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcSecondaryCtrl =  connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$SECONDARY_CLUSTER]" 
        	clean_and_exit 1
	}
	# if ( ( $ret=analyse_junction_path -myController $NcPrimaryCtrl -myVserver $Vserver ) -ne $True ) {
    	# Write-LogError "ERROR: analyse_junction_path" 
		# clean_and_exit 1
	# }
	if ( ( $ret=create_update_cron_dr -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl ) -ne $True ) {
		Write-LogError "ERROR: create_update_cron_dr"
	}
	if ( ( $ret=create_update_snap_policy_dr -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR) -ne $True ) {
		Write-LogError "ERROR: create_update_snap_policy_dr"
	}

	if ( ( $ret=check_cluster_peer -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl ) -ne $True ) {
		Write-LogError "ERROR: check_cluster_peer failed"
		clean_and_exit 1
	}

	if ( $LastSnapshot ) {
    		$UseLastSnapshot = $True
	} else {
    		$UseLastSnapshot = $False
	}
	if($DRfromDR.IsPresent){
		if ( ($ret=update_vserver_dr -myDataAggr $DataAggr -UseLastSnapshot $UseLastSnapshot -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR -DDR $True) -ne $True ) {
			Write-LogError "ERROR: update_vserver_dr failed" 
			 clean_and_exit 1
		}
	}else{
		if ( ($ret=update_vserver_dr -myDataAggr $DataAggr -UseLastSnapshot $UseLastSnapshot -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR -DDR $False) -ne $True ) {
			Write-LogError "ERROR: update_vserver_dr failed" 
			 clean_and_exit 1
		}
	}
	

    if ( ( $ret=update_CIFS_server_dr -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR ) -ne $True ) {
        Write-Warning "Some CIFS options has not been set on [$VserverDR]"
    }

    #if ( ( update_cifs_usergroup -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR) -ne $True ) {
    #    Write-LogError "ERROR: update_cifs_usergroup failed"
	#	clean_and_exit 1
    #}
  	if ( ( $ret=svmdr_db_switch_datafiles -myController $NcPrimaryCtrl -myVserver $Vserver ) -eq $false ) {
        	Write-LogError "ERROR: Failed to switch SVMTOOL_DB datafiles" 
        	clean_and_exit 1
  	}
	if ( ( $ret=save_vol_options_to_voldb -myController $NcPrimaryCtrl -myVserver $Vserver ) -ne $True ) {
		Write-LogError "ERROR: save_vol_options_to_voldb failed"
		clean_and_exit 1
	}
	if ( $AllowQuotaDR -eq "True" ) {
		Write-Log "[$VserverDR] Save quota policy rules to SVMTOOL_DB [$SVMTOOL_DB]" 
		if ( ( $ret=save_quota_rules_to_quotadb -myPrimaryController $NcPrimaryCtrl -myPrimaryVserver $Vserver -mySecondaryController $NcSecondaryCtrl -mySecondaryVserver $VserverDR ) -ne $True ) {
 			Write-LogError "ERROR: save_quota_rules_to_quotadb failed"
 			clean_and_exit 1
		}
	}
	clean_and_exit 0
}

if ( $ActivateDR ) {
    $Run_Mode="ActivateDR"
	Write-LogOnly "SVMDR ActivateDR"
	# Connect to the Cluster
	if ( $ForceActivate -eq $True ) {
		Write-Log "Force Activate vserver $VserverDR"
	} 
    else 
    {
		$ANS=Read-Host "Do you want to disable the primary vserver [$Vserver] [$PRIMARY_CLUSTER] ? [y/n]"
		if ( $ANS -eq 'y' ) {
			$myCred=get_local_cDotcred ($PRIMARY_CLUSTER) 
			$tmp_str=$MyCred.UserName
			Write-LogDebug "Connect to cluster [$PRIMARY_CLUSTER] with login [$tmp_str]"
			Write-LogDebug "connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
			if ( ( $NcPrimaryCtrl =  connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
				Write-LogError "ERROR: Unable to Connect to NcController [$PRIMARY_CLUSTER]"
			} else {
				if ( ( $ret=disable_network_protocol_vserver_dr -myController $NcPrimaryCtrl -myVserver $Vserver ) -ne $True ) {
					Write-LogError "ERROR: Failed to desactivate all Network Services for $Vserver"
				}
			}
		}
	}

	$myCred=get_local_cDotcred ($SECONDARY_CLUSTER) 
	Write-LogDebug "connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcSecondaryCtrl =  connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$SECONDARY_CLUSTER]" 
        	clean_and_exit 1
	}

	if ( ( $ret=activate_vserver_dr -myController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR ) -ne $True ) {
		Write-LogError "ERROR: activate_vserver_dr failed"
		clean_and_exit 1
	}
	# if ( ( update_CIFS_server_dr -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR ) -ne $True ) {
        # Write-Warning "Some CIFS options has not been set on [$VserverDR]"
    # }
    # if ( ( update_cifs_usergroup -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR) -ne $True ) {
        # Write-LogError "ERROR: update_cifs_usergroup failed"
		# clean_and_exit 1
    # }
    # if ( ( create_update_localuser_dr -myPrimaryController $myPrimaryController -mySecondaryController $mySecondaryController -myPrimaryVserver $myPrimaryVserver -mySecondaryVserver $mySecondaryVserver) -ne $True ) { 
        # Write-LogError "ERROR: Failed to create all user"
        # $Return = $True 
    # }
	if ( ( $ret=set_vol_options_from_voldb -myController $NcSecondaryCtrl -myVserver $VserverDR ) -ne $True ) {
		Write-LogError "ERROR: set_vol_options_from_voldb failed"
	}
    #if ( ( $ret=set_shareacl_options_from_shareacldb -myController $NcSecondaryCtrl -myVserver $VserverDR ) -ne $True ) {
	#	Write-LogError "ERROR: set_shareacl_options_from_shareacldb"
	#}
	if ( $AllowQuotaDR -eq "True" ) {
		if ( ( $ret=create_quota_rules_from_quotadb -myController $NcSecondaryCtrl -myVserver $VserverDR  ) -ne $True ) {
			Write-LogError "ERROR: create_quota_rules_from_quotadb failed"
		}
	}
	clean_and_exit 0
}

if ( $CreateQuotaDR ) {
    $Run_Mode="CreateQuotaDR"
	$myCred=get_local_cDotcred ($SECONDARY_CLUSTER) 
	Write-LogDebug "connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcSecondaryCtrl =  connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$SECONDARY_CLUSTER]" 
        	clean_and_exit 1
	}

	if ( ( $ret=create_quota_rules_from_quotadb -myController $NcSecondaryCtrl -myVserver $VserverDR  ) -ne $True ) {
		Write-LogError "ERROR: create_quota_rules_from_quotadb failed"
		clean_and_exit 1
	}
	clean_and_exit 0
}

if ( $ReCreateQuota ) {
    $Run_Mode="ReCreateQuota"
	$myCred=get_local_cDotcred ($PRIMARY_CLUSTER) 
	Write-LogDebug "connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcPriamaryCtrl =  connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$PRIMARY_CLUSTER]" 
        	clean_and_exit 1
	}

	if ( ( $ret=create_quota_rules_from_quotadb -myController $NcPrimaryCtrl -myVserver $Vserver  ) -ne $True ) {
		Write-LogError "ERROR: create_quota_rules_from_quotadb failed"
		clean_and_exit 1
	}
	clean_and_exit 0
}

if ( $ReActivate ) {
    $Run_Mode="ReActivate"
	Write-LogOnly "SVMDR ReActivate"
	# Connect to the Cluster
	$myCred=get_local_cDotcred ($PRIMARY_CLUSTER) 
	$tmp_str=$MyCred.UserName
	Write-LogDebug "Connect to cluster [$PRIMARY_CLUSTER] with login [$tmp_str]"
	Write-LogDebug "connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcPrimaryCtrl =  connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$PRIMARY_CLUSTER]" 
		clean_and_exit 1
	}
	$myCred=get_local_cDotcred ($SECONDARY_CLUSTER) 
	Write-LogDebug "connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcSecondaryCtrl =  connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$SECONDARY_CLUSTER]" 
		clean_and_exit 1
	}
	if ( ( $ret=check_cluster_peer -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl ) -ne $True ) { 
		Write-LogError "ERROR: check_cluster_peer failed" 
		clean_and_exit 1
	}
	if ( ( $ret=disable_network_protocol_vserver_dr -myController $NcSecondaryCtrl -myVserver $VserverDR ) -ne $True ) { 
		Write-LogError "ERROR: disable_network_protocol_vserver_dr failed" 
		clean_and_exit 1
	}
	if ( ( $ret=activate_vserver_dr -myController $NcPrimaryCtrl -myPrimaryVserver $VserverDR -mySecondaryVserver $Vserver ) -ne  $True ) {
		Write-LogError "ERROR: activate_vserver_dr failed" 
		clean_and_exit 1
	}
	if ( ( $ret=resync_vserver_dr -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR ) -ne  $True ) { 
		Write-LogError "ERROR: resync_vserver_dr failed" 
		clean_and_exit 1
	}

	if ( ( $ret=check_snapmirror_broken_dr -myPrimaryController $NcSecondary -mySecondaryController $NcPrimaryCtrl -myPrimaryVserver $VserverDR -mySecondaryVserver $Vserver ) -ne $True ) { 
		Write-LogError "ERROR: Failed snapmirror relations bad status unable to clean" 
		clean_and_exit 1
	}

	if ( ( $ret=remove_snapmirror_dr -myPrimaryController $NcSecondaryCtrl -mySecondaryController $NcPrimaryCtrl -myPrimaryVserver $VserverDR -mySecondaryVserver $Vserver	 ) -ne $True ) { 
		Write-LogError "ERROR: remove_snapmirror_dr failed" 
		clean_and_exit 1
	}
	if ( ( $ret=set_vol_options_from_voldb -myController $NcPrimaryCtrl -myVserver $Vserver ) -ne $True ) {
		Write-LogError "ERROR: set_vol_options_from_voldb failed"
	}
    #if ( ( $ret=set_shareacl_options_from_shareacldb -myController $NcPrimaryCtrl -myVserver $Vserver ) -ne $True ) {
	#	Write-LogError "ERROR: set_shareacl_options_from_shareacldb"
	#}
	if ( $AllowQuotaDR -eq "True" ) {
		if ( ( $ret=create_quota_rules_from_quotadb -myController $NcPrimaryCtrl -myVserver $Vserver  ) -ne $True ) {
			Write-LogError "ERROR: create_quota_rules_from_quotadb failed"
		}
	}
	clean_and_exit 0
}

if ( $CleanReverse ) {
    $Run_Mode="CleanReverse"
	Write-LogOnly "SVMDR CleanReverse"
	# Connect to the Cluster
	$myCred=get_local_cDotcred ($PRIMARY_CLUSTER) 
	$tmp_str=$MyCred.UserName
	Write-LogDebug "Connect to cluster [$PRIMARY_CLUSTER] with login [$tmp_str]"
	Write-LogDebug "connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcPrimaryCtrl =  connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$PRIMARY_CLUSTER]" 
		clean_and_exit 1
	}
	$myCred=get_local_cDotcred ($SECONDARY_CLUSTER) 
	Write-LogDebug "connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcSecondaryCtrl =  connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$SECONDARY_CLUSTER]" 
		clean_and_exit 1
	}
	if ( ( $ret=check_snapmirror_broken_dr -myPrimaryController $NcSecondary -mySecondaryController $NcPrimaryCtrl -myPrimaryVserver $VserverDR -mySecondaryVserver $Vserver ) -ne $True ) { 
		Write-LogError "ERROR: Failed snapmirror relations bad status unable to clean" 
		clean_and_exit 1
	}
	if ( ( $ret=remove_snapmirror_dr -myPrimaryController $NcSecondaryCtrl -mySecondaryController $NcPrimaryCtrl -myPrimaryVserver $VserverDR -mySecondaryVserver $Vserver	 ) -ne $True ) { 
		Write-LogError "ERROR: remove_snapmirror_dr failed" 
		clean_and_exit 1
	}
	clean_and_exit 0
}

if ( $Resync ) {
    $Run_Mode="Resync"
	Write-LogOnly "SVMDR Resync"
	# Connect to the Cluster
	$myCred=get_local_cDotcred ($PRIMARY_CLUSTER) 
	$tmp_str=$MyCred.UserName
	$ANS = read-host "Do you want to erase data on vserver [$VserverDR] [$SECONDARY_CLUSTER] ? [y/n]"
	if ( $ANS -ne 'y' ) {
		clean_and_exit 0
	}
	Write-LogDebug "Connect to cluster [$PRIMARY_CLUSTER] with login [$tmp_str]"
	Write-LogDebug "connect_cluster $PRIMARY_CLUSTER -myCred $MyCred  -myTimeout $Timeout"
	if ( ( $NcPrimaryCtrl =  connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$PRIMARY_CLUSTER]" 
        	clean_and_exit 1
	}
	$myCred=get_local_cDotcred ($SECONDARY_CLUSTER) 
	Write-LogDebug "connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcSecondaryCtrl =  connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$SECONDARY_CLUSTER]" 
        	clean_and_exit 1
	}
	if ( ( $ret=resync_vserver_dr -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR ) -ne $True ) {
		Write-LogError "ERROR: Resync error"
		clean_and_exit 1
	}
	clean_and_exit 0 
}

if ( $ResyncReverse ) {
    $Run_Mode="ResyncReverse"
	Write-LogOnly "SVMDR ResyncReverse"
	# Connect to the Cluster
	$myCred=get_local_cDotcred ($PRIMARY_CLUSTER) 
	$tmp_str=$MyCred.UserName

	$ANS = read-host "Do you want to erase data on vserver [$Vserver] [$PRIMARY_CLUSTER] ? [y/n]"
	if ( $ANS -ne 'y' ) {
		clean_and_exit 0
	}

	Write-LogDebug "Connect to cluster [$PRIMARY_CLUSTER] with login [$tmp_str]"
	Write-LogDebug "connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcPrimaryCtrl =  connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$PRIMARY_CLUSTER]" 
        	clean_and_exit 1
	}
	$myCred=get_local_cDotcred ($SECONDARY_CLUSTER) 
	Write-LogDebug "connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcSecondaryCtrl =  connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$SECONDARY_CLUSTER]" 
        	clean_and_exit 1
	}
	if ( ( $ret=resync_reverse_vserver_dr -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR) -ne $True ) {
		Write-LogError "ERROR: Resync Reverse error"
		clean_and_exit 1
	}
	clean_and_exit 0 
}

if ( $UpdateReverse ) {
    $Run_Mode="UpdateReverse"
	Write-LogOnly "SVMDR UpdateReverse"
	# Connect to the Cluster
	$myCred=get_local_cDotcred ($PRIMARY_CLUSTER) 
	$tmp_str=$MyCred.UserName
	Write-LogDebug "Connect to cluster [$PRIMARY_CLUSTER] with login [$tmp_str]"
	Write-LogDebug "connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcPrimaryCtrl =  connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$PRIMARY_CLUSTER]" 
        	clean_and_exit 1
	}
	$myCred=get_local_cDotcred ($SECONDARY_CLUSTER) 
	Write-LogDebug "connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcSecondaryCtrl =  connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$SECONDARY_CLUSTER]" 
        	clean_and_exit 1
	}
	# if ( ( $ret=analyse_junction_path -myController $NcPrimaryCtrl -myVserver $Vserver) -ne $True ) {
    	# Write-LogError "ERROR: analyse_junction_path" 
		# clean_and_exit 1
	# }
	if ( ( $ret=check_cluster_peer -myPrimaryController $NcSecondaryCtrl -mySecondaryController $NcPrimaryCtrl ) -ne $True ) {
		Write-LogError "ERROR: check_cluster_peer" 
		clean_and_exit 1
	}
	if ( $LastSnapshot ) {
    		$UseLastSnapshot = $True
	} else {
    		$UseLastSnapshot = $False
	}
	if($DRfromDR.IsPresent){
		if ( ( $ret=update_vserver_dr -myDataAggr $DataAggr -UseLastSnapshot $UseLastSnapshot -myPrimaryController $NcSecondaryCtrl -mySecondaryController $NcPrimaryCtrl -myPrimaryVserver $VserverDR -mySecondaryVserver $Vserver -DDR $True) -ne  $True ) { 
			Write-LogError "ERROR: update_vserver_dr" 
			clean_and_exit 1 
		}
	}else{
		if ( ( $ret=update_vserver_dr -myDataAggr $DataAggr -UseLastSnapshot $UseLastSnapshot -myPrimaryController $NcSecondaryCtrl -mySecondaryController $NcPrimaryCtrl -myPrimaryVserver $VserverDR -mySecondaryVserver $Vserver -DDR $False) -ne  $True ) { 
			Write-LogError "ERROR: update_vserver_dr" 
			clean_and_exit 1 
		}
	}
	
    if ( ( $ret=update_CIFS_server_dr -myPrimaryController $NcSecondaryCtrl -mySecondaryController $NcPrimaryCtrl -myPrimaryVserver $VserverDR -mySecondaryVserver $Vserver ) -ne $True ) {
        Write-Warning "Some CIFS options has not been set on [$Vserver]"
    }
    #if ( ( update_cifs_usergroup -myPrimaryController $NcSecondaryCtrl -mySecondaryController $NcPrimaryCtrl -myPrimaryVserver $VserverDR -mySecondaryVserver $Vserver ) -ne $True ) {
    #    Write-LogError "ERROR: update_cifs_usergroup failed"
	#	clean_and_exit 1
    #}
  	if ( ( $ret=svmdr_db_switch_datafiles -myController $NcSecondaryCtrl -myVserver $VserverDR ) -eq $false ) {
        	Write-LogError "ERROR: Failed to switch SVMTOOL_DB datafiles" 
        	clean_and_exit 1
  	}
	if ( ( $ret=save_vol_options_to_voldb -myController $NcSecondaryCtrl -myVserver $VserverDR ) -ne $True ) {
		Write-LogError "ERROR: save_vol_options_to_voldb failed"
		clean_and_exit 1
	}
    if ( ( $ret=create_update_cron_dr -myPrimaryController $NcSecondaryCtrl -mySecondaryController $NcPrimaryCtrl ) -ne $True ) {
		Write-LogError "ERROR: create_update_cron_dr"
	}
	if ( ( $ret=create_update_snap_policy_dr -myPrimaryController $NcSecondaryCtrl -mySecondaryController $NcPrimaryCtrl -myPrimaryVserver $VserverDR -mySecondaryVserver $Vserver) -ne $True ) {
		Write-LogError "ERROR: create_update_snap_policy_dr"
	}
	if ( $AllowQuotaDR -eq "True" ) {
		Write-Log "[$VserverDR] Save quota policy rules to SVMTOOL_DB [$SVMTOOL_DB]" 
		if ( ( $ret=save_quota_rules_to_quotadb -myPrimaryController $NcSecondaryCtrl -myPrimaryVserver $VserverDR -mySecondaryController $NcPrimaryCtrl -myPrimaryVserver $Vserver ) -ne $True ) {
 			Write-LogError "ERROR: save_quota_rules_to_quotadb failed"
 			clean_and_exit 1
		}
	}
	<# if ( $MirrorSchedule ) {
		Write-LogDebug "Flag MirrorSchedule"
	} else {
		clean_and_exit 0
	} #>
	clean_and_exit 0
}

if ( $MirrorSchedule ) {
    $Run_Mode="MirrorSchedule"
    Write-LogOnly "SVMDR MirrorSchedule"
    # Connect to the Cluster
    $myCred=get_local_cDotcred ($PRIMARY_CLUSTER) 
    $tmp_str=$MyCred.UserName
    Write-LogDebug "Connect to cluster [$PRIMARY_CLUSTER] with login [$tmp_str]"
    Write-LogDebug "connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
    if ( ( $NcPrimaryCtrl =  connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
        Write-LogError "ERROR: Unable to Connect to NcController [$PRIMARY_CLUSTER]" 
        clean_and_exit 1
    }
    $myCred=get_local_cDotcred ($SECONDARY_CLUSTER) 
    Write-LogDebug "connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
    if ( ( $NcSecondaryCtrl =  connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
        Write-LogError "ERROR: Unable to Connect to NcController [$SECONDARY_CLUSTER]" 
        clean_and_exit 1
    }
    if ( ( $ret=set_snapmirror_schedule_dr -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $Vserver -mySecondaryVserver $VserverDR -mySchedule $MirrorSchedule ) -ne $True ) {
        Write-LogError "ERROR: set_snapmirror_schedule_dr error"
        clean_and_exit 1
    }
    clean_and_exit 0
}

if ( $MirrorScheduleReverse ) {
    $Run_Mode="MirrorScheduleReverse"
    Write-LogOnly "SVMDR MirrorScheduleReverse"
    # Connect to the Cluster
    $myCred=get_local_cDotcred ($SECONDARY_CLUSTER) 
    $tmp_str=$MyCred.UserName
    Write-LogDebug "Connect to cluster [$SECONDARY_CLUSTER] with login [$tmp_str]"
    Write-LogDebug "connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
    if ( ( $NcPrimaryCtrl =  connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
        Write-LogError "ERROR: Unable to Connect to NcController [$SECONDARY_CLUSTER]" 
        clean_and_exit 1
    }
    $myCred=get_local_cDotcred ($PRIMARY_CLUSTER) 
    Write-LogDebug "connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
    if ( ( $NcSecondaryCtrl =  connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
        Write-LogError "ERROR: Unable to Connect to NcController [$PRIMARY_CLUSTER]" 
        clean_and_exit 1
    }
    if ( ( $ret=set_snapmirror_schedule_dr -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl -myPrimaryVserver $VserverDR -mySecondaryVserver $Vserver -mySchedule $MirrorScheduleReverse ) -ne $True ) {
        Write-LogError "ERROR: set_snapmirror_schedule_dr error"
        clean_and_exit 1
    }
    clean_and_exit 0
}

if ( $InternalTest ) {
	Write-LogOnly "SVM InternalTest"
	# Connect to the Cluster
	$myCred=get_local_cDotcred ($PRIMARY_CLUSTER) 
	$tmp_str=$MyCred.UserName
	Write-LogDebug "Connect to cluster [$PRIMARY_CLUSTER] with login [$tmp_str]"
	Write-LogDebug "connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcPrimaryCtrl =  connect_cluster $PRIMARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$PRIMARY_CLUSTER]" 
        	clean_and_exit 1
	}
	$myCred=get_local_cDotcred ($SECONDARY_CLUSTER)
	Write-LogDebug "connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout"
	if ( ( $NcSecondaryCtrl =  connect_cluster $SECONDARY_CLUSTER -myCred $MyCred -myTimeout $Timeout ) -eq $False ) {
		Write-LogError "ERROR: Unable to Connect to NcController [$SECONDARY_CLUSTER]" 
        	clean_and_exit 1
	}
	if ( ( $ret=check_cluster_peer -myPrimaryController $NcPrimaryCtrl -mySecondaryController $NcSecondaryCtrl ) -ne $True ) {
		Write-LogError "ERROR: check_cluster_peer failed"
		clean_and_exit 1
	}
	# _ADD TEST
	# _ADD TEST
	clean_and_exit 0 
}

Write-LogError "ERROR: No options selected: Use Help Options for more information" 
clean_and_exit 1