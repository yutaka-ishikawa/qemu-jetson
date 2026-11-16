# 0006: Ubuntu QEMUゲストのSELinux構成

日本語 | [English](../en/decisions/0006-guest-selinux.md)

状態：選択待ち。推奨A。ユーザーの決定前に実装しない。

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
