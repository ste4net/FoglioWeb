# Rimuove Foglio (CLI, collegamenti per le IA, dati locali) da QUESTA macchina Windows. Da incollare in PowerShell.
# Prima mostra cosa trova, poi chiede conferma. Non tocca il cloud: l'accesso delle IA si revoca nell'app, in «IA con accesso ai tuoi Fogli».
# Prima di cambiare un file ne salva una copia accanto con estensione .foglio-bak.

$ErrorActionPreference = 'Stop'
$home_ = $env:USERPROFILE
$appData = Join-Path $env:APPDATA 'foglio'                 # sessioni degli agenti, archivi locali
$binDir = Join-Path $env:LOCALAPPDATA 'foglio'             # CLI installata (foglio.mjs, lanciatore)
$codexToml = Join-Path $home_ '.codex\config.toml'
$codexMd = Join-Path $home_ '.codex\AGENTS.md'
$skillDir = Join-Path $home_ '.claude\skills\foglio'
$claudeSettings = Join-Path $home_ '.claude\settings.json'
$claudeJson = Join-Path $home_ '.claude.json'
$repoDefault = 'C:\X_LAV\AllTech\FoglioCli'                # copia del repository sulla seconda macchina (se c'è)

function Has($path, $needle) { (Test-Path $path) -and ((Get-Content $path -Raw -ErrorAction SilentlyContinue) -match [regex]::Escape($needle)) }

$piano = @()
if (Test-Path $appData)  { $n = @(Get-ChildItem $appData -Recurse -Filter *.sqlite -ErrorAction SilentlyContinue).Count; $piano += "Profilo locale $appData (sessioni degli agenti, indirizzo, $n archivio/i SQLite: ciò che non è stato inviato al cloud si perde)" }
if (Test-Path $binDir)   { $piano += "CLI installata $binDir e voce nel PATH dell'utente" }
if (Has $codexToml '# foglio:begin')        { $piano += "Collegamento MCP di Codex in $codexToml" }
if (Has $codexMd '<!-- foglio')             { $piano += "Regole e skill di Foglio in $codexMd" }
if (Test-Path $skillDir)                    { $piano += "Skill di Claude Code $skillDir" }
if (Has $claudeSettings 'hook pre-tool-use'){ $piano += "Hook di Foglio in $claudeSettings" }
if (Has $claudeSettings 'sqlite3')          { $piano += "Regole di divieto di Foglio in $claudeSettings" }
if (Has $claudeJson '"foglio"')             { $piano += "Server MCP «foglio» in $claudeJson" }
if (Test-Path $repoDefault)                 { $piano += "(facoltativo, lo chiedo dopo) copia del repository in $repoDefault" }

if ($piano.Count -eq 0) { Write-Host 'Non trovo nulla di Foglio su questa macchina.'; return }
Write-Host "`nTrovato:" -ForegroundColor Cyan
$piano | ForEach-Object { Write-Host " - $_" }
Write-Host "`nChiudi prima Claude Code e Codex se sono aperti." -ForegroundColor Yellow
if ((Read-Host "Scrivi SI per rimuovere (altro = annulla)") -ne 'SI') { Write-Host 'Annullato, non ho toccato nulla.'; return }

function Backup($p) { if (Test-Path $p) { Copy-Item $p "$p.foglio-bak" -Force } }

# Toglie da un file di testo i blocchi tra due marcatori (inclusi).
function StripBlocks($path, $pairs) {
  if (-not (Test-Path $path)) { return }
  Backup $path
  $t = Get-Content $path -Raw
  if (-not $t) { return }   # file vuoto: niente da togliere
  foreach ($p in $pairs) { $t = [regex]::Replace($t, "(?s)\r?\n?$([regex]::Escape($p[0])).*?$([regex]::Escape($p[1]))\r?\n?", "`n") }
  Set-Content $path $t.TrimEnd() -Encoding UTF8
}

# Codex
StripBlocks $codexToml @(,@('# foglio:begin', '# foglio:end'))
StripBlocks $codexMd @(@('<!-- foglio:begin', '<!-- foglio:end -->'), @('<!-- foglio-skill:begin', '<!-- foglio-skill:end -->'))

# Claude Code: skill, hook e regole di divieto
if (Test-Path $skillDir) { Remove-Item $skillDir -Recurse -Force }
if (Test-Path $claudeSettings) {
  Backup $claudeSettings
  $d = Get-Content $claudeSettings -Raw | ConvertFrom-Json
  if ($d.hooks -and $d.hooks.PreToolUse) {
    $keep = @($d.hooks.PreToolUse | Where-Object { ($_ | ConvertTo-Json -Depth 20 -Compress) -notmatch 'hook pre-tool-use' })
    if ($keep.Count) { $d.hooks.PreToolUse = $keep } else { $d.hooks.PSObject.Properties.Remove('PreToolUse') }
    if (-not @($d.hooks.PSObject.Properties).Count) { $d.PSObject.Properties.Remove('hooks') }
  }
  if ($d.permissions -and $d.permissions.deny) {
    $keep = @($d.permissions.deny | Where-Object { $_ -ne 'Bash(sqlite3:*)' -and $_ -notmatch '^(Read|Edit|Write)\(.*foglio.*\*\*\)$' })
    if ($keep.Count) { $d.permissions.deny = $keep } else { $d.permissions.PSObject.Properties.Remove('deny') }
    if (-not @($d.permissions.PSObject.Properties).Count) { $d.PSObject.Properties.Remove('permissions') }
  }
  $d | ConvertTo-Json -Depth 20 | Set-Content $claudeSettings -Encoding UTF8
}
if (Has $claudeJson '"foglio"') {
  Backup $claudeJson
  $j = Get-Content $claudeJson -Raw | ConvertFrom-Json
  foreach ($s in @($j) + @($j.projects.PSObject.Properties.Value)) { if ($s.mcpServers -and $s.mcpServers.foglio) { $s.mcpServers.PSObject.Properties.Remove('foglio') } }
  $j | ConvertTo-Json -Depth 30 | Set-Content $claudeJson -Encoding UTF8
}

# Profilo locale e CLI installata
if (Test-Path $appData) { Remove-Item $appData -Recurse -Force }
if (Test-Path $binDir) {
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  $new = ($userPath -split ';' | Where-Object { $_ -and ($_ -notlike "$binDir*") }) -join ';'
  [Environment]::SetEnvironmentVariable('Path', $new, 'User')
  Remove-Item $binDir -Recurse -Force
}

# Copia del repository (facoltativa)
if (Test-Path $repoDefault) {
  if ((Read-Host "Cancello anche la copia del repository $repoDefault ? (SI/no)") -eq 'SI') { Remove-Item $repoDefault -Recurse -Force; Write-Host 'Repository rimosso.' }
}

Write-Host "`nFatto. Copie dei file modificati: *.foglio-bak accanto agli originali (cancellale quando sei tranquillo)." -ForegroundColor Green
Write-Host "Ultimo passo, nell'app: «IA con accesso ai tuoi Fogli» -> revoca l'IA di questa macchina." -ForegroundColor Green
