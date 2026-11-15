# qemu-jetson
QEMU for NVIDIA Jetson Orin Nano

NVIDIA版OP-TEE／fTPMを、ソース変更を極力抑えてQEMU上で動かすための開発プロジェクトです。

## 設計と手順

- [要件と作業方針](docs/requirements.md)
- [QEMU起動設計](docs/qemu-boot-design.md)
- [実装手順](docs/implementation-plan.md)
- [L4Tリリース候補](docs/release-candidates.md)
- [R36.5.2ソース調査](docs/r36.5.2-source-investigation.md)
- [R36.5.2無変更ビルド結果](docs/r36.5.2-build.md)

QEMUの実装基準は、2026-11-16確認時点の最新安定版 **11.1.3** です。
NVIDIA版OP-TEE／fTPMのT234向け無変更ビルドは成功しています。
QEMU側の実装と起動・TPM実行試験は未実施です。
