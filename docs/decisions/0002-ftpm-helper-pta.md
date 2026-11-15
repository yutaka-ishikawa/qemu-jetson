# 0002: QEMU構成のfTPM helper PTA

日本語 | [English](../en/decisions/0002-ftpm-helper-pta.md)

状態：B2をユーザーが承認済み。0001で採用したB案を継続する。

## 根拠

NVIDIAのfTPM TAは起動時に`FTPM_HELPER_PTA_CMD_PING_NS`を呼ぶ。
対象UUIDは`6c879517-2dfc-4663-863d-4896e8ccbe3a`。
NVIDIA OP-TEEのQEMU構成にはこのPTAが含まれない。
実際の起動でもこのUUIDのロードが`0xffff0008`（ITEM_NOT_FOUND）になった。
TAを無変更で使うため、OP-TEE側の対応範囲を決める必要がある。

| 候補 | 内容 | 利点 | 制約 |
| --- | --- | --- | --- |
| B1（推奨） | QEMU専用PTAで通常世界の起動状態通知を実装 | TAを変更せず、TPMコマンド・永続化の検証へ進める。NVIDIA側の変更を限定できる | helperの製造・証明書・プロビジョニングAPI全体は提供しない。未対応コマンドは明示的なエラーにする |
| B2 | NVIDIAのhelper PTA全体と依存機能を移植 | helper APIも含めた互換性を広く目指せる | Tegra Fuse・鍵管理・プロビジョニングへの依存があり、実装範囲が広がる。物理SEの鍵保護は別途必要 |

B1を実施する場合でも、準備完了を固定値で偽装せず、NVIDIA実装と同じREE状態に基づいて通知する。
ユーザーはPTAを重要と位置付け、B2を選択した。NVIDIAのhelper PTA全体を組み込み、QEMUの仮想Fuse・プロビジョニングデータへの接続はプラットフォーム側に実装する。
PTA本体のコマンドをPING_NSだけに縮小しない。鍵・証明書の検証データの選択は別途記録する。

API一覧・Linuxデーモンとの違い・REE状態の依存は[サービス比較](../optee-service-comparison.md)を参照。
