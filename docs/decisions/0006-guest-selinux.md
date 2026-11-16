# 0006: Ubuntu QEMUゲストのSELinux構成

日本語 | [English](../en/decisions/0006-guest-selinux.md)

状態：ユーザー承認済み。Aを選択。QEMU専用の全4フェーズのDTBに`selinux=0`を追加する。

## 観測結果

ユーザーの起動ログでLinux、OP-TEEドライバ、Ubuntuのinitまで起動した。
一方、`/etc/selinux/default/policy/policy.33`がなく、systemdがSELinuxラベルを初期化できない。
journaldとudevのソケットで`Failed to determine SELinux label: No data available`が発生した。
fTPM試験のPASSは未確認。以前追加したpolicycoreutilsでrestoreconの実行不能は解消したが、これはSELinuxポリシーの導入・ラベル整備とは別である。

| 候補 | 実装 | 利点 | 制約 |
| --- | --- | --- | --- |
| A（推奨） | QEMU専用DTBのLinux bootargsにselinux=0を追加 | カーネル・NVIDIA OP-TEE/TAを変更せず、既存rootfsとディスクを保持して試せる | ゲストのSELinuxによるアクセス制御は無効。ホストのSELinuxには影響しない |
| B | UbuntuゲストにSELinuxポリシーを導入し、ファイルラベルと各サービスのアクセス規則を整備 | ゲストでもSELinuxを運用できる | rootfs変更とラベルの永続化、OP-TEE/fTPM用規則の設計・検証が必要 |

AでもSELinuxの無効化はゲストのセキュリティ構成の変更として明記する。
TPMコマンド機能、OP-TEEのセキュア世界との分離、CAの信頼範囲とは区別する。
どちらも実装後にjournald/udevの起動とfirst/secondのPASSを実際に検証する必要がある。
既存の鍵・provisioning・NV状態を消して成功に見せる手順にはしない。

## 適用手順

QEMUが終了してから、既存ディスク・鍵・provisioningを保持して実行する。

```bash
git pull --ff-only
bash scripts/prepare-ftpm-virt-dtb.sh
bash scripts/run-ftpm-virt.sh first
```

既に初回試験がPASS済みの場合は`first`を再実行せず`second`を実行する。
DTBはinstall/へ自動配置される。QEMU・カーネル・OP-TEE・rootfsの再ビルドは不要。
Linuxログの`Kernel command line`に`selinux=0`が入ることを確認する。
初回PASS後に同じディスクで`second`を実行し、永続性を検証する。

## 検証

全4フェーズのinstall済みDTBを逆変換して起動引数を確認した。
手元の既存永続ディスクでsecondを実行し、journald/udevの起動、PTA試験、`FTPM_TEST: PASS phase=second`とpoweroffを確認した。
SELinuxラベルによるソケット作成エラーはなかった。ユーザーの新規rootfsでのfirstは別途確認が必要。
[ログ抜粋](../results/guest-selinux-excerpt.txt)と[結果](../results/guest-selinux.json)を保存した。
