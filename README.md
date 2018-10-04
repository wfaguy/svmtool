# svmtool
### Powershell tools to manage NetApp Storage Virtual Machine (aka SVM)


This script use [NetApp PowerShell Toolkit](https://mysupport.netapp.com/tools/info/ECMLP2310788I.html?productID=61926)

It also require at least .Net Framework v3.5 and Windows Powershell at least v3.0.

*This script currently not working with Powershell Core*

Mains objectives of this script are:
- Create/Maintain/Manage SVM Disaster Relationship between NetApp MetroCluster for old version of **ONTAP** 8.3 to 9.X
- Migrate SVM with old **ONTAP** version (SVM Migrate is officially supported with **ONTAP** since 9.4)
- Backup and Restore all configuration (volumes, lif, cron, junction-path, etc...) to original or alternate cluster
- Clone DR SVM which allows to test your DR SVM through a cloned version it, without interrupting SnapMirror relationships during the test timeframe

### DR & Migration Purpose
**All Supported Options**

Supported Protocols | SVMTOOL
--------------------|--------
Support NFS | Yes
Support CIFS | Yes
Support iSCSI | Yes
Support FCP | No

Supported Network Services | SVMTOOL
---------------------------|--------
DNS Client Setup | Yes
NIS Client Setup | Yes
LDAP Client Setup | Yes

Supported NAS Objects | SVMTOOL
---------------------|---------
Export Policy & Rules | Yes
CIFS Shares | Yes
CIFS ACL | Yes
CIFS HomeDir | Yes
CIFS NetBios Alias | Yes
Quota Replication* | Yes
Snapshot Policy* | Yes
QoS Policy Group | Yes
Vscan Policy | Yes
Fpolicy | Yes
CIFS Local User & Group | Yes
CIFS Symlink | No
Name Mapping | Yes
Local Unix User & Group | Yes
Vserver User & Role | Yes

(*)Require a Local SVMDB flat files database to replicate Quota and Snapshot-Policy

Supported SAN Objects | SVMTOOL
----------------------|--------
SAN iGroup* | Yes
SAN LUN* | Yes
SAN LUN Serial Number* | Yes
SAN LUN Mapping* | Yes

(*)Only for iSCSI protocol

Supported Options | SVMTOOL
------------------|--------
Create a new SVM DR relationship | Yes
Update DR SVM | Yes
Activate DR SVM | Yes
Remediation with Resync or Resync Reverse | Yes
Provisioning New Volumes during Update | Yes
Can be used to Failover | Yes
Can be use to test Failover | Yes
Use an MCC for source or destination or both | Yes
Two differents DR destination | Yes
DR inside the same cluster, between HA pair in different rooms | Yes
Use Version Flexible SnapMirror when necessary<br>(by example: build a DR from 9.X to 8.3.2) | Yes
Migrate an SVM and keep it identity<br>For CIFS, IP and Server Name will be the same,<br>so users will only have to reconnect just by refreshing explorer<br>or double-click on folder<br><span style="color:red">**MSID cannot be preserved if destination is on a MetroCluster**</span> | 
Select subset of sources volumes that will be replicated | Yes
Clone DR SVM<br>In order to test DR without interrupting SnapMirror relationships during the timeframe of the test | Yes

### BACKUP & RESTORE Purpose
In order to perform a restore operation a minimal config must exist on the destination Cluster:
- Node Setup done
- Cluster Setup done
- Data aggregates recreated
- Low Level Network configuration done : IFGRP, IPSPACE, SUBNET, BROADCAST-DOMAIN already created

### Documentation
For more information download [Manual](https://github.com/oliviermasson/svmtool/blob/master/SVMTOOL_Manual_v1.0.docx)

HTH
