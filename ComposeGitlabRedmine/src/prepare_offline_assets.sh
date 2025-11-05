#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================
# Offline Redmine + GitLab asset preparer
# Target: Ubuntu 22.04 (Jammy)
# Run this on an INTERNET-CONNECTED machine.
# ==============================================

WORKDIR="${PWD}/offline_assets"
UBU_VER="bookworm"
ARCH="amd64"
GITLAB_VER="gitlab-ce_18.3.5-ce.0_amd64.deb"

mkdir -p "${WORKDIR}"/{debs,gitlab,redmine,certs}

echo "[+] Downloading essential .deb packages..."

PKGS=(
  ruby-full ruby-dev build-essential git imagemagick
  libsqlite3-dev sqlite3 libffi-dev libreadline-dev zlib1g-dev
  nginx ca-certificates
)

# Save all dependencies locally
# for pkg in "${PKGS[@]}"; do
#   apt-get download $(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "$pkg" | grep "^\w" | sort -u)
# done
mkdir -p "${WORKDIR}/debs"
cd "${WORKDIR}/debs"

for pkg in "${PKGS[@]}"; do
  echo "  -> Resolving dependencies for ${pkg}..."
  deps=$(apt-cache depends --recurse --no-recommends --no-suggests \
           --no-conflicts --no-breaks --no-replaces --no-enhances "$pkg" | grep "^\w" | sort -u)
  for dep in $deps; do
    echo "     Downloading $dep ..."
    if ! apt download "$dep" >/dev/null 2>&1; then
      echo "       ⚠️  $dep not found, trying newer candidate..."
      apt-get install --print-uris -y "$dep" 2>/dev/null | grep -Eo 'http[^ ]+\.deb' | while read -r url; do
        fname=$(basename "$url")
        wget -q -O "$fname" "$url" || echo "         ❌ $fname failed"
      done
    fi
  done
done

cd -
echo "[+] .deb package collection complete."


mv ./*.deb "${WORKDIR}/debs/" || true

echo "[+] Downloading GitLab Omnibus package..."
wget -P "${WORKDIR}/gitlab" "https://packages.gitlab.com/gitlab/gitlab-ce/packages/ubuntu/${UBU_VER}/${GITLAB_VER}/download.deb" -O "${WORKDIR}/gitlab/${GITLAB_VER}"

echo "[+] Downloading Redmine source (offline bundle-friendly)..."
REDMINE_VER="5.1.3"
wget -P "${WORKDIR}/redmine" "https://www.redmine.org/releases/redmine-${REDMINE_VER}.tar.gz"

echo "[+] (Optional) Sample plugin download..."
wget -P "${WORKDIR}/redmine/plugins" "https://github.com/akabekobeko/redmine-gitlab-hook/archive/refs/heads/master.tar.gz" -O "${WORKDIR}/redmine/plugins/redmine-gitlab-hook.tar.gz"

echo "[+] Generating placeholder certificate directory..."
cat > "${WORKDIR}/certs/README.txt" <<EOF
Place your CA-signed certs here before transfer:
 - gatewayserver.crt
 - gatewayserver.key
 - ca.crt
EOF

echo
echo "=============================================="
echo "Offline asset preparation completed!"
echo "Directory structure:"
tree "${WORKDIR}" -L 2
echo
echo "Next: Transfer ${WORKDIR} → /opt/offline/ on gatewayserver."
echo "=============================================="
