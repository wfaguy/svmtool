# svmtool
### Powershell tools to manage NetApp Storage Virtual Machine (aka SVM)


This script use [NetApp PowerShell Toolkit](https://mysupport.netapp.com/tools/info/ECMLP2310788I.html?productID=61926)

It also require at least .Net Framework v3.5 and Windows Powershell at least v3.0.

*This script currently not working with Powershell Core*

Mains objectives of this script are:
- Create/Maintain/Manage SVM Disaster Relationship between NetApp MetroCluster for old version of **ONTAP** 8.3 to 9.X
- Migrate SVM with old **ONTAP** version (SVM Migrate is officially supported with **ONTAP** since 9.4)
- Backup and Restore all configuration (volumes, lif, cron, junction-path, etc...) to original or alternate cluster

For more information download [Manual](https://github.com/oliviermasson/svmtool/blob/master/SVMTOOL_Manual_v1.0.docx)

HTH
