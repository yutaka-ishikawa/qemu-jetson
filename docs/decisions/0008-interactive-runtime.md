# 0008: 通常起動・SSH・ホスト共有・CPU数

日本語 | [English](../en/decisions/0008-interactive-runtime.md)

状態：通常起動・manページ・CPU数指定（既定4）はユーザー指示済み。SSH認証と共有方式もユーザー指定済み。

現在のrootはパスワードなしでロックされている。既定パスワードは存在しない。
変更前の起動はfirst/second/export/boundの自動試験専用だった。通常起動を追加し、自動試験と自動電源断を行わない。
現OP-TEEビルドのCPU上限1では4CPU起動を保証できないため、TF-Aの上限8に合わせてOP-TEEを8CPU対応で再ビルドする。
起動時の既定は4、指定範囲は1〜8とし、DTB内のCPU数と一致させる。

| 当初の提案（履歴。採用結果は後述） | 候補A | 候補B |
| --- | --- | --- |
| SSH認証 | root公開鍵認証。コンソール用rootパスワードはユーザーが手元で設定 | rootパスワード認証も許可。パスワードは手元で設定 |
| ホスト共有 | 9p。配布カーネルのCONFIG_NET_9P_VIRTIO=y/CONFIG_9P_FS対応を使う | virtio-fs。現在の配布カーネルは非対応で再ビルドとvirtiofsd導入が必要 |

SSHは起動オプションで有効化し、ホストの127.0.0.1ポート転送を使用する設計。
ホスト共有は指定されたディレクトリのみ公開し、ゲスト内の専用コマンドを手動実行してマウントする設計。
既存のTPM状態・seed・CA・ディスクを初期化しない。既存ディスクへのサービス導入・設定手順も用意する。
選択後、採用結果と具体的なコマンドを日英manと手順へ記載する。

## 採用結果

ユーザー指定：root SSHは禁止。SSHは一般ユーザーの公開鍵認証のみ。
初期起動後にユーザーと公開鍵を登録し、共有方式は9pを採用する。
既定パスワードは設定しない。明示的なsetup起動だけ、初期設定用rootコンソールを提供する。
通常起動・SSHではこのコンソールの無認証設定を利用しない。
共有は既定read-only、--share-rwで明示的に書込み可能。ゲスト内で手動マウントする。

### 複数コアとGICの追加判断

4CPU試験でNVIDIA配布カーネルのGICv2初期化に失敗し、ipi_setup/__ipi_send_maskでpanicした。
ソースではSGI割当て側のparam_count=1と、変換側が要求するパラメータ数が一致しない。
候補A：QEMU/TF-A/OP-TEEをGICv3へ統一して配布カーネルを保持。
候補B：カーネルのGICv2処理を修正し再ビルド。
ユーザーはAを選択。GICv3と最大8CPU対応のファームウェアを再ビルドする。
既存1CPU構成の検証結果を、そのまま4CPUの検証結果とは扱わない。

### デバッグ

追加指示に従い、--qemu-console、--monitor-socket、--gdb/--gdb-port、--wait-gdbを提供する。
GDBはlocalhostで待ち受けるゲストCPU用リモートスタブ。QEMUホストプロセスへのgdb -pとは区別する。

### DTBの64ビット値の配置

GICv3のDTBでsecure-chosen/kaslr-seedが4バイト境界となり、OP-TEE早期の64ビット読出しでalignment faultが発生した。
align-optee-dtb.pyがFDT_NOPを挿入して8バイト境界へ揃える。seed値やASLRを無効化せず、NVIDIAコードも変更しない。
TF-Aは旧GICv2中間物を混ぜないためwork/tf-a-gic3でビルドする。

実装時に追加で確認した点：
- TF-Aの標準QEMU構成は1クラスタ4CPUを前提にMPIDRを検証する。QEMU GICv3のAff0=0..7へ合わせ、この構成だけQEMU_JETSON_FTPM=1で1クラスタ8CPUにする。
- GICv3用TF-Aはwork/tf-a-ftpmへ隔離し、旧GICv2の中間物を混用しない。
- OP-TEEの早期kaslr-seed読出しは64ビット境界が必要。標準FDT_NOPを挿入してDTBデータだけを整列し、seed値とNVIDIA OP-TEEの読出し関数は変更しない。
- 通常電源断は、TPM2_Shutdown・fTPMドライバ解放をsupplicant停止より先に実行する。
