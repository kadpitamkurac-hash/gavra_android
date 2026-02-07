# Script to run Flutter app with environment variables from .env file
# Usage: .\run_with_env.ps1

# Read .env file and parse key-value pairs
$envVars = @{}
Get-Content ".env" | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') {
        $key = $matches[1].Trim()
        $value = $matches[2].Trim()
        $envVars[$key] = $value
    }
}

# Build the flutter run command with --dart-define arguments
$command = "flutter run"
foreach ($key in $envVars.Keys) {
    $value = $envVars[$key]
    $command += " --dart-define $key=`"$value`""
}

Write-Host "Running: $command" -ForegroundColor Cyan

# Execute the command
Invoke-Expression $command