# 同梱ソースとビルド構成

日本語 | [English](en/source-layout.md)

## ソース配置

- `qemu/`：公式QEMU 11.1.3のリリースソース。直接この配下を修正する。別Gitリポジトリやsubmoduleではない。
- `optee/`：NVIDIA R36.5.2のOP-TEEパッケージ。内包ディレクトリ構成を維持する。
- `kernel/`：NVIDIA R36.5.2のkernel_srcパッケージ。カーネル本体は `kernel/kernel/kernel-jammy-src/`。
- `work/`：ビルド、ダウンロード、rootfs、実行時状態。Git管理外。

取得元、ハッシュ、QEMUの基準コミットは [source-baselines.json](../manifests/source-baselines.json) に記録。
上流の全Git履歴は取り込まず、配布版のスナップショットから本プロジェクトの変更を記録する。
QEMUのリリースアーカイブにはROM関連ソースやテスト用データも含まれ、展開後約899MiB。
カーネルソースは約1.3GiB。生成されたビルド成果物はコミットしない。
NVIDIAの別配布Out-of-treeモジュールやディスプレイドライバは今回のkernel_src取り込みに含めていない。

## 別条件のNVIDIA部品

OP-TEEのCCCヘッダ・暗号ライブラリ、一部ビルドヘルパーや文書には、BSD系コードとは別の条件が記載されている。
これらを公開Gitへ一括転載せず、公式アーカイブから利用者の作業ツリーに復元する。
対象リストは [optee-excluded-files.json](../manifests/optee-excluded-files.json)。
加えて `kernel/nvcommon_build.sh` も同様に扱う。元のLICENSE類は同梱し、条件を保持する。

公式配布物の取得から復元まで自動で行う場合は `scripts/fetch-nvidia-components.sh` を実行する。
既に内包アーカイブを持っている場合は次の方法も使える。

```bash
scripts/restore-nvidia-components.py \
  /path/to/nvidia-jetson-optee-source.tbz2 \
  /path/to/kernel_src.tbz2
```

両アーカイブはNVIDIA公式R36.5.2のpublic_sources.tbz2内の `Linux_for_Tegra/source/` にある。
復元スクリプトはSHA-256を検証し、対象ファイルだけを取り出す。異なる既存ファイルは上書きしない。
復元部品は.gitignore対象なので、公開ソースと混同してpushしない。
したがって、初回cloneだけでNVIDIAのT234公式ビルド入力がすべて揃うという意味ではない。

## QEMUビルド

ソースを再cloneする必要はない。ビルドディレクトリを分離する。
LinuxホストのGCC、Make、Python、venv、Ninja、pkg-config、GLib開発パッケージ等が必要。
実際のconfigureで不足依存を確認する。

```bash
mkdir -p work/qemu-build
cd work/qemu-build
../../qemu/configure --target-list=aarch64-softmmu \
  --without-default-features --disable-werror --disable-docs
ninja -j2 qemu-system-aarch64
./qemu-system-aarch64 --version
```

これはAArch64 system emulationの最小機能ビルド。まだ専用Jetsonマシンの起動手順は別途必要であり、
このビルドだけではNVIDIA版OP-TEEの起動に必要なファームウェア等は揃わない。

## OP-TEEとLinux

OP-TEEの既存手順は[ビルド記録](r36.5.2-build.md)を参照し、ソース作業先を同梱 `optee/` に置き換える。
ツールチェーン、StMM、復元対象の部品は別途用意する。
Linuxのrootfs連携設定は [optee-ftpm.config](../configs/kernel/optee-ftpm.config) と
[Ubuntu rootfs手順](ubuntu-rootfs.md)を基準にする。
カーネル設定・DT・モジュールのビルドとQEMU上での実行試験は今後の段階で行う。

## 取り込み検証

2026-11-16（日本時間）：QEMU 78,773件、kernel_src 73,920件、OP-TEE 4,209件の
配布ファイル／シンボリックリンクがGitの追跡対象に揃っていることを確認した。
上記件数は別条件で除外したファイルを含まない。ファイル名はすべてASCII。
復元対象7件は追跡されていないことを確認した。

`scripts/build-qemu.sh`はホスト上で同梱ソースを直接ビルドする。出力先は`work/qemu-build/`。[ホスト環境の準備](native-host.md)を参照。

`QEMU_BUILD_DIR=/absolute/path`でビルド先を変更できる。システムへのQEMUのinstallは行わない。
既存の同名イメージは通常再利用する。基準試験スクリプトは `scripts/check-qemu-baseline.py`。

## QEMU基準試験結果

2026-11-16（日本時間）：同梱QEMU 11.1.3のAArch64 system emulatorをビルドし、
`scripts/build-qemu.sh` が終了コード0で完了した。
Ubuntu 22.04のビルド用コンテナと、上記の最小機能構成を使用。

`scripts/check-qemu-baseline.py` で以下を確認した。

- `virt,secure=on`、TCG、`max` CPU、1コア、128MiB RAMで起動できる。
- QMPのcapabilities、query-status、CPUモデル照会、quitがエラーなく応答する。
- 停止状態はprelaunchで、CPUモデルの `pauth` がtrue。
- プロセスが正常終了する。

これは**QEMU本体の基準試験のみ**。ファームウェア、Linux、OP-TEE、TPMを起動していない。
この基準試験時点では専用T234マシン、TCU、EL3起動コードは未実装だった。
その後の実装と試験は[段階Aの記録](t234-stage-a.md)を参照。
ソース取り込み時点のGitパックは手元で約387MiB。ビルド用には追加の空き容量が必要。
この作業環境は約8GiBの上限があるため、検証済みrootfsの再生成可能なtarとDockerビルドキャッシュを整理した。
ソース、Git履歴、OP-TEEの圧縮済みビルド基準資料は保持している。

現在の読み取り専用Fuseモデルの範囲と試験結果は[t234-fuse.md](t234-fuse.md)を参照。
