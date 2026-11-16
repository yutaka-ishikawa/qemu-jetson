# B2：NVIDIA helper PTA全体の移植

日本語 | [English](en/ftpm-helper-port.md)

[決定0002](decisions/0002-ftpm-helper-pta.md)でユーザーがB2を選択した。
NVIDIAの`jetson_ftpm_helper_pta.c`、helper TA、fTPM TAのソースを変更せず、プラットフォーム依存部分を接続する。
[CSR署名とEKの違い](ek-csr-signing.md)も参照。

## 実装境界

- `CFG_QEMU_JETSON_FTPM=y`でNVIDIAのhelper PTAとREE状態管理を有効にする。
- vexpress独自のEPSプロパティ実装を外し、NVIDIA helper PTAの元のEPS実装を使う。
- `qemu_ftpm_platform.c`でSN・64ビットECID・fTPM EKBプロパティ取得APIを提供する。
- helper TAとfTPM TAをEarly TAとして組み込む。
- QEMUは`provisioning-file`をセキュア専用RAM `0x0c400000`（64 KiB）に読み込む。
  PTAがseed・Firmware ID鍵の受け渡し元を消去できるよう、ROMではなくRAMとする。
  リセット時は初回読み込み時の同じ内容を再配置し、ホストファイルは変更しない。

これはTegraの暗号化EKBコンテナやSEドライバの移植ではない。
元のhelper PTAに渡すデータをQEMUの仮想プラットフォームで提供する。
Linuxゲストからのアクセスを制限するが、ホスト管理者からの保護は提供しない。
NVIDIAの暗号化EKBファイルを`provisioning-file`に直接指定することはできない。

SNは既存`JFTPM001`デバイスIDの先頭10バイト、64ビットECIDは続く8バイト。
T234実機のFuseビット列からの変換とは異なる、QEMU機能検証プロファイルの規約である。
HUKは既存のデバイス固有ファイルから供給するが、B2のEPSはNVIDIA PTAのseed・SNを使う元のHKDF経路になる。
以前のB試作版のEPS導出とは異なるため、検証済みのTPM状態を移行できるとは扱わない。

## 受け渡し形式

`JFPRV001`はこのプロジェクト専用の形式。リトルエンディアン。
先頭8バイトmagic、32ビット総サイズ、32ビットエントリ数、16個分のディレクトリ。
各エントリは32ビットID・オフセット・長さ・予約領域（ゼロ）の16バイト。
ペイロードは272バイト以降に配置し、重複・範囲外・長さ異常を拒否する。

| manifestの項目 | ID | 内容 |
| --- | --- | --- |
| `ftpm_seed` | 1 | 32バイトのfTPM seed |
| `firmware_id_key` | 2 | 32バイトのEC P-256秘密スカラー |
| `firmware_id_cert` | 3 | 対応するFirmware ID証明書（DER） |
| `sn` | 91 | 10バイト。省略時はデバイスIDから設定 |
| `eps_seed` | 92 | 32バイトのEPS seed |
| `rsa_ek_cert` / `ec_ek_cert` | 93 / 94 | EK証明書（DER） |
| `sid_cert` | 95 | SID証明書（DER） |
| `rsa_ek_csr` / `ec_ek_csr` | 96 / 97 | EK CSR（DER） |

PTAの元の判定どおり、RSA/EC EK証明書が揃うとoffline、SID証明書とRSA/EC CSRが揃うとonline。
両組がある場合、元のPTAの処理順によりonlineが優先する。
秘密を含むデータ・manifest・入力ファイルはGit管理外の`work/`に置く。

manifestは項目名から入力ファイルへの相対パスを指定するJSON。
`pack-ftpm-provisioning.py`は既存の鍵を読み込むだけで生成せず、既存出力を上書きしない。
SNとデバイスID、Firmware ID鍵と証明書の公開鍵の一致、および形式・長さを検査する。
証明書チェーンの信頼や、EKがfTPM内の実際の鍵と一致することの証明は別の検証である。

```bash
python3 scripts/check-ftpm-provisioning.py
# cryptographyをインストールしたPython環境を使用する
python3 scripts/pack-ftpm-provisioning.py \
  work/provisioning/manifest.json work/ftpm-virt/device-identity.bin \
  work/ftpm-virt/provisioning.bin
scripts/prepare-ftpm-virt-dtb.sh
```

DTは`nvidia,ftpm-contents`およびseed・Firmware ID鍵・証明書の受け渡し先アドレスを含む。
DT自体に秘密データは埋め込まない。PTAは元のDT処理で内容を取り込み、受け渡し元を消去する。

## 検証状態

テストCAの生成をユーザーが承認し、NVIDIAの有効なhelper PTA API、署名の暗号学的検証、TPMコマンド、完全停止後のNV・鍵・sealed dataの保持を確認した。
実際のfTPMのRSA/EC EK公開鍵に対応する証明書・CSRと、標準NV indexのEK証明書も検証済み。
[最新の結果・再現手順](ftpm-functional-validation.md)と[機械可読結果](results/ftpm-functional.json)を参照。
`INJECT_EPS`は元の設定どおり無効。Measured Bootも無効。実機SEの保護やメーカーCAの信頼を提供するものではない。

[初期のデータなし起動結果](results/ftpm-helper-b2.json)と[そのログ](results/ftpm-helper-b2-boot-excerpt.txt)は開発履歴として保持する。
