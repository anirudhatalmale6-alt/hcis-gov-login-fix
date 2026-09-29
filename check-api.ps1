<#
  HCIS - check the sign-in path the BROWSER actually uses.

  diagnose.sql asks the database whether hcis_login exists. That is a true
  answer about the wrong layer. The browser does not talk to the database - it
  talks to PostgREST, which builds a cache of what it can call when it starts
  and does not notice functions added afterwards.

  On the Gov box the function was added in August and PostgREST was never
  restarted, so the database said yes, the API said "could not find the
  function", and the page reported that the system had not been set up. That
  cost several exchanges to find because the report said everything was fine.

  This walks the same path the browser walks and reports what each step says.
  It only reads.
#>

param(
    [string]$BaseUrl = 'http://localhost:3000'
)

function Say($m, $c = 'Gray') { Write-Host "  $m" -ForegroundColor $c }

Write-Host ''
Say '=== 7. The sign-in path the browser uses ==='
Write-Host ''

# --- is the API answering at all? ----------------------------------------
try {
    $root = Invoke-WebRequest -Uri $BaseUrl -UseBasicParsing -TimeoutSec 10
    Say ("PostgREST is answering on {0} (HTTP {1})" -f $BaseUrl, $root.StatusCode) 'Green'
} catch {
    Say ("PostgREST is NOT answering on {0}" -f $BaseUrl) 'Red'
    Say 'Nothing can sign in while that is the case. Run STEP-2-reload-api.bat.' 'Red'
    Say ("  ({0})" -f $_.Exception.Message) 'DarkGray'
    exit 0
}

# --- does the API know about the sign-in function? -----------------------
# Deliberately a password that cannot be right. A working API answers "no rows"
# or an empty list. An API with a stale cache says it cannot find the function,
# and that is the case we are hunting.
$body = @{ p_identifier = '__connectivity_check__'
           p_password   = '__not_a_real_password__' } | ConvertTo-Json -Compress

try {
    $r = Invoke-WebRequest -Uri ("{0}/rpc/hcis_login" -f $BaseUrl) -Method Post `
                           -ContentType 'application/json' -Body $body `
                           -UseBasicParsing -TimeoutSec 15
    Say ("The API knows hcis_login and answered HTTP {0}." -f $r.StatusCode) 'Green'
    Say 'Sign-in should work. If it still refuses, it is the password.' 'Green'
} catch {
    $resp = $_.Exception.Response
    $code = if ($resp) { [int]$resp.StatusCode } else { 0 }
    # Where the response body lives depends on the PowerShell version, and the
    # two boxes here do not agree. Windows PowerShell 5.1 leaves it on the
    # response stream; PowerShell 7 has already read the stream and puts the
    # text in ErrorDetails, so reading the stream there returns nothing and the
    # check silently falls through to the unhelpful branch. Try both.
    $text = ''
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
        $text = $_.ErrorDetails.Message
    } elseif ($resp) {
        try {
            $sr = New-Object IO.StreamReader($resp.GetResponseStream())
            $text = $sr.ReadToEnd()
        } catch {}
    }

    if ($text -match 'hcis_login' -and ($code -eq 404 -or $text -match 'Could not find')) {
        Say 'THE API DOES NOT KNOW ABOUT hcis_login.' 'Red'
        Say ''
        Say 'This is the fault. The function IS in the database - section 2' 'Red'
        Say 'above confirms it - but PostgREST caches what it can call when' 'Red'
        Say 'it starts, and it has not been restarted since the function was' 'Red'
        Say 'added. It will refuse every sign-in until it is.' 'Red'
        Say ''
        Say 'Fix: run STEP-2-reload-api.bat, then try signing in again.' 'Yellow'
    } elseif ($code -eq 401 -or $code -eq 403) {
        Say ("The API answered HTTP {0} - it knows the function but refused the call." -f $code) 'Yellow'
        Say 'That is a permissions problem, not a missing function. Send me this.' 'Yellow'
    } else {
        Say ("The API answered HTTP {0}." -f $code) 'Yellow'
        if ($text) { Say ("  {0}" -f $text.Substring(0, [Math]::Min(300, $text.Length))) 'DarkGray' }
    }
}

Write-Host ''
exit 0
