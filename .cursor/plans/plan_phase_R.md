# Phase R: ストア公開準備

> **正本の位置づけ**: 全体像・確定した設計判断・品質方針・リリース要件は [ポリゴンアプリ再設計_e54196e6.plan.md](ポリゴンアプリ再設計_e54196e6.plan.md)（マスター）を参照。技術的負債表・テスト方針・リスクと対策は [plan_future_phases.md](plan_future_phases.md) を参照。完了済みフェーズの実装済み仕様・過去の検討メモは [plan_archive_history.md](plan_archive_history.md) を参照。着手時の進捗・次ステップは下記 **現在のステータス** を参照。
> **運用**: 本ファイルは「現在着手中のフェーズ」専用ファイル。ファイル名にフェーズ名を含める（`plan_phase_<フェーズ>.md`）運用とし、Hα → Hβ → F → G → Hγ → Select → Hδ → **R** で継続（2026-08-14: `plan_phase_H_delta.md` を本ファイルへ差し替え）。R 完了時の実装完了メモ・検討メモは、差し替え時に [plan_archive_history.md](plan_archive_history.md) へ移す。Phase 完了コミット後は **現在のステータス** を次 Phase 用に更新する。

## 📍 現在のステータス (2026-08-16)

- **完了フェーズ**: Phase A〜E+・G-spike・Hα・Hβ・F・G・Hγ・Select・**Hδ** がすべて完了。Hδ の完了記録・追加 UI/UX は [plan_archive_history.md](plan_archive_history.md) の「Phase Hδ」および「検討メモ（Hδ）」を参照。
- **現在のフェーズ**: Phase R（ストア公開準備）**着手中**。
- **アプリID（確定・適用済み）**: `com.tukimibook.lowpolydraw`（Android `applicationId` / `namespace`。iOS は対象外）。変更と実機 Smoke Test（Pixel 7a 起動確認）は **完了**。
- **リリース署名（完了・AAB は保留）**: リリース用キーストア（`upload-keystore.jks`）と `android/key.properties` を配置。`android/app/build.gradle.kts` に `signingConfigs.release` を追加し `buildTypes.release` へ適用済み。鍵ファイルは `android/.gitignore` で git 管理外であることを確認したうえで、設定のみをコミット（`7515779`）。`flutter build apk --release` による署名 APK の検証は成功。**AAB の最終書き出しは、ヘルプ機能などの未実装画面がすべて完了した後に実行する（現在は保留）**。→ 検討メモ（2026-08-16）
- **保存上限（確定）**: 無料のギャラリー保存枚数はマスター記載の 10 枚から **8 枚** へ変更（実装済み）。→ 検討メモ（2026-08-16）
- **次フェーズ**: v1.1 以降（グリッド、SVG、スポイト、設定永続化、グラデ仕上げ等）。本 Phase が v1 出荷ラインの最終マイルストーン。
- **次ステップ**: 下記「着手前チェックリスト（R）」の残り（アプリ名・アイコン/スプラッシュ、バージョニング、広告本番切替、法務/UMP/ライセンス、統合 smoke）と、ヘルプ等の未実装画面を消化したうえで AAB を書き出す。

## Phase R: ストア公開準備

> **位置づけ**: Google Play へ出せる状態にする横断マイルストーン。機能芯（下絵・なぞり・テッセレーション・保存・選択/彩色・PNG エクスポート）は Hδ まで完了済み。残るのは識別子・署名・広告・法務・QA。
>
> **アプリID（確定）**: **`com.tukimibook.lowpolydraw`** — Android の `applicationId` / `namespace` として適用済み（[android/app/build.gradle.kts](android/app/build.gradle.kts)）。旧 `com.example.polygon_art_app` は廃止。iOS 側の変更は不要（Android 専業）。

### 要件（`plan_future_phases.md` から移行）

- **アプリ識別**: `applicationId` は **`com.tukimibook.lowpolydraw` に変更済み**（実機 Smoke Test 完了）。残作業はアプリ名・アイコン・スプラッシュ、バージョニング運用（`versionName` / `versionCode`）。
- **署名**: リリース用キーストア作成と署名設定は **完了**（`key.properties` / キーストアは git 管理外、鍵はコミットしない）。AAB の最終書き出しは未実装画面完了後（保留）。→ 検討メモ（2026-08-16）
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
- [x] リリース用キーストア + `key.properties`（git 管理外）（2026-08-16。`build.gradle.kts` の release 署名適用済み。AAB 書き出しは未実装画面完了後に保留）
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

### 2026-08-16: リリース署名設定完了（AAB 書き出しは保留）

リリース用キーストア（`upload-keystore.jks`、`android/app/` 配置）と `android/key.properties` を作成。`android/app/build.gradle.kts` に `key.properties` 読み込み・`signingConfigs { create("release") }`・`buildTypes.release` への適用を追記。`android/.gitignore` により `key.properties` と `*.jks` が git 管理外であることを確認したうえで、署名設定（`build.gradle.kts` のみ）をコミット（`7515779`）。検証として `flutter build apk --release` は成功（`app-release.apk`）。**AAB の最終書き出しは、ヘルプ機能などの未実装画面がすべて完了した後に実行する方針とし、現時点では保留。** チェックリストの「リリース用キーストア + key.properties」は完了。

### 2026-08-16: ギャラリー保存上限を 10 枚から 8 枚へ変更

マスター（[ポリゴンアプリ再設計_e54196e6.plan.md](ポリゴンアプリ再設計_e54196e6.plan.md)）のリリース要件は無料保存 **10 枚** だったが、v1 の初期枠を **8 枚** とする決定に変更。上限到達時はギャラリーで削除して空ける方針は維持。リワード広告による枠拡張は従来どおり後付け（`GalleryQuota.bonusSlots`）。実装は `GalleryQuota.baseSlotLimit = 8`（一次ゲート＋権威ゲート）。マスター本文は ~~10 枚~~ **8 枚** へ取り消し線訂正済み。

### 2026-08-14: アプリID 変更完了（`com.tukimibook.lowpolydraw`）

Android 専業としてパッケージ名を `com.example.polygon_art_app` から **`com.tukimibook.lowpolydraw`** へ変更。`namespace` / `applicationId`（`android/app/build.gradle.kts`）と `MainActivity.kt` のパッケージ階層を合わせて更新。`flutter clean` / `pub get` 後、debug APK ビルドおよび Pixel 7a 実機起動の Smoke Test を実施し、端末上のパッケージも同 ID で確認済み。iOS は未変更。チェックリストの当該項目は完了。

### 2026-08-14: Phase Hδ 完了、Phase R 着手（ドキュメント整理）

Hδ 完了および追加 UI/UX の記録に伴い、旧 `plan_phase_H_delta.md` を本ファイル（`plan_phase_R.md`）へ差し替え。Hδ の完了記録は [plan_archive_history.md](plan_archive_history.md) の「検討メモ（Hδ）」へ移動。R の要件は [plan_future_phases.md](plan_future_phases.md) から本ファイルへ引き込み、跡地はリンク案内のみとした。
