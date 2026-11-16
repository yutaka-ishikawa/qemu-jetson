# OP-TEEページテーブル使用量の解析

日本語 | [English](en/page-table-analysis.md)

## 結論

QEMU B2の診断ビルドで、**DTBのASLR seedにより使用数が変わり、今回の最大は9/32個**と確認した。
9個を必要とする配置でもbound試験はPASSした。観測した最大値に対する残りは23個（92KiB）。
これは今回試した配置・負荷での余裕であり、全seed・全TPM負荷に対する上限の証明ではない。
32個の設定を維持し、この計測だけを理由に9個へ減らさない。

以前のユーザー環境では8個を使い切り、次の割当てに失敗していた。
今回、起動時に8個、最初の非セキュア共有メモリのマッピングで9個になる経路を計測した。
元のユーザーDTBそのものは未受領なので、当時の配置をビット単位で再現したとは主張しないが、同じ不足条件を生む配置を確認できた。

## 対象と計測方法

- 対象：jetson-ftpm-virt、Cortex-A57、1 CPU、RAM 1GiB、NVIDIA Linux 5.15.199-tegra、B2 OP-TEE。
- CFG_CORE_ASLR=y、CFG_NS_VIRTUALIZATION無効、MAX_XLAT_TABLES=32。
- core_mmu_xlat_table_allocで割当て後のxlat_tables_used、上限を記録。
- core_mmu_entry_to_finer_grainedで分割元のレベル・VA・index、core_mmu_entry_copyでコピーを記録。
- core_mmu_map_pagesでVA、ページ数、memtypeを記録。秘密値やページ内容は出力しない。
- [診断パッチ](results/xlat-analysis/instrumentation.patch)はログ出力だけ。計測後にソースから除去し、通常のファームウェアを再ビルド・配置した。
- 通常DTBでsecondとboundを完走。追加で/secure-chosen/kaslr-seedだけを変更し、5種類を6秒ずつ起動した。
- 追加試験はQEMUの-snapshotと書込み可能なTMPDIRを使用し、ディスクへの書込みを破棄。9個を使うseedではboundも完走した。
- 元のDTBは復元した。仮想ID・CA・seedファイル・provisioning・TPM NVを再生成していない。ここで変えたkaslr-seedはメモリ配置用であり、TPMのEPS/デバイスseedとは別。

## 実測値

起動時は`Primary CPU switching to normal world boot`まで。ピークは計測ログ全体の最大。

| 配置・負荷 | 起動時 | ピーク | 32個との差 | 結果 |
| --- | ---: | ---: | ---: | --- |
| 既存DTB、second | 4 | 5 | 27 | PASS |
| 既存DTB、bound | 4 | 5 | 27 | PASS |
| secure seed 0x0000000000000001 | 6 | 7 | 25 | 6秒の起動計測 |
| secure seed 0x0000000020001000 | 5 | 6 | 26 | 6秒の起動計測 |
| secure seed 0x0000000060001000 | 6 | 7 | 25 | 6秒の起動計測 |
| secure seed 0x00000000b3b0b000 | 8 | 9 | 23 | 6秒の起動計測 |
| secure seed 0x00000000fdf01000 | 7 | 8 | 24 | 6秒の起動計測 |
| secure seed 0x00000000b3b0b000、bound | 8 | 9 | 23 | PASS |

短時間試験の終了コード124は意図した打切りであり、fTPM試験全体のPASSを意味しない。
9個の配置のboundではPTA検証、実EK/証明書一致、標準NV、second、EK_TESTがすべてPASSした。

### 元の上限8個の決まり方

測定時の設定はCFG_LPAE_ADDR_SPACE_BITS=32、CFG_CORE_ASLR=y、CFG_NS_VIRTUALIZATION=n。
QEMU専用の上書きがない場合、core_mmu_lpae.cの既定式はこの条件でTEE用5個＋ASLR用3個＝8個となる。
これはこの実装の既定の容量設定であり、あらゆる仮想配置の必要数を保証する計算式ではない。
今回の32個はQEMU fTPMプラットフォームのMAX_XLAT_TABLESによる上書き。
9個の配置ではbound中の411回のcore_mmu_map_pages呼出しを通じて最大9個のままで、呼出しごとにテーブルが増える挙動は観測しなかった。

## なぜ8個では足りない配置があるか

1. OP-TEEは[boot.c](../optee/optee/optee_os/core/arch/arm/kernel/boot.c)で/secure-chosen/kaslr-seedを取得し、[core_mmu.c](../optee/optee/optee_os/core/mm/core_mmu.c)で仮想配置を決める。
2. 異なる仮想配置は、異なる1GiB/2MiB境界にまたがる。領域の総バイト数だけでは必要な変換テーブル数は決まらない。
3. 今回の9個の配置では、L1からの分割が3回、L2からの分割が6回発生した。各分割で1個の下位テーブルを割り当てた。COPYイベントはなかった。
4. 最初の8個は通常世界に渡る前に使用済み。次にMEM_AREA_NSEC_SHM（memtype=13）の4KiBマッピングが、VA 0xbea00000を含む領域にL3テーブルを要求した。

```text
XLAT_MAP va=bea00000 pages=1 type=13
XLAT_SPLIT level=2 va=80000000 idx=501
XLAT_ALLOC used=9 max=32
```

このL2 tableはVA 0x80000000を基点に、index 501の2MiB領域を4KiBページへ分割する。
L1からL2への分割は1GiB領域の細分化、L2からL3への分割は2MiB領域の細分化に相当する。
上限8なら[core_mmu_lpae.c](../optee/optee/optee_os/core/arch/arm/mm/core_mmu_lpae.c)の`used >= MAX_XLAT_TABLES`で9個目を拒否し、map_pages側がpanicする。

実際に受領した変更前のエラーは次のとおり。

```text
8 xlat tables exhausted
Panic 'Failed to spread pgdir on small tables'
```

Linuxの最後の表示がシリアルコンソール切替だったことは、UART自体が原因という証拠ではない。
セキュア側でpanicした後、Linuxの進行が止まってタイムアウトした。

## メモリ量と「使用量」の意味

- 1個は512エントリ×8バイト=4096バイト。pool全体は8個時32KiB、32個時128KiB、増分96KiB。
- 観測ピーク9個分は36KiB、残り23個分は92KiB。ただしpoolは静的配列なので未使用分も確保される。92KiBが一般用途の空きメモリになるわけではない。
- xlat_tables_usedはこのpoolの割当てカウンタ。今回の非仮想化構成では起動内の高水位として扱える。マッピング解除ごとに減るカウンタではない。
- ベーステーブル、xlat_tables_ul1、TA側のページテーブル等は別枠。本書の9個はOP-TEEの全ページテーブルメモリ量ではない。
- ASLR seedの違いが必要数を変えることを制御試験で確認した。断片化やリークを推測しただけの説明にはしない。一方、未実施の長時間・多TA・全メモリ配置にリークがないと証明したわけでもない。

## 証拠と再集計

[集計](results/xlat-analysis/usage.json)、[要約](results/xlat-analysis/summary.json)、同ディレクトリのsecureログと通常ログ抜粋を保存した。

```bash
python3 scripts/analyze-ftpm-xlat-log.py docs/results/xlat-analysis/*.log
```

このコマンドは診断済みログを読むだけで、鍵・ディスクを変更しない。
再計測はQEMU停止中に診断パッチを適用してファームウェアをビルドする。通常のビルドには計測パッチを適用しない。
再現用seedの設定例は`fdtput -t x DTB /secure-chosen kaslr-seed 0 b3b0b000`。
DTBの退避・復元、QEMUの-snapshot、書込み可能なTMPDIRを必須とし、通常ディスクへ並行起動しない。

実機のT234メモリ配置で同じ使用数になるとは限らない。実機側の必要数は実機で別途計測する必要がある。
