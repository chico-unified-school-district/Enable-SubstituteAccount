# Enable Substitute Account

Enables substitute AD accounts based on pending SQL requests and sets their expiration dates. The script polls for requests marked `waiting`, applies changes in AD, and writes the result back to the request record.

## What it does

- Reads submissions with status `waiting` from `[cf_bp_data]` (`attribute_id = 9722`).
- Retrieves submission data and extracts:
  - `samAccountName` from `attribute_id = 9725`
  - `days` from `attribute_id = 9720`
- Enables the AD account and sets `AccountExpirationDate = Today + days`.
- Updates the request status to `success` or `error`.
- Repeats every 60 seconds until `StopTime`.

## Requirements

- PowerShell 5.1+
- Modules:
  - `CommonScriptFunctions`
  - `dbatools`
- AD permissions to read/update user accounts
- SQL permissions to read/update `[cf_bp_data]`

## Files

- Main script: [Enable-SubstituteAccount.PS1](Enable-SubstituteAccount.PS1)
- Supporting SQL example: [sql/lf-get-sub-account-request.sql](sql/lf-get-sub-account-request.sql)

## Parameters

- `DomainControllers` (string[]): Domain controllers for AD session.
- `ADCredential` (PSCredential): Credential for AD operations.
- `SQLServer` (string): SQL instance name.
- `SQLDatabase` (string): Target database.
- `SQLCredential` (PSCredential): Credential for SQL operations.
- `StopTime` (string, default `5:00 PM`): Local time to stop polling.
- `WhatIf` (switch): Simulates changes without updating AD or SQL.

## Example usage

Run manually:

Enable-SubstituteAccount.PS1 -DomainControllers "dc1","dc2" -ADCredential $adCred -SQLServer "sql01" -SQLDatabase "LFCatalog" -SQLCredential $sqlCred

Dry run:

Enable-SubstituteAccount.PS1 -DomainControllers "dc1","dc2" -ADCredential $adCred -SQLServer "sql01" -SQLDatabase "LFCatalog" -SQLCredential $sqlCred -WhatIf

## Process flow

1. Connects to SQL and AD (AD only when requests are found).
2. Gets all submissions with status `waiting`.
3. Extracts `samAccountName` and `days`.
4. Enables the account and sets expiration.
5. Writes `success` or `error` back to the request record.
6. Waits 60 seconds and repeats until `StopTime`.

## Behavior notes

- `-WhatIf` skips AD/SQL updates and the 60-second sleep.
- AD errors are captured in `adError` and reported to the console.
- Status updates are written to `[cf_bp_data]` only when not using `-WhatIf`.

## Troubleshooting

- **No requests processed**: Confirm records exist with `attribute_id = 9722` and `value = 'waiting'`.
- **AD update errors**: Verify permissions and that `samAccountName` exists.
- **SQL errors**: Confirm credentials and database connectivity.

## Notes

- The script uses `Get-ADUser` and `Set-ADUser` via a remote AD session created by `Connect-ADSession`.
