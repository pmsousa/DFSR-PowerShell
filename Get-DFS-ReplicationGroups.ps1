<#
.SYNOPSIS
  Gets DFSR backlog counts for all replication groups or one(s) you specify
.DESCRIPTION
  Gets DFSR backlog counts for all replication groups or one(s) you specify. Intended to use as a PRTG Custom Sensor or standalone script.
  Based on the work of:
    Florian Rossmark - https://www.it-admins.com
    Tyler Woods - https://tylermade.net
.PARAMETER <ReplicationGroupList>
    Comma-separated list of replication groups to evaluate.
.PARAMETER <SourceComputer>
    Computer running DFSR to query.
.INPUTS
  None
.OUTPUTS
  Outputs XML in PRTG Sensor format.
  Reference: https://www.paessler.com/manuals/prtg/custom_sensors
.NOTES
  Version:        1.0
  Author:         Pedro Sousa - pmsousa@gmail.com
  Creation Date:  20/September/2019
  Purpose/Change: Initial script development
  
.EXAMPLE
    Get-DFS-ReplicationGroups.ps1 -ReplicationGroupList 'Local-Group1,Local-Group2' -SourceComputer 'NAS01'

    Retrive the DFSR Backlog for replication groups Local-Group1 and Local-Group2 from server NAS01.
#>
 
Param (
    [String]$ReplicationGroupList = $args[0],
    [string]$SourceComputer = $args[1]
)

Import-Module Dfsr
 
[String[]]$RepGroupList = $ReplicationGroupList.split(",")
         

$ComputerName = $SourceComputer

$XML = "<prtg>"


$RGroups = Get-WmiObject  -Namespace "root\MicrosoftDFS" -Query "SELECT * FROM DfsrReplicationGroupConfig" -ComputerName $ComputerName
#If  replication groups specified, use only those.
if ($RepGroupList) {
    $SelectedRGroups = @()
    foreach ($ReplicationGroup IN $RepGroupList) {
        $SelectedRGroups += $rgroups | Where-Object { $_.ReplicationGroupName -eq $ReplicationGroup }
    }
    if ($SelectedRGroups.count -eq 0) {
        #Write-Error "None of the group names specified were found, exiting"
        Write-Output "<prtg>"
        Write-Output "<error>1</error>"
        Write-Output "<text>None of the group names ($RepGroupList) specified were found for $ComputerName, exiting</text>"
        Write-Output "</prtg>"
        Exit        
    }
    else {
        $RGroups = $SelectedRGroups
    }
}

 
foreach ($Group in $RGroups) {
    $RGFoldersWMIQ = "SELECT * FROM DfsrReplicatedFolderConfig WHERE ReplicationGroupGUID='" + $Group.ReplicationGroupGUID + "'"
    $RGFolders = Get-WmiObject -Namespace "root\MicrosoftDFS" -Query  $RGFoldersWMIQ -ComputerName $ComputerName
    $RGConnectionsWMIQ = "SELECT * FROM DfsrConnectionConfig WHERE ReplicationGroupGUID='" + $Group.ReplicationGroupGUID + "'"
    $RGConnections = Get-WmiObject -Namespace "root\MicrosoftDFS" -Query  $RGConnectionsWMIQ -ComputerName $ComputerName
    foreach ($Connection in $RGConnections) {
        $ConnectionName = $Connection.PartnerName#.Trim()
        if ($Connection.Enabled -eq $True) {
            foreach ($Folder in $RGFolders) {
                $RGName = $Group.ReplicationGroupName
                $RFName = $Folder.ReplicatedFolderName

                if ($Connection.Inbound -eq $True) {
                    $SendingMember = $ConnectionName
                    $ReceivingMember = $ComputerName
                    $Direction = "inbound"
                }
                else {
                    $SendingMember = $ComputerName
                    $ReceivingMember = $ConnectionName
                    $Direction = "outbound"
                }

                $Backlog = Get-DfsrBacklog -GroupName $RGName -FolderName $RFName -SourceComputerName $SendingMember -DestinationComputerName $ReceivingMember -Verbose 4>&1
                
                $BackLogFilecount = 0
                $BackLogFilecount = $Backlog[0].ToString().Split(":")[2].Trim()

                $XML += "<result><channel>BackLog $SendingMember-$ReceivingMember for $RGName</channel><value>$BacklogFileCount</value><unit>Count</unit></result>"

            } # Closing iterate through all folders
        } # Closing  If Connection enabled
    } # Closing iteration through all connections
} # Closing iteration through all groups

$XML += "</prtg>"

Function WriteXmlToScreen ([xml]$xml) {
    $StringWriter = New-Object System.IO.StringWriter;
    $XmlWriter = New-Object System.Xml.XmlTextWriter $StringWriter;
    $XmlWriter.Formatting = "indented";
    $xml.WriteTo($XmlWriter);
    $XmlWriter.Flush();
    $StringWriter.Flush();
    Write-Output $StringWriter.ToString();
}

WriteXmlToScreen $XML