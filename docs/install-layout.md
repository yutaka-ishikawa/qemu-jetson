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
