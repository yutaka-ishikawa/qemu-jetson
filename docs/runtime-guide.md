# 通常起動・SSH・ホスト共有・デバッグ

日本語 | [English](en/runtime-guide.md)

[ビルド・導入](build-install.md)と[テスト](test-guide.md)に加えて、対話的にLinuxを使う手順。
起動コマンドのmanは[日本語](ja/man/run-ftpm-virt.1)／[英語](man/run-ftpm-virt.1)。

新規環境は[build-install.md](build-install.md)から開始する。既存ディスクの更新は先に[upgrade-guide.md](upgrade-guide.md)を実施する。

## 初期設定用コンソール

rootはロックされ、既定パスワードはない。通常起動でrootへパスワードなしログインする設定ではない。
明示的なsetupモードだけが初期設定用rootシェルを/dev/ttyAMA0へ接続する。
SSHでは常にrootログインとパスワード認証を禁止する。

新規構築後は公開鍵だけを共有用ディレクトリへ準備する。以下の鍵ファイルは自分の公開鍵に置き換え、秘密鍵はコピーしない。
既にユーザー・公開鍵登録済みなら、この初期設定を飛ばして通常起動へ進む。

```bash
mkdir -p work/login-share
install -m 0644 "$HOME/.ssh/id_ed25519.pub" work/login-share/login.pub
bash scripts/run-ftpm-virt.sh setup --share "$PWD/work/login-share"
```

setupコンソールでゲスト内の次を実行する。mountは手動であり自動マウントしない。

```bash
qemu-mount-host
adduser cradsec
usermod -aG sudo cradsec
qemu-register-ssh-key cradsec /mnt/host/login.pub
```

電源を切る前に、ゲスト内で`/home/cradsec/.ssh/authorized_keys`の配置を確認する。

```bash
stat -c '%a %U:%G %n' /home/cradsec/.ssh /home/cradsec/.ssh/authorized_keys
ssh-keygen -lf /mnt/host/login.pub
ssh-keygen -lf /home/cradsec/.ssh/authorized_keys
grep -Fqx -f /mnt/host/login.pub /home/cradsec/.ssh/authorized_keys && echo 'Public key installed: OK'
```

`stat`で`.ssh`が`700 cradsec:cradsec`、`authorized_keys`が`600 cradsec:cradsec`であることを確認する。
2つの`ssh-keygen`出力に同じ鍵のフィンガープリントがあり、`Public key installed: OK`が表示されれば登録を確認できる。
既存の鍵がある場合、authorized_keys側には複数のフィンガープリントが表示される。
ファイルがない、所有者・権限が異なる、または鍵が一致しない場合は、公開鍵の入力先を確認して登録コマンドを再実行し、再確認する。
確認できたら電源を切る。

```bash
poweroff
```

例ではcradsecを使用する。必要なら任意の一般ユーザー名へ変更する。adduserで設定するパスワードはローカルログイン・sudo用であり、SSHでは受け付けない。
既にユーザーが存在する場合、adduserを再実行しない。公開鍵登録は既存の鍵を残し、重複追加しない。
新規rootfsには必要なサービスが導入済み。ここではビルドやパッケージ導入を行わない。
rootパスワードはこの手順では設定しない。必要な管理は一般ユーザーのsudoで行う。
setupはホスト操作者向けのrootコンソールなので、設定後は通常起動を使う。

## 通常起動（オプションなし）

以降は連続して実行する手順ではなく、目的に応じて選ぶ起動例。ホスト側の`run-ftpm-virt.sh`は1つだけ実行する。
別の起動例を試す場合は、先にゲスト内で`sudo poweroff`し、QEMUの終了を待つ。
オプションは組み合わせられるが、`--qemu-console`と`--monitor-socket`は同時指定できない。
各節の「ゲスト側」「別のホスト端末」「GDB内」は、その起動例を使う場合に続けて行う操作。

```bash
bash scripts/run-ftpm-virt.sh
```

同時起動はしない。既定は4CPU・RAM 1GiB、通常モードに試験実行・自動poweroff・300秒制限はない。
コンソールは作成した一般ユーザーでログインする。

## 起動オプション1：SSH

SSHを使う場合は、オプションなしの起動に代えて次を選ぶ。

```bash
bash scripts/run-ftpm-virt.sh --ssh
```

起動後、別のホスト端末から接続する。

```bash
ssh -p 2222 -i "$HOME/.ssh/id_ed25519" cradsec@127.0.0.1
```

SSH待受け転送はlocalhostのみ。--ssh-port 2223等で変更できる。
--sshなしではネットワークデバイスを作らず、sshdも起動条件を満たさない。
SSH設定は/etc/ssh/sshd_config_qemuを使用し、PermitRootLogin no、AuthenticationMethods publickey、PasswordAuthentication noを固定する。

## 起動オプション2：ホスト共有（9p・手動マウント）

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

ホスト側（読み取り専用の起動例に代えて選ぶ）：

```bash
bash scripts/run-ftpm-virt.sh --share /path/to/host/data --share-rw
```

その起動後、ゲスト側：

```bash
sudo qemu-mount-host --rw /mnt/host
```

mapped-xattrを使用するため書込み先FSのxattr対応が必要。ホストの権限を超えて書き込めるわけではない。
共有は必要なディレクトリに限定し、ホストの秘密鍵やCA秘密鍵を置いたディレクトリを共有しない。

## 起動オプション3：CPU数

2CPUとSSHを組み合わせて起動する例：

```bash
bash scripts/run-ftpm-virt.sh --cpus 2 --ssh
```

CPUは1〜8、既定4。起動時に指定数に合わせてDTBを生成するためdtcが必要。
旧1CPU/GICv2ファームウェアは再ビルドを要求して停止する。新構成はGICv3を使い、NVIDIA配布カーネルは変更しない。
ゲストではgetconf _NPROCESSORS_ONLNで稼働CPU数を確認する。

## 起動オプション4：QEMUコンソール・モニター

```bash
bash scripts/run-ftpm-virt.sh --qemu-console
```

Ctrl-a cでゲストシリアルとQEMUモニターを切り替える。モニターのinfo cpus、info registers、cont等を使用できる。
quitやCtrl-a xはQEMUの即時終了で、ゲストの正常停止ではない。通常はゲスト内でsudo poweroffする。
別端末から接続する場合：

```bash
bash scripts/run-ftpm-virt.sh --monitor-socket "$PWD/work/qemu-monitor.sock"
```

その起動後、別のホスト端末（socatが必要）：

```bash
socat -,raw,echo=0 UNIX-CONNECT:"$PWD/work/qemu-monitor.sock"
```

既存のソケットパスは上書きしない。古いソケットを消す場合はQEMU終了を確認してから行う。
--qemu-consoleと--monitor-socketは排他。

## 起動オプション5：GDB

GDB接続を待ってCPUを停止する起動例：

```bash
bash scripts/run-ftpm-virt.sh --gdb --wait-gdb
```

その起動後、別のホスト端末（AArch64対応GDB）：

```bash
gdb-multiarch
```

GDB内：

```text
target remote 127.0.0.1:1234
info registers
continue
```

--gdbは起動を継続、--wait-gdbはCPUを起動前に停止する。--gdb-port 1235で待受けポートを変更できる。
待機中に出力がないのは意図どおり。通常起動は時間制限なし。試験で待つ場合は--timeout 0等を明示する。
この接続はゲストCPU用スタブであり、シンボルは対象のELFとASLR配置に合わせて読み込む。OP-TEE/カーネルのシンボルを自動再配置する機能はない。
QEMU本体をデバッグする場合はホスト用GDBでgdb -p PIDを使う。install内はstrip済みのため、詳細解析には一致するwork/qemu-buildの未stripバイナリを使う。

## 起動オプション6：試験モード

通常起動に代えて、自動試験を実行するモード。以下はsecondを実行する段階で選ぶ例であり、通常利用に必要な追加操作ではない。

```bash
bash scripts/run-ftpm-virt.sh second --cpus 4
```

試験モードは明示的にfirst/second/export/boundを選ぶ。firstを既存の完了済みディスクで実行しない。
試験は自動終了する。実行順序・前提条件・成功判定は[test-guide.md](test-guide.md)に従う。

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
