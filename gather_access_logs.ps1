# Set execution policy
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Set working directory
Set-Location -Path "C:\Scripts\Gather_CF_Access"

# Start logging
Start-Transcript -Path "C:\Scripts\Gather_CF_Access\LogFile.txt" -Append

# Function to load the .env file
function Load-EnvFile {
    param (
        [string]$envFilePath
    )

    if (-Not (Test-Path $envFilePath)) {
        # Create the .env file with example values
        @"
AUTH_EMAIL=your_email
AUTH_KEY=your_api_key
ACCOUNT_ID=your_account_id
ZONE_ID=your_zone_id
OUTPUT_LOCATION=logs
"@ | Out-File -FilePath $envFilePath -Encoding utf8

        Write-Output "The .env file was not found and has been created with example values. Please update it with your actual credentials."
        exit
    }

    # Load the .env file
    Get-Content $envFilePath | ForEach-Object {
        if ($_ -match "^(.*?)=(.*)$") {
            [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2].Trim())
        }
    }
}

# Function to check basic login
function Check-Login {
    param (
        [string]$authEmail,
        [string]$authKey
    )

    # Set the API endpoint for fetching account details
    $apiUrl = "https://api.cloudflare.com/client/v4/accounts"

    # Define the headers for the API request
    $headers = @{
        "X-Auth-Email" = $authEmail
        "X-Auth-Key"   = $authKey
        "Content-Type" = "application/json"
    }

    # Make the API request to fetch account details
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers
        if ($response.success) {
            Write-Output "Login successful. Your Account ID is: $($response.result[0].id)"
            return $true
        } else {
            Write-Error "Failed to fetch account details: $($response.errors)"
            return $false
        }
    } catch {
        Write-Error "Exception occurred: $_"
        return $false
    }
}

# Function to make the API request
function Fetch-AccessLogs {
    param (
        [string]$authEmail,
        [string]$authKey,
        [string]$accountId,
        [string]$startTime,
        [string]$endTime
    )

    # Set the API endpoint for fetching access logs
    $apiUrl = "https://api.cloudflare.com/client/v4/accounts/$accountId/access/logs/access_requests"

    # Define the headers for the API request
    $headers = @{
        "X-Auth-Email" = $authEmail
        "X-Auth-Key"   = $authKey
        "Content-Type" = "application/json"
    }

    # Define the parameters for the API request
    $params = @{
        "start" = $startTime
        "end"   = $endTime
    }

    # Make the API request to fetch the logs
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -Body ($params | ConvertTo-Json)
        return $response
    } catch {
        Write-Error "Exception occurred: $_"
        return $null
    }
}

# Function to save the logs to a file
function Save-Logs {
    param (
        [object]$logs,
        [string]$outputLocation
    )

    # Create the output folder if it doesn't exist
    if (-Not (Test-Path $outputLocation)) {
        New-Item -ItemType Directory -Path $outputLocation
    }

    # Generate the filename with the current date and time
    $currentDateTime = Get-Date -Format "yyyyMMdd_HHmmss"
    $filename = "access_logs_$currentDateTime.json"
    $filePath = Join-Path -Path $outputLocation -ChildPath $filename

    # Save the logs to the specified output location
    $logs | ConvertTo-Json | Out-File -FilePath $filePath
    Write-Output "Logs have been saved to $filePath"
}

# Main script
$envFilePath = ".env"
Load-EnvFile -envFilePath $envFilePath

# Retrieve the values from the environment variables
$authEmail = [System.Environment]::GetEnvironmentVariable("AUTH_EMAIL")
$authKey = [System.Environment]::GetEnvironmentVariable("AUTH_KEY")
$accountId = [System.Environment]::GetEnvironmentVariable("ACCOUNT_ID")
$outputLocation = [System.Environment]::GetEnvironmentVariable("OUTPUT_LOCATION")

# Check login
if (-Not (Check-Login -authEmail $authEmail -authKey $authKey)) {
    exit
}

# Define the start and end times for the logs
$startTime = (Get-Date).AddDays(-1).ToString("yyyy-MM-ddTHH:mm:ssZ")
$endTime = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")

# Fetch the access logs
$response = Fetch-AccessLogs -authEmail $authEmail -authKey $authKey -accountId $accountId -startTime $startTime -endTime $endTime

# Check if the request was successful
if ($response -and $response.success) {
    Save-Logs -logs $response.result -outputLocation $outputLocation
} else {
    Write-Error "Failed to fetch logs: $($response.errors)"
    Write-Output "Error details: $($response | ConvertTo-Json -Depth 10)"
}

# Stop logging
Stop-Transcript