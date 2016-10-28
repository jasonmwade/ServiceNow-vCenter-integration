#
# Create_VM.ps1 - written in 2015 by wadejm 
#
# How to run: This script should be called by a controller script, but could be run if the proper variables are passed in the correct order below.
# What is needed to run: Variables in the correct order with valid information
#                        vcenter credentials
#
# ChangeLog:
# Date     - Changer   What was changed
# 20151015 - wadejm    Initial Conception
#
#
#
# Pass varibles to this script in this order
#
# $FOLDER      : Folder to store tmp VMs
# $VCENTER     : vcenter server
# $DATASTORE   : datastore for tmp VMs
# $NETWORK     : Network to use
# $TEMPLATE    : Template to clone
# $VMhost      : Resource pool to put VMs
# $HN          : Hostname of the new system



param(
[Parameter(Mandatory=$true)]
[String]$FOLDER,
[String]$VCENTER,
[String]$DATASTORE,
[String]$NETWORK,
[String]$TEMPLATE,
[String]$VMhost,
[String]$HN
)

start-transcript -OutputDirectory "d:\scripts\log\"
Add-PSSnapin vm*


#New-VICredentialStoreItem -Host VCENTER -User "USERNAME" -Password "PASSWORD"




Connect-VIServer $VCENTER

write-host "Hostname    : $HN"
write-host "Folder      : $FOLDER"
write-host "Vcenter     : $VCENTER"
write-host "Datastore   : $DATASTORE"
write-host "NETWORK     : $NETWORK"
write-host "TEMPLATE    : $TEMPLATE"
write-host "VMhost      : $VMhost"

New-VM -vmhost $VMhost -name $HN -location $($FOLDER) -template $TEMPLATE -datastore $DATASTORE

Set-annotation -entity $HN -CustomAttribute "Contact" -Value "Open"
Set-Annotation -entity $HN -CustomAttribute "Build Date" -value $(Get-Date)

Get-VM $HN | Get-NetworkAdapter | Set-NetworkAdapter -PortGroup $NETWORK -Confirm:$false
New-HardDisk -VM $HN -CapacityGB 100 -StorageFormat thin 



Stop-Transcript
