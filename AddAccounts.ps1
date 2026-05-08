<#

CyberArk Account Onboarding Script - 26/09/2022
Made by Steffan

Parameters:
    CSVInput     - Input csv with accounts to onboard
    Verify       - Verify accounts after onboarding
    Change       - Change accounts after onboarding
    Reconcile    - Reconcile accounts after onboarding
    PVWA         - PVWA URL
    LogDir       - Directory for logs

#>
[CmdletBinding(PositionalBinding=$false)]
param(
    [String] $CSVInput = "$((Get-Location).Path)\AddAccounts.csv", # CSV Input
    [switch] $Verify, # Verify Accounts after onboarding
    [switch] $Change, # Change Accounts after onboarding
    [switch] $Reconcile, # Reconcile Accounts after onboarding
    [String] $PVWA, # PVWA URL
    [String] $LogDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("..\..\Logs\OnboardLog-$(Get-Date -Format 'dd-MM-yyyy').csv") 
)

function Get-Account() {
    <#
        Function to search and return account
        Search should be a Hashtable with keys being account properties, and the values being the search terms
        Example:
        $Search = @{
            "safename" = "TESTING-SAFE";
            "username" = "unixaccount";
            "address" = "1.1.1.1";
            "platformid"  = "UnixviaSSH";
            "platformAccountProperties\hostname" = "UKSERVER1"
        }
        Above example will search for "unixaccount 1.1.1.1 UnixviaSSH" inside safe TESTING-SAFE.
        Make sure that your search terms (the keys) are directly related to account properties.
        For any additional account properties, use platformAccountProperties\property
    #>
    param(
        # Account validation
        [ValidateNotNullOrEmpty()]
        [PSCustomObject] $Search = @{}
    )

    $search_terms = ($Search.Keys).ToLower() # Get account search keys
    if($search_terms.Count -lt 1) {
        throw "Search input is missing`nCurrent Search: $Search"
        return
    }

    # Building search param object for Get-PASAccount
    $params = @{
        search = @();
    }
    foreach($param in $search_terms) {
        if($param -eq "safename") {
            $params.Add("safeName", $Search."$param")
        } else {
            $params."search" += $Search."$param"
        }
    }

    $params."search" = "$($params."search")" # turn string[] into string

    # After we get accounts, we need to make sure we return the correct Account
    $account = $null

    $accounts = Get-PASAccount @params # Search for account using our filters

    foreach($acc in $accounts) { # loop through accounts in results
        $found = $false
        foreach($term in $search_terms) { # loop through our queries
            if($term -contains "\") { # check for additional props
                # platformAccountProperties\hostname
                # $term."platformAccountProperties"."hostname"
                $term_split = $term -Split "\"
                if($acc."$($term_split[0])"."$($term_split[1])" -eq $Search."$($term_split[0])"."$($term_split[1])") {
                    $found = $true # value is correct
                }
            } else {
                if($acc."$term" -eq $Search."$term") {
                    $found = $true # value is correct
                }
            }
        }
        # if found is true, then the account has been found
        if($found -eq $true) {
            $account = $acc
            break #skip the rest
        }
    }
    return $account # Return account, $null or account object
}

function Add-AccountLog() {
    <#
        Function to log account data and if onboarding was successfull
        $LogDir points to the directory and file of log
        $Success is boolean True/False
        $Account is a CyberArk account API object
        $Comment is a string
        $LogonAccount is a string
    #>
    param(
        $LogDir,
        $Success,
        $Account,
        $Comment = $null,
        $LogonAccount,
		$APIDetails = @{"Id" = $null; "name" = $null;}
    )
    try {
        $null = [PSCustomObject]@{
            DateAdded  = $(Get-Date -Format 'dd-MM-yyyy HH:mm');
            Action     = "Add Account";
            Success    = $Success;
            SafeName   = $Account.SafeName;
            Address    = $Account.address;
            Hostname   = $Account.platformAccountProperties.Hostname;
            AccountID  = $APIDetails.Id;
            Name       = $APIDetails.name;
            Username   = $Account.userName;
            PlatformID = $Account.platformId;
            Member     = $null;
            Group      = $null;
            Comment    = $Comment;
            CyberArkLogon = $LogonAccount;
        } | Export-Csv -Path $LogDir -NoTypeInformation -Append
    } catch {
        Write-Host "Error updating log for account $($Account.username) with error: $_"
    }
}

# START
Write-Host "-----------------------------------------------------" -f Cyan
Write-Host "             CyberArk Onboarding Script"
Write-Host "                steffan" -f Red -nonewline; Write-Host " - 15/07/2022"
Write-Host "-----------------------------------------------------" -f Cyan
Write-Host "Log File Location: " -f Cyan -NoNewLine; Write-Host "$LogDir"

# Importing CSV - required, check provided csv as an example
Write-Host "CSV Location: " -f Cyan -NoNewLine; Write-Host "$CSVInput"
try {
    $accountsInput = Import-Csv $CSVInput
} catch {
    Write-Host "$_" -f Red
    Write-Host "`nExiting.`n"
    exit
}
$inputTotal = ($accountsInput | Measure-Object).Count
if($inputTotal -eq 0) {
    Write-Host "Input csv has zero accounts present, please check the format of csv" -f Red
    Write-Host "`nExiting.`n"
    exit
}
Write-Host "Number of accounts: " -f Cyan -NoNewLine; Write-Host "$inputTotal"

# Parse Action Inputs
$action = "None"
$actionCount = 0
if($Verify.IsPresent) {
    $actionCount++
    $action = "Verify" # Set accounts to verify once onboarded
}
if($Change.IsPresent) {
    $actionCount++
    $action = "Change" # Set accounts to change once onboarded
}
if($Reconcile.IsPresent) {
    $actionCount++
    $action = "Reconcile" # Set accounts to reconcile once onboarded
}
if($actionCount -gt 1) {
    Write-Host "Multiple actions supplied, please only provide one action" -f Red
    Write-Host "Actions: -Verify -Change -Reconcile" -f Red
    Write-Host "`nExiting.`n"
    exit
}
# Manual Actioning, if you're running via ISE, 
#$action = "None"

Write-Host "Action: " -f Cyan -NoNewLine; Write-Host "$action"

# Login to CyberArk
Write-Host "Connecting to PVWA: " -f Cyan -NoNewLine; Write-Host "$PVWA"
$loggedin = $false
try {
    if((Get-PASSession -ErrorAction Ignore).User -ne $null -and (Get-PASSession -ErrorAction Ignore).User -ne "") {
        $loggedin = $true
    }
} catch {}
if(!$loggedin) {
    Write-Host "Username: " -f Cyan -NoNewLine
    $login_username = Read-Host

    Write-Host "Password: " -f Cyan -NoNewLine
    $login_password = Read-Host -AsSecureString

    #Write-Host "OTP: " -f Cyan -NoNewLine
    #$otp = Read-Host

    $cred = New-Object System.Management.Automation.PSCredential ($login_username, $login_password)
    
    New-PASSession -Credential $cred -BaseURI $PVWA -concurrentSession $true -Type LDAP

}



# ONBOARD
# Time to onboard
Write-Host "`nOnboarding " -NoNewline; Write-Host $inputTotal -f Cyan -NoNewline; Write-Host " accounts"
Write-Host "-----------------------------------------------------" -f Cyan

# Success and failure counters
$successCount = 0
$failCount = 0

# Failure array, these will be outputed to a csv after onboarding is complete
$failAccounts = @()

$rowIndex = 1
#Name,Password,SafeName,PlatformID,Address,Username,logonAccount,logonHostname,logonSafe,logonPlatform,ReconAccountName,ReconHostname,ReconSafe,ReconPlatform,ParameterName1,ParameterValue1,..,ParameterName10,ParameterValue10
foreach($account in $accountsInput) {

    # lines 170-175 is for printing 
    $prefix = "[$rowIndex/$inputTotal] "
    $tab = "";
    for($i=0;$i -lt ($prefix.Length-2); $i++) { $tab += " " } # Stupid tab size code
    $send = "$([char]0x2192) " # right-arrow
    $receive = "$([char]0x2190) " # left-arrow

    Write-Host "$prefix" -f Cyan -NoNewline ; Write-Host "$($account.Address) $($account.Username)"
    
    # Search if account already exists
    $searchParams = @{
        "username" = $account.Username;
        "address" = $account.Address;
        "platformid" = $account.PlatformID.replace(' ','')
        "safename" = $account.SafeName;
    }
    $accountCheck = Get-Account -Search $searchParams
    $accountCheck = $null # Fix this bug!

    if($null -ne $accountCheck) {
        $tab_ = $tab + $receive
        Write-Host "$($tab_)" -f Cyan -NoNewline; Write-Host "Account already exists, skipping" -f Yellow
        Write-Host "$accountCheck" -f Yellow
        #Add-AccountLog -LogDir $LogDir -Success $false -Account $account -Comment "Account already exists, skipping. Account: $($accountCheck.name)" -LogonAccount $apiAccount
        $failCount++
        $rowIndex++
        continue
    }
    
    # Account details/properties can be passed to Add-PASAccount as @account_details
    $accountDetails = @{}

    # Add account properties
    foreach($param in ($account | Get-Member -MemberType NoteProperty).Name) { # Loop through all columns in csv
        if($account."$param" -ne "" -and $null -ne $account."$param") { # Ignore blank values
            if($param -match "ParameterName") { # Extra Parameters columns
                # Additional Parameters
                $paramIndex = $param -replace '\D+(\d+)','$1'
                $paramName = $account."$param"
                $paramValue = $account."ParameterValue$paramIndex" # Get relevant parameter from index

                if(($paramName).ToLower() -match "remotemachines") {
                    $accountDetails.Add($paramName, $paramValue) # Remote Machines is it's own thing
                } else {
                    if(!($accountDetails.Keys -contains "-platformAccountProperties")) {
                        $accountDetails.Add("-platformAccountProperties", @{}) # Create platformAccountProperties if not exists
                    }
                    $accountDetails."-platformAccountProperties".Add($paramName, $paramValue)
                }
            } elseif($param -match "ParameterValue") { # ignore these, they'll be handled with ParameterName
            } else {
                # Normal property, address, username etc
                # ignore certain parameters
                # LogonAccount,LogonHostname,LogonSafe,LogonPlatform,ReconAccountName,ReconHostname,ReconSafe,ReconPlatform
                if($param -match "Logon" -or $param -match "Recon") { # Ignore Logon and Recon columns, we deal with them later
                    continue
                }
                if($param -eq "Password") { # Password value needs to be secure string instead of plaintext
                    if($account."$param" -ne "key") {
                        $password = ConvertTo-SecureString -String $account."$param" -AsPlainText -Force
                        $accountDetails.Add("-secretType", "Password")
                        $accountDetails.Add("-secret", $password)
                    } else {
                        $ssh_key = Get-Content -Path ".\Keys\$($account.Username.Trim())" | Out-String
                        $ssh_key_secure = ConvertTo-SecureString -String $ssh_key -AsPlainText -Force
                        $accountDetails.Add("-secretType", "key")
                        $accountDetails.Add("-secret", $ssh_key_secure)
                    }
                } 
                elseif($param -eq "PlatformID") { # Password value needs to be secure string instead of plaintext
                    $accountDetails.Add("-$param", $account."$param".replace(' ',''))
                }else { # normal properties, address, username etc
                    $accountDetails.Add("-$param", $account."$param")
                }
            }
        }
    }

    # Logon Account
    # LogonAccount, LogonHostname, LogonSafe, LogonPlatform
    if($account.LogonAccount -ne "" -and $null -ne $account.LogonAccount) {

        $tab_ = $tab + $send
        Write-Host "$($tab_)Searching for Logon Account: " -f Cyan -NoNewline; Write-Host "$($account.LogonAccount) $($account.LogonHostname) $($account.LogonSafe)"

        # search for Logon by hostname
        $logonSearch = @{
            "username" = $account.LogonAccount;
            "platformid" = $account.LogonPlatform;
            "safename" = $account.LogonSafe;
            "platformAccountProperties\hostname" = $account.LogonHostname;
        }
        $logonAccount = Get-Account -Search $logonSearch
        if($null -eq $logonAccount) {
            # search again for Logon by address
            $logonSearch = @{
                "username" = $account.LogonAccount;
                "platformid" = $account.LogonPlatform;
                "safename" = $account.LogonSafe;
                "address" = $account.LogonHostname;
            }
            $logonAccount = Get-Account -Search $logonSearch
        }

        # if logon_account is still $null, then we error
        if($null -eq $logonAccount) {
            $tab_ = $tab + $receive
            Write-Host "$($tab_)" -f Cyan -NoNewline; Write-Host "Unable to find Logon Account, skipping" -f Red
            Write-Host ""
            #Add-AccountLog -LogDir $LogDir -Success $false -Account $account -Comment "Unable to find Logon Account, skipping" -LogonAccount $apiAccount
            $failAccounts += $account
            $failCount++
            $rowIndex++
            continue
        }

        if(!($accountDetails.Keys -contains "-platformAccountProperties")) {
            $accountDetails.Add("-platformAccountProperties", @{})
        }

        # Add properties, ExtraPass parameters should be added to the platform
        $accountDetails."-platformAccountProperties".Add("ExtraPass1Folder", "root")
        $accountDetails."-platformAccountProperties".Add("ExtraPass1Safe", $logonAccount.safename)
        $accountDetails."-platformAccountProperties".Add("ExtraPass1Name", $logonAccount.name)
        
        $tab_ = $tab + $receive
        Write-Host "$($tab_)Found: " -f Cyan -NoNewline; Write-Host "$($logonAccount.name)"

    }

    # Reconcile Account
    # ReconAccountName, ReconHostname, ReconSafe, ReconPlatform
    if($account.ReconAccountName -ne "" -and $null -ne $account.ReconAccountName) {

        $tab_ = $tab + $send
        Write-Host "$($tab_)Searching for Recon Account: " -f Cyan -NoNewline; Write-Host "$($account.ReconAccountName) $($account.ReconHostname) $($account.ReconSafe)"

        # search for Recon by hostname
        $reconSearch = @{
            "username" = $account.ReconAccountName;
            "platformid" = $account.ReconPlatform;
            "safename" = $account.ReconSafe;
            "platformAccountProperties\hostname" = $account.ReconHostname;
        }
        $reconAccount = Get-Account -Search $reconSearch
        if($null -eq $reconAccount) {
            # search again for Recon by address
            $reconSearch = @{
                "username" = $account.ReconAccountName;
                "platformid" = $account.ReconPlatform;
                "safename" = $account.ReconSafe;
                "address" = $account.ReconHostname;
            }
            $reconAccount = Get-Account -Search $reconSearch
        }

        # if logon_account is still $null, then we error
        if($null -eq $reconAccount) {
            $tab_ = $tab + $receive
            Write-Host "$($tab_)" -f Cyan -NoNewline; Write-Host "Unable to find Recon Account, skipping" -f Red
            Write-Host ""
            #Add-AccountLog -LogDir $LogDir -Success $false -Account $account -Comment "Unable to find Recon Account, skipping" -LogonAccount $apiAccount
            $failAccounts += $account
            $failCount++
            $rowIndex++
            continue
        }

        if(!($accountDetails.Keys -contains "-platformAccountProperties")) {
            $accountDetails.Add("-platformAccountProperties", @{})
        }

        # Add properties, ExtraPass parameters should be added to the platform
        $accountDetails."-platformAccountProperties".Add("ExtraPass3Folder", "root")
        $accountDetails."-platformAccountProperties".Add("ExtraPass3Safe", $reconAccount.safename)
        $accountDetails."-platformAccountProperties".Add("ExtraPass3Name", $reconAccount.name)
        
        $tab_ = $tab + $receive
        Write-Host "$($tab_)Found: " -f Cyan -NoNewline; Write-Host "$($reconAccount.name)"

    }

    # onboarding time
    try {

        $r = Add-PASAccount @accountDetails # Onboard account

        if($r) {
			
            $tab_ = $tab + $receive
            Write-Host "$($tab_)Successfully Onboarded" -f Green
            $successCount++
			
            #Add-AccountLog -LogDir $LogDir -Success $true -Account $account -LogonAccount $apiAccount -APIDetails $r
            
            if($action -ne "None") {
                try {
                    if($action -eq "Verify") {
                        # Verify
                        Invoke-PASCPMOperation -AccountID $r.id -VerifyTask
                    } elseif($action -eq "Change") {
                        # Change
                        Invoke-PASCPMOperation -AccountID $r.id -ChangeTask
                    } elseif($action -eq "Reconcile") {
                        # Verify
                        Invoke-PASCPMOperation -AccountID $r.id -ReconcileTask
                    }
                    
                    $tab_ = $tab + $receive
                    Write-Host "$($tab_)Account set to: " -f Cyan -NoNewline; Write-Host "$action"
                    
                } catch {
                    $tab_ = $tab + $receive
                    Write-Host "$($tab_)Unable to set account to $action" -f Red
                    Write-Host "$_" -f Red
                }
            }
            
        }
        
    } catch {
        $tab_ = $tab + $receive
        Write-Host "$($tab_)" -f Cyan -NoNewline; Write-Host "Error while onboarding account:" -f Red
        Write-Host "$_" -f Red
        #Add-AccountLog -LogDir $LogDir -Success $false -Account $account -Comment "$_" -LogonAccount $apiAccount
        $failAccounts += $account
        $failCount++
    }
    Write-Host ""
    $rowIndex++
}

Write-Host "Finished" -f Cyan
Write-Host "Total: " -f Cyan -NoNewLine; Write-Host "$inputTotal"
Write-Host "Success: " -f Cyan -NoNewLine; Write-Host "$successCount" -f Green
Write-Host "Fails: " -f Cyan -NoNewLine; Write-Host "$failCount" -f Red

# If failures, output failed accounts to csv
if($failCount -gt 0) {
    if(!(Test-Path "./Failures")) {
        $null = New-Item -Name "Failures" -ItemType "directory"
    }
    $failDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("./Failures/Failures-$(Get-Date -Format 'dd-MM-yyyy HH-mm').csv") # Specific to VF
    Write-Host "Saving failures to: " -f Cyan -NoNewLine; Write-Host "$failDir"
    $failAccounts | Export-Csv -Path $failDir -NoTypeInformation
}

Write-Host ""
# END