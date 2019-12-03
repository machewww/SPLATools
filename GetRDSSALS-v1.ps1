$FilePath = "C:\Scripts\SPLA\Expports"
$Group = ""

Import-Module ActiveDirectory

$Members = Get-ADGroupMember -Identity $Group -Recursive | select distinguishedname
$Members | Export-Csv -Path $FilePath\SPLA-RDSCount-$Group-$(get-date -f yyyy-MM-dd).csv -NoTypeInformation -Encoding UTF8
