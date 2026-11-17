# 0010: OP-TEEサンプルの追加

日本語 | [English](../en/decisions/0010-optee-samples.md)

状態：ユーザーがBを選択（2026-11-17、日本時間）。

- A（推奨として提示）：hello_world・random・secure_storage。基本APIと永続化を学ぶ。
- B（採用）：Aにaes・sign_verifyを追加。暗号APIも学べるが、検証対象が増える。
- C：候補の記録のみとしてimportを延期する。

取得元はlinaro-swg/optee_examples、固定コミットは71e8f3f320eef46a9369700bf30b91d67427d535。
samples/へ5ディレクトリをコピーし、原本のMakefileをMakefile.upstreamへ保存してビルド用ラッパーを追加。
ソース・ライセンス・著作権表示を保持し、取得アーカイブと元ファイルのハッシュをsamples/optee-examples-source.jsonに記録した。

個別・一括make、ホストのクロスビルド、ゲストのARM64ネイティブビルドを用意。
[samples-guide.md](../samples-guide.md)に9p共有・make・TA配置・実行・確認点を記載。
make dry-run、クライアントC構文、ソースハッシュ、文書リンク・シェル構文を確認する。
現環境ではクロスコンパイラ展開容量が不足し、実ビルド・TA署名・ゲスト実行は未検証。
