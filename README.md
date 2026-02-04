# Enable Substitute Account

This process enables substitute accounts based on pending requests in SQL and sets the account expiration date in Active Directory. It polls for requests marked as `waiting`, updates the AD account, and writes the result back to the request record.

## What it does

- Reads submissions with status `waiting` from the SQL table `[cf_bp_data]` (field `attribute_id = 9722`).
- Retrieves submission data for each request and extracts:
  - `samAccountName` from field `attribute_id = 9725`.
  - Expiration date from field `attribute_id = 9726`.
- Enables the AD account and sets `AccountExpirationDate` to the provided date at **5:00 PM** local time.
- Updates the request status (`attribute_id = 9722`) to `success` or the AD error message.
- Repeats every 60 seconds until `StopTime` (unless `-WhatIf` is used).

## Requirements

- PowerShell 5.1+.
- Modules:
  - `CommonScriptFunctions`
  - `dbatools`
- AD permissions to read and update user accounts.
- SQL permissions to read and update `[cf_bp_data]`.

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

1. Connects to SQL and AD.
2. Gets all submissions with status `waiting`.
3. Extracts `samAccountName` and expiration date from submission data.
4. Enables the account and sets expiration (date at 5:00 PM).
5. Writes `success` or error back to the request record.
6. Waits 60 seconds and repeats until `StopTime` (skipped in `-WhatIf`).

## Notes

- The script uses `Get-ADUser` and `Set-ADUser` under a remote AD session created by `Connect-ADSession`.
- Status updates and sleep are skipped when `-WhatIf` is used.
- Errors from AD updates are captured in `adUpdateError` and logged to the console.
