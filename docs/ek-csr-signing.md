# SIGN_EK_CSRの署名鍵とEKの違い

日本語 | [English](en/ek-csr-signing.md)

結論：NVIDIAのhelper PTAの`SIGN_EK_CSR`は、EK自身を使った署名ではない。
EKのCSR（証明書署名要求）のダイジェストをFirmware ID秘密鍵で署名する。
また、メーカーCAがEK証明書に付ける署名とも異なる。

| 操作 | 署名する対象 | 使用する秘密鍵 | 意味 |
| --- | --- | --- | --- |
| helper PTAの`SIGN_EK_CSR` | EK CSRのSHA-256ダイジェスト（32バイト） | Firmware IDのEC P-256秘密鍵 | Firmware ID鍵の所持に基づいてEKの証明書要求を署名 |
| EK証明書の発行 | EK公開鍵などを含む証明書の署名前部分 | メーカー／テストCAの秘密鍵 | CAがEK公開鍵と証明書内の属性を証明 |
| 一般のTPM署名（例：`TPM2_Sign`） | コマンドが指定するダイジェストなど | 指定したTPM署名オブジェクトの秘密鍵 | そのTPM署名鍵による署名 |

一般的なTCG EKテンプレートのEKはrestricted decrypt鍵であり、通常の署名鍵として使わない。
TPM保有の確認には、EKによる任意データ署名の代わりに、AKと`MakeCredential`／`ActivateCredential`などを使う方式がある。
この一般的なTPMの説明と、NVIDIA固有のCSR署名経路は分けて考える。

## NVIDIAソースで確認した処理

1. helper TAがCSRのCertificateRequestInfo部分のハッシュを計算する。
2. helper TAからhelper PTAの`FTPM_HELPER_PTA_CMD_SIGN_EK_CSR`を呼ぶ。
3. PTAの`sign_ek_csr_digest()`は、入力がSHA-256の32バイト、出力バッファが80バイトであることを検査する。
4. `crypto_acipher_ecc_sign(TEE_ALG_ECDSA_SHA256, &ftpm_property.fw_id_key, ...)`を呼ぶ。EKは渡していない。
5. helper TAは戻されたr/s署名をASN.1表現へ変換し、CSRの署名部分を更新する。

Firmware ID鍵はPTA内でNIST P-256として確保される。秘密スカラーは、セキュア側で使うDTの
`nvidia,ftpm-firmware-id-privkey`が指す32バイトから読み込む。
対応するFirmware ID証明書は`nvidia,ftpm-firmware-id-certificate`から取得する。
`SIGN_EK_CSR`内でFirmware ID秘密鍵をTPMのEKから生成する処理や、`TPM2_Sign`を呼ぶ処理はない。

この署名を検証する鍵はFirmware ID公開鍵であり、CSR内のEK公開鍵ではない。
Firmware ID証明書の発行元の信頼と、実際にCSRが示すEKをTPMが保有することの確認は、別途検証する事項である。
このAPI単独でEKの保有証明や実機相当のハードウェア保護が成立すると主張しない。

## QEMU B2での扱い

[決定0002](decisions/0002-ftpm-helper-pta.md)に従い、NVIDIAのhelper PTA全体を使う。
Firmware ID鍵・証明書を含むプロビジョニング情報は、QEMU用データとして出自と検証範囲を明記する。
EK鍵、Firmware ID鍵、CA鍵は異なる役割の鍵として扱う。

## ソース

- [helper PTA：署名処理とFirmware ID鍵の読み込み](../optee/optee/optee_os/core/pta/tegra/jetson_ftpm_helper_pta.c)
- [helper TA：CSRのハッシュ・署名呼出し・ASN.1変換](../optee/optee/samples/ftpm-helper/ta/ftpm_helper_ta.c)
- [PTAコマンド定義](../optee/optee/optee_os/lib/libutee/include/pta_jetson_ftpm_helper.h)
