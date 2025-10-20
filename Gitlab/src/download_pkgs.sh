#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 [--edition ce|ee] [--gitlab_version version] [--arch architecture]
Options:
  --edition ce|ee          GitLab edition (default: ee)
  --gitlab_version version GitLab version to download (default: 18.5.0)
  --arch architecture      Architecture (e.g. amd64, el9.x86_64, arm64, etc.)
EOF
}

# デフォルト値
gitlab_version="18.5.0"
arch=""
expand="rpm"
edition="ce"

# 引数処理
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gitlab_version)
      gitlab_version="$2"
      shift 2
      ;;
    --arch)
      arch="$2"
      shift 2
      ;;
    --edition)
      edition="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# --- アーキテクチャ・ディストリビューション分類 ---
expand="rpm"
package_dir=""
os_family="rpm"

# アーキテクチャ未指定なら選択式
if [[ -z "$arch" ]]; then
  echo "Select architecture:"
  echo "1) amd64"
  echo "2) arm64"
  echo "3) amazon2.aarch64"
  echo "4) amazon2.x86_64"
  echo "5) amazon2023.aarch64"
  echo "6) el9.aarch64"
  echo "7) el9.x86_64"
  echo "8) el8.x86_64"
  echo "9) el8.aarch64"
  echo "10) sles15.aarch64"
  echo "11) sles15.x86_64"
  read -rp "Enter choice [1-11]: " choice
  case $choice in
    1) arch="amd64" ;;
    2) arch="arm64" ;;
    3) arch="amazon2.aarch64" ;;
    4) arch="amazon2.x86_64" ;;
    5) arch="amazon2023.aarch64" ;;
    6) arch="el9.aarch64" ;;
    7) arch="el9.x86_64" ;;
    8) arch="el8.x86_64" ;;
    9) arch="el8.aarch64" ;;
    10) arch="sles15.aarch64" ;;
    11) arch="sles15.x86_64" ;;
    *) echo "Invalid choice"; exit 1 ;;
  esac
fi


case "$arch" in
  amd64)
    package_dir="debian/bookworm"
    expand="deb"
    os_family="deb"
    ;;
  arm64)
    package_dir="ubuntu/jammy"
    expand="deb"
    os_family="deb"
    ;;
  amazon2.*)
    package_dir="amazon/2"
    ;;
  amazon2023.*)
    package_dir="amazon/2023"
    ;;
  el9.*)
    package_dir="ol/9"
    ;;
  el8.*)
    package_dir="ol/8"
    ;;
  sles15.*)
    package_dir="sles/15.6"
    ;;
  *)
    echo "Unsupported architecture: $arch"
    exit 1
    ;;
esac

# --- ダウンロードディレクトリ構築 ---
download_dir="./gitlab_deps_${edition}_${arch}"
mkdir -p "$download_dir"
cd "$download_dir"

# --- GitLab本体ダウンロード ---
package_name="gitlab-${edition}"
filename="${package_name}_${gitlab_version}-${edition}.0_${arch}.${expand}"
url="https://packages.gitlab.com/gitlab/${package_name}/packages/${package_dir}/${filename}/download.${expand}"

echo "Downloading GitLab ${edition^^} ${gitlab_version} for ${arch}..."
echo "URL: ${url}"

wget --content-disposition "${url}"

# --- 依存パッケージ収集 ---
echo "Collecting dependency packages for ${arch}..."

if [[ "$os_family" == "deb" ]]; then
  sudo apt-get update
  # 依存パッケージをリストアップしてダウンロード
  deps=$(apt-cache depends gitlab-${edition} | awk '/Depends:/ {print $2}')
  mkdir -p deps
  cd deps
  for pkg in $deps; do
    echo "Downloading dependency: $pkg"
    apt-get download "$pkg" || echo "Warning: could not fetch $pkg"
  done
  cd ..
else
  # RPM系
  if ! command -v yumdownloader >/dev/null && ! command -v dnf >/dev/null; then
    echo "Please install yum-utils or dnf-utils"
    exit 1
  fi
  mkdir -p deps
  cd deps
  if command -v dnf >/dev/null; then
    sudo dnf download --resolve "${package_name}"
  else
    sudo yumdownloader --resolve "${package_name}"
  fi
  cd ..
fi

echo "All packages downloaded under: $(pwd)"
echo "You can copy this directory to your offline environment."

# --- Redmine 依存パッケージ収集 ---
echo "Now collecting Redmine dependencies for ${arch}..."

mkdir -p redmine_deps
cd redmine_deps

if [[ "$os_family" == "deb" ]]; then
  # Redmineはパッケージ版が存在しないので、必要パッケージ群を明示的に指定
  redmine_pkgs=(
    ruby ruby-dev
    build-essential zlib1g-dev libssl-dev libreadline-dev
    libpq-dev libsqlite3-dev libyaml-dev libxml2-dev libxslt1-dev
    imagemagick libmagickwand-dev
    git curl nodejs
  )

  for pkg in "${redmine_pkgs[@]}"; do
    echo "Downloading Redmine dependency: $pkg"
    apt-get download "$pkg" || echo "Warning: could not fetch $pkg"
  done

else
  # RPM系
  if command -v dnf >/dev/null; then
    sudo dnf download --resolve \
      ruby ruby-devel make gcc zlib-devel openssl-devel readline-devel \
      libffi-devel libyaml-devel libxml2-devel libxslt-devel \
      postgresql-devel sqlite-devel ImageMagick ImageMagick-devel \
      git curl nodejs
  else
    sudo yumdownloader --resolve \
      ruby ruby-devel make gcc zlib-devel openssl-devel readline-devel \
      libffi-devel libyaml-devel libxml2-devel libxslt-devel \
      postgresql-devel sqlite-devel ImageMagick ImageMagick-devel \
      git curl nodejs
  fi
fi

cd ..

echo "Redmine dependency packages downloaded under: $(pwd)/redmine_deps"

# --- 証明書関連ライブラリ収集 ---
echo "Collecting certificate and SSL-related libraries for ${arch}..."

mkdir -p cert_deps
cd cert_deps

if [[ "$os_family" == "deb" ]]; then
  cert_pkgs=(
    ca-certificates openssl libssl-dev
    libgnutls30 libgnutls-openssl27
    libnss3 libnspr4
    python3-certifi python3-cryptography python3-openssl
  )

  for pkg in "${cert_pkgs[@]}"; do
    echo "Downloading certificate package: $pkg"
    apt-get download "$pkg" || echo "Warning: could not fetch $pkg"
  done

else
  if command -v dnf >/dev/null; then
    sudo dnf download --resolve \
      ca-certificates openssl openssl-devel nss nss-util nspr \
      gnutls gnutls-utils \
      python3-certifi python3-cryptography python3-pyOpenSSL
  else
    sudo yumdownloader --resolve \
      ca-certificates openssl openssl-devel nss nss-util nspr \
      gnutls gnutls-utils \
      python3-certifi python3-cryptography python3-pyOpenSSL
  fi
fi

cd ..

echo "Certificate-related packages downloaded under: $(pwd)/cert_deps"
# --- 自動証明書更新ジョブ関連ライブラリ収集 ---
echo "Collecting certificate auto-renewal job related packages for ${arch}..."

mkdir -p certbot_deps
cd certbot_deps

if [[ "$os_family" == "deb" ]]; then
  certbot_pkgs=(
    certbot python3-certbot python3-acme python3-josepy
    python3-configargparse python3-requests python3-distro
    cron systemd systemd-cron
  )

  for pkg in "${certbot_pkgs[@]}"; do
    echo "Downloading certbot-related package: $pkg"
    apt-get download "$pkg" || echo "Warning: could not fetch $pkg"
  done

else
  if command -v dnf >/dev/null; then
    sudo dnf download --resolve \
      certbot python3-certbot python3-acme python3-josepy \
      python3-configargparse python3-requests python3-distro \
      cronie systemd
  else
    sudo yumdownloader --resolve \
      certbot python3-certbot python3-acme python3-josepy \
      python3-configargparse python3-requests python3-distro \
      cronie systemd
  fi
fi

cd ..

echo "Certbot-related packages downloaded under: $(pwd)/certbot_deps"

echo "All done!"

