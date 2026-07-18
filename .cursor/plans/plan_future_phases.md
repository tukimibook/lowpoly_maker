# 未来フェーズ仕様・技術的負債・検討メモアーカイブ

> **正本の位置づけ**: 全体像・確定した設計判断・品質方針・リリース要件は [ポリゴンアプリ再設計_e54196e6.plan.md](ポリゴンアプリ再設計_e54196e6.plan.md)（マスター）を参照。現在着手中のフェーズ（F）の詳細・着手前チェックリストは [plan_phase_F.md](plan_phase_F.md) を参照。着手時の進捗・次ステップは同ファイル冒頭の **現在のステータス** を参照。完了済みフェーズ（A〜E+、G-spike、Hα、Hβ）の実装済み仕様と、過去（2026-07-10〜07-17）の検討メモは [plan_archive_history.md](plan_archive_history.md) を参照（2026-07-17、コンテキスト肥大化防止のため本ファイルから分離）。
>
> 本ファイルには **未着手フェーズ（G/Hγ/Hδ/R）の詳細仕様**、**コード品質・技術的負債表**、**テスト方針**、**リスクと対策**を格納する。完了済みフェーズの仕様・過去の検討メモは本ファイルには置かない（[plan_archive_history.md](plan_archive_history.md) が正本）。F の詳細も本ファイルには置かない（[plan_phase_F.md](plan_phase_F.md) が正本）。

## 完了済みフェーズ仕様

> 完了済みフェーズ（A〜E+、G-spike、Hα、Hβ）の実装済み仕様は [plan_archive_history.md](plan_archive_history.md) の「完了済みフェーズ仕様（アーカイブ）」に隔離しました。現在着手中の詳細は [plan_phase_F.md](plan_phase_F.md) を参照してください。

## 未着手フェーズ仕様

### Phase F: なぞりモード

> **現在着手中のため本ファイルには詳細を置かない。現在着手中の詳細は [plan_phase_F.md](plan_phase_F.md) を参照してください。**

### Phase Hα: 下絵（背景画像）（完了）

> **完了済み（2026-07-17）。詳細仕様は [plan_archive_history.md](plan_archive_history.md) の「完了済みフェーズ仕様（アーカイブ）」に隔離しました。**

### Phase Hβ: ズーム / パン UI（完了）

> **完了済み（2026-07-17）。詳細仕様は [plan_archive_history.md](plan_archive_history.md) の「完了済みフェーズ仕様（アーカイブ）」に隔離しました。**

### Phase G: 自動テッセレーション（三角・幾何学ローポリ）

> **着手前提（必須）**: G-spike 完了（Go、Tier B 確定済み） + 下記コード品質節の G 本番直前チェック + **maxEdge/minEdge の world 値を実装前に相談で確定**（#20）。→ 検討メモ（2026-07-13・2026-07-14 追記続き4・2026-07-15、下記アーカイブ）参照。

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
- G 本番直前に `_polygonEdgeGraph` / `_shortestBoundaryPath` / `_absorbVerticesAlongNewSegment` / `_collapseConsecutive*` を `geometry/` または `services/artwork/` へ純関数抽出（G の境界溶接再利用。計画 2026-07-10 メモと整合）。
- ドロネーは G-spike Go 時のみ Tier B。No-Go 時は Tier C（ドロネーなし）。
- **重い三角分割は `compute()`（Isolate）で実行し、計算中は画面にローディングインジケータを表示する**（#17）。失敗時は Artwork 不変 + ユーザー通知。

~~**完了条件**: 閉じた輪郭の内部が三角メッシュで埋まり、生成後に頂点編集できる。**計算中は UI が固まらずローディング表示が出る（重い図形でも ANR が起きない）**。既定間隔で実機確認（顔・シンプルなイラスト等の代表例）。`flutter analyze` / `flutter test` パス。~~
**完了条件**: 相談で確定した `maxEdge`/`minEdge` で、閉曲線内部が三角メッシュで埋まり、**max 超え三角が実用上残らない**。生成後に頂点編集可。計算中 UI フリーズなし（#17）。顔・シンプルなイラスト等で実機確認。`flutter analyze` / `flutter test` パス。

### Phase H+: 保存・エクスポート（v1 必須分）と v1.1 以降

#### ~~旧仕様（2026-07-13 前）~~

~~既存計画の以下を **G の後に一括接続**: グリッド表示/スナップ、下絵取込、ピンチズーム/パン UI、スタイル/グラデ/パレット、保存・作品一覧、PNG + SVG エクスポート、仕上げ。下絵・ズームは G より後ろにまとめていた。~~ → 検討メモ（2026-07-13、下記アーカイブ）参照。

#### 現行仕様（2026-07-13〜）

下絵（Hα）・ズーム（Hβ）を G より前に切り出し。保存・PNG は v1 必須、それ以外は v1.1。

##### Phase Hγ: 保存・作品一覧（v1 必須）

- 形式: **1作品＝1 JSON** + サムネPNG + 索引ファイル。`schemaVersion` は最初から。アトミック書き込み（temp→rename）。
- **★文書データと表示レイアウトの分離**: `Artwork.canvasSize` は端末依存のため、永続 JSON には**幾何データ（`ArtworkDocument`）**として保存し、表示サイズ・下絵 fit は別フィールドまたは復元時に再計算。`schemaVersion` 切る前に設計を固定する。**Undo スナップショットも幾何データのみ**を保持し、`canvasSize` はセッション表示用に外す（分離後も undo が壊れないこと）。
- 下絵: 取り込み時にアプリ内へ画像コピー。作品 JSON はコピーパスを参照。
- 自動保存＋復帰。エンタイトルメント継ぎ目（無料10枚・エクスポート tier）を空実装で用意。
- Undo/Redo: Redo と履歴の永続化は v1.1。v1 は D0 の Undo のみ。

**完了条件**: 作品の保存・一覧・再開・削除。kill 後も復帰。下絵付き作品が壊れない。

##### Phase Hδ: PNG エクスポート（v1 必須）

- 標準 PNG をギャラリー保存（`gal` 等）。下絵なし出力で可。共有シート経由。

#### v1.1 以降（H+ 残り）

グリッド表示/スナップ、スタイル/グラデ/パレット、SVG エクスポート、スポイト、Redo 永続化、一般設定（キャンバス背景・触覚 ON/OFF の永続化）、編集モード UI 文言改善、豪華チュートリアル、仕上げ。

保存（永続化）の設計方針（詳細）:

- 形式: **1作品＝1 JSON ファイル**（`path_provider` のアプリ内ドキュメント領域）＋**サムネイルPNG**＋軽い**索引ファイル**（一覧用メタ）。DB は使わない（データが軽く、JSON方式が単純・堅牢・移行を完全制御できるため）。
- 直列化: モデルは `freezed` だが JSON 化が未実装。`fromJson/toJson` を追加し、`Offset`/`Size`/`Color` 用の**専用コンバータ**を用意。
- 堅牢性: `schemaVersion` ＋マイグレーション、アトミック書き込み（temp→rename）。
- 下絵: 取り込み時に**アプリ内へ画像をコピー保存**し、作品はそのコピーを参照（元写真の削除/移動で下絵が消えるのを防ぐ）。
- タイミング: **自動保存＋復帰**（手動保存ボタン中心にはしない）。
- エクスポート: 無料は標準PNG、プレミアム（透かし無し／高解像度／SVG）はエンタイトルメント（リリース後リワード解放）で制御。SVG 生成はワールド座標基準・ズーム非依存。

一般設定（設定画面にまとめて実装、永続化はここで一括対応）:

- キャンバス背景（ライト/ダーク、Phase B3 で session-only 実装済み → ここで永続化）。
- 触覚フィードバック オン/オフ（Phase C の磁石スナップ吸着時のバイブ）。→ 検討メモ（2026-07-11）参照。強さの多段階選択は作らない（OS側の「タッチ操作時の触覚フィードバック」設定が既にオフスイッチとして機能するため、アプリ内では単純な1個のトグルのみで十分と判断）。

### Phase R: ストア公開準備

- アプリ識別: `applicationId` を独自ID（例 `com.<owner>.polygonart`）へ変更（現 `com.example.polygon_art_app` は公開不可、[android/app/build.gradle.kts](android/app/build.gradle.kts) 19行目）。アプリ名・アイコン・スプラッシュ、バージョニング運用（`versionName`/`versionCode`）。
- 署名: リリース用キーストア作成と署名設定（`key.properties` は git 管理外、鍵はコミットしない。現在は release がデバッグ鍵のまま = 同ファイル 30-32行目）。
- 準拠: Play のターゲットAPIレベル方針に準拠。
- 広告: AdMob バナー実装（ホーム/ギャラリー、テスト↔本番ID切替）。
- 法務/プライバシー: プライバシーポリシー公開＋Play「データ安全」申告、Google UMP 同意フォーム、一般向け(13+)設定、OSSライセンス表示（`showLicensePage`）。
- QA: ユニット/ゴールデンテスト、実機マトリクス確認、空/権限拒否/失敗系（#19）。**統合 smoke フル実行（U2）** を公開前ゲートとする。

## コード品質・修正前提（レビュー統合）

Phase A〜E 完了時点のコードレビュー（2件）を統合した、**着手前に片付ける修正・設計判断**の正本。→ 検討メモ（2026-07-13、下記アーカイブ）参照。

### 維持する設計の核（変更不要）

- 溶接モデル（`Artwork.vertices` 共有プール + ID 参照）
- `ViewportTransform` による座標数学の継ぎ目（`hitRadius / scale`）
- transient / committed 分離（`dragPreviewProvider`、`_lastTapAt` は Undo 対象外）
- `findNearestPoint` の純粋幾何分離
- バグ C・共有境界クローズ・ダイクストラ経路のテスト群

### 直した方がよいこと（技術的負債・修正一覧）

| # | 項目 | 内容 | 着手タイミング |
|---|------|------|----------------|
| 1 | **許容距離の座標系混在** | `kVertexHitRadius` のみ `/scale` 済み。`kDoubleTapMaxDistance`・`kLineAbsorptionTolerance` はワールド固定のまま → ズームでダブルタップ・線上吸着がずれる | **Hβ（ズーム）の前** |
| 2 | **ジェスチャー継ぎ目未着手** | Phase B は座標数学のみ。`polygon_canvas` の `onPan*` とピンチズームは `GestureDetector` で共存不可（assert）→ `onScale*` + `pointerCount` へ書き直し | **Hβ 着手時（最初の作業）** |
| 3 | **F は `handleDrawTap` 再利用禁止** | 点ごと呼び出しだと疑似ダブルタップ誤爆・Undo 爆発・O(n)×点数の jank | **Phase F-core** |
| 4 | **`commitTraceStroke` 契約** | 1ストローク1Undo。疑似ダブルタップを通さない。吸着はバッチ | **Phase F-core** |
| 5 | **Undo スタック上限** | 無制限 `Artwork` スナップショット。G で数千ポリゴン時にメモリ肥大 → 上限（例 50〜100）+ 切り捨て | **E+（完了済み）** |
| 6 | **純幾何の抽出** | `_polygonEdgeGraph` / `_shortestBoundaryPath` / `_absorbVerticesAlongNewSegment` / `_collapseConsecutive*` を `geometry/` 等へ。G の境界溶接再利用 | **G 本番直前** |
| 7 | **`weldVertices` figure-8** | 非連続重複（例 `[A,keep,B,keep,C]`）を `_collapseConsecutiveRingIds` が通す。自己接触ポリゴンが G 入力で破綻 → 弾くか正規化 | **E+（完了済み）** |
| 8 | **G 入力サニタイズ** | 自己交差ポリゴン、`moveVertex` による coincident-but-unwelded（同座標・別 ID）を許容している → G 前に方針決定 | **G 本番直前** |
| 9 | **`Artwork.canvasSize` と保存の分離** | 端末レイアウト依存値を JSON に直列化しない。`ArtworkDocument`（幾何）と表示レイアウトを分ける | **G-spike 完了時（設計確定）／Hγ 着手前（実装）** |
| 10 | **当たり判定 O(n)** | 全頂点走査。G 後にボトルネック → `VertexHitTest` インターフェースを切り、将来空間インデックス差し替え可能に（中身は O(n) のままで可） | **G 本番直前** |
| 11 | **`_isPseudoDoubleTap` の `DateTime.now()`** | テスト制御不能。クロック注入 or ジェスチャー層へ移動を検討 | **F または Hβ**（優先度中） |
| 12 | **消しゴムの共有頂点 UX** | `findPolygonVertexNear` は「最後に走査したポリゴン」が対象。仕様はテストで固定済みだがユーザー向け説明 or 仕様変更を決める | **v1 仕上げ前** |
| 13 | **`closePolygon` 二重 `_recordUndo` リスク** | 現状は問題なし。将来 `closePolygon({bool recordUndo})` 等のガードを検討 | **必要時** |
| 14 | **自己クローズ後の冗長 Undo** | throwaway 点除去により undo 1回が見た目同一状態。バグではないが UX の小さな引っかかり | **低（仕様固定 or 除去）** |
| 15 | **`clearDraft` / `clearAll` の Undo テスト不足** | 実装はあるがテストなし | **E+（完了済み）** |
| 16 | **`detachVertexFromDraft` テスト不足** | polygon 版のみテスト済み | **E+（完了済み）** |
| 17 | **G のANR対策未検討** | 数千三角形規模のドロネー分割をメインスレッド（UIスレッド）で実行すると画面が完全にフリーズし、OSに「応答なし」と判断され強制終了（ANR）される恐れがある → `compute()`（Isolate）への分離実行 + 計算中のローディング表示が必須 | **G-spike／G 本番直前** |
| 18 | **Hα のOOM対策未検討** | 端末カメラの高解像度写真（4K以上）をそのままデコード・展開するとネイティブメモリを圧迫し OOM（メモリ不足）でクラッシュする → 取込時に上限解像度へダウンサンプリング必須 | **Hα** |
| 19 | **保存・取込の失敗系** | 破損 JSON、権限拒否、ディスク満杯、不正画像 → クラッシュせずユーザーに通知 | **Hγ / Phase R QA** |
| 20 | **G 三角サイズ（maxEdge/minEdge）** | ~~spacing 単一~~ → **maxEdge + minEdge（= max × 0.4 固定比率）** で品質定義。v1 UI なし。**world 値は計画時点未確定 → G 着手前に実機相談で確定** | **G-spike（仮値検証）／G 着手前（確定）** |

### 着手前チェックリスト（統合、F を除く）

> **F の着手前チェックリストは [plan_phase_F.md](plan_phase_F.md) を参照**（現在着手中フェーズのため分離）。Hα・Hβ・G-spike の着手前チェックリストは完了済み（[plan_archive_history.md](plan_archive_history.md) 参照）。

**E+（完了済み）**

- [x] Undo スタック上限（#5）
- [x] `weldVertices` figure-8 対策 + テスト（#7）
- [x] `clearDraft` / `clearAll` の Undo テスト（#15）
- [x] `detachVertexFromDraft` テスト（#16）

**G 本番直前**

- [ ] 境界グラフ・吸着・リング畳みの純関数抽出（#6）
- [ ] G 入力サニタイズ方針（#8）
- [ ] 当たり判定のインターフェース切り出し（#10）
- [ ] バッチ polygon insert + Undo 1回の API
- [ ] `compute()` 経由のテッセレーション呼び出し + ローディングUI実装（#17）
- [ ] **`maxEdge` / `minEdge` の world 値を実機相談で確定してから実装**（#20）

**Hγ（保存）の前**

- [ ] `ArtworkDocument` と表示レイアウトの分離**実装**（#9 — 設計は G-spike で確定済みであること）
- [ ] Undo スナップショットが幾何のみであることの確認
- [ ] `schemaVersion` v1 スキーマ確定
- [ ] `applicationId`・署名（Phase R の一部を並行推奨）
- [ ] 統合 smoke チェックリスト草案（U2）

**Phase R QA 前**

- [ ] 統合 smoke **フル実行**（U2）
- [ ] 失敗系（#19）の手動確認

### `canvas_provider` の分割方針

- **複数 Notifier への分割はしない**（`polygons`+`vertices`+`draft` の原子更新が多いため）。
- **純関数抽出を推奨**（効果の高い順）:
  1. 境界グラフ + ダイクストラ + 吸着 + リング畳み込み → `geometry/` または `services/artwork/`
  2. `UndoHistory<Artwork>` クラス（上限・将来 Redo）
  3. ダブルタップ検出のウィジェット層移動（任意）
- F-core: `TracePointGenerator` / `commitTraceStroke` は **notifier 外の純関数 + 薄い facade API**。

## 追加すべきテスト（優先度付き）

> G-spike で検証済みの2項目（`compute()` ラッパー #17、maxEdge 超え辺なし #20、ジッター対策込み）は下記アーカイブ（2026-07-15）に詳細記録。全項目は以下が正本。

**高（E+ / Hβ / G 前）**

- `scale≠1` で `hitRadius / scale` が画面距離一定になること（Hβ で実装済み）
- `kDoubleTapMaxDistance`/`kLineAbsorptionTolerance` の scale 対応（Hβ で実装済み）
- `weldVertices` の非連続重複（figure-8）を弾く/正規化（E+ で実装済み）
- `moveVertex` で同座標・別 ID（自動溶接されない）の明示テスト
- `clearDraft` / `clearAll` の Undo 復元（E+ で実装済み）
- 共有頂点の消しゴム対象ポリゴン（現仕様の固定化 or 変更）
- 画像ダウンサンプリング関数が上限解像度に収まる出力を返すこと（#18）
- `compute()` ラッパーが Isolate 経由でも正しい結果を返すこと（#17）
- テッセレーション出力で maxEdge 超え辺が残らないこと（#20、仮値可）

**中（F-core / G と同時）**

> **F 該当項目は [plan_phase_F.md](plan_phase_F.md) の「追加すべきテスト（F関連）」に移行済み**（`TracePointGenerator`、`commitTraceStroke`、なぞり終了時の close ポリシー、1線分上の複数頂点吸着順序、`absorbVerticesOnSegment` の単体テスト）。G 本番直前チェックリスト（#6 純関数抽出）着手時に、`absorbVerticesOnSegment` 等の共有テストが F 側で既にカバーされているかを確認すること。

**低（v1.1 / QA）**

- painter ゴールデンテスト
- 自己クローズ後の undo 深さ
- `worldToUnderlayPixel`（スポイト実装時）
- Widget test: 描画 pan と zoom の競合

## テスト方針

- ~~純粋幾何（`findNearestPoint`、テッセレーションの点分布・三角分割）はユニットテストを厚く。~~
- ~~座標変換は `CoordinateTransform` に集約してテスト。~~
- 純粋幾何（`findNearestPoint`、テッセレーションの点分布・三角分割、`TracePointGenerator`、抽出した吸着/境界グラフ）はユニットテストを厚く。
- `CanvasNotifier` の溶接・クローズ・編集はロジックテスト。
- 座標変換は `CoordinateTransform` に集約してテスト。**scale≠1 の往復・hitRadius 統合は Hβ 前に必須**（上記コード品質節）。

### 統合 smoke チェックリスト（v1 必須・手動）

ストア体験の一本道（9ステップ）を **1端末で通し切る**。Phase 完了ごとに全項目は不要。**フル実行タイミング**: Hγ 完了時、Phase R QA 前（U2）。

1. 新規 → 4K 級写真を下絵 → OOM しない（#18）
2. ピンチズーム → なぞり → 閉じる → テッセレーション → UI フリーズ/ANR なし（#17）
3. 編集（共有頂点移動）→ Undo 1 回
4. kill → 再起動 → 作品復帰
5. PNG 書き出し → 共有シート
6. 権限拒否時にクラッシュしない（ギャラリー/保存）（#19）
7. 破損 JSON（手動で1ファイル壊す）→ 一覧でスキップ or エラー表示（クラッシュしない）（#19）

※ 自動 E2E は v1.1 検討。v1 は **手動 smoke + `flutter test` CI** でカバー。→ 検討メモ（2026-07-14 追記続き4、下記アーカイブ）参照。

## リスクと対策

- ~~テッセレーションが最重量・依存最多 → 土台（A〜E）安定後に着手（順序で担保）。~~
- ~~ズーム導入時の座標ズレ → Phase B の継ぎ目に全入力/描画/当たり判定を通す。~~
- テッセレーションが最重量・依存最多 → 土台（A〜E）安定後に着手。**G-spike で早期 de-risk**。G 本番直前チェックリストを完了条件に含める。
- ズーム導入時の座標ズレ → Phase B の数学的継ぎ目 + **許容距離の screen px 統一**（#1）。
- **ズームのジェスチャー衝突** → pan/scale 共存不可。Hβ 着手時に `onScale*` 設計を最初に決める（#2）。~~Phase B の継ぎ目だけでは不十分~~（ジェスチャー継ぎ目は未カバーだった）。
- F の `handleDrawTap` 再利用 → 誤爆・Undo 汚染・jank（#3〜4）。`commitTraceStroke` 必須。F-UI は Hβ 後に一度だけ実装。
- 溶接の副作用（動かすと想定外に一緒に動く） → Phase E の detach で回避。消しゴム共有頂点は UX 説明要（#12）。
- **`weldVertices` figure-8** → G 入力退化（#7）。**E+ で前倒し済み**。
- Undo メモリ肥大 → 上限 + F/G のバッチ確定（#5）。**E+ で前倒し済み**。
- 保存フォーマットの後方互換 → `schemaVersion`＋マイグレーション。`canvasSize` を文書データに含めない（#9）。Undo も幾何のみ。
- 収益モデルの後追い変更で反発 → 上限モデル（無料10枚・エクスポートtier）を今固定、既存作品は救済。IAP追加の余地はエンタイトルメントの継ぎ目で確保。
- リリース阻却（公開不可設定） → Phase R で applicationId・リリース署名・同意/プライバシーを確実に対応。Hγ 前後に applicationId を並行推奨。
- O(n) 当たり判定 → G 後に顕在化。インターフェース切り出しで将来対応（#10）。
- **v1 目玉 G が終盤で詰まる** → G-spike を Hα 前に実施。**No-Go なら Tier C**（格子+辺分割）。**Go なら Tier B**（#20）。
- **操作の発見性不足** → ターゲットは「絵が苦手」層。v1 に簡易オンボーディングを意図的に入れる（豪華版は v1.1）。
- **G のANR（画面フリーズ・強制終了）** → 重いテッセレーション計算をメインスレッドで実行しない。`compute()`/Isolate + ローディング表示を必須化（#17）。
- **Hα のOOM（高解像度画像でクラッシュ）** → 取込時に上限解像度へダウンサンプリング必須化（#18）。
- **完成直前の統合停滞** → U1〜U5 のゲート + 統合 smoke（U2）。CI で unit 全通過。
- **G の三角粒度未定（U5）** → world 値は計画時点では決めない。**Hβ・F 実機後、G 着手前に相談で確定**（#20）。

## 検討メモ（過去アーカイブ）

> 過去の実装履歴と検討メモは [plan_archive_history.md](plan_archive_history.md) に隔離しました。現在着手中の詳細は [plan_phase_F.md](plan_phase_F.md) を参照してください。

