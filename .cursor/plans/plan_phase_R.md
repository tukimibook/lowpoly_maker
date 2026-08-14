# Phase R: ストア公開準備

> **正本の位置づけ**: 全体像・確定した設計判断・品質方針・リリース要件は [ポリゴンアプリ再設計_e54196e6.plan.md](ポリゴンアプリ再設計_e54196e6.plan.md)（マスター）を参照。技術的負債表・テスト方針・リスクと対策は [plan_future_phases.md](plan_future_phases.md) を参照。完了済みフェーズの実装済み仕様・過去の検討メモは [plan_archive_history.md](plan_archive_history.md) を参照。着手時の進捗・次ステップは下記 **現在のステータス** を参照。
> **運用**: 本ファイルは「現在着手中のフェーズ」専用ファイル。ファイル名にフェーズ名を含める（`plan_phase_<フェーズ>.md`）運用とし、Hα → Hβ → F → G → Hγ → Select → Hδ → **R** で継続（2026-08-14: `plan_phase_H_delta.md` を本ファイルへ差し替え）。R 完了時の実装完了メモ・検討メモは、差し替え時に [plan_archive_history.md](plan_archive_history.md) へ移す。Phase 完了コミット後は **現在のステータス** を次 Phase 用に更新する。

## 📍 現在のステータス (2026-08-14)

- **完了フェーズ**: Phase A〜E+・G-spike・Hα・Hβ・F・G・Hγ・Select・**Hδ** がすべて完了。Hδ の完了記録・追加 UI/UX は [plan_archive_history.md](plan_archive_history.md) の「Phase Hδ」および「検討メモ（Hδ）」を参照。
- **現在のフェーズ**: Phase R（ストア公開準備）**着手中**。
- **アプリID（確定・適用済み）**: `com.tukimibook.lowpolydraw`（Android `applicationId` / `namespace`。iOS は対象外）。変更と実機 Smoke Test（Pixel 7a 起動確認）は **完了**。
- **次フェーズ**: v1.1 以降（グリッド、SVG、スポイト、設定永続化、グラデ仕上げ等）。本 Phase が v1 出荷ラインの最終マイルストーン。
- **次ステップ**: 下記「着手前チェックリスト（R）」の残りを消化する。次の実作業候補はリリース署名の土台（キーストア / `key.properties`）。

## Phase R: ストア公開準備

> **位置づけ**: Google Play へ出せる状態にする横断マイルストーン。機能芯（下絵・なぞり・テッセレーション・保存・選択/彩色・PNG エクスポート）は Hδ まで完了済み。残るのは識別子・署名・広告・法務・QA。
>
> **アプリID（確定）**: **`com.tukimibook.lowpolydraw`** — Android の `applicationId` / `namespace` として適用済み（[android/app/build.gradle.kts](android/app/build.gradle.kts)）。旧 `com.example.polygon_art_app` は廃止。iOS 側の変更は不要（Android 専業）。

### 要件（`plan_future_phases.md` から移行）

- **アプリ識別**: `applicationId` は **`com.tukimibook.lowpolydraw` に変更済み**（実機 Smoke Test 完了）。残作業はアプリ名・アイコン・スプラッシュ、バージョニング運用（`versionName` / `versionCode`）。
- **署名**: リリース用キーストア作成と署名設定（`key.properties` は git 管理外、鍵はコミットしない。現在は release がデバッグ鍵のまま）。
- **準拠**: Play のターゲット API レベル方針に準拠。
- **広告**: AdMob バナー実装（ホーム/ギャラリー、テスト↔本番 ID 切替）。キャンバス上には出さない。リワード解放フックは後付け可（エンタイトルメント継ぎ目は v1 で用意する方針はマスターのリリース要件どおり）。
- **法務/プライバシー**: プライバシーポリシー公開＋Play「データ安全」申告、Google UMP 同意フォーム、一般向け(13+)設定、OSS ライセンス表示（`showLicensePage`）。
- **QA**: ユニット/ゴールデン（任意）テスト、実機マトリクス確認、空/権限拒否/失敗系（#19）。**統合 smoke フル実行（U2）** を公開前ゲートとする。

### 完了条件

- Play にアップロード可能な `applicationId`・リリース署名・アイコン/スプラッシュ/バージョニングが揃う。
- ホーム/ギャラリーに AdMob バナー（開発はテスト ID）。キャンバスには出ない。
- プライバシーポリシー・データ安全申告・UMP・ライセンス表示の最低ラインを満たす。
- 統合 smoke（[plan_future_phases.md](plan_future_phases.md) の 1〜7）を 1 端末で通し、失敗系でクラッシュしない（#19 / U4）。
- `flutter analyze` / `flutter test` パス。

### アーキテクチャ上の境界（実装時）

- 広告 SDK はホーム/ギャラリーに閉じ、エディタの描画経路（`PolygonPainter` / `ArtworkPngRenderer`）に混ぜない。
- 署名・鍵ファイルをリポジトリに入れない。
- 既存の保存・エクスポート・権限 UX（Hγ / Hδ）を壊さない。QA は回帰として smoke を回す。

## 着手前チェックリスト（R）

- [x] `applicationId` を公開可能な独自 ID へ変更 → **`com.tukimibook.lowpolydraw`**（2026-08-14、実機 Smoke Test 完了）
- [ ] リリース用キーストア + `key.properties`（git 管理外）
- [ ] アプリ名・ランチャーアイコン・スプラッシュ
- [ ] `versionName` / `versionCode` 運用の確定
- [ ] Play ターゲット API 方針への準拠確認
- [ ] AdMob バナー（ホーム/ギャラリー、テスト ID）
- [ ] プライバシーポリシー公開 + Play「データ安全」申告
- [ ] Google UMP 同意フォーム、対象年齢 13+
- [ ] OSS ライセンス表示（`showLicensePage`）
- [ ] 統合 smoke **フル実行**（U2）
- [ ] 失敗系（#19）の手動確認（権限拒否・破損 JSON・エクスポート失敗）

→ 技術的負債表・統合 smoke 本文は [plan_future_phases.md](plan_future_phases.md) を参照。

## 追加すべきテスト（R 関連）

- 統合 smoke 1〜7 の手動記録（Pass/Fail）
- バナーがエディタキャンバスに出ないこと（実機）
- 権限拒否・破損 JSON でクラッシュしないこと（#19）

## リスクと対策（R）

1. **公開不可設定** — `com.example.*` のままでは Play に出せない。**解消済み**: `applicationId` は `com.tukimibook.lowpolydraw`。
2. **鍵の漏洩** — キーストア / `key.properties` をコミットしない。
3. **広告と描画の混線** — バナーをキャンバスに置かない（マスターのリリース要件）。
4. **統合 QA の爆発** — U2 を公開前ゲートにし、Hδ までの機能回帰は既存 `flutter test` + smoke でカバー。

## 検討メモ（直近）

### 2026-08-14: アプリID 変更完了（`com.tukimibook.lowpolydraw`）

Android 専業としてパッケージ名を `com.example.polygon_art_app` から **`com.tukimibook.lowpolydraw`** へ変更。`namespace` / `applicationId`（`android/app/build.gradle.kts`）と `MainActivity.kt` のパッケージ階層を合わせて更新。`flutter clean` / `pub get` 後、debug APK ビルドおよび Pixel 7a 実機起動の Smoke Test を実施し、端末上のパッケージも同 ID で確認済み。iOS は未変更。チェックリストの当該項目は完了。

### 2026-08-14: Phase Hδ 完了、Phase R 着手（ドキュメント整理）

Hδ 完了および追加 UI/UX の記録に伴い、旧 `plan_phase_H_delta.md` を本ファイル（`plan_phase_R.md`）へ差し替え。Hδ の完了記録は [plan_archive_history.md](plan_archive_history.md) の「検討メモ（Hδ）」へ移動。R の要件は [plan_future_phases.md](plan_future_phases.md) から本ファイルへ引き込み、跡地はリンク案内のみとした。
