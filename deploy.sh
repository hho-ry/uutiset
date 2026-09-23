#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# deploy-ghpages.sh
# Julkaisee hakemiston $HOME/sites/uutiset sisallon gh-pages-haaraan
# repoon haaga-helia-sko/uutiset -> https://haaga-helia-sko.github.io/uutiset/
# Ajettavissa niin usein kuin haluaa, myos cronista.
# ---------------------------------------------------------------------------
set -euo pipefail

GH_ORG="hho-ry"
GH_REPO="uutiset"
ROOT_REPO="hho-ry.github.io"
GH_USER="juhanurmonen"
BRANCH="gh-pages"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_ALIAS="gh-uutiset"
# 1 = Markdown-lahteet, GitHub kaantaa ne Jekyllilla (index.md -> index.html)
# 0 = valmiit HTML-tiedostot, Jekyll ohitetaan (.nojekyll)
JEKYLL=1
CUSTOM_DOMAIN=""          # jata tyhjaksi, jos ei omaa verkkotunnusta

# --- Valitaan toimiva yhteys (portti 22, varalla 443) -----------------------
REMOTE=""
for a in "$HOST_ALIAS" "${HOST_ALIAS}-443"; do
    if git ls-remote "git@${a}:${GH_ORG}/${GH_REPO}.git" >/dev/null 2>&1; then
        REMOTE="git@${a}:${GH_ORG}/${GH_REPO}.git"
        break
    fi
done
if [ -z "$REMOTE" ]; then
    echo "VIRHE: repoon ${GH_ORG}/${GH_REPO} ei saa yhteytta. Aja ./setup-ghpages.sh" >&2
    exit 1
fi

# --- Tarkistukset -----------------------------------------------------------
if [ ! -d "$SRC_DIR" ]; then
    echo "VIRHE: lahdehakemistoa ei ole: $SRC_DIR" >&2
    exit 1
fi
if [ -z "$(ls -A "$SRC_DIR")" ]; then
    echo "VIRHE: $SRC_DIR on tyhja, ei julkaista mitaan." >&2
    exit 1
fi

# Haetaan Ylen ammattikorkeakoulu-aiheen artikkelit palvelinpuolella.
if command -v python3 >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
    if curl -fsSL --max-time 30 'https://yle.fi/t/18-209712/fi' | python3 "$SRC_DIR/update-news.py" > "$SRC_DIR/news.json.tmp"; then
        mv "$SRC_DIR/news.json.tmp" "$SRC_DIR/news.json"
        echo "Ylen AMK-uutisdata päivitetty."
    else
        rm -f "$SRC_DIR/news.json.tmp"
        echo "VAROITUS: Ylen uutisdataa ei voitu päivittää, käytetään aiempaa news.json-tiedostoa." >&2
    fi
fi
if [ ! -f "$SRC_DIR/index.html" ] && [ ! -f "$SRC_DIR/index.md" ] && [ ! -f "$SRC_DIR/README.md" ]; then
    echo "VAROITUS: $SRC_DIR:ssa ei ole index.md, index.html eika README.md." >&2
    echo "          Sivuston juuri antaa 404." >&2
fi
if [ "$JEKYLL" -eq 1 ] && [ -f "$SRC_DIR/index.md" ]; then
    if ! head -n 1 "$SRC_DIR/index.md" | grep -q '^---[[:space:]]*$'; then
        echo "VAROITUS: index.md ei ala '---'-rivilla (YAML front matter)." >&2
        echo "          Jekyll ei kaanna tiedostoa, vaan se nakyy raakana." >&2
    fi
fi

# --- Tyohakemisto -----------------------------------------------------------
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ghpages.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

if git ls-remote --exit-code --heads "$REMOTE" "$BRANCH" >/dev/null 2>&1; then
    echo "Haetaan olemassa oleva haara $BRANCH..."
    git clone --quiet --depth 1 --branch "$BRANCH" "$REMOTE" "$WORK"
else
    echo "Haaraa $BRANCH ei ole, luodaan uusi..."
    git init --quiet "$WORK"
    git -C "$WORK" checkout --quiet -b "$BRANCH"
    git -C "$WORK" remote add origin "$REMOTE"
fi

git -C "$WORK" config user.name  "$GH_USER"
git -C "$WORK" config user.email "${GH_USER}@users.noreply.github.com"

# --- Sisallon korvaus -------------------------------------------------------
find "$WORK" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
find "$SRC_DIR" -mindepth 1 -maxdepth 1 ! -name '.git' -exec cp -a {} "$WORK"/ \;

if [ "$JEKYLL" -eq 0 ]; then
    # Ohitetaan Jekyll: HTML menee lapi sellaisenaan, _-alkuiset kansiot toimivat
    touch "$WORK/.nojekyll"
fi

if [ -n "$CUSTOM_DOMAIN" ]; then
    printf '%s\n' "$CUSTOM_DOMAIN" > "$WORK/CNAME"
fi

git -C "$WORK" add -A

if git -C "$WORK" diff --cached --quiet; then
    echo "Ei muutoksia, ei julkaista mitaan."
else
    git -C "$WORK" commit --quiet -m "Deploy from kapsi $(date '+%Y-%m-%d %H:%M:%S')"
    git -C "$WORK" push --quiet origin "HEAD:refs/heads/${BRANCH}"
    echo "Julkaistu."
fi
if [ -n "$CUSTOM_DOMAIN" ]; then
    echo "Osoite: https://${CUSTOM_DOMAIN}/"
else
    echo "Osoite: https://${GH_ORG}.github.io/${GH_REPO}/"
fi

# Jos organisaation Pages-juurirepo on olemassa, julkaise sinne redirect.
# GitHub Pages ei voi ohjata organisaation juurta projektireposta käsin.
ROOT_REMOTE=""
for a in "${HOST_ALIAS}-root" "${HOST_ALIAS}-root-443"; do
    if git ls-remote "git@${a}:${GH_ORG}/${ROOT_REPO}.git" >/dev/null 2>&1; then
        ROOT_REMOTE="git@${a}:${GH_ORG}/${ROOT_REPO}.git"
        break
    fi
done

if [ -n "$ROOT_REMOTE" ]; then
    ROOT_WORK="$(mktemp -d "${TMPDIR:-/tmp}/ghpages-root.XXXXXX")"
    trap 'rm -rf "$WORK" "$ROOT_WORK"' EXIT
    if git ls-remote --exit-code --heads "$ROOT_REMOTE" main >/dev/null 2>&1; then
        git clone --quiet --depth 1 --branch main "$ROOT_REMOTE" "$ROOT_WORK"
    else
        git init --quiet "$ROOT_WORK"
        git -C "$ROOT_WORK" checkout --quiet -b main
        git -C "$ROOT_WORK" remote add origin "$ROOT_REMOTE"
    fi
    git -C "$ROOT_WORK" config user.name "$GH_USER"
    git -C "$ROOT_WORK" config user.email "${GH_USER}@users.noreply.github.com"
    find "$ROOT_WORK" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
    cat > "$ROOT_WORK/index.html" <<EOF
<!doctype html>
<html lang="fi"><head><meta charset="utf-8"><meta http-equiv="refresh" content="0; url=https://${GH_ORG}.github.io/${GH_REPO}/"><title>SKO ry</title></head>
<body><p>Siirrytään SKO ry:n uutisiin...</p><script>location.replace('https://${GH_ORG}.github.io/${GH_REPO}/');</script></body></html>
EOF
    git -C "$ROOT_WORK" add -A
    if ! git -C "$ROOT_WORK" diff --cached --quiet; then
        git -C "$ROOT_WORK" commit --quiet -m "Redirect root to uutiset"
        git -C "$ROOT_WORK" push --quiet origin main
    fi
    echo "Juuriosoite ohjaa nyt: https://${GH_ORG}.github.io/"
else
    echo "HUOMIO: ${ROOT_REPO}-repoa ei ole tai siihen ei ole oikeutta; juuriosoitetta ei voitu julkaista." >&2
    echo "Luo GitHubiin repo ${GH_ORG}/${ROOT_REPO}, niin deploy.sh julkaisee redirectin sinne." >&2
fi

