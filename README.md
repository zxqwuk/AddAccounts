# AddAccounts.ps1 - CyberArk Account Onboarding Script

A PowerShell script for bulk onboarding accounts into CyberArk via the API using psPAS. It reads accounts from a CSV, resolves linked logon and reconcile accounts, and onboards each entry via **psPAS** - with optional post-onboarding CPM actions (Verify, Change, Reconcile). Results are logged to a CSV for auditing.

<p align="center"><img width="791" height="635" alt="image" align-item="center" src="https://github.com/user-attachments/assets/85f6cd7d-9678-4cc0-8bc9-c3dffda0ff31" /></p>

## Credits & Dependencies

This script requires the following PowerShell module:

* **[psPAS](https://pspas.pspete.dev/)** by *pspete*: Used for all interactions with the CyberArk REST API - authentication, account search, account creation, and CPM operations.

## CSV Input Format

The default input file is `AddAccounts.csv` (in the same directory as the script). The CSV must have the following columns:

```
Name, Password, SafeName, PlatformID, Address, Username,
LogonAccount, LogonHostname, LogonSafe, LogonPlatform,
ReconAccountName, ReconHostname, ReconSafe, ReconPlatform,
ParameterName1, ParameterValue1, ..., ParameterName10, ParameterValue10
```

| Column | Description |
|---|---|
| `Name` | Account object name in CyberArk |
| `Password` | Account password, or `key` to load an SSH key from `.\Keys\<Username>` |
| `SafeName` | Target safe to onboard the account into |
| `PlatformID` | CyberArk platform ID (e.g. `UnixviaSSH`) |
| `Address` | Account address / IP |
| `Username` | Account username |
| `LogonAccount` | *(Optional)* Username of a linked Logon account |
| `LogonHostname` | *(Optional)* Hostname or address of the Logon account |
| `LogonSafe` | *(Optional)* Safe containing the Logon account |
| `LogonPlatform` | *(Optional)* Platform ID of the Logon account |
| `ReconAccountName` | *(Optional)* Username of a linked Reconcile account |
| `ReconHostname` | *(Optional)* Hostname or address of the Reconcile account |
| `ReconSafe` | *(Optional)* Safe containing the Reconcile account |
| `ReconPlatform` | *(Optional)* Platform ID of the Reconcile account |
| `ParameterName`*N* | *(Optional)* Name of an additional platform account property |
| `ParameterValue`*N* | *(Optional)* Value for the corresponding `ParameterName`*N* |

> **SSH Keys:** If `Password` is set to `key`, the script will read the private key from `.\Keys\<Username>` and onboard it as a key-based secret.

## Usage

```powershell
# Basic onboarding with a PVWA URL:
.\AddAccounts.ps1 -PVWA "https://pvwa.example.com"

# Onboard and immediately trigger a password verify on each account:
.\AddAccounts.ps1 -PVWA "https://pvwa.example.com" -Verify

# Onboard and immediately trigger a password change:
.\AddAccounts.ps1 -PVWA "https://pvwa.example.com" -Change

# Onboard and immediately trigger a password reconcile:
.\AddAccounts.ps1 -PVWA "https://pvwa.example.com" -Reconcile

# Specify a custom CSV and log path:
.\AddAccounts.ps1 -PVWA "https://pvwa.example.com" -CSVInput "C:\path\to\accounts.csv" -LogDir "C:\path\to\log.csv"
```

### Parameters

| Parameter | Type | Description |
|---|---|---|
| `-PVWA` | String | CyberArk PVWA URL |
| `-CSVInput` | String | Path to the input CSV (default: `.\AddAccounts.csv`) |
| `-Verify` | Switch | Trigger a CPM Verify on each account after onboarding |
| `-Change` | Switch | Trigger a CPM Change on each account after onboarding |
| `-Reconcile` | Switch | Trigger a CPM Reconcile on each account after onboarding |
| `-LogDir` | String | Path for the onboarding log CSV |

> Only one of `-Verify`, `-Change`, or `-Reconcile` can be supplied at a time.

## Output

- **Console**: Live per-account status with success/failure indicators.
- **Log CSV**: Appended log of every onboarding attempt, including account details, CyberArk object ID, and any error messages.
- **Failures CSV**: If any accounts fail, a `.\Failures\Failures-<date>.csv` file is written containing only the failed rows for easy re-processing.

<p align="center"><sub><b>made by <a href="https://steffanj.uk">steffan</a><br>❤️</b></sub></p>
