// Phase G-spike: テッセレーション実現性検証用の「捨てコード」。
//
// 本番の `lib/` には一切触れず、外部パッケージ `delaunay`
// (https://pub.dev/packages/delaunay, Delaunator.js の Dart 移植版) が
// 代表的な閉曲線（四角形）を破綻なく三角分割できるかだけを確認する。
// G 本番実装の Go/No-Go 判断材料であり、このファイル自体は spike 完了後に
// 削除してよい。

import 'dart:math';
import 'dart:typed_data';

import 'package:delaunay/delaunay.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_test/flutter_test.dart';

/// [points]（画面/world 座標の頂点リスト）を `delaunay` パッケージが要求する
/// フラットな `Float32List`（[x0, y0, x1, y1, ...]）に変換する。
Float32List _toFloat32List(List<Offset> points) {
  final coords = Float32List(points.length * 2);
  for (var i = 0; i < points.length; i++) {
    coords[i * 2] = points[i].dx;
    coords[i * 2 + 1] = points[i].dy;
  }
  return coords;
}

/// `delaunay.triangles`（頂点インデックスのフラットな3つ組リスト）を
/// 3頂点ずつのグループ（三角形1つ分のインデックス3つ組）に読み替える。
List<(int, int, int)> _groupTriangles(List<int> triangles) {
  assert(triangles.length % 3 == 0);
  return [
    for (var i = 0; i < triangles.length; i += 3)
      (triangles[i], triangles[i + 1], triangles[i + 2]),
  ];
}

/// [compute] に渡すための Isolate 実行対象。クロージャは不可なので、外部
/// 状態を一切参照しないトップレベル関数として定義する（引数の [coords] と
/// 戻り値だけを Isolate 境界越しにコピーする）。
///
/// G-spike 要件 #17（ANR 対策）の検証本体: 重いドロネー分割をメインスレッド
/// から追い出せるかを確認するため、本番同様に `Delaunay(coords)..update()`
/// を呼ぶだけの薄いラッパーとする。
Uint32List _triangulateOffMainThread(Float32List coords) {
  final delaunay = Delaunay(coords)..update();
  return delaunay.triangles;
}

/// 数千三角形規模を想定したダミー座標（[count] 点、0〜1000 の範囲にランダム
/// 配置）を生成する。シード固定で再現可能にしておく。
Float32List _generateRandomCoords(int count, {int seed = 42}) {
  final random = Random(seed);
  final coords = Float32List(count * 2);
  for (var i = 0; i < coords.length; i++) {
    coords[i] = random.nextDouble() * 1000;
  }
  return coords;
}

/// 2点間のユークリッド距離（ピクセル距離）。
double _edgeLength(Offset a, Offset b) => (a - b).distance;

/// [a] と [b] の「ジッター付き中点」。厳密な中点だと、辺の両端＋中点の3点
/// が完全に一直線上（collinear）になってしまい、`delaunay` パッケージが
/// 退化（面積ゼロ）三角形を生成して、当の辺がいつまでも分割されずに残る
/// ケースがある（下記テスト内で実際に再現・記録）。ごく僅かな乱数オフ
/// セット（[jitter]、既定 0.01px = 見た目に影響しない誤差）を加えて厳密
/// な共線を避けるのは、メッシュ細分化で一般的に使われる回避策。
Offset _jitteredMidpoint(
  Offset a,
  Offset b,
  Random random, {
  double jitter = 0.01,
}) {
  return Offset(
    (a.dx + b.dx) / 2 + (random.nextDouble() - 0.5) * jitter,
    (a.dy + b.dy) / 2 + (random.nextDouble() - 0.5) * jitter,
  );
}

/// [triangleGroups] が指す各三角形の3辺すべてを (始点インデックス, 終点イ
/// ンデックス) の組として列挙する。
Iterable<(int, int)> _edgesOf((int, int, int) triangle) {
  final (a, b, c) = triangle;
  return [(a, b), (b, c), (c, a)];
}

void main() {
  group('Phase G-spike: delaunay package tessellation', () {
    test(
      '代表閉曲線（四角形）を三角分割し、既存 Artwork 相当の頂点/三角形に変換できる',
      () {
        // 代表閉曲線: シンプルな四角形（正方形）。
        const square = [
          Offset(0, 0),
          Offset(100, 0),
          Offset(100, 100),
          Offset(0, 100),
        ];

        final delaunay = Delaunay(_toFloat32List(square))..update();

        // 四角形 = 2つの三角形に分割されるはず（縮退や例外なし）。
        final triangleGroups = _groupTriangles(delaunay.triangles);
        expect(delaunay.triangles.length % 3, 0);
        expect(triangleGroups, hasLength(2));

        // 三角形が指す頂点インデックスは、すべて入力頂点(4点)の範囲内。
        for (final (a, b, c) in triangleGroups) {
          for (final index in [a, b, c]) {
            expect(index, inInclusiveRange(0, square.length - 1));
          }
          // 縮退三角形（3頂点が同一）が出力されていないことを確認。
          expect({a, b, c}, hasLength(3));
        }

        // delaunay.coords から Artwork 側の Offset 表現に戻せることを確認
        // （紙上設計での「Artwork へ投入できるか」の検証に相当）。
        final rebuiltVertices = [
          for (var i = 0; i < delaunay.coords.length; i += 2)
            Offset(delaunay.coords[i], delaunay.coords[i + 1]),
        ];
        expect(rebuiltVertices, hasLength(square.length));
        for (final original in square) {
          expect(rebuiltVertices, contains(original));
        }
      },
    );

    test('自己交差していない凸五角形も破綻なく三角分割できる', () {
      const pentagon = [
        Offset(50, 0),
        Offset(100, 40),
        Offset(80, 100),
        Offset(20, 100),
        Offset(0, 40),
      ];

      final delaunay = Delaunay(_toFloat32List(pentagon))..update();
      final triangleGroups = _groupTriangles(delaunay.triangles);

      // n 頂点の凸多角形は (n - 2) 個の三角形に分割される。
      expect(triangleGroups, hasLength(pentagon.length - 2));
    });

    test('縮退入力（3点未満・全点が同一直線上）でも例外を投げずに扱える', () {
      // 三角形すら作れない縮退入力: 三角化不可でも例外にせず空の結果を返す
      // ことを期待する（G 本番 #8 の「壊れ方の材料」に相当）。
      const collinear = [Offset(0, 0), Offset(50, 0), Offset(100, 0)];

      final delaunay = Delaunay(_toFloat32List(collinear))..update();

      // 縮退入力では三角形が1つも生成されない（例外は投げない）。
      expect(delaunay.triangles, isEmpty);
    });
  });

  group('Phase G-spike: Isolate (compute) offload (#17)', () {
    test(
      '10,000点規模のドロネー分割を compute() 経由でメインスレッド外に'
      '追い出しても、正しく三角形リストが返る',
      () async {
        final coords = _generateRandomCoords(10000);

        final triangles = await compute(_triangulateOffMainThread, coords);

        // メインスレッド実行と結果が一致すること（Isolate 境界を越えても
        // 計算結果が変質しないことの確認）。
        final expected = _triangulateOffMainThread(coords);
        expect(triangles, equals(expected));

        // 数千点規模なら当然、三角形は1つ以上生成される。
        expect(triangles, isNotEmpty);
        expect(triangles.length % 3, 0);
      },
    );
  });

  group('Phase G-spike: maxEdge 超え三角の再分割 PoC (#20)', () {
    test(
      '発見: 辺の厳密な中点を追加すると、3点が完全に一直線上（collinear）'
      'になり退化（面積ゼロ）三角形が生成され、その辺自体は分割されずに'
      '残ってしまうことがある（delaunay パッケージの既知の限界）',
      () {
        // 下辺 (0,0)-(500,0) のちょうど中点 (250,0) を追加しても、この
        // 3点は完全に一直線上にあるため、再三角形化の結果に元の 500px の
        // 辺がそのまま生き残ってしまう。
        const points = [
          Offset(0, 0),
          Offset(500, 0),
          Offset(500, 500),
          Offset(0, 500),
          Offset(250, 0), // 下辺の厳密な（ジッターなし）中点
        ];

        final delaunay = Delaunay(_toFloat32List(points))..update();
        final triangleGroups = _groupTriangles(delaunay.triangles);

        // 下辺の元の両端（index 0 = (0,0), index 1 = (500,0)）を直接つな
        // ぐ辺が、三角形化の結果にまだ残っているかを確認する。
        final bottomEdgeStillIntact = triangleGroups.any(
          (triangle) => _edgesOf(triangle).any(
            (edge) =>
                (edge.$1 == 0 && edge.$2 == 1) ||
                (edge.$1 == 1 && edge.$2 == 0),
          ),
        );

        // 中点 (250,0) を追加したにもかかわらず、元の 500px の辺
        // (0,0)-(500,0) 自体がそのまま生き残っている。
        // → 「中点をそのまま追加して再三角形化するだけ」では maxEdge
        // 制約を満たせないケースがある、という G 本番 #8 向けの知見。
        // 次のテストでは、ごく僅かなジッターでこれを回避する。
        expect(bottomEdgeStillIntact, isTrue);
        expect(_edgeLength(points[0], points[1]), 500.0);
      },
    );

    test(
      '巨大な四角形を maxEdge を超えない三角形群まで、ジッター付き中点分割'
      'で再分割できる（無限ループに陥らず、上記の退化ケースも回避する）',
      () {
        const maxEdge = 50.0;
        const initialSquare = [
          Offset(0, 0),
          Offset(500, 0),
          Offset(500, 500),
          Offset(0, 500),
        ];
        // 初期の四角形は対角線1本で2三角形に分割される。
        const initialTriangleCount = 2;

        final random = Random(7); // 再現性のため固定シード。
        final points = List<Offset>.of(initialSquare);

        // 無限ループ防止の安全弁。ジッターありなら数十回程度で収束する
        // はずなので、これに到達したらロジックが破綻しているとみなす。
        const maxIterations = 200;

        var triangleGroups = <(int, int, int)>[];
        var iterations = 0;
        while (iterations < maxIterations) {
          iterations++;
          final delaunay = Delaunay(_toFloat32List(points))..update();
          triangleGroups = _groupTriangles(delaunay.triangles);

          // maxEdge を超える辺ごとに、ジッター付き中点を1つずつ集める
          // （上記テストで判明した「厳密な中点は退化三角形を生み、辺が
          // 分割されないことがある」問題を避けるため）。
          final midpointsToAdd = <Offset>[];
          for (final triangle in triangleGroups) {
            for (final (i, j) in _edgesOf(triangle)) {
              final a = points[i];
              final b = points[j];
              if (_edgeLength(a, b) > maxEdge) {
                midpointsToAdd.add(_jitteredMidpoint(a, b, random));
              }
            }
          }

          // 追加すべき点がもうない = 全辺が maxEdge 以下になった。
          if (midpointsToAdd.isEmpty) break;
          points.addAll(midpointsToAdd);
        }

        // 安全弁（無限ループ）に引っかからず、正常に収束したことの証明。
        expect(
          iterations,
          lessThan(maxIterations),
          reason: '$maxIterations 回以内に maxEdge 超えの辺がなくなるはず',
        );

        // 収束後の最終分割で、すべての辺が maxEdge 以下であることを確認。
        for (final triangle in triangleGroups) {
          for (final (i, j) in _edgesOf(triangle)) {
            expect(
              _edgeLength(points[i], points[j]),
              lessThanOrEqualTo(maxEdge),
            );
          }
        }

        // 初期2三角形から大幅に三角形数が増えている（実際に細分化された
        // ことの確認）。
        expect(
          triangleGroups.length,
          greaterThan(initialTriangleCount * 10),
        );
      },
    );
  });
}
