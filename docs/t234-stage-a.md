# 段階A：最初のOP-TEEログ

日本語 | [English](en/t234-stage-a.md)

2026-11-16（日本時間）：**無変更のNVIDIA版OP-TEEが専用QEMUマシンで最初のログを出すところまで到達した。**
OP-TEE初期化完了、Linux起動、fTPM機能の達成ではない。
機械可読の結果は [t234-stage-a.json](results/t234-stage-a.json)。

本書は段階Aの記録。[後続のFuse実装](t234-fuse.md)も参照。Fuseイメージ未指定時は引き続き本書の構成になる。

## 実装

- QEMUの `hw/arm/jetson-t234-dev.c` に `jetson-t234-dev` を追加。
- TCG、`max` CPU、1コア、非Secure RAM 128MiBに限定。
- Secure専用アドレス空間にROMとRAMを配置。非Secure側からのアクセスを分離。
- `0x0c198000` にTCU送信モデルを追加。1〜3バイトの送信、flush、同期的なbusy解除を扱う。
- `firmware/t234-boot/` にEL3初期化、Secure EL1への遷移、例外診断、試験用の停止処理を実装。
- NVIDIAのOP-TEE／fTPMソースは変更していない。

TCUは送信だけの最小モデル。受信、割り込み、実機のリモートプロセッサ、時間に依存するバックプレッシャーは未実装。
Fuse、SE、RNG1、GIC、QSPI、Scratch、実機ブートチェーンも未実装。
移行・スナップショットの互換性は未検証。

## メモリと入力契約

| 領域 | 配置 | 用途 |
| --- | --- | --- |
| Secure ROM | `0x00000000 / 0x10000` | EL3試験用ファームウェア |
| Secure RAM | `0x80000000 / 0x04000000` | OP-TEEと試験用予約領域 |
| OP-TEE用範囲 | `0x80000000 / 0x03fc0000` | 公式T234ビルドのTZDRAM設定 |
| DT | `0x83ff0000 / 最大0x10000` | OP-TEEのDT入力 |
| EL3 stack | 上端 `0x83fe0000` | OP-TEE用範囲の外 |
| Non-secure RAM | `0x90000000 / 0x08000000` | 将来の非Secure側、現在は分離試験 |

`-bios`をROM、`-kernel`のrawイメージをOP-TEE範囲、`-dtb`を上記DT領域にロードする。
これはLinux向けの通常の `-kernel` 起動動作ではなく、このマシン独自の入力契約。
EL3コードはx0=0、x1=`0x83fc0000`、x2=`0x83ff0000`、x3=0を設定してSecure EL1へ入る。
ROMとSecure RAMはQEMUのSecureアドレス空間を通してロードする。

## 再実行

NVIDIA指定AArch64ツールチェーン、dtc、Dockerを用意する。

```bash
export CROSS_COMPILE_AARCH64=/path/to/toolchain/bin/aarch64-buildroot-linux-gnu-
# dtcがPATHにない場合のみ指定
export DTC=/path/to/dtc
scripts/build-t234-firmware.sh
scripts/build-qemu.sh
```

`work/t234-firmware/` にboot、selftest、isolationのELF／rawイメージとDTBを生成する。
OP-TEEは既存の無変更ビルドの `tee-raw.bin` を `work/optee-baseline/tee-raw.bin` に置く。
初回cloneにはその成果物は含まれない。[OP-TEEビルド記録](r36.5.2-build.md)を参照。

```bash
docker run --rm -v "$PWD:/src" -w /src qemu-jetson-build:jammy \
  python3 scripts/check-t234-boot.py \
  work/qemu-container-build/qemu-system-aarch64 \
  --optee work/optee-baseline/tee-raw.bin
```

`--optee`を省略するとハーネスの試験だけを行う。
既定ではOP-TEE入力のSHA-256を、既存ビルドの
`96bcd44d8a4ceee39fa8a4ffd97b5bc0e193c6b3d5fc6cdc2208b806aeb9beb9` と照合する。
再ビルド時は日時等でハッシュが変わるため、別途ビルド記録に保存した値を
`--optee-sha256 <hash>` で明示する。ハッシュが一致するだけで同じソースからのビルドを証明するものではない。

試験用ファームウェアの終了にQEMU semihostingを使う。これは開発用の停止手段であり、
実機のOPTEED／Secure Monitorを実装したものではない。
未知のEL3例外／SMCはレジスタを表示して終了する。OP-TEEサービスへ架空の成功を返さない。

## 確認結果

1. EL3 → Secure EL1 → SMC → EL3の経路が通り、`BOOT: SELFTEST PASS`、終了コード0を確認。
2. TCUの1文字送信、3文字パケット `ABC`、busy解除、flushを確認。
3. 非Secure EL1から `0x80000000` を読む試験が、ESR_EL1=`0x96000010`、FAR_EL1=`0x80000000`のアボートとなり、`BOOT: NS isolation PASS`、終了コード0を確認。
4. 未対応の256MiB RAMと2コア指定を、マシンの制約により拒否することを確認。
5. 無変更OP-TEEが以下を出力することを確認。

```text
BOOT: EL3 entry
I/TC: OP-TEE version: 4.2 ... aarch64
I/TC: Primary CPU initializing
E/TC:00 00 Core data-abort at address 0x86210200
E/TC:00 00  esr 0x96000010
```

停止箇所のELRは `0x8002e850`。対応するELFをaddr2lineで照合すると
`fuse_generate_ecid()` 内の `io_read32()`、`tegra_driver_fuse.c:30`。
DTとドライバの対応から、物理 `0x03810200` の `FUSE_OPT_VENDOR_CODE_0` 読み取りに相当する。
Fuseモデルがないため、データアボートが繰り返される。

さらに、最小DTにTPMイベントログノードがない旨のログと、`stmm_sp_parse_dt()` のinitcall失敗も観測した。
これらも未解決であり、初期化が正常という意味ではない。

試験スクリプトは最初のデータアボートを観測後、QEMUへ終了を要求してログの増大を止める。
`stop_reason=observed_data_abort` は正常ブートやタイムアウト成功を意味しない。
ログ、コマンド、終了理由は `work/t234-results/` に記録し、
`initialization_verified=false`、`tpm_verified=false`を維持する。

## 次の段階

Fuseの読み取り専用モデルを追加して、識別子とSNの値・バイト順を検証する。
続いてSE／乱数とDTの未解決項目を調べる。Linux／fTPMの動作検証はその後に進む。
