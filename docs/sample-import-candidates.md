# OP-TEEサンプルのimport候補

日本語 | [English](en/sample-import-candidates.md)

2026-11-17（日本時間）調査。ユーザー依頼によりsamples/ftpm-helper-probeを追加済み。
以下の追加importは判断待ちであり、まだ取り込んでいない。

## 推奨する取得元

[linaro-swg/optee_examples](https://github.com/linaro-swg/optee_examples)はOP-TEEのサンプル集。
[LICENSE](https://github.com/linaro-swg/optee_examples/blob/master/LICENSE)は原則BSD-2-Clauseで、各ファイル独自のライセンスが優先される。
確認したhello_world/host/main.cとsecure_storage/ta/secure_storage_ta.cにもBSD-2-Clauseの明記がある。
import時には採用する固定コミット、全対象ファイルのライセンス・著作権表示を確認・保存する。
masterを無条件に追従せず、このリポジトリのNVIDIA OP-TEE SDKとのビルド・実行互換性を確認する。

| 候補 | 学べる内容 | 利点・制約 |
| --- | --- | --- |
| hello_world | セッション開始、TAへのコマンド呼出し | 最小の入門例。TPM固有機能は含まない |
| random | TA内での乱数生成、結果の受渡し | 基本APIを短いコードで確認。乱数の品質認証ではない |
| secure_storage | TAの永続オブジェクト保存・読出し | 再起動後の保持を試せる。現在のREE filesystemではホストのロールバックへの耐性を意味しない |
| aes | TA内の対称鍵暗号 | 暗号APIの入門。基本3例より学習範囲が広がる |
| sign_verify | TA内の署名・検証 | TPMを介さない暗号APIの例。EKやFirmware ID署名とは別 |

## 提示した選択肢

- A（推奨）：hello_world・random・secure_storage。まず基本呼出しと永続化を学ぶ。
- B：Aにaes・sign_verifyを追加。暗号APIまで扱う分、検証対象が増える。
- C：今回は候補の記録のみ。追加importは後で決める。

状態：ユーザー判断待ち。採用後に選択内容と固定した取得元を追記する。

## 同梱済みNVIDIAサンプルについて

optee/optee/samplesにはftpm-helper、hwkey-agent、luks-srv、ms-tpm、pkcs11-sample等がある。
pkcs11-sample/LICENSEにはBSD形式の条件があるが、ライセンスだけでは現在のB2で動くとは判断できない。
hwkey-agent等はTegra固有PTA・鍵経路に依存するため、今回のQEMU B2でそのまま動く入門サンプルとしては推奨しない。
