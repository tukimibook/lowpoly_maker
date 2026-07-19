# Phase G: 自動テッセレーション（現在着手中）

> **正本の位置づけ**: 全体像・確定した設計判断・品質方針・リリース要件は [ポリゴンアプリ再設計_e54196e6.plan.md](ポリゴンアプリ再設計_e54196e6.plan.md)（マスター）を参照。未着手フェーズ（Hγ/Hδ/R）の詳細・技術的負債表・テスト方針・リスクと対策は [plan_future_phases.md](plan_future_phases.md) を参照。完了済みフェーズ（A〜E+、G-spike、Hα、Hβ、F）の実装済み仕様・過去（2026-07-10〜2026-07-19）の検討メモは [plan_archive_history.md](plan_archive_history.md) を参照。着手時の進捗・次ステップは下記 **現在のステータス** を参照。
> **運用**: 本ファイルは「現在着手中のフェーズ」専用ファイル。ファイル名にフェーズ名を含める（`plan_phase_<フェーズ>.md`）運用とし、G が完了し次のフェーズ（Hγ）に進んだら、本ファイルの中身を Hγ の詳細（[plan_future_phases.md](plan_future_phases.md) から該当セクションを移動）に差し替え、ファイル名も `plan_phase_H_gamma.md` にリネームして使い続ける（Hα → Hβ → F → G でこの運用を継続、2026-07-19）。G 完了時の実装完了メモ・検討メモは、差し替え時に [plan_archive_history.md](plan_archive_history.md) へ移す。Phase 完了コミット後は **現在のステータス** を次 Phase 用に更新する。

## 📍 現在のステータス (2026-07-19)
- **完了フェーズ**: Phase A〜E+・G-spike・Hα・Hβ・F がすべて完了。F では `TracePointGenerator`／`CanvasNotifier.commitTraceStroke`／`TraceStrokePreviewController`／`TraceGestureController`（Lock & Ignore）によるなぞりモードを実装し、サンプリング間隔をワールド座標の固定絶対距離（`kTraceVertexSpacing = 50.0`）に統一済み。詳細は [plan_archive_history.md](plan_archive_history.md) 参照。
- **現在のフェーズ**: Phase G（自動テッセレーション）に着手する。**着手前提として、`maxEdge`/`minEdge` の world 値を実機相談で確定する必要がある**（#20、下記「着手前チェックリスト」参照）。

## Phase G: 自動テッセレーション（三角・幾何学ローポリ）

> **着手前提（必須）**: G-spike 完了（Go、Tier B 確定済み） + 下記「着手前チェックリスト」の G 本番直前チェック + **maxEdge/minEdge の world 値を実装前に相談で確定**（#20）。→ 検討メモ（2026-07-13・2026-07-14 追記続き4・2026-07-15、[plan_archive_history.md](plan_archive_history.md)）参照。

#### ~~旧仕様（2026-07-13 前）~~

- ~~パイプライン: (1) 輪郭取得 → (2) 内部点生成 → (3) ドロネー分割。~~
- ~~点分布: `PointDistribution.generate(boundary, spacing)`。v1 は幾何学ローポリ用1種。~~
- ~~出力は共有頂点プールに三角ポリゴン群として投入。~~
- ~~完了条件: 指で描いた〇の内部が三角メッシュで埋まり、**間隔スライダーで粗さを変えられ**、生成後に頂点編集できる。~~

> ~~関連: 閉じる辺の吸着ヘルパーを G で再利用（2026-07-10 メモ）。~~

#### ~~現行仕様（2026-07-13〜）~~

~~- パイプライン: (1) 輪郭取得（指の閉曲線を簡素化） → (2) 内部点生成 → (3) 三角形分割（ドロネー、境界は制約付き）。~~
~~- 点分布を差し替え式に: `PointDistribution.generate(boundary, spacing)`。v1 は幾何学ローポリ用1種・既定間隔のみ（間隔スライダーは v1.1 に先送り）。~~

#### 現行仕様（2026-07-14〜）

- パイプライン: (1) 輪郭取得（指の閉曲線を簡素化） → (2) 内部点生成 → (3) 三角形分割（G-spike の **Tier B または Tier C**）。
- **三角サイズ品質（#20）**: v1 は UI 調整なし（ボタン1つのみ）。内部定数は **world 座標の `maxEdge`（主）** + **`minEdge = maxEdge × 0.4`（比率固定）**。品質 Pass の優先は **「辺長が maxEdge を超える三角形が残らないこと」**。
  - **⚠ 実装前相談必須**: 計画時点では **具体的な world 値（物理サイズ相当）は未確定**。Hβ・F 実機（下絵フィット・なぞり点間隔・ズーム後の見え方）を踏まえ、**G 本番着手前に相談して `maxEdge` を確定**してから実装する。理由: キャンバス world サイズ・なぞり間隔と揃えないとローポリの粒度が破綻するため。
  - spike では仮値で検証可。本番定数は相談後に `lib/` へ反映。
- 点分布: `PointDistribution.generate(boundary, maxEdge)`（~~spacing 単一~~ → **maxEdge 中心**）。~~間隔スライダー~~ → **v1.1**。
- 出力は共有頂点プールに三角ポリゴン群として投入 → Phase D/E の編集がそのまま効く。**一括生成 = Undo 1回**。
- ~~G 本番直前に `_polygonEdgeGraph` / `_shortestBoundaryPath` / `_absorbVerticesAlongNewSegment` / `_collapseConsecutive*` を `geometry/` または `services/artwork/` へ純関数抽出（G の境界溶接再利用。計画 2026-07-10 メモと整合）。~~ → **完了済み**（2026-07-14 commit `13836db`）。`buildPolygonEdgeGraph`/`findShortestBoundaryPath`（`lib/geometry/polygon_graph.dart`）、`findVerticesAlongSegment`（`lib/geometry/line_absorption.dart`）、`collapseConsecutiveRingIds`/`collapseConsecutiveOpenIds`/`hasNonConsecutiveDuplicate`（`lib/geometry/ring_collapse.dart`）として存在。
- ドロネーは G-spike Go 時のみ Tier B。No-Go 時は Tier C（ドロネーなし）。
- **重い三角分割は `compute()`（Isolate）で実行し、計算中は画面にローディングインジケータを表示する**（#17）。失敗時は Artwork 不変 + ユーザー通知。

~~**完了条件**: 閉じた輪郭の内部が三角メッシュで埋まり、生成後に頂点編集できる。**計算中は UI が固まらずローディング表示が出る（重い図形でも ANR が起きない）**。既定間隔で実機確認（顔・シンプルなイラスト等の代表例）。`flutter analyze` / `flutter test` パス。~~
**完了条件**: 相談で確定した `maxEdge`/`minEdge` で、閉曲線内部が三角メッシュで埋まり、**max 超え三角が実用上残らない**。生成後に頂点編集可。計算中 UI フリーズなし（#17）。顔・シンプルなイラスト等で実機確認。`flutter analyze` / `flutter test` パス。

## 着手前チェックリスト（G 本番直前）

- [x] 境界グラフ・吸着・リング畳みの純関数抽出（#6）（2026-07-14 commit `13836db` にて完了。`lib/geometry/polygon_graph.dart`／`line_absorption.dart`／`ring_collapse.dart` へ抽出済み。単体テストは 2026-07-20 `test/geometry/polygon_graph_test.dart`／`line_absorption_test.dart`／`ring_collapse_test.dart` で追加済み）
- [x] G 入力サニタイズ方針（#8）（2026-07-20 実装完了。`lib/geometry/tessellation_input.dart`（`sanitizeTessellationBoundary`/`weldCoincidentRingVertices`）＋ `lib/geometry/self_intersection.dart`（`segmentsIntersect`/`isSelfIntersectingRing`）。coincident-but-unwelded は正規化（自動溶接）、自己交差ポリゴンは弾く方針。単体テストは `test/geometry/tessellation_input_test.dart`／`self_intersection_test.dart`）
- [x] 当たり判定のインターフェース切り出し（#10）（2026-07-20 実装完了。`lib/geometry/vertex_hit_test.dart` に `VertexHitTest`／`LinearVertexHitTest` を新設し、`CanvasNotifier` の `_findPolygonVertexNearIn`／`findVertexNear` を差し替え。内部実装は既存の O(n) 線形探索のまま。単体テストは `test/geometry/vertex_hit_test_test.dart`）
- [ ] バッチ polygon insert + Undo 1回の API
- [x] `compute()` 経由のテッセレーション呼び出し + ローディングUI実装（#17）（2026-07-20 実装完了。`lib/services/tessellation_service.dart`（`TessellationRequest`/`TessellationResult`/`triangulate`、Isolate に渡すトップレベル関数。`triangulate` 本体は次回のアルゴリズム実装まで `UnimplementedError`）＋ `lib/providers/tessellation_provider.dart`（`isTessellatingProvider`／`TessellationController.tessellate`、`compute()` 起動と成否ハンドリング）。`CanvasNotifier.commitTessellationResult` で境界頂点ID再利用＋Undo1回コミット。`lib/screens/editor_screen.dart` に `_TessellationBlockingOverlay`（`AbsorbPointer`＋ローディング表示）を追加。単体テストは `test/services/tessellation_service_test.dart`／`test/canvas_notifier_tessellation_test.dart`／`test/providers/tessellation_provider_test.dart`）
- [ ] **`maxEdge` / `minEdge` の world 値を実機相談で確定してから実装**（#20）

→ その他フェーズの着手前チェックリストは [plan_future_phases.md](plan_future_phases.md) の「着手前チェックリスト（統合、G を除く）」を参照。

## 追加すべきテスト（G関連）

[plan_future_phases.md](plan_future_phases.md) の「追加すべきテスト（優先度付き）」全体のうち、G に直接関連する項目のみ抜粋（全項目は同ファイルを参照）:

- `compute()` ラッパーが Isolate 経由でも正しい結果を返すこと（#17）
- テッセレーション出力で maxEdge 超え辺が残らないこと（#20、仮値可）

## 検討メモ（直近）

（まだなし。Phase G 着手後の検討・実装内容をここに追記していく。）
