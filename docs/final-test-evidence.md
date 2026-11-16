# 最終テストの証拠整理

日本語 | [English](en/final-test-evidence.md)

2026-11-17（日本時間）整理。対象はユーザー環境のjetson-ftpm-virt B2。
全テストPASSのユーザー報告を受領済み。ただし、受領ログで独立に確認した範囲と報告のみの範囲を区別する。
更新：boundとbound-rebootのログを受領し、必要なPASS項目とexportからのEK同一性を再検証した。両方PASS。初回の元ログは未受領のまま。

## 証拠一覧

| 段階・事象 | 証拠 | 判定 |
| --- | --- | --- |
| 初回試験の再実行 | 受領log.txtにPTA各検証PASSとFAIL line=22 | first.done不存在チェックに失敗。初回完了マーカーの存在に対応するが、初回PASSログそのものではない |
| second | 受領log2.txt | PASS。NV/鍵保持・PCRリセット・RSA署名・seal/unseal、helper PTA証明書/CSR/署名のマーカーを確認 |
| export | 受領export.log | PASS。RSA/ECC両公開鍵を復号・形式検証し、SPKI SHA-256を記録 |
| bind/pack/適用 | 全PASSのユーザー報告 | 後続boundで発行・適用結果を確認。発行物そのもののホスト側独立検証は未実施 |
| bound | 受領bound.log | PASS。PTA、実EK/証明書一致、標準NV、second、最終EK_TESTを確認 |
| bound再起動 | 受領bound-reboot.log | PASS。同じ全項目とexport/bound/rebootのRSA/ECC EK一致を確認 |
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

## 確認済みの範囲と残る証拠上の制約

両boundログでPTA証明書/CSR/署名、実EKとの一致、標準NV index、second、最後のEK_TEST: PASSを確認し、試験FAILマーカーがないことも確認した。
RSA/ECC EK_EXPORTを復号し、DER SPKIのSHA-256がexport/bound/bound-rebootで一致することを確認した。
元ログのSHA-256と抜粋は台帳に追加済み。再テストやディスク初期化は不要。
初回firstの元PASSログは未受領。存在しないログを生成するためfirstを再実行しない。
証明書署名検証はゲストのPASSマーカーに基づく。発行済み公開証明書ファイルによるホスト側での独立検証は未実施。
秘密鍵・seed・デバイスID・ディスクの提出は不要。
従来の6ログ用checkerの不足をログ複製で回避しない。

実行方法は[test-guide.md](test-guide.md)、検証範囲と限界は[実機との差分](hardware-qemu-differences.md)を参照。

追加の[ページテーブル計測](page-table-analysis.md)は開発側の診断試験。ユーザーログの証拠とは分離して記録した。
