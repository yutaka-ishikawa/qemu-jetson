# 既存QEMU環境の更新手順

日本語 | [English](en/upgrade-guide.md)

既存ディスクを使い、アカウント・公開鍵・SSHホスト鍵・仮想ID・seed・CA・TPM NV状態を保持したまま更新する。
新規clone・新規ディスクの構築は本書ではなく[build-install.md](build-install.md)を参照。
ホスト側でディスクを更新する前にQEMUを停止する。エラー時はそこで止め、ディスク作り直しや鍵再生成で回避しない。

## 既存環境の更新（初回のみ）

QEMUを終了してから、リポジトリ直下で実行する。既存のディスク・ID・seed・CAを保持する。
ホスト依存にlibslirp-devとlibattr1-devが追加された。コマンドは各段階の成功を確認してから続ける。

```bash
git pull --ff-only
sudo bash scripts/install-host-deps.sh
# build-install.mdに従いNVIDIA CROSS_COMPILE、dtc、Python venvを設定
bash scripts/build-qemu.sh
bash scripts/build-ftpm-virt-firmware.sh
sudo bash scripts/install-ftpm-runtime-overlay.sh
python3 scripts/install-artifacts.py manual
```

QEMUは9pとユーザーネットワーク対応、ファームウェアはGICv3・最大8CPU対応で再ビルドする。
既存ディスクはファイル更新だけを行い、rootfs.tarやrootfs.ext4を作り直さない。
install-ftpm-runtime-overlay.shはsudoで実行する。QEMUが使用中なら中止する。ディスク所有者は変更せず、新規ロックファイルもディスク所有者へ戻すため、通常起動は一般ユーザーで行える。


## 古いゲストに不足するサービスを導入

openssh-server・sudo・dbusとruntime設定が既に導入済みなら本節は不要。
通常起動対応前に作成したディスクだけ、公開の導入スクリプト・設定を共有する。

```bash
mkdir -p work/runtime-share/scripts work/runtime-share/configs/rootfs
cp scripts/setup-ftpm-runtime-guest.sh work/runtime-share/scripts/
cp -a configs/rootfs/runtime-overlay work/runtime-share/configs/rootfs/
bash scripts/run-ftpm-virt.sh setup --ssh --share "$PWD/work/runtime-share"
```

ゲストのsetupコンソールで実行する。

```bash
qemu-mount-host
bash /mnt/host/scripts/setup-ftpm-runtime-guest.sh
poweroff
```

ゲストのパッケージ取得にインターネット接続（または明示的なプロキシ設定）が必要。
ユーザーや鍵は作り直さない。新たなユーザー・公開鍵が必要なら[通常利用の初期設定](runtime-guide.md#初期設定用コンソール)へ進む。
登録済みの場合は[runtime-guide.md](runtime-guide.md)の通常起動から使える。

## 通常起動でシリアルログインが出ない場合

通常モードでもttyAMA0で一般ユーザーのログインができる。--sshはシリアルログインを無効にしない。
旧runtime-overlayのsetupサービスにConflicts=serial-getty@ttyAMA0.serviceがあり、setupの起動条件が偽でもsystemdのジョブ依存関係が通常のシリアルgettyを止めていた。
修正版はConflictsを除去し、setupとgettyそれぞれの逆のConditionKernelCommandLineで切り替える。
QEMU終了後に次を実行する。再ビルドやアカウント・鍵の再登録は不要。

```bash
git pull --ff-only
sudo bash scripts/install-ftpm-runtime-overlay.sh
bash scripts/run-ftpm-virt.sh --ssh
```

rootの通常ログインを有効にする修正ではない。コンソールには作成済みの一般ユーザーと、そのローカルパスワードでログインする。

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

