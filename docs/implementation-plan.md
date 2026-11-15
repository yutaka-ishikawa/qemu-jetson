# QEMU Jetson OP-TEE／fTPM 実装手順

日本語 | [English](en/implementation-plan.md)

作成日：2026-11-16（日本時間）。本書は実装前の手順書。
完了済みはNVIDIA版OP-TEE／fTPMの無変更ビルドと依存調査まで。
QEMUマシンモデル、起動ファームウェア、実行試験はこれから行う。

## 1. 基準と実装境界

- [設計書](qemu-boot-design.md) に従う。
- NVIDIA側：Jetson Linux R36.5.2、既存のT234向けビルド成果物を使用。
- QEMU側：**11.1.3（調査時点の最新安定版）**。
- 公式Git： https://gitlab.com/qemu-project/qemu.git
- タグ：`v11.1.3`。
- コミット：`005c61c0ef6f6ae615283440b4bb7be51b2c6ddd`。
- 公式配布物： https://download.qemu.org/qemu-11.1.3.tar.xz
- 公式リリース確認元： https://www.qemu.org/download/

公式ページには11.2.0-rc0（2026-11-11）もある。RCは開発候補版なので、
本計画では11.1.3（2026-10-28）を最新安定版として選ぶ。
バージョン番号だけでなくタグが指すコミットを公式Gitのls-remoteで確認済み。
未リリース版が必要になった場合は本書の基準版を明示的に変更する。

NVIDIAのOP-TEE／fTPMソースはまず無変更で維持する。
専用QEMUマシンと試験用EL3ファームウェアを本リポジトリで開発する。
NVIDIA版ATFやMB2全体の無変更実行は初期実装の対象外。
最初はTCG／1 CPUで進める。CUDA／GPUは実装しない。

## 2. リポジトリ構成（実装時に作成）

```text
docs/                       設計、ビルド、実行、検証記録
manifests/                  取得元、固定コミット、入力ハッシュ
scripts/                    取得・ビルド・起動・成果物確認
patches/qemu/11.1.3/         公式QEMUへの追加・変更パッチ
firmware/                   本プロジェクトの試験用EL3ファームウェア
configs/                    仮想マシン、DT生成、テスト用Fuseの設定
tests/                      MMIOモデル、起動、TPMの試験
```

上記は予定構成であり、既に存在するディレクトリを意味しない。
QEMU原本は公式リポジトリから取得し、追加コードをパッチとして管理する。
NVIDIA配布物、第三者原本、大容量ビルド成果物、仮想デバイスの秘密状態はGit管理外に置く。
取り込むコードのライセンスと著作権表示をファイルごとに維持する。

## 3. QEMU原本の固定とベースライン確認

1. manifestsに上記の公式URL、タグ、コミットを保存する。
2. 作業領域に公式Gitから対象タグを取得する。
3. HEADが固定コミットと一致することを確認する。
4. 選定版のビルド依存を公式configureと文書で確認する。
5. AArch64 system emulationを対象に、未変更QEMUをビルドする。
6. バージョン、利用可能なCPU、secure=onのマシン設定を確認する。

取得・ビルドコマンドの予定形（この段階では未実行）：

```bash
git clone --depth 1 --branch v11.1.3 https://gitlab.com/qemu-project/qemu.git work/qemu
git -C work/qemu rev-parse HEAD
mkdir -p work/qemu-build
cd work/qemu-build
../qemu/configure --target-list=aarch64-softmmu --disable-werror
ninja
./qemu-system-aarch64 --version
./qemu-system-aarch64 -machine help
./qemu-system-aarch64 -cpu help
```

configureオプションと依存パッケージは実際のホストで確認後に実行手順書へ固定する。
本計画のコマンド例を実行済み手順と混同しない。

## 4. 段階A：OP-TEEの最初のログ

### 4.1 専用マシン

仮称 `jetson-t234-dev` を追加する。これは開発用の部分モデル。
QEMUの既存Arm CPU、アドレス空間、RAM、タイマ等の部品を再利用し、
標準virtのFlash配置との衝突を回避する。

- Secure EL1とEL3を利用できるCPU構成を選び、PAUTH対応を確認する。
- CPUのMPIDRとOP-TEEのコア番号計算が一致することを確認する。
- 公式ビルドのTZDRAM開始`0x80000000`とサイズ`0x03fc0000`を基準にSecure RAMを配置する。
- EL3ファームウェア、OP-TEE、DT、非Secure RAMの配置表を作成し、範囲の重複を検査する。
- Secure RAMが非Secureアクセスから保護されることを試験する。
- 未実装MMIO、例外、停止位置をログまたはトレースに残す。

### 4.2 TCUモデル

`0x0c198000`にCombined UARTの最小モデルを追加する。
送信ワードの文字数・flush・busyの扱いは公開ドライバに合わせる。
char backendへ出力し、リセット状態とアクセス幅を定義する。
TCUはこの段階で送信観測に必要な範囲を実装し、未実装機能を明記する。

単体試験で、文字出力、busy解除、flush、リセット後の動作を確認する。

### 4.3 起動ファームウェア

本プロジェクトの小さなEL3起動コードを追加し、NVIDIAツールチェーンでビルドする。
必要なシステムレジスタと例外ベクタを設定し、Secure EL1へ遷移する。
OP-TEE初回引数は設計書のOPTEED契約を基準に構成する。
QEMUの汎用loaderだけで十分とは扱わない。

- ELFのロードセグメントとtee-raw.bin生成形式を確認し、正しい位置・入口へ配置する。
- 外部DTを用意し、x2で渡す。DT容量はビルド設定の最大サイズとの整合も確認する。
- 例外時はESR、ELR、FARなどを記録して停止する。
- OP-TEE初期化完了のSMCに到達した場合、未処理呼び出しとして黙って続行しない。

### 4.4 実行と判定

起動スクリプトに入力ハッシュ、CPU、マシン、メモリ、ファームウェアの版を記録させる。
タイムアウト付きで実行し、TCUログと未実装アクセスを保存する。

合格条件は、前段階と同じ無変更OP-TEEがログを出し、次の停止原因を特定できること。
タイムアウトを成功扱いしない。ここではTPMやOP-TEE初期化完了の成功を要求しない。

## 5. 段階B：初期化完了

段階Aの観測結果に基づき、最初に必要なデバイスから追加する。

1. Fuseモデルを追加する。ECID／SN、BSI、security modeを読み取り専用で提供する。
2. SNのバイト順をEKBとの比較に使える形で試験する。
3. 公開仕様からSEの必要なコマンド、鍵スロット、完了・エラー通知を実装する。
4. 乱数生成はゲスト要求に応じてホスト乱数から供給する。固定値を乱数として返さない。
5. EKB、シード、boot-mode、イベントログ等を必要に応じてDTとSecure RAMへ配置する。
6. 必要なSMC処理を用意し、OP-TEEのENTRY_DONEへの到達を確認する。

CCCはprebuiltなので公開CソースだけではSEの全仕様が確定しない。
不明点は公開仕様と実アクセスから調べ、逆アセンブルを前提としない。
SEが未実装の状態でダミー成功を返して先へ進めても、段階B合格とはしない。
initcall失敗、panic、未実装MMIO、乱数・暗号処理を確認してから合格とする。

## 6. 段階C〜E：LinuxとfTPM

- **C**：QEMU配置に対応するSecure Monitorを構成する。TF-A OPTEED等の利用を検討し、
  Linux OP-TEE driver、tee-supplicant、TA呼び出し、REE FS保存を確認する。
- **D**：LinuxのfTPM TEE driverとtpm2-toolsを用意する。GetCapability、PCR、NV、
  鍵生成、seal／unseal、再起動後の再利用を実行する。
- **E**：Fuse、シード、EKB、ストレージ鍵、EK／証明書を仮想デバイス単位で整合させる。
  TPMクリア、別デバイス、複製、スナップショットでの結果を定義・検証する。

段階Dだけの成功を、実機同等のデバイス認証やFuseの再現成功とは扱わない。
実機比較が可能になったら同一L4T・同一コマンドで差分を確認する。

## 7. 変更と進捗の記録

各段階で実装差分、ビルド手順、実行コマンド、入力ハッシュ、試験結果、
未実装機能を文書化してpushする。NVIDIAソース変更が必要になった場合は、
変更箇所と理由、QEMU側だけで対応する場合の規模を示して設計を更新する。

最新QEMUへの追従は自動更新にしない。新安定版が出た際にパッチを移植し、
到達済み段階の試験を通してから基準コミットを更新する。

ユーザーランドはUbuntu 22.04 ARM64を採用する。[rootfs構築手順](ubuntu-rootfs.md)を参照。
