# =============================================================================
# Le Keeper des Vets — démarrage en un clic
#
# Ce script est appelé par demarrer.cmd, à la racine du projet.
# Il vérifie l'environnement, prépare la base au besoin, ouvre le navigateur
# dès que le serveur répond, puis affiche les journaux du serveur.
#
# Arrêter le serveur : Ctrl+C dans cette fenêtre.
# =============================================================================

$ErrorActionPreference = 'Stop'
$PORT = 8787
$URL = "http://127.0.0.1:$PORT/"

# Se placer à la racine du projet, quel que soit l'endroit d'où on lance.
Set-Location (Split-Path $PSScriptRoot -Parent)

function Titre($texte) {
    Write-Host ""
    Write-Host "  $texte" -ForegroundColor Cyan
}
function Info($texte) { Write-Host "  $texte" -ForegroundColor Gray }
function Ok($texte) { Write-Host "  [ok] $texte" -ForegroundColor Green }
function Souci($texte) { Write-Host "  [!] $texte" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "     Le Keeper des Vets - demarrage" -ForegroundColor Cyan
Write-Host "  ================================================" -ForegroundColor Cyan

# --- Le serveur tourne-t-il déjà ? -------------------------------------------
$dejaEnMarche = $false
try {
    Invoke-WebRequest $URL -UseBasicParsing -TimeoutSec 3 | Out-Null
    $dejaEnMarche = $true
} catch { }

if ($dejaEnMarche) {
    Titre "Le serveur tourne deja sur le port $PORT."
    Info "Ouverture du navigateur..."
    Start-Process $URL
    Write-Host ""
    Info "Rien d'autre a faire. Tu peux fermer cette fenetre."
    Write-Host ""
    Start-Sleep -Seconds 3
    exit 0
}

# --- Node.js ------------------------------------------------------------------
Titre "Verification de l'environnement"
try {
    $versionNode = (& node --version).Trim()
    Ok "Node.js $versionNode"
} catch {
    Souci "Node.js est introuvable."
    Info "Installe-le depuis https://nodejs.org (version 20 ou plus recente)."
    exit 1
}

# --- Dépendances --------------------------------------------------------------
if (-not (Test-Path 'node_modules')) {
    Titre "Premiere utilisation : installation des dependances"
    Info "Cette etape ne se produit qu'une fois, compte une minute ou deux."
    & npm install
    if ($LASTEXITCODE -ne 0) {
        Souci "L'installation des dependances a echoue."
        exit 1
    }
    Ok "Dependances installees"
} else {
    Ok "Dependances presentes"
}

# --- Secrets locaux -----------------------------------------------------------
if (-not (Test-Path '.dev.vars')) {
    Titre "Configuration du mot de passe administrateur"
    Copy-Item '.dev.vars.example' '.dev.vars'
    Souci "Le fichier .dev.vars vient d'etre cree avec des valeurs par defaut."
    Info "Ouvre-le et remplace ADMIN_PASSWORD par ton vrai mot de passe,"
    Info "puis relance ce script."
    Info ""
    Info "Fichier : $((Resolve-Path '.dev.vars').Path)"
    Write-Host ""
    Read-Host "  Appuie sur Entree pour ouvrir le fichier"
    Start-Process notepad '.dev.vars'
    exit 0
}
Ok "Secrets locaux presents (.dev.vars)"

# --- Base de données ----------------------------------------------------------
# « migrations apply » est idempotent : il n'applique que ce qui manque.
Titre "Mise a jour de la base de donnees locale"
& npx wrangler d1 migrations apply keepervets --local 2>&1 |
    Where-Object { $_ -match 'No migrations|migrations to be applied|✅|Error|error' } |
    ForEach-Object { Info $_ }

if ($LASTEXITCODE -ne 0) {
    Souci "La preparation de la base a echoue. Le serveur va tout de meme demarrer."
} else {
    Ok "Base de donnees a jour"
}

# --- Ouverture différée du navigateur ----------------------------------------
# Le navigateur ne s'ouvre qu'une fois le serveur reellement pret, sinon
# l'utilisateur tombe sur une page d'erreur.
$attente = Start-Job -ScriptBlock {
    param($url)
    for ($i = 0; $i -lt 90; $i++) {
        try {
            Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 2 | Out-Null
            Start-Process $url
            return
        } catch { Start-Sleep -Milliseconds 700 }
    }
} -ArgumentList $URL

# --- Serveur ------------------------------------------------------------------
Titre "Demarrage du serveur"
Info "Adresse : $URL"
Info "Le navigateur s'ouvrira automatiquement."
Write-Host ""
Write-Host "  Pense a cliquer sur 'Lancer le robot' pour rafraichir les donnees." -ForegroundColor Yellow
Write-Host "  Pour arreter le serveur : Ctrl+C" -ForegroundColor Yellow
Write-Host ""

try {
    & npx wrangler dev --port $PORT --local
} finally {
    Stop-Job $attente -ErrorAction SilentlyContinue
    Remove-Job $attente -Force -ErrorAction SilentlyContinue
    Write-Host ""
    Info "Serveur arrete."
}
