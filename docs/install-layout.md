# ビルド成果物のローカルinstall配置

日本語 | [English](en/install-layout.md)

[決定0005](decisions/0005-install-prefix.md)に従い、ビルド後の既定配置先をリポジトリ直下の`install/`にする。
通常ユーザーで配置でき、ホストの`/usr/local`などへのシステムインストールは行わない。

```text
install/
├── bin/                         ホスト用QEMU
├── include/                     OP-TEEクライアント等の公開ヘッダ
├── lib/
│   ├── aarch64-linux-gnu/        ARM64用libteec等（.so/.a）
│   │   └── optee_armtz/          fTPM/helper/probeのTA
│   ├── optee/ta-dev-kit-aarch64/ TA開発用ヘッダ・ライブラリ・makeファイル
│   └── modules/                 ゲストのNVIDIAカーネルモジュール
├── libexec/aarch64-linux-gnu/    ゲスト用tee-supplicant、nvftpm-helper-app、probe
└── share/
    ├── qemu/                    QEMUのROM等
    └── qemu-jetson/
        ├── ftpm-virt/           flash.bin、Image、runtime-*.dtb、Linux entry
        ├── optee/               OP-TEEのイメージとデバッグELF
        ├── tf-a/                BL1/BL2/BL31とFIP
        └── t234/                T234検証用ファームウェア
```

ホスト用QEMUとゲスト用ARM64プログラムを区別する。ゲスト用バイナリをホストから直接実行する構成ではない。
NVIDIA提供カーネルの取得スクリプトも、取得後にImageとモジュールを`install/`へ配置する。
QEMUが使用するホストのGLib等はホスト依存パッケージであり、このディレクトリへ再配布しない。

## ビルド環境の具体的な設定（x86_64 Ubuntu）

以下は**x86_64版Ubuntu 22.04以降**のホスト用。すべてclone済みリポジトリのトップで実行する。
`uname -m`が`x86_64`であることを確認する。この配布ツールチェーンはARM64ゲスト用コードを生成するx86_64ホスト用である。

### 1. dtcなどのホストツール

```bash
sudo bash scripts/install-host-deps.sh
command -v dtc
dtc --version
```

`dtc`はDevice Tree Compiler。上記スクリプトがホスト用の`device-tree-compiler`パッケージを導入する。

### 2. NVIDIA指定のクロスコンパイラ

検証済みツールチェーンはBootlin Buildroot 2022.08、GCC 11.3.0。
NVIDIA配布アーカイブを`work/toolchains/`へ展開する。

```bash
mkdir -p work/downloads work/toolchains
curl -fL --retry 3 \
  https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v3.0/toolchain/aarch64--glibc--stable-2022.08-1.tar.bz2 \
  -o work/downloads/aarch64--glibc--stable-2022.08-1.tar.bz2
printf '%s  %s\n' \
  8af54f268c462b2d0737df8789b5e35db03a2d1ecbec90e20948f66f9244fcdd \
  work/downloads/aarch64--glibc--stable-2022.08-1.tar.bz2 | sha256sum -c -
# 初回だけ展開する。既に展開済みならこのtarコマンドは不要。
tar -xjf work/downloads/aarch64--glibc--stable-2022.08-1.tar.bz2 -C work/toolchains
export CROSS_COMPILE="$PWD/work/toolchains/aarch64--glibc--stable-2022.08-1/bin/aarch64-buildroot-linux-gnu-"
"${CROSS_COMPILE}gcc" --version
"${CROSS_COMPILE}gcc" -dumpmachine
```

`CROSS_COMPILE`はgccそのものではなく、**コンパイラのパスと接頭辞（末尾の`-`を含む）**。
スクリプトが後ろに`gcc`、`ar`、`objcopy`等を付ける。
確認結果はGCC `11.3.0`、ターゲット`aarch64-buildroot-linux-gnu`となる。
既に別の場所へ展開してある場合は、export行のディレクトリをその場所へ置き換える。

### 3. Python venv

```bash
python3 -m venv work/venv
source work/venv/bin/activate
python3 -m pip install -r docs/build-python-requirements.txt
python3 -c 'import sys, cryptography, Crypto, elftools; print(sys.executable); print("OP-TEE Python dependencies: OK")'
```

venvはビルド用PythonとライブラリをホストのシステムPythonから分ける。
`sys.executable`がリポジトリ内の`work/venv/bin/python3`を指し、importが成功すればよい。
パッケージ名`pycryptodome`のimport名は`Crypto`、`pyelftools`のimport名は`elftools`。

新しい端末を開いた場合は、同じリポジトリのトップで次の2行を再実行する。

```bash
source work/venv/bin/activate
export CROSS_COMPILE="$PWD/work/toolchains/aarch64--glibc--stable-2022.08-1/bin/aarch64-buildroot-linux-gnu-"
```

venv作成とpip install、コンパイラのダウンロード・展開は毎回行う必要はない。
以下のビルドは、この環境を設定した同じシェルで通常ユーザーとして実行する。
コンパイラの取得元・SHA-256と検証時の詳細は[無変更ビルド記録](r36.5.2-build.md)を参照。

## ビルドと配置

```bash
bash scripts/build-qemu.sh
# 上記の環境を設定済みの同じシェルで実行
bash scripts/build-ftpm-virt-firmware.sh
bash scripts/build-optee-client.sh
bash scripts/build-ftpm-helper-probe.sh
python3 scripts/fetch-ftpm-virt-kernel.py
```

各ビルドスクリプトは成功後に配置まで実行する。QEMUにはローカルprefixを設定し、Mesonのinstallを使用する。
その他の成果物は`install-artifacts.py`が既知の成果物だけをコピーする。
TA開発キットに署名用秘密鍵を含めない。probeのビルドでは、`TA_SIGN_KEY`指定またはリポジトリ同梱の開発用鍵を入力として使う。

既存のビルド済み成果物を再コンパイルせずに配置する例：

```bash
python3 scripts/install-artifacts.py firmware
python3 scripts/install-artifacts.py kernel
python3 scripts/install-artifacts.py probe
python3 scripts/install-artifacts.py client --client-export /path/to/optee/install/t234/usr
```

## ビルド後：初回起動とテスト

上の5つのビルド・取得コマンドがすべて成功したら、次の順に準備する。
以下は既定の`install/`と`work/`を使う初回手順。同じvenvを有効にしたリポジトリのトップで実行する。
既に鍵・provisioning image・ディスクがある場合は再生成せず、準備済みの段階を飛ばす。
既存ファイルを消して試験をやり直す手順ではない。

### 1. QEMU専用のテストCA・鍵・証明書を作成

```bash
source work/venv/bin/activate
python3 scripts/generate-ftpm-test-provisioning.py work/ftpm-test-provisioning
python3 scripts/pack-ftpm-provisioning.py \
  work/ftpm-test-provisioning/manifest.json \
  work/ftpm-virt/device-identity.bin \
  work/ftpm-virt/provisioning.bin
```

`device-identity.bin`はfirmwareビルド時に作成済み。これを上書きしない。
CA等は`work/ftpm-test-provisioning/`、PTAへ渡す情報は`work/ftpm-virt/provisioning.bin`に保存される。
この段階のRSA/EC証明書はAPI試験用fixtureであり、実際のfTPM EKとの対応付けは後述の工程で行う。

### 2. Ubuntu 22.04 ARM64 rootfsを作成

```bash
sudo env FTPM_FUNCTIONAL_PROFILE=1 bash scripts/build-ubuntu-rootfs.sh
```

`install/`のクライアント・ライブラリ・カーネルモジュールを使い、`work/ftpm-virt/rootfs.tar`を作成する。
`FTPM_FUNCTIONAL_PROFILE=1`で、起動時に実行するテスト用サービスを組み込む。
ホストのapt・PRoot等が必要。新しい方式による管理者権限でのrootfs全体の再構築は、この実行環境では未検証。

### 3. 公開検証データを追加し、ディスクを作成

```bash
python3 scripts/prepare-ftpm-test-rootfs.py \
  work/ftpm-virt/rootfs.tar work/ftpm-test-provisioning
sudo bash scripts/create-ftpm-virt-disk.sh
```

検証用の公開証明書・CSRとinstall済みprobeを追加し、`work/ftpm-virt/rootfs.ext4`を作る。
CA秘密鍵やFirmware ID秘密鍵をゲストのrootfsへコピーしない。
ディスクはsudo実行元ユーザーの所有となる。

### 4. 起動用DTBを生成

```bash
bash scripts/prepare-ftpm-virt-dtb.sh
```

QEMUゲストは[決定0006](decisions/0006-guest-selinux.md)のAに従い、SELinuxを無効にする。
DTBの起動引数に`lsm=lockdown,yama,integrity,apparmor,bpf`を設定する。ホストのSELinux設定は変更しない。


生成したDTBは`install/share/qemu-jetson/ftpm-virt/runtime-*.dtb`に配置される。

### 5. 初回試験を実行

```bash
bash scripts/run-ftpm-virt.sh first
```

これは対話用ログイン起動ではなく、ゲスト内のテストを自動実行する起動。
`PTA_TEST`の署名・証明書試験と、`FTPM_TEST`のNV・PCR・署名・seal/unseal試験を行う。
成功時は`FTPM_TEST: PASS phase=first`を表示してpoweroffする。
失敗・タイムアウトは成功と扱わず、次へ進む前に出力を確認する。

### 6. 同じディスクで再起動後の試験

初回のPASSを確認してから実行する。`first`を再実行しない。

```bash
bash scripts/run-ftpm-virt.sh second
```

同じ鍵・ディスクを使用し、NVデータ・署名鍵・sealed dataの保持とPCRリセットを確認する。
成功時は`FTPM_TEST: PASS phase=second`を表示してpoweroffする。
通常世界のログは端末へ、セキュア側ログは`work/ftpm-virt/secure-<phase>-native.log`へ出力する。

実際のfTPM EK公開鍵への証明書対応付けと標準NV indexの検証は、その後の`export`→`bind-ftpm-test-ek.py`→`bound`の工程。
詳しいコマンドは[機能検証の再現手順](ftpm-functional-validation.md#再現手順)を参照。

## rootfs.tarに試験用ファイルしかない場合の復旧

`create-ftpm-virt-disk.sh`が`usr/sbin`不存在で失敗し、tarの内容が約22件の試験用ファイルだけの場合、Ubuntu本体が入っていない。
旧`prepare-ftpm-test-rootfs.py`はtarの追記モードを使い、入力ファイルが存在しなくても新規tarを作成してしまった。
この内容だけからUbuntu生成が未実行だったのか、失敗したのかは断定できない。
修正版はUbuntu本体とOP-TEEクライアントの存在を確認し、不完全なtarへの追記とディスク作成を拒否する。

リポジトリのトップで以下を実行する。問題のtarとチェックサムを退避し、Ubuntuを再構築する。
鍵・証明書・device identity・provisioning・既存ディスクは変更しない。

```bash
git pull --ff-only
source work/venv/bin/activate
backup=$(mktemp -d "$PWD/work/ftpm-rootfs-backup.XXXXXX")
sudo mv -- work/ftpm-virt/rootfs.tar "$backup/"
if [ -f work/ftpm-virt/rootfs.tar.sha256 ]; then
  sudo mv -- work/ftpm-virt/rootfs.tar.sha256 "$backup/"
fi
sudo env FTPM_FUNCTIONAL_PROFILE=1 bash scripts/build-ubuntu-rootfs.sh
```

最後のコマンドが失敗した場合はそこで止め、エラー出力を確認する。成功した場合だけ続行する。

```bash
python3 scripts/prepare-ftpm-test-rootfs.py \
  work/ftpm-virt/rootfs.tar work/ftpm-test-provisioning
sudo bash scripts/create-ftpm-virt-disk.sh
bash scripts/prepare-ftpm-virt-dtb.sh
bash scripts/run-ftpm-virt.sh first
```

既存ディスクを上書きしない。初回PASS後に限り、前節の`second`を実行する。

## 配置先とビルド先の変更

```bash
INSTALL_DIR="$PWD/local-sdk" bash scripts/build-qemu.sh
INSTALL_DIR="$PWD/local-sdk" bash scripts/build-optee-client.sh
# 起動・DT生成も同じINSTALL_DIRを使う
INSTALL_DIR="$PWD/local-sdk" bash scripts/prepare-ftpm-virt-dtb.sh
INSTALL_DIR="$PWD/local-sdk" bash scripts/run-ftpm-virt.sh second
```

`INSTALL_DIR`を省略すると`install/`。相対パスはリポジトリ基準。
`QEMU_BUILD_DIR`はコンパイル用の中間ディレクトリだけを変更する。起動先の指定ではない。
カスタム配置先をGit管理下へ置く場合は、生成物を追跡しないよう設定する。既定の`install/`はGit管理外。

## 状態ファイルとrootfs

`work/`には.o等の中間ファイルと、仮想デバイス固有の状態を残す。
`device-identity.bin`、`provisioning.bin`、CA秘密鍵、seed、`rootfs.ext4`はinstall処理でコピー・再生成・削除しない。
QEMU起動は`install/`のプログラム・読み取り専用イメージと、`work/ftpm-virt/`の既存状態を組み合わせる。

rootfs作成は既定で`install/`のクライアント・ライブラリ・モジュールを使用する。

```bash
sudo env FTPM_FUNCTIONAL_PROFILE=1 bash scripts/build-ubuntu-rootfs.sh
# 公開fixtureと、install済みprobeをtarへ追加
python3 scripts/prepare-ftpm-test-rootfs.py work/ftpm-virt/rootfs.tar work/ftpm-test-provisioning
sudo bash scripts/create-ftpm-virt-disk.sh
```

`build-ubuntu-rootfs.sh OUTPUT_TAR`で出力先のみ指定できる。
従来の`build-ubuntu-rootfs.sh CLIENT_INSTALL_DIR OUTPUT_TAR`も利用できる。
既存ディスクやtarは上書きしない。rootfs全体の新しい管理者権限での組み立ては、この実行環境では未検証。

## 検証

配置済みQEMUと配置済みROMで標準virt検査を実行する。
配置済みのヘッダ・ARM64ライブラリ・TA開発キットでクライアントとprobeをコンパイルする。
配置済みのQEMU・ファームウェア・kernel Image・DTBを使い、既存NV状態でfTPMを起動する。
インストール先へ秘密鍵・仮想デバイス状態が入らないことと、別prefix（空白を含む）の配置も検査する。
[結果](results/install-layout.json)と[起動ログ抜粋](results/install-layout-excerpt.txt)を参照。
