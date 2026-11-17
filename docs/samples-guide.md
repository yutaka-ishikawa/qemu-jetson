# OP-TEEサンプルのビルド・実行

日本語 | [English](en/samples-guide.md)

対象は[samples/ftpm-helper-probe](../samples/ftpm-helper-probe/)。Linux側クライアントと、実際のNVIDIA helper PTAへ中継するテスト用TAをビルドする。
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
cp -a samples/ftpm-helper-probe work/sample-share/
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

## 検証状況

元のtests側probeは既存B2試験で動作確認済み。本サンプルではmakeのdry-run（TAのsubmakeを含む）、ホスト側C構文確認、文書内シェル構文確認を実施。現環境ではクロスコンパイラが利用できず、コンパイル・リンク・TA署名は未実行。
ゲスト内のapt導入・make・TA配置から実行までの新しい手順は、この開発環境では未実行。動作確認済みの手順として扱わない。
