# qemu-jetson

日本語 | [English](README.en.md)
QEMU for NVIDIA Jetson Orin Nano

NVIDIA版OP-TEE／fTPMを、ソース変更を極力抑えてQEMU上で動かすための開発プロジェクトです。

## 設計と手順

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
OP-TEE初期化完了、Linux起動、TPM機能は未検証です。

## ドキュメント方針

本プロジェクトの各ドキュメントは日本語版と英語版を用意し、ファイル名・ディレクトリ名は英語に統一します。
更新時は両言語を同時に更新し、技術値・コマンド・検証状況を一致させます。
Python依存定義は両言語で共用します。

変更はPRを作成せず、`main`へ直接pushします。

同梱する上流ソース内の文書・ライセンスは原文を保持します。

設計・互換性に重要な選択肢はユーザーへ提示し、選択後に両言語で判断記録を残してpushします。
[今回のfTPM実行経路の選択](docs/decisions/0001-ftpm-execution-path.md)。
