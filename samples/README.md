# OP-TEEサンプル

日本語 | [English](README.en.md)

| サンプル | 内容 |
| --- | --- |
| [ftpm-helper-probe](ftpm-helper-probe/) | NVIDIA helper PTAをテスト用TA経由で呼び出すCプログラム |
| [hello_world](hello_world/) | TA呼出し・値の受渡し |
| [random](random/) | セキュア側乱数 |
| [secure_storage](secure_storage/) | 永続オブジェクト |
| [aes](aes/) | AES暗号化・復号 |
| [sign_verify](sign_verify/) | 署名・検証 |

ビルドとQEMUゲストでのmake・実行は[サンプル利用ガイド](../docs/samples-guide.md)を参照。
ftpm-helper-probeはtests/ftpm-helper-probeからのコピー。既存の自動試験は引き続きtests側を使用する。
追加importの候補は[候補一覧](../docs/sample-import-candidates.md)。ユーザーはBを選択し、5サンプルを取り込み済み。
