# Phase Select: 図形タップ選択（Hit-Testing）＋彩色基盤

> **正本の位置づけ**: 全体像・確定した設計判断・品質方針・リリース要件は [ポリゴンアプリ再設計_e54196e6.plan.md](ポリゴンアプリ再設計_e54196e6.plan.md)（マスター）を参照。未着手フェーズ（Hδ / R）の詳細・技術的負債表・テスト方針・リスクと対策は [plan_future_phases.md](plan_future_phases.md) を参照。完了済みフェーズの実装済み仕様・過去の検討メモは [plan_archive_history.md](plan_archive_history.md) を参照。着手時の進捗・次ステップは下記 **現在のステータス** を参照。
> **運用**: 本ファイルは「現在着手中のフェーズ」専用ファイル。ファイル名にフェーズ名を含める（`plan_phase_<フェーズ>.md`）運用とし、Select が完了し次のフェーズ（Hδ）に進んだら、本ファイルの中身を Hδ の詳細（[plan_future_phases.md](plan_future_phases.md) から該当セクションを移動）に差し替え、ファイル名も `plan_phase_H_delta.md` にリネームして使い続ける（Hα → Hβ → F → G → Hγ → Select でこの運用を継続、2026-08-03）。Select 完了時の実装完了メモ・検討メモは、差し替え時に [plan_archive_history.md](plan_archive_history.md) へ移す。Phase 完了コミット後は **現在のステータス** を次 Phase 用に更新する。

## 📍 現在のステータス (2026-08-09)

- **完了フェーズ**: Phase A〜E+・G-spike・Hα・Hβ・F・G・**Hγ**・**Select** がすべて完了。Hγ（保存・作品一覧）は `ArtworkDocument` v1・下絵実体コピー・AutoSave／ギャラリー統合・タスクキル復帰／破損 JSON スキップの実機検証まで完了（[plan_archive_history.md](plan_archive_history.md) の「検討メモ（Hγ）」参照）。Select は Hit-Testing／Edit 選択／Shade（3.1〜3.7）まで完走（結合テスト `test/widgets/toolbar/shade_workflow_test.dart` 含む）。`solid` は選択 Set バッチ適用を正式仕様とする。
- **現在のフェーズ**: Phase Select **完了**。運用ルールに従い、次コミット以降で本ファイルを Hδ 用に差し替え・リネームし、Select 完了メモは [plan_archive_history.md](plan_archive_history.md) へ移す。
- **次フェーズ**: Phase Hδ（PNG エクスポート）→ Phase R。

## Phase Select: 図形タップ選択（Hit-Testing）＋彩色基盤（重要）

> **位置づけ**: 従来は v1.1（スタイル／パレット周辺）に含めていた「任意の図形を直接タップして選ぶ」能力を、**保存（Hγ）の前または並行**で着手する重要マイルストーンとして前倒ししていた（2026-07-27）。Hγ 完了後の本ファイルが正本。トグル巡回だけではテッセレーション後の多数三角形を扱う操作が破綻しやすい。彩色アルゴリズムや選択モード UI の土台にもなる。

**Hit-Testing（当たり判定）**

- タップのワールド座標に対し、確定ポリゴンの内部判定（既存の `isPointInPolygon` を再利用）。
- **AABB 事前フィルタ**: まず各ポリゴンの軸平行バウンディングボックスで候補を絞り、通過したものだけ Point-in-Polygon（O(n) 全頂点走査の緩和。将来の空間インデックス差し替えは #10 の `VertexHitTest` 方針と整合）。実装正本は `polygon_hit_test.dart`。
- **Z-Order（重なり）**: 複数ポリゴンがヒットした場合は **描画上の最前面**（現行は `Artwork.polygons` の後ろほど手前、と実装／テストで固定する）を優先選択。`CanvasNotifier.findPolygonContaining` 経由。
- 頂点ヒット（既存の `findVertexNear` / 編集モード）との優先順位: 頂点ハンドル近傍は従来どおり頂点選択を優先し、空白に近い塗り領域タップで図形選択。Edit では図形選択後に辺ヒット（`findNearestRingEdgeIndex`）へドリルダウン。

**選択階層の整理**

- **第1層（図形）**: キャンバスを直接タップ → Hit-Testing で対象ポリゴンを確定。インデックスは `editSelectionProvider`（旧 `polygonCycleIndexProvider` は廃止・統合済み）。解決結果は `editTargetProvider` が単一ソース。
- **第2層（辺）**: 図形が選ばれたあと、辺タップまたはトグルで `editSelectionProvider.edgeIndex` を更新。辺候補は「今選ばれている図形の辺」に限定。
- 図形未選択時の「図形を切り替え」トグルは残す（タップ不能な微小図形・アクセシビリティ用）が、**主操作はタップ選択**とする。

**彩色基盤（最小）**

- Edit: ターゲット図形に対するパレット塗り（`changePolygonColor` → Undo 1 エントリ）。
- Shade: `selectedFillColorProvider` はペン色のみ更新。塗り適用は `ShadeTool.solid` / `light` が `applyPolygonColors` で行う。本格グラデ・スポイトは引き続き v1.1。
- 選択状態は session-only（永続化は Hγ の `ArtworkDocument` と混ぜない）。

**完了条件**: 重なり合う複数図形をタップで最前面優先選択できる。選択後に辺トグル・既存の図形削除／テッセレーション対象指定が同じターゲットを指す。AABB + PIP の単体テスト、Z-Order のウィジェット／ロジックテスト。

**Hγ との関係**: 保存スキーマ自体は Select に依存しない。Hγ は完了済み。本フェーズは編集・彩色 UX の土台として単独完走する。

## 着手前チェックリスト（Select）

- [x] Point-in-Polygon + AABB 事前フィルタの純関数（単体テスト）
- [x] Z-Order（最前面優先）の仕様固定とロジック／ウィジェットテスト
- [x] 頂点ヒット vs 図形塗りヒットの優先順位をテストで固定
- [x] タップ選択 → 既存辺トグル／図形削除／テッセレーション対象とのターゲット連携
- [x] 彩色の最小入口（選択図形の塗り変更 + Undo 1 エントリ）の方針確定

→ その他フェーズの着手前チェックリストは [plan_future_phases.md](plan_future_phases.md) の「着手前チェックリスト（統合、Select を除く）」を参照。

## 追加すべきテスト（Select関連）

[plan_future_phases.md](plan_future_phases.md) の「追加すべきテスト（優先度付き）」全体のうち、Select に直接関連する項目のみ抜粋（全項目は同ファイルを参照）:

- [x] AABB + `isPointInPolygon` の図形ヒット（重なり時は最前面）
- [x] タップ選択と辺トグル／テッセレーション対象のターゲット一致
- [x] 選択図形の塗り変更が Undo 1 回で戻ること（彩色最小入口）
- [x] Shade 結合: select → light → solid 手直し → Undo 回帰（`shade_workflow_test.dart` / Step 3.7）

## 検討メモ（直近）

### アーキテクチャ確定仕様（2026-08-04）— Step 3.0

シニアレビューで指摘された死角を塞ぎ、Wave 1〜3 の実装規約を確定した記録。  
**モデル／JSON／`schemaVersion`（`PolygonShape.fillColor` 単色）は変更しない。**  
※ 下記「実装ステップ」のとおり、Wave 3 のコード実装は Step 3.1〜3.6 まで完了済み（2026-08-09 時点のコード事実に同期）。

#### UI言語のグローバル規約（v1.0）

v1.0 における UI 言語（Tooltip、SemanticLabel、SnackBar、ダイアログ本文、ボタンラベルなど、**ユーザーの目に触れる全テキスト**）はすべて **英語** で実装すること。日本語対応など多言語化は v1.1 以降とする。現段階で日本語の文字列をハードコードすることは固く禁ずる（コード内コメント・計画書の日本語は対象外）。

#### Wave 1〜2 の死角対策（規約の追加）

1. **セーブ処理の重複排除（死角1）** — **実装済み**  
   `saveAndFlushCurrentDocument(EditorSessionRead)`（`auto_save_provider.dart`）に集約。auto-save と Editor の明示 flush（Home / Gallery 退出）がこれを呼ぶ。

2. **ナビゲーションの明確化（死角2）** — **実装済み**  
   退出は **Home** と **Gallery** の二ボタン。Home は常に `popUntil(isFirst)`。Gallery はスタック上に Gallery ルートがあればそこまで `popUntil`、無ければ root へ戻してから Gallery を push（`editor_screen.dart` に明記）。

3. **描画定数の波及範囲（死角3）** — **今回は見送り（現状維持）**  
   頂点ドット縮小（`_vertexRadius` / `_continuationHandleRadius` 等）は要望確認待ちだったが、**Select では着手しない**。ヒット半径（`kVertexHitRadius`）とは独立のまま、現行の描画定数を維持する。将来の UX 調整フェーズで再検討する。

4. **Wave 3A/3B 厳格ルール**  
   - 彩色 API は対象を **ID 渡し**とする（実装: `changePolygonColor` / `applyPolygonColors`）。セッションプロバイダを Notifier 内で直接読ませない。  
   - 辺ヒットの純関数は新規ファイルを作らず、`polygon_hit_test.dart` に追記して正本を保つ。  
   - テストは「頂点 > 辺 > 塗り」の優先順位を widget test で固定。  
   - **Wave 3C（辺維持）は今回見送る**（状態管理を増やさない判断）。

#### Wave 3（彩色・距離ベースシェーディング）確定仕様

単一図形内の Shader グラデーションではなく、**複数ポリゴンへの距離ベース単色シェーディング（バッチ塗り）**。`fillColor` 一括更新のみ。Undo はバッチ前 `_recordUndo()` 1回。

1. **モードとツールの分離**  
   - `CanvasMode.shade` を新設。ツールバーで `ShadeTool`: `solid` / `select` / `light` を切り替える（`DrawMode` と同型のサブツール）。  
   - **`solid`（現行コードの事実）**: ジェスチャー終了時に、現在の選択 Set（`SelectionDragController`）**全体**へ `selectedFillColorProvider` の色を `applyPolygonColors` で一括適用（Undo 1回）。選択が空なら no-op。適用後に選択を clear。※ 当初案の「タップした1図形に即適用」とは異なる。UX の最終方針は別途決定する。  
   - `select`: タップまたはなぞり（ドラッグ）で対象図形を選択／解除。**ストローク極性**（Wave 3.2.1）: そのストローク内で**最初にヒットした図形**の状態で Add/Remove を固定する。空白開始はヒットまで極性未決定（図形に触れるまで no-op）。選択済み開始 → Remove、未選択開始 → Add。ストローク中にモード反転しない。Select 中はオート X-Ray（塗り透過）で下絵／重なりを視認しやすくする。  
   - 全解除ボタン: Shade ツールバー（Row 1）右端に配置。アイコンは **`Icons.deselect`**、tooltip `"Clear selection"`。選択 Set が空のときは非活性。  
   - `light`: 選択範囲内の図形を1つタップし、起点として距離グラフ計算→グラデーション色をバッチ適用（`computeDistanceShading` → `applyPolygonColors`）。クリア色（`kClearFillColor`）をベースにした light は no-op。手直しはパレット（アコーディオン）＋ `solid`。

2. **状態管理とジェスチャー（既存規約の遵守）**  
   - 高頻度（〜60fps）で更新するドラッグ選択状態を `StateProvider` に置くことは **禁止**。  
   - `SelectionDragController extends ValueNotifier<Set<String>>` を新設し、`PolygonPainter` が `repaint` ソースとして直接監視する（`DragPreviewController` 等と同列）。`add` / `remove` は**変化があったときだけ** notify（死角 C 回避）。  
   - ドラッグ中の選択変更は「プレビューして離した時にコミット」ではなく、**その場で即座に Set へ add/remove**する（2本指混入で選択が消える事故を防ぐ）。  
   - **マルチセレクトのストローク極性**（Wave 3.2.1）: 最初のヒットで Add/Remove を固定。空白開始はヒットまで極性未決定。2本指混入時は極性を破棄し既存パン／ズームへ切替。  
   - 1本指 = 選択ブラシ、2本指 = パン/ピンチ。既存の `onScale*` + `ViewportGestureBaseline` / `hadMultiFinger` サブサイクルに載せる（新規ジェスチャー機構は作らない）。  
   - Edit 単一ターゲット（`editSelectionProvider`）とは **完全分離**。Shade 中は辺トグル等の単一ターゲット UI を更新しない。

3. **モード離脱時のライフサイクル管理**  
   状態残留防止のため、`clearShadeSessionUi` が `SelectionDragController` の clear と **`activeBaseColorProvider`（アコーディオン・アンカー）の null 化**を行う。呼び出しは次の **2箇所に明示**する:  
   1. `lib/widgets/toolbar/editor_toolbar.dart` の `selectMode`（Shade 以外へ切替時）  
   2. `lib/providers/gallery_provider.dart` の作品 Open / New 時  
   ※ 旧案の `lastShadingRampProvider`（Light 適用後のランプ事後保存）は **廃止済み**。代わりに Shade パレットは `activeBaseColorProvider` を基準に、選択した基本色の直前（左）に明るい1段・直後（右）に暗い数段を **インライン挿入（アコーディオン展開）**する。初期状態は未展開（`null`）。ベース色判定は `kDefaultPolygonPalette.contains(color)` のみ。  
   Row0 の `SegmentedButton<CanvasMode>` は Draw / Edit / Shade の3値を正しく扱う。

4. **ヒットテストとエッジケース**  
   - **頂点ヒット無効化**: Shade モード中は頂点ハンドルを非表示にし、タップ判定は `findPolygonContaining` のみとする。  
   - **no-op**: `light` で選択 Set 外をタップした場合は何も起きない。  
   - **非連結図形**: 共有頂点ベースの隣接グラフで光源から BFS 到達できない図形は Map に含めず、既存 `fillColor` を維持する（ベース色で上書きしない）。  
   - **`hadMultiFinger` UX**: 2本指パン直後に1本指へ戻っても、同一物理ジェスチャー内では選択ブラシが再開されない挙動は **仕様として許容**する。  
   - 隣接定義: 選択 Set 内で `vertexIds` 交差が非空なら隣接。ランプは先に 5〜6色生成し、`distance → ramp[min(distance, rampStops-1)]` で割当。コントラスト強化として gamma / 決定論的 lightness jitter（現行 `kShadingLightnessJitter = 0.7`）を適用。

5. **ハイライトの疎結合**  
   - `PolygonHighlightStyle` を導入。有彩色・破線は使わず **alpha（透過度）変更のみ**で選択状態を描画する。見た目定数はコア／純関数から参照しない。差し替えはこのスタイル（および必要なら小さな描画ヘルパー）に閉じる。塗り自体の intrinsic alpha は chrome alpha と乗算（`blendFillChromeAlpha`）。クリア塗り（alpha 0）は `drawPath` をスキップ。

6. **コア API（実装時の境界）**  
   - 純関数 `computeDistanceShading` → `ShadingResult(colorsByPolygonId, ramp)`（provider 非依存）。パレット用の左右展開は `buildAccordionPaletteExpansion`。  
   - `CanvasNotifier.applyPolygonColors(Map<String, Color>)` — `_recordUndo()` 1回のあと一括 `copyWith(fillColor: …)`。未知 ID は無視、変化なしなら no-op。  
   - パレット: Shade 中のスウォッチタップは `selectedFillColorProvider` の更新のみ（即時塗りしない）。基本6色タップ時のみ `activeBaseColorProvider` も更新してアコーディオンを展開。手動の一括塗り適用は `solid`（選択 Set バッチ）。`FillColorPalette` は `ListView.separated` + 役割ベース `Key` + 二段階スクロール（`ensureVisible`、未構築時は粗い `animateTo` フォールバック）。

#### 実装ステップ（記録・進捗同期 2026-08-09）

| Step | 内容 | 状態 |
|------|------|------|
| 3.0 | 本エントリ（仕様固定） | **完了** |
| 3.1 | `computeDistanceShading` + 単体テスト | **実装完了** |
| 3.2 | `applyPolygonColors`（Undo 1回） | **実装完了** |
| 3.3 | `CanvasMode.shade` / `ShadeTool` / `SelectionDragController` / session クリア2箇所（現行は `activeBaseColorProvider`） | **実装完了** |
| 3.2.1 | UX改善: ストローク極性 + `remove` + 全解除（`Icons.deselect`） | **実装完了** |
| 3.4 | `PolygonHighlightStyle` + Painter（Set / repaint / X-Ray） | **実装完了** |
| 3.5 | ツールバー（Row0 Shade、Row1 3ツール＋全解除、Row2 クリア＋既定＋アコーディオン） | **実装完了** |
| 3.6 | キャンバス入力（solid バッチ / select 極性 / light、既存 onScale*）＋パレット ListView 二段階スクロール | **実装完了** |
| 3.7 | 結合（光源→バッチ→アコーディオン手直し→solid、Undo 回帰テスト／フェーズクローズ） | **完了**（`shade_workflow_test.dart`） |

Wave 1〜2（セーブヘルパー・ナビ仕様確定・Select ヒットテスト基盤）は上記のとおり実装済み。描画定数（死角3）は **見送り（現状維持）**。`solid` の選択 Set バッチ適用は正式仕様として維持。
