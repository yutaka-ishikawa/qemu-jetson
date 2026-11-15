# 無変更T234 OP-TEEのQEMU起動設計

調査日：2026-11-16（日本時間）。ソース調査に基づく設計案。
QEMUの実装、起動試験、TPM実行試験は未実施。アドレスのマッピングだけで
デバイス動作が再現できるとは判断しない。

## 結論

NVIDIAのT234向けOP-TEE／fTPMソースと前段階の成果物を維持し、
**専用のQEMUマシンモデルと起動用ファームウェアを追加する**方針を提案する。
CPU、割り込みコントローラ、タイマなどはQEMUの既存部品を再利用する。
最初の目標はOP-TEEのログ出力であり、fTPM動作やJetson全体の再現とは別の到達点とする。

NVIDIA版ATFの無変更実行は初期目標に含めない。OP-TEEだけでなく
NVIDIA版ATFも必須なら、MC、MCE/ARI、電源・リセットなどの依存調査を追加する必要がある。
この選択はNVIDIA版OP-TEE／fTPMソースを維持するための実装案であり、
ユーザーの「NVIDIA開発環境でコンパイルされたコード」の全範囲を満たしたという意味ではない。

## 標準virtとの相違

比較用に [QEMU v9.2.0のhw/arm/virt.c](https://github.com/qemu/qemu/blob/v9.2.0/hw/arm/virt.c)
を確認した。これは比較の固定参照であり、今後の実装に使うQEMUバージョンは未選定。

- virtのFlash範囲は `0x00000000–0x07ffffff`。T234のFuse、SE、RNG1、QSPIのアドレスと重なる。
- virtのSecure RAMは `0x0e000000`、16 MiB。T234ビルドのTZDRAM設定は
  `0x80000000`、`0x03fc0000`バイト（63.75 MiB）。単純に既定Secure RAMへ置けない。
- TCUの `0x0c198000` はvirtのplatform bus領域内。追加方法と重複処理を決める必要がある。
- virtのGIC配置はT234の配置と異なる。NVIDIA版ATFはGICD `0x0f400000`、GICR `0x0f440000` を使う。

OP-TEEは物理再配置を有効化しているが、今回の最初の試験ではリンク時設定を基準に
Secure RAMを配置し、再配置とマシンモデルの問題を同時に増やさない。
EL3ファームウェア、DT、OP-TEE、共有メモリの配置は実装時に重複検査する。

## OP-TEEに入るまでの契約

NVIDIAのATFソースも公式public_sourcesから取得・展開した。
内包 `atf_src.tbz2` のSHA-256は
`dd79c4e9dd82f54ff2c3fa9c520530a4d5b7ef3b965f641036ddb9d1ecf1e1ad`。
SHA-1 `4787ede3d1c2721f2c3c744b9b4534062f91d9e0` は同梱値と一致。

ATFの `services/spd/opteed/opteed_main.c` と `opteed_common.c` を確認すると、
BL32 entry情報のargsはOP-TEEに入るレジスタと同じ並びではない。

| BL32 entry情報 | OPTEEDの扱い | OP-TEE初回エントリ |
| --- | --- | --- |
| arg0 | AArch32／AArch64の選択 | 実行状態の構成に使用 |
| arg1 | pageable_part | x0 |
| arg2 | mem_limit | x1 |
| arg3 | DTアドレス | x2 |

今回のOP-TEEはPager無効、Transfer List無効。`core/arch/arm/kernel/boot.c`
の `boot_save_args()` はx2から外部DTを保存する。
`-kernel tee-raw.bin` のようなLinux向け起動では、この契約やSecure EL1状態を満たせない。
ローダーでPCだけ設定する方法も、EL3へのSMC復帰先を提供しないため十分ではない。

最初の試験用ファームウェアは、EL3初期化、Secure EL1への遷移、例外記録を担当する。
初期化完了まで進む段階ではOP-TEEのENTRY_DONEを受けるSMC処理も必要。
Linuxとの連携段階では、検証済みのTF-A OPTEEDなどによる通常のSecure Monitor構成へ進む。
独自の最小ローダーを本番用Secure Monitorとして扱わない。

## MMIOと起動依存

参照元はR36.5.2 OP-TEEパッケージ内。別記しないパスは `optee/optee_os/` 以下。

| 領域 | ベース／サイズ | 必要な動作と根拠 |
| --- | --- | --- |
| Combined UART（TCU） | `0x0c198000 / 0x1000` | `core/drivers/tegra_combined_uart.c`。送信ワードのbit31はbusy／trigger、bit24は1文字、bit26はflush。busy解除と文字出力が最初の観測点 |
| Fuse | `0x03810000 / 0x600` | `core/drivers/tegra/t234/tegra_fuse.c` とcommon側。識別子、BSI、security modeを読む |
| SE0 | `0x03b50000 / 0x30000` | 公式DTとT234 SEドライバ。CCCの初期化、AES、鍵スロット、乱数生成の実行経路に関係 |
| RNG1 | `0x03b70000 / 0x10000` | CCCデバイス初期化でマップ。T234の公開 `rng_get_random` 経路は `tegra_se_ccc_aes_genrnd()` を呼ぶので、RNG1だけを実装して十分とは言えない |
| QSPI | `0x03270000 / 0x10000` | plat-tegra/main.cで登録、StMMにもマッピング。実際の起動時アクセスは未確認 |
| Scratch | `0x0c390000` | main.cの登録は`0x1000`、StMM DTは2ページ指定。マッピングと実アクセス範囲を区別する |

公式ビルドはCCCのprebuiltライブラリをリンクするため、公開Cソースだけでは
SEの全MMIOプロトコルを確定できない。ライブラリの逆アセンブルは行っていない。
公開仕様とQEMUの実アクセス記録から調査し、SEの実装見積もりはまだ確定しない。
不明レジスタを一律0で成功扱いする実装では、暗号・乱数・永続化の正しさを確認できない。

### Fuseモデルの初期仕様

最初は読み取り専用のテスト用Fuseイメージをホストから設定し、通常の再起動では保持する。
Fuse書き込み・焼き込み動作は初期試験には含めない。

読み取り対象として確認したオフセット：

- security mode：`0x1a0`。
- vendor／fab／lot／wafer／座標／reserved：`0x200, 0x204, 0x208, 0x20c, 0x210, 0x214, 0x218, 0x220`。
- Boot Security Info：`0x268`。OEM key validのmaskは`0x200`。
- ODM_INFO：`0x29c`、ODMID0：`0x408`、ODMID1：`0x40c`。

SNは10バイト。`core/drivers/tegra/common/tegra_driver_fuse.c:fuse_generate_sn()`
にはODM_INFOとODMIDのバイト順の違いがある。EKBのSNと同じ数値表記を並べるだけでは不十分。
具体的なテスト値と期待バイト列を定義してから実装する。

`CFG_TEGRA_SE_USE_TEST_KEYS=y` の既存経路では、BSIのOEM key validが0なら
CCCに全ゼロのテストOEMキーを設定する。ただし、その処理自体にSE実装が必要。
このキー設定だけでeFuse依存性がなくなるわけではない。

## DTでMB2の成果を受け渡す

公式 `optee/tegra234-optee.dts` のコメントと利用側を確認した。
MB2全体を動かす前に、試験用ファームウェアが同じ形式の入力を用意する案を採る。

- non-secureメモリは `device_type = "memory"` のregで通知。Secure RAMと重複させない。
- Fuse／SE／RNG1は対応compatible、reg、secure-statusを持たせる。
- EKBは `jetson-ekb-blob` のregで渡す。利用側が内容をコピー後に消去するため、書き込み可能なRAMが必要。
- fTPMのシード、Firmware ID秘密鍵と証明書はSecure RAM上に置き、対応ノードのregで渡す。
- TPMイベントログとboot-modeも実装段階に応じて構成する。

初回のログ試験では未実装のDTノードを有効化して架空の正常状態を作らない。
fTPM機能試験へ進む際に、EKB・ストレージ鍵・Fuse SNとの整合を検証する。

## 段階と合格条件

| 段階 | 実装するもの | 合格条件 |
| --- | --- | --- |
| A：最初のログ | 専用マシン、Secure CPU／RAM、TCU、最小EL3起動、試験DT | 無変更tee-raw.binがOP-TEEのログを出す。停止位置と未実装MMIOを記録できる |
| B：初期化完了 | Fuse、SE／乱数、必要なDT入力、SMC復帰 | OP-TEE ENTRY_DONEまで到達。ログのinitcall失敗、panic、未実装MMIOを評価し、黙認しない |
| C：Linux連携 | Secure Monitor、非Secure Linux、OP-TEE driver、tee-supplicant | TA呼び出しとREE FS永続化が成立 |
| D：fTPM基本機能 | fTPM driver、tpm2-tools、仮想デバイス状態の保存 | GetCapability、PCR操作、NV、鍵、seal／unseal、再起動後の利用を確認 |
| E：デバイス同一性 | Fuse／シード／EKB／EK証明書の整合 | 同じ仮想デバイスで鍵が安定し、別デバイスでは分離。クリア・複製・スナップショットの挙動を確認 |

次に着手するのは**段階A**。CPUはまず1コアのTCGを使い、Pointer Authentication対応を確認する。
実機のCortex-A78AEや12コア構成の完全再現を前提にしない。
段階AのログだけをもってOP-TEE正常起動やfTPM同等性の達成とは報告しない。
