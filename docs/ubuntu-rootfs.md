# Ubuntu 22.04 ARM64 rootfs

日本語 | [English](en/ubuntu-rootfs.md)

## 採用構成

ユーザーランドはUbuntu 22.04 ARM64とし、NVIDIAのSample Root Filesystem全体を前提にしない。
公式Ubuntu Base 22.04.5を固定入力にし、Ubuntuのjammy／updates／securityから必要なパッケージを導入する。
OP-TEE clientはNVIDIA R36.5.2でビルドしたものを使う。fTPMとHelper TAはSecure WorldのEarly TAであり、Ubuntuパッケージではない。

- `tee-supplicant`、`libteec.so.2`、`nvftpm-helper-app`を既存のOP-TEE installディレクトリから取り込む。
- Ubuntuからsystemd、udev、kmod、tpm2-tools、device TCTIライブラリ、OpenSSL等を導入する。
- `/data/tee`をREE FS保存先とする。仮想デバイスごとに保持する必要がある。
- fTPM driverはLinuxカーネルの `CONFIG_TCG_FTPM_TEE`。ユーザーランド側のサービスとは別に用意する。

rootfs、ダウンロード、ビルドコンテキストは `work/` 以下でGit管理外。
QEMU／OP-TEE／Linuxのソースはその後同梱した。[ソース配置](source-layout.md)を参照。

## ビルド

ホストにDocker、Bash、curl、sha256sum、readelf、tarが必要。
PRootとQEMUユーザーモードをビルドコンテナ内で使うため、ホストへのbinfmt登録や特権コンテナは不要。

```bash
scripts/fetch-ubuntu-base.sh
scripts/build-ubuntu-rootfs.sh \
  /workspace/work/nvidia-r36.5.2/optee/optee/install/t234 \
  work/ubuntu-jammy-arm64-rootfs.tar
```

OP-TEEのinstallパスは自分のビルド先に置き換える。
既存の出力tarは上書きしない。Dockerイメージ `qemu-jetson-rootfs:jammy` とrootfs tarを生成する。
最終イメージにはビルド用のPRoot／QEMUを含めない。
取得時は [固定SHA-256](../manifests/ubuntu-base-22.04.5-arm64.sha256) を検証する。
公式チェックサムは https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/SHA256SUMS 。
Ubuntuの署名検証を別途実施したという意味ではない。
APTパッケージは構築時点の更新を導入し、版を `/usr/share/qemu-jetson/packages.tsv` に保存する。
APTリポジトリとビルド用Ubuntuイメージはスナップショット固定していないため、ビット単位の再現性は保証しない。

## カーネルと起動の前提

[設定フラグメント](../configs/kernel/optee-ftpm.config)を対象カーネル設定にマージし、olddefconfig後の値を確認する。
これは完全なJetson／QEMU用defconfigではない。CPU、割り込み、ストレージ、コンソール、ネットワークの設定は別途必要。
`CONFIG_TCG_FTPM_TEE=m` の対応モジュールはrootfsの `/lib/modules/<kernel-release>/` に導入し、depmodを実行する。
起動時はmodules-load設定により `tpm_ftpm_tee` をロードする。
OP-TEE driverのDTノードとSMC経路、Secure WorldのfTPM TAが動作している必要がある。

`jetson-tee-supplicant.service`はforegroundで起動し、失敗時は再試行する。
TAロード先は `/lib/optee_armtz`。今回のfTPMとHelper TAは組み込み済みなので外部TAを重複配置しない。
rootfs構築ではTAのプロビジョニングやTPMクリアを実行しない。

出力tarはまだ起動可能なディスクイメージではない。
root所有権・パーミッションを保持してext4等へ展開し、カーネル、root=、init=/sbin/init、コンソールを起動構成に設定する段階が別途必要。
デフォルトのQEMU user networking用DNSは `10.0.2.3`。ネットワーク構成を変える場合は修正する。
ログイン用の既定パスワードやSSHサービスは追加していない。

## ゲストでの確認

ゲストrootで以下を実行する。読み取りのみのTPM問い合わせを行う。

```bash
/usr/local/sbin/check-ftpm-guest.sh
```

Ubuntu／CPU、`/dev/teepriv0`、supplicantサービス、`/dev/tpmrm0`を確認してから、
`tpm2_getcap properties-fixed`と`tpm2_pcrread sha256:0`を実行する。
これだけでNV永続化、seal／unseal、Fuse由来の同一性、証明書の同等性が確認できるわけではない。

## 検証状況

取得・構築・実行の結果は本書末尾に記録する。rootfs内のユーザーランド実行試験と、
QEMU system emulationでのOP-TEE／TPM試験は区別する。

2026-11-16（日本時間）：Docker／PRoot／QEMUユーザーモードによる構築が終了コード0で成功。
Ubuntu 22.04.5 LTS ARM64、NVIDIA版 `tee-supplicant --help` と `tpm2_getcap --version`（5.2）を確認。
出力tar内のARM64 ELF、libteec、ゲスト確認スクリプト、サービスの有効化リンク、
`/data/tee`の0700権限、ビルド用QEMUが含まれないことを検証した。
Bash構文と文書の相対リンクも確認した。

- rootfs tarサイズ：272,271,872バイト（約260 MiB）。
- 今回のrootfs SHA-256：`00daf6ca3c24e0eaf4264d722cda81da5659b1debb18b9eb43b2898b3fddd803`。
- rootfs内supplicantのSHA-256は既存の無変更ビルド記録と一致。
- systemdの実際の起動、カーネルモジュール、OP-TEE接続、TPMへの問い合わせは未検証。
