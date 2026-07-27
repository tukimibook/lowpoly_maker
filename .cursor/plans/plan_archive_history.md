# 完了済みフェーズ仕様・検討メモ アーカイブ

> **正本の位置づけ**: 全体像・確定した設計判断・品質方針・リリース要件は [ポリゴンアプリ再設計_e54196e6.plan.md](ポリゴンアプリ再設計_e54196e6.plan.md)（マスター）を参照。未着手フェーズ（Hδ/R）の詳細仕様・技術的負債表・テスト方針・リスクと対策は [plan_future_phases.md](plan_future_phases.md) を参照。現在着手中のフェーズの詳細・直近の検討メモは [plan_phase_H_gamma.md](plan_phase_H_gamma.md) を参照。
>
> **運用**: 本ファイルは「完了済みフェーズの実装済み仕様」と「過去の検討メモ」専用のアーカイブ（2026-07-17 新設。[plan_future_phases.md](plan_future_phases.md) が肥大化し、開発チャットでのコンテキスト消費を圧迫していたため分離した）。現在着手中フェーズ（`plan_phase_<フェーズ>.md`）が完了し次フェーズへ差し替わる際、その完了フェーズの「📍 現在のステータス」の完了記録と「検討メモ（直近）」の全内容を、本ファイル末尾へそのまま追記していく運用とする。（2026-07-20 追記: 現在着手中フェーズの正本は [plan_phase_H_gamma.md](plan_phase_H_gamma.md)。）

## 完了済みフェーズ仕様（アーカイブ）

### Phase A: 溶接統一・クローズ簡素化・計測撤去（バグC解消）

対象: [lib/providers/canvas_provider.dart](lib/providers/canvas_provider.dart)

核心: 単発タップの吸着（`findPolygonVertexNear` → `snapDraftEndToExistingVertex`、ID 再利用）は既に溶接として正しく動く。だから **ダブルタップは「再探索せず、そのまま閉じるだけ」** にする。これがバグCの根治。

- `handleDrawTap` のダブルタップ分岐（現 195-197 行）を、`_closeDraftNear` 呼び出しから直接 `closePolygon(fillColor)` に置換する。
  - 理由: 双子タップの1回目が最終頂点を配置（必要なら既存頂点へ溶接）済み。2回目は「閉じる合図」なので、undo も再探索も不要。2回目座標での再探索がバグCの原因だった。
- `_closeDraftNear`（316-384 行）を削除。
- `_lastTapInsertedCount` フィールドと関連ロジック（クローズの undo 用）を削除。`_isPseudoDoubleTap` は時間・距離判定のみ残す（`_lastTapAt` / `_lastTapPosition` は維持）。
- 計測コード一式を撤去: `// #region agent log` 〜 `// #endregion` のブロック全て、`_debugLog`、`_debugPosOf`、`import 'dart:convert'`、`import 'dart:io'`。
- ドックの整合性: `handleDrawTap` / `_handleSingleDrawTap` / `_isPseudoDoubleTap` / `closePolygon` のドキュメントコメントを、非対称ルール廃止・クローズ簡素化に合わせて更新。`findPolygonVertexNear` の「描画時は自分の点に吸着しない（draft 除外）」挙動は維持（自己交差防止のため正しい）。
- テスト更新: [test/canvas_notifier_test.dart](test/canvas_notifier_test.dart) の pseudo double-tap 系テストを新仕様（ダブルタップ=そのまま閉じる／座標コピーではなく既存 ID 溶接を検証）に書き換え。
- 補足確認: Glob 上 `lib/providers/canvas_provider.dart` がパス区切り差で二重表示された。実体が1ファイルであることを確認し、重複ファイルがあれば削除。

完了条件: `flutter analyze` / `flutter test` パス。実機で「B の終点を A の頂点付近に置いてダブルタップ→A に溶接して閉じる（始点に戻らない）」。

### Phase B: 座標変換の継ぎ目（拡大率=1 で先行）

目的: 後からピンチズームを足しても描画・スナップ・編集を書き直さない土台。

- `lib/services/coordinate_transform.dart` を新設: `scale` + `offset` を持つ `ViewportTransform`、`screenToWorld(Offset)` / `worldToScreen(Offset)`。初期は恒等（scale=1）。
- `lib/providers/viewport_provider.dart` を新設: `StateProvider<ViewportTransform>`（初期恒等）。
- [lib/widgets/canvas/polygon_canvas.dart](lib/widgets/canvas/polygon_canvas.dart): `details.localPosition` を `screenToWorld` でワールド化してから notifier に渡す。
- [lib/widgets/canvas/polygon_painter.dart](lib/widgets/canvas/polygon_painter.dart): `canvas.translate/scale` で変換を適用（描画は今のまま world 座標で書ける形に）。
- 当たり判定半径のパラメータ化: `findPolygonVertexNear(Offset, {double hitRadius})` に変更し、呼び出し側で `kVertexHitRadius / transform.scale` を渡す。`kVertexHitRadius` の意味を「画面 px 基準」と明記。

完了条件: 見た目・操作は現状維持（scale=1）で回帰なし。以降のスナップ／編集がすべて継ぎ目経由になっている。

> **未カバー（Hβ で対応）**: 座標**数学**の継ぎ目のみ。ジェスチャー（pan vs ピンチズーム）は Phase C で `onPan*` を導入したため、ズーム UI 追加時に `polygon_canvas` の書き直しが必要（→ 下記「コード品質・修正前提」#2、検討メモ 2026-07-13、下記アーカイブ）。

> 関連: Phase B の実機テストで発覚したクローズ処理の課題については、末尾の検討メモ（2026-07-10）参照。

### Phase C: 磁石スナップ・プレビュー（①ラバーバンド方式）

採用UI: ①ラバーバンド方式（最後に置いた点→プレビュー先端の予告線＋吸着相手のリング強調）。スマホは画面が狭く指が太いため、置く前に接続先が見える保険として有効。②指オフセット・③中央レティクルは精度不足を実機で感じてからの将来オプション。

- 磁石プレビュー（機能#2）: 指ドラッグ中、プレビュー線の先端を最寄り既存頂点（画面 ~55px、Phase B の `/scale` 換算に対応）に吸着表示。`polygon_canvas.dart` に onPanUpdate/onPanEnd（or Listener）を追加し、暫定プレビュー座標を状態（軽量プロバイダ or notifier の transient フィールド）に保持。指を離した位置で確定。
- 描画: `polygon_painter.dart` で「最後の draft 点→プレビュー座標」を薄い/点線で描画し、吸着中は相手頂点にリング強調を出す。吸着判定は `findNearestPoint`（[lib/geometry/nearest_point.dart](lib/geometry/nearest_point.dart)）を再利用。
- 任意: 吸着した瞬間に触覚フィードバック（バイブ、`HapticFeedback`）。低コストで「繋がった感」が上がる。
- 対象外（今回やらない）: 結合時に相手ポリゴンの全頂点を選択色へ変える演出は、大げさで紛らわしいため不採用。頂点は黒のまま。繋がった実感は Phase D（共有点を動かすと両方動く）で担保する。

完了条件: ドラッグ中に近い頂点へピタッと吸い付く予告線が出て、離すとその頂点に溶接される。頂点の色は黒のまま。

> 実装メモ・ジェスチャーモデルの変更点（`onTapDown` 即確定 → `onPanDown`/`onPanUpdate`/`onPanEnd` の指を離した瞬間に確定へ変更）は末尾の検討メモ（2026-07-11）参照。

### Phase D0: 汎用Undoの継ぎ目

目的: Phase D（頂点ドラッグ移動）が「ドラッグ中どう状態を持つか」を決める前に、汎用Undoの土台を先に敷く。Phase B/B3（座標変換・ダークモードの継ぎ目前倒し）と同じ判断: 後から入れると各フェーズの確定ロジックを手直しすることになる★項目のため前倒しする。詳細な相談経緯は末尾の検討メモ（2026-07-11）参照。

- `CanvasNotifier` に **`Artwork` スナップショット方式の Undo スタック**を新設。既存の各確定操作（点を打つ・スナップ吸着・閉じる・消しゴムで頂点削除 等）の後に、その時点の `Artwork` を1エントリとして積む。
- 現在の `undoLastVertex`（下書き中の1点だけ戻す、閉じた後は無効化される特別扱い）を撤廃し、**汎用の `undo()` に統合**。閉じる操作もUndo対象になり、閉じた直後にUndoすれば下書き状態に戻る（一般的な描画アプリの挙動に合わせる、末尾の検討メモ2026-07-11参照）。
- ドラッグ中の transient な状態（Phase C の `dragPreviewProvider` など、まだ `Artwork` に反映されていない指の移動そのもの）は履歴に積まない。指を離して確定した時点のみ1エントリ。Phase D の頂点ドラッグ移動も同じ「ドラッグ中は transient、離した瞬間だけ確定」の型で実装することが前提（この型で作ればUndo履歴が中間フレームで埋まらない）。
- 今回は **Undo のみ**（Redo は任意で入れられる余地を残すが必須ではない）。永続化（アプリ再起動をまたいだUndo履歴の保持）や保存フォーマットとの統合は対象外、Phase H+ の汎用Undo/Redo項目に引き継ぐ。
- UI: [lib/widgets/toolbar/editor_toolbar.dart](lib/widgets/toolbar/editor_toolbar.dart) のボタン表示を「1点戻す」→「元に戻す」に変更（下書き中は1点だけ戻る従来の見た目のまま、下書きが空の時は直前の確定操作＝閉じる/消す等を取り消す）。

完了条件: 点を打つ→閉じる→Undoで閉じる前の下書き状態に戻る。さらにUndoすれば点が1つずつ戻る。ドラッグ中の中間状態はUndo履歴に残らない。

> 実装メモは末尾の検討メモ（2026-07-11）参照。

### Phase D: 頂点編集（選択・移動）

- 短タップ/長押しで最寄り頂点を選択（draft・確定の両方、`findNearestPoint` 再利用）。選択ハンドル表示、空白タップで解除。
- 長押し+ドラッグで `Vertex.position` を更新。溶接済み頂点なら参照する全ポリゴンが一緒に動く（隙間なし）＝溶接モデルの利点。ドラッグ中は Phase C の `dragPreviewProvider` と同じ型（transient状態→指を離した瞬間だけ確定）で実装し、Phase D0 のUndo履歴に1エントリだけ積む。
- 完了条件: 共有された角をドラッグすると隣接ポリゴンが追従。

> 実装メモは末尾の検討メモ（2026-07-11）参照。

### Phase E: 切り離し / 手動溶接

- detach: 選択頂点を複製し、片方のポリゴンの参照のみ新 ID に差し替え（局所操作）。
- weld: 近接する2頂点を1つに統合（参照張り替え＋prune）。
- 完了条件: 溶接された角を「個別に動かせる」状態に分離／再結合できる。

> 実装・実機テスト完了メモは末尾の検討メモ（2026-07-11）参照。

> 関連: 閉じる辺の吸着で増える想定外の溶接パターンについては、末尾の検討メモ（2026-07-10）参照。

### Phase E+: 負債前倒し（G前の崖を分散）

> **目的**: G 直前に集中していた小さな修正を前倒しし、「G前ゲート」の崖を緩める。→ 検討メモ（2026-07-13 追記続き2、下記アーカイブ）参照。

- **#5 Undo スタック上限**: 無制限 `Artwork` スナップショットに上限（例 50〜100）+ 切り捨て。`UndoHistory<Artwork>` クラス化を検討。
- **#7 `weldVertices` figure-8**: 非連続重複（例 `[A,keep,B,keep,C]`）を弾くか正規化 + テスト追加。
- **#15 `clearDraft` / `clearAll` の Undo テスト**: 実装はあるがテストなし → 追加。
- **#16 `detachVertexFromDraft` テスト**: polygon 版のみテスト済み → draft 版を追加。

**完了条件**: 上記4項目が `flutter test` でカバーされ、Undo 上限が動作。実機確認は不要（ロジックのみ）だが analyze/test パス必須。

**実装完了（2026-07-14）**

- [lib/providers/canvas_provider.dart](lib/providers/canvas_provider.dart): `kUndoStackLimit = 100` を新設。`_recordUndo()` がスタック長超過時に最も古いスナップショットを1件破棄。
- 同ファイル: `_canWeldVertices` に `_hasNonConsecutiveDuplicate` チェックを追加。合体後のポリゴンリング／下書きの各配列に「連続ではない重複 ID」（figure-8/bowtie、例: 四角形の対角2頂点を溶接すると発生）が残る場合、`weldVertices` は false を返し何もしない。
- [test/canvas_notifier_test.dart](test/canvas_notifier_test.dart): 新規4グループ・10件を追加
  - Undo スタック上限（#5）: 120回コミット後に上限100件のみ戻せることを検証。
  - weld figure-8 ガード（#7）: 四角形の対角頂点溶接を拒否／通常の別ポリゴン間溶接は従来通り許可。
  - `clearDraft` / `clearAll` の Undo（#15）: 各3件（復元・空時no-op含む）。
  - `detachVertexFromDraft`（#16）: 共有頂点の分離・独立移動・非共有時no-op・draft未参照時no-op・Undo復元。
- `flutter analyze` / `flutter test`（66件）パス。実機確認は本 Phase の完了条件外（ロジックのみ）。

→ 検討メモ（2026-07-14 追記続き5、下記アーカイブ）参照。

### Phase G-spike: テッセレーション実現性検証（完了）

> **目的**: v1 の目玉（G）の de-risk。本番実装前に 0.5〜2日でパッケージ選定・Isolate 実行・スキーマ・maxEdge 再分割の実現性を検証。→ 検討メモ（2026-07-13〜07-15、下記アーカイブ）参照。

- パッケージ選定: `delaunay`（v3.0.0、純Dart実装、Mapbox のアルゴリズム移植版）を採用。
- `compute()`（Isolate）でのオフロードを確認（#17、10,000点規模でメインスレッド直接実行と一致）。
- `ArtworkDocument` v1 スキーマ（U1）と `Artwork` 投入のデータ変換フローを紙上設計、双方 Go 判定。
- `maxEdge` 超え辺の反復再分割 PoC が成功（500×500pxの四角形、maxEdge=50.0 で44回の反復で収束）。**分割点にジッターを加えることが収束の必須条件**という重要な知見を得た（collinear な点が退化三角形を生み分割が止まるため）→ G 本番実装への必須 TODO。

**Go/No-Go 判定**: **Go（Tier B: 制約付きドロネー + max 超え再分割、分割点にジッター付与）**。

**完了（2026-07-15）**: 検証はすべて `test/spike_tessellation_test.dart`（捨てコード、本番未マージ）で実施。次は **Phase Hα**（本ファイル後方の「Phase Hα」節を参照）。

### Phase Hα: 下絵（背景画像）（完了、2026-07-17）

> G より先に実装（v1 の芯）。保存（Hγ）と同時リリース — セッションのみの下絵は不可。→ 検討メモ（2026-07-13・追記続き3、下記「検討メモ（過去アーカイブ）」）参照。

- `image_picker` でギャラリーから選択。`UnderlayLayout`（画像参照 + world rect + opacity）を独立モデルに。`Artwork` 本体とは分離し、保存時は Hγ で JSON に含める。
- **取り込み時に上限解像度（`maxWidth: 1920` / `maxHeight: 1080`、2026-07-16改訂）へダウンサンプリング（＝標準化）してから保持・表示する**（#18）。理由: 端末カメラの写真は4K以上の高解像度が普通で、そのままメモリ上に展開するとデコード時点でネイティブメモリを圧迫し、OOM（メモリ不足）でクラッシュするため。加えて、`maxWidth`/`maxHeight` 指定はプラットフォーム側でのリサイズ＋標準JPEG形式への再エンコードも兼ねるため、非標準的な形式のJPEGに対するデコード失敗（下記「検討メモ（Hα）」の2026-07-16参照）の回避にも寄与する。`image_picker` の `maxWidth`/`maxHeight` 指定で実現（アプリ内コピーとして再保存はしない）。
- `PolygonPainter` とは別の `CustomPaint`（`UnderlayPainter`）として、viewport 変換**内側**（world 固定）に下絵を描画。ポリゴンより背面、両方を個別の `RepaintBoundary` で分離。
- 透過: スライダーではなく段階的なボタン操作（スワイプ操作によるOSジェスチャー誤爆を避けるため、2026-07-15 決定）。~~5段階ボタン（`SegmentedButton`）＋表示ON/OFFトグル（`SwitchListTile`）を `showModalBottomSheet`（AppBarの「下絵設定」ボタンから開く）に格納。~~ → **2026-07-16 改訂**: モーダルシートを廃止し、ボトムツールバー上段に「💧 NN%」の単一トグルボタン（タップで10/30/50/70/100%をループ）＋表示ON/OFFアイコンボタンとして統合（タップ数削減）。
- v1 は**キャンバスへのフィット固定**（拡大・回転・自由配置は見送り）。下絵の配置（`offset`/`scale`）は `fitUnderlayToCanvas` が画像インポート時・キャンバスリサイズ時にのみ算出し、`Artwork` の Undo スタックの対象外（幾何ではなく表示状態のため）。
- スポイト（色取得）は v1.1。

**画像読み込みの仕様（v1 スコープ、2026-07-15 確定）**:
- **v1 の実装**: `image_picker` でギャラリーから選択した画像を、選択したままの向き（0度扱い、EXIF回転の解釈以上の加工はしない）で取り込む。OOM対策・形式標準化として `ImagePicker().pickImage(maxWidth: 1920, maxHeight: 1080)` を指定し、デコード前にネイティブ側でダウンサンプリング＋標準JPEGへの再エンコードを行う（#18 の実装方式として確定、2026-07-16に2048×2048正方から1920×1080へ改訂）。
- **v1.1 以降へ見送り**: アプリ内での画像の回転・反転、および `image_cropper` 等のUI付き切り抜きプラグインの導入。取り込んだ写真の向き・切り出しを変えたい場合は、ユーザーが端末側のギャラリーで編集してから選び直す運用とする。
- **iOS の Info.plist（`NSPhotoLibraryUsageDescription`）**: 本リポジトリには `ios/` プラットフォームが未追加（Google Play / Android のみを対象とした計画のため）。iOS 対応が将来必要になった際に `flutter create --platforms=ios .` で追加してから設定する。今回はスコープ外（ユーザー確認済み）。

**完了条件**: 写真を透過下絵として載せ、その上に描画できる。**高解像度写真（4K級）を取り込んでもクラッシュせず、特殊な形式のJPEGでも正しく表示される**（下1/3が黒くなる等の描画破綻がない）。加えて、モード切替時の下絵位置ズレバグの根本解決、編集モードのUX強化（図形/辺トグル・平行移動・中点挿入・図形削除）、長押しドラッグ関連の2件のバグ修正・UX強化を完了。実機確認済み。

**着手前チェックリスト（Hα、完了）**:
- [x] 画像取込時のダウンサンプリング方式（上限解像度・リサイズタイミング）を決定（#18）— `image_picker` の `maxWidth: 1920`/`maxHeight: 1080` によるネイティブ側ダウンサンプリング＋形式標準化（2026-07-16改訂）。
- [x] `UnderlayLayout` の実装とキャンバスへの描画・操作（v1: フィット固定＋不透明度/表示切替のみ、自由配置とUndo対象化は見送り）。

**追加すべきテスト（Hα関連、すべて実施済み）**:
- 画像ダウンサンプリング関数が上限解像度に収まる出力を返すこと（#18）
- `fitUnderlayToCanvas` が画像/キャンバスの縦横比に応じて正しくフィットする（contain-fit・中央寄せ・縦横どちらが基準辺になるケースも）こと
- `UnderlayLayout`（`copyWith`/`toMap`/`fromMap`/`worldToLocal`）の単体テスト
- `UnderlayLayoutController.cycleOpacity()` の単体テスト
- `resolveDetachTarget`（共有頂点の切り離し対象を解決する純関数）の単体テスト
- `edgeMidpoint`／`resolvePolygonTarget`／`resolveEdgeTarget`（図形・辺のトグル選択を解決する純関数群）の単体テスト
- `CanvasNotifier.translatePolygon`／`insertVertexAtEdge`／`deletePolygon` の単体テスト（Undo復元込み）
- `findNearestPoint` の `preferredId` タイブレークの単体テスト
- 切り離し直後の同座標タイブレークが正しく新頂点側を掴むことのテスト（`CanvasNotifier`単体・ウィジェット両方）
- 長押しドラッグで別の頂点へ直接切り替えた際に検出/切り離し/図形・辺サイクルの各カウンタが正しくリセットされる（同一頂点への再長押しではリセットされない）ことのウィジェットテスト
- 「選択を解除」ボタンが選択解除・検出サイクルリセット・共有頂点/非共有頂点どちらのUIでも表示されることのウィジェットテスト

詳細な設計経緯・実装内容は本ファイル末尾の「検討メモ（Hα、2026-07-15〜2026-07-17）」を参照。

### Phase Hβ: ズーム / パン UI（完了、2026-07-17）

> Phase B の座標変換の継ぎ目にズーム/パン UI を載せ、ジェスチャー衝突（`GestureDetector` は `onPan*` と `onScale*` を共存できない）を解消。→ 検討メモ（2026-07-13、上記「検討メモ（過去アーカイブ）」）参照。

- `viewport_provider.dart`: `ViewportController` に `reset()`（`value` を `ViewportTransform.identity` へ）を追加。
- **ジェスチャー方針**: `GestureDetector` は `onPan*` と `onScale*` を同時に持てない（Flutter assert）ため、描画・消しゴム・編集の3モードすべてで `onPan*` を `onScale*` + `pointerCount` に置き換え、1本指（各モードの既存の確定ロジック）と2本指（ビューポートのピンチズーム＋パン）を分岐。編集モードの `onLongPress*`/`onTapUp`（頂点の移動・選択・結合）は `onScale*` と共存させたまま維持。
- `viewport_gesture_provider.dart`（新設）: `ViewportGestureBaseline`（`pointerCount`/`transform`/`focalPoint`/`hadMultiFinger` を保持する不変クラス）と `ViewportGestureController`（`ValueNotifier`）。Flutter の `ScaleGestureRecognizer` は指の本数が変わるたびに内部的に `onEnd`+`onStart` を再発火させる（1回の物理ジェスチャー中に複数回の「サブサイクル」が起こる）ため、サブサイクルごとに基準点（viewport・フォーカルポイント）を取り直す設計とした。
- `geometry/viewport_pinch.dart`（新設）: 基準の `ViewportTransform`/フォーカルポイントと現在の scale/フォーカルポイントから新しい `ViewportTransform` を計算する純関数 `applyPinchPan`。`kMinViewportScale`（0.2）/`kMaxViewportScale`（8.0）でクランプ。
- 「全体表示に戻す」ボタン（`Icons.fit_screen`、Tooltip付き）をツールバー上段（Row 1）に追加。押下時に `ViewportController.reset()` を呼ぶ。
- **許容距離の画面px統一**: `kDoubleTapMaxDistance` / `kLineAbsorptionTolerance` を画面 px 基準に統一。`canvas_provider.dart` の `handleDrawTap`/`closePolygon`と内部ヘルパーに省略可能パラメータ `doubleTapMaxDistance`/`lineAbsorptionTolerance`（デフォルトは既存定数）を追加し定数の直接参照を置き換え。`polygon_canvas.dart`/`editor_toolbar.dart` は `hitRadius()` と同型のヘルパーで `viewport.value.scale` 換算した値を渡す。
- **実機フィードバックを受けた修正（同日）**: 2本目の指が加わった瞬間に、進行中の1本指アクション（描画中のドラフト点・頂点/図形ドラッグプレビュー等）を「その場で確定」する当初方針は、実機では2本の指が完全に同時には触れず必ずどちらかが数msec先行するため、「意図しない点が打たれてしまう」というUX上の不具合として現れた。原因は Flutter SDK の `ScaleGestureRecognizer._reconfigure` が、指の本数が変化するたびに変化後の新しい `pointerCount`（1→2 の場合は 0 ではなく 2）を持つ `onEnd` を同期的に発火させ、既存の「1本指のみのジェスチャーが正常終了した」判定条件を誤って満たしてしまうことだった。`endGestureSubCycle` に `details.pointerCount == 0`（全指が本当にリフトした「最終リリース」）という条件を追加し、各モードの `onScaleEnd` で、コミットしない場合は該当のプレビュー状態を明示的に `null` 化して**破棄**（Artwork・Undoスタックは無変更）するよう修正した。

**完了条件**: 2本指でズーム/パン、1本指の描画・編集が正常。拡大後もスナップ・ダブルタップ・線上吸着が画面距離一定。`scale≠1` の統合テストあり。実機確認済み（ズーム/パンの滑らかさ、および実機フィードバック対応後は意図しない点の追加がないことを含む）。

**着手前チェックリスト（Hβ、完了）**:
- [x] `kDoubleTapMaxDistance` / `kLineAbsorptionTolerance` の screen px 統一を実装（#1）
- [x] ジェスチャー方針決定（`onScale*` + `pointerCount`）（#2）
- [x] `scale≠1` / `offset≠0` の `CoordinateTransform` テスト + hitRadius 統合テスト

**追加したテスト（Hβ関連、すべて実施済み）**:
- `scale≠1` で `hitRadius / scale` が画面距離一定になること
- `kDoubleTapMaxDistance`/`kLineAbsorptionTolerance` の scale 対応（パラメータ化後の単体テスト）
- `applyPinchPan`（ピンチ/パンの変換計算）の純関数単体テスト
- Widget test: 2本指ピンチズーム／2本指パン／描画中に2本目の指が触れた際のキャンセル／「全体表示に戻す」ボタン／ズーム時のダブルタップ許容距離
- Widget test: 図形ドラッグ中に2本目の指が加わった際のキャンセル（実機フィードバック対応の回帰テスト）

詳細な設計経緯・実装内容は本ファイル末尾の「検討メモ（Hβ、2026-07-17）」を参照。

### Phase F: なぞりモード（完了、2026-07-19）

> Phase B〜E の「タップで1点ずつ置く」に加え、フリーハンドでなぞった軌跡を等間隔サンプリングしてドラフトへ追記する「なぞりモード」を追加。F-core（純関数＋バッチAPI）とF-UI（ジェスチャー統合）に分割して実装。→ 検討メモ（2026-07-18〜2026-07-19、下記「検討メモ（F、2026-07-18〜2026-07-19）」）参照。

- `lib/geometry/trace_point_generator.dart`（新設）: 純関数 `generateTracePoints(rawPath, {spacing})`。累積距離配列を作り、`spacing` の倍数ごとに該当セグメントを線形補間してサンプリングする O(rawPath.length) 実装。始点・終点は必ず保持（末尾が `spacing` の倍数ちょうどでなくても、最後にもう一度生の終点を追加）。
- `CanvasNotifier.commitTraceStroke(points, {hitRadius, lineAbsorptionTolerance})`（新設）: 疑似ダブルタップ検出・自動クローズを一切通さず、1ストローク=`_recordUndo` 1回のバッチ処理でドラフトへ追記。既存の吸着/スナップ規則（`_findPolygonVertexNearIn` 内部ヘルパーへ切り出し）を点ごとに適用しつつ、`state` への書き込みは合計1回。
- `TraceStrokePreviewController`（[lib/providers/trace_stroke_preview_provider.dart](lib/providers/trace_stroke_preview_provider.dart)、新設）: `ValueNotifier` ではなく素の `ChangeNotifier`。`Path.lineTo` でO(1)のインクリメンタル追記によるライブプレビュー（生の `List<Offset>` も同時に保持）。
- `TraceGestureController`（[lib/providers/trace_gesture_provider.dart](lib/providers/trace_gesture_provider.dart)、新設）: `idle`→`awaitingDisambiguation`→`locked` の3状態機械による「Lock & Ignore」。猶予期間 `kTraceGraceWindow`（120ms）の `Timer` とスロップ `kTraceGraceSlop`（10px）の両方でロックを確定し、既存のHβ `onScale*`/`isViewportGesture()` 基盤は無改変のまま再利用。ロック確定後は対象ポインタ以外を完全に無視し、2本指ズーム/パンとの競合を回避。
  - 製品判断1: 猶予期間中（未ロック）に指が離れた場合はストロークを破棄（コミットしない）。
  - 製品判断2: ロック対象の指が離れた瞬間に即座に `commitTraceStroke` を確定（他の指の状態は無関係）。
- `DrawMode`（[lib/models/draw_mode.dart](lib/models/draw_mode.dart)、新設）: `tap`/`trace` の2値。`drawModeProvider` を `canvas_provider.dart` に新設。
- [lib/widgets/canvas/polygon_canvas.dart](lib/widgets/canvas/polygon_canvas.dart): `CanvasMode.draw && DrawMode.trace` のときのみ、既存の `onScale*` `GestureDetector` の外側に生ポインタ用の `Listener` を追加する分岐を新設。Hβ の `beginGestureSubCycle`/`isViewportGesture`/`applyViewportUpdate`/`endGestureSubCycle` は無改変のまま再利用。
- [lib/widgets/toolbar/editor_toolbar.dart](lib/widgets/toolbar/editor_toolbar.dart): 描画モードのRow2先頭に タップ/なぞり の `SegmentedButton` を追加。モード切替（`_CommonRow.selectMode`）で描画モードから離れる際に `traceGestureProvider`/`traceStrokePreviewProvider` も防御的にリセット。
- [lib/widgets/canvas/polygon_painter.dart](lib/widgets/canvas/polygon_painter.dart): `tracePreview`（`TraceStrokePreviewController`）を受け取り、ストローク中はティール色の実線で描画（`Listenable.merge` に追加）。
- **サンプリング間隔の仕様修正（2026-07-19）**: 当初はスクリーンpx基準（`kTraceVertexSpacing / viewport.value.scale`）で画面上の点密度を一定に保つ設計だったが、「ズームインしたまま描いて等倍に戻すと点が密集する」というUX上の問題と、将来のユーザー指定間隔スライダー機能を見据え、**ズーム率に関わらずワールド座標上で常に固定の絶対距離（`kTraceVertexSpacing = 50.0`）でサンプリングする**方式に変更。`polygon_canvas.dart` の `traceVertexSpacing()` ヘルパー（`/ viewport.value.scale` 除算）を削除し、`generateTracePoints` へ `kTraceVertexSpacing` を直接渡す形にした。`kVertexHitRadius` 等の当たり判定はスクリーン基準のまま変更なし（矛盾なし、ズームインするほど相対的にヒットテストが「厳しく」感じられるUX上のトレードオフのみ許容）。

**完了条件**: 下絵＋ズームありの状態で、なぞりにより等間隔（ワールド座標固定間隔）の頂点列が生成され既存頂点と溶接される。1ストロークのUndoが1回。疑似ダブルタップ誤爆なし。2本指ズーム/パンとの競合なし（Lock & Ignore）。`flutter analyze`/`flutter test` 全パス。

**着手前チェックリスト（F-core / F-UI、完了）**:
- [x] `TracePointGenerator` を純関数として外に出す設計を固定（`lib/geometry/trace_point_generator.dart`、`generateTracePoints`）
- [x] `commitTraceStroke`（1ストローク1Undo・ダブルタップ非経由）のAPIを固定（`CanvasNotifier.commitTraceStroke`）
- [x] `TracePointGenerator` 単体テストを先に書く（`test/geometry/trace_point_generator_test.dart`）
- [x] なぞりジェスチャーを `onScale*` 土台に載せる（`TraceGestureController` によるLock & Ignore）
- [x] 下絵＋ズームありで実機確認

**追加したテスト（F関連、すべて実施済み）**:
- `generateTracePoints`（等間隔・末尾保持・複数セグメント跨ぎ・短いストローク・折返し・ゼロ長セグメント・空/1点入力・spacingアサート）
- `CanvasNotifier.commitTraceStroke`（空リストno-op・通常追記・1バッチ=1Undo・既存頂点へのスナップ・線上吸着・疑似ダブルタップ非発火・既存ドラフトへの継続・直後タップの誤ダブルタップ防止・hitRadiusスケーリング）
- Widget test: なぞりモードgesture（Lock & Ignore） — スロップ超えでの一括コミット・猶予期間中の早期リリース破棄・猶予期間中の2本目の指によるピンチ/パンへのハンドオフ・ロック後の2本目の指の無視・モード切替時の防御的リセット
- Widget test: scale=2.0でもワールド座標上の頂点間隔が `kTraceVertexSpacing`（50.0）で一定であること（サンプリング間隔仕様修正のリグレッションガード）

詳細な設計経緯・実装内容は本ファイル末尾の「検討メモ（F、2026-07-18〜2026-07-19）」を参照。

### Phase G: 自動テッセレーション（三角・幾何学ローポリ）（完了、2026-07-20）

> **着手前提（達成済み）**: G-spike 完了（Go、Tier B 確定済み） + 着手前チェックリストの G 本番直前チェック + **maxEdge/minEdge の world 値を実装前に相談で確定**（#20）。

#### ~~旧仕様（2026-07-13 前）~~

- ~~パイプライン: (1) 輪郭取得 → (2) 内部点生成 → (3) ドロネー分割。~~
- ~~点分布: `PointDistribution.generate(boundary, spacing)`。v1 は幾何学ローポリ用1種。~~
- ~~出力は共有頂点プールに三角ポリゴン群として投入。~~
- ~~完了条件: 指で描いた〇の内部が三角メッシュで埋まり、**間隔スライダーで粗さを変えられ**、生成後に頂点編集できる。~~

#### ~~現行仕様（2026-07-13〜）~~

~~- パイプライン: (1) 輪郭取得（指の閉曲線を簡素化） → (2) 内部点生成 → (3) 三角形分割（ドロネー、境界は制約付き）。~~
~~- 点分布を差し替え式に: `PointDistribution.generate(boundary, spacing)`。v1 は幾何学ローポリ用1種・既定間隔のみ（間隔スライダーは v1.1 に先送り）。~~

#### 現行仕様（2026-07-14〜）

- パイプライン: (1) 輪郭取得（指の閉曲線を簡素化） → (2) 内部点生成 → (3) 三角形分割（G-spike の Tier B）。
- **三角サイズ品質（#20）**: v1 は UI 調整なし（ボタン1つのみ）。品質 Pass の優先は「辺長が maxEdge を超える三角形が残らないこと」。実機チューニング（iPhone14相当 390x844、スパイクスクリプトで検証後に削除）の結果、`maxEdge: 150.0` で確認されたスリバー三角形対策として角度フィルター案を検討したが、元の境界頂点自体の鋭角には無力かつ無限ループの懸念があるため不採用。妥協案として `minEdge: 25.0` を採用し、`lib/services/tessellation_service.dart` の `kTessellationDefaultMaxEdge`/`kTessellationDefaultMinEdge` として確定。
- 出力は共有頂点プールに三角ポリゴン群として投入 → Phase D/E の編集がそのまま効く。**一括生成 = Undo 1回**（`CanvasNotifier.commitTessellationResult`）。
- G 本番直前に `_polygonEdgeGraph` / `_shortestBoundaryPath` / `_absorbVerticesAlongNewSegment` / `_collapseConsecutive*` を `geometry/` へ純関数抽出（2026-07-14 commit `13836db`）。`buildPolygonEdgeGraph`/`findShortestBoundaryPath`（`lib/geometry/polygon_graph.dart`）、`findVerticesAlongSegment`（`lib/geometry/line_absorption.dart`）、`collapseConsecutiveRingIds`/`collapseConsecutiveOpenIds`/`hasNonConsecutiveDuplicate`（`lib/geometry/ring_collapse.dart`）として存在。
- G 入力サニタイズ（#8）: `lib/geometry/tessellation_input.dart`（`sanitizeTessellationBoundary`/`weldCoincidentRingVertices`）＋ `lib/geometry/self_intersection.dart`（`segmentsIntersect`/`isSelfIntersectingRing`）。coincident-but-unwelded は正規化（自動溶接）、自己交差ポリゴンは弾く方針。
- 当たり判定のインターフェース切り出し（#10）: `lib/geometry/vertex_hit_test.dart` に `VertexHitTest`／`LinearVertexHitTest` を新設し `CanvasNotifier` の `_findPolygonVertexNearIn`／`findVertexNear` を差し替え。内部実装は既存の O(n) 線形探索のまま。
- ~~`triangulate`（`lib/services/tessellation_service.dart`）本体: `delaunay` パッケージで初期分割 → 生成された三角形の辺を走査し `maxEdge` を超える辺の中点（ジッター付き、`kTessellationJitter = 1.0`）を追加 → 再分割、を繰り返す。`minEdge` 未達（分割後の半辺が `minEdge` を下回る）ならその辺の分割はスキップ。`kTessellationMaxIterations = 10` で強制停止。~~
- **重い三角分割は `compute()`（Isolate）で実行し、計算中は画面にローディングインジケータを表示する**（#17）。失敗時は Artwork 不変 + ユーザー通知（`TessellationRejectReason.computeFailed`）。`isTessellatingProvider` と `TessellationController.tessellate`（`lib/providers/tessellation_provider.dart`）、`_TessellationBlockingOverlay`（`AbsorbPointer`、`lib/screens/editor_screen.dart`）で実装。

#### エンジン刷新後の現行仕様（2026-07-25〜、Phase G 完了後）

穴空きポリゴン対応とスリバー排除のため、G 完了時点の `delaunay` 依存パイプラインを廃止し、純 Dart の poly2tri（Sweep-line CDT）内製エンジンへ差し替えた。

- **エンジン**: `lib/geometry/vendor/poly2tri/` に poly2tri（BSD-3-Clause、上流 [jhasse/poly2tri](https://github.com/jhasse/poly2tri)）を純 Dart 移植。`CDT` / `Sweep` / `SweepContext` / `AdvancingFront` および `P2tPoint`・`P2tEdge`・`P2tTriangle`・述語（`orient2d` / `inCircle`）。Flutter / アプリモデル非依存。
- **アダプター**: `lib/geometry/poly2tri_adapter.dart` の `runPoly2TriCdt` が `TessellationRequest`（`Offset` リング）↔ poly2tri を橋渡し。重複・近接座標は `kP2tEpsilon` 以内で同一 `P2tPoint` にマージ。`TessellationResult.points` のインデックス契約は **boundary → holes flatten → Steiner** を厳守。
- **穴**: Phase-1 で導入した `TessellationRequest.holes`（完全内包ポリゴン）を真の制約辺として CDT に渡す（旧: 非制約 Delaunay + 重心フィルタ）。
- **品質精錬（Steiner）**: `triangulate` 前に外枠 AABB 上へ `maxEdge` 間隔のグリッド Steiner を生成し `CDT.addPoint` で登録。フィルタは (1) 外枠の厳密内側かつ全穴の外側 (2) 既存頂点・他 Steiner から ≥ `minEdge` (3) 制約辺からのクリアランス（`max(kP2tEpsilon, minEdge * 0.25)`）(4) 上限 `kPoly2TriMaxSteinerPoints`。既定の `kTessellationDefaultMaxEdge` / `kTessellationDefaultMinEdge`（150.0 / 25.0）は継続利用。
- **依存除去**: `flutter pub remove delaunay` 相当で `pubspec.yaml` から削除。旧検証用 `test/spike_tessellation_test.dart` を削除し、関連 Linter 警告を解消（`flutter analyze` → No issues found）。

**完了条件**: 相談で確定した `maxEdge`/`minEdge` で、閉曲線内部が三角メッシュで埋まり、**max 超え三角が実用上残らない**。生成後に頂点編集可。計算中 UI フリーズなし（#17）。顔・シンプルなイラスト等で実機確認。`flutter analyze` / `flutter test` パス。
→ **達成済み（2026-07-20）**。`maxEdge`/`minEdge` の world 値（150.0/25.0）は実機チューニングで確定済み（#20）。`compute()` 経由の非同期実行・ローディングUI（#17）と合わせて配線完了。
→ **エンジン刷新達成済み（2026-07-25）**。上記 poly2tri CDT + アダプター + Steiner 精錬に置換。穴付きフィクスチャでも制約辺を保持し穴内に三角形重心が落ちないことを単体テストで確認。

**着手前チェックリスト（G 本番直前、すべて完了）**:
- [x] 境界グラフ・吸着・リング畳みの純関数抽出（#6）（2026-07-14 commit `13836db`。単体テストは 2026-07-20 `test/geometry/polygon_graph_test.dart`／`line_absorption_test.dart`／`ring_collapse_test.dart`）
- [x] G 入力サニタイズ方針（#8）（2026-07-20。単体テストは `test/geometry/tessellation_input_test.dart`／`self_intersection_test.dart`）
- [x] 当たり判定のインターフェース切り出し（#10）（2026-07-20。単体テストは `test/geometry/vertex_hit_test_test.dart`）
- [x] `compute()` 経由のテッセレーション呼び出し + ローディングUI実装（#17）（2026-07-20。単体テストは `test/services/tessellation_service_test.dart`／`test/canvas_notifier_tessellation_test.dart`／`test/providers/tessellation_provider_test.dart`）
- [x] `maxEdge` / `minEdge` の world 値を実機相談で確定してから実装（#20）（2026-07-20。`maxEdge: 150.0`／`minEdge: 25.0` で確定。角度フィルター案は不採用）

（「バッチ polygon insert + Undo 1回の API」は `commitTessellationResult` に統合実装されたため、独立項目としては解消済み。）

**追加したテスト（G関連）**:
- `compute()` ラッパーが Isolate 経由でも正しい結果を返すこと（#17）
- ~~テッセレーション出力で maxEdge 超え辺が実用上残らないこと・`minEdge`/最大イテレーションによるループ停止（#20）~~（旧 delaunay 中点再分割前提）
- poly2tri CDT コア（四角形・穴付き）およびアダプター経由の Steiner 精錬・穴制約（`test/geometry/vendor/poly2tri/`・`test/services/tessellation_service_test.dart`・`tessellation_holes_test.dart`）

詳細な設計経緯・実装内容は本ファイル末尾の「検討メモ（G、2026-07-20）」および「2026-07-25: Phase G エンジン刷新」を参照。

## 検討メモ（過去アーカイブ: 2026-07-10〜07-15）

> Hα 着手（2026-07-15〜）〜Hβ 着手（2026-07-17〜）の間の検討メモは本ファイル末尾「検討メモ（Hα、2026-07-15〜2026-07-17）」を、Hβ 着手中の検討メモは本ファイル末尾「検討メモ（Hβ、2026-07-17）」を、F 着手中の検討メモは本ファイル末尾「検討メモ（F、2026-07-18〜2026-07-19）」を参照。G 以降の検討メモは [plan_phase_G.md](plan_phase_G.md) を参照。2026-07-13〜07-15（G-spike 完了まで）分は本節に格納。

### 2026-07-10: クローズ処理の統一と今後の整合性

実機テストで発覚した「別ポリゴン同士を跨いでクローズすると、閉じる辺が既存の途中の頂点を無視して直線で始点に戻ってしまう」という点を相談し、以下の方針で合意。

**合意した修正方針（`closePolygon` の統一ルール化）**

- 始点・終点が同一の既存ポリゴンを共有 → その境界の短い弧をたどる（既存の `_sharedBoundaryClosure` の挙動を維持）。
- それ以外のあらゆる組み合わせ（別ポリゴン同士／片方だけ既存頂点／両方フリーハンドの新規点など）→ 終点→始点の直線上に乗っている既存頂点を、通常の辺と同じ `_absorbVerticesAlongNewSegment` で吸着してから閉じる、という**共通のフォールバック**に統一する。
- 「ダブルタップは閉じるだけ（終点の再探索はしない）」という Phase A の原則とは矛盾しない。終点自体は変えず、確定済みの始点・終点の間に何を挟むかだけを扱うため。
- どの多角形から始まり、どの多角形で終わっても同じ1つのルールで処理されるようにする（始点・終点の組み合わせによって挙動が変わらないようにする）。

**今後のフェーズとの整合性メモ**

- **Phase C（磁石スナップ・プレビュー）**: ドラッグ中の予告線はユーザーが置く次の1点のプレビューであり、閉じる辺（ダブルタップ/「閉じる」ボタンで暗黙に生成される最後の辺）の吸着とは別物。閉じる辺の吸着結果が予告なしに反映される点は、Phase C でプレビューの一貫性として検討する余地あり（必須ではない）。
- **Phase D（頂点編集・選択移動）**: 本修正の最大の受益フェーズ。統一ルール化しないまま Phase D に進むと「同一ポリゴン共有時だけ正しく追従し、別ポリゴン同士は追従しない」という再現性の低い不具合になるため、**Phase D 着手前に本修正を完了させておくこと**。
- **Phase E（切り離し/手動溶接）**: 閉じる辺の吸着が増えることで、ユーザーが意識せず溶接される頂点が増える。Phase E のテストケースに「閉じる辺で吸着された頂点の切り離し」パターンも含めること。
- **Phase G（自動テッセレーション）**: テッセレーションは `closePolygon` を通らない別パイプラインのため、この修正だけでは境界溶接は解決しない。実装時は「直線上の既存頂点吸着」ヘルパーを汎用化しておき、Phase G の境界溶接処理からも再利用できる形にする。

**実装完了（同日）**

- [lib/providers/canvas_provider.dart](lib/providers/canvas_provider.dart): `closePolygon` が新設した `_closingEdgeVertices` 経由で閉じるように変更。`_sharedBoundaryClosure` が空を返した場合、既存の `_absorbVerticesAlongNewSegment` を再利用して閉じる辺（終点→始点の直線）上の既存頂点を吸着するフォールバックを追加。始点・終点がどの多角形に属していても同じ1ルールで処理される。
- [test/canvas_notifier_test.dart](test/canvas_notifier_test.dart): 別ポリゴン同士のクローズで「吸着対象なし＝直線のまま」（既存テスト、回帰なしを確認）と「吸着対象あり＝既存頂点を溶接して閉じる」（新規テスト）の両方を検証。
- `flutter analyze` / `flutter test`（37件）パス。次は実機での確認待ち。

**追加合意・実装（同日続き）**: 上記の吸着フォールバックだけでは、実機で報告された「多角形Aから多角形Bへ跨ぐクローズが、隣接する既存の（曲がった）境界を辿らず始点への直線に戻る」ケースが再発することが判明。相談の結果、以下の2点を追加で合意・実装した。

- **境界追跡をグラフ最短経路に一般化**: 「同一ポリゴン内の2つの弧のどちらが短いか」という従来の判定を、**既存の全確定ポリゴンの辺をグラフとして扱い、始点⇄終点間の最短経路（ダイクストラ法、辺の重みは画面距離）を探す**方式に一般化した。同一ポリゴン内の場合は従来通り短い弧に自然に帰着し、別ポリゴン同士でも、途中で共有（溶接）頂点を経由できる鎖があれば、そのルートを辿って閉じるようになった（＝ユーザーが望んだ「どの多角形から始まりどの多角形で終わっても、既存の最短の点と線を辿って隙間を作らない」動作）。
  - [lib/providers/canvas_provider.dart](lib/providers/canvas_provider.dart): `_sharedBoundaryClosure` を `_shortestBoundaryPath`（ダイクストラ本体）＋ `_polygonEdgeGraph`（全確定ポリゴンの辺からグラフを構築）に置き換え。旧 `_arcVertices` / `_pathLength` は不要になり削除。
- **ダブルタップは「隙間ができない時だけ」閉じるように変更**: 「ダブルタップで始点に直線が伸びてしまう挙動自体をなくしたい」という要望を受け、①この直線フォールバック自体（何にも繋がっていない独立図形を閉じるための正当な手段）は残しつつ、②**別々の既存ポリゴン同士を跨ぎ、かつ繋がる経路も吸着対象も見つからない場合に限り、ダブルタップでは閉じない**（普通の点として追加されるだけ）よう変更した。この場合でもツールバーの明示的な「閉じる」ボタン（`closePolygon` を直接呼ぶ操作）は従来通り直線での強制クローズを許可する。「気づかないうちに隙間ができる直線」は暗黙のジェスチャーからは締め出し、意図的な操作にのみ残す、という切り分け。
  - [lib/providers/canvas_provider.dart](lib/providers/canvas_provider.dart): `_tryCloseAtVertex` の連結クローズ分岐に `_wouldCloseWithUnweldedGap` チェックを追加。
- [test/canvas_notifier_test.dart](test/canvas_notifier_test.dart): 「別々の既存ポリゴンが共有頂点を介して隣接している場合、直線ではなくその共有頂点を経由して閉じる」（グラフ最短経路の検証）と、「共有も吸着対象もない別ポリゴン同士はダブルタップでは閉じないが、明示的な閉じるボタンでは閉じる」（安全策の検証）の2件を新規追加。
- `flutter analyze` / `flutter test`（39件）パス。次は実機での確認待ち。

### 2026-07-10（続き）: ダークモード対応の継ぎ目を前倒し（Phase B3）

「OSのダーク設定にアプリはどう対応すべきか」を相談し、Phase C 着手前の今のうちに土台（継ぎ目）だけ作っておく方針で合意。Phase B の「座標変換の継ぎ目を前倒し」と同じ考え方（今後 Phase C〜H+ で増えるUI部品が、後から全部ダーク対応の手直しをしなくて済むようにする）。

**合意した方針**

- **アプリ全体のUIクローム（ホーム画面・AppBar・ボタン等）**: OSのダーク設定に自動追従（`ThemeMode.system` 既定）。ライト/ダークのどちらも同じ seed color から `ColorScheme.fromSeed` で生成し、アプリ内切替UIは今回は作らない（将来 Phase H+ の設定画面で追加できる余地だけ残す）。
- **キャンバス（描画サーフェス）本体の背景色は、アプリ全体のテーマとは独立**させる。理由: お絵描き系アプリ（Procreate 等）ではキャンバス周りの明るさが制作中の配色の見え方に影響するため、OS設定と連動させず、既定はライトで**アーティストが明示的に選べる**トグルとした。
- キャンバス背景の選択は**今回は永続化しない**（アプリ再起動でライトに戻る、session-only）。永続化は Phase H+ で予定している一般設定/保存の仕組みとまとめて対応する（実機テスト自体には支障なし。エンドユーザー向けにはリリース前の対応が必要、と認識）。
- 上記のキャンバス背景トグルにより、ドラフトの下書き線・頂点ドット等の**UIオーバーレイの色**（黒固定だと暗い背景で見えなくなる）もキャンバス背景に応じて可変にする必要があると判明し、合わせて対応。ポリゴン本体の塗り色・線色（アートワークのデータ）はユーザーが選んだ色であり、この対応の対象外（従来通り）。

**実装完了（同日）**

- [lib/app.dart](lib/app.dart): `MaterialApp` に `darkTheme` を追加（`theme` と同じ seed color、brightness違いのみ）。`themeMode` は指定せず既定の `ThemeMode.system` に委ねる。
- [lib/providers/canvas_background_provider.dart](lib/providers/canvas_background_provider.dart): 新設。キャンバス背景の明暗を持つ `StateProvider<Brightness>`（既定 `Brightness.light`、session-only）。
- [lib/screens/editor_screen.dart](lib/screens/editor_screen.dart): AppBar に切替アイコンボタンを追加し、`ColoredBox` の背景色をこのプロバイダの値で切り替え。
- [lib/widgets/canvas/polygon_painter.dart](lib/widgets/canvas/polygon_painter.dart): `canvasBrightness` を受け取り、下書き線・頂点ドット等のUIオーバーレイ色（黒/白）をキャンバス背景に応じて可変化。ポリゴン本体の塗り/線色は対象外（従来通りアートワークのデータのまま）。
- [lib/widgets/canvas/polygon_canvas.dart](lib/widgets/canvas/polygon_canvas.dart): `canvasBackgroundProvider` を読み、`PolygonPainter` に渡す配線を追加。
- [test/widget_test.dart](test/widget_test.dart): キャンバス背景トグルが既定でライトになっていること、タップでダークに切り替わり、アイコンも切り替わることを検証する新規テストを追加。
- `flutter analyze` / `flutter test`（40件）パス。次は実機での確認待ち。

### 2026-07-11: Phase C（磁石スナップ・プレビュー）実装

**ジェスチャーモデルの変更点**: 従来は `onTapDown` の瞬間に確定していた「点を置く」操作を、`onPanDown`/`onPanUpdate`/`onPanEnd` の**指を離した瞬間に確定**するモデルへ変更した（描画モードのみ。消しゴムモードは従来通り `onPanDown` の瞬間に即削除、プレビュー無し）。`onPanDown` はタップの押下と同じタイミングで発火するため、動かさずに離す通常のタップは「移動距離ゼロのドラッグ」として同じ経路で従来通りに動作し、既存の全テスト（`tester.tapAt` によるもの含む）は無改修で通過した。

- [lib/providers/drag_preview_provider.dart](lib/providers/drag_preview_provider.dart): 新設。`DragPreview`（指の現在のワールド座標 + 吸着中の既存頂点ID、あれば）を保持する `ValueNotifier` ベースの `DragPreviewController`。Phase B の `ViewportController` と同じ理由（`CustomPainter.repaint` に直結し、ウィジェット再構築なしに毎フレーム更新するため）で Riverpod の `StateProvider` ではなく `ValueNotifier` を採用。
- [lib/widgets/canvas/polygon_canvas.dart](lib/widgets/canvas/polygon_canvas.dart): `onTapDown` を `onPanDown`/`onPanUpdate`/`onPanEnd`/`onPanCancel` に置き換え。ドラッグ中は既存の `findPolygonVertexNear`（吸着判定は新規実装せず、既存の単発タップと全く同じ関数・同じ `hitRadius` を再利用）で毎フレーム吸着先を再計算し `dragPreviewProvider` を更新、離した瞬間に最後のプレビュー座標で従来通り `handleDrawTap` を呼ぶ。新規に吸着した瞬間（未吸着→吸着、または別頂点への切替）にのみ `HapticFeedback.selectionClick()`。
- [lib/widgets/canvas/polygon_painter.dart](lib/widgets/canvas/polygon_painter.dart): `dragPreview` を受け取り `viewport` と合わせて `Listenable.merge` で `repaint` に接続。ドラフトの最後の点→現在位置へ薄い予告線、吸着中は相手頂点にリング（teal、二重丸）を強調表示。合意通り、相手ポリゴンの頂点色は変更しない。
- `CanvasNotifier` 本体（`handleDrawTap` 等）は無改修 — 「離した瞬間の確定」も内部的には従来と同じ入口を同じ規則で呼ぶだけなので、クローズ判定・吸着ロジックの二重実装を避けられた。
- [test/widget_test.dart](test/widget_test.dart): 「ドラッグで置いた点は指を離した位置になる（押下位置ではない）」と「既存頂点の近くへドラッグすると `dragPreviewProvider` が吸着先を示し、離すとクリアされる」の2件を新規追加。
- `flutter analyze` / `flutter test`（42件）パス。

**実機テスト結果（同日）**: 予告線・リング表示・従来のタップ操作は問題なし。吸着した瞬間の触覚フィードバックが微弱すぎると判明したため、[lib/widgets/canvas/polygon_canvas.dart](lib/widgets/canvas/polygon_canvas.dart) の `HapticFeedback.selectionClick()` を `HapticFeedback.mediumImpact()` に変更（selectionClick は本来スクロール選択用の最も控えめなティックで、ドラッグ中に気づきにくかった）。Phase C 完了。

### 2026-07-11（続き）: 触覚フィードバックの強さ・設定項目化の方針

上記 `mediumImpact` への変更後、「一般的にはどのくらいの強さが定石か」「端末設定でON/OFFを付けるべきか」「強さを選べるようにすべきか」を相談し、以下で合意した。

- **強さ**: 一般的な定石（iOSのアライメントガイド吸着などに多い軽め）よりは強いが、Android端末はERM/LRAモーターの個体差やOS/OEM実装差が大きく、軽いフィードバックだと機種によっては全く感じ取れないことがある。加えて「吸着した瞬間の1回だけ」という低頻度発火なので、`mediumImpact` のままで問題ない（ゲームのような多用ではないため過剰演出にはならない）。**多段階の強さ選択UIは作らない**。
- **ON/OFF**: Android の `HapticFeedback.*` 系API（Flutter含む）は、OS設定の「タッチ操作時の触覚フィードバック」トグルに従う種類の呼び出しであり、ユーザーがOS側で無効化していれば既にアプリ側は何もしなくても鳴らない。アプリ内に同機能のトグルを重複して作る必要は薄い。ただし将来の設定画面がまとまった際には、他の設定と並べて**単純な1個のON/OFFトグルとしてなら**追加する価値がある（他の app でも強さの多段階よりON/OFFのみが主流）。
- **実装タイミング**: 今回は何もしない。キャンバス背景の永続化（Phase B3 で session-only 実装済み）と同じタイミング — **Phase H+ の一般設定画面**でまとめて対応する。単独で先に作ると、Phase H+ の保存/設定の仕組みと二重実装になる。

→ Phase H+ の節に「一般設定」として反映済み（`phase-h-rest` todo および該当セクション参照）。

### 2026-07-11（続き）: 汎用Undoの継ぎ目をPhase D0として前倒し

「閉じた直後は『1点戻す』ボタンが使えない（下書きが空になるため）のは一般的な仕様と違うのでは」という相談から、一般的な描画/ベクター系アプリ（Illustrator・Procreate等）の標準的な挙動を確認した。

**確認した一般的な仕様**: 標準的な描画アプリは「点を打つ」「閉じる」「消す」等をすべて**同じ1本の統一Undo履歴（アクション単位）**に積む。閉じる操作もUndo対象で、閉じた直後にUndoすれば下書き（開いたパス）に戻る。「点を打つ操作だけUndoできて閉じる操作はUndoできない」という現状の非対称は非標準。

**合意した対応方針**: 「リリース要件」に元々★（後から入れると作り直しになる）として記載していた汎用Undo/Redoのうち、**基本の継ぎ目（Undoのみ・スナップショット方式）を Phase D 着手前に前倒し**（Phase B/B3 と同じ「継ぎ目の前倒し」判断）。理由: Phase D（頂点ドラッグ移動）が「ドラッグ中どう状態を持つか」を決める前に土台を敷いておかないと、後からPhase Dの確定ロジックを手直しする★パターンになるため。

- 新設: **Phase D0（汎用Undoの継ぎ目）**。`CanvasNotifier` に `Artwork` スナップショット方式のUndoスタックを追加し、確定操作（点を打つ/閉じる/消す）ごとに1エントリ積む。現在の `undoLastVertex`（下書き中の1点だけ戻す特別扱い）を撤廃し汎用 `undo()` に統合。ドラッグ中の transient 状態（`dragPreviewProvider` 等、まだ `Artwork` に反映されていない指の移動）は履歴に積まない。
- Redo・永続化（アプリ再起動をまたいだ履歴保持）・保存フォーマット統合は対象外、Phase H+ に引き継ぐ（`phase-h-rest` todo を更新済み）。
- Phase D は、頂点ドラッグ移動を Phase C の `dragPreviewProvider` と同じ「ドラッグ中は transient、離した瞬間だけ確定」の型で実装することが前提（この型で作ればUndo履歴が中間フレームで埋まらない）。Phase D の節にこの前提を追記済み。
- UIボタン表示を「1点戻す」→「元に戻す」に変更予定（Phase D0 の節参照）。

→ Phase D の節、todos（`phase-d0-undo-seam`）、リリース要件の★Undo/Redo項目、`phase-h-rest` todo に反映済み。次はPhase D0の実装。

**実装完了（同日続き）**

- [lib/providers/canvas_provider.dart](lib/providers/canvas_provider.dart): `_undoStack`（`Artwork` スナップショット方式）と `canUndo` / `undo()` / `_recordUndo()` を新設。確定操作（`handleDrawTap` の点追加、`closePolygon`、`handleEraseTap`→`deletePolygonVertex`、`clearDraft`、`clearAll`）の直前に `_recordUndo()` を呼ぶ。`setCanvasSize` とダブルタップ自己クローズ時の `_removeLastDraftVertex`（旧 `undoLastVertex` の内部用抽出）は履歴に積まない。公開 API の `undoLastVertex` は廃止し `undo()` に統合。
- [lib/widgets/toolbar/editor_toolbar.dart](lib/widgets/toolbar/editor_toolbar.dart): ボタン表示を「1点戻す」→「元に戻す」に変更。有効化条件を `draftVertexIds.isNotEmpty` から `notifier.canUndo` に変更（閉じた直後も Undo 可能に）。
- [test/canvas_notifier_test.dart](test/canvas_notifier_test.dart): `undoLastVertex` 参照を `undo()` に更新。Phase D0 専用テスト4件を追加（初期 `canUndo`、閉じる操作の Undo、点の逐次 Undo、消しゴムの Undo）。
- `flutter analyze` / `flutter test`（46件）パス。次は実機での確認待ち。

### 2026-07-11（続き）: Phase D（頂点編集・選択移動）実装

- [lib/models/canvas_mode.dart](lib/models/canvas_mode.dart): `CanvasMode.edit` を追加（描画／消しゴム／編集の3モード）。
- [lib/providers/selected_vertex_provider.dart](lib/providers/selected_vertex_provider.dart): 編集モードで選択中の頂点ID（`StateProvider<String?>`）を新設。
- [lib/providers/vertex_drag_preview_provider.dart](lib/providers/vertex_drag_preview_provider.dart): 長押しドラッグ中の transient プレビュー（`VertexDragPreview`: 移動中の頂点ID＋指位置）を新設。Phase C の `dragPreviewProvider` と同型（`ValueNotifier`、離した瞬間だけ `Artwork` に確定）。
- [lib/providers/canvas_provider.dart](lib/providers/canvas_provider.dart): `findVertexNear`（確定ポリゴン＋下書きの全参照頂点を `findNearestPoint` で探索。描画用の `findPolygonVertexNear` とは別）と `moveVertex`（共有プールの座標更新、変更時のみ `_recordUndo`）を新設。
- [lib/widgets/canvas/polygon_canvas.dart](lib/widgets/canvas/polygon_canvas.dart): 編集モードは `onTapUp` で選択／空白で解除、`onLongPressStart`/`MoveUpdate`/`End` で頂点移動（ドラッグ中は `vertexDragPreview` のみ更新、離した瞬間に `moveVertex`）。描画・消しゴムモードは従来通り。
- [lib/widgets/canvas/polygon_painter.dart](lib/widgets/canvas/polygon_painter.dart): 編集モードで全頂点に青ハンドル、選択頂点にオレンジリング。ドラッグ中は `_positionFor` がプレビュー座標を返すため、溶接済み頂点を動かすと参照する全ポリゴン・下書き線が追従表示される。
- [lib/widgets/toolbar/editor_toolbar.dart](lib/widgets/toolbar/editor_toolbar.dart): モード切替に「編集」セグメントを追加。編集モード用の操作説明と「元に戻す」ボタンを表示。モード切替時に選択・各プレビューをクリア。
- [test/canvas_notifier_test.dart](test/canvas_notifier_test.dart): Phase D 専用テスト4件を追加（`findVertexNear`、単独移動、溶接頂点の共有追従、移動の Undo）。
- `flutter analyze` / `flutter test`（50件）パス。

**実機テスト結果（同日）**: 編集モード切替、頂点タップ選択／空白タップで解除、長押しドラッグ移動（離した瞬間に確定）、共有角を動かしたときの隣接ポリゴン追従、移動後の「元に戻す」— いずれも問題なし。Phase D 完了。

### 2026-07-11（続き）: Phase E（切り離し / 手動溶接）実装

- [lib/providers/canvas_provider.dart](lib/providers/canvas_provider.dart): `isVertexShared` / `polygonsReferencing` / `draftReferencesVertex` を新設。`detachVertexFromPolygon`（選択頂点を複製し、指定ポリゴンの参照のみ新 ID に差し替え）と `detachVertexFromDraft`（下書き側のみ差し替え）を新設。`weldVertices`（2頂点の参照を統合、連続重複を畳み、prune。ポリゴンが3点未満になる場合は拒否）を新設。いずれも `_recordUndo()` 対象。
- [lib/widgets/canvas/polygon_canvas.dart](lib/widgets/canvas/polygon_canvas.dart): 編集モードで頂点が選択済みのとき、別の頂点をタップすると `weldVertices`（選択側を keep）を試行。成功時は選択を維持し `mediumImpact`。
- [lib/widgets/toolbar/editor_toolbar.dart](lib/widgets/toolbar/editor_toolbar.dart): 共有頂点選択時にポリゴン色チップ／「下書き」ボタンで切り離し。操作説明を溶接・切り離し手順に更新。
- [test/canvas_notifier_test.dart](test/canvas_notifier_test.dart): Phase E 専用テスト6件を追加（共有角の切り離し後の独立移動、溶接と prune、溶解を伴う溶接の拒否、detach/weld の Undo、閉じる辺吸着頂点の切り離し）。
- `flutter analyze` / `flutter test`（56件）パス。

**実機テスト結果（同日）**: 共有角での2ポリゴン作成 → 編集モードで共有角選択 → ツールバーの色チップで片方を切り離し → 切り離した角のみドラッグ移動（もう一方は動かない）→ 2頂点を順タップで溶接 → 再び一緒に動く → 「元に戻す」で detach / weld が戻る — いずれも問題なし。Phase E 完了。

**所感（同日）**: 編集モードの操作説明文がやや分かりづらい（切り離し／溶接の手順が一文に詰まっている）。機能は問題ないため、UI文言・段階表示の改善は Phase H+（一般設定・仕上げ）でまとめて対応する。

### 2026-07-12: コミット運用ルール

Phase E 完了後のコミット作業で、Phase ごとの細分化が `canvas_provider.dart` 等の共有ファイルに複数 Phase の差分が混在しており困難だった。以下で合意し、[ポリゴンアプリ再設計_e54196e6.plan.md](ポリゴンアプリ再設計_e54196e6.plan.md)（マスター）の「Git / コミット運用」節に反映済み。

- **マイルストーンは実機確認後にコミット**（ユニットテストだけではタッチ操作・触覚・UI文言は拾えない）。
- **目標は Phase 完了＝1コミット**だが、同一ファイルに複数 Phase が載っているときは **無理な分割よりまとめコミットを提案** する（Phase E 時は B–D0 まとめ / D / E の3コミットになった）。
- ユーザーが「Phase 毎にコミット」と依頼しても、分割コスト＞メリットなら代替案を先に出す。

### 2026-07-13: 品質方針・v1 出荷ライン・コードレビュー統合

**品質方針（合意）**

- 早くリリースより、**破綻しない・シンプルなコードでリリース**を優先。
- 核（溶接・座標数学・transient/committed・テスト）は維持。Notifier 乱立は避け純関数抽出。
- 各 Phase は実機確認 + コード品質節のチェックリストを完了条件に含める。

**v1.0 最小出荷ライン（合意）**

- 芯: **下絵（透過）→ ズーム/パン → なぞり(F) → テッセレーション(G・既定間隔) → 編集(D/E) → 保存 → PNG**。
- 目玉: G（サラッと三角ローポリ）、下絵＋なぞり。丸だけのデモは v1 にしない。
- 見送り: G 粗さスライダー、スポイト、グリッド、SVG、リワード、Redo 永続化、下絵自由変形 等 → v1.1。
- UX: **簡易オンボーディング**（初回3ステップ or エディタ常時ヒント1行）を v1 に意図的に入れる。豪華チュートリアルは v1.1。

**コードレビュー2件の統合（Codex + Thinking 系）**

Phase A〜E 完了時点の外部レビューを「コード品質・修正前提」節に正本化。要点:

- **維持**: 溶接モデル、ViewportTransform、テスト文化は非常に良い。
- **最優先修正**: 許容距離の座標系統一（#1）、ジェスチャー継ぎ目（#2、Phase B では未カバー）、F のバッチ API（#3〜4）。
- **G 前**: Undo 上限、純幾何抽出、weld figure-8、入力サニタイズ → 後に E+ / G本番直前 に分散（追記続き2 参照）。
- **保存前**: `ArtworkDocument` と `canvasSize` 分離。Undo も幾何のみ。
- **分割**: 複数 Notifier は非推奨。純関数抽出が筋。

→ [plan_future_phases.md](plan_future_phases.md) の「品質方針」「v1.0 最小出荷ライン」「コード品質・修正前提」節、および [ポリゴンアプリ再設計_e54196e6.plan.md](ポリゴンアプリ再設計_e54196e6.plan.md)（マスター）の同名節に反映済み。frontmatter todos に `phase-e-plus` / `phase-g-spike` / `phase-h-underlay` / `phase-h-viewport` を追加し F/G/H の記述を更新。

**追記（同日続き）: 運用ルールに沿った取り消し線での復元**

2026-07-13 の本文更新時に、旧決定を削除してしまっていた。`.commit_snapshots/e/` の Phase E 完了時点の文言をもとに、以下を **~~取り消し線~~ で復元**し現行版と併記した:

- 実装順序の旧 mermaid（F→G→H+ 一括）
- Phase F / G / H+ の旧節
- テスト方針・リスクと対策の旧行
- frontmatter todos の旧文言（本文「改定済み frontmatter todos」節）
- overview の旧要約（frontmatter コメント）

改定の正本は引き続き現行フロー・現行各 Phase 節。履歴は取り消し線行 + 本検討メモを参照。

**追記（同日続き2）: 実装順序の再改定（外部レビュー反映）**

外部レビュー（2026-07-13 深夜）で、初回改定フロー `F → Hα → Hβ → G → …` に対する懸念が合意された:

1. **F と Hβ の前後**: F のジェスチャー配線（`onPanUpdate`）は Hβ の `onScale*` 書き直しで二度手間。v1 芯「拡大しながらなぞる」は Hα+Hβ 後でないと本番検証できない → **F-core（純関数）を前倒し、F-UI（ジェスチャー）は Hβ 後**に分割。
2. **G前ゲートの崖**: 6項目が G 直前に集中 → **#5/#7/#15/#16 を E+ に前倒し**、**#6/#8/#10 を G 本番直前**に分散。
3. **G の不確実性**: 目玉機能なのにドロネー未確定 → **G-spike を Hα 前**に 0.5〜2日で de-risk。
4. **オンボーディング**: v1 table に簡易版を追加（意図的に入れる）。

**改定後の実装順（正本）**: `E+ → G-spike → Hα → Hβ → F → G → Hγ → Hδ → R`

初回改定フロー `F → Hα → Hβ → …` は同日中の中間決定であり、本追記で上書き（取り消し線は不要 — 2026-07-13 内の直接上書き）。

**追記（同日続き3）: ANR・OOM対策の追記（外部レビュー反映）**

外部レビュー（2026-07-13 昼）で計画の技術的な死角3点の指摘を受け、事実確認の上で以下のように反映した。

1. **G のANR対策が未記載だった（新規 #17）**: ドロネー分割は数千三角形規模になり得る重い計算。これを Flutter のメインスレッド（UIスレッド）で実行すると、計算中は画面が完全にフリーズし、OS に「応答なし」と判断されてアプリが強制終了（ANR）されるリスクがある。これまでの計画は「G-spike でパッケージを選ぶ」「G 本番で実装する」としか書いておらず、**どのスレッドで実行するか**が空白だった。→ Phase G-spike / Phase G の実装項目・完了条件、コード品質節の負債表（#17）、着手前チェックリスト、リスクと対策に追記。方針: 重い幾何計算は `compute()`（Isolate）で非同期化し、計算中はローディングインジケータを表示する。
2. **Hα のOOM対策が未記載だった（新規 #18）**: 最近の端末カメラで撮影した写真は4K以上の高解像度が普通で、これをリサイズせずそのままメモリに展開すると、デコード時点でネイティブメモリを圧迫し OOM（メモリ不足）でクラッシュする。これまでの計画は「ギャラリーから画像を選ぶ」としか書いておらず、**取り込む画像の解像度をどう扱うか**が空白だった。→ Phase Hα の実装項目・完了条件、コード品質節の負債表（#18）、着手前チェックリスト（新設「Hα の前」）、リスクと対策に追記。方針: 取り込み時に上限解像度（例: 長辺2048px程度）へダウンサンプリングしてから保持・表示する。
3. **なぞり中のダブルタップ排他（指摘3点目）は対応済みと確認**: Phase F-UI の節（「なぞりモードでは暗黙クローズ（疑似ダブルタップ）を無効化」）と「追加すべきテスト」節（なぞり終了時の close ポリシー）に既に明記されていたため、追加対応は不要と判断（レビュー側の見落としと思われる）。本文への追記はしていない。

いずれも「後から入れると作り直しになる」性質の設計判断（実行スレッドモデル・画像取込パイプライン）であり、実装着手前の今のうちに計画へ反映した。既存の決定を覆すものではなく、これまで明示されていなかった要件の追記のため、本文側は運用ルールの「単純な情報追加」に該当すると判断して直接追記した。ただし既存の「完了条件」文は要件が増える分、内容が変わって見えるため ~~取り消し線~~ を引いた旧文を残し、新文を並記した（G-spike／Hα／G の3箇所、[plan_future_phases.md](plan_future_phases.md) 参照）。

### 2026-07-14（追記続き4）: 統合・不確定要素・G 三角サイズ（外部レビュー + 内部検討）

**背景**: 構造的リスク・統合テスト・計画書肥大化への不安を受け、外部レビュー指摘のうち v1 停滞に直結する項目のみ計画へ反映。あわせて G の三角サイズを ~~spacing 単一~~ から **maxEdge/minEdge** に変更する方針を検討・合意。

**採用した反映（本文）**:
1. **不確定要素 U1〜U5** — 特に U1（ArtworkDocument @ G-spike）、U2（統合 smoke）、U5（maxEdge world 値 @ G 着手前相談）。
2. **統合 smoke チェックリスト** — v1 は手動。Hγ/R でフル実行。E2E 自動化は v1.1。
3. **CI 推奨** — `flutter analyze` + `flutter test` のみ。
4. **#19 失敗系**、Phase × タッチポイント表、#9 タイミング分割。
5. **G #20 / Tier B/C** — maxEdge 主 + minEdge = max × 0.4。Go=Tier B、No-Go=Tier C。

**G の maxEdge/minEdge — 計画時点で world 値を書かない理由**:
- キャンバス world サイズ（Hα 下絵フィット）・なぞり点間隔（F）・ズーム後の見え方（Hβ）が揃う前に数値を固定すると、ローポリ粒度が実機とズレる。
- **方針と品質基準（max 超え禁止）は計画で固定。具体的な world 値は G 本番着手前に相談で確定**してから `lib/` に反映する。
- G-spike では **仮値** で Tier B/C と max 超え検証のみ行う。

**計画書に載せなかったもの（スコープ外）**:
- Cursor/API 従量課金の予算管理 → 開発運用メモ。
- 長期 OS/依存ライブラリ更新ルール → v1 出荷後の運用メモ（リリース後に dogfooding しながら決めれば足りる）。

**取り消し線を使った箇所**: Phase G の ~~spacing 既定間隔~~ 仕様 → maxEdge/minEdge 仕様（2026-07-14）。#9 着手タイミング列、G 完了条件（[plan_future_phases.md](plan_future_phases.md) 参照）。

### 2026-07-14（追記続き5）: Phase E+ 実装完了

**現在のステータス**（当時は別ファイル `現行サマリ.md` に記載）に沿って Phase E+ の4項目（#5, #7, #15, #16）を実装。

- **#5 Undo スタック上限**: `kUndoStackLimit = 100`。`_recordUndo()` で超過時に最古の1件を破棄する単純な cap 方式を採用（`UndoHistory<Artwork>` クラス化は Redo 対応が必要になる Phase H+ まで見送り — 今は複雑さに見合わない）。
- **#7 `weldVertices` figure-8 対策**: 「弾くか正規化」の二択のうち **弾く**（reject）を採用。四角形の対角2頂点を溶接するなど、合体後のリング／下書きに「連続ではない重複頂点 ID」が残る場合は `weldVertices` が `false` を返し何も変更しない。正規化（自己交差ポリゴンを2つに分割する等）は複雑さに対して E+ の目的（G前の崖を薄く分散）に合わず見送り。既存の「溶解防止」チェックと同じ場所（`_canWeldVertices`）に実装したため、他の挙動への回帰なし。
- **#15 / #16**: テストのみ追加（実装は既存のまま）。`clearDraft` / `clearAll` の Undo 復元3件、`detachVertexFromDraft` の共有分離・no-op系・Undo復元4件。

**確認**: `flutter analyze` 0件 / `flutter test` 66件（新規10件）パス。実機確認は本 Phase の完了条件外（ロジックのみ、着手前チェックリストの通り）。

→ frontmatter `phase-e-plus` を `completed` に更新済み（マスターファイル）。`overview` を「Phase A〜E+ 完了。次は G-spike→…」に更新済み。Phase E+ の完了済み仕様全文は [plan_future_phases.md](plan_future_phases.md) を参照。次は **Phase G-spike**。

**追記: 2026-07-15 パッケージ検証完了**
- **選定**: `delaunay` (v3.0.0)。純Dart実装でMapboxのアルゴリズム移植版。
- **結果**: 四角形・五角形の分割、および縮退入力（同一直線）での例外不発生（空リスト返却）を確認。
- **懸念**: 入出力が `Float32List` のため、`Offset` (64bit double) との往復で精度劣化がないか、G本番着手前に要確認。

**追記: 2026-07-15 Isolate（compute()）実行可否検証完了（#17）**
- 10,000点規模のダミー座標で `compute(_triangulateOffMainThread, coords)` を実行し、メインスレッド直接実行と完全一致する三角形リストが返ることを確認（`test/spike_tessellation_test.dart`）。
- Isolate 境界を越える引数・戻り値は `Float32List`/`Uint32List` のみで、クロージャや共有状態を持たないトップレベル関数のみで完結できることを確認 — G 本番でも同じ形（純関数 + `compute()`）で ANR 対策を実装できる見込み。

**追記: 2026-07-15 紙上設計（Artwork投入 ＆ Documentスキーマ）**

**1. Artwork 投入のデータ変換設計**
- **課題**: `delaunay` パッケージの出力はフラットな数値リスト（`Float32List`の座標、`Uint32List`の頂点インデックス）だが、既存の `Artwork` モデルはUUIDベースの `Vertex` プールと `Polygon` オブジェクトである。
- **変換フロー**:
  1. `delaunay.coords`（Float32List）を読み、`(x, y)` ごとに新規UUIDを生成して `Vertex` を作成。`Map<String, Vertex>`（プール）に格納すると同時に、「配列のインデックス番号」と「生成したUUID」の対応表（List等）を作成する。
  2. `delaunay.triangles`（Uint32List）を3つずつ読み（a, b, c）、対応表からUUIDを引き当てて `[uuid_a, uuid_b, uuid_c]` のリストを作成。
  3. それを `vertexIds` とする `Polygon` インスタンスを生成し、リストに追加する。
- **精度**: `Float32List`（32bit）から `Offset`（64bit）への変換となるが、モバイル画面のピクセル座標としては十分な精度とみなす。
- **Go/No-Go**: 上記フローは既存 `Artwork` モデル（`Map<String, Vertex>` + `vertexIds` を持つ `PolygonShape`）にそのまま流し込める。追加の変換層（インデックス↔UUID対応表の生成のみ）で対応可能、モデル自体の変更は不要と判断 → **Go**（Tier B/C いずれでも共通して使える変換）。

**2. ArtworkDocument v1 スキーマ設計（U1 / #9）**

保存・復元のためのJSONスキーマ構造を以下のように確定する。

- **`canvasSize` の非永続化**: 端末ごとの画面サイズ依存を避けるため、JSONには絶対保存しない。読み込み時に現在の端末のViewまたは下絵（Underlay）のサイズに合わせて動的にフィットさせる。
- **スキーマ構造（Draft）**:
  ```json
  {
    "version": 1,
    "artwork": {
      "vertices": { "uuid-1": { "x": 10.0, "y": 20.0 } },
      "polygons": [
        { "id": "p-1", "vertexIds": ["uuid-1", "uuid-2", "uuid-3"], "color": 4294901760 }
      ]
    },
    "underlay": {
      "imagePath": "assets/images/sample.png",
      "layout": { "offsetX": 0.0, "offsetY": 0.0, "scale": 1.0, "opacity": 1.0 }
    }
  }
  ```
  - `version`: スキーマバージョン。将来の移行（migration）判定に使う。
  - `artwork.vertices`: UUIDキーの `Vertex` プール（座標のみ、`Float32List`→`double`変換済み）。
  - `artwork.polygons`: `id` と `vertexIds`（UUID参照）、`color`（ARGB int）を持つ配列。
  - `underlay`: 下絵の画像パスと、`UnderlayLayout`（オフセット・スケール・不透明度）。`canvasSize` は含めない（前述の理由）。`opacity` は2026-07-15 Hα実装時に追加（`UnderlayLayout` 本体に追加した不透明度フィールドをそのまま反映）。表示ON/OFF（`visible`）は非永続 — Hγ実装時に「保存対象に含めるか」を決定する（現時点では未決定）。
- **Go/No-Go**: 既存 `Artwork`/`Vertex`/`PolygonShape` の各フィールドがそのままJSONにマッピングできる（UUID・座標・色のみで、Notifier内部の一時状態は含まない）ため、追加のモデル変更は不要と判断 → **Go**。

**追記: 2026-07-15 Phase G-spike 完了とGo判定**
- **maxEdge検証（#20）**: 巨大な四角形（500×500px）に対し、`maxEdge`（仮値50.0）を超える辺を検出して分割点を追加・再分割するPoCテストが成功。無限ループや破綻なく、すべての辺を指定サイズ以下に細分化できることを証明した（44回の反復で1974点・3889三角形、最大辺長48.9pxまで収束）。
- **発見（重要・G本番への実装上の注意点）**: 辺の**厳密な中点**をそのまま追加して毎回フル再三角形化すると**収束しない**ケースを確認した。四角形の境界辺上に厳密な中点を追加すると3点が完全に一直線上（collinear）になり、`delaunay` パッケージが面積ゼロの退化三角形を生成し、元の長い辺自体が分割されずに残ってしまう（最小再現テストで実証、`test/spike_tessellation_test.dart` 参照）。**ごく僅かなランダムジッター（±0.005px程度）を分割点に加える**ことで、厳密な共線を避けて正常に収束することを確認した（メッシュ細分化で一般的な回避策）。→ **G本番の #20 実装では、分割点の生成時にジッターを加える処理が必須**（本番実装時のTODOとして明記）。
- **Go/No-Go 判定**: パッケージ（`delaunay`）、Isolate実行、および maxEdge 再分割（ジッター対策込み）のすべてが実証されたため、**【Go】（Tier B: 制約付きドロネー + max 超え再分割の実装、分割点にジッター付与）** と確定する。
- **次のアクション（実施済み）**: 本検討メモをアーカイブへ移動し、`.cursor/plans/plan_phase_G_spike.md` を `.cursor/plans/plan_phase_H_alpha.md` としてPhase Hα向けに差し替えた。

## 検討メモ（Hα、2026-07-15〜2026-07-17）

> Phase Hα 着手時点（旧 `plan_phase_H_alpha.md`）の検討メモ。Hβ 着手中の検討メモは本ファイル末尾「検討メモ（Hβ、2026-07-17）」を、F 着手中の検討メモは本ファイル末尾「検討メモ（F、2026-07-18〜2026-07-19）」を参照。G 以降の検討メモは [plan_phase_G.md](plan_phase_G.md) を参照。

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
- [lib/widgets/underlay/underlay_settings_sheet.dart](lib/widgets/underlay/underlay_settings_sheet.dart)（新設、後に廃止）: ボトムシートの内容（`SwitchListTile` + `SegmentedButton`）。`ref.watch` ではなく `ValueListenableBuilder` で `UnderlayLayoutController` を直接購読（`Provider<Controller>` 自体は変化しないため）。
- [lib/screens/editor_screen.dart](lib/screens/editor_screen.dart): AppBar に「下絵設定」ボタンを追加（下絵未選択時は無効化）。下絵表示がキャンバス上で直接確認できるようになったため、ピック成功時の一時的な `SnackBar` 通知は削除（失敗時のエラー通知のみ残す）。
- `pubspec.yaml`: `vector_math`（`Matrix4` 利用のため、推移的依存から直接依存へ明示化）を追加。
- テスト（新設）: [test/geometry/underlay_fit_test.dart](test/geometry/underlay_fit_test.dart)、[test/underlay_layout_test.dart](test/underlay_layout_test.dart)、[test/underlay_layout_provider_test.dart](test/underlay_layout_provider_test.dart)、[test/widgets/underlay_settings_sheet_test.dart](test/widgets/underlay_settings_sheet_test.dart)（シート自体は後に廃止）。

**スキーマ検討メモへの反映**: 本ファイル「2. ArtworkDocument v1 スキーマ設計（U1 / #9）」の `underlay.layout` に `opacity` フィールドを追記済み（`visible` は非永続のまま、Hγ で要否を決定）。

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

### 2026-07-16: 切り離し直後の長押しドラッグが別の多角形を掴んでしまうバグの修正（同座標タイブレークの優先度付け）

**症状（実機報告）**: 編集モードで共有頂点を切り離し（✂️）た直後、その場所を長押しして頂点を移動させようとすると、切り離した対象の多角形ではなく、隣接する（元々頂点を共有していた）別の多角形にハイライトが移り、そちらの頂点が移動してしまう。

**原因（調査結果、Askモードで事前分析→承認済み）**: `detachVertexFromPolygon`/`detachVertexFromDraft` は、切り離し先の多角形にのみ新しい頂点（元の頂点と全く同じ座標）を割り当て、他の多角形は元の頂点IDをそのまま参照し続ける。この結果、同座標に2つの独立した頂点が一時的に重なって存在する状態になる。長押し開始時のヒットテスト `CanvasNotifier.findVertexNear` は内部で純関数 `findNearestPoint`（[lib/geometry/nearest_point.dart](lib/geometry/nearest_point.dart)）に委譲しているが、同距離の候補が複数あった場合「イテレーション順で最後に出会った候補が勝つ」という仕様だった。`findVertexNear` 内部で候補集合を作る際、`Set`（挿入順を保持）を `state.polygons` の順に走査して構築するため、「新旧どちらが勝つか」は実際には**多角形リスト内での並び順**という、ユーザーの意図と無関係な実装詳細に依存していた（切り離し先の多角形が `state.polygons` の中でより前（インデックスが小さい）だと、切り離し元に残った旧頂点側が「最後の候補」としてタイブレークに勝ってしまう）。意図しない**バグ**と判断（優先度ルールは元々存在しなかった）。

**修正方針（Askモードで提案→承認済み）**: 既存の「最後の候補が勝つ」という挙動自体は変更せず、任意の優先IDが同距離タイの中に含まれる場合だけそれを優先する、というフォールバック付きの拡張とした。優先IDには `selectedVertexProvider` の値（＝ユーザーが直前まで操作していた頂点。切り離し実行直後は新しいコピー頂点のIDに更新されている）をそのまま使う。`highlightedPolygonId`（多角形単位の情報）は使わず、頂点IDである `selectedVertexId` を直接使うほうが、多角形からの逆引きが不要でシンプルなため採用しなかった。

**実装**:
- [lib/geometry/nearest_point.dart](lib/geometry/nearest_point.dart): `findNearestPoint` に任意引数 `T? preferredId` を追加。同距離タイ（`distance == closestDistance`）の分岐で、`preferredId` が絡む場合はそれを優先し、絡まない場合は既存の「最後の候補が勝つ」動作を維持するロジックに変更（既存呼び出し元・既存テストは無変更で全てパス — 後方互換）。
- [lib/providers/canvas_provider.dart](lib/providers/canvas_provider.dart): `CanvasNotifier.findVertexNear` に任意引数 `String? preferredVertexId` を追加し、そのまま `findNearestPoint` の `preferredId` へ橋渡し。
- [lib/widgets/canvas/polygon_canvas.dart](lib/widgets/canvas/polygon_canvas.dart): `startVertexDrag`（長押しドラッグ開始）と `handleEditTap`（タップでの選択/ウェルド判定）の両方で、ヒットテスト実行**前**に `ref.read(selectedVertexProvider)` を読み、`preferredVertexId` として渡すよう変更。`handleEditTap` 側も同時に修正した理由: 同じタイブレーク不具合により、切り離し直後の次のプレーンタップが「たった今切り離した頂点を自動的に再ウェルドしてしまう」という、報告されたバグとは別のより厄介な不具合につながる可能性があったため（`selected != tappedId` の分岐がウェルドを試みる）。

**テスト**:
- [test/geometry/nearest_point_test.dart](test/geometry/nearest_point_test.dart): `preferredId` タイブレークの単体テスト7件（優先IDなしなら従来通り「最後が勝つ」、タイの中の先頭/末尾どちらでも優先IDが勝つ、三者タイでも位置に関わらず優先IDが勝つ、タイに含まれない優先IDは無効、タイでない場合は優先IDより真に近い候補が勝つ、候補が1件のみのケース）。
- [test/canvas_notifier_edit_test.dart](test/canvas_notifier_edit_test.dart): `findVertexNear` の `preferredVertexId` に関する単体テスト3件。特に1件目は、`preferredVertexId` を渡さない場合に実際にバグが再現すること（`state.polygons` の並び順により、切り離し元に残った旧頂点側が返ってしまうこと）自体を確認する回帰テストとして先に作成し、意図した通りに再現することを確認した上で、2件目で `preferredVertexId` を渡すと正しく新頂点側が返ることを確認。
- [test/widget_test.dart](test/widget_test.dart): 実際に「描画→切り離し実行→長押しドラッグ」までのフルフローを再現するウィジェットテストを追加。修正を一時的に無効化して意図的にテストが失敗することを確認した上で（`Offset(150.0, 50.0)` のまま＝ドラッグが別の頂点に当たっていたことを実測）、修正を戻してパスすることを再確認済み。

**確認**: `flutter analyze` 0件 / `flutter test`（149件、新規11件）パス。実機での再現確認（同じ手順でバグが解消していること）は本タスク完了後にユーザーが実施予定。

### 2026-07-17: 頂点選択中のUX強化（長押しドラッグでの自動選択切り替え・選択解除ボタン）

**背景**: 編集モードで頂点Aを選択中に別の頂点Bを操作したい場合、従来は一度空白をタップして選択解除してからでないとBを選び直せなかった。この制約をなくし、操作の連続性を高める。

**採用した設計（Askモードで提案→承認済み）**:
- **長押しドラッグでの自動切り替え**: `onTapUp`（`handleEditTap`、ウェルド判定）と `onLongPressStart`（`startVertexDrag`、ドラッグ判定）は、Flutterのジェスチャーアリーナ機構により同じタッチシーケンスに対して片方しか発火しないことが構造上保証されている（ポリゴン全体移動の `onPan*` と `onLongPress*` の排他性導入時と同じ仕組み）ため、「タップによるウェルドが暴発しないための」追加のフラグ管理は不要と判断。既存の `startVertexDrag` はもともとヒットテストで見つかった頂点をそのまま無条件で新しい選択対象にしていたため、「A選択中にBを長押し→Bへ切り替えてそのままドラッグ開始」という挙動自体はすでに成立していた。ただし `handleEditTap` が持つ「新たに選択された瞬間のカウンタリセット」（`detachCycleIndexProvider`／`polygonCycleIndexProvider`／`edgeCycleIndexProvider`）が `startVertexDrag` 側には欠けており、切り替え後に前の頂点の巡回状態が引き継がれてしまう抜け穴があったため、これを追加する。
- **ガード条件（ユーザー指示により確定）**: 上記リセットは「新しく検出した頂点が直前の選択頂点と異なる場合」のみ実行する（`vertexId != previouslySelected`）。同一頂点への再長押し（＝選択を維持したまま位置調整のためにもう一度掴む）ではリセットしない。これにより、切り離し対象を巡回で選んだ直後にその頂点自体をドラッグで動かしても、選んでいた対象が0番目に戻ってしまうことを防ぐ。
- **選択解除ボタン**: 頂点選択中（`selectedVertexId != null`）は下段（Row 2）の右端に常設の「✖️ 選択を解除」（`Icons.close`）ボタンを配置する。共有頂点選択時（♻️/✂️の2ボタン）・非共有頂点選択時（装飾ヒント）のどちらでも同じ位置に表示されるよう、`_EditModeRow` を「`Expanded(Center(内容))` ＋ 常設の✖️」という外枠に組み替え、上段の「↩️ 元に戻す」と縦に並ぶ配置にした（どちらも"やり直し系"の安全弁であるため、位置を覚えやすくする狙い）。押下時のリセットは `selectedVertexId = null` と `detachCycleIndexProvider = 0` のみで十分（`polygonCycleIndexProvider`/`edgeCycleIndexProvider` は頂点選択中は常に `-1` のまま変化しない不変条件がすでに成立しているため、解除の瞬間に改めてリセットする必要がない — `handleEditTap` の空タップ分岐が既にこの不変条件に依拠しているのと同じ理由）。

**実装**:
- [lib/widgets/canvas/polygon_canvas.dart](lib/widgets/canvas/polygon_canvas.dart): `startVertexDrag` で、ヒットテスト前に `previouslySelected = ref.read(selectedVertexProvider)` を読み、ヒット結果 `vertexId` と比較。`vertexId != previouslySelected` のときのみ `detachCycleIndexProvider`/`polygonCycleIndexProvider`/`edgeCycleIndexProvider` をリセット（`handleEditTap` と同じ値）。同一頂点への再長押しではこれらの状態を変更しない。
- [lib/widgets/toolbar/editor_toolbar.dart](lib/widgets/toolbar/editor_toolbar.dart): `_EditModeRow` を再設計。頂点選択中は「共有頂点なら`_DetachControls`（♻️/✂️、新設のサブウィジェットとして分離）、非共有頂点なら装飾ヒント」を `Expanded(Center(...))` に包み、その右に `IconButton`（`Icons.close`、`iconSize: 28`、Tooltip「選択を解除」）を常設。押下時に `selectedVertexProvider` を `null`、`detachCycleIndexProvider` を `0` に設定。

**テスト**:
- [test/widget_test.dart](test/widget_test.dart) に新規グループ「Edit mode selected-vertex UX enhancements (2026-07-17)」を追加（4件）:
  - 頂点Aを選択→巡回カウンタ3種に非ゼロ値をセット→別の頂点Bへ直接長押しドラッグ→選択がBに切り替わり3種すべてがリセットされること。
  - 同じ頂点Aへの再長押しドラッグでは `detachCycleIndexProvider` の値が維持されること（ガード条件の確認）。
  - 「選択を解除」ボタン押下で選択が`null`に戻り、`detachCycleIndexProvider`が0になり、頂点未選択時の図形/辺トグル行（`図形を切り替え`等）が再表示されること。
  - 共有頂点選択時にも♻️/✂️と並んで「選択を解除」ボタンが表示されること。

**確認**: `flutter analyze` 0件 / `flutter test`（153件、新規4件）パス。実機での操作感確認は本タスク完了後にユーザーが実施予定。

### 2026-07-17: Phase Hα 完了、Phase Hβ へ移行（ドキュメント整理・スリム化）

Phase Hα の実装・テストがすべて完了。次フェーズ（Hβ: ズーム / パン UI）着手にあたり、コンテキスト肥大化防止のためドキュメント構成を整理した。

- 本ファイル（`plan_archive_history.md`）を新設し、`plan_future_phases.md` から「完了済みフェーズ仕様（アーカイブ）」と「検討メモ（過去アーカイブ: 2026-07-10〜07-15）」の2セクションを移動。加えて、完了した Phase Hα 自身の仕様（本ファイル「完了済みフェーズ仕様」内）と検討メモ（本節群）も、旧 `plan_phase_H_alpha.md` から本ファイルへ移動。
- `plan_phase_H_alpha.md` を `plan_phase_H_beta.md` にリネームし、内容を Phase Hβ（ズーム/パン UI）専用に再構築（詳細仕様・着手前チェックリスト・追加すべきテストを `plan_future_phases.md` から移行）。
- `plan_future_phases.md` は未着手フェーズ（F/G/Hγ/Hδ/R）の詳細・技術的負債表・テスト方針・リスクと対策の正本として残置し、移動元の跡地にはリンク案内のみを残した。
- [ポリゴンアプリ再設計_e54196e6.plan.md](ポリゴンアプリ再設計_e54196e6.plan.md)（マスター）のファイル分割案内・frontmatter todos（`phase-h-underlay` を completed に更新）も追随。

## 検討メモ（Hβ、2026-07-17）

> Phase Hβ 着手時点（旧 `plan_phase_H_beta.md`）の検討メモ。Phase F 着手中の検討メモは本ファイル末尾「検討メモ（F、2026-07-18〜2026-07-19）」を参照。Phase G 以降の検討メモは [plan_phase_G.md](plan_phase_G.md) を参照。

### 2026-07-17: 着手前提2件(許容距離のpx統一・ジェスチャー方針)を実装

**実装要件1: 許容距離の画面px統一**
- `canvas_provider.dart`: `handleDrawTap`/`closePolygon`と内部ヘルパー(`_tryCloseAtVertex`/`_handleSingleDrawTap`/`_isPseudoDoubleTap`/`_insertAbsorbedVertices`/`_closingEdgeVertices`/`_wouldCloseWithUnweldedGap`)に、省略可能パラメータ`doubleTapMaxDistance`/`lineAbsorptionTolerance`(デフォルトは既存定数)を追加し、定数の直接参照を置き換えた。
- `polygon_canvas.dart`: `hitRadius()`と同型の`doubleTapMaxDistance()`/`lineAbsorptionTolerance()`ヘルパー(定数を`viewport.value.scale`で割った値)を追加し、Notifier呼び出し時に渡すようにした。
- `editor_toolbar.dart`: 「閉じる」ボタンの`closePolygon`呼び出しにも、viewportのscaleから換算した`lineAbsorptionTolerance`を渡すよう修正。
- これにより、拡大表示中もダブルタップ許容距離・線上吸着許容距離が「画面上一定のpx」になる(ズームインするほどワールド座標上での許容範囲は狭くなる)。

**実装要件2: ジェスチャー方針(`onScale*` + `pointerCount`)**
- `viewport_gesture_provider.dart`(新設): `ViewportGestureBaseline`(不変クラス。`pointerCount`/`transform`/`focalPoint`/`hadMultiFinger`を保持)と、それを管理する`ValueNotifier`ベースの`ViewportGestureController`を追加。ジェスチャーの「サブサイクル」(`onScaleStart`が発火するたび。Flutterの`ScaleGestureRecognizer`は指の本数が変わるたびに内部的に`onEnd`+`onStart`を再発火させるため、1回の物理ジェスチャー中に複数回のサブサイクルが起こる)ごとに基準点を取り直す設計。
- `viewport_pinch.dart`(新設): 基準の`ViewportTransform`/フォーカルポイントと、現在のscale/フォーカルポイントから新しい`ViewportTransform`を計算する純粋関数`applyPinchPan`を追加。`kMinViewportScale`(0.2)/`kMaxViewportScale`(8.0)でクランプ。
- `polygon_canvas.dart`: 描画・消しゴム・編集の3モードすべてで`onPan*`を`onScale*`に置き換え(編集モードの`onLongPress*`/`onTapUp`はそのまま維持し、`onScale*`と共存させることでピンチ/パンとタップ/長押しドラッグを両立)。
  - 1本指のみのジェスチャーでは、`GestureDetector`が単一の`ScaleGestureRecognizer`しか持たない描画/消しゴムモードではアリーナが即時解決される(スロップなし)一方、タップ/長押しと競合する編集モードではスロップが掛かる、という既存の挙動差はそのまま維持される。
  - 2本目の指が追加された時点(`hadMultiFinger`が立った時点)で、進行中の1本指アクション(描画中のドラフト点・頂点ドラッグプレビューなど)を「その時点の位置で確定」してからズーム/パンに切り替える(破棄ではなく確定する方針で実装)。**→ 後日、実機フィードバックにより「破棄」方針へ修正（下記2件目のメモ参照）。**

**実装要件3: UIの追加**
- `editor_toolbar.dart`の上段(Row 1)に「全体表示に戻す」ボタン(`Icons.fit_screen`、Tooltip付き)を追加。押下時に`viewportProvider`経由で`ViewportController.reset()`(新設。`value`を`ViewportTransform.identity`にリセット)を呼ぶ。

**テスト**
- `test/geometry/viewport_pinch_test.dart`(新設): `applyPinchPan`の純粋関数テスト(scale/offsetの計算、min/maxクランプ)。
- `test/canvas_notifier_draw_test.dart`: `doubleTapMaxDistance`/`lineAbsorptionTolerance`のscale対応を検証する新規テストグループを追加(デフォルト許容距離では吸着/クローズするが、scale 2相当の狭い許容距離では吸着/クローズしないことを確認)。
- `test/widget_test.dart`: 「Phase Hβ: viewport pinch/pan gesture」テストグループを新設し、以下5件を追加(すべてパス):
  1. 2本指ピンチでフォーカルポイントを固定したままscaleが増加すること。
  2. 2本指を同方向に等速で動かす(スパン不変)パンでoffsetのみ移動し、scaleは1のままであること。
  3. 描画中に2本目の指が触れると、その時点の位置でドラフト点が確定し、以降の移動はビューポートのズーム/パンとして扱われること。
  4. 「全体表示に戻す」ボタンで任意のpan/zoom状態がidentityに戻ること。
  5. scale 2相当にズームインした状態でも、ダブルタップによる自己クローズの許容距離が画面px基準で一定に保たれること(スケール未対応バグの再発防止用リグレッションガード)。
  - ピンチ/パンの2テスト(1・2)は、実機の2本指入力を模すため、両指を小刻みに(50ステップ)インターリーブして動かす形に実装。また、1本指操作特有の副作用(描画モードでの点追加など)を避けるため、消しゴムモード(`onScaleStart`一度だけ`handleEraseTap`を呼ぶが、空のキャンバス上では無害なno-op)かつ単一の`ScaleGestureRecognizer`のみを持つ(=スロップなしでアリーナが即時解決される)状態で実行している。
- 全体: `flutter analyze`(0件)、`flutter test`(166件全パス)を確認。

### 2026-07-17: 実機フィードバックを受け、2本指ジェスチャー開始時の「確定」を「破棄（キャンセル）」に修正

**問題**: 実機でピンチ操作を試したところ、現実には2本の指が完全に同時には触れず必ずどちらかが数msec先行するため、上記の「2本目の指が触れた時点でその場の位置に確定する」という実装方針が、ドローモードで「意図しない点が打たれてしまう」というUX上の不具合として現れた。

**原因**: `ScaleGestureRecognizer._reconfigure`(Flutter SDK, `packages/flutter/lib/src/gestures/scale.dart`)は、指の本数が変化するたびに、変化後の新しい`pointerCount`を持った`onEnd`を同期的に発火させる。1本指→2本指の場合、この`onEnd`の`pointerCount`は0ではなく2(増えた後の数)になるため、`endGestureSubCycle`の判定条件(`baseline!=null && !baseline.hadMultiFinger && baseline.pointerCount<2`)が「1本指のみのジェスチャーが今まさに正常終了した」と誤認し、`commitDrawDrag`/`commitPolygonDrag`を呼んでしまっていた。

**修正**:
- `endGestureSubCycle`に`details.pointerCount == 0`(=全指が本当にリフトした「最終リリース」)という条件を追加。2本目の指が加わったことによる`onEnd`(`pointerCount>=1`)ではコミットしない。
- 各モードの`onScaleEnd`で、`endGestureSubCycle`が`false`を返した場合は「何もしない」ではなく、明示的に該当のプレビュー状態(`dragPreview`/`polygonDragPreview`)を`null`化して破棄するよう変更(Artworkは一切変更されず、Undoスタックも汚れない)。
- 編集モードの`onScaleStart`で`isViewportGesture()`が真になった際にも、防御的に`vertexDragPreview`を`null`化(長押しドラッグ中に2本目の指が加わるケースへの保険。既存のジェスチャーアリーナの仕組み上、実際にはこの経路が発火する場面は限定的だが、一貫性のため追加)。
- `test/widget_test.dart`の既存テスト「touching a second finger down mid-draw...」を「discards...」に反転させ、ドラフト頂点が一切追加されずUndo不可(`canUndo == false`)であることを検証するよう更新。編集モードの図形ドラッグにも同様のキャンセル検証テストを新規追加。
- `flutter analyze`(0件)、`flutter test`(167件全パス)を確認。

### 2026-07-17: Phase Hβ 完了、Phase F へ移行（ドキュメント整理）

Phase Hβ の実装・実機テスト（バグ修正含む）がすべて完了。次フェーズ（F: なぞりモード）着手にあたり、ドキュメント構成を整理した。

- 本ファイル（`plan_archive_history.md`）に、完了した Phase Hβ 自身の仕様（本ファイル「完了済みフェーズ仕様」内）と検討メモ（本節群）を、旧 `plan_phase_H_beta.md` から移動。
- `plan_phase_H_beta.md` を `plan_phase_F.md` にリネームし、内容を Phase F（なぞりモード）専用に再構築（詳細仕様・着手前チェックリスト（F-core / F-UI の前）・追加すべきテストを `plan_future_phases.md` から移行）。
- `plan_future_phases.md` は未着手フェーズ（G/Hγ/Hδ/R）の詳細・技術的負債表・テスト方針・リスクと対策の正本として残置し、移動元の跡地にはリンク案内のみを残した。
- [ポリゴンアプリ再設計_e54196e6.plan.md](ポリゴンアプリ再設計_e54196e6.plan.md)（マスター）のファイル分割案内・frontmatter todos（`phase-h-viewport` を completed に更新）も追随。

## 検討メモ（F、2026-07-18〜2026-07-19）

> Phase F 着手時点（旧 `plan_phase_F.md`）の検討メモ。Phase G 以降の検討メモは [plan_phase_G.md](plan_phase_G.md) を参照。

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

**残課題 / 次のステップ（当時）**

- 下絵＋ズームありでの実機確認。
- なぞりで生成した点列からポリゴンを自動生成するかどうかは v1 では見送り（ドラフトに追加するのみ、閉じるのはツールバーの「閉じる」ボタン）— 元設計どおり。

### 2026-07-19: なぞりモードのサンプリング間隔仕様変更（ワールド座標の絶対距離固定化）

**背景**: 実機確認前の見直しで、サンプリング間隔をスクリーンpx基準（ズーム率で除算）にしていると、ズームインしたまま描画し等倍表示に戻した際にキャンバス上の点が密集してしまう問題が判明。将来のユーザー指定間隔スライダー機能を見据え、ワールド座標での絶対距離固定化に方針変更。

**分析**: `generateTracePoints` 自体は座標空間に無関心な純関数（`Offset` 間のユークリッド距離のみ）のため無修正。実質的な修正は呼び出し元の `polygon_canvas.dart` の `traceVertexSpacing()`（`kTraceVertexSpacing / viewport.value.scale`）ヘルパーのみ。`kVertexHitRadius`/`kLineAbsorptionTolerance` 等の当たり判定はスクリーン基準のまま独立しているため矛盾なし（ズームインするほどヒットテストが相対的に「厳しく」感じられるUXトレードオフのみ許容、将来のスライダー導入時に再検討）。

**実装**:
- [lib/widgets/canvas/polygon_canvas.dart](lib/widgets/canvas/polygon_canvas.dart): `traceVertexSpacing()` ヘルパーを削除し、`generateTracePoints` の呼び出しで `kTraceVertexSpacing` を直接渡すよう変更。
- [lib/providers/canvas_provider.dart](lib/providers/canvas_provider.dart): `kTraceVertexSpacing` を `40.0`→`50.0` に変更。ドキュメントコメントを「呼び出し側で `/scale` すべき」から「ズーム率に関わらずワールド座標上で固定の絶対距離」である旨に修正。
- [test/widget_test.dart](test/widget_test.dart): 既存のなぞりテストのコメントを新仕様に合わせて修正。scale=2.0でもワールド座標上の頂点間隔が `kTraceVertexSpacing`（50.0）で一定であることを検証する新規テストを追加。

**確認**: `flutter analyze` 0件 / `flutter test`（全件）パス。

### 2026-07-19: Phase F 完了、Phase G へ移行（ドキュメント整理）

Phase F の実装・テストがすべて完了。次フェーズ（G: 自動テッセレーション）着手にあたり、ドキュメント構成を整理した。

- 本ファイル（`plan_archive_history.md`）に、完了した Phase F 自身の仕様（本ファイル「完了済みフェーズ仕様」内）と検討メモ（本節群）を、旧 `plan_phase_F.md` から移動。
- `plan_phase_F.md` を `plan_phase_G.md` にリネームし、内容を Phase G（自動テッセレーション）専用に再構築（詳細仕様・着手前チェックリスト（G本番直前）・追加すべきテストを `plan_future_phases.md` から移行）。
- `plan_future_phases.md` は未着手フェーズ（Hγ/Hδ/R）の詳細・技術的負債表・テスト方針・リスクと対策の正本として残置し、移動元の跡地にはリンク案内のみを残した。
- [ポリゴンアプリ再設計_e54196e6.plan.md](ポリゴンアプリ再設計_e54196e6.plan.md)（マスター）のファイル分割案内・frontmatter todos（`phase-f-trace` を completed に更新）も追随。

## 検討メモ（G、2026-07-20）

> Phase G 着手時点（旧 `plan_phase_G.md`）の検討メモ。着手中は個別の日付エントリとしてではなく、実装項目（#6/#8/#10/#17/#20）ごとに `plan_phase_G.md` 本文へ直接反映する運用だったため、本節は実装完了の要点のみを記録する。

### 2026-07-20: `triangulate` 本体実装・実機チューニング・#20 確定

- `lib/services/tessellation_service.dart` の `triangulate`（`delaunay` パッケージでの初期分割 → `maxEdge` 超え辺へのジッター付き中点挿入 → 再分割ループ、`minEdge`/`kTessellationMaxIterations` による停止）を実装。
- `test/geometry/tessellation_tuning_spike.dart`（iPhone14相当 390x844、星型・ひょうたん型ダミーポリゴン）で `maxEdge` 30/60/100/150 を視覚比較。`maxEdge: 150.0` で極端な鋭角のスリバー三角形を確認。
- スリバー対策として「新規中点の角度チェックによる棄却」案を検討したが、Askモードでの分析の結果、元の境界頂点自体の鋭角（例: 星型の先端）には無力な上、幾何的に解決不能な箇所で無限に再試行しうるため不採用と判断。妥協案として `minEdge` を従来の spike 値（10.0）より高めの `25.0` に設定することを採用。
- `kTessellationDefaultMaxEdge = 150.0`／`kTessellationDefaultMinEdge = 25.0` を確定し、`TessellationController.tessellate`（`lib/providers/tessellation_provider.dart`）の既定値に設定。スパイクスクリプトと出力SVGは検証後に削除。
- `flutter analyze` 0件 / `flutter test` 全パス。Phase G 完了。

### 2026-07-20: Phase G 完了、Phase Hγ へ移行（ドキュメント整理）

Phase G の実装・テストがすべて完了。次フェーズ（Hγ: 保存・作品一覧）着手にあたり、ドキュメント構成を整理した。

- 本ファイル（`plan_archive_history.md`）に、完了した Phase G 自身の仕様（本ファイル「完了済みフェーズ仕様」内）と検討メモ（本節群）を、旧 `plan_phase_G.md` から移動。
- `plan_phase_G.md` を `plan_phase_H_gamma.md` にリネームし、内容を Phase Hγ（保存・作品一覧）専用に再構築（詳細仕様・着手前チェックリストを `plan_future_phases.md` から移行）。
- `plan_future_phases.md` は未着手フェーズ（Hδ/R）の詳細・技術的負債表・テスト方針・リスクと対策の正本として残置し、移動元の跡地にはリンク案内のみを残した。
- [ポリゴンアプリ再設計_e54196e6.plan.md](ポリゴンアプリ再設計_e54196e6.plan.md)（マスター）のファイル分割案内・frontmatter todos（`phase-g-tessellation` を completed に更新）も追随。

### 2026-07-25: Phase G エンジン刷新（delaunay → 純 Dart poly2tri CDT）

Phase G 完了後（Hγ 着手期間中）に実施した、テッセレーションエンジンの大規模アーキテクチャ刷新の記録。

1. **エンジンの刷新**: 複雑な穴空きポリゴンへの対応とスリバー（極端に細長い三角形）排除のため、`delaunay` パッケージへの依存を完全に削除し、純 Dart 実装の poly2tri（Sweep-line algorithm）をベースとした内製 CDT エンジン（`lib/geometry/vendor/poly2tri/`）へ差し替えた。外部 pub 依存を増やさず、C++/JS 上流に忠実な shapes・predicates・Sweep・CDT ファサードを移植した。途中で検証した `dts` パッケージは古典的 CDT ではないこと等が判明し不採用、リポジトリはクリーンな状態へ戻したうえで本移植に進んだ。
2. **アダプター層**: `lib/geometry/poly2tri_adapter.dart`（`runPoly2TriCdt`）を新設し、`TessellationRequest` / `Offset` と poly2tri 間の変換を担当。`TessellationResult.points` のインデックス契約（boundary → holes flatten → Steiner）を担保。`tessellation_service.triangulate` は adapter 呼び出しに一本化した。
3. **品質精錬（Steiner 点）**: `maxEdge` / `minEdge` 制約を満たすため、`CDT.triangulate()` 前に外枠バウンディングボックス基準のグリッド Steiner を自動追加し `CDT.addPoint` で登録。内外判定・`minEdge` 近接排除・制約辺クリアランスの安全フィルターを組み込み、poly2tri が苦手とする近接点／線分上点によるクラッシュを回避した。
4. **技術的負債の排除**: `flutter pub remove delaunay` により依存を除去。旧検証用 `test/spike_tessellation_test.dart` を削除し、vendor 内の不要 getter/setter やテストの不要 `dart:ui` import 等の Linter 警告を解消。`flutter analyze` は No issues found。

関連テスト: `test/geometry/vendor/poly2tri/`、`test/services/tessellation_service_test.dart`、`test/services/tessellation_holes_test.dart`、`test/providers/tessellation_provider_test.dart`。

### 2026-07-27: Phase G 補完 — 軌跡ベース意図推定とウェイポイント制約付き経路探索

共有境界クローズ（`_sharedBoundaryClosure`）が常に幾何最短弧を返すため、既存図形の**長い方の境界**を意図的になぞっても短弧側で結合されてしまう UX 課題への対応。Ask モードで設計合意後に実装（`flutter analyze` No issues / `flutter test` 全パス）。

1. **意図推定（pure）**: `lib/geometry/boundary_intent.dart` を新設し、`inferBoundaryWaypoints` を実装。`draftVertexIds` のうち既存境界グラフ（`graph.containsKey`）上にある頂点だけを候補とし、経路端点（`fromId` / `toId`、クローズ時は draft の last→first）は必ず除外。draft は start→…→end 順、探索は end→start のため、中継候補は **draft 出現順の逆順** で返す（端→経由→始がなぞった弧と一致するようにする）。フリーハンドのみの draft は空リスト（後段フォールバック）。
2. **経由地付き探索**: `lib/geometry/polygon_graph.dart` に `findBoundaryPathViaWaypoints` を新設。`waypoints` に従い既存の `findShortestBoundaryPath` を区間ごと（`from → w1 → … → wk → to`）に呼び出し連結。いずれかの区間が `null` なら全体 `null`。`findShortestBoundaryPath` 本体および `blockedHops`（グラフ外 draft のみ禁止）は**無変更**。
3. **オーケストレーション**: `CanvasNotifier._sharedBoundaryClosure` で `inferBoundaryWaypoints` →（非空なら）`findBoundaryPathViaWaypoints` → 失敗／空なら **従来の `findShortestBoundaryPath` へフォールバック**。返却 mids の draft 既存 ID dedupe、および `closePolygon` 側の `_isSafeClosedRing` ゲートは維持。

関連テスト: `test/geometry/boundary_intent_test.dart`（新規）、`test/geometry/polygon_graph_test.dart`（`findBoundaryPathViaWaypoints` の連結・切断・空 waypoints）。
