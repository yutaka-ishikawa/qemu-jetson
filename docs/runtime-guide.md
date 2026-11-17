# 通常起動・SSH・ホスト共有・デバッグ

日本語 | [English](en/runtime-guide.md)

[ビルド・導入](build-install.md)と[テスト](test-guide.md)に加えて、対話的にLinuxを使う手順。
起動コマンドのmanは[日本語](ja/man/run-ftpm-virt.1)／[英語](man/run-ftpm-virt.1)。

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
新規構築の場合はruntime-overlayとopenssh-server/sudo/dbus/dbusがrootfs生成時に組み込まれるため、ディスク更新と下記のゲストパッケージ導入は不要。

## 初期設定用コンソール

rootはロックされ、既定パスワードはない。通常起動でrootへパスワードなしログインする設定ではない。
明示的なsetupモードだけが初期設定用rootシェルを/dev/ttyAMA0へ接続する。
SSHでは常にrootログインとパスワード認証を禁止する。

既存ディスクにサービスを導入するため、共有用に必要なファイルと公開鍵だけを準備する。
以下の鍵ファイルは自分の公開鍵に置き換える。秘密鍵をコピーしない。

```bash
mkdir -p work/runtime-share/scripts work/runtime-share/configs/rootfs
cp scripts/setup-ftpm-runtime-guest.sh work/runtime-share/scripts/
cp -a configs/rootfs/runtime-overlay work/runtime-share/configs/rootfs/
install -m 0644 "$HOME/.ssh/id_ed25519.pub" work/runtime-share/login.pub
bash scripts/run-ftpm-virt.sh setup --ssh --share "$PWD/work/runtime-share"
```

setupコンソールでゲスト内の次を実行する。mountは手動であり自動マウントしない。

```bash
qemu-mount-host
bash /mnt/host/scripts/setup-ftpm-runtime-guest.sh
adduser dev
usermod -aG sudo dev
qemu-register-ssh-key dev /mnt/host/login.pub
poweroff
```

devは任意の一般ユーザー名へ変更する。adduserで設定するパスワードはローカルログイン・sudo用であり、SSHでは受け付けない。
既にユーザーが存在する場合、adduserを再実行しない。公開鍵登録は既存の鍵を残し、重複追加しない。
新規rootfsではパッケージ導入済みなので、setup-ftpm-runtime-guest.shの実行を省略できる。
rootパスワードはこの手順では設定しない。必要な管理は一般ユーザーのsudoで行う。
setupはホスト操作者向けのrootコンソールなので、設定後は通常起動を使う。

## 通常起動とSSH

```bash
bash scripts/run-ftpm-virt.sh
# SSHが必要な場合
bash scripts/run-ftpm-virt.sh --ssh
```

同時起動はしない。既定は4CPU・RAM 1GiB、通常モードに試験実行・自動poweroff・300秒制限はない。
コンソールは作成した一般ユーザーでログインする。SSHは別のホスト端末から接続する。

```bash
ssh -p 2222 -i "$HOME/.ssh/id_ed25519" dev@127.0.0.1
```

SSH待受け転送はlocalhostのみ。--ssh-port 2223等で変更できる。
--sshなしではネットワークデバイスを作らず、sshdも起動条件を満たさない。
SSH設定は/etc/ssh/sshd_config_qemuを使用し、PermitRootLogin no、AuthenticationMethods publickey、PasswordAuthentication noを固定する。

## ホストディレクトリの手動マウント

ホスト側：

```bash
bash scripts/run-ftpm-virt.sh --ssh --share /path/to/host/data
```

ゲスト側：

```bash
sudo qemu-mount-host
ls /mnt/host
sudo umount /mnt/host
```

タグはhostshare。9p/virtioを使い、既定は読み取り専用。マウント先を変える場合はsudo qemu-mount-host /mnt/data。
書込みが必要な場合は両側で明示する。

```bash
# ホスト
bash scripts/run-ftpm-virt.sh --share /path/to/host/data --share-rw
# ゲスト
sudo qemu-mount-host --rw /mnt/host
```

mapped-xattrを使用するため書込み先FSのxattr対応が必要。ホストの権限を超えて書き込めるわけではない。
共有は必要なディレクトリに限定し、ホストの秘密鍵やCA秘密鍵を置いたディレクトリを共有しない。

## CPU数と試験モード

```bash
bash scripts/run-ftpm-virt.sh --cpus 2 --ssh
bash scripts/run-ftpm-virt.sh second --cpus 4
```

CPUは1〜8、既定4。起動時に指定数に合わせてDTBを生成するためdtcが必要。
旧1CPU/GICv2ファームウェアは再ビルドを要求して停止する。新構成はGICv3を使い、NVIDIA配布カーネルは変更しない。
ゲストではgetconf _NPROCESSORS_ONLNで稼働CPU数を確認する。
試験モードは明示的にfirst/second/export/boundを選ぶ。firstを既存の完了済みディスクで実行しない。

## QEMUモニターとGDB

```bash
bash scripts/run-ftpm-virt.sh --qemu-console
```

Ctrl-a cでゲストシリアルとQEMUモニターを切り替える。モニターのinfo cpus、info registers、cont等を使用できる。
quitやCtrl-a xはQEMUの即時終了で、ゲストの正常停止ではない。通常はゲスト内でsudo poweroffする。
別端末から接続する場合：

```bash
bash scripts/run-ftpm-virt.sh --monitor-socket "$PWD/work/qemu-monitor.sock"
# 別のホスト端末（socatが必要）
socat -,raw,echo=0 UNIX-CONNECT:"$PWD/work/qemu-monitor.sock"
```

既存のソケットパスは上書きしない。古いソケットを消す場合はQEMU終了を確認してから行う。
--qemu-consoleと--monitor-socketは排他。

```bash
bash scripts/run-ftpm-virt.sh --gdb --wait-gdb
# 別のホスト端末（AArch64対応GDB）
gdb-multiarch
# GDB内
target remote 127.0.0.1:1234
info registers
continue
```

--gdbは起動を継続、--wait-gdbはCPUを起動前に停止する。--gdb-port 1235で待受けポートを変更できる。
待機中に出力がないのは意図どおり。通常起動は時間制限なし。試験で待つ場合は--timeout 0等を明示する。
この接続はゲストCPU用スタブであり、シンボルは対象のELFとASLR配置に合わせて読み込む。OP-TEE/カーネルのシンボルを自動再配置する機能はない。
QEMU本体をデバッグする場合はホスト用GDBでgdb -p PIDを使う。install内はstrip済みのため、詳細解析には一致するwork/qemu-buildの未stripバイナリを使う。

## manの表示

```bash
man -l docs/ja/man/run-ftpm-virt.1
man -l docs/man/run-ftpm-virt.1
# installへ配置したページを検索
MANPATH="$PWD/install/share/man:${MANPATH:-}" man run-ftpm-virt
```

man/SSHクライアント/socat/GDBはホストに必要な場合だけ導入する。変更の判断記録は[0008](decisions/0008-interactive-runtime.md)。

通常の電源断ではqemu-ftpm-shutdown.serviceがsupplicantより先にTPM2_Shutdownとドライバ解放を実行する。バックエンド停止後にカーネルがTPMを終了しようとして待つことを避けるための順序設定。

8CPU対応は、この構成だけTF-AのMPIDR配置をQEMU GICv3へ合わせている。他の構成の配置は変更しない。ランチャーとディスク更新は共通ロックで同時操作を防止する。

## 検証結果

開発側の既存ディスクで4/8CPUのLinux、一般ユーザー公開鍵SSH、root/パスワード認証拒否、9p手動マウント（RO/RW）、モニター切替・UNIX接続、GDB停止/レジスタ取得、通常電源断を確認した。4/8CPUのboundもPASS。
新規rootfs全体の管理者権限での再構築は未実施。詳細は[機械可読結果](results/runtime.json)と[ログ抜粋](results/runtime-excerpt.txt)を参照。

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
