[cmdletbinding()]
param (
 [Parameter(Mandatory = $True)][Alias('DCs')][string[]]$DomainControllers,
 [Parameter(Mandatory = $True)][System.Management.Automation.PSCredential]$ADCredential,
 [Parameter(Mandatory = $True)] [string]$SQLServer,
 [Parameter(Mandatory = $True)][string]$SQLDatabase,
 [Parameter(Mandatory = $True)][System.Management.Automation.PSCredential]$SQLCredential,
 [string]$StopTime = '5:00 PM',
 [Alias('wi')][SWITCH]$WhatIf
)

function Format-Obj {
 process {
  [PSCustomObject]@{
   adGuid         = $null
   date           = $null
   # days           = $null
   submission_id  = $_.submission_id
   samid          = $null
   submissionData = $null
   status         = $null
  }
 }
}

function Set-ADData {
 process {
  $_.adGuid = (Get-ADUser -Identity $_.samid).ObjectGUID
  $_
 }
}

function Set-SubmissionData ($session) {
 begin { $sql = 'SELECT * FROM [cf_bp_data] WHERE submission_id = @id;' }
 process {
  $_.submissionData = New-SqlOperation -Server $session -Query $sql -Parameters "id=$($_.submission_id)" | ConvertTo-Csv | ConvertFrom-Csv
  $_
 }
}

function Set-Variables {
 process {
  # samAccountName : 9725
  # days = 9720 - no longer used - replaced with date
  # date = 9726
  $_.samid = ($_.submissionData.Where({ $_.attribute_id -eq 9725 })).value
  # $_.days = ($_.submissionData.Where({ $_.attribute_id -eq 9720 })).value
  $_.date = ($_.submissionData.Where({ $_.attribute_id -eq 9726 })).value
  $_
 }
}

function Show-Obj { process { Write-Verbose ( '{0},{1}' -f $MyInvocation.MyCommand.Name, ($_ | Out-String)) } }

function Update-ADExpirationDate {
 process {
  $expireDate = (Get-Date "$($_.date) 5:00PM")
  $params = @{
   Identity              = $_.adGuid
   AccountExpirationDate = $expireDate
   Enabled               = $true
   ErrorVariable         = 'adError'
   WhatIf                = $WhatIf
  }
  Set-ADUser @params
  if ($adError) {
   $_.status = 'error'
   Write-Error ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.samid, $adError) -F Red
  }
  else {
   $_.status = 'success'
   Write-Host ('{0},{1},Expires:{2}' -f $MyInvocation.MyCommand.Name, $_.samid, $expireDate) -F Green
  }
  $_
 }
}

function Set-LFStatusField ($session) {
 begin {
  $sql = 'UPDATE [cf_bp_data] SET value = @status WHERE submission_id = @id AND attribute_id = 9722;'
 }
 process {
  Write-Host ('{0},{1},Submission ID:{2},{3}' -f $MyInvocation.MyCommand.Name, $_.samid, $_.submission_id, $_.status) -F Cyan
  $vars = "id=$($_.submission_id)", "status=$($_.status)"
  if (!$WhatIf) { New-SqlOperation -Server $session -Query $sql -Parameters $vars }
  $_
 }
}

# =============================== Main ==================================
Import-Module -Name CommonScriptFunctions -Cmdlet Show-TestRun, Show-BlockInfo, Connect-ADSession, Clear-SessionData, New-SqlOperation
Import-Module -Name dbatools -Cmdlet Set-DbatoolsConfig, Invoke-DbaQuery, Connect-DbaInstance

Show-BlockInfo main

if ($WhatIf) { Show-TestRun }

$adCmdLets = 'Get-ADUser', 'Set-ADUser'

$dbaInstance = Connect-DbaInstance -SqlInstance $SQLServer -SqlCredential $SQLCredential -Database $SQLDatabase

# LF Forms field ids
# status = 9722
$accountRequestSql = "SELECT submission_id FROM [cf_bp_data] WHERE attribute_id = 9722 AND value = 'waiting';"

do {
 $subAccountRequests = Invoke-DbaQuery -SqlInstance $dbaInstance -Query $accountRequestSql | ConvertTo-Csv | ConvertFrom-Csv
 if ($subAccountRequests) {
  Connect-ADSession -DomainControllers $DomainControllers -Cmdlets $adCmdLets -Credential $ADCredential
 }
 $subAccountRequests |
  Format-Obj |
   Set-SubmissionData $dbaInstance |
    Set-Variables |
     Set-ADData |
      Update-ADExpirationDate |
       Set-LFStatusField $dbaInstance |
        Show-Obj

 Clear-SessionData

 if (!$WhatIf) { Start-Sleep 60 }
} until ($WhatIf -or ((Get-Date) -ge (Get-Date $StopTime)))

if ($WhatIf) { Show-TestRun }
Show-BlockInfo end