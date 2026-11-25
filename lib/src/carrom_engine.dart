import 'dart:math' as math;

import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

/// Karambol (carrom tipi parmakla vuruşlu tahta oyunu).
///
/// Kare tahtanın dört köşesinde cep vardır. Oyuncu vurucu taşı kendi taban
/// çizgisinin üstüne koyar, parmakla fiskeler; kendi renkli taşlarını cebe
/// sokan yeniden vurur. Ortadaki kırmızı "kraliçe" sokulunca aynı ya da
/// sonraki vuruşta kendi taşınla "örtülmelidir". Vurucuyu cebe sokmak
/// fauldür. Bütün fizik saf Dart ve deterministiktir.

/// Oyun alanı (dünya birimi; 1000 × 1600 sahnenin ortasında 800 × 800).
class CBox {
  final double l, t, r, b;
  const CBox(this.l, this.t, this.r, this.b);
}

const kBoard = CBox(100, 400, 900, 1200);
const double kManR = 17, kStrikerR = 23, kPocketR = 33, kPocketInset = 30;
const double kStrikerMass = 2.6;
const double kCenterX = 500, kCenterY = 800;

/// Taban çizgileri: oyuncu 0 altta, oyuncu 1 üstte. Vurucu bu çizgide
/// [kBaseMinX, kBaseMaxX] arasında durur.
const double kBaseBottom = 1090, kBaseTop = 510, kBaseMinX = 240, kBaseMaxX = 760;

double baseY(int seat) => seat == 0 ? kBaseBottom : kBaseTop;

const kCarromPockets = [
  [100.0 + kPocketInset, 400.0 + kPocketInset],
  [900.0 - kPocketInset, 400.0 + kPocketInset],
  [100.0 + kPocketInset, 1200.0 - kPocketInset],
  [900.0 - kPocketInset, 1200.0 - kPocketInset],
];

/// Taş türleri.
const kStriker = 0, kWhite = 1, kBlack = 2, kQueen = 3;

class Man {
  double x, y, vx = 0, vy = 0;
  final double r, m;
  final int kind;
  bool live = true;
  Man(this.x, this.y, this.kind)
      : r = kind == kStriker ? kStrikerR : kManR,
        m = kind == kStriker ? kStrikerMass : 1;
  Man copy() => Man(x, y, kind)
    ..vx = vx
    ..vy = vy
    ..live = live;
  double get speed => math.sqrt(vx * vx + vy * vy);
}

/// Bir fizik adımı (iki alt adım). Cebe girenler [onPot] ile bildirilir.
/// Hareket eden taş varsa true.
bool stepCarrom(List<Man> ms, void Function(Man) onPot) {
  for (var sub = 0; sub < 2; sub++) {
    for (final a in ms) {
      if (!a.live) continue;
      a.x += a.vx / 2;
      a.y += a.vy / 2;
    }
    for (var i = 0; i < ms.length; i++) {
      final a = ms[i];
      if (!a.live) continue;
      for (var j = i + 1; j < ms.length; j++) {
        final b = ms[j];
        if (b.live) _collide(a, b, 0.9);
      }
    }
    for (final a in ms) {
      if (!a.live) continue;
      for (final p in kCarromPockets) {
        final dx = a.x - p[0], dy = a.y - p[1];
        if (dx * dx + dy * dy < kPocketR * kPocketR) {
          a
            ..live = false
            ..vx = 0
            ..vy = 0;
          onPot(a);
          break;
        }
      }
      if (a.live) _rails(a, 0.72);
    }
  }
  var moving = false;
  for (final a in ms) {
    if (!a.live) continue;
    a.vx *= 0.984;
    a.vy *= 0.984;
    if (a.speed < 0.07) {
      a.vx = 0;
      a.vy = 0;
    } else {
      moving = true;
    }
  }
  return moving;
}

void _collide(Man a, Man b, double e) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final rr = a.r + b.r;
  final d2 = dx * dx + dy * dy;
  if (d2 >= rr * rr || d2 < 1e-9) return;
  final dist = math.sqrt(d2);
  final nx = dx / dist, ny = dy / dist;
  final pen = rr - dist;
  final ta = b.m / (a.m + b.m), tb = a.m / (a.m + b.m);
  a.x -= nx * pen * ta;
  a.y -= ny * pen * ta;
  b.x += nx * pen * tb;
  b.y += ny * pen * tb;
  final rv = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
  if (rv > 0) return;
  final j = -(1 + e) * rv / (1 / a.m + 1 / b.m);
  a.vx -= j * nx / a.m;
  a.vy -= j * ny / a.m;
  b.vx += j * nx / b.m;
  b.vy += j * ny / b.m;
}

void _rails(Man a, double e) {
  if (a.x - a.r < kBoard.l) {
    a.x = kBoard.l + a.r;
    a.vx = a.vx.abs() * e;
  } else if (a.x + a.r > kBoard.r) {
    a.x = kBoard.r - a.r;
    a.vx = -a.vx.abs() * e;
  }
  if (a.y - a.r < kBoard.t) {
    a.y = kBoard.t + a.r;
    a.vy = a.vy.abs() * e;
  } else if (a.y + a.r > kBoard.b) {
    a.y = kBoard.b - a.r;
    a.vy = -a.vy.abs() * e;
  }
}

/// Vuruşun en çok adım sayısı (iki cihazda aynı).
const kCarromMaxSteps = 1400;

/// Fiske hızı: yön ve güçten.
(double, double) carromVelocity(double angle, double power) {
  final sp = 4 + power.clamp(0.0, 1.0) * 40;
  return (math.cos(angle) * sp, math.sin(angle) * sp);
}

/// Taban çizgisinde vurucunun duramayacağı (taşlarla çakışan) yer var mı.
bool strikerFits(List<Man> ms, double x, double y) {
  for (final m in ms) {
    if (!m.live || m.kind == kStriker) continue;
    final dx = m.x - x, dy = m.y - y;
    if (dx * dx + dy * dy < (kStrikerR + m.r + 1) * (kStrikerR + m.r + 1)) return false;
  }
  return true;
}

/// İstenen x'e en yakın boş yer (taban çizgisi üstünde).
double placeStriker(List<Man> ms, double want, int seat) {
  final y = baseY(seat);
  final x0 = want.clamp(kBaseMinX, kBaseMaxX);
  for (var k = 0; k <= 60; k++) {
    for (final sgn in const [1, -1]) {
      final x = x0 + sgn * k * 9;
      if (x < kBaseMinX || x > kBaseMaxX) continue;
      if (strikerFits(ms, x, y)) return x;
    }
  }
  return x0;
}

/// Taşı ortaya (doluysa en yakın boş yere) koy.
void returnToCenter(List<Man> ms, Man m) {
  m
    ..live = true
    ..vx = 0
    ..vy = 0;
  for (var ring = 0; ring < 12; ring++) {
    final n = ring == 0 ? 1 : ring * 6;
    for (var k = 0; k < n; k++) {
      final a = k * math.pi * 2 / n;
      final x = kCenterX + math.cos(a) * ring * (kManR * 2 + 2), y = kCenterY + math.sin(a) * ring * (kManR * 2 + 2);
      var ok = true;
      for (final o in ms) {
        if (identical(o, m) || !o.live || o.kind == kStriker) continue;
        if ((o.x - x) * (o.x - x) + (o.y - y) * (o.y - y) < (o.r + kManR + 1) * (o.r + kManR + 1)) {
          ok = false;
          break;
        }
      }
      if (ok) {
        m
          ..x = x
          ..y = y;
        return;
      }
    }
  }
  m
    ..x = kCenterX
    ..y = kCenterY;
}

/// Başlangıç dizilişi: ortada kraliçe, çevresinde 6, dışta 12 taş
/// (9 beyaz, 9 siyah). [0] vurucu.
List<Man> openingLayout() {
  final ms = <Man>[Man(500, kBaseBottom, kStriker)];
  const d = kManR * 2 + 0.5;
  final inner = <(double, double)>[for (var k = 0; k < 6; k++) (math.cos(k * math.pi / 3) * d, math.sin(k * math.pi / 3) * d)];
  final outer = <(double, double)>[
    for (var k = 0; k < 12; k++)
      k.isEven
          ? (math.cos(k * math.pi / 6) * d * 2, math.sin(k * math.pi / 6) * d * 2)
          : (math.cos(k * math.pi / 6) * d * math.sqrt(3), math.sin(k * math.pi / 6) * d * math.sqrt(3)),
  ];
  for (var k = 0; k < 6; k++) {
    ms.add(Man(kCenterX + inner[k].$1, kCenterY + inner[k].$2, k.isEven ? kWhite : kBlack));
  }
  for (var k = 0; k < 12; k++) {
    ms.add(Man(kCenterX + outer[k].$1, kCenterY + outer[k].$2, k.isEven ? kBlack : kWhite));
  }
  ms.add(Man(kCenterX, kCenterY, kQueen));
  return ms;
}

// ---------------------------------------------------------------------------
// Tek kişilik bölüm: beyaz taşları sınırlı vuruşta cebe sok.

class CarromLevel {
  final ArcadeMeta meta;
  final int difficulty;
  final int rounds; // 0: sınırsız
  const CarromLevel(this.meta, this.difficulty, this.rounds);
}

CarromLevel generateCarrom(LevelSpec spec) {
  final m = ArcadeMeta.of(spec);
  final d = spec.difficulty.clamp(1, 10);
  return CarromLevel(m, d, m.goal ? (d >= 7 ? 2 : 1) : 0);
}

class CarromSim extends ArcadeSim {
  final CarromLevel level;
  final List<Man> men = [];
  int round = 0, phase = 0, phaseTicks = 0;
  int shots = 0, used = 0, budget = 0;
  int target = 0, pottedRound = 0, potted = 0, boards = 0, fouls = 0, queens = 0;
  int lastEvent = 0; // 1 vuruş, 2 sokuldu, 3 çoklu, 4 faul, 5 tur bitti
  String flash = '';
  int flashTicks = 0;
  bool queenPending = false;
  // nişan
  bool aiming = false, placing = false;
  double pressX = -1, pressY = -1, curX = -1, curY = -1;
  double aimAngle = -math.pi / 2, aimPower = 0.6;
  int _pottedShot = 0, _wrongShot = 0;
  bool _foulShot = false, _queenShot = false;
  final List<ArcadeInput> botQueue = [];

  CarromSim(this.level) : super(level.meta, lives: 3) {
    setupRound();
  }

  Man get striker => men.first;

  int get rd => (level.difficulty + (level.rounds == 0 ? round ~/ 2 : 0)).clamp(1, 10);
  int get roundSeed => mixSeed([meta.seed, 7117, round]);

  void setupRound() {
    final r = SeededRandom(roundSeed);
    final d = rd;
    men
      ..clear()
      ..add(Man(500, kBaseBottom, kStriker));
    final whites = (2 + d).clamp(3, 9);
    final blacks = d <= 3 ? 0 : (d - 2).clamp(1, 5);
    final queen = d >= 5;
    void scatter(int kind, int n) {
      var placed = 0, tries = 0;
      while (placed < n && tries++ < 800) {
        final x = kBoard.l + 90 + r.nextDouble() * (kBoard.r - kBoard.l - 180);
        final y = kBoard.t + 90 + r.nextDouble() * (kBaseBottom - 90 - kBoard.t - 90);
        var ok = true;
        for (final o in men.skip(1)) {
          if ((o.x - x) * (o.x - x) + (o.y - y) * (o.y - y) < 62 * 62) ok = false;
        }
        for (final p in kCarromPockets) {
          if ((p[0] - x) * (p[0] - x) + (p[1] - y) * (p[1] - y) < 120 * 120) ok = false;
        }
        if (ok) {
          men.add(Man(x, y, kind));
          placed++;
        }
      }
    }

    scatter(kWhite, whites);
    scatter(kBlack, blacks);
    if (queen) scatter(kQueen, 1);
    target = men.where((m) => m.kind == kWhite).length;
    pottedRound = 0;
    used = 0;
    budget = target + (d <= 3 ? 6 : (d <= 7 ? 5 : 4));
    queenPending = false;
    striker
      ..x = placeStriker(men, 500, 0)
      ..y = kBaseBottom;
    aimAngle = -math.pi / 2;
    aimPower = 0.6;
  }

  double get roundProgress => target == 0 ? 1 : pottedRound / target;

  @override
  double get progress => level.rounds > 0 ? ((round + roundProgress.clamp(0.0, 1.0)) / level.rounds).clamp(0.0, 1.0) : 0;

  @override
  String get goalText => '$pottedRound/$target • ${budget - used}';

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    phaseTicks++;
    if (flashTicks > 0) flashTicks--;
    if (phase == 1) {
      if (_flight()) {
        phase = 0;
        phaseTicks = 0;
      }
      return;
    }
    _input(input);
  }

  bool inBaseStrip(double x, double y) => (y - kBaseBottom).abs() < 48 && x > kBoard.l && x < kBoard.r;

  void _input(ArcadeInput i) {
    if (i.down && i.hasPointer) {
      if (!aiming && !placing) {
        if (inBaseStrip(i.x, i.y)) {
          placing = true;
        } else {
          aiming = true;
          pressX = i.x;
          pressY = i.y;
        }
      }
      if (placing) {
        striker.x = placeStriker(men, i.x, 0);
        return;
      }
      curX = i.x;
      curY = i.y;
      dragAim(curX - pressX, curY - pressY);
      return;
    }
    if (placing && !i.down) {
      placing = false;
      return;
    }
    if (aiming && !i.down) {
      aiming = false;
      final len = math.sqrt(math.pow(curX - pressX, 2) + math.pow(curY - pressY, 2));
      if (len > 25 && aimPower > 0.05) _fire();
      return;
    }
    if (i.dirX != 0) aimAngle = clampAngle(aimAngle + i.dirX * 0.02);
    if (i.dirY != 0) aimPower = clampD(aimPower - i.dirY * 0.012, 0.1, 1);
    if (i.tap && !i.hasPointer) _fire();
  }

  /// Vurucu ileriye (taban çizgisinden tahtanın içine) fiskelenir.
  static double clampAngle(double a) {
    var x = a;
    while (x > math.pi) {
      x -= math.pi * 2;
    }
    while (x < -math.pi) {
      x += math.pi * 2;
    }
    if (x > 0) x = x > math.pi / 2 ? -math.pi + 0.12 : -0.12;
    return x.clamp(-math.pi + 0.12, -0.12);
  }

  void dragAim(double dx, double dy) {
    final vx = -dx, vy = -dy;
    final len = math.sqrt(vx * vx + vy * vy);
    if (len < 4) return;
    aimAngle = clampAngle(math.atan2(vy, vx));
    aimPower = (len / 350).clamp(0.0, 1.0);
  }

  void _fire() {
    shots++;
    used++;
    lastEvent = 1;
    _pottedShot = 0;
    _wrongShot = 0;
    _foulShot = false;
    _queenShot = false;
    final v = carromVelocity(aimAngle, aimPower);
    striker
      ..vx = v.$1
      ..vy = v.$2;
    phase = 1;
    phaseTicks = 0;
  }

  void say(String s) {
    flash = s;
    flashTicks = 70;
  }

  bool _flight() {
    final moving = stepCarrom(men, (m) {
      switch (m.kind) {
        case kStriker:
          _foulShot = true;
        case kWhite:
          _pottedShot++;
        case kBlack:
          _wrongShot++;
        default:
          _queenShot = true;
      }
    });
    if (moving && phaseTicks < kCarromMaxSteps) return false;
    for (final m in men) {
      m
        ..vx = 0
        ..vy = 0;
    }
    if (_foulShot) {
      fouls++;
      score = math.max(0, score - 50);
      say('FOUL');
      lastEvent = 4;
      // Ceza: bu vuruşta sokulan beyazlar ve bir beyaz daha ortaya döner.
      final penalty = pottedRound > 0 ? 1 : 0;
      var back = _pottedShot + penalty;
      for (final m in men) {
        if (back == 0) break;
        if (m.kind == kWhite && !m.live) {
          returnToCenter(men, m);
          back--;
        }
      }
      pottedRound -= penalty;
      for (final m in men) {
        if (m.kind == kQueen && !m.live) returnToCenter(men, m);
      }
      queenPending = false;
    } else {
      if (_pottedShot > 0) {
        pottedRound += _pottedShot;
        potted += _pottedShot;
        score += 100 * _pottedShot;
        say(_pottedShot > 1 ? 'x$_pottedShot!' : 'IN!');
        lastEvent = _pottedShot > 1 ? 3 : 2;
      }
      if (_wrongShot > 0) score = math.max(0, score - 40 * _wrongShot);
      // Kraliçe: aynı ya da sonraki vuruşta bir beyazla örtülür.
      if (_queenShot || queenPending) {
        if (_pottedShot > 0) {
          queens++;
          score += 300;
          queenPending = false;
          say('♛');
        } else if (_queenShot) {
          queenPending = true;
        } else {
          queenPending = false;
          for (final m in men) {
            if (m.kind == kQueen && !m.live) returnToCenter(men, m);
          }
        }
      }
    }
    striker
      ..live = true
      ..y = kBaseBottom
      ..x = placeStriker(men, striker.x, 0);
    if (pottedRound >= target && !queenPending) {
      boards++;
      score += (budget - used) * 50;
      _roundDone();
      return true;
    }
    if (used >= budget && !meta.zen) {
      lastEvent = 4;
      shield = 0;
      hit();
    }
    return true;
  }

  void _roundDone() {
    round++;
    lastEvent = 5;
    if (level.rounds > 0 && round >= level.rounds) {
      win();
      return;
    }
    setupRound();
  }

  @override
  void onLifeLost() {
    phase = 0;
    aiming = false;
    placing = false;
    setupRound();
  }

  @override
  bool useBooster() {
    if (over) return false;
    budget += 2;
    return true;
  }

  @override
  int get stars => won ? math.min(lifeStars(this, 3), fouls == 0 ? 3 : (fouls <= 2 ? 2 : 1)) : 0;

  @override
  Map<String, int> get stats => {
        'shots_taken': shots,
        'pieces_pocketed': potted,
        'boards_cleared': boards,
        'queens_covered': queens,
      };
}

// ---------------------------------------------------------------------------
// Yapay zekâ: hayalet taş yöntemiyle aday vuruşlar, fizikle denenir.

/// Bir vuruş adayı: vurucunun x'i, açı, güç.
typedef CarromShot = (double, double, double);

bool _clear(List<Man> ms, double x0, double y0, double x1, double y1, Set<Man> ignore, double rad) {
  final dx = x1 - x0, dy = y1 - y0;
  final len2 = dx * dx + dy * dy;
  if (len2 < 1) return true;
  for (final m in ms) {
    if (!m.live || ignore.contains(m) || m.kind == kStriker) continue;
    final t = (((m.x - x0) * dx + (m.y - y0) * dy) / len2).clamp(0.0, 1.0);
    final px = x0 + dx * t - m.x, py = y0 + dy * t - m.y;
    if (px * px + py * py < (rad + m.r) * (rad + m.r)) return false;
  }
  return true;
}

/// Hedef türleri için aday vuruşlar (geometrik maliyete göre sıralı).
List<(CarromShot, double)> carromCandidates(List<Man> ms, int seat, Set<int> kinds) {
  final y = baseY(seat);
  final dirY = seat == 0 ? -1.0 : 1.0;
  final out = <(CarromShot, double)>[];
  for (final m in ms) {
    if (!m.live || !kinds.contains(m.kind)) continue;
    for (final pk in kCarromPockets) {
      final dx = pk[0] - m.x, dy = pk[1] - m.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < 1) continue;
      final gx = m.x - dx / dist * (kManR + kStrikerR), gy = m.y - dy / dist * (kManR + kStrikerR);
      if ((gy - y) * dirY < 10) continue; // hayalet nokta tabanın önünde olmalı
      for (var k = 0; k <= 8; k++) {
        final sx = kBaseMinX + (kBaseMaxX - kBaseMinX) * k / 8;
        if (!strikerFits(ms, sx, y)) continue;
        final ax = gx - sx, ay = gy - y;
        final al = math.sqrt(ax * ax + ay * ay);
        if (al < 1) continue;
        final cut = math.acos(((ax * dx + ay * dy) / (al * dist)).clamp(-1.0, 1.0));
        if (cut > 1.2) continue;
        if (!_clear(ms, sx, y, gx, gy, {m}, kStrikerR)) continue;
        if (!_clear(ms, m.x, m.y, pk[0], pk[1], {m}, kManR)) continue;
        final cost = cut * 500 + dist + al * 0.4;
        out.add(((sx, math.atan2(ay, ax), 0), cost));
      }
    }
  }
  out.sort((a, b) => a.$2.compareTo(b.$2));
  return out;
}

/// Vuruşu kopyada sonuna kadar oynat; dönen: sokulan taşların türleri ve
/// vurucu sokuldu mu. [ms] değişir.
(List<int>, bool) simulateCarromShot(List<Man> ms, int seat, double sx, double vx, double vy) {
  final st = ms.first;
  st
    ..live = true
    ..x = sx
    ..y = baseY(seat)
    ..vx = vx
    ..vy = vy;
  final pots = <int>[];
  var foul = false;
  for (var t = 0; t < kCarromMaxSteps; t++) {
    final moving = stepCarrom(ms, (m) {
      if (m.kind == kStriker) {
        foul = true;
      } else {
        pots.add(ms.indexOf(m));
      }
    });
    if (!moving) break;
  }
  for (final m in ms) {
    m
      ..vx = 0
      ..vy = 0;
  }
  return (pots, foul);
}

/// Bantlı adaylar: hayalet noktanın üst/alt ve yan bantlara göre aynası.
List<(CarromShot, double)> carromBankCandidates(List<Man> ms, int seat, Set<int> kinds) {
  final y = baseY(seat);
  final out = <(CarromShot, double)>[];
  final far = seat == 0 ? kBoard.t + kStrikerR : kBoard.b - kStrikerR;
  for (final m in ms) {
    if (!m.live || !kinds.contains(m.kind)) continue;
    for (final pk in kCarromPockets) {
      final dx = pk[0] - m.x, dy = pk[1] - m.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < 1) continue;
      final gx = m.x - dx / dist * (kManR + kStrikerR), gy = m.y - dy / dist * (kManR + kStrikerR);
      final mirrors = <(double, double)>[
        (gx, 2 * far - gy),
        (2 * (kBoard.l + kStrikerR) - gx, gy),
        (2 * (kBoard.r - kStrikerR) - gx, gy),
      ];
      for (var k = 0; k <= 4; k++) {
        final sx = kBaseMinX + (kBaseMaxX - kBaseMinX) * k / 4;
        if (!strikerFits(ms, sx, y)) continue;
        for (final (mx, my) in mirrors) {
          final ax = mx - sx, ay = my - y;
          if ((seat == 0 && ay > -20) || (seat == 1 && ay < 20)) continue;
          // Bant sonrası geliş yönü ile cebe yön arasındaki açı.
          final inX = mx == gx ? ax : -ax, inY = mx == gx ? -ay : ay;
          final il = math.sqrt(inX * inX + inY * inY);
          final cut = math.acos(((inX * dx + inY * dy) / (il * dist)).clamp(-1.0, 1.0));
          if (cut > 1.25) continue;
          out.add(((sx, math.atan2(ay, ax), 0), cut * 500 + dist + il * 0.3));
        }
      }
    }
  }
  out.sort((a, b) => a.$2.compareTo(b.$2));
  return out;
}

/// En iyi vuruşu ara. [value]: sokulanlar ve faule göre değer.
CarromShot bestCarromShot(List<Man> ms, int seat, Set<int> kinds, double Function(List<int> pots, bool foul, List<Man> after) value,
    {int tries = 10, List<double> powers = const [0.45, 0.7, 0.95], double good = 500}) {
  final fwd = seat == 0 ? -1.0 : 1.0;
  var best = -1e18;
  CarromShot pick = (placeStriker(ms, 500, seat), fwd * math.pi / 2, 0.8);
  void tryAll(Iterable<CarromShot> shots) {
    for (final c in shots) {
      final copy = [for (final m in ms) m.copy()];
      final v = carromVelocity(c.$2, c.$3);
      final (pots, foul) = simulateCarromShot(copy, seat, c.$1, v.$1, v.$2);
      final s = value(pots, foul, copy) - c.$3 * 0.5;
      if (s > best) {
        best = s;
        pick = c;
      }
    }
  }

  tryAll([
    for (final c in carromCandidates(ms, seat, kinds).take(tries))
      for (final p in powers) (c.$1.$1, c.$1.$2, p),
  ]);
  if (best >= good) return pick;
  tryAll([
    for (final c in carromBankCandidates(ms, seat, kinds).take(tries))
      for (final p in const [0.6, 0.85, 1.0]) (c.$1.$1, c.$1.$2, p),
  ]);
  if (best >= good) return pick;
  // Yedek: taban boyunca yelpaze.
  tryAll([
    for (final sx in const [260.0, 420.0, 580.0, 740.0])
      if (strikerFits(ms, sx, baseY(seat)))
        for (var k = 1; k <= 10; k++)
          for (final p in const [0.55, 0.9]) (sx, fwd * (0.15 + (math.pi - 0.3) * k / 11), p),
  ]);
  return pick;
}

// Tek kişilik bot: girdi kuyruğu.
const double _padX = 500, _padY = 700;

/// Oyunun nicemlenmiş dokunuştan okuyacağı açı ve güç.
(double, double, int, int) realizeCarromPull(double a, double p) {
  final cx = (_padX - math.cos(a) * p * 350).roundToDouble();
  final cy = (_padY - math.sin(a) * p * 350).roundToDouble();
  final vx = -(cx - _padX), vy = -(cy - _padY);
  final len = math.sqrt(vx * vx + vy * vy);
  return (CarromSim.clampAngle(math.atan2(vy, vx)), (len / 350).clamp(0.0, 1.0), cx.toInt(), cy.toInt());
}

ArcadeInput carromBot(ArcadeSim sim) {
  final s = sim as CarromSim;
  if (s.botQueue.isNotEmpty) return s.botQueue.removeAt(0);
  if (s.phase == 1) return ArcadeInput.idle;
  if (s.aiming) return ArcadeInput(down: false, x: s.curX, y: s.curY);
  if (s.placing) return ArcadeInput.idle;
  final kinds = s.queenPending ? {kWhite} : {kWhite, if (s.pottedRound > 0 || s.target - s.pottedRound > 1) kQueen};
  final shot = bestCarromShot(s.men, 0, kinds, (pots, foul, after) {
    var v = 0.0;
    for (final i in pots) {
      final k = after[i].kind;
      v += k == kWhite ? 1000 : (k == kQueen ? 300 : -400);
    }
    if (foul) v -= 1800;
    // Sonraki vuruş için: kalan beyazların cebe yakınlığı.
    for (final m in after) {
      if (!m.live || m.kind != kWhite) continue;
      var near = 1e9;
      for (final p in kCarromPockets) {
        near = math.min(near, math.sqrt(math.pow(m.x - p[0], 2) + math.pow(m.y - p[1], 2)));
      }
      v -= near * 0.05;
    }
    return v;
  }, tries: 8);
  final sx = placeStriker(s.men, shot.$1, 0);
  final (_, _, cx, cy) = realizeCarromPull(shot.$2, shot.$3);
  s.botQueue
    ..add(ArcadeInput(down: true, x: sx.roundToDouble(), y: kBaseBottom))
    ..add(ArcadeInput(down: false, x: sx.roundToDouble(), y: kBaseBottom))
    ..add(const ArcadeInput(down: true, x: _padX, y: _padY))
    ..add(ArcadeInput(down: true, x: cx.toDouble(), y: cy.toDouble()))
    ..add(ArcadeInput(down: false, x: cx.toDouble(), y: cy.toDouble()));
  return s.botQueue.removeAt(0);
}

// ---------------------------------------------------------------------------
// İki kişilik maç (bilgisayara ya da çevrimiçi rakibe karşı).

/// Maç durumu. Oyuncu 0 beyaz (altta, ilk vuruş), oyuncu 1 siyah (üstte).
/// Kurallar (uluslararası kurallara göre sadeleştirilmiş):
///  * Kendi taşını sokan yeniden vurur; rakibin taşını sokmak ona yarar.
///  * Vurucuyu sokmak faul: o vuruşta sokulan kendi taşların ve ceza olarak
///    daha önce soktuğun bir taş ortaya döner (soktuğun taş yoksa borç kalır),
///    sıra geçer. Kraliçe de ortaya döner.
///  * Kraliçe, ilk kendi taşından önce sokulursa ortaya döner. Sokulunca aynı
///    ya da sonraki vuruşta kendi taşınla örtülmeli; örtülmezse ortaya döner.
///  * Kraliçe örtülmeden bir tarafın son taşı sokulamaz: o taşlar ortaya
///    döner ve sıra geçer.
///  * Bütün taşlarını ve kraliçeyi bitiren taraf tahtayı kazanır: rakibin
///    tahtada kalan her taşı 1 puan, kraliçeyi o örttüyse +3.
class CarromMatch {
  int turn = 0;
  int winner = -1;
  int queenOwner = -1; // örten taraf
  int queenPending = -1; // sokup örtmeyi bekleyen taraf
  final List<int> due = [0, 0];
  int lastFoul = -1;

  static int kindOf(int seat) => seat == 0 ? kWhite : kBlack;

  int onBoard(List<Man> ms, int seat) => ms.where((m) => m.live && m.kind == kindOf(seat)).length;
  int pocketedCount(List<Man> ms, int seat) => ms.where((m) => !m.live && m.kind == kindOf(seat)).length;
  bool queenLive(List<Man> ms) => ms.any((m) => m.kind == kQueen && m.live);

  void _back(List<Man> ms, int i) => returnToCenter(ms, ms[i]);

  /// Bir taşı (tür) cebinden ortaya getir; yoksa false.
  bool _returnOne(List<Man> ms, int kind) {
    for (final m in ms.reversed) {
      if (m.kind == kind && !m.live) {
        returnToCenter(ms, m);
        return true;
      }
    }
    return false;
  }

  /// Vuruş sonucu: [pots] cebe giren taşların sırası (dizideki yerleri).
  /// Taşlar fizik sonunda; bu yöntem kuralları uygular (ortaya dönüşler dahil).
  void apply(List<Man> ms, int shooter, List<int> pots, bool foul) {
    final mine = kindOf(shooter);
    final ownIdx = [for (final i in pots) if (ms[i].kind == mine) i];
    final queenIn = pots.any((i) => ms[i].kind == kQueen);
    final hadOwn = pocketedCount(ms, shooter) - ownIdx.length;
    lastFoul = -1;
    var keep = false;
    if (foul) {
      lastFoul = shooter;
      for (final i in ownIdx) {
        _back(ms, i);
      }
      if (!_returnOne(ms, mine)) due[shooter]++;
      for (final i in pots) {
        if (ms[i].kind == kQueen) _back(ms, i);
      }
      if (queenPending == shooter) {
        for (final m in ms) {
          if (m.kind == kQueen && !m.live) returnToCenter(ms, m);
        }
      }
      queenPending = -1;
    } else {
      // Borç: soktuğun taşlardan biri ortaya döner.
      var own = ownIdx.length;
      while (due[shooter] > 0 && own > 0) {
        _back(ms, ownIdx[own - 1]);
        own--;
        due[shooter]--;
      }
      if (queenIn) {
        if (hadOwn + ownIdx.length == 0) {
          for (final i in pots) {
            if (ms[i].kind == kQueen) _back(ms, i);
          }
        } else if (ownIdx.isNotEmpty) {
          queenOwner = shooter;
        } else {
          queenPending = shooter;
          keep = true;
        }
      } else if (queenPending == shooter) {
        if (ownIdx.isNotEmpty) {
          queenOwner = shooter;
        } else {
          for (final m in ms) {
            if (m.kind == kQueen && !m.live) returnToCenter(ms, m);
          }
        }
        queenPending = -1;
      }
      if (ownIdx.isNotEmpty) keep = true;
      if (queenOwner == shooter && queenPending == shooter) queenPending = -1;
    }
    // Kraliçe örtülmeden son taşlar sokulamaz.
    if (queenOwner < 0) {
      for (final seat in const [0, 1]) {
        if (onBoard(ms, seat) == 0) {
          for (final i in pots) {
            if (ms[i].kind == kindOf(seat) && !ms[i].live) _back(ms, i);
          }
          if (onBoard(ms, seat) == 0) _returnOne(ms, kindOf(seat));
          lastFoul = shooter;
          keep = false;
        }
      }
    }
    // Tahta bitti mi?
    if (queenOwner >= 0) {
      for (final seat in const [0, 1]) {
        if (onBoard(ms, seat) == 0) winner = seat;
      }
    }
    turn = keep && winner < 0 ? shooter : 1 - shooter;
  }

  /// Kazananın tahta puanı.
  int points(List<Man> ms) {
    if (winner < 0) return 0;
    return onBoard(ms, 1 - winner) + (queenOwner == winner ? 3 : 0);
  }
}

/// Maç için başlangıç dizilişi; vurucu sıradakinin tabanında.
List<Man> matchLayout() => openingLayout();

/// Taşların kısa yazımı: "x,y,canlı;…" (2 basamak).
String carromLayout(List<Man> ms) =>
    [for (final m in ms) '${m.x.toStringAsFixed(2)},${m.y.toStringAsFixed(2)},${m.live ? 1 : 0}'].join(';');

bool applyCarromLayout(List<Man> ms, String layout) {
  final parts = layout.split(';');
  if (parts.length != ms.length) return false;
  final parsed = <(double, double, bool)>[];
  for (final p in parts) {
    final f = p.split(',');
    if (f.length != 3) return false;
    final x = double.tryParse(f[0]), y = double.tryParse(f[1]);
    if (x == null || y == null || !x.isFinite || !y.isFinite) return false;
    parsed.add((x, y, f[2] == '1'));
  }
  for (var i = 0; i < ms.length; i++) {
    ms[i]
      ..x = parsed[i].$1
      ..y = parsed[i].$2
      ..live = parsed[i].$3
      ..vx = 0
      ..vy = 0;
  }
  return true;
}

/// Ağ hamlesi: "K:<vurucu x>|<vx>|<vy>|<sokulanlar>|<faul>|<son dizilim>".
class CarromShotMsg {
  final double sx, vx, vy;
  final List<int> pots;
  final bool foul;
  final String layout;
  const CarromShotMsg(this.sx, this.vx, this.vy, this.pots, this.foul, this.layout);

  String encode() => 'K:$sx|$vx|$vy|${pots.join(',')}|${foul ? 1 : 0}|$layout';

  static CarromShotMsg? decode(String m) {
    if (!m.startsWith('K:')) return null;
    final p = m.substring(2).split('|');
    if (p.length != 6) return null;
    final sx = double.tryParse(p[0]), vx = double.tryParse(p[1]), vy = double.tryParse(p[2]);
    if (sx == null || vx == null || vy == null || !vx.isFinite || !vy.isFinite || !sx.isFinite) return null;
    final pots = <int>[];
    if (p[3].isNotEmpty) {
      for (final s in p[3].split(',')) {
        final v = int.tryParse(s);
        if (v == null || v < 0 || v > 19) return null;
        pots.add(v);
      }
    }
    return CarromShotMsg(sx, vx, vy, pots, p[4] == '1', p[5]);
  }
}

/// Maç botu: kendi taşları (gerekirse kraliçe) için en iyi vuruş.
CarromShot carromMatchBot(List<Man> ms, CarromMatch match, int seat, int d, SeededRandom r) {
  final mine = CarromMatch.kindOf(seat), theirs = CarromMatch.kindOf(1 - seat);
  final canQueen = match.queenOwner < 0 && match.queenPending != seat && match.pocketedCount(ms, seat) > 0;
  final kinds = match.queenPending == seat ? {mine} : {mine, if (canQueen) kQueen};
  final shot = bestCarromShot(ms, seat, kinds, (pots, foul, after) {
    var v = 0.0;
    for (final i in pots) {
      final k = after[i].kind;
      v += k == mine ? 1000 : (k == theirs ? -600 : 500);
    }
    if (foul) v -= 2000;
    return v;
  }, tries: d >= 6 ? 10 : 6);
  final dd = d.clamp(1, 10);
  final noise = (11 - dd) * 0.012;
  final a = shot.$2 + (r.nextDouble() - r.nextDouble()) * noise;
  final p = clampD(shot.$3 + (r.nextDouble() - 0.5) * noise * 2, 0.2, 1.0);
  return (shot.$1, a, p);
}
