# Installa la CLI di Foglio (Windows). Nessun amministratore, nessun segreto.
#
# Il modo più corto, da qualunque PowerShell (o incollato nella chat di Claude Code / Codex):
#   irm https://foglio.online/cli/install.ps1 | iex
# Con il nome dell'IA da collegare (e, se vuoi, indirizzo e chiave pubblica):
#   $env:FOGLIO_AGENT = 'claude-code'; irm https://foglio.online/cli/install.ps1 | iex
# Oppure scaricato: powershell -ExecutionPolicy Bypass -File install.ps1 [-Agent <nome>] [-Url <supabase>] [-AnonKey <chiave pubblica>]
#
# Variabili: FOGLIO_AGENT, FOGLIO_URL, FOGLIO_ANON_KEY, FOGLIO_CLI_BASE (default https://foglio.online/cli), FOGLIO_INSTALL_DIR,
#            FOGLIO_YES=1 (installa Node senza chiedere, se manca), FOGLIO_NO_PATH=1 (non tocca il PATH: per le prove).
param(
  [string]$Url = $env:FOGLIO_URL,
  [string]$AnonKey = $env:FOGLIO_ANON_KEY,
  [string]$Agent = $env:FOGLIO_AGENT,
  [string]$Base = $(if ($env:FOGLIO_CLI_BASE) { $env:FOGLIO_CLI_BASE } else { 'https://foglio.online/cli' }),
  [string]$Dir = $(if ($env:FOGLIO_INSTALL_DIR) { $env:FOGLIO_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'foglio\bin' })
)

# Tutto in una funzione: con `| iex` un `exit` chiuderebbe la finestra dell'utente, un `return` no.
function Install-Foglio {
  param([string]$Url, [string]$AnonKey, [string]$Agent, [string]$Base, [string]$Dir)
  $ErrorActionPreference = 'Stop'

  function Test-NodeOk {
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) { return $false }
    & node -e "const [a,b]=process.versions.node.split('.').map(Number);process.exit(a>22||(a===22&&b>=13)?0:1)"
    return ($LASTEXITCODE -eq 0)
  }

  # 1. Node >= 22.13: se manca (o è vecchio) lo propone e lo installa con winget
  if (-not (Test-NodeOk)) {
    $have = Get-Command node -ErrorAction SilentlyContinue
    if ($have) { Write-Host "Node $(& node --version) è troppo vecchio: serve 22.13 o più recente." -ForegroundColor Yellow }
    else { Write-Host "Serve Node.js 22.13 o più recente (non l'ho trovato)." -ForegroundColor Yellow }
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
      $yes = ($env:FOGLIO_YES -eq '1')
      if (-not $yes) { $a = Read-Host "Lo installo ora con winget (OpenJS.NodeJS.LTS)? [S/n]"; $yes = ($a -eq '' -or $a -match '^[sSyY]') }
      if ($yes) {
        & winget install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
        # winget aggiorna il PATH di sistema, non quello di questa finestra: lo rileggo
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
      }
    }
    if (-not (Test-NodeOk)) {
      Write-Host "Node non è pronto. Installalo da https://nodejs.org (versione LTS), poi rilancia questo comando." -ForegroundColor Yellow
      return
    }
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
    if ($LASTEXITCODE -ne 0) { return }

    # 3. Installa: il file e il lanciatore (che scambia un aggiornamento rimasto accanto)
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    Copy-Item (Join-Path $tmp 'foglio.mjs') (Join-Path $Dir 'foglio.mjs.tmp') -Force
    Move-Item (Join-Path $Dir 'foglio.mjs.tmp') (Join-Path $Dir 'foglio.mjs') -Force
    $cmd = "@echo off`r`nif exist `"%~dp0foglio.mjs.new`" (move /y `"%~dp0foglio.mjs.new`" `"%~dp0foglio.mjs`" >nul 2>&1 & del `"%~dp0foglio.mjs.new.json`" >nul 2>&1)`r`nnode `"%~dp0foglio.mjs`" %*`r`n"
    Set-Content -Path (Join-Path $Dir 'foglio.cmd') -Value $cmd -Encoding ASCII
  } finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }

  # 4. PATH dell'utente (senza amministratore): vale subito in questa finestra e nelle prossime
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($env:FOGLIO_NO_PATH -ne '1' -and ($userPath -split ';') -notcontains $Dir) {
    [Environment]::SetEnvironmentVariable('Path', ($(if ($userPath) { "$userPath;" } else { '' }) + $Dir), 'User')
    Write-Host "Aggiunto $Dir al PATH dell'utente."
  }
  if (($env:Path -split ';') -notcontains $Dir) { $env:Path = "$env:Path;$Dir" }
  # Avvisa le finestre del sistema che l'ambiente è cambiato (i programmi nuovi vedono il PATH aggiornato); i terminali già aperti no.
  try {
    Add-Type -Namespace Foglio -Name Native -MemberDefinition '[DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);' -ErrorAction Stop
    $r = [UIntPtr]::Zero
    [void][Foglio.Native]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$r)
  } catch { }
  Write-Host "Installata: $(Join-Path $Dir 'foglio.cmd') ($(& node (Join-Path $Dir 'foglio.mjs') --version))"
  Write-Host "Se usi Claude Code, Codex o un altro terminale GIA' APERTO, `foglio` non è ancora nel suo PATH: riaprilo, oppure usa il percorso completo: $(Join-Path $Dir 'foglio.cmd')"

  # 5. Collega la macchina (il browser si apre da solo per l'approvazione)
  if ($Agent) {
    $loginArgs = @('login', '--agent', $Agent)
    if ($Url) { $loginArgs += @('--url', $Url) }
    if ($AnonKey) { $loginArgs += @('--anon-key', $AnonKey) }
    & node (Join-Path $Dir 'foglio.mjs') @loginArgs
  } else {
    Write-Host "Per collegare questa macchina:  foglio login --agent <nome>   (es. claude-code, codex)"
  }
}

Install-Foglio -Url $Url -AnonKey $AnonKey -Agent $Agent -Base $Base -Dir $Dir
