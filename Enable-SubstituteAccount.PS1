[cmdletbinding()]
param (
 [Parameter(Mandatory = $True)][PSCredential]$ADCredential,
 [Parameter(Mandatory = $False)][string]$Bcc,
 [Parameter(Mandatory = $True)][PSCredential]$EmailCredential,
 [Parameter(Mandatory = $True)][string]$SQLServer,
 [Parameter(Mandatory = $True)][string]$SQLDatabase,
 [Parameter(Mandatory = $True)][PSCredential]$SQLCredential,
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
   html           = $null
   mail           = $null
   pw             = $null
   pwURL          = $null
   samid          = $null
   subMail        = $null
   submissionData = $null
   submissionId   = $_.submission_Id
   status         = $null
  }
 }
}

function Send-Email {
 param (
  [pscredential]$cred,
  [string]$bcc
 )
 process {
  $params = @{
   To         = $_.mail
   From       = '<{0}>' -f $cred.Username
   Subject    = '{0} CUSD Substitute Account Information - {1}' -f (Get-Date -Format 'MM/dd/yyyy'), $_.samid
   Html       = $_.html
   SMTPServer = 'smtp.office365.com'
   Cred       = $cred
   UseSSL     = $True
   Port       = 587
   WhatIf     = $WhatIf
   Suppress   = $True
  }
  if ($bcc) { $params += @{Bcc = $bcc } }
  if ($_.subMail) { $params += @{Cc = $_.subMail } }

  Send-EmailMessage @params
  Write-Verbose ($params | Out-String)
  $msg = $MyInvocation.MyCommand.name, ($params.To -join ','), $_.subMail, $params.Subject
  Write-Host ('{0},Recipient: [{1},{2}],Subject: [{3}]' -f $msg) -F Green
  $_
 }
}

function Set-PropAData ([pscredential]$cred) {
 process {
  $_.ad = Get-ADUser -Identity $_.samid -Credential $cred
  $_
 }
}

function Set-PropDate {
 process {
  # date : attribute id 9726
  $_.date = ($_.submissionData.Where({ $_.attribute_id -eq 9726 })).value
  $_
 }
}

function Set-PropStatus {
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

function Set-PropExpireDate {
 process {
  $_.expireDate = (Get-Date "$($_.date) 5:00PM")
  $_
 }
}

function Set-PropMail {
 process {
  $_.mail = $_.submissionData.Where({ $_.attribute_id -eq 9718 }).value
  $_
 }
}

function Set-PropHTML {
 begin {
  $head = "<style TYPE=`"TEXT/CSS`"><!--`n" + (Get-Content -Path .\html\style.css -Raw) + "`n--></style>"
  $pre = Get-Content -Path .\html\accountInfo.html -Raw
  $sig = Get-Content -Path .\html\emailSig.html -Raw
 }
 process {
  $passwordLink = '<a href="{0}">Click here for Password</a>' -f [System.Net.WebUtility]::HtmlEncode($_.pwURL)
  $tableData = [ordered]@{
   'Username:'   = 'Chico\' + $_.samid
   'Password:'   = 'PASSWORD_LINK'
   'Expiration:' = Get-Date $_.expireDate -Format 'MMMM dd h:mm tt'
  }
  # Convert directly to HTML rows
  $htmlTable = $tableData.GetEnumerator() | Select-Object @{N = 'Sub Login Details'; E = { $_.Key } }, @{N = ' '; E = { $_.Value } } | ConvertTo-Html -Fragment | Out-String
  $htmlTable = $htmlTable -replace 'PASSWORD_LINK', $passwordLink
  $html = ConvertTo-Html -Body ($pre + $htmlTable) -Head $head -PostContent $sig | Out-String
  $_.html = $html
  # Write-Verbose ($_.html | Out-String)
  $_
 }
}

function Set-PropPW {
 process {
  $_.pw = New-PassPhrase
  $_
 }
}

function Set-PropPwURL {
 begin {
  . .\lib\New-PasswordRequestURL.ps1
 }
 process {
  $_.pwURL = if ($WhatIf) { 'https://test.url/{0}' -f $_.pw }
  else { New-PasswordRequestURL -Password $_.pw -ExpireDays 2 -ExpireViews 5 }
  $_
 }
}

function Set-PropSubMail {
 process {
  $_.subMail = $_.submissionData.Where({ $_.attribute_id -eq 10178 }).value
  $_
 }
}

function Set-PropSubmissionData ($session) {
 begin { $sql = 'SELECT * FROM [cf_bp_data] WHERE submission_id = @id;' }
 process {
  $_.submissionData = New-SqlOperation -Server $session -Query $sql -Parameters "id=$($_.submissionId)" |
   ConvertTo-Csv |
    ConvertFrom-Csv
  # Write-Verbose ($_.submissionData | Out-String)
  $_
 }
}

function Set-PropSamid {
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

function Update-ADExpirationDate ([pscredential]$cred) {
 process {
  $params = @{
   Credential            = $cred
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

function Update-ADPW ([pscredential]$cred) {
 process {
  $securePW = ConvertTo-SecureString -String $_.pw -AsPlainText -Force
  $params = @{
   Credential    = $cred
   Identity      = $_.ad.ObjectGUID
   NewPassword   = $securePW
   Reset         = $true
   Confirm       = $false
   ErrorVariable = 'adPwError'
   ErrorAction   = 'Stop'
   WhatIf        = $WhatIf
  }
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.samid) -F Magenta
  Set-ADAccountPassword @params
  $_.error = if ($adPwError) { $adPwError.Exception.Message }
  $_
 }
}

# =============================== Main ==================================
Show-BlockInfo start
Import-Module -Name ActiveDirectory -Cmdlet Get-ADUser, Set-ADUser, Set-ADAccountPassword -WarningAction SilentlyContinue -ErrorAction Stop
Import-Module -Name CommonScriptFunctions -Cmdlet Show-TestRun, Show-BlockInfo, Clear-SessionData, New-SqlOperation
Import-Module -Name dbatools -Cmdlet Set-DbatoolsConfig, Invoke-DbaQuery, Connect-DbaInstance
Import-Module -Name Mailozaurr -Cmdlet Send-EmailMessage

. .\lib\New-PassPhrase.ps1

if ($WhatIf) { Show-TestRun }
Show-BlockInfo main

$accountRequestSql = "SELECT submission_id FROM [cf_bp_data] WHERE attribute_id = 9722 AND value = 'waiting';"
$dbaInstance = Connect-DbaInstance -SqlInstance $SQLServer -SqlCredential $SQLCredential -Database $SQLDatabase

do {
 $subAccountRequests = Invoke-DbaQuery -SqlInstance $dbaInstance -Query $accountRequestSql | ConvertTo-Csv | ConvertFrom-Csv
 $subAccountRequests |
  Format-Obj |
   Set-PropSubmissionData -session $dbaInstance |
    Set-PropSubMail |
     Set-PropSamid |
      Set-PropDate |
       Set-PropExpireDate |
        Set-PropAData -cred $ADCredential |
         Set-PropMail |
          Set-PropPW |
           Set-PropPwURL |
            Set-PropHTML |
             Update-ADExpirationDate -cred $ADCredential |
              Update-ADPW -cred $ADCredential |
               Send-Email -cred $EmailCredential -Bcc $Bcc |
                Set-PropStatus |
                 Set-LFStatusField -session $dbaInstance |
                  Show-Obj

 if ($WhatIf) { break }
 Start-Sleep 60
} until ((Get-Date) -ge (Get-Date $StopTime))

if ($WhatIf) { Show-TestRun }
Show-BlockInfo end