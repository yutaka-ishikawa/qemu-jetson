# T234 Fuseの読み取り専用モデル

日本語 | [English](en/t234-fuse.md)

2026-11-16（日本時間）：Fuseモデルを追加し、無変更OP-TEEが段階AのFuse読み取りアボートを通過することを確認した。
現在の停止箇所はSE0初期化であり、OP-TEE初期化完了やfTPM動作ではない。
機械可読の結果は [t234-fuse.json](results/t234-fuse.json)。

## モデルの範囲

`jetson-t234-dev`の `fuse-image` オプションで、ホスト上の明示的なテスト用イメージを指定する。
指定しなければFuseはマップせず、[段階A](t234-stage-a.md)の構成を維持する。
イメージは起動時に一度だけ読み込む。ゲストの書き込み、起動後のQMPによる設定変更は拒否する。
QMPのsystem_resetでは値を維持し、同じ内容のイメージを使った別プロセスでも同じ値になる。
イメージを複製すれば同一識別情報を持つ仮想デバイスになる。別IDを使う場合は別の内容を明示的に用意する。

- MMIO：`0x03810000 / 0x600`、Secure側のみ。
- アクセス：4バイト、アライン済み、little-endian。
- 対応オフセット：`0x1a0, 0x200, 0x204, 0x208, 0x20c, 0x210, 0x214, 0x218, 0x220, 0x268, 0x29c, 0x408, 0x40c`。
- 未対応レジスタの読み取りはデコードエラー、書き込みはアクセスエラーとし、ゲストにアボートを発生させる。
- 成功した読み取りと拒否した書き込みはQEMU traceイベントで観測できる。

これは識別子・設定値の部分モデルで、Tegra Fuse Controller全体の再現ではない。
焼き込み、OTPビット遷移、秘密鍵Fuse、KDK0、SE鍵スロットは未実装。
BSIやsecurity modeの値を設定しても、Secure Bootや実機の鍵保護を実装したことにはならない。
移行・スナップショットでの状態互換性は未検証。

## 入力形式

イメージは正確に1536バイト。各レジスタ値をそのオフセットへ32-bit little-endianで置き、
未対応オフセットの領域は0とする。これはNVIDIAの製造用fuseblob形式ではない。
サイズ不正と、未対応領域に非0のデータがあるイメージは起動時に拒否する。

公開の合成テスト値は `configs/fuse/test-device-a.json` と `test-device-b.json`。
実機由来の秘密は含まない。生成は次のとおり。

```bash
scripts/make-t234-fuse-image.py configs/fuse/test-device-a.json work/fuse/device-a.bin
scripts/make-t234-fuse-image.py configs/fuse/test-device-b.json work/fuse/device-b.bin
```

生成スクリプトは対応レジスタの過不足、32-bit範囲、lot番号のbase-36桁を検証する。
異なる既存イメージは上書きしない。起動後にホストファイルを編集しても現在のVMの値は変わらない。
再起動で同じIDを使うには、入力ファイルの内容も保持する。

## NVIDIAの関数を使った検証

変換ロジックをQEMU側で実装し直していない。既存の無変更OP-TEEバイナリ内の
`fuse_generate_ecid()` と `fuse_generate_sn()` を、試験用ファームウェアから直接呼び出した。
関数のアドレスは対応するELFのシンボルから取得する。
OP-TEE全体を初期化した試験ではなく、MMIOとこの2関数の相互運用試験である。

```bash
export CROSS_COMPILE_AARCH64=/path/to/toolchain/bin/aarch64-buildroot-linux-gnu-
export DTC=/path/to/dtc
export OPTEE_ELF=work/optee-baseline/tee.elf
scripts/build-t234-firmware.sh
scripts/build-qemu.sh

  python3 scripts/check-t234-fuse.py work/qemu-build/qemu-system-aarch64 \
  --optee work/optee-baseline/tee-raw.bin
```

ELFとrawイメージは同じ無変更ビルドの組を使う。生成・入力のハッシュは[段階Aの手順](t234-stage-a.md)と同じ扱い。
再ビルド成果物には記録済みのハッシュを `--optee-sha256` で指定できる。
`OPTEE_ELF`指定時にfuse-probe／fuse-resetを生成するため、これらの試験前には必ず指定してビルドする。

確認した値：

| 項目 | デバイスA | デバイスB |
| --- | --- | --- |
| SN（10バイト） | `01020123456789abcdef` | `03041032547698badcfe` |
| ECID64 | `82541b1d454a0255` | `82541b1d454e0456` |
| ECID128（32-bitワード順） | `d280956a 1448d159 540420c4 00000002` | `138115ab 148d159e 540420c4 00000002` |

SNの先頭2バイトはODM_INFOからbig-endianで構成され、残りはODMID0/1の各レジスタのlittle-endianバイト列となる。
各イメージで2回ずつ別プロセスを起動し、期待値と一致した。
さらに、書き込み拒否後に値が変わらないこと、未対応読み取りのアボート、非Secure EL1からのアクセス拒否、
不正イメージ拒否、QMPリセット後の値の維持と実行中のfuse-image変更拒否を確認した。
リセット試験の過程で、最小マシンのCPUをsystem_resetへ登録する処理も追加した。

## OP-TEEの次の停止箇所

```bash
  python3 scripts/check-t234-boot.py work/qemu-build/qemu-system-aarch64 \
  --optee work/optee-baseline/tee-raw.bin \
  --fuse-image work/fuse/device-a.bin --output-dir work/t234-fuse-boot-results
```

同じSHA-256のOP-TEEを使い、以前のFuseアボートを通過して以下を観測した。

```text
Core data-abort at address 0x86550014
esr 0x96000010
elr 0000000080003cf8
```

ELFシンボルは `tegra_se_ccc_configure_se0`。公開側の呼び出し元は
`tegra_se_map_device.c:45`。DTと呼び出し時のベースアドレスから物理 `0x03b50014` に相当すると推定する。
CCCライブラリの逆アセンブルは行っていない。SEプロトコルは未確定で、ここでは成功値を返していない。

StMMのDT初期化失敗とTPMイベントログ不足も残っている。
ログとJSONは `work/t234-fuse-results/`、OP-TEE診断は `work/t234-fuse-boot-results/` に保存する。
次はSE0の公開仕様とアクセスを調べ、必要な動作を定義する。

追加確認：Fuseイメージ未指定では段階Aと同じFuseアボートを再現した。NVIDIA関数のプローブをtrace付きで実行し、12回の読み取りを記録できることも確認した。

読み取りtraceはQEMU起動引数 `-trace enable=jetson_t234_fuse_read -D work/fuse.trace.log` で有効化できる。
