[System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Ensure UTF‑8 for Python subprocesses
$Env:PYTHONIOENCODING = "utf-8"
$Env:PYTHONLEGACYWINDOWSSTDIO = "0"
chcp 65001 > $null

$projectRoot = "D:\\Anh Tuan\\VinAI\\TRACK2_Day20_2A202601582_HaAnhTuan"
Set-Location $projectRoot

# Path to the llama-server binary (used by lib\\labkit.py)
$llamaServer = Join-Path $projectRoot "runtime\\\\b10488\\\\llama-server.exe"
if (-not (Test-Path $llamaServer)) {
    Write-Error "Cannot find llama-server.exe at $llamaServer"
    exit 1
}
# Export variable that lib\\labkit.py will read (if it uses one)
$Env:LAB_SERVER_PORT = "8099"  # using default port 8099
$Env:LLAMA_SERVER_PATH = $llamaServer

# -------------------------------------------------
# 1️⃣ Start the Llama server as a background **Job**
# -------------------------------------------------
$serveLog = Join-Path $projectRoot "serve.log"
$serveJob = Start-Job -ScriptBlock {
    $Env:PYTHONIOENCODING = 'utf-8'
    $Env:PYTHONLEGACYWINDOWSSTDIO = '0'
    chcp 65001 > $null
    Set-Location $using:projectRoot
    $Env:LLAMA_SERVER_PATH = $using:llamaServer
    # Run the server and capture both stdout and stderr to serve.log
    & "$using:projectRoot\lab.ps1" serve *>&1 | Out-File -FilePath $using:serveLog -Encoding utf8
}

# -------------------------------------------------
# 2️⃣ Wait until the server is listening on port 8080 (max 90 s)
# -------------------------------------------------
$port = $Env:LAB_SERVER_PORT
if (-not $port) { $port = 8080 }
$maxWait = 90
$elapsed = 0
while ($elapsed -lt $maxWait) {
    if (Test-NetConnection -ComputerName localhost -Port $port -InformationLevel Quiet) { break }
    Start-Sleep -Seconds 3
    $elapsed += 3
}
if ($elapsed -ge $maxWait) {
    Write-Error "Server did not become reachable on port $port after $maxWait seconds."
    if ($serveJob.State -eq 'Running') { Stop-Job $serveJob }
    exit 1
}

# -------------------------------------------------
# 3️⃣ Smoke test
# -------------------------------------------------
& "$projectRoot\lab.ps1" smoke

# -------------------------------------------------
# 4️⃣ Load‑10 (Locust 10 users)
# -------------------------------------------------
& "$projectRoot\lab.ps1" load-10

# -------------------------------------------------
# 5️⃣ Load‑50 (Locust 50 users)
# -------------------------------------------------
& "$projectRoot\lab.ps1" load-50

# -------------------------------------------------
# 6️⃣ Clean‑up – stop the server job
# -------------------------------------------------
if ($serveJob.State -eq 'Running') {
    Stop-Job $serveJob | Out-Null
    Receive-Job $serveJob | Out-Null
    Remove-Job $serveJob | Out-Null
}
