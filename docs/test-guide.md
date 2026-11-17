# fTPM・EK証明書テスト手順

日本語 | [English](en/test-guide.md)

この手順は[ビルド・インストール手順](build-install.md)で準備したB2構成を使い、firstから全試験を実行する。QEMU専用テストCAによる機能検証であり、NVIDIA製造証明書の信頼は提供しない。
従来の[機能検証の再現手順](ftpm-functional-validation.md)は初期構築からの全工程を記載する。現在のビルド・導入はbuild-install.md、テスト実行は本書を参照する。

新規構築は[build-install.md](build-install.md)、既存環境の更新は[upgrade-guide.md](upgrade-guide.md)、通常利用は[runtime-guide.md](runtime-guide.md)を参照。本書はテスト実行と判定だけを扱う。

## 開始前と現在の位置

すべてリポジトリ直下、同じPython venvで実行する。

```bash
cd /home/ishikawa/work/qemu-jetson
source work/venv/bin/activate
set -o pipefail
```

別の場所にcloneした場合はcd先だけ変更する。teeを使う各シェルでpipefailを有効にする。
各コマンドの成功を確認してから次へ進む。QEMUの終了コード0だけで成功とせず、PASSとFAILの有無を確認する。
失敗・タイムアウト（通常124）ならそこで停止し、通常ログとsecureログを保存する。

| 段階 | 内容 | この対話で確認済みの状態 |
| --- | --- | --- |
| first | 新規ディスクでNV・PCR・署名・seal/unsealを初期検証 | 既存ディスクには完了マーカーあり。再実行不要 |
| second | 再起動後のNV・鍵・sealed dataとPCR | 添付ログでPASS確認済み |
| export | 実際のRSA/ECC EK公開鍵の取得 | 添付export.logでPASS確認済み |
| bind / pack | 既存テストCAで実EK用証明書を発行しデータを梱包 | 実行結果は未確認 |
| 適用 / bound | PTA証明書と実EKの一致、標準NV indexの検証 | 未確認 |
| bound再起動 | EK・証明書NV・既存TPM状態の永続化 | 未確認 |

secondとexportのPASSを既に確認していれば再実行せず、手順3から続ける。
既にbound用ディレクトリや切り替え前バックアップがある場合は、削除・再生成せず準備済みの段階を確認する。
鍵、device-identity.bin、CA、rootfs.ext4、ゲストのfirst.done、TPM NV状態を消さない。
firstは新規ディスクに一度だけ実行し、完了済みなら再実行しない。QEMUを多重起動しない。

## 0. first：新規ディスクの初回試験

新規導入したディスクだけで実行する。既存ディスクでfirst完了済みの場合は手順1へ進む。

```bash
bash scripts/run-ftpm-virt.sh first 2>&1 | tee work/ftpm-virt/first.log
```

成功条件：`FTPM_TEST: PASS phase=first`。PTAの証明書・CSR・署名検証、TPM能力・乱数、NV書き込み/読み出し、PCR extend、RSA署名、seal/unsealを実行し、自動で電源を切る。
初回試験では後続の永続化検証に使うTPM状態を作る。first.doneが存在する場合は再実行を拒否する。
FAIL line=22は現在のスクリプトでは完了マーカーの存在確認での失敗。マーカーを削除せず、実行履歴を確認する。

## 1. second：再起動後の検証

```bash
bash scripts/run-ftpm-virt.sh second 2>&1 | tee work/ftpm-virt/second.log
```

成功条件：`FTPM_TEST: PASS phase=second`。NV・署名鍵・sealed dataの保持、PCRリセット、RSA署名、seal/unsealとPTA検証を実行する。
既に成功していてログがない場合、記録を得るためのsecond再実行は可能。firstを代わりに実行しない。

## 2. export：実際のEK公開鍵を取得

```bash
bash scripts/run-ftpm-virt.sh export 2>&1 | tee work/ftpm-virt/export.log
```

成功条件：`EK_EXPORT: rsa ...`と`EK_EXPORT: ecc ...`の両方、最後に`EK_TEST: PASS`。
EK秘密鍵は出力しない。このログは次の証明書発行の入力なので保存する。

## 3. bind：既存CAで実EK用のテスト証明書を発行

```bash
python3 scripts/bind-ftpm-test-ek.py \
  work/ftpm-test-provisioning \
  work/ftpm-virt/export.log \
  work/ftpm-bound-provisioning
```

成功時に`Test-only certificates issued for actual fTPM RSA/EC EK public keys; seeds and device keys unchanged.`と表示する。
新しい出力先work/ftpm-bound-provisioningを作り、既存CAでRSA/ECC EK証明書とFirmware ID署名CSRを発行する。
出力先が存在すると拒否する。その場合、既に完了しているかを確認し、ディレクトリを消して再発行しない。
CAやFirmware ID秘密鍵を添付・pushしない。

## 4. pack：PTAへ渡すデータを梱包

```bash
python3 scripts/pack-ftpm-provisioning.py \
  work/ftpm-bound-provisioning/manifest.json \
  work/ftpm-virt/device-identity.bin \
  work/ftpm-bound-provisioning/provisioning.bin
```

正常終了し、最後の出力ファイルが作成されることを確認する。既存の出力は上書きしない。
まだ稼働用のprovisioning.binは切り替わらない。

## 5. QEMU停止確認とデータ切り替え

```bash
pgrep -af '[q]emu-system-aarch64'
```

対象ディスクを開いているQEMUがないことを確認する。表示される場合はそのQEMUを正常終了させてから続ける。
以下は初回切り替え専用。バックアップがあればエラーで停止する。バックアップを消して再実行しない。

```bash
(
  set -e
  test ! -e work/ftpm-virt/provisioning-api-fixture.bin
  cp -p work/ftpm-virt/provisioning.bin work/ftpm-virt/provisioning-api-fixture.bin
  install -m 0600 work/ftpm-bound-provisioning/provisioning.bin \
    work/ftpm-virt/provisioning.bin
)
```

既存のseedとデバイスIDは保持し、証明書等のprovisioning内容だけを切り替える。
バックアップが存在する場合は処理を停止する。上書きせず、既にどこまで実行済みか確認する。
切り替え後の公開証明書・CSR・試験プログラムを、停止中の既存ディスクへ適用する。

```bash
bash scripts/update-ftpm-test-disk.sh work/ftpm-bound-provisioning
```

e2fsck/debugfsによる更新が正常終了したことを確認する。ディスク全体の再作成は不要。
CA秘密鍵・Firmware ID秘密鍵をゲストへ配布しない。

## 6. DTBを再生成しboundを実行

```bash
bash scripts/prepare-ftpm-virt-dtb.sh
```

正常終了後に起動する。新しいprovisioningをDTBにも埋め込むため、再生成は必須。

```bash
bash scripts/run-ftpm-virt.sh bound 2>&1 | tee work/ftpm-virt/bound.log
```

次のすべてが必要。FAILがあれば成功と扱わない。

```text
PTA_TEST: certificates/CSR match, CA chains, Firmware ID signature PASS
EK_TEST: actual RSA/EC EK keys match PTA certificates PASS
EK_TEST: standard RSA/EC EK certificate NV indices PASS
FTPM_TEST: PASS phase=second
EK_TEST: PASS
```

標準NV indexはRSAが0x01c00002、ECCが0x01c0000a。
未作成のindexはゲスト内で証明書を登録し、読み戻した内容がPTAの証明書と一致することを確認する。
既存indexは上書きせず内容を比較する。不一致なら停止し、削除で回避しない。
bound内で既存TPM状態のsecond試験も実行する。

## 7. boundを再起動し永続化を確認

前回がPASSしてQEMUが終了してから、同じディスク・鍵・provisioningで実行する。

```bash
bash scripts/run-ftpm-virt.sh bound 2>&1 | tee work/ftpm-virt/bound-reboot.log
```

手順6と同じ全PASSを確認する。RSA/ECCのEK_EXPORT値もexport.logと同じであることを確認する。
これで実EKと証明書の一致、標準NV証明書の再起動後の保持、従来のTPM状態の保持を確認できる。

## ログ・失敗時の扱い

通常ログは上のtee出力、セキュアログはwork/ftpm-virt/secure-<phase>-native.log。
同じphaseを再実行するとセキュアログは上書きされるため、必要なログを先に別名で保存する。
PASS後の`ERROR: QEMU System Power off: with GPIO.`はこのファームウェアの電源断時の表示。
この表示だけ、ログインプロンプトの表示だけ、QEMU終了だけでは成功と判定しない。

従来のcheck-ftpm-functional-results.pyはfirst/second/export/bound/bound-reboot/accounts-fixedの6ログすべてを要求する。
本書の続行手順だけで実行すると、first.logやaccounts-fixed.logの欠落で失敗し得るため、必須手順には含めない。
不足するログをコピー・改変して検証を通さない。必要なら[従来の全工程](ftpm-functional-validation.md)の証拠を揃える。
本書は全TPMコマンドや実機eFuseの耐タンパ性、ロールバック耐性を検証するものではない。

## ページテーブル数変更後の確認結果

2026-11-17（日本時間）、ユーザーから本書の全テストPASSの報告を受けた。進捗表は手順作成時点の履歴。
OP-TEEのテーブル数8→32の変更理由と変更前のpanicは[ビルド・導入手順](build-install.md#op-teeのページテーブル数変更と変更前のエラー)を参照。

## 実機との差分と検証証拠

[実機とQEMUの違い](hardware-qemu-differences.md)と[最終テストの証拠整理](final-test-evidence.md)を参照。

対話利用は[通常起動・SSH・共有・デバッグ](runtime-guide.md)を参照。現行ランチャーは引数なしで通常起動、既定4CPU。試験モードは明示する。旧ファームウェアからの更新手順も同書に記載。
