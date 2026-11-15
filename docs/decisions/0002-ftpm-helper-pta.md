# 0002: QEMU構成のfTPM helper PTA

日本語 | [English](../en/decisions/0002-ftpm-helper-pta.md)

状態：ユーザーの判断待ち。0001で採用したB案を取り消すものではない。

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
ユーザーの選択を得るまで、どちらの実装にも着手しない。

API一覧・Linuxデーモンとの違い・REE状態の依存は[サービス比較](../optee-service-comparison.md)を参照。
