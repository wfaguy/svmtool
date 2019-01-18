@echo off
set /a EXIT=0
echo "Execution started"
echo "RUN SVMTOOL UPATE"
powershell -NonInteractive -NoProfile -InputFormat none -Command "& 'C:\Users\masson\OneDrive - NetApp Inc\GitHub\svmtool\svmtool.ps1' -Instance COT3-AFF -Vserver PSLAB_DR -UpdateDR -DataAggr AGGR1_Node2 ; exit $LastExitCode"
set /a EXIT=%ERRORLEVEL%
echo Command complete.
goto end
:end
exit /b %EXIT%
