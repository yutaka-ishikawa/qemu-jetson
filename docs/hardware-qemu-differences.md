# Jetson実機とQEMU環境の違い

日本語 | [English](en/hardware-qemu-differences.md)

対象はJetson Orin Nano（T234）と、本リポジトリのB2機能検証構成`jetson-ftpm-virt`。
QEMUでの試験合格は、実機と全ハードウェア・全TPMコマンド・保護強度が同一という意味ではない。
実機との同条件の比較測定は未実施。実機欄の保護機能は、製品の設定・製造時プロビジョニングに依存する。

## QEMU自体を修正しているか

**修正している。** 本リポジトリに同梱したQEMU 11.1.3のソースへ直接変更を加えている。
標準QEMUに起動オプションを指定するだけの構成ではない。

現在のB2で使う主な追加実装は[jetson-ftpm-virt.c](../qemu/hw/arm/jetson-ftpm-virt.c)。
標準virtマシンを継承した独自マシンjetson-ftpm-virtを登録し、次の機能を追加している。

| 追加機能 | 実装内容 |
| --- | --- |
| identity-file | 72バイトのJFTPM001を検証・読込み。Secureアドレス空間0x0c200000に4KiBのROM領域として配置 |
| provisioning-file | JFPRV001を検証・読込み。Secureアドレス空間0x0c400000に64KiBのRAM領域を配置。PTAによるコピー後の消去を許容 |
| リセット処理 | 保存した初期provisioning内容からRAMを復元。ホスト側ファイルはQEMUから書き換えない |
| 設定変更の制限 | 初期化後のidentity-file/provisioning-file変更を拒否 |
| ビルド登録 | [meson.build](../qemu/hw/arm/meson.build)で独自マシンのソースを追加 |

これはB2の仮想ID・provisioning供給機構であり、実機Fuse ControllerやSEをそのまま再現する仕組みではない。
Secure空間への配置はゲスト側の分離であり、ホスト管理者からの秘密保護を意味しない。
TPMコマンド処理はQEMU内の別TPM実装へ置き換えておらず、ゲスト内のNVIDIA fTPM TAが行う。
現在の[起動スクリプト](../scripts/run-ftpm-virt.sh)もQEMUの-tpmdevやswtpmを使用しない。

別経路の[jetson-t234-dev.c](../qemu/hw/arm/jetson-t234-dev.c)等にも独自のT234モデル実装がある。
こちらのFuseモデルの状態と、B2のPASSは区別する。
OP-TEE側にもQEMUプラットフォーム移植と[ページテーブル上限の変更](page-table-analysis.md)がある。
したがって「NVIDIA TA/PTA本体を極力変更しない」と「QEMUもOP-TEEプラットフォームも無変更」は別である。

## プラットフォームとソフトウェア

| 項目 | Jetson実機 | 現在のQEMU B2 |
| --- | --- | --- |
| CPU・周辺機器 | Orin NanoのCortex-A78AEとTegra周辺機器 | virtを基にした仮想機械。起動スクリプトはCortex-A57、既定4 CPU（1〜8指定可）、RAM 1GiB、GICv3 |
| NVIDIA開発環境 | Jetson向けクロスビルド | 同じNVIDIAツールチェーンで対象コードを再ビルド。実機用バイナリ全般の無変更実行は保証しない |
| Linux | 対応L4TカーネルとTegraドライバ | NVIDIA配布L4T R36.5.2のImage（5.15.199-tegra）と対応fTPMモジュール。Tegra機器を使うドライバは未再現部分がある |
| ユーザーランド | 配布イメージ・導入パッケージによる | Ubuntu 22.04 ARM64 baseに必要なサービス・ツールを追加。Jetsonユーザーランド全体の複製ではない |
| OP-TEE | T234向けプラットフォーム | vexpress-qemu_armv8aにNVIDIA helper PTAとデータ供給経路を移植 |
| fTPM/helper TA | NVIDIA版TA | NVIDIA版ソースを再ビルド。検証対象のTA/PTA本体のソース同一性は既存のハッシュ検査で確認。プラットフォームまで無変更という意味ではない |
| GPU・CUDA | 実GPUで実行 | 未提供。今回の要件外 |
| ブート | Jetsonの製品ブートチェーン | QEMU向けTF-A、OP-TEE、Linux entry shimを使用。BootROM、MB1/MB2、製品Secure Bootチェーン全体は再現しない |
| I/O・性能 | 実ストレージ、割り込み、タイミング | virtio-blk、仮想UART等。性能、競合、タイムアウト、実時間精度の同等性は未検証 |
| ネットワーク | 実機の設定次第 | 既定-nic none。--sshでvirtio-net/ユーザーネットワークとlocalhost転送を有効化。一般ユーザー公開鍵SSHを提供 |

## eFuse・鍵・証明書・永続状態

| 項目 | Jetson実機 | 現在のQEMU B2 |
| --- | --- | --- |
| eFuse | OTPの識別情報・設定・秘密値。焼き込みと保護は実機仕様に依存 | B2はファイル由来の仮想ID/秘密とprovisioningをPTAへ供給。OTPの不可逆性を持たない |
| SE・鍵スロット | Tegraの暗号ハードウェアとハードウェア鍵経路 | SE全体、実機鍵スロット、秘密値の非抽出性を再現しない |
| ID・seed | 製造・プロビジョニング経路による | work/ftpm-virt/device-identity.binとprovisioning.bin等に永続化。ホスト管理者が読出し・交換・複製可能 |
| SN・ECID | 実Fuseから取得・変換 | B2はテスト値をAPIへ供給。実機の固有IDや製造履歴ではない |
| EK証明書 | 製品の発行・信頼体系次第 | 独自のQEMU専用テストCA。実際の仮想fTPM EKとの一致とNV読出しは試験するが、NVIDIA製造証明ではない |
| SIGN_EK_CSR | NVIDIA helperのFirmware ID署名経路 | Firmware IDテスト鍵で検証。EK秘密鍵による署名や製造CAによる証明書発行と混同しない |
| TPM利用経路 | OP-TEE、カーネルドライバ、クライアント | /dev/tpmrm0経由のTPMコマンドとhelper PTA APIを検証。全コマンドの同等性は未検証 |
| 永続化 | 製品のストレージ構成に依存 | 同じディスク・ID・seedを使う独立QEMUプロセス間でNV、鍵、sealed data、EK証明書を検証 |
| 保護・ロールバック | 構成したハードウェア保護・ストレージ方式に依存 | REE filesystem使用。ホストによるディスク差し戻し・秘密取得・VM複製への耐性は提供しない |
| 乱数 | 実機の乱数・暗号サービス構成 | QEMU側でホスト/dev/urandomとvirtio-rngを使用。物理乱数源と認証強度の同等性は主張しない |

ゲストのTPM API経由でEK秘密鍵をexportしていないことと、ホスト管理者から秘密を保護できることは別。
仮想ID・seed・ディスクを一緒に複製すると同一の仮想TPM状態を複製できる。
TPM Clear、OS再インストール、スナップショット、ライブマイグレーションの全組合せは未検証。

## 機能と設定上の制約

- PCR extendと再起動時のPCRリセットは試験済み。ただしMeasured Bootは無効。実機の測定値やブートイベントログを再現しない。
- INJECT_EPSは無効で、呼出しを拒否することを確認した。
- ゲストSELinuxは承認済みのAに従いLSMリストから除外する。ホストSELinuxは変更しない。製品のアクセス制御構成と同等ではない。
- QEMU fTPM構成だけOP-TEEのMAX_XLAT_TABLESを8→32へ変更。元の構成ではテーブル不足でpanicした。
  32個で試験は通ったが最大負荷時の余裕は未計測。実機のメモリ配置・テーブル使用量を同じとは扱わない。
- 機能試験はTPM能力照会、乱数、NV、PCR、RSA署名、seal/unseal、helper API、証明書・CSR・Firmware ID署名、実EKとの一致、標準証明書NVを対象とする。
  全TPMコマンド、全OSサービス、リモート認証、物理攻撃への耐性は網羅していない。

## 別構成jetson-t234-devとの区別

[読み取り専用Fuseモデル](t234-fuse.md)はT234ハードウェア再現用の別構成jetson-t234-devに属する。
対応レジスタ読出しとNVIDIAのSN/ECID変換関数を検証したが、OTP書込み・秘密Fuse・SEは未実装で、SE0初期化で停止する。
B2のfTPM PASSをもって、このT234構成が完成したとは扱わない。

## 根拠と利用範囲

[ビルド・導入](build-install.md)、[テスト手順](test-guide.md)、[helper PTA移植](ftpm-helper-port.md)、
[CSR署名](ek-csr-signing.md)、[従来の検証結果](ftpm-functional-validation.md)を参照。
本構成は、NVIDIA版fTPM/helperのソフトウェア機能、API連携、状態の保持、証明書処理を開発・試験するための環境。
製品の信頼基盤・保護強度や実機での最終検証を代替しない。

[ページテーブル計測](page-table-analysis.md)でQEMUの観測ピーク9/32個を確認。実機の使用数を示すものではない。

対話起動・SSH・9p共有・デバッグの設定は[通常起動ガイド](runtime-guide.md)を参照。ページテーブル計測は当時の1CPU構成であり、4/8CPUの最大使用数を示すものではない。
