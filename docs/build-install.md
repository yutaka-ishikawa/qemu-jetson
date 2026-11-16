# ビルド・インストール手順

環境準備からビルド、成果物の配置、Ubuntuディスク作成、起動用DTB生成までを説明する。
試験の実行は[test-guide.md](test-guide.md)に集約し、本書では実行しない。

日本語 | [English](en/build-install.md)

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

## ビルド後：初回のデータ・ディスク・DTB準備

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

ここまでで初期導入は完了。[テスト手順](test-guide.md)へ進み、初回試験から開始する。
既に試験済みのディスクは、テスト手順に従って完了済みの段階を飛ばす。

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
```

既存ディスクを上書きしない。復旧後の試験は[test-guide.md](test-guide.md)を参照。

## 配置先とビルド先の変更

```bash
INSTALL_DIR="$PWD/local-sdk" bash scripts/build-qemu.sh
INSTALL_DIR="$PWD/local-sdk" bash scripts/build-optee-client.sh
# 起動・DT生成も同じINSTALL_DIRを使う
INSTALL_DIR="$PWD/local-sdk" bash scripts/prepare-ftpm-virt-dtb.sh
```

`INSTALL_DIR`を省略すると`install/`。相対パスはリポジトリ基準。
`QEMU_BUILD_DIR`はコンパイル用の中間ディレクトリだけを変更する。起動先の指定ではない。
カスタム配置先をGit管理下へ置く場合は、生成物を追跡しないよう設定する。既定の`install/`はGit管理外。

## 状態ファイルとrootfs

`work/`には.o等の中間ファイルと、仮想デバイス固有の状態を残す。
`device-identity.bin`、`provisioning.bin`、CA秘密鍵、seed、`rootfs.ext4`はinstall処理でコピー・再生成・削除しない。
QEMU起動は`install/`のプログラム・読み取り専用イメージと、`work/ftpm-virt/`の既存状態を組み合わせる。

`build-ubuntu-rootfs.sh OUTPUT_TAR`で出力先のみ指定できる。
従来の`build-ubuntu-rootfs.sh CLIENT_INSTALL_DIR OUTPUT_TAR`も利用できる。
既存ディスクやtarは上書きしない。rootfs全体の新しい管理者権限での組み立ては、この実行環境では未検証。

## 検証

配置済みQEMUと配置済みROMで標準virt検査を実行する。
配置済みのヘッダ・ARM64ライブラリ・TA開発キットでクライアントとprobeをコンパイルする。
配置済みのQEMU・ファームウェア・kernel Image・DTBを使い、既存NV状態でfTPMを起動する。
インストール先へ秘密鍵・仮想デバイス状態が入らないことと、別prefix（空白を含む）の配置も検査する。
[結果](results/install-layout.json)と[起動ログ抜粋](results/install-layout-excerpt.txt)を参照。

## OP-TEEのページテーブル数変更と変更前のエラー

QEMU ARMv8のfTPM構成では、OP-TEEの変換テーブル上限`MAX_XLAT_TABLES`を**8個から32個**に増やした。
修正箇所は[`platform_config.h`](../optee/optee/optee_os/core/arch/arm/plat-vexpress/platform_config.h)の
`PLATFORM_FLAVOR_qemu_armv8a`かつ`CFG_QEMU_JETSON_FTPM`の場合のみ。
NVIDIAのfTPM/helper TA本体や、実機向けT234構成は変更していない。

変更前の8個では、ユーザー環境のOP-TEEセキュアログに次のエラーが出た。
行番号は当時のビルドのもの。

```text
E/TC:0 0 core_mmu_xlat_table_alloc:520 8 xlat tables exhausted
E/TC:0 0 Panic 'Failed to spread pgdir on small tables' at core/mm/core_mmu.c:1922 <core_mmu_map_pages>
```

これはOP-TEEがメモリマッピングに必要な下位変換テーブルを確保できずpanicしたことを示す。
通常側ではシリアルコンソール切り替え付近で出力が止まり、fTPM試験開始前に起動スクリプトがタイムアウトした。
Linuxの最終出力だけでは原因を特定できず、`work/ftpm-virt/secure-first-native.log`で上記panicを確認した。

32個への変更で静的なテーブル領域は32KiBから128KiBへ増え、追加消費は96KiB。
この変更はOP-TEEファームウェアへ組み込むため、DTB再生成だけでは反映されない。
初期構築では本書のfirmwareビルドに含まれる。変更前のfirmwareがある場合は、QEMU停止後に設定済みのビルド環境で次を実行する。

```bash
bash scripts/build-ftpm-virt-firmware.sh
bash scripts/prepare-ftpm-virt-dtb.sh
```

`install/`内のflash.binも更新される。Linux、rootfs、ディスク、CAや鍵の再作成は不要。
再起動する試験の選択は[test-guide.md](test-guide.md)に従い、完了済みのfirstは再実行しない。

テーブル数を増やした後、手元の既存ディスクではPTAとsecondのPASSを確認した。
さらに2026-11-17（日本時間）、ユーザーから[test-guide.md](test-guide.md)の全テストがPASSしたと報告を受けた。
最後の全PASSはユーザー報告であり、この報告に対応する全ログをこちらで再検証したという意味ではない。
[手元の検証結果](results/optee-xlat-tables.json)と[ログ抜粋](results/optee-xlat-tables-excerpt.txt)も参照。

8個を超えた詳細なマッピング内訳と32個の最大負荷時の余裕は未計測。
QEMUとT234実機はプラットフォーム・メモリ配置が異なるため、この結果だけで実機での発生や非発生を断定しない。

## 文書構成の選択

ユーザー指定で旧install-layout.mdをbuild-install.mdへ改名し、ビルド・導入を集約した。
テスト文書名の候補はtest-guide.md、ftpm-tests.md、testing.md、test-procedures.md。ユーザーはtest-guide.mdを選択した。
旧ftpm-test-guide.mdを改名し、初回試験も移して全試験をまとめた。日英で同じ分担とする。

## 実機との差分と検証証拠

[実機とQEMUの違い](hardware-qemu-differences.md)と[最終テストの証拠整理](final-test-evidence.md)を参照。
