#!/usr/bin/env bash
set -Eeuo pipefail

###=====[ Editable parameters ]=====###
HOSTNAME_FQDN="picsv00150"
GITLAB_HTTPS_PORT=8443
REDMINE_HTTPS_PORT=9443

# Offline assets roots
OFFLINE_ROOT="/opt/offline"
CERT_DIR="${OFFLINE_ROOT}/certs"
DEB_POOL="${OFFLINE_ROOT}/debs"
GITLAB_DEB="$(ls -1 ${OFFLINE_ROOT}/gitlab/*.deb 2>/dev/null | head -n1 || true)"
REDMINE_TARBALL="${OFFLINE_ROOT}/redmine/redmine.tar.gz"
REDMINE_PLUGINS_DIR="${OFFLINE_ROOT}/redmine/plugins"

# Install roots
GITLAB_ETC="/etc/gitlab"
GITLAB_DATA="/var/opt/gitlab"
GITLAB_LOG="/var/log/gitlab"

REDMINE_ROOT="/srv/redmine"
REDMINE_SHARED="${REDMINE_ROOT}/shared"
REDMINE_ENV="/srv/redmine/env"  # rbenv等にしない素直な構成
REDMINE_USER="redmine"
REDMINE_GROUP="redmine"

# TLS locations
SERVER_CERT="${CERT_DIR}/${HOSTNAME_FQDN}.crt"
SERVER_KEY="${CERT_DIR}/${HOSTNAME_FQDN}.key"
CA_CERT="${CERT_DIR}/ca.crt"     # あれば配置

# Admin bootstrap (change after install)
ADMIN_EMAIL_GL="admin@gitlab.local"
ADMIN_PASS_GL="AdminPassword!ChangeMe"
ADMIN_EMAIL_RM="admin@redmine.local"
ADMIN_PASS_RM="AdminPassword!ChangeMe"

###==================================###

log() { printf -- "[+] %s\n" "$*"; }
err() { printf -- "[!] %s\n" "$*" >&2; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "Run as root."
    exit 1
  fi
}

check_prereqs() {
  log "Checking offline assets..."
  [[ -f "${SERVER_CERT}" && -f "${SERVER_KEY}" ]] || { err "Missing cert/key in ${CERT_DIR}"; exit 1; }
  [[ -n "${GITLAB_DEB}" && -f "${GITLAB_DEB}" ]] || { err "Missing GitLab omnibus .deb under ${OFFLINE_ROOT}/gitlab/"; exit 1; }
  [[ -f "${REDMINE_TARBALL}" ]] || { err "Missing ${REDMINE_TARBALL}"; exit 1; }
  [[ -d "${DEB_POOL}" ]] || { err "Missing deb pool at ${DEB_POOL}"; exit 1; }

  log "Assets OK."
}

install_local_debs() {
  log "Installing local debs from ${DEB_POOL} (multiple passes for deps)..."
  shopt -s nullglob
  local passes=3
  for i in $(seq 1 ${passes}); do
    log "Pass ${i}/${passes}"
    dpkg -i ${DEB_POOL}/*.deb || true
    # Try to fix deps using only local cache
    # We prevent network by clearing sources temporarily
    if [[ -d /etc/apt/sources.list.d ]]; then
      mkdir -p /tmp/offline-apt.bak
      mv /etc/apt/sources.list /tmp/offline-apt.bak/ 2>/dev/null || true
      mv /etc/apt/sources.list.d /tmp/offline-apt.bak/ 2>/dev/null || true
      echo > /etc/apt/sources.list
      mkdir -p /etc/apt/sources.list.d
    fi
    apt-get -y --allow-downgrades --allow-change-held-packages -o Debug::pkgProblemResolver=yes -o Acquire::Retries=0 -o Dir::Etc::sourcelist="sources.list" -o Dir::Cache::Archives="${DEB_POOL}" install -f || true
  done

  # sanity checks
  for bin in nginx git ruby gem; do
    command -v "${bin}" >/dev/null 2>&1 || { err "Missing ${bin}. Ensure its .deb and deps are in ${DEB_POOL}"; exit 1; }
  done
  log "Base packages present."
}

setup_tls_system() {
  log "Installing TLS certs..."
  install -d -m 0755 /etc/ssl/local_certs
  install -m 0644 "${SERVER_CERT}" /etc/ssl/local_certs/${HOSTNAME_FQDN}.crt
  install -m 0600 "${SERVER_KEY}"  /etc/ssl/local_certs/${HOSTNAME_FQDN}.key
  if [[ -f "${CA_CERT}" ]]; then
    install -m 0644 "${CA_CERT}" /usr/local/share/ca-certificates/offline-ca.crt
    update-ca-certificates || true
  fi
}

install_gitlab() {
  log "Installing GitLab omnibus: ${GITLAB_DEB}"
  dpkg -i "${GITLAB_DEB}" || true
  apt-get -y install -f || true

  log "Configuring /etc/gitlab/gitlab.rb ..."
  cat >/etc/gitlab/gitlab.rb <<EOF
external_url "https://${HOSTNAME_FQDN}:${GITLAB_HTTPS_PORT}"

nginx['listen_addresses'] = ['0.0.0.0']
nginx['listen_port'] = ${GITLAB_HTTPS_PORT}
nginx['listen_https'] = true
letsencrypt['enable'] = false

nginx['ssl_certificate']     = "/etc/ssl/local_certs/${HOSTNAME_FQDN}.crt"
nginx['ssl_certificate_key'] = "/etc/ssl/local_certs/${HOSTNAME_FQDN}.key"

# Avoid outbound connections in offline env
gitlab_rails['env'] = { 'http_proxy' => nil, 'https_proxy' => nil, 'no_proxy' => 'localhost,127.0.0.1' }
gitlab_rails['gitlab_default_projects_features_builds'] = true
EOF

  log "gitlab-ctl reconfigure (this may take a while offline but no downloads)"
  gitlab-ctl reconfigure

  log "Ensuring GitLab is up..."
  gitlab-ctl status || true
}

bootstrap_gitlab_admin_and_token() {
  log "Bootstrapping GitLab admin & PAT via gitlab-rails runner..."
  local script='/tmp/gl_bootstrap.rb'
  cat >"${script}" <<'RUBY'
u = User.find_by(username: 'root')
if u && !u.confirmed?
  u.confirm
end
u = User.find_by(username: 'root') || User.admins.first
# Ensure a PAT named 'offline-admin-token' exists
existing = PersonalAccessToken.find_by(name: 'offline-admin-token', user: u)
if existing && existing.active?
  puts "PAT=#{existing.token}"
else
  token = PersonalAccessToken.create!(
    user: u,
    name: 'offline-admin-token',
    scopes: [:api, :read_user, :read_api, :read_repository, :write_repository]
  )
  token.set_token
  token.save!
  puts "PAT=#{token.token}"
end
RUBY
  chmod 0644 "${script}"
  # Set root password if empty and create PAT
  # Note: root password can be set with gitlab-rake if needed; we leave GUI to change
  local out
  out="$(gitlab-rails runner "${script}" 2>/dev/null || true)"
  echo "${out}" | grep -q '^PAT=' || { err "Failed to obtain GitLab PAT"; }
  GITLAB_PAT="$(echo "${out}" | sed -n 's/^PAT=//p' | tail -n1)"
  export GITLAB_PAT
  log "GitLab PAT acquired."
}

install_redmine_user_layout() {
  log "Creating redmine user and dirs..."
  id -u "${REDMINE_USER}" >/dev/null 2>&1 || useradd -r -m -d "${REDMINE_ROOT}" -s /usr/sbin/nologin "${REDMINE_USER}"
  install -d -o "${REDMINE_USER}" -g "${REDMINE_GROUP}" -m 0755 "${REDMINE_ROOT}"
  install -d -o "${REDMINE_USER}" -g "${REDMINE_GROUP}" -m 0755 "${REDMINE_SHARED}"
}

install_redmine_from_tarball() {
  log "Unpacking Redmine..."
  tar -xzf "${REDMINE_TARBALL}" -C "${REDMINE_ROOT}" --strip-components=1
  chown -R "${REDMINE_USER}:${REDMINE_GROUP}" "${REDMINE_ROOT}"

  # database.yml (SQLite)
  cat > "${REDMINE_ROOT}/config/database.yml" <<EOF
production:
  adapter: sqlite3
  database: ${REDMINE_ROOT}/redmine.sqlite3
  pool: 10
  timeout: 5000
EOF
  chown "${REDMINE_USER}:${REDMINE_GROUP}" "${REDMINE_ROOT}/config/database.yml"
  chmod 0640 "${REDMINE_ROOT}/config/database.yml"

  # configuration.yml minimal
  cat > "${REDMINE_ROOT}/config/configuration.yml" <<'EOF'
production:
  email_delivery:
    delivery_method: :async_smtp
    smtp_settings:
      address: "localhost"
      port: 25
  attachments_storage_path: ./files
EOF
  chown "${REDMINE_USER}:${REDMINE_GROUP}" "${REDMINE_ROOT}/config/configuration.yml"
  chmod 0640 "${REDMINE_ROOT}/config/configuration.yml"

  # Plugins
  if [[ -d "${REDMINE_PLUGINS_DIR}" ]]; then
    log "Installing Redmine plugins from ${REDMINE_PLUGINS_DIR}"
    install -d -o "${REDMINE_USER}" -g "${REDMINE_GROUP}" -m 0755 "${REDMINE_ROOT}/plugins"
    for t in "${REDMINE_PLUGINS_DIR}"/*.tar.gz; do
      [[ -f "$t" ]] || continue
      tar -xzf "$t" -C "${REDMINE_ROOT}/plugins"
    done
    chown -R "${REDMINE_USER}:${REDMINE_GROUP}" "${REDMINE_ROOT}/plugins"
  fi
}

bundle_install_offline() {
  log "Bundler (offline/local) setup..."
  # Expect vendor/cache populated in tarball
  su -s /bin/bash - "${REDMINE_USER}" <<'EOSU'
set -Eeuo pipefail
cd "${HOME}"
cd /srv/redmine
gem install bundler --local || true
bundle config set --local deployment 'true'
bundle config set --local without 'development test'
bundle config set --local path 'vendor/bundle'
bundle install --local
EOSU
}

redmine_db_migrate_and_secret() {
  log "DB migrate & generate secret..."
  su -s /bin/bash - "${REDMINE_USER}" <<'EOSU'
set -Eeuo pipefail
cd /srv/redmine
bundle exec rake generate_secret_token RAILS_ENV=production
bundle exec rake db:migrate RAILS_ENV=production
bundle exec rake redmine:plugins RAILS_ENV=production
EOSU
}

bootstrap_redmine_admin_and_key() {
  log "Bootstrapping Redmine admin and API key..."
  local runner='/srv/redmine/bootstrap_admin.rb'
  cat > "${runner}" <<'RUBY'
api_key = nil
u = User.find_by_login('admin')
if u
  # Ensure admin has an API key
  if u.api_key
    api_key = u.api_key.value
  else
    t = Token.create!(user: u, action: 'api')
    api_key = t.value
  end
end
puts "API_KEY=#{api_key}" if api_key
RUBY
  chown "${REDMINE_USER}:${REDMINE_GROUP}" "${runner}"
  chmod 0644 "${runner}"

  local out
  out="$(su -s /bin/bash - "${REDMINE_USER}" -c "cd /srv/redmine && bundle exec rails runner -e production /srv/redmine/bootstrap_admin.rb" || true)"
  echo "${out}" | grep -q '^API_KEY=' || { err "Failed to obtain Redmine API key"; }
  REDMINE_API_KEY="$(echo "${out}" | sed -n 's/^API_KEY=//p' | tail -n1)"
  export REDMINE_API_KEY
  log "Redmine API key acquired."
}

setup_puma_service() {
  log "Configuring Puma app server for Redmine..."
  cat > "${REDMINE_ROOT}/config/puma.rb" <<EOF
directory "${REDMINE_ROOT}"
environment "production"
tag "redmine"
pidfile "${REDMINE_SHARED}/puma.pid"
state_path "${REDMINE_SHARED}/puma.state"
stdout_redirect "${REDMINE_SHARED}/puma.stdout.log", "${REDMINE_SHARED}/puma.stderr.log", true
bind "tcp://127.0.0.1:3000"
workers 2
threads 2,8
preload_app!
EOF
  chown "${REDMINE_USER}:${REDMINE_GROUP}" "${REDMINE_ROOT}/config/puma.rb"

  cat > /etc/systemd/system/redmine-puma.service <<EOF
[Unit]
Description=Redmine Puma App Server
After=network.target

[Service]
Type=simple
User=${REDMINE_USER}
Group=${REDMINE_GROUP}
WorkingDirectory=${REDMINE_ROOT}
Environment=RAILS_ENV=production
ExecStart=/usr/bin/env bundle exec puma -C ${REDMINE_ROOT}/config/puma.rb
Restart=on-failure
TimeoutSec=120

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now redmine-puma.service
}

setup_nginx_for_redmine_tls() {
  log "Configuring Nginx vhost for Redmine on :${REDMINE_HTTPS_PORT} ..."
  # Minimal TLS site
  cat > /etc/nginx/sites-available/redmine.conf <<EOF
server {
    listen ${REDMINE_HTTPS_PORT} ssl;
    server_name ${HOSTNAME_FQDN};

    ssl_certificate     /etc/ssl/local_certs/${HOSTNAME_FQDN}.crt;
    ssl_certificate_key /etc/ssl/local_certs/${HOSTNAME_FQDN}.key;

    # Optional: trust internal CA for upstream if needed
    # ssl_client_certificate /usr/local/share/ca-certificates/offline-ca.crt;

    access_log /var/log/nginx/redmine_access.log;
    error_log  /var/log/nginx/redmine_error.log;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Ssl on;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Port ${REDMINE_HTTPS_PORT};
        proxy_read_timeout 300;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/redmine.conf /etc/nginx/sites-enabled/redmine.conf
  # Default site may bind 443; ensure not conflicting
  [[ -f /etc/nginx/sites-enabled/default ]] && rm -f /etc/nginx/sites-enabled/default || true
  nginx -t
  systemctl enable --now nginx
  systemctl restart nginx
}

final_report() {
  echo
  echo "============================================"
  echo " Install summary (OFFLINE, Ubuntu 22.04)"
  echo "--------------------------------------------"
  echo " Hostname          : ${HOSTNAME_FQDN}"
  echo " GitLab URL        : https://${HOSTNAME_FQDN}:${GITLAB_HTTPS_PORT}"
  echo " Redmine URL       : https://${HOSTNAME_FQDN}:${REDMINE_HTTPS_PORT}"
  echo
  echo " Redmine admin     : (初回ログイン後にGUIでパスワード変更を推奨)"
  echo "   - 既存 'admin' ユーザが有効。"
  echo "   - Redmine API key: ${REDMINE_API_KEY}"
  echo
  echo " GitLab admin      : root (初回にGUIで設定/変更してください)"
  echo "   - Personal Access Token (api等): ${GITLAB_PAT}"
  echo
  echo " 次の手順（GUIでの最終連携）:"
  echo "  1) Redmine側: 利用中プラグインのドキュメントに従って、"
  echo "     - GitLab PAT を使った連携設定 or Webhook URL を作成。"
  echo "     - 必要なら Redmineのトラッカー・プロジェクトのマッピング設定。"
  echo "  2) GitLab側: 対象プロジェクトで Integrations/Webhooks を開き、"
  echo "     - Redmine側が提供する Webhook URL を登録（自己署名のCAを許可）。"
  echo "     - Push events / Issues events を有効化、SSL検証設定を適宜調整。"
  echo
  echo " Gatewayポート転送例:"
  echo "   - GitLab : 外 -> Gateway:8443 -> ${HOSTNAME_FQDN}:${GITLAB_HTTPS_PORT}"
  echo "   - Redmine: 外 -> Gateway:9443 -> ${HOSTNAME_FQDN}:${REDMINE_HTTPS_PORT}"
  echo "============================================"
}

main() {
  require_root
  check_prereqs
  install_local_debs
  setup_tls_system
  install_gitlab
  bootstrap_gitlab_admin_and_token
  install_redmine_user_layout
  install_redmine_from_tarball
  bundle_install_offline
  redmine_db_migrate_and_secret
  bootstrap_redmine_admin_and_key
  setup_puma_service
  setup_nginx_for_redmine_tls
  final_report
}

main "$@"
