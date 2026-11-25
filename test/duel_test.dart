import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oyun_karambol/oyun_karambol.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

class FakeLink implements MatchLink {
  @override
  final int mySeat;
  @override
  final List<(int, String)> history;
  final StreamController<(int, String)> ctrl = StreamController.broadcast();
  final List<String> sent = [];
  @override
  final Set<int> dropped = {};
  int? winner;
  FakeLink(this.mySeat, {this.history = const []});
  @override
  int get seed => 5;
  @override
  List<String> get names => const ['A', 'B'];
  @override
  bool get isHost => mySeat == 0;
  @override
  Stream<(int, String)> get moves => ctrl.stream;
  @override
  Future<void> send(String move, {int? asSeat}) async => sent.add(move);
  @override
  Future<void> finish(int winner, {bool? iWon}) async => this.winner = winner;
}

PlayContext ctxFor(GeneratedLevel gl, List<RoundResult> out, {FakeLink? link}) => PlayContext(
      spec: gl.spec,
      generated: gl,
      resume: const {},
      pieceColors: const [Color(0xFF3E6FB0), Color(0xFFC8553D)],
      background: const [Color(0xFF203040), Color(0xFF304050)],
      colorBlind: false,
      reducedMotion: false,
      leftHanded: false,
      lang: 'tr',
      t: (k, [p = const {}]) => k,
      finish: out.add,
      saveResume: (_) {},
      requestHint: () async => true,
      requestBooster: () async => true,
      requestContinue: () async => false,
      sfx: (_) {},
      seats: link == null ? const [] : [for (var i = 0; i < 2; i++) i == link.mySeat ? SeatRole.local : SeatRole.remote],
      match: link,
    );

/// Bir vuruşu atan cihazda çöz, mesajı üret (ağ hamlesi).
String shoot(List<Man> men, CarromMatch m, int seat, SeededRandom r) {
  final shot = carromMatchBot(men, m, seat, 6, r);
  final sx = placeStriker(men, shot.$1, seat);
  final v = carromVelocity(shot.$2, shot.$3);
  final (pots, foul) = simulateCarromShot(men, seat, sx, v.$1, v.$2);
  final lay = carromLayout(men);
  applyCarromLayout(men, lay);
  return CarromShotMsg(sx, v.$1, v.$2, pots, foul, lay).encode();
}

void main() {
  final rules = CarromRules();
  final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: rules.optionalMechanics);

  test('iki kişilik: bilgisayara karşı ve çevrimiçi masa açık', () {
    expect(rules.localPlayers, 2);
  });

  test('başlangıç dizilişi: 9 beyaz, 9 siyah, ortada kraliçe, çakışma yok', () {
    final ms = openingLayout();
    expect(ms.where((m) => m.kind == kWhite).length, 9);
    expect(ms.where((m) => m.kind == kBlack).length, 9);
    expect(ms.where((m) => m.kind == kQueen).length, 1);
    for (var i = 1; i < ms.length; i++) {
      for (var j = i + 1; j < ms.length; j++) {
        final dx = ms[i].x - ms[j].x, dy = ms[i].y - ms[j].y;
        expect(dx * dx + dy * dy >= (2 * kManR) * (2 * kManR) - 1e-6, isTrue);
      }
    }
  });

  test('aynı vuruş aynı tahtada aynı sonucu verir (deterministik fizik)', () {
    final a = openingLayout(), b = openingLayout();
    final ra = simulateCarromShot(a, 0, 500, 0.4, -40), rb = simulateCarromShot(b, 0, 500, 0.4, -40);
    expect(rb.$1, ra.$1);
    expect(rb.$2, ra.$2);
    expect(carromLayout(b), carromLayout(a));
  });

  test('vuruş hamlesi yazılır ve okunur, bozuk hamle reddedilir', () {
    final ms = openingLayout();
    final s = CarromShotMsg(412.5, 3.25, -33.125, [3, 19], true, carromLayout(ms));
    final d = CarromShotMsg.decode(s.encode())!;
    expect(d.sx, s.sx);
    expect(d.vx, s.vx);
    expect(d.pots, [3, 19]);
    expect(d.foul, isTrue);
    expect(CarromShotMsg.decode('K:1|2|x|||'), isNull);
    expect(CarromShotMsg.decode('çöp'), isNull);
  });

  test('kurallar: vurucu faulü, kraliçe örtme, ilk taştan önce kraliçe', () {
    final ms = openingLayout();
    final m = CarromMatch();
    final queen = ms.indexWhere((x) => x.kind == kQueen);
    final w1 = ms.indexWhere((x) => x.kind == kWhite);
    // İlk taştan önce kraliçe: ortaya döner, sıra geçer.
    ms[queen].live = false;
    m.apply(ms, 0, [queen], false);
    expect(ms[queen].live, isTrue);
    expect(m.turn, 1);
    // Siyah bir taş sokar, yeniden vurur.
    final b1 = ms.indexWhere((x) => x.kind == kBlack);
    ms[b1].live = false;
    m.apply(ms, 1, [b1], false);
    expect(m.turn, 1);
    // Kraliçeyi sokar: örtmeyi bekler, yeniden vurur.
    ms[queen].live = false;
    m.apply(ms, 1, [queen], false);
    expect(m.queenPending, 1);
    expect(m.turn, 1);
    // Örtemez: kraliçe ortaya döner, sıra geçer.
    m.apply(ms, 1, [], false);
    expect(ms[queen].live, isTrue);
    expect(m.queenPending, -1);
    expect(m.turn, 0);
    // Beyaz vurucuyu sokar (faul): soktuğu yok, borç kalır.
    m.apply(ms, 0, [], true);
    expect(m.due[0], 1);
    expect(m.turn, 1);
    // Beyaz bir taş sokunca borç ödenir: taş ortaya döner.
    ms[w1].live = false;
    m.apply(ms, 0, [w1], false);
    expect(ms[w1].live, isTrue);
    expect(m.due[0], 0);
  });

  test('iki cihaz bütün maç boyunca aynı tahtada kalır ve maç biter', () {
    for (final seed in [1, 2, 3]) {
      final dev = [matchLayout(), matchLayout()];
      final mt = [CarromMatch(), CarromMatch()];
      final r = SeededRandom(seed);
      var shots = 0;
      while (mt[0].winner < 0 && shots < 400) {
        final sh = mt[0].turn;
        final msg = shoot(dev[sh], mt[sh], sh, r);
        final got = CarromShotMsg.decode(msg)!;
        final o = 1 - sh;
        simulateCarromShot(dev[o], sh, got.sx, got.vx, got.vy);
        applyCarromLayout(dev[o], got.layout);
        for (var k = 0; k < 2; k++) {
          mt[k].apply(dev[k], sh, got.pots, got.foul);
        }
        expect(carromLayout(dev[1]), carromLayout(dev[0]));
        expect(mt[1].turn, mt[0].turn);
        shots++;
      }
      expect(mt[0].winner, isNot(-1));
      expect(mt[0].queenOwner, isNot(-1));
      expect(mt[0].onBoard(dev[0], mt[0].winner), 0);
    }
  });

  testWidgets('bilgisayara karşı: bot oynar, ekran hata vermez', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final gl = rules.build(planner.spec(3));
    final out = <RoundResult>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: karambolConfig.buildPlay(ctxFor(gl, out)))));
    expect(find.byType(CarromDuelView), findsOneWidget);
    // Nişan al ve vur.
    final c = tester.getCenter(find.byType(CustomPaint).last);
    final g = await tester.startGesture(c);
    await g.moveBy(const Offset(0, 120));
    await g.up();
    for (var i = 0; i < 900; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('çevrimiçi: rakibin vuruşu gelir, tahta onun dizilimine oturur', (tester) async {
    final gl = rules.build(planner.run(GameModeId.online, 5, difficulty: 4));
    final link = FakeLink(1);
    final out = <RoundResult>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: karambolConfig.buildPlay(ctxFor(gl, out, link: link)))));
    final men = matchLayout();
    final msg = shoot(men, CarromMatch(), 0, SeededRandom(9));
    link.ctrl.add((0, msg));
    for (var i = 0; i < 1500; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('tek kişilik günlük: sahne açılır', (tester) async {
    final gl = rules.build(planner.daily('2026-11-25'));
    final out = <RoundResult>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: karambolConfig.buildPlay(ctxFor(gl, out)))));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
