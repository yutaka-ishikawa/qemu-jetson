# 最終テストの証拠整理

日本語 | [English](en/final-test-evidence.md)

2026-11-17（日本時間）整理。対象はユーザー環境のjetson-ftpm-virt B2。
全テストPASSのユーザー報告を受領済み。ただし、受領ログで独立に確認した範囲と報告のみの範囲を区別する。
全工程のログ検証が完了したという一括PASS判定はまだ出さない。

## 証拠一覧

| 段階・事象 | 証拠 | 判定 |
| --- | --- | --- |
| 初回試験の再実行 | 受領log.txtにPTA各検証PASSとFAIL line=22 | first.done不存在チェックに失敗。初回完了マーカーの存在に対応するが、初回PASSログそのものではない |
| second | 受領log2.txt | PASS。NV/鍵保持・PCRリセット・RSA署名・seal/unseal、helper PTA証明書/CSR/署名のマーカーを確認 |
| export | 受領export.log | PASS。RSA/ECC両公開鍵を復号・形式検証し、SPKI SHA-256を記録 |
| bind/pack/適用 | 全PASSのユーザー報告 | 最終の発行物・ログは未受領 |
| bound | 全PASSのユーザー報告 | 最終bound.log未受領。実EK/PTA証明書一致・標準NV indexの独立確認は未完了 |
| bound再起動 | 全PASSのユーザー報告 | 最終bound-reboot.log未受領。export時とのEK同一性を含め再検証待ち |
| ページテーブル不足 | 受領secure-first-native.log | 過去の失敗。8 tables exhaustedとpanicを記録し、成功ログと混同しない |
| 無出力でタイムアウト | 受領launch-first.strace | 過去のSIGTTOU停止。起動スクリプトのforeground修正理由を記録 |

[機械可読の証拠台帳](results/final-user-evidence.json)には受領元ファイル名、バイト数、元ファイル全体のSHA-256、確認したマーカーを保存した。
[ログ抜粋](results/final-user-evidence-excerpt.txt)は必要な結果行のみを抽出したもの。抜粋のハッシュと元ログのハッシュは別。
元の全文ログはアップロードから確認したもので、本リポジトリへ全文コピーしていない。秘密鍵・seed・デバイス固有ファイルは含めない。
EKフィンガープリントは実ユーザー環境のexport公開鍵に基づく。開発環境のEKと一致する必要はない。

## 開発環境の結果との区別

[従来の全機能結果](results/ftpm-functional.json)、[テーブル数修正後の結果](results/optee-xlat-tables.json)、
[SELinux変更後の結果](results/guest-selinux.json)は、手元の開発環境・既存ディスクによる結果。
ユーザー環境で不足するログの代用にしない。各ファイルのpending等の表現は当時の検証範囲を表す。
現在のユーザー報告と受領状況は本台帳を参照する。

## 証拠を揃えるために必要なもの

テストは既にPASSしたとの報告があるため、再実行やディスク初期化をせず、保存済みの次のログを提出すれば続けて確認できる。

- work/ftpm-virt/bound.log
- work/ftpm-virt/bound-reboot.log
- 保存されていればwork/ftpm-virt/first.log（存在しなくても再生成のためfirstを実行しない）

boundの両ログでPTA証明書/CSR/署名、実EKとPTA証明書の一致、標準NV index、secondのPASS、最後のEK_TEST: PASSを確認する。
exportとのRSA/ECC EK_EXPORT値も比較する。
証明書署名までホスト側で再検証する場合に限り、発行した公開証明書・CSR・CA公開証明書を使用する。
CA秘密鍵、Firmware ID秘密鍵、provisioning.bin、device-identity.bin、rootfs.ext4の提出は不要。
check-ftpm-functional-results.pyはfirst等を含む6ログを要求するため、不足ログを複製して通さない。

実行方法は[test-guide.md](test-guide.md)、検証範囲と限界は[実機との差分](hardware-qemu-differences.md)を参照。
