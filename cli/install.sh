#!/bin/sh
# Installa la CLI di Foglio (Mac/Linux). Nessun amministratore, nessun segreto.
# Uso: curl -fsSL https://foglio.online/cli/install.sh | sh -s -- [--url <supabase>] [--anon-key <chiave pubblica>] [--agent <nome>]
# Variabili: FOGLIO_CLI_BASE (default https://foglio.online/cli), FOGLIO_INSTALL_DIR, FOGLIO_URL, FOGLIO_ANON_KEY, FOGLIO_AGENT
set -eu

BASE="${FOGLIO_CLI_BASE:-https://foglio.online/cli}"
DIR="${FOGLIO_INSTALL_DIR:-$HOME/.local/share/foglio/bin}"
URL="${FOGLIO_URL:-}"; ANON="${FOGLIO_ANON_KEY:-}"; AGENT="${FOGLIO_AGENT:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --url) URL="$2"; shift 2 ;;
    --anon-key) ANON="$2"; shift 2 ;;
    --agent) AGENT="$2"; shift 2 ;;
    *) echo "opzione sconosciuta: $1" >&2; exit 1 ;;
  esac
done

# 1. Node >= 22.13
if ! command -v node >/dev/null 2>&1; then
  echo "Serve Node.js 22.13 o più recente (non l'ho trovato)." >&2
  echo "Installalo da https://nodejs.org (versione LTS) oppure con nvm: nvm install 22. Poi rilancia questo comando." >&2
  exit 1
fi
if ! node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>22||(a===22&&b>=13)?0:1)'; then
  echo "Node $(node --version) è troppo vecchio: serve 22.13 o più recente (https://nodejs.org)." >&2
  exit 1
fi

# 2. Scarica e controlla (impronta e firma con la chiave pubblica, usando lo stesso Node)
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fetch() { if command -v curl >/dev/null 2>&1; then curl -fsSL "$1" -o "$2"; else wget -q "$1" -O "$2"; fi; }
fetch "$BASE/latest.json" "$TMP/latest.json"
FILE="$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).file||"foglio.mjs")' "$TMP/latest.json")"
fetch "$BASE/$FILE" "$TMP/foglio.mjs"
node -e '
const c=require("crypto"),fs=require("fs");
const m=JSON.parse(fs.readFileSync(process.argv[1],"utf8")), f=fs.readFileSync(process.argv[2]);
const sha=c.createHash("sha256").update(f).digest("hex");
if(sha!==m.sha256){console.error("impronta del file non valida: installazione annullata");process.exit(1)}
const key=c.createPublicKey({key:Buffer.concat([Buffer.from("302a300506032b6570032100","hex"),Buffer.from("PjwWEaVADPDTyeOJ81K7oMqFG/0p7azy0BxVjAuMJlU=","base64")]),format:"der",type:"spki"});
if(!m.signature||!c.verify(null,Buffer.from(sha),key,Buffer.from(m.signature,"base64"))){console.error("firma non valida: installazione annullata");process.exit(1)}
console.log("Versione "+m.version+": impronta e firma verificate.");
' "$TMP/latest.json" "$TMP/foglio.mjs"

# 3. Installa: il file e il lanciatore (che scambia un aggiornamento rimasto accanto)
mkdir -p "$DIR"
cp "$TMP/foglio.mjs" "$DIR/foglio.mjs.tmp" && mv "$DIR/foglio.mjs.tmp" "$DIR/foglio.mjs"
cat > "$DIR/foglio" <<'EOS'
#!/bin/sh
D="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$D/foglio.mjs.new" ]; then mv -f "$D/foglio.mjs.new" "$D/foglio.mjs" 2>/dev/null; rm -f "$D/foglio.mjs.new.json"; fi
exec node "$D/foglio.mjs" "$@"
EOS
chmod +x "$DIR/foglio"

# 4. PATH dell'utente (una volta sola)
case ":$PATH:" in
  *":$DIR:"*) ;;
  *)
    LINE="export PATH=\"$DIR:\$PATH\" # foglio"
    for rc in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
      [ -f "$rc" ] || continue
      grep -q '# foglio$' "$rc" 2>/dev/null || printf '\n%s\n' "$LINE" >> "$rc"
    done
    [ -f "$HOME/.profile" ] || printf '%s\n' "$LINE" > "$HOME/.profile"
    export PATH="$DIR:$PATH"
    echo "Aggiunto $DIR al PATH: apri un nuovo terminale."
    ;;
esac
echo "Installata: $DIR/foglio ($("$DIR/foglio" --version))"

# 5. Collega la macchina
if [ -n "$AGENT" ]; then
  set -- login --agent "$AGENT"
  [ -n "$URL" ] && set -- "$@" --url "$URL"
  [ -n "$ANON" ] && set -- "$@" --anon-key "$ANON"
  "$DIR/foglio" "$@"
else
  echo "Per collegare questa macchina: foglio login --agent <nome>   (es. claude-code, codex)"
fi
