# Phase Hα: 下絵（背景画像）（現在着手中）

> **正本の位置づけ**: 全体像・確定した設計判断・品質方針・リリース要件は [ポリゴンアプリ再設計_e54196e6.plan.md](ポリゴンアプリ再設計_e54196e6.plan.md)（マスター）を参照。完了済み/未着手の他フェーズ詳細・技術的負債表・過去（2026-07-10〜07-15）の検討メモは [plan_future_phases.md](plan_future_phases.md) を参照。着手時の進捗・次ステップは下記 **現在のステータス** を参照。
> **運用**: 本ファイルは「現在着手中のフェーズ」専用ファイル。ファイル名にフェーズ名を含める（`plan_phase_<フェーズ>.md`）運用とし、Hα が完了し次のフェーズ（Hβ）に進んだら、本ファイルの中身を Hβ の詳細（[plan_future_phases.md](plan_future_phases.md) から該当セクションを移動）に差し替え、ファイル名も `plan_phase_H_beta.md` にリネームして使い続ける（G-spike → Hα でこの運用に切り替え済み）。Hα 完了時の実装完了メモ・検討メモは、差し替え時に [plan_future_phases.md](plan_future_phases.md) の検討メモアーカイブへ移す。Phase 完了コミット後は **現在のステータス** を次 Phase 用に更新する。

## 📍 現在のステータス (2026-07-16)
- **完了フェーズ**: Phase G-spike が大成功で完了（無限ループのバグの種もジッター付与で事前解決済み、本番実装は Tier B に確定）。
- **現在のフェーズ**: Phase Hα（下絵インポート・キャンバス準備）に着手中。実機での表示自体には成功したが、特定のJPEG（過去に画像処理を経た少し特殊なもの）で下1/3が黒く表示されるバグを検出・修正した（下記「2026-07-16: 特殊なJPEG...」検討メモ参照）。さらに、モード切替時に下絵の表示位置がズレる不具合を発端に、ボトムツールバーの構造とUI/UXを刷新した（下記「2026-07-16: 下絵位置ズレバグの根本解決...」検討メモ参照）。この刷新の副産物として生まれた「編集モードで頂点が未選択のときは何もできない」というUXの穴を埋めるため、図形/辺のトグル選択・平行移動・中点への頂点挿入・図形削除を追加した（下記「2026-07-16: 編集モードのUX強化...」検討メモ参照）。これは下絵の機能そのものではないが、同じ2026-07-16のボトムツールバー刷新作業の一部として連続して実施した。

## Phase Hα: 下絵（背景画像）

> G より先に実装（v1 の芯）。保存（Hγ）と同時リリース — セッションのみの下絵は不可。→ 検討メモ（2026-07-13・追記続き3、[plan_future_phases.md](plan_future_phases.md)）参照。

- `image_picker` でギャラリーから選択。`UnderlayLayout`（画像参照 + world rect + opacity）を独立モデルに。`Artwork` 本体とは分離し、保存時は Hγ で JSON に含める。
- **取り込み時に上限解像度（`maxWidth: 1920` / `maxHeight: 1080`、2026-07-16改訂）へダウンサンプリング（＝標準化）してから保持・表示する**（#18）。理由: 端末カメラの写真は4K以上の高解像度が普通で、そのままメモリ上に展開するとデコード時点でネイティブメモリを圧迫し、OOM（メモリ不足）でクラッシュするため。加えて、`maxWidth`/`maxHeight` 指定はプラットフォーム側でのリサイズ＋標準JPEG形式への再エンコードも兼ねるため、非標準的な形式のJPEGに対するデコード失敗（下記「2026-07-16」検討メモ参照）の回避にも寄与する。`image_picker` の `maxWidth`/`maxHeight` 指定で実現（アプリ内コピーとして再保存はしない）。
- `PolygonPainter` とは別の `CustomPaint`（`UnderlayPainter`）として、viewport 変換**内側**（world 固定）に下絵を描画。ポリゴンより背面、両方を個別の `RepaintBoundary` で分離。
- 透過: スライダーではなく段階的なボタン操作（スワイプ操作によるOSジェスチャー誤爆を避けるため、2026-07-15 決定）。~~5段階ボタン（`SegmentedButton`）＋表示ON/OFFトグル（`SwitchListTile`）を `showModalBottomSheet`（AppBarの「下絵設定」ボタンから開く）に格納。~~ → **2026-07-16 改訂**: モーダルシートを廃止し、ボトムツールバー上段に「💧 NN%」の単一トグルボタン（タップで10/30/50/70/100%をループ）＋表示ON/OFFアイコンボタンとして統合（タップ数削減、下記「2026-07-16: 下絵位置ズレバグの根本解決...」検討メモ参照）。
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
- ~~下絵設定ボトムシート（表示ON/OFFトグル・5段階不透明度ボタン）が操作に応じて即座に `UnderlayLayoutController` を更新するウィジェットテスト（実施済み）~~ → シート廃止（2026-07-16）に伴い削除。後継の `UnderlayLayoutController.cycleOpacity()` の単体テストを実施済み（下記検討メモ参照）。
- `resolveDetachTarget`（共有頂点の切り離し対象を解決する純関数）の単体テスト（実施済み）
- `edgeMidpoint`／`resolvePolygonTarget`／`resolveEdgeTarget`（図形・辺のトグル選択を解決する純関数群）の単体テスト（実施済み）
- `CanvasNotifier.translatePolygon`／`insertVertexAtEdge`／`deletePolygon` の単体テスト（Undo復元込み、実施済み）

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

### 2026-07-16: 下絵位置ズレバグの根本解決とボトムツールバーのUI/UX刷新（ハイブリッド2段構成・バリア構造・トグル式UI）

**症状**: 画面下部の「描画」/「編集」ボタンでモードを切り替えた際、下絵（背景画像）の表示位置がズレる。

**原因（調査結果）**: `Scaffold.bottomNavigationBar`（旧 `EditorToolbar`）はモードごとに高さが異なっていた（描画モードはカラーパレット行、編集モードは共有頂点操作の行など）。`Scaffold` はボディに残りの領域を渡すため、ボトムバーの高さが変わるたびに `PolygonCanvas` の `LayoutBuilder` が受け取る `constraints` も変化し、`canvasProvider.setCanvasSize()` → `underlayFitCoordinatorProvider`（`canvasSize` の変化を監視）→ `fitUnderlayToCanvas` の再計算が走り、下絵の `offset`/`scale` が毎回再フィットされていた。ポリゴン自体は `canvasSize` に依存しない座標系で描かれるため影響を受けず、下絵だけがズレて見えていた。**意図しないバグ**と判断（「やむを得ない仕様」ではない）。

**検討した方針**:
- 方針A（旧）: ボトムバーの高さを固定するのみ。
- 方針B: `canvasSize` が変化しても、縦横比が変わらない限り再フィットしないようガードするロジック変更。将来のズーム/パン実装（Hβ）への影響リスクがあるため不採用。
- 方針C→採用: **ロジック（`canvasProvider`/`fitUnderlayToCanvas`）には一切手を入れず、レイアウト構造を変更**。`Scaffold.bottomNavigationBar` を廃止し、`body` 内で `Stack` を使い `PolygonCanvas` を全面（`Positioned.fill`）、`EditorToolbar` を最前面下部に `Positioned` でオーバーレイ配置。これにより `PolygonCanvas` が受け取る領域サイズはボトムバーの高さに関係なく常に一定になり、根本的に再フィットの発生条件そのものを消す。

**Stack オーバーレイ案の技術的懸念と対応**:
- **タップの貫通（懸念）**: `Stack` は子を重ねるだけなので、ツールバーの背面にあるボタン間の隙間をタップすると、そのタップがそのまま背面の `PolygonCanvas` にも渡ってしまう（意図しない頂点追加等を誘発しうる）。
  - **対応**: `EditorToolbar` の外側を丸ごと `GestureDetector(behavior: HitTestBehavior.opaque)` でラップ（`_ToolbarBarrier`、[lib/screens/editor_screen.dart](lib/screens/editor_screen.dart)）。Flutter の `RenderBox.hitTest` は子（ここではツールバー内の各アイコンボタン）を先にテストしてから自身の判定を行うため、`opaque` はツールバー自身の各ボタンの動作を一切妨げない。一方 `RenderStack` は子のヒットテストが一度 `true` を返すと以降のZ順で背面の兄弟（`PolygonCanvas`）のテストを打ち切るため、`opaque` により「ツールバーの矩形内で起きたタップは、ボタンの有無に関わらず必ずここで吸収され、背面には絶対に届かない」ことが保証される。`AbsorbPointer` は使わない（ツールバー自身のボタンの操作も一緒に吸収してしまうため不適）。
  - この設計により、ボトムバーの実際の高さが将来的に変動しても（`_kRowHeight` 定数の変更など）、バリアはツールバー自身の外形にそのまま追従するため、高さを厳密に固定する必要は構造上なくなった。
- **描画面積の実質的な増加はない（既知のトレードオフ）**: ツールバーが浮いている領域は依然としてタップ不可（バリアがある）なので、キャンバスの「使える」面積自体はボトムナビゲーションバー方式と変わらない。今回の主目的は面積拡大ではなく「レイアウトシフトの根絶」。
- **既存テストの前提崩れ**: `farPoint`（キャンバス右下付近を使った磁石スナップのテスト）がボトムバーの直下に来なくなり、逆にツールバーの真下（バリアで吸収される領域）に入ってしまうケースがあったため、[test/widget_test.dart](test/widget_test.dart) の該当テストを「キャンバス右上付近」を使うよう修正。

**UI/UX刷新（ユーザー最終承認済みの基本仕様）**: 上記の構造変更に合わせ、モダンな描画アプリとしての操作性向上も同時に実施。
- **完全アイコン化**: すべてのボタンからテキストラベルを排除し、`Icons.xxx` のみ＋`Tooltip`（読み上げ・長押しヒント用のアクセシブルネーム）とした。言語依存をなくし、UIをより簡潔にする狙い。
- **2段構成（[lib/widgets/toolbar/editor_toolbar.dart](lib/widgets/toolbar/editor_toolbar.dart) を全面再実装）**:
  - **上段（Row 1・全モード共通）**: モード切替（`SegmentedButton`、描画=`Icons.draw_outlined`／消しゴム=`Icons.backspace_outlined`／編集=`Icons.open_with`）、下絵の表示ON/OFF（`Icons.visibility`/`visibility_off`）、下絵の不透明度トグル（`Icons.opacity` ＋現在値「NN%」の1ボタン、タップで10→30→50→70→100%をループ）、元に戻す（`Icons.undo`）。**下絵設定を旧モーダルシート（`UnderlaySettingsSheet`、廃止・削除）から常時表示の上段に統合**し、タップ1回で操作可能に。
  - **下段（Row 2・モード別）**: 描画=カラーパレット（横スクロール）＋閉じるボタン（`Icons.check_circle`）。消しゴム=装飾的な `Icons.delete_outline`（非操作、頂点タップで削除する旨のヒント表示のみ）。編集（頂点未選択 or 非共有頂点）=装飾的な `Icons.touch_app_outlined`。編集（共有頂点選択中）=「切り離し対象の切り替え」（`Icons.autorenew`）＋「切り離し実行」（`Icons.content_cut`）の2ボタンのみ（旧: 共有先の多角形数だけボタンが並ぶ可変UI → 固定2ボタンに削減）。
- **状態管理**:
  - `UnderlayLayoutController.cycleOpacity()`（[lib/providers/underlay_layout_provider.dart](lib/providers/underlay_layout_provider.dart)）: 新規 `kUnderlayOpacitySteps = [0.1, 0.3, 0.5, 0.7, 1.0]` を巡回。現在値に最も近いステップを求めてから次に進めるため、想定外の中間値からの復帰にも安全。新規Providerは追加せず既存の `ValueNotifier` に集約。
  - `detachCycleIndexProvider`（`StateProvider<int>`）＋純関数 `resolveDetachTarget`（[lib/providers/detach_cycle_provider.dart](lib/providers/detach_cycle_provider.dart)、新設）: 「切り離し対象」の巡回位置を保持する未クランプの生カウンタと、それを候補数で剰余して現在の対象（確定済み多角形のいずれか、または下書き）を解決する純関数に分離。ツールバーのボタンと `PolygonPainter` のハイライトが同じ関数を呼ぶことで、両者が指す対象を常に一致させる。カウンタのリセット（3箇所）: (1) [lib/widgets/canvas/polygon_canvas.dart](lib/widgets/canvas/polygon_canvas.dart) の `handleEditTap` で新しい頂点を選択した瞬間、(2) [lib/widgets/toolbar/editor_toolbar.dart](lib/widgets/toolbar/editor_toolbar.dart) でモードを編集以外に切り替えた瞬間、(3) 「切り離し実行」成功直後。
  - ハイライト: `PolygonPainter`（[lib/widgets/canvas/polygon_painter.dart](lib/widgets/canvas/polygon_painter.dart)）に `highlightedPolygonId` を追加。対象の多角形のみ塗り透過度を `_highlightedFillAlpha`（153、約60%）に、それ以外は既存の `_fillAlpha`（77、約30%）のまま描画。`PolygonCanvas` が `resolveDetachTarget` の結果から算出して渡す。
- **AppBar側の変更**: [lib/screens/editor_screen.dart](lib/screens/editor_screen.dart) の「下絵設定」ボタン（`Icons.tune`）を削除（機能はツールバー上段へ移動）。「下絵を選択/変更」ボタンは頻度の低い単発操作のため AppBar に残置。

**テスト**:
- [test/detach_cycle_provider_test.dart](test/detach_cycle_provider_test.dart)（新設）: `resolveDetachTarget` の単体テスト（候補0件でnull、単一候補、複数候補の巡回順、ラップアラウンド、下書きが末尾に来ること、下書き単体、候補数が減った後の生カウンタが範囲外にならないこと）。
- [test/underlay_layout_provider_test.dart](test/underlay_layout_provider_test.dart): `cycleOpacity` のテスト3件（順序通りに巡回してラップアラウンドすること、中間値からは最も近いステップの次に進むこと、opacity以外のフィールドに影響しないこと）を追加。
- [test/widgets/underlay_settings_sheet_test.dart](test/widgets/underlay_settings_sheet_test.dart)（削除）: `UnderlaySettingsSheet` 自体の削除に伴い不要化。
- [test/widget_test.dart](test/widget_test.dart): 「閉じる」ボタンの `find.text` 依存（テキストラベル廃止のため）を `IconButton.tooltip` によるカスタム `Finder`（`_iconButtonByTooltip`）に置き換え。`farPoint`（磁石スナップのテスト）をキャンバス右上付近に変更（上記「既存テストの前提崩れ」参照）。

**確認**: `flutter analyze` 0件 / `flutter test`（103件、新規10件・既存4件修正）パス。実機での見た目確認（実際にモード切替で下絵がズレないこと、新UIの操作感）は本タスク完了後にユーザーが実施予定。

### 2026-07-16: 編集モードのUX強化（図形/辺トグル・平行移動・中点挿入・図形削除）

**背景**: 直前のツールバー刷新で「編集モード・頂点未選択時」の下段は装飾的なヒントアイコン（`Icons.touch_app_outlined`）のみだった。細い辺や小さい図形に対してピクセル単位の正確なタップを要求する既存の操作感（タップで頂点選択、長押しドラッグで移動）を補い、トグル選択とハイライトだけで「図形全体の移動」「辺への頂点追加」「図形削除」まで行えるようにする。

**採用した設計（実装前にユーザー承認済み）**:
- **状態管理**: [lib/providers/polygon_edit_target_provider.dart](lib/providers/polygon_edit_target_provider.dart)（新設）に `polygonCycleIndexProvider`／`edgeCycleIndexProvider`（いずれも初期値 `-1` = 「まだ選んでいない」の意図的なセンチネル）と、それを候補数で剰余して解決する純関数 `resolvePolygonTarget`／`resolveEdgeTarget` を用意。`detachCycleIndexProvider`（初期値0、常に候補が1件以上ある前提）と違い、この機能は編集モードに入った直後・候補ゼロの状態からすでにUIが有効なため、`-1` を「まだ何も選んでいない」と「巡回して1周した」の区別に使う。カウンタのリセット（5箇所）: (1) [lib/widgets/toolbar/editor_toolbar.dart](lib/widgets/toolbar/editor_toolbar.dart) で編集モードを離れた瞬間（両方）、(2) [lib/widgets/canvas/polygon_canvas.dart](lib/widgets/canvas/polygon_canvas.dart) の `handleEditTap` で頂点が新たに選択された瞬間（両方）、(3) 「図形を切り替え」ボタン押下時（`edgeCycleIndexProvider` のみ — 辺の意味は対象図形に依存するため）、(4) 「ここに頂点を追加」成功後（両方）、(5) 「図形を削除」成功後（両方）。
- **ハイライト描画**: `PolygonPainter`（[lib/widgets/canvas/polygon_painter.dart](lib/widgets/canvas/polygon_painter.dart)）の既存 `highlightedPolygonId` を「切り離し対象」と「図形トグル対象」の両方で流用（頂点選択の有無で排他的に切り替わるため、フィールドを分けずに済ませた）。新規フィールド `targetEdge`（`PolygonEdge?`）を追加し、新設メソッド `_paintTargetEdge` で対象の辺だけをアクセントカラー（`Colors.blueAccent`）・太めのストローク（3.0）で上書き描画。
- **平行移動（commit-on-release）**: [lib/providers/polygon_drag_preview_provider.dart](lib/providers/polygon_drag_preview_provider.dart)（新設）に `PolygonDragPreview`（対象図形の全頂点ID＋ドラッグ中の変位）と `PolygonDragPreviewController`（`ValueNotifier`、他のドラッグプレビュー同様に `CustomPainter.repaint` の購読対象とすることでRiverpod経由の再構築を伴わず毎フレーム再描画）。`PolygonPainter._positionFor` を拡張し、対象図形の頂点をプレビューの変位分だけオフセットして描画。`PolygonCanvas` の編集モード用 `GestureDetector` に素の `onPan*`（`onLongPress*` とは別系統）を追加。図形がトグルで選ばれている（かつ頂点未選択の）ときだけ有効になり、指を離した瞬間に一度だけ `CanvasNotifier.translatePolygon` を呼んでUndoに記録する。既存の「長押しで頂点ドラッグ」とはFlutterのジェスチャーアリーナ機構により排他（長押しの待機中に素早く動かせばpanが、動かさず待てば長押しが勝つ）。
- **幾何ロジック**: [lib/geometry/edge_midpoint.dart](lib/geometry/edge_midpoint.dart)（新設）に純関数 `edgeMidpoint`。`CanvasNotifier`（[lib/providers/canvas_provider.dart](lib/providers/canvas_provider.dart)）に3メソッドを追加: `translatePolygon(polygonId, delta)`（対象図形の全頂点を一括平行移動、共有頂点は他の図形からも動いて見える）、`insertVertexAtEdge(polygonId, ringIndex)`（指定辺の中点に新頂点を挿入して`vertexIds`へスプライスし、新頂点IDを返す — 呼び出し側が即座に選択状態にできる）、`deletePolygon(polygonId)`（対象図形を削除し、他から参照されなくなった頂点のみプール剪定）。いずれもUndo記録込み。
- **UI**: [lib/widgets/toolbar/editor_toolbar.dart](lib/widgets/toolbar/editor_toolbar.dart) の編集モード・頂点未選択時の下段を新設 `_NoSelectionRow` に置き換え、4アイコンボタン（♻️「図形を切り替え」`Icons.autorenew`／⏭️「辺を切り替え」`Icons.skip_next`／➕「ここに頂点を追加」`Icons.add_circle_outline`／🗑️「図形を削除」`Icons.delete_outline`）を配置。対象未確定の段階では該当ボタンを `onPressed: null` で無効化（`辺を切り替え`/`ここに頂点を追加`/`図形を削除` は対象図形が要る、`ここに頂点を追加` はさらに対象辺も要る）。頂点選択済み・非共有頂点のときの装飾ヒント表示はそのまま維持。

**テスト**:
- [test/geometry/edge_midpoint_test.dart](test/geometry/edge_midpoint_test.dart)（新設）: `edgeMidpoint` の単体テスト5件。
- [test/polygon_edit_target_provider_test.dart](test/polygon_edit_target_provider_test.dart)（新設）: `polygonCycleIndexProvider`/`edgeCycleIndexProvider` の初期値、`resolvePolygonTarget`/`resolveEdgeTarget` の巡回・ラップアラウンド・センチネル・縮退ケースの単体テスト。
- [test/canvas_notifier_edit_test.dart](test/canvas_notifier_edit_test.dart): `translatePolygon`/`insertVertexAtEdge`/`deletePolygon` の単体テスト（共有頂点の伝播、無効ID/範囲外インデックスでのno-op、Undo復元）を追加。
- [test/widget_test.dart](test/widget_test.dart): 4ボタンの表示・無効化状態、図形ハイライト、辺選択→中点挿入で新頂点が即選択されること、図形削除、実際のpanジェスチャーによる平行移動（Flutterの `DragStartBehavior.start` 既定動作により、アリーナ勝利の契機となる最初の move は変位0として消費される点に注意 — 2回目以降のmoveで実際の変位が計測される）をウィジェットテストで確認。

**確認**: `flutter analyze` 0件 / `flutter test`（138件、新規22件）パス。実機での操作感確認は本タスク完了後にユーザーが実施予定。
