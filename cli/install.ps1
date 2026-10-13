# Installa la CLI di Foglio (Windows). Nessun amministratore, nessun segreto.
# Uso: powershell -ExecutionPolicy Bypass -File install.ps1 [-Url <supabase>] [-AnonKey <chiave pubblica>] [-Agent <nome>]
# Variabili: FOGLIO_CLI_BASE (default https://foglio.online/cli), FOGLIO_INSTALL_DIR
param(
  [string]$Url = $env:FOGLIO_URL,
  [string]$AnonKey = $env:FOGLIO_ANON_KEY,
  [string]$Agent = $env:FOGLIO_AGENT,
  [string]$Base = $(if ($env:FOGLIO_CLI_BASE) { $env:FOGLIO_CLI_BASE } else { 'https://foglio.online/cli' }),
  [string]$Dir = $(if ($env:FOGLIO_INSTALL_DIR) { $env:FOGLIO_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'foglio\bin' })
)
$ErrorActionPreference = 'Stop'

# 1. Node >= 22.13
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
  Write-Host "Serve Node.js 22.13 o piu' recente (non l'ho trovato)." -ForegroundColor Yellow
  Write-Host "Installalo con:  winget install OpenJS.NodeJS.LTS   (oppure da https://nodejs.org), poi rilancia questo script."
  exit 1
}
& node -e "const [a,b]=process.versions.node.split('.').map(Number);process.exit(a>22||(a===22&&b>=13)?0:1)"
if ($LASTEXITCODE -ne 0) {
  Write-Host "Node $(& node --version) e' troppo vecchio: serve 22.13 o piu' recente (winget upgrade OpenJS.NodeJS.LTS)." -ForegroundColor Yellow
  exit 1
}

# 2. Scarica e controlla (impronta e firma con la chiave pubblica, usando lo stesso Node)
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("foglio-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  Invoke-WebRequest -UseBasicParsing "$Base/latest.json" -OutFile (Join-Path $tmp 'latest.json')
  $meta = Get-Content (Join-Path $tmp 'latest.json') -Raw | ConvertFrom-Json
  $file = if ($meta.file) { $meta.file } else { 'foglio.mjs' }
  Invoke-WebRequest -UseBasicParsing "$Base/$file" -OutFile (Join-Path $tmp 'foglio.mjs')
  $verify = @'
const c=require("crypto"),fs=require("fs");
const m=JSON.parse(fs.readFileSync(process.argv[2],"utf8")), f=fs.readFileSync(process.argv[3]);
const sha=c.createHash("sha256").update(f).digest("hex");
if(sha!==m.sha256){console.error("impronta del file non valida: installazione annullata");process.exit(1)}
const key=c.createPublicKey({key:Buffer.concat([Buffer.from("302a300506032b6570032100","hex"),Buffer.from("PjwWEaVADPDTyeOJ81K7oMqFG/0p7azy0BxVjAuMJlU=","base64")]),format:"der",type:"spki"});
if(!m.signature||!c.verify(null,Buffer.from(sha),key,Buffer.from(m.signature,"base64"))){console.error("firma non valida: installazione annullata");process.exit(1)}
console.log("Versione "+m.version+": impronta e firma verificate.");
'@
  $vf = Join-Path $tmp 'verify.cjs'
  Set-Content -Path $vf -Value $verify -Encoding ASCII
  & node $vf (Join-Path $tmp 'latest.json') (Join-Path $tmp 'foglio.mjs')
  if ($LASTEXITCODE -ne 0) { exit 1 }

  # 3. Installa: il file e il lanciatore (che scambia un aggiornamento rimasto accanto)
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  Copy-Item (Join-Path $tmp 'foglio.mjs') (Join-Path $Dir 'foglio.mjs.tmp') -Force
  Move-Item (Join-Path $Dir 'foglio.mjs.tmp') (Join-Path $Dir 'foglio.mjs') -Force
  $cmd = "@echo off`r`nif exist `"%~dp0foglio.mjs.new`" (move /y `"%~dp0foglio.mjs.new`" `"%~dp0foglio.mjs`" >nul 2>&1 & del `"%~dp0foglio.mjs.new.json`" >nul 2>&1)`r`nnode `"%~dp0foglio.mjs`" %*`r`n"
  Set-Content -Path (Join-Path $Dir 'foglio.cmd') -Value $cmd -Encoding ASCII
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# 4. PATH dell'utente (senza amministratore)
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $Dir) {
  [Environment]::SetEnvironmentVariable('Path', ($(if ($userPath) { "$userPath;" } else { '' }) + $Dir), 'User')
  $env:Path = "$env:Path;$Dir"
  Write-Host "Aggiunto $Dir al PATH dell'utente: apri un nuovo terminale."
}
Write-Host "Installata: $(Join-Path $Dir 'foglio.cmd') ($(& node (Join-Path $Dir 'foglio.mjs') --version))"

# 5. Collega la macchina
if ($Agent) {
  $loginArgs = @('login', '--agent', $Agent)
  if ($Url) { $loginArgs += @('--url', $Url) }
  if ($AnonKey) { $loginArgs += @('--anon-key', $AnonKey) }
  & node (Join-Path $Dir 'foglio.mjs') @loginArgs
} else {
  Write-Host "Per collegare questa macchina:  foglio login --agent <nome>   (es. claude-code, codex)"
}
