# Phase Select: 図形タップ選択（Hit-Testing）＋彩色基盤

> **正本の位置づけ**: 全体像・確定した設計判断・品質方針・リリース要件は [ポリゴンアプリ再設計_e54196e6.plan.md](ポリゴンアプリ再設計_e54196e6.plan.md)（マスター）を参照。未着手フェーズ（Hδ / R）の詳細・技術的負債表・テスト方針・リスクと対策は [plan_future_phases.md](plan_future_phases.md) を参照。完了済みフェーズの実装済み仕様・過去の検討メモは [plan_archive_history.md](plan_archive_history.md) を参照。着手時の進捗・次ステップは下記 **現在のステータス** を参照。
> **運用**: 本ファイルは「現在着手中のフェーズ」専用ファイル。ファイル名にフェーズ名を含める（`plan_phase_<フェーズ>.md`）運用とし、Select が完了し次のフェーズ（Hδ）に進んだら、本ファイルの中身を Hδ の詳細（[plan_future_phases.md](plan_future_phases.md) から該当セクションを移動）に差し替え、ファイル名も `plan_phase_H_delta.md` にリネームして使い続ける（Hα → Hβ → F → G → Hγ → Select でこの運用を継続、2026-08-03）。Select 完了時の実装完了メモ・検討メモは、差し替え時に [plan_archive_history.md](plan_archive_history.md) へ移す。Phase 完了コミット後は **現在のステータス** を次 Phase 用に更新する。

## 📍 現在のステータス (2026-08-03)

- **完了フェーズ**: Phase A〜E+・G-spike・Hα・Hβ・F・G・**Hγ** がすべて完了。Hγ（保存・作品一覧）は `ArtworkDocument` v1・下絵実体コピー・AutoSave／ギャラリー統合・タスクキル復帰／破損 JSON スキップの実機検証まで完了（[plan_archive_history.md](plan_archive_history.md) の「検討メモ（Hγ）」参照）。
- **現在のフェーズ**: Phase Select（図形タップ選択＋彩色基盤）**着手中**。
- **次フェーズ**: Select 完了後 → Phase Hδ（PNG エクスポート）→ Phase R。

## Phase Select: 図形タップ選択（Hit-Testing）＋彩色基盤（重要）

> **位置づけ**: 従来は v1.1（スタイル／パレット周辺）に含めていた「任意の図形を直接タップして選ぶ」能力を、**保存（Hγ）の前または並行**で着手する重要マイルストーンとして前倒ししていた（2026-07-27）。Hγ 完了後の本ファイルが正本。トグル巡回（`resolvePolygonTarget`）だけではテッセレーション後の多数三角形を扱う操作が破綻しやすい。彩色アルゴリズムや選択モード UI の土台にもなる。

**Hit-Testing（当たり判定）**

- タップのワールド座標に対し、確定ポリゴンの内部判定（既存の `isPointInPolygon` を再利用）。
- **AABB 事前フィルタ**: まず各ポリゴンの軸平行バウンディングボックスで候補を絞り、通過したものだけ Point-in-Polygon（O(n) 全頂点走査の緩和。将来の空間インデックス差し替えは #10 の `VertexHitTest` 方針と整合）。
- **Z-Order（重なり）**: 複数ポリゴンがヒットした場合は **描画上の最前面**（現行は `Artwork.polygons` の後ろほど手前、と実装／テストで固定する）を優先選択。
- 頂点ヒット（既存の `findVertexNear` / 編集モード）との優先順位: 頂点ハンドル近傍は従来どおり頂点選択を優先し、空白に近い塗り領域タップで図形選択、など衝突ルールを仕様化してテスト固定。

**選択階層の整理**

- **第1層（図形）**: キャンバスを直接タップ → Hit-Testing で対象ポリゴン ID を確定（`polygonCycleIndexProvider` 相当のターゲットをタップ結果でセット／ハイライト）。
- **第2層（辺）**: 図形が選ばれたあと、その内部の辺選択は **既存のトグル式**（`edgeCycleIndexProvider` / 「辺を切り替え」）を連携継続。辺トグルの候補集合は「今選ばれている図形の辺」に限定（現行 `_NoSelectionRow` と同じ解決関数を再利用）。
- 図形未選択時の「図形を切り替え」トグルは残してよい（タップ不能な微小図形・アクセシビリティ用）が、**主操作はタップ選択**とする。

**彩色基盤（最小）**

- 選択中ポリゴンに対する塗り色変更の入口（既存パレット／`selectedFillColorProvider` との接続方針を決める）。本格グラデ・スポイトは引き続き v1.1。
- 選択状態は session-only（永続化は Hγ の `ArtworkDocument` と混ぜない）。Undo は「色変更 1 操作 = 1 エントリ」など既存 D0 パターンに合わせる。

**完了条件**: 重なり合う複数図形をタップで最前面優先選択できる。選択後に辺トグル・既存の図形削除／テッセレーション対象指定が同じターゲットを指す。AABB + PIP の単体テスト、Z-Order のウィジェット／ロジックテスト。

**Hγ との関係**: 保存スキーマ自体は Select に依存しない。Hγ は完了済み。本フェーズは編集・彩色 UX の土台として単独完走する。

## 着手前チェックリスト（Select）

- [ ] Point-in-Polygon + AABB 事前フィルタの純関数（単体テスト）
- [ ] Z-Order（最前面優先）の仕様固定とロジック／ウィジェットテスト
- [ ] 頂点ヒット vs 図形塗りヒットの優先順位をテストで固定
- [ ] タップ選択 → 既存辺トグル／図形削除／テッセレーション対象とのターゲット連携
- [ ] 彩色の最小入口（選択図形の塗り変更 + Undo 1 エントリ）の方針確定

→ その他フェーズの着手前チェックリストは [plan_future_phases.md](plan_future_phases.md) の「着手前チェックリスト（統合、Select を除く）」を参照。

## 追加すべきテスト（Select関連）

[plan_future_phases.md](plan_future_phases.md) の「追加すべきテスト（優先度付き）」全体のうち、Select に直接関連する項目のみ抜粋（全項目は同ファイルを参照）:

- AABB + `isPointInPolygon` の図形ヒット（重なり時は最前面）
- タップ選択と辺トグル／テッセレーション対象のターゲット一致
- 選択図形の塗り変更が Undo 1 回で戻ること（彩色最小入口）

## 検討メモ（直近）

### アーキテクチャ確定仕様（2026-08-04）— Step 3.0

シニアレビューで指摘された死角を塞ぎ、Wave 1〜3 の実装規約を確定した記録。  
**モデル／JSON／`schemaVersion`（`PolygonShape.fillColor` 単色）は変更しない。** 実装着手は本記録の後、別指示で行う。

#### Wave 1〜2 の死角対策（規約の追加）

1. **セーブ処理の重複排除（死角1）**  
   `ArtworkDocument.fromSession` を組み立てて `flush` する処理が `auto_save_provider.dart` と `editor_screen.dart` の2箇所に重複している。ギャラリーへ戻るボタン等でさらに増えるのを防ぐため、ヘルパー（例: `saveAndFlushCurrentDocument(WidgetRef)`）を1箇所に切り出し、各所からそれを呼ぶルールとする。

2. **ナビゲーションの明確化（死角2）**  
   `_SaveAndExitButton` などの「戻る」は現状 `popUntil(isFirst)`（Home へ戻る）だが、Gallery 経由遷移とドキュメントコメントが矛盾しうる。実装前に「戻り先は常に Gallery（存在しなければ push）」か「既存どおり常に Home」かを **1文で仕様確定**し、該当コードのコメントに明記すること。

3. **描画定数の波及範囲（死角3）**  
   頂点ドット縮小時、`_vertexRadius` は選択リング・磁石スナップ・クローズヒント等にも波及する。要望が「編集ハンドルのみ」か「描画中の点も含む」かを確認してから、対象定数（`_continuationHandleRadius` 等）を修正すること。ヒット半径（`kVertexHitRadius`）とは独立。

4. **Wave 3A/3B 厳格ルール**  
   - 彩色 API は対象を **ID 渡し**とする（例: `CanvasNotifier.setPolygonFillColor(String polygonId, Color color)`）。セッションプロバイダを Notifier 内で直接読ませない。  
   - 辺ヒットの純関数は新規ファイルを作らず、`polygon_hit_test.dart` に追記して正本を保つ。  
   - テストは「頂点 > 辺 > 塗り」の優先順位を widget test で **先に赤にしてから**実装する。  
   - **Wave 3C（辺維持）は今回見送る**（状態管理を増やさない判断）。

#### Wave 3（彩色・距離ベースシェーディング）確定仕様

単一図形内の Shader グラデーションではなく、**複数ポリゴンへの距離ベース単色シェーディング（バッチ塗り）**。`fillColor` 一括更新のみ。Undo はバッチ前 `_recordUndo()` 1回。

1. **モードとツールの分離**  
   - `CanvasMode.shade` を新設。ツールバーで `ShadeTool`: `solid` / `select` / `light` を切り替える（`DrawMode` と同型のサブツール）。  
   - `solid`: タップした1図形に現在色を即適用（1タップ = Undo 1回）。  
   - `select`: タップまたはなぞり（ドラッグ）で対象図形を Set に追加（add-only）。  
   - `light`: 選択範囲内の図形を1つタップし、起点として距離グラフ計算→グラデーション色をバッチ適用。生成ランプ（5〜6色）を UI に展開し、`solid` で手直し可能にする。

2. **状態管理とジェスチャー（既存規約の遵守）**  
   - 高頻度（〜60fps）で更新するドラッグ選択状態を `StateProvider` に置くことは **禁止**。  
   - `SelectionDragController extends ValueNotifier<Set<String>>` を新設し、`PolygonPainter` が `repaint` ソースとして直接監視する（`DragPreviewController` 等と同列）。  
   - ドラッグ中の選択は「プレビューして離した時にコミット」ではなく、**その場で即座に Set へ add**する（2本指混入で選択が消える事故を防ぐ）。  
   - 1本指 = 選択ブラシ、2本指 = パン/ピンチ。既存の `onScale*` + `ViewportGestureBaseline` / `hadMultiFinger` サブサイクルに載せる（新規ジェスチャー機構は作らない）。  
   - `polygonCycleIndexProvider`（edit 単一ターゲット）とは **完全分離**。Shade 中は辺トグル等の単一ターゲット UI を更新しない。

3. **モード離脱時のライフサイクル管理**  
   状態残留防止のため、`SelectionDragController` と `lastShadingRamp`（および関連 Shade session 状態）のクリアを、次の **2箇所に明示的に直書き**する（共有ヘルパー任せで漏れないこと）:  
   1. `lib/widgets/toolbar/editor_toolbar.dart` の `selectMode`  
   2. `lib/providers/gallery_provider.dart` の作品 Open / New 時  
   あわせて Row0 の `SegmentedButton<CanvasMode>` の `selected` 判定が Draw/Edit の2値フォールバックのままにならないよう、Shade 追加時に直す。

4. **ヒットテストとエッジケース**  
   - **頂点ヒット無効化**: Shade モード中は頂点ハンドルを非表示にし、タップ判定は `findPolygonContaining` のみとする。  
   - **no-op**: `light` で選択 Set 外をタップした場合は何も起きない。  
   - **非連結図形**: 共有頂点ベースの隣接グラフで光源から BFS 到達できない図形は Map に含めず、既存 `fillColor` を維持する（ベース色で上書きしない）。  
   - **`hadMultiFinger` UX**: 2本指パン直後に1本指へ戻っても、同一物理ジェスチャー内では選択ブラシが再開されない挙動は **仕様として許容**する。  
   - 隣接定義: 選択 Set 内で `vertexIds` 交差が非空なら隣接。ランプは先に 5〜6色生成し、`distance → ramp[min(distance, rampStops-1)]` で割当。

5. **ハイライトの疎結合**  
   - `PolygonHighlightStyle` を導入。有彩色・破線は使わず **alpha（透過度）変更のみ**で選択状態を描画する。見た目定数はコア／純関数から参照しない。差し替えはこのスタイル（および必要なら小さな描画ヘルパー）に閉じる。

6. **コア API（実装時の境界）**  
   - 純関数 `computeDistanceShading` → `ShadingResult(colorsByPolygonId, ramp)`（provider 非依存）。  
   - `CanvasNotifier.applyPolygonColors(Map<String, Color>)` — `_recordUndo()` 1回のあと一括 `copyWith(fillColor: …)`。未知 ID は無視、変化なしなら no-op。  
   - パレット: Shade 中のスウォッチタップは `selectedFillColorProvider` の更新のみ（即時塗りしない）。手動適用は `solid` で図形タップ。

#### 実装ステップ（記録・未着手）

| Step | 内容 |
|------|------|
| 3.0 | 本エントリ（仕様固定）— **完了** |
| 3.1 | `computeDistanceShading` + 単体テスト |
| 3.2 | `applyPolygonColors`（Undo 1回） |
| 3.3 | `CanvasMode.shade` / `ShadeTool` / `SelectionDragController` / ramp + クリア2箇所 |
| 3.4 | `PolygonHighlightStyle` + Painter（Set / repaint） |
| 3.5 | ツールバー（Row0 Shade、Row1 3ツール、Row2 既定＋生成ランプ） |
| 3.6 | キャンバス入力（solid / select / light、既存 onScale*） |
| 3.7 | 結合（光源→バッチ→ランプ→solid 手直し、Undo 回帰） |

Wave 1〜2（セーブヘルパー・ナビ仕様確定・描画定数・Select ヒットテスト基盤）は上記規約に従い、Wave 3 本体より前または並行で進める。
