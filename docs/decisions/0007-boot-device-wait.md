# 0007: 起動時のudev・ttyAMA0待ち

日本語 | [English](../en/decisions/0007-boot-device-wait.md)

状態：調査済みの範囲と候補を記録。永続的な高速化変更は未実装。推奨A。

## 確認した原因と未確定の範囲

表示はLinuxカーネルの停止ではなく、systemdの起動ジョブの進行表示。
`/dev/ttyAMA0`はserial-gettyが依存するdevice unitのudev登録待ち。
カーネルは約0.2秒でPL011/ttyAMA0を認識しており、物理的なUART出現を90秒待っているわけではない。
`1min 30s`はdevice jobの待機上限で、毎回90秒待つ指定ではない。
`Coldplug All udev Devices`はsystemd-udev-trigger.serviceの処理中を表す。

実ディスク内のunitを読んだ結果、subsystemsとdevicesへの`udevadm trigger --action=add`を順に実行する。
このunitはBefore=sysinit.targetを持つため、終了まで基本サービス・試験の開始が遅れる。
B2のsupplicantはfTPMのドライバprobeに備え、このtriggerより前に起動する設計。

通常ログではcoldplug終了が起動約20秒台、その後にdevice unitが登録される。
診断用のsystemd debug起動でも同順序を確認し、second試験はPASSした。
起動スクリプトはソフトウェアエミュレーション、仮想CPU1個であり、ユーザーランドの大量のcoldplug処理は時間を要し得る。
ただし、遅延の内訳（個々のudevルール・プロセス・sysfs操作・CPU時間）は未計測で、原因を特定のルールや単なるCPU不足と断定しない。
ページテーブルpanicやSELinuxのソケット作成失敗とは異なる事象。

## 候補

| 候補 | 内容 | 利点 | 制約 |
| --- | --- | --- | --- |
| A（推奨） | 通常Ubuntuサービスとudevを維持し、トリガー/ルールごとの処理時間を測定して不要な負荷や並列数を調整 | 現在のサービス動作とTPM試験を保ちながら改善を評価できる | 追加計測が必要で、短縮量は未確定 |
| B | fTPM試験専用の最小起動プロファイルを別途設計し、不要なログイン・デバイス処理を限定 | 試験専用環境の高速化余地 | 起動対象・デバイス自動検出が通常Ubuntuと異なる。ttyの待ちだけを除去してもcoldplug全体は解消しない |

タイムアウト短縮、systemd.show_statusの非表示化は原因解消ではない。
udevを一律に無効化するとTPMデバイスの認識・アクセス設定にも影響するため実施しない。
A/Bいずれの永続変更も、必要な範囲と影響を確認し、second/boundの再試験で評価する。

[通常のビルド](../build-install.md)と[試験](../test-guide.md)は変更していない。

ユーザー判断：起動待ちは現状維持。専用の高速化変更は行わない。後続のCPU既定4への変更は別要件によるもの。
