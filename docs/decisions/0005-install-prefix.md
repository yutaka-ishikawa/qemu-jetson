# 0005: install/へのビルド成果物の集約

日本語 | [English](../en/decisions/0005-install-prefix.md)

状態：ユーザー承認済み。ユーザーが既定の配置先として`install/`配下のbin/include/lib等を指定した。

| 候補 | 内容 | 制約 |
| --- | --- | --- |
| 従来 | work内のビルドディレクトリから直接起動・参照 | 中間ファイルと実行用成果物が同じ場所に残る |
| 採用 | build後にローカルinstall prefixへ実行ファイル・ヘッダ・ライブラリ・boot payloadを配置 | build先と配置先を区別する必要がある |

既定prefixはリポジトリ直下のinstall/。INSTALL_DIRで変更できる。
ホストQEMUはbin、公開ヘッダはinclude、ARM64ライブラリはlib/aarch64-linux-gnuへ置く。
ゲストプログラムはlibexec、読み取り専用boot payloadはshareへ置く。
秘密鍵とNVディスクはビルド成果物ではないためworkに保持し、install処理では更新しない。
Docker不使用とmainへの直接pushを継続する。[配置詳細](../build-install.md)を参照。
