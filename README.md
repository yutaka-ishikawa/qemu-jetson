# qemu-jetson

現在のビルド・起動はDocker不要です。まず[ホスト環境の準備](docs/native-host.md)を参照してください。QEMUは`install/bin/`へ配置します。ビルド中間物は`work/qemu-build/`です。[ビルド・インストール手順](docs/build-install.md)を参照。

日本語 | [English](README.en.md)
QEMU for NVIDIA Jetson Orin Nano

NVIDIA版OP-TEE／fTPMを、ソース変更を極力抑えてQEMU上で動かすための開発プロジェクトです。

## 必要なディスク容量の目安

### ビルド・インストール後の実測値

2026-11-17（日本時間）、ユーザー環境でbuild & install後の`du -sh qemu-jetson`は**5.4G**でした。
以下は同じ環境の`du -sh *`から抜粋した主要ディレクトリの占有量です（単位・丸めはduの表示どおり）。

| ディレクトリ | 実測値 |
| --- | ---: |
| work/ | 2.4G |
| kernel/ | 1.3G |
| qemu/ | 882M |
| install/ | 486M |
| optee/ | 54M |
| firmware/ | 38M |
| samples/ | 436K |

5.4Gは構築後のリポジトリ全体の占有量であり、下表の概算より小さい実測例です。
ビルド・展開中の一時ディレクトリやリポジトリ外の領域を含むピーク使用量は未計測です。
`du -sh *`には.git等の隠し項目が含まれないため、この抜粋を全体の完全な内訳として合算しません。
この測定だけでは、全テスト実行時のピーク容量や必要最小空き容量は確定できません。

### 一時領域を含めた容量計画（概算）

新規構築から全テストまで実行する場合、**空き容量30GB以上、余裕を見て50GBを推奨**します。
既存環境を残して別ディレクトリで構築する場合は、追加でこの容量を確保してください。

| 用途 | 概算 |
| --- | ---: |
| Git管理情報・同梱ソース | 3〜5GB |
| ツールチェーン・取得アーカイブ | 2〜5GB |
| QEMU・OP-TEE・TF-A等のビルド中間物 | 2〜4GB |
| install/の配置済み成果物 | 0.5〜1GB |
| Ubuntu rootfs・tar・仮想ディスク | 5〜10GB |
| 展開・組み立て時の一時領域、ログ等 | 3〜5GB |
| **合計（丸めた目安）** | **約16〜30GB** |

これは現在のNVIDIA配布カーネルを取得する構成の概算であり、新規構築全工程で実測したピーク値ではありません。
Linuxカーネルもソースからビルドする場合は、さらに10〜20GB程度を見込み、空き容量50GB以上を推奨します。

## ドキュメント一覧

新規環境はbuild-install.mdから開始してください。設計資料・検証記録・判断記録も以下にまとめています。

| 分類 | 内容 | ドキュメント |
| --- | --- | --- |
| 利用手順 | 新規clone・環境準備・ビルド・ディスク・DTB作成 | [build-install.md](docs/build-install.md) |
| 利用手順 | 初回ユーザー・公開鍵登録、通常起動・SSH・9p・デバッグ | [runtime-guide.md](docs/runtime-guide.md) |
| 利用手順 | first/second・EK証明書・永続化の試験 | [test-guide.md](docs/test-guide.md) |
| 利用手順 | 既存ディスク・環境の更新と修正適用 | [upgrade-guide.md](docs/upgrade-guide.md) |
| 利用手順 | サンプルのホスト側クロスビルド・QEMUゲスト内make・実行 | [samples-guide.md](docs/samples-guide.md) |
| 環境・構築 | Dockerを使わないホスト環境 | [native-host.md](docs/native-host.md) |
| 環境・構築 | 同梱ソースとビルド構成 | [source-layout.md](docs/source-layout.md) |
| 環境・構築 | Ubuntu 22.04 ARM64 rootfs | [ubuntu-rootfs.md](docs/ubuntu-rootfs.md) |
| 状況・検証 | 完了状況と残件 | [project-status.md](docs/project-status.md) |
| 状況・検証 | Jetson実機とQEMU環境の違い | [hardware-qemu-differences.md](docs/hardware-qemu-differences.md) |
| 状況・検証 | 最終テストの証拠整理 | [final-test-evidence.md](docs/final-test-evidence.md) |
| 状況・検証 | OP-TEEページテーブル使用量の解析 | [page-table-analysis.md](docs/page-table-analysis.md) |
| 状況・検証 | fTPM・helper PTAの過去の検証結果と再現記録 | [ftpm-functional-validation.md](docs/ftpm-functional-validation.md) |
| 設計・調査 | 目的と段階的な進め方 | [requirements.md](docs/requirements.md) |
| 設計・調査 | 無変更T234 OP-TEEのQEMU起動設計 | [qemu-boot-design.md](docs/qemu-boot-design.md) |
| 設計・調査 | T234実装計画と段階的な検証の記録 | [implementation-plan.md](docs/implementation-plan.md) |
| 設計・調査 | B案：NVIDIA fTPMのQEMU機能検証構成 | [ftpm-virt.md](docs/ftpm-virt.md) |
| 設計・調査 | B2：NVIDIA helper PTA全体の移植 | [ftpm-helper-port.md](docs/ftpm-helper-port.md) |
| 設計・調査 | OP-TEEのデーモン・TA・PTAとサービスの比較 | [optee-service-comparison.md](docs/optee-service-comparison.md) |
| 設計・調査 | SIGN_EK_CSRの署名鍵とEKの違い | [ek-csr-signing.md](docs/ek-csr-signing.md) |
| 設計・調査 | OP-TEEサンプルのimport候補 | [sample-import-candidates.md](docs/sample-import-candidates.md) |
| T234検証 | T234 Fuseの読み取り専用モデル | [t234-fuse.md](docs/t234-fuse.md) |
| T234検証 | 段階A：最初のOP-TEEログ | [t234-stage-a.md](docs/t234-stage-a.md) |
| リリース調査 | Jetson Linuxリリース候補 | [release-candidates.md](docs/release-candidates.md) |
| リリース調査 | R36.5.2 OP-TEE／fTPMソース調査 | [r36.5.2-source-investigation.md](docs/r36.5.2-source-investigation.md) |
| リリース調査 | R36.5.2 無変更ビルド記録 | [r36.5.2-build.md](docs/r36.5.2-build.md) |
| リファレンス | 起動スクリプトのmanページ | [日本語](docs/ja/man/run-ftpm-virt.1) / [English](docs/man/run-ftpm-virt.1) |
| 判断記録 | 0001: fTPM実行経路の選択 | [0001-ftpm-execution-path.md](docs/decisions/0001-ftpm-execution-path.md) |
| 判断記録 | 0002: QEMU構成のfTPM helper PTA | [0002-ftpm-helper-pta.md](docs/decisions/0002-ftpm-helper-pta.md) |
| 判断記録 | 0003: B2の検証用プロビジョニング情報 | [0003-ftpm-provisioning-data.md](docs/decisions/0003-ftpm-provisioning-data.md) |
| 判断記録 | 0004: Dockerを使わないビルド・実行 | [0004-native-host.md](docs/decisions/0004-native-host.md) |
| 判断記録 | 0005: install/へのビルド成果物の集約 | [0005-install-prefix.md](docs/decisions/0005-install-prefix.md) |
| 判断記録 | 0006: Ubuntu QEMUゲストのSELinux構成 | [0006-guest-selinux.md](docs/decisions/0006-guest-selinux.md) |
| 判断記録 | 0007: 起動時のudev・ttyAMA0待ち | [0007-boot-device-wait.md](docs/decisions/0007-boot-device-wait.md) |
| 判断記録 | 0008: 通常起動・SSH・ホスト共有・CPU数 | [0008-interactive-runtime.md](docs/decisions/0008-interactive-runtime.md) |
| 判断記録 | 0009: 新規構築・通常利用・テスト・更新の文書分離 | [0009-guide-organization.md](docs/decisions/0009-guide-organization.md) |
| 判断記録 | 0010: OP-TEEサンプルの追加 | [0010-optee-samples.md](docs/decisions/0010-optee-samples.md) |

## 現在の実装状況

QEMUの実装基準は、2026-11-16確認時点の最新安定版 **11.1.3** です。
NVIDIA版OP-TEE／fTPMのT234向け無変更ビルドは成功しています。
専用QEMUマシンで無変更OP-TEEの最初のログを確認し、読み取り専用Fuseモデルを追加しました。
現在はFuse初期化を通過し、未実装SE0の設定関数で停止します。
T234専用構成のSE0再現は未完了です。別のB2機能検証構成では、NVIDIA helper PTA・fTPM TA、Ubuntu 22.04 ARM64を起動し、TPMコマンド・永続化・実際のEKに対応するテスト証明書を検証済みです。
[実行結果と再現手順](docs/ftpm-functional-validation.md)を参照してください。

## ドキュメント方針

本プロジェクトの各ドキュメントは日本語版と英語版を用意し、ファイル名・ディレクトリ名は英語に統一します。
更新時は両言語を同時に更新し、技術値・コマンド・検証状況を一致させます。
Python依存定義は両言語で共用します。

変更はPRを作成せず、`main`へ直接pushします。

同梱する上流ソース内の文書・ライセンスは原文を保持します。

設計・互換性に重要な選択肢はユーザーへ提示し、選択後に両言語で判断記録を残してpushします。
[今回のfTPM実行経路の選択](docs/decisions/0001-ftpm-execution-path.md)。

B案の実装・起動・永続化検証手順は[機能検証構成](docs/ftpm-virt.md)を参照してください。

B2では[NVIDIA helper PTA全体の移植](docs/ftpm-helper-port.md)を進めています。[SIGN_EK_CSRとEKの違い](docs/ek-csr-signing.md)も記録しています。

**install手順の入口：** [docs/build-install.md](docs/build-install.md)。実行ファイル・ヘッダ・ライブラリは既定で`install/`配下にまとめます。
