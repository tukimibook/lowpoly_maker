# Phase Hδ: PNG エクスポート

> **正本の位置づけ**: 全体像・確定した設計判断・品質方針・リリース要件は [ポリゴンアプリ再設計_e54196e6.plan.md](ポリゴンアプリ再設計_e54196e6.plan.md)（マスター）を参照。未着手フェーズ（R）の詳細・技術的負債表・テスト方針・リスクと対策は [plan_future_phases.md](plan_future_phases.md) を参照。完了済みフェーズの実装済み仕様・過去の検討メモは [plan_archive_history.md](plan_archive_history.md) を参照。着手時の進捗・次ステップは下記 **現在のステータス** を参照。
> **運用**: 本ファイルは「現在着手中のフェーズ」専用ファイル。ファイル名にフェーズ名を含める（`plan_phase_<フェーズ>.md`）運用とし、Hδ が完了し次のフェーズ（R）に進んだら、本ファイルの中身を R の詳細（[plan_future_phases.md](plan_future_phases.md) から該当セクションを移動）に差し替え、ファイル名も `plan_phase_R.md` 等にリネームして使い続ける（Hα → Hβ → F → G → Hγ → Select → Hδ でこの運用を継続、2026-08-09）。Hδ 完了時の実装完了メモ・検討メモは、差し替え時に [plan_archive_history.md](plan_archive_history.md) へ移す。Phase 完了コミット後は **現在のステータス** を次 Phase 用に更新する。

## 📍 現在のステータス (2026-08-10)

- **完了フェーズ**: Phase A〜E+・G-spike・Hα・Hβ・F・G・Hγ・Select・**Hδ（PNG エクスポート）** がすべて完了。
- **現在のフェーズ**: **Phase Hδ 完了**（2026-08-10）。実装・単体／ウィジェットテスト・Android 実機 Smoke（A〜C 合格、D は Scoped Storage によりスキップ妥当、E は処理速度上問題なし）まで閉じた。
- **次フェーズ**: Phase R（ストア公開準備）。
- **次ステップ**: 未着手フェーズ（**Phase R: ストア公開準備**など）または **v1.1 以降**のタスクへの移行。本ファイルを次フェーズ用に差し替える際は、Hδ の完了記録・検討メモを [plan_archive_history.md](plan_archive_history.md) へ移す運用とする。

## Phase Hδ: PNG エクスポート（v1 必須）

> **位置づけ**: v1 出荷ラインの「PNG 書き出し → 共有シート」を満たすマイルストーン。保存（Hγ）は完了済み。下絵・編集クロムを含まない **完成物としての標準 PNG** を、端末ギャラリー保存および OS 共有シート経由で出力する。

### 要件（`plan_future_phases.md` から移行／監査後更新）

- **標準 PNG** をデバイスのギャラリーへ保存（`gal` 等）。→ **達成済み**。
- **下絵なし出力で可**（編集中の underlay / 透過プレビュー／選択ハイライト／頂点ハンドルは含めない。確定ポリゴンの不透明塗り＋ストロークのみ）。→ **`ArtworkPngRenderer` 専用経路で達成済み**。Hγ サムネ用 `RepaintBoundary` の流用や、エクスポート用「下絵非表示フラグ」の追加は **不要**。
- **共有シート経由**の書き出し（`share_plus` 等）も提供する。→ **達成済み**。
- **出力背景の選択（新規要件・2026-08-10）**: エクスポート実行時に背景を **白** または **透過** から選べる UI（ダイアログ等）を出し、選択結果を `ArtworkPngRenderer.render` の `backgroundColor`（および透過時は透明クリア相当）へ渡す。~~現状の既定は常時白下地（`kExportBackgroundColor`）のみ~~ → **達成済み**（選択 UI → レンダラ引き渡し。ドキュメントには永続化しない）。
- 無料枠は標準 PNG。高解像度／透かし無し／SVG は v1.1 以降（エンタイトルメント継ぎ目は将来用）。
- UI 言語は v1.0 規約どおり **英語**（Tooltip / SnackBar / 背景選択ダイアログ等）。
- **プラットフォーム**: v1 本 Phase は **Android のみ**（iOS はスコープ外）。

### 完了条件

- 空でない作品から PNG を生成し、ギャラリー保存と共有シートの両経路が動作する。→ **達成済み**（実機 smoke A 含む）。
- 下絵・編集 UI クロムが PNG に混入しない。→ **達成済み**（レンダラ分離）。
- エクスポート時に背景 **白／透過** を選択でき、結果が出力 PNG に反映される。→ **達成済み**（実機 smoke A／B）。
- 巨大キャンバスでも長辺上限ガード（2048px・単一 scale）により `toImage` が端末を OOM させにくい。→ **達成済み**（実装＋実機 smoke C でアスペクト維持確認）。
- 権限拒否・失敗系でクラッシュしない（ユーザー向けメッセージを表示）。`Gal.hasAccess` / `requestAccess` による明示リクエストを含む（#19）。→ **達成済み**（実装済み。Android 13+ 実機では Scoped Storage により従来型権限ダイアログ smoke D はスキップ妥当）。
- `flutter analyze` / `flutter test` パス。実機でギャラリー保存・共有を確認（Android 13+ 含む）。→ **達成済み**。

### アーキテクチャ上の境界（実装時）

- サムネイル用 `RepaintBoundary` キャプチャ（Hγ）と **エクスポート用レンダラは分離**する（画面上の編集見た目をそのまま焼かない）。→ **分離済み**；載せ替え・統合はしない。
- レンダラはマウント中ウィジェットに依存しないこと（将来のバックグラウンドキューにも耐える）。→ **`ArtworkPngRenderer` で達成済み**。
- `ExportController` 等は失敗を swallow せず、呼び出し側が SnackBar 等で通知できる結果／メッセージを返す（#19）。→ **達成済み**（権限明示リクエスト含む）。
- 背景色選択は **エクスポート実行フローの UI 層**で行い、レンダラは受け取った色（白または透明）を塗るだけに留める（ドキュメント／作品モデルへの背景色永続化は本 Phase の必須としない）。→ **達成済み**。
- エクスポート排他: `beginExport` / `abortExport` + `_runExport` 再入防止。`isExporting`（メニュー無効）と `isWorking`（スピナー）を分離。

### ギャップ監査サマリ（2026-08-10）→ 完了時点で充足

| 項目 | 結果 |
|------|------|
| `gal` / `share_plus`（`pubspec.yaml`） | **導入済み** |
| `ArtworkPngRenderer`（下絵・編集クロムなし） | **実装済み**（白／透過対応・長辺 2048 OOM ガード含む） |
| `ExportController` + Gallery / Share ターゲット | **実装済み** |
| Editor AppBar Save / Share 導線・失敗 SnackBar | **実装済み** |
| エクスポート用下絵非表示フラグ / `RepaintBoundary` 載せ替え | **不要**（専用レンダラで充足） |
| iOS 対応 | **スコープ外**（Android 専売） |
| 出力背景 白／透過の選択 UI | **完了** |
| `toImage` 長辺上限（OOM ガード） | **完了**（単一 scale・アスペクト維持） |
| `Gal.hasAccess` / `requestAccess` 明示フロー | **完了**（render 前） |
| Android 実機 smoke | **完了**（下記検討メモ 2026-08-10） |

## 着手前チェックリスト（Hδ）

- [x] 要件↔既存コードのギャップ監査（`ArtworkPngRenderer` / `ExportController` / Editor AppBar 導線）→ 2026-08-10 完了。
- [x] 下絵・ハイライト・ドラフトが PNG に出ないこと（専用レンダラ経路で設計確認済み）。
- [x] **出力背景の選択 UI**（白／透過）と `ArtworkPngRenderer` への引き渡し
- [x] **OOM 対策**: `toImage` 前の長辺上限スケールダウン（`ArtworkPngRenderer` 内）
- [x] **権限 UX**: `Gal.hasAccess` / `requestAccess` の明示フロー（#19）
- [x] ギャラリー保存経路の **実機**確認（権限許可時、Android 13+ 含む）
- [x] 共有シート経路の **実機**確認
- [x] 権限拒否・レンダ失敗時にクラッシュせずメッセージ表示（実装済み。Android 13+ の従来型権限ダイアログ smoke は Scoped Storage によりスキップ妥当）
- [x] 空キャンバス時のエクスポート UI（無効化または no-op）の仕様固定とテスト（既存挙動の確認含む）

→ その他（R 準備・統合 smoke）は [plan_future_phases.md](plan_future_phases.md) の「着手前チェックリスト」を参照。

## 残タスク一覧（Hδ）

- [x] **出力背景の選択 UI（新規要件）** — White／Transparent → `ArtworkPngRenderer.render(..., backgroundColor: …)`（ドキュメント非永続）
- [x] **OOM 対策（長辺上限ガード）** — 長辺 2048・単一 scale でスケールダウン後にラスタライズ
- [x] **権限 UX 改善** — ギャラリー保存前に `Gal.hasAccess` / `requestAccess`、拒否時は英語メッセージ（クラッシュなし）
- [x] **実機 Smoke Test（Android）** — A〜C 合格、D スキップ妥当、E 問題なし（下記検討メモ）
- [x] **締め** — `flutter analyze` / `flutter test`、チェックリスト消化、完了記録

## 追加すべきテスト（Hδ関連）

[plan_future_phases.md](plan_future_phases.md) の「追加すべきテスト」「統合 smoke」のうち、Hδ に直接関連する項目:

- PNG 書き出し → 共有シート（smoke #5）→ **実機確認済み**
- 権限拒否時にクラッシュしない（ギャラリー/保存）（smoke #6 / #19）→ **実装済み**；Android 13+ 従来型ダイアログは Scoped Storage によりスキップ妥当
- レンダラが空 `canvasSize` や空作品で安全に振る舞うこと
- **背景白／透過**の選択結果が PNG（不透明画素／アルファ）に反映されること → **実機確認済み**
- 長辺上限ガードが巨大 `canvasSize` で出力寸法を抑え、dispose を維持すること → **実装＋アスペクト実機確認済み**
- （任意）多数ポリゴンでのメモリ挙動（下記リスク）

## リスクと対策（Hδ）

1. **OOM / メモリ圧迫**  
   - 高解像度キャンバスや大量ポリゴンをフル解像度で `toImage` すると端末メモリを圧迫しうる。  
   - ~~対策方針: 出力解像度の上限またはダウンサンプル方針をギャップ監査で確認し、必要なら上限を設ける。~~ → ~~監査結果: 長辺上限ガードは未実装。~~ → **実装済み**（`kExportMaxLongEdgePx = 2048`、単一 scale）。Hα の下絵 OOM 対策（#18）とは別経路。  
   - `Picture` / `Image` は必ず dispose する（既存レンダラの finally パターンを維持）。

2. **権限エラー・失敗系（#19）**  
   - ギャラリー権限拒否、ディスク満杯、共有シート失敗、レンダ null。  
   - 対策: 例外をアプリ全体に投げず、ユーザー向け英語メッセージを表示。テストで「hang / crash しない」を固定。  
   - ~~**残**: `hasAccess` / `requestAccess` の明示フロー~~ → **実装済み**（render 前。Android 13+ では Scoped Storage によりアプリ設定の権限メニューが空／グレーになり得るのは仕様）。

3. **編集見た目の混入**  
   - サムネ経路や `RepaintBoundary` を流用すると下絵・透過・選択枠が焼き付く。  
   - 対策: エクスポート専用レンダラのみを使う（要件どおり下絵なし）。→ **充足確認済み**。

4. **透過 PNG とギャラリー／共有先**  
   - 背景透過を選んだ場合、保存先アプリや共有先によっては黒／白で平坦化されて見えることがある。  
   - 対策: v1 は「ファイルとしてはアルファ付き PNG」を保証し、表示側の差は既知のプラットフォーム差として実機 smoke で確認する。→ **実機で確認済み**。

## 検討メモ（直近）

### 2026-08-10: Phase Hδ 完了（実装＋実機 Smoke）

**完了判定**: Phase Hδ の全要件・完了条件を満たし、**Phase Hδ 完了**とする。

**実装（要約）**:

- 出力背景選択 UI（White / Transparent、使い捨て・非永続）→ `ExportController` → `ArtworkPngRenderer`
- OOM ガード: 長辺 2048・単一 scale（アスペクト維持）＋ `canvas.scale` 後 `toImage`
- Gal 権限 UX: `hasAccess` / `requestAccess` を重い render **前**に実行。拒否は SnackBar（`Permission denied` 等）
- 排他: `_runExport` 再入防止、`beginExport` / `abortExport`、`isExporting` / `isWorking` 分離
- `AndroidManifest.xml` の `WRITE_EXTERNAL_STORAGE`（`maxSdkVersion="29"`）は既存宣言で充足

**実機 Smoke（Android）結果**:

| 項目 | 結果 |
|------|------|
| A. 白／透過背景の切り替え | **合格** |
| B. クリア塗り ＋ 透過背景の抜け | **合格** |
| C. アスペクト比の維持 | **合格** |
| D. 権限ダイアログ中の画面離脱 | **スキップ妥当**（Android 13+ Scoped Storage により従来型権限 UI が実質出ない／設定の権限がグレーになり得る） |
| E. 二重実行 | **問題なし**（処理速度上、問題となる二重実行は確認されず） |

**次**: 未着手の Phase R（ストア公開準備）または v1.1 以降へ。本ファイル差し替え時に本メモを [plan_archive_history.md](plan_archive_history.md) へ移す。

### 2026-08-10: ギャップ監査結果と出力背景（白／透過）要件の合意

**ギャップ監査（要件↔実装）の結論**:

- 必須パッケージ（`gal` / `share_plus`）、専用エクスポート描画（`ArtworkPngRenderer`）、`ExportController`、Editor の Save/Share、失敗時 SnackBar は **既に揃っている**。Hδ は「ゼロから書く」フェーズではなく、差分と品質を閉じるフェーズ。
- Hγ の `RepaintBoundary` サムネ経路とは分離済み。エクスポート用の下絵非表示フラグ追加や、エクスポートを `RepaintBoundary` へ載せ替える案は **不要**。
- iOS は本アプリ方針どおり **スコープ外**（Android 専売）。実機検証も Android（13+ 含む）に限定。

**新規合意要件**:

- エクスポート時に背景を **白** または **透過** から選択できる UI を追加し、選択を `ArtworkPngRenderer` に渡す。巨大四角形ポリゴンで背景色を代用する運用案内は、正式な背景色機能の代替にはしない（選択・テッセレーションとの干渉リスクあり。本要件でレンダラ側の背景を直接選ばせる）。

~~**残件（実装・検証）**:~~ → 同日の完了メモでクローズ。

1. ~~背景選択 UI + レンダラ引き渡し~~  
2. ~~`toImage` 長辺上限（OOM）~~  
3. ~~`Gal.hasAccess` / `requestAccess`~~  
4. ~~Android 実機 smoke（権限拒否・ギャラリー・共有）~~

### 2026-08-09: Phase Select 完了、Phase Hδ 着手（ドキュメント整理）

Select 完了に伴い、旧 `plan_phase_Select.md` を本ファイル（`plan_phase_H_delta.md`）へ差し替え。Select の完了記録は [plan_archive_history.md](plan_archive_history.md) の「検討メモ（Select）」へ移動。Hδ の要件は [plan_future_phases.md](plan_future_phases.md) から本ファイルへ引き込み、跡地はリンク案内のみとした。
