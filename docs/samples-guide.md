# OP-TEEサンプルのビルド・実行

日本語 | [English](en/samples-guide.md)

hello_world・random・secure_storage・aes・sign_verifyとftpm-helper-probeを収録する。以下の基本手順の対象は[samples/ftpm-helper-probe](../samples/ftpm-helper-probe/)。Linux側クライアントと、実際のNVIDIA helper PTAへ中継するテスト用TAをビルドする。
実装元はtests/ftpm-helper-probeのコピーで、PTA本体の代替ではない。
本書のホスト側クロスビルドとゲスト内ビルドは選択肢。同じサンプルを両方でビルドする必要はない。

## ホスト側でクロスビルドする場合

[build-install.md](build-install.md)のfirmware・clientビルドとvenv/CROSS_COMPILE設定を済ませ、リポジトリ直下で実行する。

```bash
make -C samples/ftpm-helper-probe
```

既定出力はwork/samples/ftpm-helper-probe/ftpm-helper-probeと、そのta/以下の7fc1d460-5a6c-4a5f-9b9e-6c298d3032a0.ta。
配置済みinstall/include、install/lib/aarch64-linux-gnu、install/lib/optee/ta-dev-kit-aarch64を使う。
INSTALL_DIR、TA_DEV_KIT_DIR、TA_SIGN_KEY、Oはmake変数で変更可能。
既定のTA_SIGN_KEYはリポジトリ同梱の公開された開発用秘密鍵。製品用の秘密鍵ではない。

## QEMU内でmakeして実行する場合

### 1. ホスト：共有用ディレクトリを用意

上記クロスビルドは不要。ただしホストでfirmware・clientをビルド・配置済みであること。
[通常起動ガイド](runtime-guide.md)に従いcradsecアカウントとsudoを設定済みとする。
ホストでリポジトリ直下から、初回に次を実行する。共有用ディレクトリが既にある場合、重ねて実行する前に内容を確認する。

```bash
mkdir -p work/sample-share/sdk/lib
cp -a samples/. work/sample-share/
cp -a install/include work/sample-share/sdk/
cp -a install/lib/aarch64-linux-gnu work/sample-share/sdk/lib/
mkdir -p work/sample-share/sdk/lib/optee
cp -a install/lib/optee/ta-dev-kit-aarch64 work/sample-share/sdk/lib/optee/
cp optee/optee/optee_os/keys/default_ta.pem work/sample-share/default_ta.pem
chmod -R a+rX work/sample-share
bash scripts/run-ftpm-virt.sh --ssh --share "$PWD/work/sample-share"
```

リポジトリ全体を共有せず、ソース・SDK・公開された開発用TA署名鍵だけを共有する。
CA秘密鍵・Firmware ID秘密鍵・仮想デバイスID・provisioning・ディスクはコピーしない。
独自のTA署名鍵でOP-TEEを構築している場合は、対応する開発用鍵を手元で指定する。

### 2. ゲスト：共有を手動マウントし、ビルド環境を準備

QEMUコンソールまたはSSHでcradsecとしてログインして実行する。
共有は読み取り専用のため、ホームへコピーしてビルドする。aptにはゲストからのインターネット接続が必要。

```bash
sudo qemu-mount-host
sudo apt-get update
sudo apt-get install -y build-essential python3 python3-cryptography python3-pycryptodome python3-pyelftools
mkdir -p "$HOME/optee-samples"
cp -a --no-preserve=ownership /mnt/host/. "$HOME/optee-samples/"
cd "$HOME/optee-samples"
make -C ftpm-helper-probe CROSS_COMPILE= INSTALL_DIR="$PWD/sdk" TA_SIGN_KEY="$PWD/default_ta.pem" O="$PWD/build"
```

ゲストはARM64なのでCROSS_COMPILEを空にしてネイティブgccを使う。
通常ユーザーでmakeし、出力は~/optee-samples/build/へ保存する。sudo makeは不要。
SDK・libteec・ゲストで動くOP-TEEは同じ構成のものを使う。

### 3. ゲスト：TAを配置し、クライアントを実行

通常起動モードで行い、同じprobeを自動試験と並行実行しない。
このTAは既存のテスト用relay TAと同じUUIDを持つため、配置先に既存TAがあれば同じテスト用TAを置き換える。

```bash
cd "$HOME/optee-samples"
sudo install -m 0644 build/ta/7fc1d460-5a6c-4a5f-9b9e-6c298d3032a0.ta /usr/lib/optee_armtz/
mkdir -p run
cd run
LD_LIBRARY_PATH="$HOME/optee-samples/sdk/lib/aarch64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ../build/ftpm-helper-probe
```

tee-supplicantの検索先/lib/optee_armtzはUbuntuのusr-mergeにより/usr/lib/optee_armtzと同じ場所。
必要なTAファイル配置だけsudoを使い、クライアントはcradsecで実行する。
PTA_TESTのPASS表示と終了コード0を確認する。証明書・CSR・署名等がrun/へ出力される。
このprobe単体では証明書チェーンや署名の暗号学的検証までは実施しない。
これらを含む既存の全機能試験は[test-guide.md](test-guide.md)を参照。
TA読込みエラーの場合は、UUID、配置先、OP-TEEが受け入れるTA署名鍵、tee-supplicantの状態を確認する。

## 追加した5サンプル（B案）

取得元は[optee_examples](https://github.com/linaro-swg/optee_examples/tree/71e8f3f320eef46a9369700bf30b91d67427d535)、固定コミットは71e8f3f320eef46a9369700bf30b91d67427d535。
ライセンスと著作権表示を保持した。[取得元・ハッシュ一覧](../samples/optee-examples-source.json)と[ライセンス](../samples/LICENSE.optee_examples)を参照。
各サンプル最上位のMakefileを調整し、原本はMakefile.upstreamとして保存。他の取り込みファイルは無変更。

ホストではCROSS_COMPILEを設定済みのシェルで、全サンプルをまとめてビルドできる。

```bash
make -C samples
```

5サンプルだけを選ぶ場合は、上記に代えて次を実行する。

```bash
make -C samples hello_world random secure_storage aes sign_verify
```

個別には`make -C samples/hello_world`も利用可能。出力は既定でwork/samples/サンプル名/以下。
引数なしの一括makeにはftpm-helper-probeも含む。

ゲスト内でビルドする場合は、前述の共有準備・マウント・依存パッケージ導入・ホームへのコピーを済ませる。
共有準備のコマンドはsamples全体をコピーするよう更新済み。古い共有がある場合はQEMU停止中にソースを更新し、ゲストへ再コピーする。
ゲストでcradsecとして次を実行する。

```bash
cd "$HOME/optee-samples"
make hello_world random secure_storage aes sign_verify CROSS_COMPILE= INSTALL_DIR="$PWD/sdk" TA_SIGN_KEY="$PWD/default_ta.pem" O="$PWD/build-all"
```

5つのTAを配置し、対応するlibteecでクライアントを実行する。

```bash
cd "$HOME/optee-samples"
for name in hello_world random secure_storage aes sign_verify; do
    sudo install -m 0644 build-all/"$name"/ta/*.ta /usr/lib/optee_armtz/
done
export LD_LIBRARY_PATH="$HOME/optee-samples/sdk/lib/aarch64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
./build-all/hello_world/optee_example_hello_world
./build-all/random/optee_example_random
./build-all/secure_storage/optee_example_secure_storage
./build-all/aes/optee_example_aes
./build-all/sign_verify/optee_example_sign_verify
```

| サンプル | 確認点 |
| --- | --- |
| hello_world | TAが42を43へ増加させる |
| random | TAが生成した乱数値を表示する |
| secure_storage | オブジェクトの書込み・読出し・削除。object2は実行ごとに作成と削除が切り替わる |
| aes | 既定のCTR暗号化・復号で`Clear text and decoded text match`を表示。ERRORや不一致表示がない |
| sign_verify | `Sign and verify successful`を表示 |

各コマンドの終了コードとエラーを確認してから次へ進む。fTPM試験のPASSマーカーは使わない。
永続化を確認する場合はsecure_storageを1回実行し、正常電源断後に同じディスクで起動して再実行する。
変更するのはサンプル自身のTAストレージであり、fTPM NVではない。object2は実行ごとに状態が切り替わるため、開始時の状態も記録する。
AESの既定鍵・IVは公開されたテスト値であり、実データの保護には使わない。
5サンプルは一般のOP-TEE APIを使い、NVIDIA helperやTPMコマンドの検証とは別。現在のREEストレージはホストによるロールバックへの耐性を提供しない。

## 検証状況

元のtests側probeは既存B2試験で動作確認済み。本サンプルではmakeのdry-run（TAのsubmakeを含む）、ホスト側C構文確認、文書内シェル構文確認を実施。現環境ではクロスコンパイラが利用できず、コンパイル・リンク・TA署名は未実行。
ゲスト内のapt導入・make・TA配置から実行までの新しい手順は、この開発環境では未実行。動作確認済みの手順として扱わない。

追加5サンプルもmakeのdry-runとホスト側クライアントC構文確認まで。ARM64実ビルド・TA署名・QEMU実行は未検証。
