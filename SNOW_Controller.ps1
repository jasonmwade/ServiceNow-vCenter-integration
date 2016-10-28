#
#
#
# Script requires VMware PowerCLi plugin 
#
#
# Begin

# Log
start-transcript -OutputDirectory d:\scripts\log\

# Setup authentication
#
#Domain
$domain = "NAOXY"
$AD_username = "sysautsrvacct"
$AD_password = Get-Content "d:\scripts\crypt\$AD_username.crypt" | ConvertTo-SecureString
$AD_cred = New-Object System.Management.Automation.PSCredential ($AD_username, $AD_password)

#ServiceNow
$SNOW_username = "SNC_vCloud_SVC"
$SNOW_password = Get-Content "d:\scripts\crypt\$SNOW_username.crypt" | ConvertTo-SecureString
$SNOW_cred = New-Object System.Management.Automation.PSCredential ($SNOW_username, $SNOW_password)

#Linux
$Linux_username = "root"
$Linux_password = Get-Content "d:\scripts\crypt\$Linux_username.crypt" | ConvertTo-SecureString
$Linux_cred = New-Object System.Management.Automation.PSCredential ($Linux_username, $Linux_password)

$uri = "XXX-REDACTED-XXX"
# Pull everything
try {
    $srvreq = Invoke-RestMethod -Uri $uri -Method Get -Credential $SNOW_cred
}
catch {
    write-host "Error when connecting to $uri"
    write-host "Status code :" $_.Exception.Response.StatusCode.value__
    write-host "Error detail:" $_.exception.response.statusDescription
    exit
}

# Debug
#$srvreq.result

# Search for waiting items, get oldest

$request = $srvreq.result | Where-Object {$_.u_status -eq "Waiting"} | sort u_sys_created_on | select -first 1


# Set up variables 
$ID = $request.sys_id

# If ID is blank, assume there is no work.

if ($ID -eq $null) {
    write-host "No work found"
    exit
}

$status = $request.u_status
$CPU = $request.u_cpu
$MEM = $request.u_memory
$Environment = $request.u_environment.ToLower()
$location = $request.u_location.ToLower()
$OS = $request.u_os.ToLower()
$owner = $request.sys_created_by
$APP = $request.u_app_code.ToLower()
$description = $request.u_description
$request_uri = $request.u_request_item
$request_link_uri = $uri + "/" + $ID
$start_time = Get-Date
$Windows_TEMPLATE = "HO_Win2012_r2_v09"
$Linux_TEMPLATE = "HO_RHEL-6-Server_v01"


# Use TMP servers?
$DO_TMP = "no"

#
# SAMPLE VARIABLES
#$ticket_num=
#$CPU="4"
#$MEM="8"
#$Location = "HY".ToLower()
#$Environment="JIB".ToLower()
#$App="RDP".ToLower()
#$OS="Windows".ToLower()


write-host "Status           = $status"
write-host "location         = $location"
write-host "description      = $description"
write-host "sys_id           = $ID"

# Snow headers
$headers = @{
"Accept"="application/json"
"Content-type"="application/json"
}

# functions

function update_SNOW ($ID, $field, $setting)
{
    $SNOW_body = @{
        $field=$setting
        }
    $body = $SNOW_body | ConvertTo-Json

    try {
        Invoke-RestMethod -uri $request_link_uri -Method Put -Credential $SNOW_cred -headers $headers -Body $body
    }
    catch {
        write-host "Error when connecting to $request_link_uri"
        write-host "Status code :" $_.Exception.Response.StatusCode.value__
        write-host "Error detail:" $_.exception.response.statusDescription
        exit
    }
}



# Set SNOW timestamp and status

update_SNOW $ID u_result "Begin on $start_time"
update_SNOW $ID u_status "Processing"


# Validate variables and create hostname

write-host "Got location = $Location"
if ($Location.length -ne 2) {
    $setting = "Location is not set to 2 characters, Location = $Location"
    write-host $setting
    update_SNOW $ID u_result $setting
    update_SNOW $ID u_status Error
    exit
}

switch ($Location) {
    hy {write-host "Provisioning for $Location"}
    dy {write-host "Provisioning for $Location"}
    default {$setting = "Location is not a site configured for automated provisioning, Location = $location"
    write-host $setting
    update_SNOW $ID u_result $setting
    update_SNOW $ID u_status Error
    exit}
}




switch ($Location) {
    { ($_ -eq 'hy') -or ($_ -eq 'ho') -or ($_ -eq 'dt') -or ($_ -eq 'dy') } {$FL = "o"}
    { ($_ -eq 'mo') -or ($_ -eq 'dq') -or ($_ -eq 'bg') -or ($_ -eq 'au') } {$FL = "n"}
    default {write-host "First letter of hostname is not correct, check that the location exists and is set in the script, Location = $Location"
    update_SNOW $ID u_result "First letter of hostname is not correct, check that the location exists and is set in the script, Location = $Location"
    update_SNOW $ID u_status Error
    exit}
}

switch ($OS) {
   "windows 2012" { $OS_1 = "w" }
   "redhat linux" { $OS_1 = "l" }
   default {write-host "OS is not correct, check that the OS exists and is set in the script, OS = $OS"
   update_SNOW $ID u_result "OS is not correct, check that the OS exists and is set in the script, OS = $OS"
   update_SNOW $ID u_status Error
   exit}
}


If ($App.length -ne 3) {
    if ($Environment -eq "poc") {
        $App = "poc"
    } else {
        write-host "Application is not set or is not 3 characters"
        update_SNOW $ID u_result "Application is not set or is not 3 characters"
        update_SNOW $ID u_status Error
        exit
    }
}

#
# Setup VMware environment. These settings should be per site and per environment and describe where the final VMs will end up
#

switch ($Location) { 
    "hy" {
        write-host "Houston"
        $AD_OU = "XXX-REDACTED-XXX" + $APP.toupper()
        switch ($environment) {
            "jib" {
                write-host "JIB environment"
                $VCENTER = "XXX-REDACTED-XXX"
                $Deploy_Folder = "JIB"
                $datastore = {"15K SAS RAID"}
            }
            "poc" {
                write-host "POC environment"
                $VCENTER = "XXX-REDACTED-XXX"
                $Folder = "POC"
                $datastore = {"XXX-REDACTED-XXX"}
                # Set generic application name
                $App = "poc"
                $OSCS = "POC_$OS_1"
                $NETWORK = "XXX-REDACTED-XXX"
                $VMhost = "XXX-REDACTED-XXX"
                # Overwrite AD OU to force all POC systems in a certain place
                $AD_OU = "XXX-REDACTED-XXX
            }
            default {
                Write-Host "Unknown environment $environment, exiting"
                update_SNOW $ID u_result "Unknown environment $environment, exiting"
                update_SNOW $ID u_status Error
                exit
            }
        }
       
    }
    "dy"{
        Write-Host "Dallas"

    }
    default { 
        Write-Host "Unknown location $location, exiting"
        update_SNOW $ID u_result "Unknown location $location, exiting"
        update_SNOW $ID u_status Error
        exit
    }
}

$HN = ( $FL + $Location + $OS_1 + $App ).ToLower()

# Connect to AD and validate application OU
import-module ActiveDirectory

try {
    [ADSI]::Exists("LDAP://$AD_OU")
}
catch {
    write-host "ActiveDirectory OU for the application $APP was not found at $AD_OU"
    update_SNOW $ID u_result "ActiveDirectory OU for the application $APP was not found at $AD_OU"
    update_SNOW $ID u_status Error
    exit
}


# Search for next available hostname


$HN_Check = 0
while ( $HN_Check -eq 0 ) {
    $RAND = Get-Random -Minimum 0 -maximum 999


    $proposed_HN = $HN + $RAND + "-" + $Environment

    write-host "Proposed Hostname   : $proposed_HN"

# Check to make sure that HN_proposed isn't already used
    
    try {
        Get-ADComputer $proposed_HN -ErrorAction stop
        write-host "Computer already found, generating a new unique name"
    }    
    catch {
        if ( Test-connection $proposed_HN -count 1 -quiet ) {
            write-host "Computer not found in AD, but pinging, generating a new hostname"
        } else { 
            write-host "Computer not found in AD or by pinging, assuming proposed HN can be HN"
            $HN = $proposed_HN
            $HN_check = 1
       }
    }
}
write-host "Final hostname set to $HN"


# Get Static IP Address




# Build Windows or Linux system

if ($OS_1 -eq "w") {

    if ($DO_TMP -eq "yes") {
# Try to use TMP servers first
# Find oldest usable TMP server in AD to use
        $TMPServer = ( $FL + $Location + $OS_1 + "tmp" )
        $TMPServer_array = Get-ADComputer -filter "Name -like '$TMPServer*'" -Properties * | sort-object -Property whenCreated
        foreach($tsh in $TMPServer_array.name) {
            write-host "Testing TMP host = $tsh"
            if(!(Test-Connection -ComputerName $tsh -Count 1 -ErrorAction 0 -Quiet)) {
                write-host "Computer named $tsh does not appear to be up, skipping"
                Continue
            } else { 
# Verify TMPServer and reconfigure
                write-host "Computer named $tsh appears to be working, connecting to it with PowerShell"       
# Try to connect using Powershell. If it errors, break out of while loop to try another system.
                try {
                    $tsh_session = New-PSSession -ComputerName $tsh -ErrorAction Stop
                }
                catch {
                    write-host "Could not connect to $tsh using PowerShell, skipping"
                    continue
                }
# Make sure the hostname of the remote system is equal to the tmp system name.
                if((Invoke-Command -Session $tsh_session -ScriptBlock {hostname}) -eq $tsh) { 
                    write-host "Powershell connection to $tsh appears to be working" 
                } else { 
                    write-host "Powershell connection to $tsh failed, switching to direct build"
                    $tsh = ""
                }
                Remove-PSSession $tsh_session
                Break
            }
        }
    }
    if($tsh -eq $null -or $DO_TMP -ne "yes") {
# If a working TMP server is not found, build server directly
        write-host "Could not find working tmp server or DO_TMP is set to no, building directly"
        write-host "If you got here, everything worked and we will build from scratch, $HN"

        $ARGUMENTS = $FOLDER, $VCENTER, $DATASTORE, $NETWORK, $WINDOWS_TEMPLATE, $VMhost
        write-host "Passing these arguments " + $arguments $HN
# DO the VM work
        try {
            Invoke-Expression "d:\scripts\CreateVM.ps1 $ARGUMENTS $HN"
            Add-PSSnapin vm*
            Connect-VIServer $VCENTER
            Set-annotation -entity $HN -CustomAttribute "Contact" -Value $OWNER
            Set-Annotation -entity $HN -CustomAttribute "Build Date" -value $(Get-Date)
            set-vm -VM $HN -MemoryGB $MEM -NumCpu $CPU -OSCustomizationSpec $OSCS -Confirm:$false
            Start-VM $HN
            Disconnect-VIServer $VCENTER -confirm:$false
            Write-Host "Built, $HN"
            update_SNOW $ID u_result "$HN built"
            update_SNOW $ID u_host_name "$HN"
            update_SNOW $ID u_status Complete
        } catch {
            write-host "Build failed for server $HN"
            update_SNOW $ID u_result "Build failed for server $HN, Check logs on script server"
            update_SNOW $ID u_status Error
            exit
        }
    

    } else {
        write-host "Oldest WORKING tmp server selected is $tsh"
# Add VM snapin and connect
        Add-PSSnapin vm*
        Connect-VIServer $VCENTER
        Write-Host "Reconfiguring $tsh into $HN with $CPU cores and $MEM GB of memory"
# Do VM work
#Move-VM -VM $VM -Destination $Deploy_Folder -Datastore $datastore 
#Set-VM -VM $tsh -Name $HN -MemoryGB $MEM -NumCpu $CPU
        Disconnect-VIServer $VCENTER -confirm:$false
# Move VM
    }
} else {
    Write-Host "Building a Linux system"
    $ARGUMENTS = $FOLDER, $VCENTER, $DATASTORE, $NETWORK, $Linux_TEMPLATE, $VMhost
    try {

        Invoke-Expression "d:\scripts\CreateVM.ps1 $ARGUMENTS $HN"
        Add-PSSnapin vm*
        Connect-VIServer $VCENTER
        Set-annotation -entity $HN -CustomAttribute "Contact" -Value $OWNER
        Set-Annotation -entity $HN -CustomAttribute "Build Date" -value $(Get-Date)
        set-vm -VM $HN -MemoryGB $MEM -NumCpu $CPU -OSCustomizationSpec $OSCS -Confirm:$false
        Start-VM $HN
        write-host "Waiting for VMTools to start"
        Wait-Tools -VM $HN -TimeoutSeconds 180

#Download and run configuration script

        Invoke-VMScript -vm $HN -ScriptType Bash -ScriptText "( cd /tmp ; wget XXX-REDACTED-XXX & )" -GuestCredential $Linux_cred

        Disconnect-VIServer $VCENTER -confirm:$false

    } catch {
        write-host "Build failed for server $HN"
        update_SNOW $ID u_result "Build failed for server $HN, Check logs on script server"
        update_SNOW $ID u_status Error
        exit
    }
}

Write-Host "Built, $HN"
update_SNOW $ID u_result "$HN built"
update_SNOW $ID u_host_name "$HN"
update_SNOW $ID u_status Complete





Stop-Transcript
