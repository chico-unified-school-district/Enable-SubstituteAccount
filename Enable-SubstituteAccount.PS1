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
   ad             = $null
   error          = $null
   date           = $null
   expireDate     = $null
   samid          = $null
   submissionData = $null
   submissionId   = $_.submission_Id
   status         = $null
  }
 }
}

function Set-AData {
 process {
  $_.ad = Get-ADUser -Identity $_.samid
  $_
 }
}

function Set-Date {
 process {
  # date : attribute id 9726
  $_.date = ($_.submissionData.Where({ $_.attribute_id -eq 9726 })).value
  $_
 }
}

function Set-Status {
 process {
  if ($_.error) {
   $_.status = $_.error
   Write-Error ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.samid, $_.error) -F Red
  }
  else {
   $_.status = 'success'
   Write-Host ('{0},{1},Expires:{2}' -f $MyInvocation.MyCommand.Name, $_.samid, $_.expireDate) -F Green
  }
  $_
 }
}

function Set-ExpireDate {
 process {
  $_.expireDate = (Get-Date "$($_.date) 5:00PM")
  $_
 }
}

function Set-SubmissionData ($session) {
 begin { $sql = 'SELECT * FROM [cf_bp_data] WHERE submission_id = @id;' }
 process {
  $_.submissionData = New-SqlOperation -Server $session -Query $sql -Parameters "id=$($_.submissionId)" |
   ConvertTo-Csv |
    ConvertFrom-Csv
  $_
 }
}

function Set-Samid {
 process {
  # samAccountName : attribute id 9725
  $_.samid = ($_.submissionData.Where({ $_.attribute_id -eq 9725 })).value
  $_
 }
}

function Set-LFStatusField ($session) {
 begin {
  # status : attribute id 9722
  $sql = 'UPDATE [cf_bp_data] SET value = @status WHERE submission_id = @id AND attribute_id = 9722;'
 }
 process {
  Write-Host ('{0},{1},Submission ID:{2},{3}' -f $MyInvocation.MyCommand.Name, $_.samid, $_.submissionId, $_.status) -F Cyan
  $vars = "id=$($_.submissionId)", "status=$($_.status)"
  if (!$WhatIf) { New-SqlOperation -Server $session -Query $sql -Parameters $vars }
  $_
 }
}

function Show-Obj { process { Write-Verbose ( '{0},{1}' -f $MyInvocation.MyCommand.Name, ($_ | Out-String)) } }

function Update-ADExpirationDate {
 process {
  $params = @{
   Identity              = $_.ad.ObjectGUID
   AccountExpirationDate = $_.expireDate
   Enabled               = $true
   ErrorVariable         = 'adUpdateError'
   WhatIf                = $WhatIf
  }
  Set-ADUser @params
  $_.error = if ($adUpdateError) { $adUpdateError.Exception.Message }
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

$accountRequestSql = "SELECT submission_id FROM [cf_bp_data] WHERE attribute_id = 9722 AND value = 'waiting';"

do {
 $subAccountRequests = Invoke-DbaQuery -SqlInstance $dbaInstance -Query $accountRequestSql | ConvertTo-Csv | ConvertFrom-Csv
 if ($subAccountRequests) {
  Connect-ADSession -DomainControllers $DomainControllers -Cmdlets $adCmdLets -Credential $ADCredential
 }
 $subAccountRequests |
  Format-Obj |
   Set-SubmissionData $dbaInstance |
    Set-Samid |
     Set-Date |
      Set-ExpireDate |
       Set-AData |
        Update-ADExpirationDate |
         Set-Status |
          Set-LFStatusField $dbaInstance |
           Show-Obj

 Clear-SessionData

 if (!$WhatIf) { Start-Sleep 60 }
} until ($WhatIf -or ((Get-Date) -ge (Get-Date $StopTime)))

if ($WhatIf) { Show-TestRun }
Show-BlockInfo end