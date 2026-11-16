# Dockerを使わないホスト環境

日本語 | [English](en/native-host.md)

[決定0004](decisions/0004-native-host.md)に従い、プロジェクトのビルド・起動・DT生成・ディスク更新はホストで直接実行する。
Docker、buildx、Dockerグループへの所属は不要。

## 配置先と権限

| 対象 | 既定の配置先 | 実行権限 |
| --- | --- | --- |
| QEMU | `install/bin/qemu-system-aarch64` | 通常ユーザーでビルド・配置・起動 |
| OP-TEE・TA・ARM64クライアント | `install/lib/`、`install/libexec/`、`install/share/` | 通常ユーザー |
| 不変の起動イメージ | `install/share/qemu-jetson/` | 通常ユーザー |
| ディスク・デバイス鍵 | `work/ftpm-virt/` | 鍵と既存状態を保持 |
| 依存ツール・開発ライブラリ | apt標準の`/usr/bin`、`/usr/lib`など | 導入時のみ管理者 |
| Ubuntu rootfsの組み立て・新規ext4作成 | 出力は`work/ftpm-virt/` | ゲストのUID/GIDを保存するため管理者 |

ビルド後にMeson installでローカルprefixへ配置する。全体のbin/include/lib/libexec/share構成は[installマニュアル](install-layout.md)を参照。
`INSTALL_DIR=/absolute/path`で全スクリプト共通の配置先を変更できる。`QEMU_BUILD_DIR`はビルド中間物の場所だけを変更する。
旧`work/qemu-container-build/`は自動削除せず、既存の鍵・ディスクも変更しない。

## Ubuntu／Debianの依存ツール

Ubuntu 22.04以降またはDebian 12以降を想定する。

```bash
sudo bash scripts/install-host-deps.sh
bash scripts/build-qemu.sh
```

導入スクリプトは明示的に実行した場合だけaptを使う。ビルド時の自動インストールは行わない。
GCC、Python venv、Ninja、pkg-config、GLib／pixman／zlib／libfdt開発ファイル、dtc、
PRoot、QEMUユーザーモード、e2fsprogs、kmod、検証用fakerootなどを導入する。
Pythonのcryptography・pycryptodome・pyelftoolsはOP-TEE用venvに別途導入する。
NVIDIA指定のAArch64クロスコンパイラは従来どおり必要で、このスクリプトで置き換えない。

```bash
INSTALL_DIR="$PWD/custom-install" JOBS=4 bash scripts/build-qemu.sh
# 起動側も同じ指定にする
INSTALL_DIR="$PWD/custom-install" bash scripts/run-ftpm-virt.sh second
```

`first`は未試験の新規ディスク用。初回試験済みのディスクには再実行しない。
`second`も試験を自動実行し、成功後にゲストをpoweroffする。
既定の配置先を使う場合、`INSTALL_DIR`や旧`FTPM_NATIVE_QEMU`の指定は不要。

## ARM64 Ubuntu rootfs

```bash
sudo env FTPM_FUNCTIONAL_PROFILE=1 \
  KERNEL_MODULES_DIR="$PWD/work/ftpm-virt/modules" \
  bash scripts/build-ubuntu-rootfs.sh /path/to/optee/install/t234 \
  "$PWD/work/ftpm-virt/rootfs.tar"
# 公開fixture／試験プログラムを追加する場合
python3 scripts/prepare-ftpm-test-rootfs.py work/ftpm-virt/rootfs.tar work/ftpm-test-provisioning
sudo bash scripts/create-ftpm-virt-disk.sh
```

PRootでARM64のaptを実行する。ホストがAArch64の場合はユーザーモードのエミュレータを省略する。
ホストのpasswd/groupやホームはゲストへbindしない。ホストへのbinfmt登録やコンテナデーモンは不要。
ゲストサービスの起動は一時的なpolicy-rc.dで抑止する。
ゲストaptが権限を下げてもファイルを参照できるよう、組み立て用一時rootfsだけは`/tmp`の公開親ディレクトリ下に置き、終了時に削除する。
カーネルモジュールの依存情報はホストのdepmodで作成する。
rootfs tarとext4の出力ファイルはsudo実行元ユーザーへ所有者を戻す。

## 既存ディスクの更新

```bash
# 必ずQEMUを停止してから実行する
bash scripts/update-ftpm-test-disk.sh work/ftpm-bound-provisioning
```

ホストのdebugfs/e2fsckで処理する。イメージへの書き込み権限が必要。
公開fixture・試験コードだけを更新し、ゲスト内のUID/GIDはrootへ明示設定する。
既存ディスクを開いているQEMUを検出した場合は中止する。
秘密鍵・seed・NV状態を再生成しない。

## 検証範囲

今回の環境では管理者権限を使ったホストパッケージ導入・rootfs全体の再構築は実行できない。
検証用依存ツールは`work/`へ展開して使用し、ネイティブQEMUビルド、既存ディスクでのfTPM再試験、
ext4のUID/GID・モード保存と上書き拒否を検証済み。
[機械可読結果](results/native-host.json)と[実際のログ抜粋](results/native-host-excerpt.txt)を保存した。
rootfsスクリプトの構文・権限エラーは確認するが、新規rootfsの管理者権限でのend-to-end再構築は未検証である。
以前のfTPM実行結果は[機能検証](ftpm-functional-validation.md)を参照。

最新版の配置・ビルド・導入手順は[installマニュアル](install-layout.md)を参照。

## Ubuntuの証明書パッケージ設定が失敗する場合

`ca-certificates`のpostinstが終了コード127で失敗しても、APTの要約だけでは原因コマンドを断定できない。
rootfs生成時はAPT失敗後に`ROOTFS_DIAG`を出力し、OpenSSLの実行・ライブラリ依存と証明書更新のシェルトレース末尾100行を表示する。
診断用の証明書再生成は破棄される一時rootfsだけで実行し、APTの元の失敗コードで停止する。正常なrootfsとして出力しない。

```bash
git pull --ff-only
set -o pipefail
sudo env FTPM_FUNCTIONAL_PROFILE=1 bash scripts/build-ubuntu-rootfs.sh 2>&1 | tee work/build-rootfs.log
```

失敗時は`ROOTFS_DIAG`を含むログを確認する。rootfsへの試験データ追記・ディスク生成には進まない。

診断トレースは`/bin/sh -ex`で実行し、元の`#!/bin/sh -e`と同様に最初のエラーで停止する。
以前の診断は`-e`を欠き、途中のエラーを越えてstatus=0を出す可能性があった。
`restorecon`が存在する場合は、`-n -v`によるラベルを書き換えない診断も行い、通常の証明書更新が隠すエラー出力を表示する。
この変更は診断の修正であり、APT失敗の解決を意味しない。

### restoreconの終了コード127への対応

ユーザー環境のログで、証明書更新中の`/sbin/restorecon`実行が127で失敗し、
直接実行でも`not found`となることを確認した。`-x`判定は通るが、リンク先を読み出せない状態だった。
リンクの由来までは未特定。Ubuntuゲストの`policycoreutils`（restoreconを提供）をAPTの明示的な依存に追加した。
パッケージが正常に設定され、rootfs作成の`Created .../rootfs.tar`が出ることを成功条件とする。
証明書更新を無効にしたり、パッケージ設定エラーを成功として扱ったりしない。
この変更は構文・回帰試験を実施したが、問題が起きたユーザーホストでの再構築は再確認が必要。
