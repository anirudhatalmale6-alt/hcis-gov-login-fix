<#
  HCIS - put one account back into service.

  Prompts for the username and a new password, then hands both to the database.

  The password is typed masked and never leaves this script. An earlier version
  of this asked for it in the .bat with "set /p", which echoes every character
  to the screen - the client sent me a screenshot of the window and his new
  password was sitting there in plain text.

  Nor is the value passed back to the .bat through a for/f loop. That captures
  stdout, so the prompt text ends up glued to the front of the password. This
  script does the whole job itself and the .bat only launches it.

  -Username and -Password exist so this can be driven non-interactively by a
  test. Use the prompts in real life.
#>

param(
    [string]$Username = '',
    [string]$Password = '',
    [string]$Db       = 'hcis_db',
    [string]$DbUser   = 'postgres',
    # The DATABASE password, which is not the same thing as the account
    # password this script sets. Without it psql stops and asks for it, and the
    # window sits there apparently frozen mid-reset. That is exactly what
    # happened to the client on 30 September: his new password had been
    # accepted and the script then stalled before it could save it.
    [string]$DbPassword = 'HcisStaging@2026',
    [string]$PgBin    = '',
    [string]$ApiUrl   = 'http://localhost:3000'
)

$ErrorActionPreference = 'Stop'
function Say($m, $c = 'Gray') { Write-Host "  $m" -ForegroundColor $c }

$sql = Join-Path $PSScriptRoot 'sql\reset_login.sql'
if (-not (Test-Path $sql)) {
    Say 'This is not unpacked - sql\reset_login.sql is not next to this script.' 'Red'
    Say 'Right-click the zip, Extract All, then run it from that folder.' 'Red'
    exit 1
}

if (-not $PgBin) {
    $PgBin = @('C:\PostgreSQL\16\bin', 'C:\PostgreSQL\17\bin',
               'C:\Program Files\PostgreSQL\16\bin', 'C:\Program Files\PostgreSQL\17\bin') |
             Where-Object { Test-Path (Join-Path $_ 'psql.exe') } | Select-Object -First 1
}
if (-not $PgBin) { Say 'psql.exe was not found on this machine.' 'Red'; exit 1 }
$psql = Join-Path $PgBin 'psql.exe'

if ($DbPassword -and -not $env:PGPASSWORD) { $env:PGPASSWORD = $DbPassword }

Write-Host ''
Say 'This sets a new password for ONE account, switches it back on and'
Say 'clears any lockout. No other account is touched.'
Write-Host ''

if (-not $Username) { $Username = Read-Host '  Username (from the list in step 1)' }
if (-not $Username) { Say 'Nothing typed. Stopping without changing anything.' 'Yellow'; exit 1 }

if (-not $Password) {
    # Masked, and asked twice - a typo here locks the account out of reach until
    # somebody runs this again.
    $a = Read-Host '  New password (at least 10 characters)' -AsSecureString
    $b = Read-Host '  Type it again' -AsSecureString

    $pa = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($a)
    $pb = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($b)
    try {
        $s1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto($pa)
        $s2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto($pb)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pa)
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pb)
    }

    if ($s1 -cne $s2) { Say 'Those two do not match. Nothing was changed.' 'Red'; exit 1 }
    $Password = $s1
}

if (-not $Password) { Say 'Nothing typed. Stopping without changing anything.' 'Yellow'; exit 1 }

Write-Host ''
Say ("Setting the password for `"{0}`" ..." -f $Username)
Write-Host ''

& $psql -q -U $DbUser -d $Db -v ON_ERROR_STOP=1 `
        -v ("usr=" + $Username) -v ("pwd=" + $Password) -f $sql
$rc = $LASTEXITCODE

Write-Host ''
if ($rc -ne 0) {
    Say '------------------------------------------------------------' 'Red'
    Say 'IT DID NOT WORK. Nothing was changed.' 'Red'
    Say 'The message above usually says the username does not exist on' 'Red'
    Say 'this box. Run step 1 to see the real list of usernames.' 'Red'
    Say '------------------------------------------------------------' 'Red'
    exit 1
}

# ---- sign in for real, over the same path the browser uses ---------------
# The database check above proves the stored hash matches. It does NOT prove
# anyone can sign in: the browser goes through PostgREST, and PostgREST can be
# stopped, or serving a schema cache that predates the login function. That gap
# cost a whole morning once, so this now goes the whole way.
Say '=== signing in through the API, exactly as the browser does ==='
Write-Host ''

$loginBody = @{ p_identifier = $Username; p_password = $Password } | ConvertTo-Json -Compress
$apiVerdict = 'unknown'
try {
    $r = Invoke-WebRequest -Uri ("{0}/rpc/hcis_login" -f $ApiUrl) -Method Post `
                           -ContentType 'application/json' -Body $loginBody `
                           -UseBasicParsing -TimeoutSec 15
    # A successful sign-in returns one row carrying a token. An empty list means
    # the function ran and refused the credentials.
    if ($r.Content -match '"token"') {
        $apiVerdict = 'ok'
        Say 'CONFIRMED - these exact credentials sign in through the API.' 'Green'
        Say 'Nothing else is in the way. Type them into the browser.' 'Green'
    } else {
        $apiVerdict = 'refused'
        Say 'The API ran the sign-in and refused these credentials.' 'Red'
        Say 'That should not happen straight after a reset - tell me.' 'Red'
    }
} catch {
    $resp = $_.Exception.Response
    $code = if ($resp) { [int]$resp.StatusCode } else { 0 }
    $text = ''
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $text = $_.ErrorDetails.Message }
    $apiVerdict = 'unreachable'

    if ($code -eq 0) {
        Say 'The API is not answering at all.' 'Red'
        Say 'The password is set correctly, but nobody can sign in until' 'Red'
        Say 'PostgREST is running. Run STEP-2-reload-api.bat.' 'Yellow'
    } elseif ($text -match 'hcis_login') {
        Say 'The API does not know about the sign-in function.' 'Red'
        Say 'Run STEP-2-reload-api.bat, then try again.' 'Yellow'
    } else {
        Say ("The API answered HTTP {0}." -f $code) 'Red'
        if ($text) { Say ("  {0}" -f $text.Substring(0, [Math]::Min(300, $text.Length))) 'DarkGray' }
    }
}

$Password = $null
[GC]::Collect()

Write-Host ''
Say '------------------------------------------------------------'
if ($apiVerdict -eq 'ok') {
    Say 'Done. Those credentials are proven to work, end to end.' 'Green'
    Write-Host ''
    Say 'Type the password by hand rather than relying on memory, and'
    Say 'watch for the difference between a two digit and a four digit'
    Say 'year - that has caught us once already today.'
} else {
    Say 'The password was set, but the sign-in path is not clear yet.'
    Say 'Read the message above - it says which part to fix.'
}
Say '------------------------------------------------------------'
exit 0
