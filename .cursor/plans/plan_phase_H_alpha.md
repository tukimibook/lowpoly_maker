# Phase Hα: 下絵（背景画像）（現在着手中）

> **正本の位置づけ**: 全体像・確定した設計判断・品質方針・リリース要件は [ポリゴンアプリ再設計_e54196e6.plan.md](ポリゴンアプリ再設計_e54196e6.plan.md)（マスター）を参照。完了済み/未着手の他フェーズ詳細・技術的負債表・過去（2026-07-10〜07-15）の検討メモは [plan_future_phases.md](plan_future_phases.md) を参照。着手時の進捗・次ステップは下記 **現在のステータス** を参照。
> **運用**: 本ファイルは「現在着手中のフェーズ」専用ファイル。ファイル名にフェーズ名を含める（`plan_phase_<フェーズ>.md`）運用とし、Hα が完了し次のフェーズ（Hβ）に進んだら、本ファイルの中身を Hβ の詳細（[plan_future_phases.md](plan_future_phases.md) から該当セクションを移動）に差し替え、ファイル名も `plan_phase_H_beta.md` にリネームして使い続ける（G-spike → Hα でこの運用に切り替え済み）。Hα 完了時の実装完了メモ・検討メモは、差し替え時に [plan_future_phases.md](plan_future_phases.md) の検討メモアーカイブへ移す。Phase 完了コミット後は **現在のステータス** を次 Phase 用に更新する。

## 📍 現在のステータス (2026-07-16)
- **完了フェーズ**: Phase G-spike が大成功で完了（無限ループのバグの種もジッター付与で事前解決済み、本番実装は Tier B に確定）。
- **現在のフェーズ**: Phase Hα（下絵インポート・キャンバス準備）に着手中。実機での表示自体には成功したが、特定のJPEG（過去に画像処理を経た少し特殊なもの）で下1/3が黒く表示されるバグを検出・修正した（下記「2026-07-16」検討メモ参照）。

## Phase Hα: 下絵（背景画像）

> G より先に実装（v1 の芯）。保存（Hγ）と同時リリース — セッションのみの下絵は不可。→ 検討メモ（2026-07-13・追記続き3、[plan_future_phases.md](plan_future_phases.md)）参照。

- `image_picker` でギャラリーから選択。`UnderlayLayout`（画像参照 + world rect + opacity）を独立モデルに。`Artwork` 本体とは分離し、保存時は Hγ で JSON に含める。
- **取り込み時に上限解像度（`maxWidth: 1920` / `maxHeight: 1080`、2026-07-16改訂）へダウンサンプリング（＝標準化）してから保持・表示する**（#18）。理由: 端末カメラの写真は4K以上の高解像度が普通で、そのままメモリ上に展開するとデコード時点でネイティブメモリを圧迫し、OOM（メモリ不足）でクラッシュするため。加えて、`maxWidth`/`maxHeight` 指定はプラットフォーム側でのリサイズ＋標準JPEG形式への再エンコードも兼ねるため、非標準的な形式のJPEGに対するデコード失敗（下記「2026-07-16」検討メモ参照）の回避にも寄与する。`image_picker` の `maxWidth`/`maxHeight` 指定で実現（アプリ内コピーとして再保存はしない）。
- `PolygonPainter` とは別の `CustomPaint`（`UnderlayPainter`）として、viewport 変換**内側**（world 固定）に下絵を描画。ポリゴンより背面、両方を個別の `RepaintBoundary` で分離。
- 透過: スライダーではなく「20/40/60/80/100%」の5段階ボタン（`SegmentedButton`）。表示 ON/OFF トグル（`SwitchListTile`）。いずれもタップのみで完結する `showModalBottomSheet`（AppBar の「下絵設定」ボタンから開く）に格納 — スワイプ操作によるOSジェスチャー誤爆を避けるため（2026-07-15 決定、下記検討メモ参照）。
- v1 は**キャンバスへのフィット固定**（拡大・回転・自由配置は見送り）。下絵の配置（`offset`/`scale`）は `fitUnderlayToCanvas` が画像インポート時・キャンバスリサイズ時にのみ算出し、`Artwork` の Undo スタックの対象外（幾何ではなく表示状態のため）。
- スポイト（色取得）は v1.1。

### 画像読み込みの仕様（v1 スコープ、2026-07-15 確定）

- **v1 の実装**: `image_picker` でギャラリーから選択した画像を、選択したままの向き（0度扱い、EXIF回転の解釈以上の加工はしない）で取り込む。OOM対策・形式標準化として `ImagePicker().pickImage(maxWidth: 1920, maxHeight: 1080)` を指定し、デコード前にネイティブ側でダウンサンプリング＋標準JPEGへの再エンコードを行う（#18 の実装方式として確定、2026-07-16に2048×2048正方から1920×1080へ改訂 — 詳細は下記「2026-07-16」検討メモ参照）。
- **v1.1 以降へ見送り**: アプリ内での画像の回転・反転、および `image_cropper` 等のUI付き切り抜きプラグインの導入。取り込んだ写真の向き・切り出しを変えたい場合は、ユーザーが端末側のギャラリーで編集してから選び直す運用とする。
- **iOS の Info.plist（`NSPhotoLibraryUsageDescription`）**: 本リポジトリには `ios/` プラットフォームが未追加（Google Play / Android のみを対象とした計画のため）。iOS 対応が将来必要になった際に `flutter create --platforms=ios .` で追加してから設定する。今回はスコープ外（ユーザー確認済み）。

~~**完了条件**: 写真を透過下絵として載せ、その上に描画できる。実機確認済み。~~
~~**完了条件**: 写真を透過下絵として載せ、その上に描画できる。**高解像度写真（4K級）を取り込んでもクラッシュしない**。実機確認済み。~~
**完了条件**: 写真を透過下絵として載せ、その上に描画できる。**高解像度写真（4K級）を取り込んでもクラッシュせず、特殊な形式のJPEGでも正しく表示される**（下1/3が黒くなる等の描画破綻がない）。実機での基本表示は確認済みだが、本項目（特殊JPEGでの黒帯バグ修正）自体の実機再確認はこれから — 下記「2026-07-16」検討メモ参照。

## 着手前チェックリスト（Hα）

**Hα の前**

- [x] 画像取込時のダウンサンプリング方式（上限解像度・リサイズタイミング）を決定（#18）— `image_picker` の `maxWidth: 1920`/`maxHeight: 1080` によるネイティブ側ダウンサンプリング＋形式標準化（2026-07-16改訂）。詳細は下記検討メモ・本ファイル「画像読み込みの仕様」参照。
- [x] `UnderlayLayout` の実装とキャンバスへの描画・操作（v1: フィット固定＋不透明度/表示切替のみ、自由配置とUndo対象化は見送り）— 詳細は下記検討メモ「2026-07-15: UnderlayLayout の実装」参照。

→ その他フェーズの着手前チェックリストは [plan_future_phases.md](plan_future_phases.md) の「コード品質・修正前提」節を参照。

## 追加すべきテスト（Hα関連）

[plan_future_phases.md](plan_future_phases.md) の「追加すべきテスト（優先度付き）」全体のうち、Hα に直接関連する項目のみ抜粋（全項目は同ファイルを参照）:

- 画像ダウンサンプリング関数が上限解像度に収まる出力を返すこと（#18）
- `fitUnderlayToCanvas` が画像/キャンバスの縦横比に応じて正しくフィットする（contain-fit・中央寄せ・縦横どちらが基準辺になるケースも）こと（実施済み）
- `UnderlayLayout`（`copyWith`/`toMap`/`fromMap`/`worldToLocal`）の単体テスト（実施済み）
- 下絵設定ボトムシート（表示ON/OFFトグル・5段階不透明度ボタン）が操作に応じて即座に `UnderlayLayoutController` を更新するウィジェットテスト（実施済み）

## 検討メモ（直近）

### 2026-07-15: 画像読み込み機能（OOM対策込み）の実装

**決定事項（スコープ確定）**:
- v1: `image_picker` でギャラリーから選んだ向きのまま取り込む（回転・反転はしない）。OOM対策として `maxWidth`/`maxHeight: 2048` を指定し、ネイティブ側で先にダウンサンプリングしてからDartへ渡す（#18）。
- v1.1 以降へ見送り: アプリ内回転・反転、`image_cropper` 等のUI付き切り抜き。
- iOS `Info.plist`（`NSPhotoLibraryUsageDescription`）: 本リポジトリに `ios/` プラットフォームが未追加（Android/Google Play専用の計画のため）。ユーザーに確認の上、今回はスコープ外と確定（iOS展開時に `flutter create --platforms=ios .` 後に対応）。

**実装**:
- `pubspec.yaml`: `image_picker: ^1.2.3` を追加（`flutter pub add image_picker`）。
- [lib/services/underlay_picker.dart](lib/services/underlay_picker.dart)（新設）: `ImagePicker` の薄いラッパー `UnderlayPicker`。`kUnderlayMaxDimension = 2048` を `maxWidth`/`maxHeight` として渡し、選択された画像のパスを返す（キャンセル時は `null`）。テストでフェイクに差し替えられるよう、状態管理とは分離した単独クラスにした。
- [lib/providers/underlay_provider.dart](lib/providers/underlay_provider.dart)（新設）: `UnderlayState`（`imagePath` / `errorMessage`）+ `UnderlayController`（`StateNotifier`）。`pickImage()` はキャンセル（`null`）を no-op、失敗時は既存の `imagePath` を保持したまま `errorMessage` にユーザー向け文言を格納する（ピッカー失敗で既存の下絵が消えないようにするため）。`underlayPickerProvider` 経由で `UnderlayPicker` を注入し、テストでフェイクに差し替え可能。
- [lib/screens/editor_screen.dart](lib/screens/editor_screen.dart): AppBar に下絵選択ボタン（`Icons.image_outlined` / 選択済みは `Icons.image`）を追加。`ref.listen` で `UnderlayState` の変化を検知し、成功時はパスを、失敗時はエラーメッセージを `SnackBar` で表示する一時的な確認 UI（本格的なキャンバス描画は後続タスク）。
- [test/underlay_provider_test.dart](test/underlay_provider_test.dart)（新設）: フェイク `UnderlayPicker` を用いたユニットテスト4件（成功時のパス保持、キャンセル時の状態不変、失敗時のエラー表示＋既存パス保持、初期状態）。

**確認**: `flutter analyze` 0件 / `flutter test`（76件、新規4件）パス。実機確認（実際のギャラピッカー起動・4K級写真での動作）は本タスクの完了条件外 — Phase Hα 全体の完了条件（下絵をキャンバスに表示できる段階）で実施予定。

### 2026-07-15: UnderlayLayout の実装（下絵の配置・不透明度・表示切替）

**設計報告（実装前にユーザー承認を得た内容の要約）**:
- **採用アプローチ**: `PolygonPainter` とは別の `UnderlayPainter`（`CustomPaint`）を追加し、`ViewportController`/`DragPreviewController` と同じ「`ValueNotifier` + `CustomPainter.repaint`」パターンで `UnderlayLayoutController` を実装。`InteractiveViewer` などの既製ジェスチャーウィジェットは、v1 が「フィット固定・自由配置なし」と決まったため不要と判断（採用しない）。
- **リスク**: 下絵に独自のピンチ/パン操作を与えると、Hβ で計画しているキャンバス全体のピンチズームジェスチャーと同じ2本指操作が競合する。→ ユーザーに確認し、**v1は自由配置なし（フィット固定＋不透明度調整のみ）** で合意（下記「決定事項」）。
- **代替案として提示**: (a) 今回提案の「フィット固定 + Undo対象外の別ValueNotifier」、(b) `InteractiveViewer` で下絵に独立ジェスチャーを与える案（Hβとの競合リスクあり）、(c) 下絵の配置を `Artwork` の一部にしてUndo対象にする案（幾何ではない情報をUndo対象にする既存方針との不整合リスクあり）。(a) で合意。

**決定事項（ユーザー確認済み）**:
- v1 は **fit-only**（`fitUnderlayToCanvas` によるキャンバスへのフィット固定のみ）＋ **不透明度調整**。ピンチ/パン等の自由配置は v1.1 以降（Hβ のキャンバス全体ジェスチャーと衝突するため）へ見送り。
- 下絵の配置変更は `CanvasNotifier`/`Artwork` の **Undo スタックの対象外**（幾何ではなく表示状態のため）。
- UI: `EditorScreen` の AppBar に「下絵設定」ボタン（`Icons.tune` — 既存の「下絵を選択」ボタン `Icons.image`/`Icons.image_outlined` と混同しないよう別アイコンを採用）を追加。タップで `showModalBottomSheet` を開き、`SwitchListTile`（表示ON/OFF）と `SegmentedButton`（不透明度 20/40/60/80/100% の5段階、タップで即時反映）を格納。スライダーではなくボタン式にすることで、ドラッグ操作によるOSスワイプジェスチャーとの誤爆を回避。

**実装**:
- [lib/models/underlay_layout.dart](lib/models/underlay_layout.dart)（新設）: `UnderlayLayout`（`offset`/`scale`/`opacity`/`visible`）。`toMap()`/`fromMap()`（`visible` は非永続 — Hγ で保存対象にするかは未決定）。将来のスクリーン→下絵ローカル座標変換に備え、`toMatrix()`（`vector_math` の `Matrix4`）と `worldToLocal()`（同じ変換をプレーンな `Offset` 演算で行う版）を用意。
- [lib/geometry/underlay_fit.dart](lib/geometry/underlay_fit.dart)（新設）: 純関数 `fitUnderlayToCanvas`。画像サイズとキャンバスサイズから contain-fit・中央寄せの `UnderlayLayout` を計算。
- [lib/providers/underlay_layout_provider.dart](lib/providers/underlay_layout_provider.dart)（新設）: `UnderlayLayoutController`（`ValueNotifier<UnderlayLayout>`）+ `underlayLayoutProvider`。
- [lib/providers/underlay_image_provider.dart](lib/providers/underlay_image_provider.dart)（新設）: `underlayImageProvider`（`FutureProvider<ui.Image?>`、選択されたパスをデコード）と `underlayFitCoordinatorProvider`（画像デコード完了時・キャンバスリサイズ時に `fitUnderlayToCanvas` を再計算して適用する副作用専用プロバイダ）。
- [lib/widgets/canvas/underlay_painter.dart](lib/widgets/canvas/underlay_painter.dart) / [underlay_layer.dart](lib/widgets/canvas/underlay_layer.dart)（新設）: 下絵の描画レイヤー。`viewport`/`layout` の `ValueListenable` を `repaint` に渡し、Riverpod 経由のウィジェット再構築なしに再描画。
- [lib/widgets/canvas/polygon_canvas.dart](lib/widgets/canvas/polygon_canvas.dart): `UnderlayLayer` をポリゴン描画の背面に `Stack` で追加。下絵層・ポリゴン層をそれぞれ個別の `RepaintBoundary` で分離。
- [lib/widgets/underlay/underlay_settings_sheet.dart](lib/widgets/underlay/underlay_settings_sheet.dart)（新設）: ボトムシートの内容（`SwitchListTile` + `SegmentedButton`）。`ref.watch` ではなく `ValueListenableBuilder` で `UnderlayLayoutController` を直接購読（`Provider<Controller>` 自体は変化しないため）。
- [lib/screens/editor_screen.dart](lib/screens/editor_screen.dart): AppBar に「下絵設定」ボタンを追加（下絵未選択時は無効化）。下絵表示がキャンバス上で直接確認できるようになったため、ピック成功時の一時的な `SnackBar` 通知は削除（失敗時のエラー通知のみ残す）。
- `pubspec.yaml`: `vector_math`（`Matrix4` 利用のため、推移的依存から直接依存へ明示化）を追加。
- テスト（新設）: [test/geometry/underlay_fit_test.dart](test/geometry/underlay_fit_test.dart)、[test/underlay_layout_test.dart](test/underlay_layout_test.dart)、[test/underlay_layout_provider_test.dart](test/underlay_layout_provider_test.dart)、[test/widgets/underlay_settings_sheet_test.dart](test/widgets/underlay_settings_sheet_test.dart)。

**スキーマ検討メモへの反映**: [plan_future_phases.md](plan_future_phases.md) の「2. ArtworkDocument v1 スキーマ設計（U1 / #9）」の `underlay.layout` に `opacity` フィールドを追記（`visible` は非永続のまま、Hγ で要否を決定）。

**確認**: `flutter analyze` 0件 / `flutter test`（96件、新規20件）パス。実機での見た目確認（実際に下絵が表示・不透明度変更が反映されるか）は未実施 — Phase Hα 全体の完了条件で実施予定。

**次のアクション**: 実機（またはエミュレータ）で、写真インポート→フィット表示→不透明度/表示切替→高解像度写真でのクラッシュなしを確認し、Phase Hα の完了条件を満たしたことを確認する。

### 2026-07-15: Android ビルド環境の不具合対応（`image_picker_android:compileDebugKotlin` 失敗）

**症状**: `image_picker` 追加後、`flutter build apk`/`flutter run` で `Execution failed for task ':image_picker_android:compileDebugKotlin'` → `Could not close incremental caches ...class-fq-name-to-source.tab, source-to-classes.tab, internal-name-to-source.tab`。`flutter clean` / `build` フォルダ削除でも再発。

**原因（特定済み）**: 本プロジェクトが `F:\polygon_art_app` にあるのに対し、Flutter の pub cache（`image_picker_android` 等プラグインのKotlinソースの実体）は `C:\Users\<user>\AppData\Local\Pub\Cache` にある。Kotlin の増分コンパイラ（Build Tools API）はキャッシュを閉じる際、2ファイル間の**相対パス**を計算しようとするが、Windowsではドライブ文字が異なる2パス間の相対パスは計算不能（`this and base files have different roots`）→ これが例外の連鎖を引き起こし `Could not close incremental caches` として表面化する。exFAT等のファイルシステム相性ではなく、**ドライブ文字（C:とF:）が異なることそのもの**が原因（Kotlin側の既知の未解決バグ、`flutter/flutter#173456`・`#187225`・`#187658`、`tauri-apps/tauri#10876`、`google/ksp#1079` 等で同種の報告あり）。
- `ext.kotlin_version`（Groovy時代の変数）は本プロジェクトには存在しない — Kotlinバージョンは `android/settings.gradle.kts` の `id("org.jetbrains.kotlin.android") version "2.3.20"` で指定されており、これは十分新しいため、バージョンアップでは根本原因（クロスドライブの相対パス計算不能）は解消しない。

**対応**: `android/gradle.properties` に `kotlin.incremental=false` を追記し、Kotlinの増分コンパイル自体を無効化（相対パスを計算するコードパスに入らせない）。Flutterチーム自身がこの既知バグへの暫定回避策として案内している設定。
- **トレードオフ**: 増分コンパイルが効かなくなるため、2回目以降のビルドも毎回フルコンパイルになり若干遅くなる（今回の初回ビルドは291秒）。根本解決には pub cache をプロジェクトと同じドライブ（F:）に移す（`PUB_CACHE` 環境変数を変更し `flutter pub get` を再実行）必要があるが、これは全パッケージの再ダウンロードを伴うマシン全体の設定変更のため、今回はスコープ外（ユーザー判断待ち、いつでも追加対応可能）。

**確認**: `flutter build apk --debug` が成功（`build\app\outputs\flutter-apk\app-debug.apk` 生成）。

### 2026-07-16: 特殊なJPEGで下絵の下1/3が黒くなるバグの修正（画像取込の標準化）

**症状**: 実機での下絵表示自体は成功したが、2回目にインポートした画像（過去に何らかの画像処理ソフトで加工された、少し特殊なJPEG）で、表示された下絵の下1/3が真っ黒になる不具合が発生。

**原因（推測、切り分け未実施）**: 以下のいずれか、または両方の複合と推測:
- メモリ不足: `maxWidth`/`maxHeight: 2048`（正方形上限）はまだ4K写真に対して大きく、デコード時のネイティブメモリ圧迫が完全には解消されていなかった可能性。
- 非標準的な圧縮形式でのデコード失敗: 問題の画像が過去の画像処理を経て、Flutterの標準デコーダ（`dart:ui`）が完全にはサポートしない、あるいは部分的にしか解釈できないJPEGエンコーディング（不完全な走査データ、特殊なチャンクマーカー等）になっていた可能性。デコーダが末尾データを読み切れず、残り領域（下1/3）が初期値（黒）のまま返された、という見た目に整合する。

**対応**: 画像インポート時に、より積極的な標準化（リサイズ）を行うことで両方の要因を同時に軽減する。
- [lib/services/underlay_picker.dart](lib/services/underlay_picker.dart): `image_picker` の `pickImage` 呼び出しに渡す上限を、`kUnderlayMaxDimension = 2048`（正方形）から `kUnderlayMaxWidth = 1920` / `kUnderlayMaxHeight = 1080` の2定数（16:9基準、Full HD相当）に変更。`maxWidth`/`maxHeight` を指定すると `image_picker` はプラットフォーム側（Android/iOSのネイティブAPI）でビットマップとしてデコード→リサイズ→標準JPEGとして再エンコードしてから返すため、この指定自体が「デコード負荷の軽減」と「画像形式の標準化（非標準エンコーディングの解消）」の両方を兼ねる。
- [lib/providers/underlay_provider.dart](lib/providers/underlay_provider.dart): ドキュメントコメントの `kUnderlayMaxDimension` 参照を新定数名に追随。

**スコープ外（切り分け・再現テスト）**: 原因を厳密に切り分けるための再現テスト（問題のJPEGバイナリを使った単体テスト等）は、問題画像がユーザーの手元にしかなく用意できないため見送り。実機での再確認（同じ画像を再インポートしても黒くならないこと）をもって修正の確認とする。

**確認**: `flutter analyze` 0件 / `flutter test`（96件、既存分すべて）パス。実機での再確認は本タスク完了後にユーザーが実施予定。
