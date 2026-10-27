function New-PasswordRequestURL {
 [CmdletBinding()]
 [OutputType([string])]
 param(
  [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
  [ValidateNotNullOrEmpty()]
  [string]$Password,

  # Days before the push auto-expires
  [int]$ExpireDays = 5,

  # Maximum views before the push auto-expires
  [int]$ExpireViews = 5
 )

 process {
  $body = @{
   push = @{
    payload               = $Password
    expire_after_duration = $ExpireDays
    expire_after_views    = $ExpireViews
   }
  } | ConvertTo-Json -Depth 5

  $headers = @{
   'Content-Type' = 'application/json'
   # 'Authorization' = 'Bearer <token>'  # Optional: registered/Pro account
  }

  $response = Invoke-RestMethod -Uri 'https://eu.pwpush.com/api/v2/pushes' `
   -Method Post `
   -Headers $headers `
   -Body $body

  "https://eu.pwpush.com/p/$($response.url_token)"
 }
}
