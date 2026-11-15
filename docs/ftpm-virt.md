# B案：NVIDIA fTPMのQEMU機能検証構成

日本語 | [English](en/ftpm-virt.md)

> 現在の状態：Linux・Ubuntu・TEE supplicantの起動を確認。fTPMコマンド試験は未完了。欠けているhelper PTAへの対応は[判断待ち](decisions/0002-ftpm-helper-pta.md)。以下のテスト手順は準備段階であり、成功結果を表していない。


[選択肢と採用理由](decisions/0001-ftpm-execution-path.md)。QEMUの`jetson-ftpm-virt`は既存の`virt`を継承する。
NVIDIA R36.5.2同梱OP-TEEの`vexpress-qemu_armv8a`を使い、NVIDIA版fTPM TAはソースを変更せずARM64でコンパイルする。
T234専用の`jetson-t234-dev`とFuseモデルは別の構成として維持する。

## 起動経路

QEMU → NVIDIA同梱TF-A 2.8（既存QEMU構成）→ OP-TEE → Linuxエントリーシム → NVIDIA配布のLinux 5.15.199-tegra → Ubuntu 22.04 ARM64。
TF-Aは`firmware/tf-a`、小さなLinuxエントリーシムは`firmware/linux-entry`に格納する。
Kernel ImageはNVIDIA BSPの配布バイナリをそのまま使う。fTPMモジュールも同じBSPのものを使う。
Linuxを`0x60200000`にロードし、シムはDTアドレス`0x40000000`をx0に設定してジャンプする。
fTPM TAはEarly TAとしてOP-TEEに埋め込む。DTの`microsoft,ftpm`ノードでLinuxドライバを結び付ける。

## 仮想eFuseの代替

機能検証構成では物理Fuseレジスタの再現は使わず、72バイトの永続ファイルをセキュア専用の読み取り専用ページ`0x0c200000`に写す。
形式は`JFTPM001`の8バイト、秘密乱数32バイト、公開デバイスID32バイト。
ファイルは初回だけ生成し、権限0600で保存する。既存ファイルを自動再生成しない。
現在のOP-TEE HUK APIが利用する秘密は先頭16バイト。残りは予約である。
`CFG_QEMU_DEVICE_IDENTITY=y`でのみOTP APIを追加し、EPSは既存HUK派生APIでTA UUIDとデバイスIDに結び付ける。
共有固定HUKを使わない。fTPM TAのEPS取得処理は変更しない。

`work/ftpm-virt/device-identity.bin`と`rootfs.ext4`は必ず対で保存する。後者には`/data/tee`の暗号化ストレージを含む。
秘密ファイルやディスクはGitに入れない。コピーすると同じTPM IDを複製するため、別デバイスでは新規生成する。
ホスト管理者からの秘密保護、耐タンパ、ロールバック防止を提供する構成ではない。

## 再現手順

Docker、Python3、NVIDIA提供AArch64 GCC、dtc、Pythonのcryptography・pycryptodome・pyelftoolsが必要。
既存のNVIDIAコンポーネント復元・クライアントビルドは[実装手順](implementation-plan.md)を参照する。

```bash
scripts/build-qemu.sh
# NVIDIAツールチェーンのprefixとdtc/Python環境を設定する
export CROSS_COMPILE=/path/to/aarch64-buildroot-linux-gnu-
scripts/build-ftpm-virt-firmware.sh
scripts/fetch-ftpm-virt-kernel.py
FTPM_FUNCTIONAL_PROFILE=1 KERNEL_MODULES_DIR="$PWD/work/ftpm-virt/modules" \
  scripts/build-ubuntu-rootfs.sh /path/to/optee/install/t234 work/ftpm-virt/rootfs.tar
scripts/create-ftpm-virt-disk.sh
scripts/prepare-ftpm-virt-dtb.sh
scripts/run-ftpm-virt.sh first 2>&1 | tee work/ftpm-virt/first.log
scripts/run-ftpm-virt.sh second 2>&1 | tee work/ftpm-virt/second.log
```

初回は新しいディスクだけに実行する。二回目は同じ秘密ファイルとディスクを使い、別のQEMUプロセスで起動する。
スクリプトは成功時に`FTPM_TEST: PASS phase=first`／`second`を出し、ゲストを停止する。
失敗やタイムアウトを成功とみなさない。既存の検証用ディスクを消して初回テストを再実行しないこと。
機能テスト用systemdサービスは専用プロファイルと`ftpm.test`カーネル引数でのみ起動する。

## 検証対象と制約

検証対象はGetCapability、GetRandom、NV読み書き、RSA署名とOpenSSL検証、seal/unseal、PCR extend、
QEMUを完全停止した後のNV・鍵・sealed objectの保持、PCRリセット。
実機のSE、ハードウェア鍵スロット、製造時EK証明書、Measured Bootはこの構成の検証範囲外。
`CFG_TA_MEASURED_BOOT=n`としている。TPMコマンドのPCR操作を起動時測定の再現と同一視しない。

## 今回確認した結果

[機械可読結果](results/ftpm-virt-boot.json)と[実行ログ抜粋](results/ftpm-virt-boot-excerpt.txt)を保存した。
LinuxのOP-TEEドライバ、Ubuntu multi-user target、TEE supplicantの起動を確認した。
helper PTAのロードは`ITEM_NOT_FOUND`となるため、fTPM動作済みとはしていない。
[次の判断](decisions/0002-ftpm-helper-pta.md)を待つ。
Ubuntuのsystemd-sysusers／systemd-resolvedサービスにも失敗が残っており、Ubuntu全サービスの健全性は未確認。
DTではセキュアRAM全体をmemreserveで予約し、Linuxの割当対象から除外する。
