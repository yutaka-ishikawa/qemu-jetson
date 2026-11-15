# Jetson Linuxリリース候補

日本語 | [English](en/release-candidates.md)

調査日：2026-11-16（日本時間）。公式Web資料を確認した段階。
配布ソースの展開、ライセンスの個別確認、ビルド、QEMU実行は未実施。

## 候補と提案

| 優先度 | JetPack / L4T | 公式に確認できた内容 | 判断 |
| --- | --- | --- | --- |
| 第1候補 | 6.2.3 / R36.5.2 | Orin Nano対応。Ubuntu 22.04、Linux 5.15、OP-TEE。BSPソースとBootlin GCC 11.3へのリンク。fTPMの構築・プロビジョニング手順あり | 最初のソース調査対象として推奨。R36系で修正が反映された候補 |
| 比較候補 | 6.2.1 / R36.4.4 | Orin Nano対応。Ubuntu 22.04、Linux 5.15。OP-TEEとfTPMの資料、BSPソースとBootlin GCC 11.3へのリンク | fTPMの旧実装との比較基準。第1候補と必要な差分がある場合に検討 |
| 新系列候補 | 7.2.1 / R39.2.1 | Orin対応。Ubuntu 24.04、Linux 6.8。BSPソースとCrosstool-NGツールチェーンへのリンク。fTPM資料はOrin Nanoを適用対象に明記 | 新規環境の有力候補。ただしR36系からfTPM実装・EK互換性の変更があり別途評価 |

R35.7 / JetPack 5.1.8もOrin NanoとOP-TEEに対応しているが、今回確認した
FirmwareTPM.htmlのURLは404だった。fTPM非対応と断定する根拠ではないが、
既存のJetPack 5互換要件がないため優先候補から外す。
R38系は公式アーカイブのOrin Nano対応欄が空欄のため採用候補としない。

「NVIDIAソース変更が最少」と実証できたリリースは、現段階ではない。
R36.5.2の推奨は調査開始点の提案であり、QEMU互換性の保証や採用確定ではない。

## fTPMの系列差

R39.2.1の公式fTPM文書は、R36.4.4 GAとR38.4 GA以降の違いを説明している。

- R36.4.4：ms-tpm-20-refコミット `e9fc7b89d865536c46deb63f9c7d0121a3ded49c`、TPM仕様Revision 1.59、Samples内のTA。
- R38.4以降：TPM仕様Revision 1.84、TAをOP-TEE/optee_ftpmに移動。
- RSAのEK生成に旧版との互換性がない旨を明記。
- OP-TEE 4.4.0への更新でREE FSの既定位置が `/data/tee` から `/var/lib/tee/` に変更。

この記述だけからR36.5.2の内部コミットを推定しない。配布ソースで確認する。
ユーザーから見たfTPMの同等性には、対象リリースを固定する必要がある。

## eFuseに関する重要な確認結果

R36.5.2のfTPM文書では、次の流れが説明されている。

1. KDK0とDevice_SNに基づき、PSCBL層でSilicon_IDを導出する。
2. MB2層でfTPM SeedとSilicon ID Key Seedを導出する。
3. fTPM Seedを暗号化されたTZメモリを経由してOP-TEEに渡す。
4. fTPM Helper PTAが、その値とEKB内のEPS_SeedなどからEPSを導出する。
5. fTPM TAにEPSを初回投入し、NVに保存する。

鍵生成にはTZ-SEとCPUからアクセスできない鍵スロットが関係する。
したがってFuseレジスタの値だけの再現で済むとは判断できない。
NVIDIAソースを維持するため、実機ブート処理をどこまで再現するか、
同じ入力状態をQEMUの起動時に構成できるかをソースから調べる。

## 次のステップ

R36.5.2を最初の調査対象として、公式BSPソースから
`nvidia-jetson-optee-source.tbz2`、`atf_and_optee_README.txt`、
fTPM関連ソースとビルド設定を確認する。
公式OP-TEE手順はこの内包アーカイブとREADMEを案内している。
配布物のハッシュ、ソースの版、個別ライセンスを記録してからビルドへ進む。
第三者のソースを本リポジトリに取り込む前に再配布条件を確認する。

## 公式資料

- [Jetson Linux Archive](https://developer.nvidia.com/embedded/jetson-linux-archive)
- [R36.5.2 リリース・配布物](https://developer.nvidia.com/embedded/jetson-linux-r3652)
- [R36.5.2 OP-TEE](https://docs.nvidia.com/jetson/archives/r36.5.2/DeveloperGuide/SD/Security/OpTee.html)
- [R36.5.2 fTPM](https://docs.nvidia.com/jetson/archives/r36.5.2/DeveloperGuide/SD/Security/FirmwareTPM.html)
- [R36.4.4 リリース・配布物](https://developer.nvidia.com/embedded/jetson-linux-r3644)
- [R36.4.4 fTPM](https://docs.nvidia.com/jetson/archives/r36.4.4/DeveloperGuide/SD/Security/FirmwareTPM.html)
- [JetPack 7.2.1 / R39.2.1 配布物](https://developer.nvidia.com/embedded/jetpack/downloads/archive-7.2.1)
- [R39.2.1 fTPM・互換性の注意](https://docs.nvidia.com/jetson/archives/r39.2.1/DeveloperGuide/SD/Security/FirmwareTPM.html)
- [R35.7 リリース](https://developer.nvidia.com/embedded/jetson-linux-r357)
