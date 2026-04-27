結論から言うと、この構成は **SDK環境ではない**。
これは **WRLinux / Yocto のネイティブビルド環境を Docker コンテナ化する構成**。

SDK は「生成済みSDKを使ってアプリや一部コンポーネントをビルドする環境」。
今回やりたいのは `wrlinux-x/setup.sh` で展開した WRL/Yocto 環境上で、レシピ編集・bitbake・sstate/download cache共有をするものなので、分類としては **ビルドホストコンテナ**。

---

## 目標構成

ホスト側にこう置く前提で書く。

```text
~/project/
  WRLINUX_LTS23/
    wrlinux-x/
      setup.sh
    build/
    layers/
    ...
  work/
    meta-nico/
    patches/
    recipes/
  
/opt/yocto-cache/
  downloads/
  sstate-cache/
```

Docker コンテナ側ではこう見せる。

```text
/work/wrlinux        # WRL展開済みディレクトリ
/work/dev            # 自作レイヤ、作業用ファイル
/cache/downloads     # DL_DIR
/cache/sstate-cache  # SSTATE_DIR
```

---

# Dockerfile

まずは汎用性重視で Ubuntu 22.04 ベースにする。
WRL LTS23 の要求パッケージ次第で微修正は必要だが、Yocto/WRL系のビルドホストとしてはこのくらいが現実ライン。

```Dockerfile
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG USERNAME=builder
ARG USER_UID=1000
ARG USER_GID=1000

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Yocto / WRLinux build host packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    gawk \
    wget \
    git \
    git-lfs \
    diffstat \
    unzip \
    texinfo \
    gcc \
    g++ \
    build-essential \
    chrpath \
    socat \
    cpio \
    python3 \
    python3-pip \
    python3-pexpect \
    python3-git \
    python3-jinja2 \
    python3-subunit \
    python3-venv \
    xz-utils \
    debianutils \
    iputils-ping \
    file \
    locales \
    libacl1 \
    liblz4-tool \
    zstd \
    lz4 \
    sudo \
    rsync \
    bc \
    bison \
    flex \
    libssl-dev \
    libelf-dev \
    openssh-client \
    ca-certificates \
    vim \
    less \
    tree \
    jq \
    time \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# repoコマンドが必要な場合用
RUN curl -o /usr/local/bin/repo https://storage.googleapis.com/git-repo-downloads/repo \
    && chmod a+x /usr/local/bin/repo

# builder user
RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m ${USERNAME} \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

# mount point
RUN mkdir -p /work/wrlinux /work/dev /cache/downloads /cache/sstate-cache \
    && chown -R ${USERNAME}:${USERNAME} /work /cache

USER ${USERNAME}
WORKDIR /work/wrlinux

# BitBake向け。rootで動かさない。
ENV TEMPLATECONF=""
ENV BB_ENV_PASSTHROUGH_ADDITIONS="DL_DIR SSTATE_DIR SOURCE_MIRROR_URL SSTATE_MIRRORS PREMIRRORS"

CMD ["/bin/bash"]
```

---

# docker-compose.yml

毎回 `docker run` を打つより、compose に固定した方が事故が少ない。

```yaml
services:
  wrl-build:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        USER_UID: ${UID:-1000}
        USER_GID: ${GID:-1000}
        USERNAME: builder

    image: wrl-lts23-build:ubuntu22.04

    container_name: wrl-lts23-build

    working_dir: /work/wrlinux

    volumes:
      # WRLinux展開済み環境
      - ${WRL_DIR}:/work/wrlinux

      # 自作レイヤ・作業場所
      - ${DEV_DIR}:/work/dev

      # Yocto download cache
      - ${YOCTO_DOWNLOADS}:/cache/downloads

      # Yocto sstate cache
      - ${YOCTO_SSTATE}:/cache/sstate-cache

      # SSH鍵を使ってprivate repoを取る場合
      - ${HOME}/.ssh:/home/builder/.ssh:ro

      # Git設定を共有したい場合
      - ${HOME}/.gitconfig:/home/builder/.gitconfig:ro

    environment:
      DL_DIR: /cache/downloads
      SSTATE_DIR: /cache/sstate-cache

      # 必要ならプロキシ
      http_proxy: ${http_proxy}
      https_proxy: ${https_proxy}
      no_proxy: ${no_proxy}
      HTTP_PROXY: ${HTTP_PROXY}
      HTTPS_PROXY: ${HTTPS_PROXY}
      NO_PROXY: ${NO_PROXY}

    tty: true
    stdin_open: true
```

---

# .env 例

```env
WRL_DIR=/home/nico/project/WRLINUX_LTS23
DEV_DIR=/home/nico/project/work

YOCTO_DOWNLOADS=/opt/yocto-cache/downloads
YOCTO_SSTATE=/opt/yocto-cache/sstate-cache
```

起動はこれ。

```bash
docker compose build
docker compose run --rm wrl-build
```

---

# コンテナ内での使い方

コンテナに入ったら、既に `/work/wrlinux` が WRL 展開済みディレクトリになっている想定。

```bash
cd /work/wrlinux
ls
```

`setup.sh` があるなら、通常はこういう流れ。

```bash
cd /work/wrlinux
source wrlinux-x/setup.sh
```

ただし WRLinux の `setup.sh` が **新規 build dir を作るタイプ**なのか、**既存 build dir に入るタイプ**なのかでコマンドは変わる。
ここは手元の WRL 展開方式に合わせる。

典型的にはこういう形になる。

```bash
source wrlinux-x/setup.sh --machines <machine> --templates <template>
```

または、すでに build ディレクトリがあるなら、

```bash
cd /work/wrlinux/build
source ../wrlinux-x/setup.sh
```

この辺は WRL 固有の `setup.sh` が支配するので、Dockerfile側で決め打ちしない方がいい。

---

# local.conf 側の設定

重要なのは、Docker の環境変数を渡すだけでは不十分な場合があること。
最終的には `conf/local.conf` に明示しておく方が堅い。

```conf
DL_DIR ?= "/cache/downloads"
SSTATE_DIR ?= "/cache/sstate-cache"
```

さらに、ローカルミラーとして downloads を使いたい場合はこう。

```conf
SOURCE_MIRROR_URL ?= "file:///cache/downloads"
INHERIT += "own-mirrors"
BB_GENERATE_MIRROR_TARBALLS = "1"
```

ただしここは注意。

## `DL_DIR` と `PREMIRRORS` は役割が違う

混同しやすいが、分けて考えた方がいい。

```text
DL_DIR
  bitbake が取得済みソースを保存するキャッシュ置き場

PREMIRRORS / SOURCE_MIRROR_URL
  まずどこからソースを取りに行くかを制御するミラー設定

SSTATE_DIR
  コンパイル済み成果物の再利用キャッシュ

SSTATE_MIRRORS
  sstate-cache を別の場所から引くためのミラー設定
```

今回、ホストの `/opt/yocto-cache/downloads` をコンテナに `/cache/downloads` としてマウントするなら、最低限はこれでよい。

```conf
DL_DIR = "/cache/downloads"
SSTATE_DIR = "/cache/sstate-cache"
```

`PREMIRRORS` は、オフラインビルドや社内ミラー運用をしたい場合に追加するもの。
「download cacheを共有したい」だけなら、まず `DL_DIR` で十分。

---

# sstate mirror も使う場合

単に `SSTATE_DIR` を共有するならこれでよい。

```conf
SSTATE_DIR = "/cache/sstate-cache"
```

複数環境から read-only に近い形で sstate を参照するなら `SSTATE_MIRRORS` を使う。

```conf
SSTATE_MIRRORS ?= "file://.* file:///cache/sstate-cache/PATH"
```

ただし、単一開発PCで Docker コンテナから使うだけなら、最初から `SSTATE_DIR=/cache/sstate-cache` を直接指定する方が単純。

---

# 自作レイヤの配置

`/work/dev/meta-nico` を使うなら、コンテナ内ではこう見える。

```bash
/work/dev/meta-nico
```

WRL build 環境に入った後、

```bash
bitbake-layers add-layer /work/dev/meta-nico
```

または `bblayers.conf` に直接追加。

```conf
BBLAYERS += "/work/dev/meta-nico"
```

この構成の利点は、WRL本体と自作レイヤを分けられること。

```text
/work/wrlinux
  WRL本体、setup.sh、build dir

/work/dev
  自作レイヤ、パッチ、メモ、検証用スクリプト
```

WRL本体を汚さずに作業できる。

---

# 推奨するホスト側ディレクトリ権限

これをやっておく。

```bash
sudo mkdir -p /opt/yocto-cache/downloads
sudo mkdir -p /opt/yocto-cache/sstate-cache

sudo chown -R $(id -u):$(id -g) /opt/yocto-cache
```

Docker コンテナ内の `builder` ユーザー UID/GID をホストと合わせるので、権限トラブルを減らせる。

確認。

```bash
id
ls -ld /opt/yocto-cache/downloads /opt/yocto-cache/sstate-cache
```

---

# 使い方まとめ

```bash
mkdir -p ~/docker/wrl-build
cd ~/docker/wrl-build
```

`Dockerfile`、`docker-compose.yml`、`.env` を置く。

```bash
docker compose build
docker compose run --rm wrl-build
```

コンテナ内。

```bash
cd /work/wrlinux
source wrlinux-x/setup.sh
```

build 環境に入った後。

```bash
bitbake-layers show-layers
bitbake-layers add-layer /work/dev/meta-nico
```

`conf/local.conf` に追加。

```conf
DL_DIR = "/cache/downloads"
SSTATE_DIR = "/cache/sstate-cache"
```

ビルド。

```bash
bitbake <target>
```

---

# この構成の現実的な注意点

## 1. Docker内ビルドでもホストカーネルは共有

Docker は仮想マシンではない。
なので、Yocto/WRL のビルド自体は問題ないが、特殊な mount、loop device、QEMU、疑似root、Fakeroot 周りでホスト設定の影響を受けることはある。

必要なら compose に追加する。

```yaml
    privileged: true
```

ただし最初から `privileged: true` にするのは雑。
まずは無しで動かし、WIC作成やloop mount周りで詰まったら付ける、でいい。

## 2. Docker Desktop on Windows は重い

Windows + Docker Desktop + WSL2 上で Yocto/WRL をビルドするのは、正直かなり遅くなりやすい。
特に `/mnt/c/...` 配下をマウントしてビルドすると地獄を見る。

使うなら最低限、

```text
WSL2のLinuxファイルシステム内に置く
例: /home/nico/project/...
```

Windows側の `C:\Users\...` を直接使うのは避ける。

## 3. sstate-cache は壊れると面倒

複数コンテナ・複数ビルドで同じ `SSTATE_DIR` に同時書き込みすると、トラブルの原因になることがある。
個人開発なら許容できるが、チーム共有ならこう分ける方が安全。

```text
/cache/sstate-cache-ro   # 共有sstate mirror、基本read only
/cache/sstate-cache      # 自分のビルド用sstate
```

最初は単純に直接マウントでいい。
チーム運用に広げる段階で mirror 化すればいい。

## 4. WRLのsetup.shをDockerfile内で実行しない方がいい

Dockerfile内で `setup.sh` を叩いて build dir を作る設計は、個人的にはおすすめしない。

理由はこれ。

```text
- WRL環境はプロジェクトごとに machine/template/branch が違う
- setup.sh の出力物は開発対象であり、Docker image に焼くべきではない
- image rebuild と WRL build dir の状態が混ざる
- cacheやlayer変更の検証がやりにくくなる
```

Dockerfile はあくまで **ビルドホストの依存パッケージを揃えるだけ**に留める。
WRLの展開済み環境は volume mount する。これが正解寄り。

---

# SDK環境との違い

今回の構成。

```text
Docker container
  ├─ WRLinux setup.sh
  ├─ bitbake
  ├─ layers
  ├─ recipes
  ├─ downloads cache
  └─ sstate cache
```

これは **Yocto/WRLネイティブビルド環境**。

SDK環境はこう。

```text
Docker container
  ├─ environment-setup-xxx
  ├─ cross-gcc
  ├─ sysroot
  └─ app build
```

SDKは主に、

```text
- アプリケーション開発
- 外部モジュール開発
- ライブラリ単体ビルド
- CIで軽くビルド確認
```

に向く。

一方で今回みたいに、

```text
- recipeを書く
- imageを作る
- kernel configを変える
- rootfsを作る
- package構成を変える
- wicを作る
- layerを追加する
```

なら SDK では足りない。
WRL/Yocto の build environment が必要。

---

# 推奨方針

まずはこの構成でいい。

```text
Docker image
  = Ubuntu + Yocto/WRLビルド依存パッケージのみ

WRL本体
  = ホストに展開して volume mount

自作レイヤ
  = /work/dev/meta-nico に mount

downloads
  = /cache/downloads

sstate-cache
  = /cache/sstate-cache
```

やらない方がいいのはこれ。

```text
- Docker image内にWRL本体をCOPYする
- Dockerfile内でsetup.shを実行する
- Windows側ファイルシステム上でYocto buildする
- rootユーザーでbitbakeする
- DL_DIRとPREMIRRORSを同じ意味で扱う
```

一言で言うと、今作るべきなのは **SDKコンテナではなく、WRLのビルドホストを再現するコンテナ**。
Dockerfileは薄く、WRL環境とcacheはvolumeで外出し。これが一番壊れにくい。
