# Enable Substitute Account

This PowerShell script processes substitute-account requests from SQL. For each request waiting for processing, it enables the Active Directory account, sets its expiration, resets its password, and emails the account information to the requester.

## What it does

1. Finds rows in `[cf_bp_data]` whose `attribute_id` is `9722` and whose value is `waiting`.
2. Reads the request fields:
   - `9725`: Active Directory `samAccountName`
   - `9726`: account expiration date
   - `9718`: recipient email address
   - `10178`: optional CC email address
3. Sets the account expiration to the requested date at **5:00 PM local time** and enables the account.
4. Generates a temporary password, resets the account password, and creates a password-sharing link that expires after two days or five views.
5. Emails the account name, expiration date, and password-sharing link to the requester. The optional `Bcc` parameter adds a BCC recipient.
6. Sets the request status to `success`, or to the captured AD update error message.
7. Polls again every 60 seconds until `StopTime`.

The script runs once before checking `StopTime`, so it processes requests even if the specified stop time has already passed.

## Requirements

- Windows PowerShell 5.1 or later.
- The following modules:
  - `ActiveDirectory`
  - `CommonScriptFunctions`
  - `dbatools`
  - `Mailozaurr`
- SQL permissions to read and update `[cf_bp_data]` in the target database.
- Active Directory permissions to read the account, enable it, set its expiration, and reset its password.
- SMTP credentials and permission to send mail through `smtp.office365.com`.
- Network access to the SQL server, Active Directory, SMTP, and `eu.pwpush.com` for password-sharing links.

## Files

- Main script: [Enable-SubstituteAccount.PS1](Enable-SubstituteAccount.PS1)
- Email templates and styles: [html/](html/)
- Password generation and sharing-link helpers: [lib/](lib/)

Run the script from the repository directory. It loads the templates and helper scripts using paths relative to the current directory.

## Parameters

| Parameter         | Type           | Required | Default   | Description                                                                                          |
| ----------------- | -------------- | -------: | --------- | ---------------------------------------------------------------------------------------------------- |
| `ADCredential`    | `PSCredential` |      Yes | —         | Credential used for Active Directory operations.                                                     |
| `EmailCredential` | `PSCredential` |      Yes | —         | Credential used to send email.                                                                       |
| `SQLServer`       | `string`       |      Yes | —         | SQL Server instance.                                                                                 |
| `SQLDatabase`     | `string`       |      Yes | —         | Database containing `[cf_bp_data]`.                                                                  |
| `SQLCredential`   | `PSCredential` |      Yes | —         | Credential used to connect to SQL Server.                                                            |
| `Bcc`             | `string`       |       No | —         | Optional BCC recipient for account emails.                                                           |
| `StopTime`        | `string`       |       No | `5:00 PM` | Local time at which polling stops.                                                                   |
| `WhatIf`          | `switch`       |       No | Off       | Simulates updates and email without committing them; processes one polling cycle. `-wi` is an alias. |

## Example

```powershell
.\Enable-SubstituteAccount.PS1 `
    -ADCredential $adCred `
    -EmailCredential $emailCred `
    -SQLServer 'Laserfiche-Sql-Server' `
    -SQLDatabase 'LF-FORMS' `
    -SQLCredential $sqlCred `
    -StopTime '5:00 PM'
```

To run one simulated cycle:

```powershell
.\Enable-SubstituteAccount.PS1 `
    -ADCredential $adCred `
    -EmailCredential $emailCred `
    -SQLServer 'sql01' `
    -SQLDatabase 'LFCatalog' `
    -SQLCredential $sqlCred `
    -WhatIf
```

In `-WhatIf` mode, the script still connects to SQL, reads waiting requests and account data, and performs AD lookups. It does not write request status to SQL, and it passes `WhatIf` to the AD and email operations. Password-sharing URLs are replaced with a test URL.
