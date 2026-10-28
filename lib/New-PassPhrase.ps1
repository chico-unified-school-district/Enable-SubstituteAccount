<#
.SYNOPSIS
Generates a secure, human-readable passphrase for temporary user passwords.

.DESCRIPTION
New-PassPhrase builds a passphrase from three words randomly selected from words.dic (the EFF large wordlist,
7,776 words) located next to this script. Each word is title-cased, and two digits and a symbol are added.
Selection uses a cryptographically secure random number generator. The result is between MinLength (default 16) and MaxLength (default 24) characters long.

.OUTPUTS
String - a generated passphrase suitable for short-term use.
#>
function New-PassPhrase {
 [cmdletbinding()]
 param (
  [ValidateRange(16, 64)][int]$MinLength = 16,
  [ValidateRange(16, 64)][int]$MaxLength = 24,
  [ValidateRange(3, 8)][int]$WordCount = 3
 )

 # Words are 3-9 characters; two digits and a symbol add 3
 if ($MaxLength -lt $MinLength) { throw "MaxLength ($MaxLength) must be greater than or equal to MinLength ($MinLength)." }
 if ($MaxLength -lt (3 * $WordCount + 3) -or $MinLength -gt (9 * $WordCount + 3)) {
  throw "A length of $MinLength-$MaxLength cannot be met with $WordCount words."
 }

 $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
 # Unbiased random integer in [0, Max); also works on Windows PowerShell 5.1
 function Get-SecureInt ([int]$Max) {
  $bytes = New-Object byte[] 4
  $limit = [uint32]::MaxValue - ([uint32]::MaxValue % [uint32]$Max)
  do {
   $rng.GetBytes($bytes)
   $n = [BitConverter]::ToUInt32($bytes, 0)
  } while ($n -ge $limit)
  [int]($n % $Max)
 }

 $TextInfo = (Get-Culture).TextInfo
 $words = Get-Content -Path (Join-Path $PSScriptRoot 'words.dic') | Where-Object { $_ -match '^[a-z]+$' }
 $symbols = '@', '%', '&', '#', '!'
 do {
  $phrase = -join (1..$WordCount | ForEach-Object { $TextInfo.ToTitleCase($words[(Get-SecureInt $words.Count)]) })
  $phrase += '{0}{1}' -f ((Get-SecureInt 90) + 10), $symbols[(Get-SecureInt $symbols.Count)]
 } until ($phrase.Length -ge $MinLength -and $phrase.Length -le $MaxLength)
 $rng.Dispose()
 $phrase
}

# Wordlist: https://www.eff.org/deeplinks/2016/07/new-wordlists-random-passphrases