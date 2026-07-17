# Phase Hβ: ズーム / パン UI（現在着手中）

> **正本の位置づけ**: 全体像・確定した設計判断・品質方針・リリース要件は [ポリゴンアプリ再設計_e54196e6.plan.md](ポリゴンアプリ再設計_e54196e6.plan.md)（マスター）を参照。未着手フェーズ（F/G/Hγ/Hδ/R）の詳細・技術的負債表・テスト方針・リスクと対策は [plan_future_phases.md](plan_future_phases.md) を参照。完了済みフェーズ（A〜E+、G-spike、Hα）の実装済み仕様・過去（2026-07-10〜07-17）の検討メモは [plan_archive_history.md](plan_archive_history.md) を参照。着手時の進捗・次ステップは下記 **現在のステータス** を参照。
> **運用**: 本ファイルは「現在着手中のフェーズ」専用ファイル。ファイル名にフェーズ名を含める（`plan_phase_<フェーズ>.md`）運用とし、Hβ が完了し次のフェーズ（F）に進んだら、本ファイルの中身を F の詳細（[plan_future_phases.md](plan_future_phases.md) から該当セクションを移動）に差し替え、ファイル名も `plan_phase_F.md` にリネームして使い続ける（Hα → Hβ でこの運用に切り替え済み、2026-07-17）。Hβ 完了時の実装完了メモ・検討メモは、差し替え時に [plan_archive_history.md](plan_archive_history.md) へ移す。Phase 完了コミット後は **現在のステータス** を次 Phase 用に更新する。

## 📍 現在のステータス (2026-07-17)
- **完了フェーズ**: Phase G-spike が大成功で完了（無限ループのバグの種もジッター付与で事前解決済み、本番実装は Tier B に確定）。Phase Hα（下絵インポート・キャンバス準備）が完了（下絵の取込・フィット表示・不透明度調整、OOM/特殊JPEG対策、モード切替時の下絵位置ズレバグの根本解決とボトムツールバーのUI/UX刷新、編集モードのUX強化（図形/辺トグル・平行移動・中点挿入・図形削除）、長押しドラッグ関連の2件のバグ修正・UX強化まで実施済み。詳細は [plan_archive_history.md](plan_archive_history.md) の「Phase Hα」節・検討メモ参照）。
- **現在のフェーズ**: Phase Hβ（ズーム / パン UI とジェスチャー方針の再設計）に着手中。着手前提（許容距離の画面px統一、ジェスチャー方針の決定 = `onScale*` + `pointerCount`、「全体表示に戻す」ボタン）は実装・テストともに完了（下記「着手前チェックリスト」・検討メモ参照）。次のステップは実機での2本指ピンチ/パン確認、および倍率表示の要否検討。

## Phase Hβ: ズーム / パン UI

> **着手前提（必須）**: 許容距離の画面 px 統一（下記「着手前チェックリスト」）。ジェスチャー方針を先に決める。→ 検討メモ（2026-07-13、[plan_archive_history.md](plan_archive_history.md)）参照。

- Phase B の `ViewportTransform` に UI を載せる。`viewport_provider` を更新。
- **ジェスチャー**: `GestureDetector` は pan と scale を同時に持てない（Flutter assert）。`onScaleStart/Update/End` + `pointerCount` で分岐:
  - **1本指**: 描画/編集（既存の確定ロジック）
  - **2本指**: ビューポートのピンチズーム + パン
- 「全体表示に戻す」ボタンをエディタに追加。倍率表示は任意。
- `kDoubleTapMaxDistance` / `kLineAbsorptionTolerance` を画面 px 基準に統一（`/ scale` または呼び出し側で換算）。

**完了条件**: 2本指でズーム/パン、1本指の描画・編集が正常。拡大後もスナップ・ダブルタップ・線上吸着が画面距離一定。`scale≠1` の統合テストあり。実機確認済み。

## 着手前チェックリスト（Hβ）

**Hβ の前**

- [x] `kDoubleTapMaxDistance` / `kLineAbsorptionTolerance` の screen px 統一を**実装**（#1、2026-07-17 完了）
- [x] ジェスチャー方針決定（`onScale*` + `pointerCount`）（#2、2026-07-17 完了）
- [x] `scale≠1` / `offset≠0` の `CoordinateTransform` テスト + hitRadius 統合テスト（2026-07-17 完了、下記「検討メモ」参照）

→ その他フェーズの着手前チェックリストは [plan_future_phases.md](plan_future_phases.md) の「着手前チェックリスト（統合、Hβ を除く）」を参照。

## 追加すべきテスト（Hβ関連）

[plan_future_phases.md](plan_future_phases.md) の「追加すべきテスト（優先度付き）」全体のうち、Hβ に直接関連する項目のみ抜粋（全項目は同ファイルを参照）:

- `scale≠1` で `hitRadius / scale` が画面距離一定になること
- `kDoubleTapMaxDistance` の scale 対応（実装後）
- Widget test: 描画 pan と zoom の競合

## 検討メモ（直近）

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
  - 2本目の指が追加された時点(`hadMultiFinger`が立った時点)で、進行中の1本指アクション(描画中のドラフト点・頂点ドラッグプレビューなど)を「その時点の位置で確定」してからズーム/パンに切り替える(破棄ではなく確定する方針で実装)。

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
