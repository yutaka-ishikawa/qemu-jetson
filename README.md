# qemu-jetson

現在のビルド・起動はDocker不要です。まず[ホスト環境の準備](docs/native-host.md)を参照してください。QEMUは`install/bin/`へ配置します。ビルド中間物は`work/qemu-build/`です。[ビルド・インストール手順](docs/build-install.md)を参照。

日本語 | [English](README.en.md)
QEMU for NVIDIA Jetson Orin Nano

NVIDIA版OP-TEE／fTPMを、ソース変更を極力抑えてQEMU上で動かすための開発プロジェクトです。

- [fTPM・EK証明書テスト手順](docs/test-guide.md)

## 設計と手順

| 目的 | 手順書 |
| --- | --- |
| 新規clone・環境準備・ビルド・ディスク・DTB作成 | [build-install.md](docs/build-install.md) |
| 初回ユーザー/公開鍵登録・通常起動・SSH・共有・デバッグ | [runtime-guide.md](docs/runtime-guide.md) |
| first/second・EK証明書・永続化の試験 | [test-guide.md](docs/test-guide.md) |
| 既存ディスク/環境の更新・修正適用 | [upgrade-guide.md](docs/upgrade-guide.md) |


- [完了状況と残件](docs/project-status.md)

- [通常起動・SSH・9p共有・デバッグ](docs/runtime-guide.md)

- [実機とQEMU環境の違い](docs/hardware-qemu-differences.md)
- [最終テストの証拠整理](docs/final-test-evidence.md)
- [OP-TEEページテーブル使用量の解析](docs/page-table-analysis.md)


- [Fuseモデルと検証](docs/t234-fuse.md)
- [段階A：最初のOP-TEEログ](docs/t234-stage-a.md)
- [同梱ソースとビルド構成](docs/source-layout.md)
- [Ubuntu 22.04 ARM64 rootfs構築](docs/ubuntu-rootfs.md)
- [要件と作業方針](docs/requirements.md)
- [QEMU起動設計](docs/qemu-boot-design.md)
- [実装手順](docs/implementation-plan.md)
- [L4Tリリース候補](docs/release-candidates.md)
- [R36.5.2ソース調査](docs/r36.5.2-source-investigation.md)
- [R36.5.2無変更ビルド結果](docs/r36.5.2-build.md)

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
