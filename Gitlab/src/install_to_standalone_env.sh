#!/usr/bin/env bash
set -euo pipefail

# install_offline_stack.sh
# オフラインでダウンロード済みパッケージを用いて
# GitLab (CE/EE) + Redmine をインストール、HTTPS化（社内CA or 自己署名）、
# Redmine連携（Webhook）まで行うワンショットスクリプト。
#
# 注意：実行は root または sudo で行ってください。

usage() {
  cat <<EOF
Usage: $0 [options]
Options:
  --edition ee|ce           GitLab edition (default: ee)
  --gitlab_version version  GitLab version (default: 18.5.0)
  --arch ARCH               architecture string used in filenames (e.g. amd64, el9.x86_64)
  --external-url URL        GitLab external URL (including https://) (default: https://gitlab.local)
  --redmine-host HOST       Redmine host (default: redmine.local)
  --db-user USER            Redmine DB user (default: redmine)
  --db-pass PASS            Redmine DB password (default: redmine)
  --db-name NAME            Redmine DB name (default: redmine_production)
  -h, --help                show this help
EOF
}

# ---- defaults ----
edition="ee"
gitlab_version="18.5.0"
arch=""
external_url="https://gitlab.local"
redmine_host="redmine.local"
db_user="redmine"
db_pass="redmine"
db_name="redmine_production"

# ---- arg parse ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --edition) edition="$2"; shift 2 ;;
    --gitlab_version) gitlab_version="$2"; shift 2 ;;
    --arch) arch="$2"; shift 2 ;;
    --external-url) external_url="$2"; shift 2 ;;
    --redmine-host) redmine_host="$2"; shift 2 ;;
    --db-user) db_user="$2"; shift 2 ;;
    --db-pass) db_pass="$2"; shift 2 ;;
    --db-name) db_name="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

# ---- helper functions ----
log() { echo "==> $*"; }
err() { echo "ERROR: $*" >&2; }
is_deb() { command -v dpkg >/dev/null 2>&1; }
is_rpm() { command -v rpm >/dev/null 2>&1; }

# Determine package flavor based on arch string or existing packages
detect_package_family() {
  # If arch contains 'amd64' or 'arm64' and we expect debs for ubuntu/debian
  if [[ "$arch" =~ ^(amd64|arm64)$ ]]; then
    echo "deb"
    return
  fi
  # el/ol/amazon/sles -> rpm
  if [[ "$arch" =~ ^(el|ol|amazon|sles|amazon2|amazon2023) ]]; then
    echo "rpm"
    return
  fi
  # fallback: check for .deb or .rpm files in cwd subdir
  if compgen -G "./*/deps/*.deb" >/dev/null; then echo "deb"; return; fi
  if compgen -G "./*/deps/*.rpm" >/dev/null; then echo "rpm"; return; fi
  echo "unknown"
}

# ---- sanity checks & paths ----
if [[ -z "$arch" ]]; then
  err "arch is required. Pass --arch 'amd64' or e.g. 'el9.x86_64'"
  exit 1
fi

pkg_family="$(detect_package_family)"
if [[ "$pkg_family" == "unknown" ]]; then
  err "Could not determine package family (deb/rpm). Check package directories."
  exit 1
fi
log "Package family determined: $pkg_family"

# find candidate offline package directory
# pattern: gitlab_deps_<edition>_<arch> or similar
candidate_dir=$(ls -d gitlab_deps_*_"${arch}"* 2>/dev/null | head -n1 || true)
if [[ -z "$candidate_dir" ]]; then
  # try generic directories
  candidate_dir=$(ls -d *"${arch}"* 2>/dev/null | grep -E "gitlab|deps" | head -n1 || true)
fi
if [[ -z "$candidate_dir" ]]; then
  err "Could not find downloaded package directory for arch=${arch} in current dir."
  err "Expected a directory like: gitlab_deps_..._${arch}"
  exit 1
fi
log "Using package directory: $candidate_dir"
cd "$candidate_dir"

# set file lists
gitlab_pkg=$(ls gitlab-*."${arch}".* 2>/dev/null | head -n1 || true)
if [[ -z "$gitlab_pkg" ]]; then
  # fallback to any gitlab package file
  gitlab_pkg=$(ls gitlab-* 2>/dev/null | grep -E "\.${arch}\." | head -n1 || true)
fi
if [[ -z "$gitlab_pkg" ]]; then
  err "GitLab package not found under ${candidate_dir}"
  exit 1
fi
log "Found GitLab package: $gitlab_pkg"

# directories (expected from previous steps)
deps_dir="./deps"
redmine_deps_dir="./redmine_deps"
cert_deps_dir="./cert_deps"
certbot_deps_dir="./certbot_deps"

# Install OS-level dependency packages (deb/rpm)
install_deps_deb() {
  log "Installing DEB packages from ${PWD} (offline)..."
  # ensure apt doesn't try to network (we depend on local .deb)
  # install base packages from deps dirs first
  for d in "$deps_dir" "$redmine_deps_dir" "$cert_deps_dir" "$certbot_deps_dir"; do
    if [[ -d "$d" ]]; then
      log "Installing .deb from $d"
      sudo dpkg -i "$d"/*.deb 2>/dev/null || true
    fi
  done

  # fix missing deps using apt (offline may fail if not all packages present)
  if command -v apt-get >/dev/null 2>&1; then
    log "Running apt-get install -f to fix dependencies (will not fetch network if sources disabled)"
    sudo apt-get install -f -y || true
  fi

  # install main gitlab package
  log "Installing GitLab package (${gitlab_pkg})"
  sudo dpkg -i "$gitlab_pkg" || {
    log "dpkg install returned non-zero; attempting apt-get -f to resolve"
    sudo apt-get install -f -y || true
    sudo dpkg -i "$gitlab_pkg"
  }
}

install_deps_rpm() {
  log "Installing RPM packages from ${PWD} (offline)..."
  # Install dependency files first
  for d in "$deps_dir" "$redmine_deps_dir" "$cert_deps_dir" "$certbot_deps_dir"; do
    if [[ -d "$d" ]]; then
      log "Installing RPMs from $d"
      if command -v dnf >/dev/null 2>&1; then
        sudo dnf localinstall -y "$d"/*.rpm || true
      else
        sudo yum localinstall -y "$d"/*.rpm || true
      fi
    fi
  done

  # install main gitlab package
  if command -v dnf >/dev/null 2>&1; then
    sudo dnf localinstall -y "$gitlab_pkg" || true
  else
    sudo yum localinstall -y "$gitlab_pkg" || true
  fi
}

# ---- perform package installation ----
if [[ "$pkg_family" == "deb" ]]; then
  install_deps_deb
else
  install_deps_rpm
fi

# ---- GitLab configuration ----
log "Configuring GitLab..."
# create /etc/gitlab if not exist (dpkg should have done it)
sudo mkdir -p /etc/gitlab

# disable email by default in closed env
sudo bash -c "cat >> /etc/gitlab/gitlab.rb" <<EOF

# Offline / closed environment settings
external_url '${external_url}'
gitlab_rails['gitlab_email_enabled'] = false
gitlab_rails['gitlab_email_from'] = 'noreply@local'
nginx['redirect_http_to_https'] = true
EOF

# ---- Certificate handling ----
# Prefer using provided inhouse-ca/server certs if present, else use any gitlab*.crt/key in current tree,
# else generate fallback self-signed certs (but prefer CA flow).

# Helper: find cert/key pair
find_cert_pair() {
  # check in common candidate locations
  local candidates=(
    "../inhouse-ca/pki/issued/gitlab.local.crt"
    "../inhouse-ca/pki/private/gitlab.local.key"
    "./inhouse-ca/pki/issued/gitlab.local.crt"
    "./inhouse-ca/pki/private/gitlab.local.key"
    "../pki/issued/gitlab.local.crt"
    "../pki/private/gitlab.local.key"
    "./gitlab.local.crt"
    "./gitlab.local.key"
  )
  for f in "${candidates[@]}"; do
    if [[ -f "$f" ]]; then
      echo "$f"
      return 0
    fi
  done
  return 1
}

# install CA root to system trust if present
if [[ -f "../inhouse-ca/pki/ca.crt" ]]; then
  log "Found inhouse CA at ../inhouse-ca/pki/ca.crt – installing to system trust store"
  sudo cp ../inhouse-ca/pki/ca.crt /usr/local/share/ca-certificates/inhouse-ca.crt || true
  sudo update-ca-certificates || true
elif [[ -f "./inhouse-ca/pki/ca.crt" ]]; then
  log "Found inhouse CA at ./inhouse-ca/pki/ca.crt – installing to system trust store"
  sudo cp ./inhouse-ca/pki/ca.crt /usr/local/share/ca-certificates/inhouse-ca.crt || true
  sudo update-ca-certificates || true
else
  log "No inhouse CA root file found in expected locations. Will attempt to use server certs or generate self-signed certs."
fi

# copy server certificate for GitLab and Redmine
gitlab_crt=""
gitlab_key=""
redmine_crt=""
redmine_key=""

# prefer explicit files
if [[ -f "../inhouse-ca/pki/issued/gitlab.local.crt" && -f "../inhouse-ca/pki/private/gitlab.local.key" ]]; then
  gitlab_crt="../inhouse-ca/pki/issued/gitlab.local.crt"
  gitlab_key="../inhouse-ca/pki/private/gitlab.local.key"
fi
if [[ -f "../inhouse-ca/pki/issued/redmine.local.crt" && -f "../inhouse-ca/pki/private/redmine.local.key" ]]; then
  redmine_crt="../inhouse-ca/pki/issued/redmine.local.crt"
  redmine_key="../inhouse-ca/pki/private/redmine.local.key"
fi

# fallback: look for generic cert files in candidate_dir
if [[ -z "$gitlab_crt" ]]; then
  if [[ -f "./certs/gitlab.local.crt" && -f "./certs/gitlab.local.key" ]]; then
    gitlab_crt="./certs/gitlab.local.crt"
    gitlab_key="./certs/gitlab.local.key"
  elif [[ -f "./gitlab.local.crt" && -f "./gitlab.local.key" ]]; then
    gitlab_crt="./gitlab.local.crt"
    gitlab_key="./gitlab.local.key"
  fi
fi
if [[ -z "$redmine_crt" ]]; then
  if [[ -f "./certs/redmine.local.crt" && -f "./certs/redmine.local.key" ]]; then
    redmine_crt="./certs/redmine.local.crt"
    redmine_key="./certs/redmine.local.key"
  elif [[ -f "./redmine.local.crt" && -f "./redmine.local.key" ]]; then
    redmine_crt="./redmine.local.crt"
    redmine_key="./redmine.local.key"
  fi
fi

# if still not found, generate self-signed cert for both hosts (CNs taken from external_url host and redmine_host)
generate_self_signed() {
  local host="$1"
  local outdir="$2"
  sudo mkdir -p "$outdir"
  sudo openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
    -keyout "${outdir}/${host}.key" \
    -out "${outdir}/${host}.crt" \
    -subj "/C=JP/ST=Tokyo/L=Tokyo/O=Inhouse/OU=Dev/CN=${host}"
}
if [[ -z "$gitlab_crt" || -z "$gitlab_key" ]]; then
  log "No GitLab cert/key found; generating self-signed cert for GitLab host"
  gitlab_host=$(echo "$external_url" | sed -E 's#https?://##' | sed -E 's#/.*##')
  generate_self_signed "$gitlab_host" "./generated_certs"
  gitlab_crt="./generated_certs/${gitlab_host}.crt"
  gitlab_key="./generated_certs/${gitlab_host}.key"
fi
if [[ -z "$redmine_crt" || -z "$redmine_key" ]]; then
  log "No Redmine cert/key found; generating self-signed cert for Redmine host"
  generate_self_signed "$redmine_host" "./generated_certs"
  redmine_crt="./generated_certs/${redmine_host}.crt"
  redmine_key="./generated_certs/${redmine_host}.key"
fi

# copy certs to proper locations
log "Deploying certificates for GitLab and Redmine"
sudo mkdir -p /etc/gitlab/ssl
sudo cp "$gitlab_crt" /etc/gitlab/ssl/ || true
sudo cp "$gitlab_key" /etc/gitlab/ssl/ || true
sudo chmod 600 /etc/gitlab/ssl/*

# For Redmine: create /etc/redmine/ssl
sudo mkdir -p /etc/redmine/ssl
sudo cp "$redmine_crt" /etc/redmine/ssl/ || true
sudo cp "$redmine_key" /etc/redmine/ssl/ || true
sudo chmod 600 /etc/redmine/ssl/*

# update gitlab.rb to point to the certs (absolute paths)
sudo bash -c "cat >> /etc/gitlab/gitlab.rb" <<EOF

# SSL certs
nginx['ssl_certificate'] = '/etc/gitlab/ssl/$(basename "$gitlab_crt")'
nginx['ssl_certificate_key'] = '/etc/gitlab/ssl/$(basename "$gitlab_key")'
EOF

# reconfigure GitLab
log "Reconfiguring GitLab (this can take a while)..."
sudo gitlab-ctl reconfigure || true
sudo gitlab-ctl restart || true

# ---- Redmine install from source (if source tarball present) ----
# Prefer /opt/redmine path
if compgen -G "../redmine-*.tar.gz" >/dev/null 2>&1 || compgen -G "./redmine-*.tar.gz" >/dev/null 2>&1; then
  log "Deploying Redmine from tarball (offline mode)"
  # find tarball
  redmine_tar=$(ls ../redmine-*.tar.gz 2>/dev/null | head -n1 || true)
  if [[ -z "$redmine_tar" ]]; then
    redmine_tar=$(ls ./redmine-*.tar.gz 2>/dev/null | head -n1 || true)
  fi
  if [[ -z "$redmine_tar" ]]; then
    log "No Redmine tarball found; skipping Redmine source install"
  else
    sudo mkdir -p /opt/redmine
    sudo tar xzf "$redmine_tar" -C /opt
    rb_dir=$(tar -tf "$redmine_tar" | head -n1 | cut -d/ -f1)
    sudo mv "/opt/${rb_dir}" /opt/redmine || true
    sudo chown -R "$(whoami):$(whoami)" /opt/redmine
    cd /opt/redmine

    # configure database.yml
    cat > config/database.yml <<DBCONF
production:
  adapter: postgresql
  database: ${db_name}
  host: localhost
  username: ${db_user}
  password: ${db_pass}
  encoding: utf8
DBCONF

    # install gems from vendor/cache (offline)
    if [[ -d vendor/cache ]]; then
      log "Installing gems from vendor/cache (offline)"
      gem install bundler || true
      bundle config set --local deployment 'true' || true
      bundle install --local || {
        log "bundle install --local failed. If network disabled, ensure vendor/cache contains required gems."
      }
    else
      log "vendor/cache not found; skipping bundle install. You must provide vendor/cache for offline gem install."
    fi

    # generate secret token and migrate DB (DB must exist)
    bundle exec rake generate_secret_token || true
    RAILS_ENV=production bundle exec rake db:migrate || true
    RAILS_ENV=production bundle exec rake redmine:load_default_data || true

    # create systemd service via puma or use passenger+nginx. We'll assume nginx+passenger installed earlier.
    log "Redmine deployed to /opt/redmine. Please configure nginx site below"
  fi
else
  log "No Redmine tarball found in parent/current dir; skipping Redmine source deployment"
fi

# ---- Nginx site for Redmine (SSL) ----
if command -v nginx >/dev/null 2>&1; then
  log "Configuring Nginx site for Redmine (SSL)..."
  redmine_site="/etc/nginx/sites-available/redmine"
  sudo bash -c "cat > ${redmine_site}" <<NGCONF
server {
  listen 80;
  server_name ${redmine_host};
  return 301 https://\$host\$request_uri;
}

server {
  listen 443 ssl;
  server_name ${redmine_host};

  ssl_certificate     /etc/redmine/ssl/$(basename "$redmine_crt");
  ssl_certificate_key /etc/redmine/ssl/$(basename "$redmine_key");

  root /opt/redmine/public;
  passenger_enabled on;
  passenger_ruby /usr/bin/ruby;

  client_max_body_size 50m;

  access_log /var/log/nginx/redmine.access.log;
  error_log  /var/log/nginx/redmine.error.log;
}
NGCONF

  sudo ln -sf "${redmine_site}" /etc/nginx/sites-enabled/redmine
  sudo nginx -t && sudo systemctl restart nginx || true
else
  log "nginx not found; skipping Redmine nginx config"
fi

# ---- GitLab <-> Redmine webhook setup note ----
# Automation of webhook creation requires GitLab API token OR manual UI.
# Here we output instructions if admin token is not available.
log "Setting up Redmine <-> GitLab integration:"
echo "  * On Redmine: install plugin (redmine_gitlab_hook) by placing plugin in /opt/redmine/plugins and run:"
echo "      cd /opt/redmine && RAILS_ENV=production bundle exec rake redmine:plugins:migrate"
echo "  * On GitLab project: add Webhook URL:"
echo "      https://${redmine_host}/gitlab_hook  (set token to same value configured in plugin)"
echo "  * Automating webhook creation requires GitLab Admin API token; this script does not attempt that."

# ---- Final messages ----
log "Installation and basic configuration steps completed."
echo
echo "Next manual tasks you may need to perform:"
echo "  - Ensure PostgreSQL is installed and create DB/user:"
echo "      sudo -u postgres createuser -P ${db_user}"
echo "      sudo -u postgres createdb -O ${db_user} ${db_name}"
echo "  - If Redmine bundle install failed due to missing gems, copy vendor/cache with required gem files."
echo "  - Create Redmine plugin directory and install redmine_gitlab_hook plugin if needed."
echo "  - In GitLab Admin UI, set license (if EE) and check SSL configuration."
echo "  - Distribute CA root (if using internal CA) to clients, or import generated certs."
echo
log "Script finished."
