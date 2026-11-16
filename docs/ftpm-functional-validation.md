# NVIDIA fTPM・helper PTAの実行検証

現在のビルド・導入は[build-install.md](build-install.md)、firstからのテスト実行は[test-guide.md](test-guide.md)を参照。本書は過去の全工程と検証結果の記録。


日本語 | [English](en/ftpm-functional-validation.md)

[決定0003](decisions/0003-ftpm-provisioning-data.md)に従い、QEMU専用のテストCA・Firmware ID鍵・証明書を生成した。
**NVIDIAのhelper PTA本体・helper TA・fTPM TAのソースを変更せず、Ubuntu 22.04 ARM64上でfTPMの動作と永続化を確認した。**
構成は[移植設計](ftpm-helper-port.md)を参照。

## 確認結果

| 対象 | 結果 |
| --- | --- |
| helper PTA | PING_NSのREADY、SN、ECID、online provisioning mode、API version 2.0を確認 |
| 証明書・CSR API | RSA/EC EK証明書、SID/Firmware ID証明書、RSA/EC CSRの取得と内容一致を確認 |
| SIGN_EK_CSR | 実際のPTAが返した署名をFirmware ID証明書の公開鍵でOpenSSL検証 |
| 不正パラメータ | SIGN_EK_CSRがBAD_PARAMETERSを返すことを確認 |
| INJECT_EPS | 元の設定どおり無効。NOT_IMPLEMENTEDを確認 |
| TPMコマンド | GetCapability、GetRandom 16バイト、NV write/read、PCR extendに成功 |
| TPM鍵操作 | RSA署名をOpenSSLで検証。seal/unsealに成功 |
| 完全停止後の保持 | 別のQEMUプロセスでNVデータ・署名鍵・sealed dataを再利用し、PCRリセットを確認 |
| 実際のEKとの対応 | fTPMからRSA/EC EK公開鍵を取得し、その公開鍵にテストCAの証明書を発行。PTAの証明書と一致 |
| EK証明書のNV領域 | NVIDIAのprovisioning scriptと同じ属性・標準index `0x01c00002` / `0x01c0000a`へ格納。再起動後も読み出して一致 |

[機械可読結果](results/ftpm-functional.json)と[実際の成功ログ抜粋](results/ftpm-functional-excerpt.txt)を保存した。
ログは通常世界・セキュア世界のUARTから採取した。検証対象の各QEMUプロセスはゲストのpoweroffで終了した。
TF-Aの`ERROR: QEMU System Power off: with GPIO`は、このQEMU用電源断経路のメッセージであり、試験失敗ではない。

## 鍵・証明書の生成と実際のEKへの対応付け

1. `generate-ftpm-test-provisioning.py`でテストCA、Firmware ID、SID、seed、API試験用RSA/ECデータを初回だけ生成する。
2. 最初のRSA/EC証明書・CSRはAPI疎通のためのfixtureであり、その時点ではfTPMのEKとは対応付けていない。
3. ゲストで`tpm2_createek`を実行し、**実際のEK公開鍵だけ**をUARTへ書き出す。EK秘密鍵は取り出さない。
4. `bind-ftpm-test-ek.py`で、その公開鍵にCA署名のテスト証明書とFirmware ID署名のCSRを作る。
5. seed、Firmware ID鍵、SN、HUK、既存TPM NV状態を維持し、証明書・CSRのデータを更新する。
6. 別のQEMUプロセスで、再生成したEK公開鍵・PTAの証明書・CSRの公開鍵が一致することを検証する。

CSRの署名鍵はEKではなくFirmware IDである（[説明](ek-csr-signing.md)）。
このCSRをEK公開鍵で自己署名検証する方式にはしない。Firmware ID公開鍵で署名を検証する。
これらはQEMU用テスト証明書であり、NVIDIAやメーカーCAの製造時の信頼はない。

## 再現手順

前提：QEMU／NVIDIAコンポーネントのビルド環境、dtc、cryptography付きPython、[ホスト依存ツール](native-host.md)。
NVIDIA配布のkernel Imageと対応fTPMモジュールを用意し、NVIDIAクライアントをビルドする。
既存の[ビルド・起動手順](ftpm-virt.md)と[移植手順](ftpm-helper-port.md)も参照する。

```bash
# CROSS_COMPILE、PATH、OPTEE_CLIENT_EXPORTを設定済みとする
scripts/build-qemu.sh
scripts/build-ftpm-virt-firmware.sh
scripts/build-ftpm-helper-probe.sh
scripts/fetch-ftpm-virt-kernel.py
python3 scripts/generate-ftpm-test-provisioning.py work/ftpm-test-provisioning
python3 scripts/pack-ftpm-provisioning.py \
  work/ftpm-test-provisioning/manifest.json work/ftpm-virt/device-identity.bin \
  work/ftpm-virt/provisioning.bin
sudo env FTPM_FUNCTIONAL_PROFILE=1 KERNEL_MODULES_DIR="$PWD/work/ftpm-virt/modules" \
  scripts/build-ubuntu-rootfs.sh /path/to/optee/install/t234 work/ftpm-virt/rootfs.tar
python3 scripts/prepare-ftpm-test-rootfs.py work/ftpm-virt/rootfs.tar work/ftpm-test-provisioning
sudo bash scripts/create-ftpm-virt-disk.sh
scripts/prepare-ftpm-virt-dtb.sh
# ログに成功マーカーがあり、各プロセスが正常終了することを確認
scripts/run-ftpm-virt.sh first > work/ftpm-virt/first.log 2>&1
scripts/run-ftpm-virt.sh second > work/ftpm-virt/second.log 2>&1
scripts/run-ftpm-virt.sh export > work/ftpm-virt/export.log 2>&1
python3 scripts/bind-ftpm-test-ek.py \
  work/ftpm-test-provisioning work/ftpm-virt/export.log work/ftpm-bound-provisioning
python3 scripts/pack-ftpm-provisioning.py \
  work/ftpm-bound-provisioning/manifest.json work/ftpm-virt/device-identity.bin \
  work/ftpm-bound-provisioning/provisioning.bin
mv work/ftpm-virt/provisioning.bin work/ftpm-virt/provisioning-api-fixture.bin
install -m 0600 work/ftpm-bound-provisioning/provisioning.bin work/ftpm-virt/provisioning.bin
# QEMUを停止した状態で公開fixtureとテストコードだけを更新
scripts/update-ftpm-test-disk.sh work/ftpm-bound-provisioning
scripts/prepare-ftpm-virt-dtb.sh
scripts/run-ftpm-virt.sh bound > work/ftpm-virt/bound.log 2>&1
scripts/run-ftpm-virt.sh bound > work/ftpm-virt/bound-reboot.log 2>&1
# Final rootfs service-health and fTPM check
scripts/run-ftpm-virt.sh bound > work/ftpm-virt/accounts-fixed.log 2>&1
python3 scripts/check-ftpm-functional-results.py \
  work/ftpm-virt work/ftpm-bound-provisioning work/ftpm-virt/functional-result.json
```

初回試験は新規ディスクにのみ実行する。既存ファイルを消して鍵を再生成したり、試験結果を成功に見せるためNV状態を初期化しない。
CA秘密鍵・Firmware ID秘密鍵・seed・デバイス固有ファイル・provisioning image・ディスクはGit管理外の`work/`に保存する。
ゲストへ配布するのは公開証明書、CSR、公開検証入力と検証用クライアントとTAプログラムだけ。
テスト用relay TAはPTAをユーザーTAから呼ぶための検証器であり、NVIDIA PTAの代替ではない。

## rootfsの修正

- Docker exportに入る`/.dockerenv`をディスク作成時に除去し、systemdがQEMUゲストとして判定するようにした。
- overlay／クライアントのディレクトリを0755とし、親ディレクトリが0700にならないようにした。
- PRoot `-R`がホストの`/etc/passwd`・`/etc/group`を参照する既定動作を、ゲスト自身のファイルへの明示bindで置き換えた。
  これによりguestのpasswd/groupとshadow/gshadowの不整合を防ぐ。
- 試験ディスクのオフライン更新はfsckでjournalを再生してから行い、変更後にも整合性を検査する。

現在のスクリプトはホスト直接実行が既定。Dockerと`FTPM_NATIVE_QEMU`の指定は不要。
QEMUの実行ファイルは`install/bin/`に配置する。必要ツールと権限は[ホスト環境](native-host.md)を参照。

## 検証の限界

SE、実機eFuseの耐タンパ性、メーカー証明書の信頼、REE filesystemのロールバック防止は提供しない。
Measured BootとINJECT_EPSは無効。全TPMコマンド、全OSサービス、実機との性能・タイミングの同一性を網羅した試験ではない。
ソフトウェアによるfTPMと有効なhelper PTA APIの動作・永続化を確認した結果である。

修正したrootfsではsystemd-sysusersとsystemd-resolvedの起動が成功し、保持した同じTPM状態で全B2試験にも再度合格した。ホスト直接実行時はディスクイメージへの書き込み権限が必要。
