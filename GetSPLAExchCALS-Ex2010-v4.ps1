Param (
    [Parameter(Mandatory = $false)]
    [ValidateNotNullorEmpty()]
    [string[]]$Group,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullorEmpty()]
    [string[]]$FTPUser,
    
    [Parameter(Mandatory = $false)]
    [ValidateNotNullorEmpty()]
    [string[]]$FTPPWD,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullorEmpty()]
    [string[]]$FTPUrl
)
    
add-pssnapin Microsoft.Exchange.Management.Powershell.E2010


$path = "C:\SPLA\Exports"

if (Test-Path $path){ write-host "The Source folder already exists." } else {New-Item -Path $path -ItemType Directory}




# Trap block 
trap {  
    write-host "An error has occurred running the script:"  
    write-host $_ 
 
    Set-ADServerSettings -ViewEntireForest $OriginalADServerSetting.ViewEntireForest -RecipientViewRoot $OriginalADServerSetting.RecipientViewRoot 
 
    exit 
}  
 
# Function that returns true if the incoming argument is a help request 
function IsHelpRequest 
{ 
    param($argument) 
    return ($argument -eq "-?" -or $argument -eq "-help"); 
} 
 
# Function that displays the help related to this script following 
# the same format provided by get-help or <cmdletcall> -? 
function Usage 
{ 
@" 
 
NAME: 
`tReportExchangeCALs.ps1 
 
SYNOPSIS: 
`tReports Exchange 2010 client access licenses (CALs) of this organization in Enterprise or Standard categories. 
 
SYNTAX: 
`tReportExchangeCALs.ps1 
 
PARAMETERS: 
 
USAGE: 
`t.\ReportExchangeCALs.ps1 
 
"@ 
} 
 
# Function that resets AdminSessionADSettings.DefaultScope to original value and exits the script 
function Exit-Script 
{ 
    Set-ADServerSettings -ViewEntireForest $OriginalADServerSetting.ViewEntireForest -RecipientViewRoot $OriginalADServerSetting.RecipientViewRoot 
 
    exit 
} 
 
######################## 
## Script starts here ## 
######################## 
 
$OriginalADServerSetting = Get-ADServerSettings 
 
# Check for Usage Statement Request 
$args | foreach { if (IsHelpRequest $_) { Usage; Exit-Script; } } 
 
# Introduction message 
write-host "Report Exchange 2010 client access licenses (CALs) in use in the organization"  
write-host "It will take some time if there are a large amount of users......" 
write-host "" 
 
Set-ADServerSettings -ViewEntireForest $true 
 
$TotalMailboxes = 0 
$TotalEnterpriseCALs = 0 
$UMUserCount = 0 
$ManagedCustomFolderUserCount = 0 
$AdvancedActiveSyncUserCount = 0 
$ArchiveUserCount = 0 
$RetentionPolicyUserCount = 0 
$AdvancedAntispamUserCount = 0 
$AdvancedAntispamEnabled = $False 
$OrgWideJournalingEnabled = $False 
$AllMailboxIDs = @{} 
$EnterpriseCALMailboxIDs = @{} 
$JournalingUserCount = 0 
$JournalingMailboxIDs = @{} 
$JournalingDGMailboxMemberIDs = @{} 
$DiscoveryConsoleRoles = @{} 
$DiscoveryConsoleRoleAssignees = @() 
$DiscoveryConsoleRoleAssignments = @() 
$SearchableMaiboxIDs = @{} 
$TotalStandardCALs = 0 
$VisitedGroups = @{} 
$DGStack = new-object System.Collections.Stack 
$UserMailboxFilter = "(RecipientTypeDetails -eq 'UserMailbox') -or (RecipientTypeDetails -eq 'SharedMailbox') -or (RecipientTypeDetails -eq 'LinkedMailbox')" 

#$UserMailboxFilter = "(OrganizationalUnit -eq 'acp.local/acp')" 

# Bool variable for outputing progress information running this script. 
$EnableProgressOutput = $True 
if ($EnableProgressOutput -eq $True) { 
    write-host "Progress:" 
} 
 
################ 
## Debug code ## 
################ 
 
# Bool variable for output hash table information for debugging purpose. 
$EnableOutputCounts = $False 
 
function Output-Counts 
{ 
    if ($EnableOutputCounts -eq $False) { 
        return 
    } 
 
    write-host "Hash Table Name                                 Count" 
    write-host "---------------                                 -----" 
    write-host "AllMailboxIDs:                                 " $AllMailboxIDs.Count 
    write-host "EnterpriseCALMailboxIDs:                       " $EnterpriseCALMailboxIDs.Count 
    write-host "JournalingMailboxIDs:                          " $JournalingMailboxIDs.Count 
    write-host "JournalingDGMailboxMemberIDs:                  " $JournalingDGMailboxMemberIDs.Count 
    write-host "VisitedGroups:                                 " $VisitedGroups.Count 
    write-host "" 
    write-host "" 
} 
 
function Merge-Hashtables 
{ 
    $Table1 = $args[0] 
    $Table2 = $args[1] 
    $Result = @{} 
     
    if ($null -ne $Table1) 
    { 
        $Result += $Table1 
    } 
 
    if ($null -ne $Table2) 
    { 
        foreach ($entry in $Table2.GetEnumerator()) 
        { 
            $Result[$entry.Key] = $entry.Value 
        } 
    } 
 
    $Result 
} 
 
# Function that outputs Exchange CALs in the organization 
function Output-Report { 
    write-host "=========================" 
    write-host "Exchange CAL Usage Report" 
    write-host "=========================" 
    write-host "" 
    write-host "Total Users:                                    $TotalMailboxes" 
    write-host "Total Standard CALs:                            $TotalStandardCALs" 
    write-host "Total Enterprise CALs:                          $TotalEnterpriseCALs" 
} 
 
################# 
## Total Users ## 
################# 
 
# Note!!!  
# Only user, shared and linked mailboxes are counted.  
# Resource mailboxes and legacy mailboxes are NOT counted. 
 
Get-Recipient -ResultSize 'Unlimited' -Filter $UserMailboxFilter | foreach { 
    $Mailbox = $_ 
    if ($Mailbox.ExchangeVersion.ExchangeBuild.Major -eq 14) { 
        $AllMailboxIDs[$Mailbox.Identity] = $null 
        $Script:TotalMailboxes++ 
    } 
} 
 
if ($TotalMailboxes -eq 0) { 
    # No mailboxes in the org. Just output the report and exit 
    Output-Report 
     
    Exit-Script 
} 
 
######################### 
## Total Standard CALs ## 
######################### 
 
# All users are counted as Standard CALs 
$TotalStandardCALs = $TotalMailboxes 
 
## Progress output ...... 
if ($EnableProgressOutput -eq $True) { 
    write-host "Total Standard CALs calculated:                 $TotalStandardCALs" 
} 
 
############################# 
## Per-org Enterprise CALs ## 
############################# 
 
## Progress output ...... 
if ($EnableProgressOutput -eq $True) { 
    write-host "Advanced Anti-spam Enabled:                     False" 
} 
 
# If Info Leakage Protection is enabled on any transport rule, all mailboxes in the org are counted as Enterprise CALs 
Get-TransportRule | foreach { 
    if ($_.ApplyRightsProtectionTemplate -ne $null) { 
        $Script:TotalEnterpriseCALs = $Script:TotalMailboxes 
         
        ## Progress output ...... 
        if ($EnableProgressOutput -eq $True) { 
            write-host "Info Leakage Protection Enabled:                True" 
            write-host "Total Enterprise CALs calculated:               $TotalEnterpriseCALs" 
 
            write-host "" 
        } 
 
        # All mailboxes are counted as Enterprise CALs, report and exit. 
        Output-Counts 
         
        Output-Report 
 
        Exit-Script 
    } 
} 
 
## Progress output ...... 
if ($EnableProgressOutput -eq $True) { 
    write-host "Info Leakage Protection Enabled:                False" 
} 
 
############################## 
## Per-user Enterprise CALs ## 
############################## 
 
# 
# Calculate Enterprise CAL users using UM, MRM Managed Custom Folder, and advanced ActiveSync policy settings 
# 
$AllMailboxIDs.Keys | foreach {   
    $Mailbox = Get-Mailbox $_ 
     
     # UM usage classifies the user as an Enterprise CAL    
    if ($Mailbox.UMEnabled) 
    { 
        $Script:UMUserCount++ 
        $Script:EnterpriseCALMailboxIDs[$Mailbox.Identity] = $null 
    } 
     
    # Archive Mailbox classifies the user as an Enterprise CAL 
    if ($Mailbox.ArchiveGuid -ne [System.Guid]::Empty) { 
        $Script:ArchiveUserCount++ 
        $Script:EnterpriseCALMailboxIDs[$Mailbox.Identity] = $null 
    } 
     
    # Retention Policy classifies the user as an Enterprise CAL 
    if ($Mailbox.RetentionPolicy -ne $null) { 
        $Script:RetentionPolicyUserCount++ 
        $Script:EnterpriseCALMailboxIDs[$Mailbox.Identity] = $null 
    } 
 
    # MRM Managed Custom Folder usage classifies the user as an Enterprise CAL 
    if ($Mailbox.ManagedFolderMailboxPolicy -ne $null) 
    {      
        $ManagedFolderLinks = (Get-ManagedFolderMailboxPolicy $Mailbox.ManagedFolderMailboxPolicy).ManagedFolderLinks 
        foreach ($FolderLink in $ManagedFolderLinks) { 
            $ManagedFolder = Get-ManagedFolder $FolderLink 
 
            # Managed Custom Folders require an Enterprise CAL 
            If ($ManagedFolder.FolderType -eq "ManagedCustomFolder")  
            { 
                $Script:ManagedCustomFolderUserCount++ 
                $Script:EnterpriseCALMailboxIDs[$Mailbox.Identity] = $null 
 
                break 
            } 
        } 
    } 
 
    # Advanced ActiveSync policies classify the user as an Enterprise CAL 
    $CASMailbox = Get-CASMailbox $_ 
    if ($CASMailbox.ActiveSyncEnabled -and ($CASMailbox.ActiveSyncMailboxPolicy -ne $null)) 
    { 
        $ASPolicy = Get-ActiveSyncMailboxPolicy $CASMailbox.ActiveSyncMailboxPolicy 
 
    if (($ASPolicy.AllowDesktopSync -eq $False) -or  
            ($ASPolicy.AllowStorageCard -eq $False) -or 
            ($ASPolicy.AllowCamera -eq $False) -or 
            ($ASPolicy.AllowTextMessaging -eq $False) -or 
            ($ASPolicy.AllowWiFi -eq $False) -or 
            ($ASPolicy.AllowBluetooth -ne "Allow") -or 
            ($ASPolicy.AllowIrDA -eq $False) -or 
            ($ASPolicy.AllowInternetSharing -eq $False) -or 
            ($ASPolicy.AllowRemoteDesktop -eq $False) -or 
            ($ASPolicy.AllowPOPIMAPEmail -eq $False) -or 
            ($ASPolicy.AllowConsumerEmail -eq $False) -or 
            ($ASPolicy.AllowBrowser -eq $False) -or 
            ($ASPolicy.AllowUnsignedApplications -eq $False) -or 
            ($ASPolicy.AllowUnsignedInstallationPackages -eq $False) -or 
            ($ASPolicy.ApprovedApplicationList -ne $null) -or 
            ($ASPolicy.UnapprovedInROMApplicationList -ne $null)) { 
 
            $Script:AdvancedActiveSyncUserCount++ 
            $Script:EnterpriseCALMailboxIDs[$Mailbox.Identity] = $null 
        } 
    } 
     
} 
 
## Progress output ...... 
if ($EnableProgressOutput -eq $True) { 
    write-host "Unified Messaging Users calculated:             $UMUserCount" 
    write-host "Managed Custom Folder Users calculated:         $ManagedCustomFolderUserCount" 
    write-host "Advanced ActiveSync Policy Users calculated:    $AdvancedActiveSyncUserCount" 
    write-host "Archived Mailbox Users calculated:              $ArchiveUserCount" 
    write-host "Retention Policy Users calculated:              $RetentionPolicyUserCount" 
} 
 
 
# 
# Calculate Enterprise CAL for e-Discovery 
# 
 
# Get all e-discovery management roles which can perform e-discovery tasks 
("*-mailboxsearch", "search-mailbox") | %{Get-ManagementRole -cmdlet $_} | Sort-Object -Unique | %{$Script:DiscoveryConsoleRoles[$_.Identity] = $_} 
 
# Get all e-discovery management role assigment on users 
foreach ($Role in $Script:DiscoveryConsoleRoles.Values) { 
    foreach ($RoleAssignment in @($Role | Get-ManagementRoleAssignment -Delegating $false -Enabled $true)) { 
            $EffectiveAssignees=@() 
            foreach ($EffectiveUserRoleAssignment in (Get-ManagementRoleAssignment -Identity $RoleAssignment.Identity -GetEffectiveUsers)) { 
                $EffectiveAssignees+=$EffectiveUserRoleAssignment.User 
            } 
            foreach ($EffectiveAssignee in $EffectiveAssignees) { 
                $Assignee = Get-User $EffectiveAssignee -ErrorAction SilentlyContinue 
                $error.Clear() 
                if ($Assignee -ne $null) { 
                    $Script:DiscoveryConsoleRoleAssignees += $Assignee 
                    $Script:DiscoveryConsoleRoleAssignments += $RoleAssignment 
                 } 
            } 
    } 
} 
 
# Get excluded mailboxes 
$ExcludedMailboxes = @{} 
 
$ManagementScopes = @{} 
Get-ManagementScope -Exclusive:$true | where {$_.ScopeRestrictionType -eq "RecipientScope"} | foreach { 
    $ManagementScopes[$_.Identity] = $_ 
    [Microsoft.Exchange.Management.Tasks.GetManagementScope]::StampQueryFilterOnManagementScope($_) 
} 
foreach ($ManagementScope in $ManagementScopes.Values) { 
    $Filter = $UserMailboxFilter 
    if (-not([System.String]::IsNullOrEmpty($ManagementScope.RecipientFilter))) { 
        $Filter = "(" + $ManagementScope.RecipientFilter + ") -and (" + $Filter + ")" 
    } 
    Get-Recipient -ResultSize 'Unlimited'-OrganizationalUnit $ManagementScope.RecipientRoot -Filter $Filter | foreach { 
        if ($_.ExchangeVersion.ExchangeBuild.Major -eq 14) { 
            $ExcludedMailboxes[$_.Identity] = $true 
        } 
    } 
} 
 
# Get all searched mailboxes in e-discovery 
for ($i=0; $i -lt $Script:DiscoveryConsoleRoleAssignments.Count; $i++) { 
    $RoleAssignment=$Script:DiscoveryConsoleRoleAssignments[$i] 
    $ManagementScope = $null 
    if (($RoleAssignment.CustomRecipientWriteScope -ne $null) -and ($RoleAssignment.RecipientWriteScope -eq "CustomRecipientScope" -or $RoleAssignment.RecipientWriteScope -eq "ExclusiveRecipientScope")) { 
        $ManagementScope = $ManagementScopes[$RoleAssignment.CustomRecipientWriteScope] 
        if ($ManagementScope -eq $null) { 
            $ManagementScope = Get-ManagementScope $RoleAssignment.CustomRecipientWriteScope 
            [Microsoft.Exchange.Management.Tasks.GetManagementScope]::StampQueryFilterOnManagementScope($ManagementScope) 
            $ManagementScopes[$RoleAssignment.CustomRecipientWriteScope] = $ManagementScope 
        } 
    } 
    $ADScope = [Microsoft.Exchange.Management.RbacTasks.GetManagementRoleAssignment]::GetRecipientWriteADScope( 
        $RoleAssignment,  
        $Script:DiscoveryConsoleRoleAssignees[$i],  
        $ManagementScope) 
    if ($ADScope -ne $null) { 
        $Filter = $UserMailboxFilter 
        $ScopeFilter = $ADScope.GetFilterString() 
        if (-not([System.String]::IsNullOrEmpty($ScopeFilter))) { 
            $Filter = "(" + $ScopeFilter + ") -and (" + $Filter + ")" 
        } 
        Get-Recipient -ResultSize 'Unlimited'-OrganizationalUnit $ADScope.Root -Filter $Filter | foreach { 
            if ($_.ExchangeVersion.ExchangeBuild.Major -eq 14) { 
                if ($RoleAssignment.RecipientWriteScope -eq [Microsoft.Exchange.Data.Directory.SystemConfiguration.RecipientWriteScopeType]::ExclusiveRecipientScope) { 
                    $Script:EnterpriseCALMailboxIDs[$_.Identity] = $null 
                    $SearchableMaiboxIDs[$_.Identity] = $null 
                } 
                else { 
                    if (-not($ExcludedMailboxes[$_.Identity] -eq $true)) { 
                        $Script:EnterpriseCALMailboxIDs[$_.Identity] = $null 
                        $SearchableMaiboxIDs[$_.Identity] = $null 
                    } 
                } 
            } 
        } 
    } 
} 
 
## Progress output ...... 
if ($EnableProgressOutput -eq $True) { 
    write-host "Searchable Users calculated:                   "$SearchableMaiboxIDs.Count 
} 
 
# 
# Calculate Enterprise CAL users using Journaling 
# 
 
# Help function for function Get-JournalingGroupMailboxMember to traverse members of a DG/DDG/group  
function Traverse-GroupMember 
{ 
    $GroupMember = $args[0] 
     
    if( $GroupMember -eq $null ) 
    { 
        return 
    } 
 
    # Note!!!  
    # Only user, shared and linked mailboxes are counted.  
    # Resource mailboxes and legacy mailboxes are NOT counted. 
    if ( ($GroupMember.RecipientTypeDetails -eq 'UserMailbox') -or 
          ($GroupMember.RecipientTypeDetails -eq 'SharedMailbox') -or 
          ($GroupMember.RecipientTypeDetails -eq 'LinkedMailbox') ) { 
        # Journal one mailbox 
        if ($GroupMember.ExchangeVersion.ExchangeBuild.Major -eq 14) { 
            $Script:JournalingMailboxIDs[$GroupMember.Identity] = $null 
        } 
    } elseif ( ($GroupMember.RecipientType -eq "Group") -or ($GroupMember.RecipientType -like "Dynamic*Group") -or ($GroupMember.RecipientType -like "Mail*Group") ) { 
        # Push this DG/DDG/group into the stack. 
        $DGStack.Push(@($GroupMember.Identity, $GroupMember.RecipientType)) 
    } 
} 
 
# Function that returns all mailbox members including duplicates recursively from a DG/DDG 
function Get-JournalingGroupMailboxMember 
{ 
    # Skip this DG/DDG if it was already enumerated. 
    if ( $Script:VisitedGroups.ContainsKey($args[0]) ) { 
        return 
    } 
     
    $DGStack.Push(@($args[0],$args[1])) 
    while ( $DGStack.Count -ne 0 ) { 
        $StackElement = $DGStack.Pop() 
         
        $GroupIdentity = $StackElement[0] 
        $GroupRecipientType = $StackElement[1] 
 
        if ( $Script:VisitedGroups.ContainsKey($GroupIdentity) ) { 
            # Skip this this DG/DDG if it was already enumerated. 
            continue 
        } 
         
        # Check the members of the current DG/DDG/group in the stack. 
 
        if ( ($GroupRecipientType -like "Mail*Group") -or ($GroupRecipientType -eq "Group" ) ) { 
            $varGroup = Get-Group $GroupIdentity -ErrorAction SilentlyContinue 
            if ( $varGroup -eq $Null ) 
            { 
                $errorMessage = "Invalid group/distribution group/dynamic distribution group: " + $GroupIdentity 
                write-error $errorMessage 
                return 
            } 
             
            $varGroup.members | foreach {     
                # Count users and groups which could be mailboxes. 
                $varGroupMember = Get-User $_ -ErrorAction SilentlyContinue  
                if ( $varGroupMember -eq $Null ) { 
                    $varGroupMember = Get-Group $_ -ErrorAction SilentlyContinue                   
                } 
 
 
                if ( $varGroupMember -ne $Null ) { 
                    Traverse-GroupMember $varGroupMember 
                } 
            } 
        } else { 
            # The current stack element is a DDG. 
            $varGroup = Get-DynamicDistributionGroup $GroupIdentity -ErrorAction SilentlyContinue 
            if ( $varGroup -eq $Null ) 
            { 
                $errorMessage = "Invalid group/distribution group/dynamic distribution group: " + $GroupIdentity 
                write-error $errorMessage 
                return 
            } 
 
            Get-Recipient -RecipientPreviewFilter $varGroup.LdapRecipientFilter -OrganizationalUnit $varGroup.RecipientContainer -ResultSize 'Unlimited' | foreach { 
                Traverse-GroupMember $_ 
            } 
        }  
 
        # Mark this DG/DDG as visited as it's enumerated. 
        $Script:VisitedGroups[$GroupIdentity] = $null 
    }     
} 
 
# Check all journaling mailboxes for all journaling rules. 
foreach ($JournalRule in Get-JournalRule){ 
    # There are journal rules in the org. 
 
    if ( $JournalRule.Recipient -eq $Null ) { 
        # One journaling rule journals the whole org (all mailboxes) 
        $OrgWideJournalingEnabled = $True 
        $Script:JournalingUserCount = $Script:TotalMailboxes 
        $Script:TotalEnterpriseCALs = $Script:TotalMailboxes 
 
        break 
    } else { 
        $JournalRecipient = Get-Recipient $JournalRule.Recipient.Local -ErrorAction SilentlyContinue 
 
        if ( $JournalRecipient -ne $Null ) { 
            # Note!!! 
            # Only user, shared and linked mailboxes are counted.  
            # Resource mailboxes and legacy mailboxes are NOT counted. 
            if (($JournalRecipient.RecipientTypeDetails -eq 'UserMailbox') -or 
                ($JournalRecipient.RecipientTypeDetails -eq 'SharedMailbox') -or 
                ($JournalRecipient.RecipientTypeDetails -eq 'LinkedMailbox') ) { 
 
                # Journal a mailbox 
                if ($JournalRecipient.ExchangeVersion.ExchangeBuild.Major -eq 14) { 
                    $Script:JournalingMailboxIDs[$JournalRecipient.Identity] = $null 
                } 
            } elseif ( ($JournalRecipient.RecipientType -like "Mail*Group") -or ($JournalRecipient.RecipientType -like "Dynamic*Group") ) { 
                # Journal a DG or DDG. 
                # Get all mailbox members for the current journal DG/DDG and add to $JournalingDGMailboxMemberIDs 
                Get-JournalingGroupMailboxMember $JournalRecipient.Identity $JournalRecipient.RecipientType 
                Output-Counts 
            } 
        } 
    } 
} 
 
if ( !$OrgWideJournalingEnabled ) { 
    # No journaling rules journaling the entire org. 
    # Get all journaling mailboxes 
    $Script:JournalingMailboxIDs = Merge-Hashtables $Script:JournalingDGMailboxMemberIDs $Script:JournalingMailboxIDs 
    $Script:JournalingUserCount = $Script:JournalingMailboxIDs.Count 
} 
 
## Progress output ...... 
if ($EnableProgressOutput -eq $True) { 
    write-host "Journaling Users calculated:                    $JournalingUserCount" 
} 
 
 
# 
# Calculate Enterprise CALs 
# 
if ( !$OrgWideJournalingEnabled ) { 
    # Calculate Enterprise CALs as not all mailboxes are Enterprise CALs 
    $Script:EnterpriseCALMailboxIDs = Merge-Hashtables $Script:JournalingMailboxIDs $Script:EnterpriseCALMailboxIDs 
    $Script:TotalEnterpriseCALs = $Script:EnterpriseCALMailboxIDs.Count 
} 
 
## Progress output ...... 
if ($EnableProgressOutput -eq $True) { 
    write-host "Total Enterprise CALs calculated:               $TotalEnterpriseCALs" 
 
    write-host "" 
} 
 
################### 
## Output Report ## 
################### 
 
Output-Counts 
 
Output-Report 
 
Set-ADServerSettings -ViewEntireForest $OriginalADServerSetting.ViewEntireForest -RecipientViewRoot $OriginalADServerSetting.RecipientViewRoot 

$currdate = Get-Date -format "yyyyMMdd"


$STDExportfile = "$path\$SvrName-STD_Exch-SALS-$currdate.csv"
$ENTExportfile = "$path\$SvrName-ENT_Exch-SALS-$currdate.csv"

$AllMailboxIDs.GetEnumerator() | select name, @{Name="Type"; Expression={"STD"}} | export-csv $STDExportfile  -delimiter ";" -encoding utf8 -NoTypeInformation
$EnterpriseCALMailboxIDs.GetEnumerator() | select name, @{Name="Type"; Expression={"ENT"}} | export-csv $ENTExportfile  -delimiter ";" -encoding utf8 -NoTypeInformation



$ftp = "ftp://${FTPUser}:${FTPPWD}@${FTPUrl}/$SvrName-STD_Exch-SALS-$currdate.csv"
$webclient = New-Object -TypeName System.Net.WebClient
$uri = New-Object -TypeName System.Uri -ArgumentList $ftp
$webclient.UploadFile($uri, $STDExportfile)


$ftp = "ftp://${FTPUser}:${FTPPWD}@${FTPUrl}/$SvrName-ENT_Exch-SALS-$currdate.csv"
$webclient = New-Object -TypeName System.Net.WebClient
$uri = New-Object -TypeName System.Uri -ArgumentList $ftp
$webclient.UploadFile($uri, $ENTExportfile)