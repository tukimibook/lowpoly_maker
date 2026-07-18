# Phase F: なぞりモード（現在着手中）

> **正本の位置づけ**: 全体像・確定した設計判断・品質方針・リリース要件は [ポリゴンアプリ再設計_e54196e6.plan.md](ポリゴンアプリ再設計_e54196e6.plan.md)（マスター）を参照。未着手フェーズ（G/Hγ/Hδ/R）の詳細・技術的負債表・テスト方針・リスクと対策は [plan_future_phases.md](plan_future_phases.md) を参照。完了済みフェーズ（A〜E+、G-spike、Hα、Hβ）の実装済み仕様・過去（2026-07-10〜07-17）の検討メモは [plan_archive_history.md](plan_archive_history.md) を参照。着手時の進捗・次ステップは下記 **現在のステータス** を参照。
> **運用**: 本ファイルは「現在着手中のフェーズ」専用ファイル。ファイル名にフェーズ名を含める（`plan_phase_<フェーズ>.md`）運用とし、F が完了し次のフェーズ（G）に進んだら、本ファイルの中身を G の詳細（[plan_future_phases.md](plan_future_phases.md) から該当セクションを移動）に差し替え、ファイル名も `plan_phase_G.md` にリネームして使い続ける（Hα → Hβ → F でこの運用を継続、2026-07-18）。F 完了時の実装完了メモ・検討メモは、差し替え時に [plan_archive_history.md](plan_archive_history.md) へ移す。Phase 完了コミット後は **現在のステータス** を次 Phase 用に更新する。

## 📍 現在のステータス (2026-07-18)
- **完了フェーズ**: Phase G-spike が大成功で完了（無限ループのバグの種もジッター付与で事前解決済み、本番実装は Tier B に確定）。Phase Hα（下絵インポート・キャンバス準備）が完了。Phase Hβ（ズーム / パン UI とジェスチャー方針の再設計）が完了（許容距離の画面px統一、`onScale*` + `pointerCount` によるジェスチャー方針の確立、「全体表示に戻す」ボタン、実機フィードバックを受けた「2本目の指が触れた際は確定ではなく破棄（キャンセル）」への修正まで実施済み。詳細は [plan_archive_history.md](plan_archive_history.md) の「Phase Hβ」節・検討メモ参照）。
- **現在のフェーズ**: Phase F（なぞりモード）の **F-core / F-UI がともに実装完了**。`TracePointGenerator`（`generateTracePoints`）・`CanvasNotifier.commitTraceStroke`・`TraceStrokePreviewController`・`TraceGestureController`（猶予期間＋ロックの2フェーズ状態機械による Lock & Ignore）まで実装・テスト済み。詳細は下記「検討メモ（直近）」参照。残作業: 実機での最終確認のみ。

## Phase F: なぞりモード

> **着手前提（必須）**: 下記「着手前チェックリスト」の F-core / F-UI チェック。`handleDrawTap` の単純再利用はしない。→ 検討メモ（2026-07-13、[plan_archive_history.md](plan_archive_history.md)）参照。

#### ~~旧仕様（2026-07-13 前）~~

- ~~`TracePointGenerator` でパス上を等間隔サンプリング。`DrawMode.tap` / `trace` 切替。~~
- ~~生成点も同じスナップ規則で近接頂点を共有。~~
- ~~完了条件: なぞりで等間隔頂点列が生成され、既存頂点と溶接される。~~

#### 現行仕様（2026-07-13〜）— F-core / F-UI 分割

**F-core（Hβ 前でも可 — 純関数 + テスト）**

- `lib/geometry/trace_point_generator.dart`（または `services/`）に **`TracePointGenerator`** を純関数として新設。パス上を等間隔サンプリング。
- **`commitTraceStroke(List<Offset>)`（または `appendTracePoints`）** を `CanvasNotifier` に新設:
  - 疑似ダブルタップ検出（`_isPseudoDoubleTap`）を**通さない**
  - **1ストローク = `_recordUndo` 1回**（点ごとに積まない）
  - 吸着・線上吸着はバッチ内でまとめて実行
- `TracePointGenerator` / `commitTraceStroke` の単体・ロジックテストを先に書く。

**F-UI（Hβ 完了後 — 最終ジェスチャー土台の上に載せる）**

- `DrawMode.tap` / `trace` 切替（ツールバー + `polygon_canvas` のジェスチャー分岐）。
- なぞり中は Hβ で確立した `onScale*` + `pointerCount` 土台上で点列生成、離した瞬間に `commitTraceStroke`。
  - Hβ の実機フィードバック対応（2本目の指が加わった際は「破棄」）と同じ方針を踏襲すること: なぞり中に2本目の指が加わった場合、それまでの点列は破棄せず「その時点までの点列で `commitTraceStroke`」するか、それとも Hβ の draw モード同様に「破棄」するかは、なぞり操作の性質（連続したストローク）を踏まえて F-UI 着手時に改めて検討する。
- なぞりモードでは暗黙クローズ（疑似ダブルタップ）を無効化。閉じるはツールバー「閉じる」ボタンに寄せる。

**完了条件**: 下絵＋ズームありの状態で、なぞり等間隔頂点列が生成され既存頂点と溶接される。1ストロークの Undo が1回。疑似ダブルタップ誤爆なし。実機確認済み。

## 着手前チェックリスト（F-core / F-UI の前）

**F-core の前（E+ と並行可）**

- [x] `TracePointGenerator` を純関数として外に出す設計を固定（`lib/geometry/trace_point_generator.dart`、`generateTracePoints`）
- [x] `commitTraceStroke`（1ストローク1Undo・ダブルタップ非経由）の API を固定（`CanvasNotifier.commitTraceStroke`）
- [x] `TracePointGenerator` 単体テストを先に書く（`test/geometry/trace_point_generator_test.dart`）

**F-UI の前（Hβ 完了後 — 着手可能）**

- [x] なぞりジェスチャーを `onScale*` 土台に載せる（`TraceGestureController` による猶予期間＋ロックの2フェーズ状態機械。`Listener` はロック後の生ポインタ追跡専用で、既存の Hβ `onScale*` 機構自体は変更なし）
- [ ] 下絵＋ズームありで実機確認（未実施 — 次のステップ）

→ その他フェーズの着手前チェックリストは [plan_future_phases.md](plan_future_phases.md) の「着手前チェックリスト（統合、F を除く）」を参照。

## 追加すべきテスト（F関連）

[plan_future_phases.md](plan_future_phases.md) の「追加すべきテスト（優先度付き）」全体のうち、F に直接関連する項目のみ抜粋（全項目は同ファイルを参照）:

- `TracePointGenerator`（等間隔・短い stroke・折返し）
- `commitTraceStroke` 1回 = Undo 1回
- なぞり終了時の close ポリシー（tap 版ダブルタップと衝突しない）
- 1線分上の複数頂点吸着順序（`t` ソート）
- 抽出した `absorbVerticesOnSegment` の単体テスト（G でも再利用するため、F-core 側で先に抽出・テストしておく）

## 検討メモ（直近）

### 2026-07-18: F-core / F-UI 実装完了

**実装したもの**

- `lib/geometry/trace_point_generator.dart` — 純関数 `generateTracePoints(rawPath, {spacing})`。累積距離配列を作り、`spacing` の倍数ごとに該当セグメントを線形補間してサンプリングする O(rawPath.length) 実装。始点・終点は必ず保持（末尾が `spacing` の倍数ちょうどでなくても、最後にもう一度生の終点を追加）。ゼロ長セグメント（指の停止）は自然にスキップされる。
- `CanvasNotifier.commitTraceStroke(points, {hitRadius, lineAbsorptionTolerance})` — `_resetPendingTap()` → `_recordUndo()` を1回だけ呼び、以降はローカル変数（`vertices`/`draftIds` のコピー）だけを更新し、ループの最後に `state.copyWith(...)` を1回だけ実行するバッチ処理。既存の `_handleSingleDrawTap` と同じスナップ/吸着ルールを点ごとに適用するが、`state` への書き込みは合計1回。`findPolygonVertexNear` は `_findPolygonVertexNearIn(vertices, excludedIds, position, ...)` という内部ヘルパーに切り出し、公開 API はそれに委譲する形にリファクタ（外部の振る舞いは変更なし）。疑似ダブルタップ・自動クローズは一切通さない（v1 方針どおり、ドラフトに追記するだけ）。
- `TraceStrokePreviewController`（`lib/providers/trace_stroke_preview_provider.dart`）— `ValueNotifier` ではなく素の `ChangeNotifier` を採用。`Path.lineTo` で O(1) にインクリメンタル追記しつつ、`commitTraceStroke` に渡す生の `List<Offset>` も同時に保持。
- `TraceGestureController`（`lib/providers/trace_gesture_provider.dart`）— 提案どおり `idle` → `awaitingDisambiguation` → `locked` の3状態。`kTraceGraceWindow`(120ms) の `Timer` と `kTraceGraceSlop`(10px) の両方でロック確定。`isTrackedPointer(pointerId)` で「今どの指を見ているか」を一元管理し、ロック後は指定ポインタ以外を完全に無視する。
- `DrawMode`（`lib/models/draw_mode.dart`）— `tap`/`trace` の2値。`drawModeProvider` は `canvasModeProvider` と同じ流儀で `canvas_provider.dart` に配置。
- `polygon_canvas.dart` — `CanvasMode.draw && DrawMode.trace` のときだけ、既存の `onScale*` `GestureDetector` の**外側**に生ポインタ用の `Listener` を追加する分岐を新設。Hβ の `beginGestureSubCycle`/`isViewportGesture`/`applyViewportUpdate`/`endGestureSubCycle` は無改変のまま再利用（`traceGesture.isLocked` のときだけ早期 `return` して既存ロジックへの影響をゼロに保つ設計）。
- `editor_toolbar.dart` — 描画モードの Row 2 先頭に タップ/なぞり の `SegmentedButton` を追加。モード切替（`_CommonRow.selectMode`）で描画モードから離れる際に `traceGestureProvider`/`traceStrokePreviewProvider` もリセットするよう防御的に追加。
- `PolygonPainter` — `tracePreview`（`TraceStrokePreviewController`）を受け取り、ストローク中はティール色の実線で描画（`Listenable.merge` に追加）。

**製品判断の実装箇所**

- 判断1（猶予期間中に指が離れたら破棄）: `Listener.onPointerUp`/`onScaleEnd` の両方で `!wasLocked` 分岐が `tracePreview.clear()` のみ呼び、`commitTraceStroke` を呼ばない。
- 判断2（ロック対象の指が離れた瞬間に即確定）: `Listener.onPointerUp` の `wasLocked` 分岐でのみ `commitTraceStrokeFromPreview()` を呼ぶ。他の指がまだ触れていても関係なく確定する。

**テスト**

- `test/geometry/trace_point_generator_test.dart` — 9件（直線等間隔、末尾保持、複数セグメント跨ぎ、短いストローク、折返し、ゼロ長セグメント、空/1点入力、spacing<=0 のアサート）。
- `test/canvas_notifier_trace_test.dart` — 10件（空リストの no-op、通常追記、1バッチ=1Undo、既存頂点へのスナップ、線上吸着、疑似ダブルタップが発火しないこと、既存ドラフトへの継続、直後の tap が誤ダブルタップにならないこと、hitRadius のスケーリング）。
- `test/widget_test.dart` に新規グループ「Phase F: なぞりモード gesture (Lock & Ignore, 2026-07-18)」を追加（5件）: スロップ超えでの一括コミット、猶予期間中の早期リリースの破棄、猶予期間中に2本目の指が来た場合のピンチ/パンへのハンドオフ、ロック後に2本目の指が来ても無視されロック対象の指のみでストロークが継続すること、モード切替時の防御的リセット。
- 全191件パス（`flutter analyze` も問題なし）。

**残課題 / 次のステップ**

- 下絵＋ズームありでの実機確認（着手前チェックリストの最後の1項目）。
- ライブプレビューの見た目（色・線幅）は仮置き。実機フィードバックを受けて調整の可能性あり。
- なぞりで生成した点列からポリゴンを自動生成するかどうかは v1 では見送り（ドラフトに追加するのみ、閉じるのはツールバーの「閉じる」ボタン）— 元設計どおり。
