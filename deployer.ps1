# =============================================================================
# Le Keeper des Vets — déploiement sur Cloudflare
#
# Appelé par deployer.cmd, à la racine du projet.
#
# Le script est ré-exécutable : il détecte ce qui est déjà en place et ne
# refait que ce qui manque. Aucun secret n'est écrit dans un fichier ni affiché.
# =============================================================================

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

function Titre($t) { Write-Host ""; Write-Host "  $t" -ForegroundColor Cyan }
function Info($t) { Write-Host "  $t" -ForegroundColor Gray }
function Ok($t) { Write-Host "  [ok] $t" -ForegroundColor Green }
function Souci($t) { Write-Host "  [!] $t" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "     Deploiement sur Cloudflare" -ForegroundColor Cyan
Write-Host "  ================================================" -ForegroundColor Cyan

# --- Étape 1 : authentification ----------------------------------------------
Titre "1/5  Compte Cloudflare"
$identite = & npx wrangler whoami 2>&1 | Out-String

if ($identite -match 'not authenticated') {
    Info "Une page va s'ouvrir dans ton navigateur pour autoriser Wrangler."
    Info "Si tu n'as pas encore de compte : https://dash.cloudflare.com/sign-up"
    Info "(gratuit, aucune carte de credit requise)"
    Write-Host ""
    Read-Host "  Appuie sur Entree pour lancer la connexion"
    & npx wrangler login
    if ($LASTEXITCODE -ne 0) { Souci "Connexion echouee."; exit 1 }
    $identite = & npx wrangler whoami 2>&1 | Out-String
}

if ($identite -match 'not authenticated') { Souci "Toujours pas authentifie."; exit 1 }
Ok "Authentifie aupres de Cloudflare"

# --- Étape 2 : base de données D1 --------------------------------------------
Titre "2/5  Base de donnees D1"

$listeJson = & npx wrangler d1 list --json 2>$null | Out-String
$identifiant = $null
try {
    $bases = $listeJson | ConvertFrom-Json
    $identifiant = ($bases | Where-Object { $_.name -eq 'keepervets' } | Select-Object -First 1).uuid
} catch { }

if (-not $identifiant) {
    Info "Creation de la base 'keepervets'..."
    & npx wrangler d1 create keepervets | Out-Null
    Start-Sleep -Seconds 3
    $listeJson = & npx wrangler d1 list --json 2>$null | Out-String
    $identifiant = ($listeJson | ConvertFrom-Json | Where-Object { $_.name -eq 'keepervets' } | Select-Object -First 1).uuid
}

if (-not $identifiant) { Souci "Impossible d'obtenir l'identifiant de la base."; exit 1 }
Ok "Base D1 : $identifiant"

# Report de l'identifiant dans la configuration.
$config = Get-Content 'wrangler.jsonc' -Raw
if ($config -match '"database_id":\s*"00000000-0000-0000-0000-000000000000"') {
    $config = $config -replace '"database_id":\s*"00000000-0000-0000-0000-000000000000"', "`"database_id`": `"$identifiant`""
    Set-Content 'wrangler.jsonc' $config -Encoding UTF8 -NoNewline
    Ok "Identifiant reporte dans wrangler.jsonc"
} elseif ($config -match [regex]::Escape($identifiant)) {
    Ok "wrangler.jsonc deja configure"
} else {
    Souci "wrangler.jsonc contient un autre identifiant : verifie-le manuellement."
}

# --- Étape 3 : migrations ----------------------------------------------------
Titre "3/5  Schema de la base distante"
& npx wrangler d1 migrations apply keepervets --remote
if ($LASTEXITCODE -ne 0) { Souci "Les migrations ont echoue."; exit 1 }
Ok "Schema a jour"

# --- Étape 4 : publication ---------------------------------------------------
# La publication vient AVANT les secrets : « wrangler secret put » exige que le
# Worker existe déjà, sinon il échoue avec « Worker not found ».
Titre "4/5  Publication"
$sortie = & npx wrangler deploy 2>&1 | Out-String
Write-Host $sortie

if ($LASTEXITCODE -ne 0) { Souci "Le deploiement a echoue."; exit 1 }
Ok "Application publiee"

$adresse = ([regex]::Match($sortie, 'https://[a-z0-9.\-]+\.workers\.dev')).Value

# --- Étape 5 : secrets -------------------------------------------------------
Titre "5/5  Secrets"
Info "Ces valeurs sont saisies directement dans le terminal et envoyees a"
Info "Cloudflare. Elles ne transitent par aucun fichier."
Info "Elles sont appliquees immediatement : aucune republication n'est requise."
Write-Host ""

$secretsExistants = & npx wrangler secret list 2>&1 | Out-String

if ($secretsExistants -match 'ADMIN_PASSWORD') {
    Ok "ADMIN_PASSWORD deja defini"
} else {
    Info "Choisis un mot de passe administrateur SOLIDE."
    Info "N'utilise pas un mot de passe deja employe ailleurs."
    & npx wrangler secret put ADMIN_PASSWORD
    if ($LASTEXITCODE -ne 0) { Souci "Echec de l'enregistrement du mot de passe." }
}

if ($secretsExistants -match 'SESSION_SECRET') {
    Ok "SESSION_SECRET deja defini"
} else {
    # Clé aléatoire generee localement : elle sert uniquement a signer les
    # cookies de session, l'utilisateur n'a pas a la retenir.
    $cle = -join ((1..64) | ForEach-Object { '0123456789abcdef'[(Get-Random -Max 16)] })
    Info "Generation d'une cle de signature aleatoire..."
    $cle | & npx wrangler secret put SESSION_SECRET
    Remove-Variable cle
}
Ok "Secrets en place"

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Green
Write-Host "     Deploiement termine" -ForegroundColor Green
Write-Host "  ================================================" -ForegroundColor Green

if ($adresse) {
    Write-Host ""
    Info "Adresse de l'application :"
    Write-Host "     $adresse" -ForegroundColor Cyan
    Write-Host ""
    Info "Etapes suivantes :"
    Info " 1. Ouvre l'adresse, connecte-toi comme administrateur"
    Info " 2. Clique sur 'Lancer le robot' pour la premiere synchronisation"
    Info " 3. Le robot tournera ensuite tout seul aux 2 heures, 24 h sur 24"
    Write-Host ""
    Souci "Le premier remplissage du dictionnaire NHL s'etale sur quelques"
    Souci "executions : c'est normal, les donnees se completent progressivement."
}
