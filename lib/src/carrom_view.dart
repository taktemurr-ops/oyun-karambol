import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/app/studio_ui.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'carrom_engine.dart';

Paint _p(int c) => Paint()..color = Color(c);

Paint _stroke(int c, double w) => Paint()
  ..color = Color(c)
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round;

/// Tahta: ahşap çerçeve, cepler, taban çizgileri, orta daire ve köşe okları.
void paintCarromBoard(Canvas c) {
  c.drawRect(const Rect.fromLTWH(0, 0, kWorldW, kWorldH), _p(0xFF1A1B2E));
  final surf = Rect.fromLTRB(kBoard.l, kBoard.t, kBoard.r, kBoard.b);
  c.drawRRect(RRect.fromRectAndRadius(surf.inflate(54), const Radius.circular(26)), _p(0xFF5B3420));
  c.drawRRect(RRect.fromRectAndRadius(surf.inflate(44), const Radius.circular(20)), _p(0xFF7A4A2C));
  c.drawRect(surf, _p(0xFFF1D9A8));
  // Kontrplak damarları
  for (var y = kBoard.t + 26; y < kBoard.b; y += 52) {
    c.drawLine(Offset(kBoard.l, y), Offset(kBoard.r, y + 6), _stroke(0x14000000, 2));
  }
  final ink = _stroke(0xFF3A2A1E, 3);
  // Dört taban çizgisi (ikişer paralel çizgi, uçlarında kırmızı daire).
  for (var side = 0; side < 4; side++) {
    c.save();
    c.translate(kCenterX, kCenterY);
    c.rotate(side * math.pi / 2);
    c.translate(-kCenterX, -kCenterY);
    const y = kBaseBottom;
    c.drawLine(const Offset(kBaseMinX, y - kStrikerR), const Offset(kBaseMaxX, y - kStrikerR), ink);
    c.drawLine(const Offset(kBaseMinX, y + kStrikerR), const Offset(kBaseMaxX, y + kStrikerR), ink);
    for (final x in const [kBaseMinX, kBaseMaxX]) {
      c.drawCircle(const Offset(0, 0).translate(x, y), kStrikerR, _p(0xFFC0392B));
      c.drawCircle(const Offset(0, 0).translate(x, y), kStrikerR, ink);
    }
    c.restore();
  }
  // Köşe okları (cepten ortaya doğru).
  for (final pk in kCarromPockets) {
    final dx = kCenterX - pk[0], dy = kCenterY - pk[1];
    final l = math.sqrt(dx * dx + dy * dy);
    final ux = dx / l, uy = dy / l;
    final a = Offset(pk[0] + ux * 70, pk[1] + uy * 70), b = Offset(pk[0] + ux * 250, pk[1] + uy * 250);
    c.drawLine(a, b, ink);
    final head = Path()
      ..moveTo(b.dx + ux * 4, b.dy + uy * 4)
      ..lineTo(b.dx - ux * 22 - uy * 12, b.dy - uy * 22 + ux * 12)
      ..lineTo(b.dx - ux * 22 + uy * 12, b.dy - uy * 22 - ux * 12)
      ..close();
    c.drawPath(head, _p(0xFF3A2A1E));
  }
  // Orta daireler
  c.drawCircle(const Offset(kCenterX, kCenterY), 92, ink);
  c.drawCircle(const Offset(kCenterX, kCenterY), 20, _stroke(0xFFC0392B, 5));
  for (final pk in kCarromPockets) {
    c.drawCircle(Offset(pk[0], pk[1]), kPocketR + 5, _p(0xFF3A2A1E));
    c.drawCircle(Offset(pk[0], pk[1]), kPocketR, _p(0xFF0B0B0B));
  }
}

void _man(Canvas c, Man m, {int strikerColor = 0xFF3E6FB0}) {
  if (!m.live) return;
  final o = Offset(m.x, m.y);
  c.drawCircle(o.translate(m.r * 0.12, m.r * 0.22), m.r, _p(0x55000000));
  final base = switch (m.kind) {
    kWhite => 0xFFF4E9D8,
    kBlack => 0xFF2B2B2B,
    kQueen => 0xFFD62828,
    _ => 0xFFE9E3D6,
  };
  c.drawCircle(o, m.r, _p(base));
  final ring = m.kind == kBlack ? 0x66FFFFFF : 0x55000000;
  c.drawCircle(o, m.r * 0.68, _stroke(ring, 2.5));
  c.drawCircle(o, m.r * 0.38, _stroke(ring, 2));
  if (m.kind == kStriker) c.drawCircle(o, m.r * 0.84, _stroke(strikerColor, 5));
  c.drawCircle(o.translate(-m.r * 0.35, -m.r * 0.35), m.r * 0.22, _p(0x66FFFFFF));
}

void _aim(Canvas c, double x, double y, double a, double power) {
  final paint = _stroke(0xAA1E3A5F, 7);
  final len = 110 + power * 380;
  for (var d = 34.0; d < len; d += 32) {
    final e = math.min(d + 16, len);
    c.drawLine(Offset(x + math.cos(a) * d, y + math.sin(a) * d), Offset(x + math.cos(a) * e, y + math.sin(a) * e), paint);
  }
}

void _powerBar(Canvas c, double power) {
  const r = Rect.fromLTWH(60, 1340, 280, 30);
  c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(15)), _p(0x88000000));
  final col = Color.lerp(const Color(0xFF52B788), const Color(0xFFE63946), power)!;
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(r.left, r.top, r.width * power.clamp(0.0, 1.0), r.height), const Radius.circular(15)),
      Paint()..color = col);
}

/// Tek kişilik sahne çizimi (ArcadeStage).
void paintCarrom(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as CarromSim;
  paintCarromBoard(c);
  final st = s.striker;
  if (s.phase == 0 && !s.over) _aim(c, st.x, st.y, s.aimAngle, s.aimPower);
  for (final m in s.men.skip(1)) {
    _man(c, m);
  }
  _man(c, st, strikerColor: p.piece(0).toARGB32());
  if (s.phase == 0) _powerBar(c, s.aimPower);
  if (s.queenPending) paintText(c, '♛ ?', const Offset(840, 1355), 44, const Color(0xFFD62828));
  if (s.flashTicks > 0 && s.flash.isNotEmpty) {
    final a = (s.flashTicks / 70).clamp(0.0, 1.0);
    paintText(c, s.flash, const Offset(500, 300), 84, Colors.white.withValues(alpha: a));
  }
}

Sfx? carromSound(ArcadeSim sim) => switch ((sim as CarromSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.place,
      3 => Sfx.combo,
      4 => Sfx.error,
      5 => Sfx.clear,
      _ => null,
    };

const _tYou = ['Sen', 'You', 'Du', 'Tú', 'Vous', 'أنت', 'تو', 'את/ה', 'آپ', 'Вы', 'Ви', 'Ty', 'Ty', 'Tu', 'Te', 'Εσύ', 'Tu', 'Você', 'Jij', 'Du', 'Du', 'Du', 'Sinä', 'あなた', '나', '你', 'आप', 'আপনি', 'Kamu', 'Anda', 'คุณ', 'Bạn', 'Ikaw'];
const _tRival = ['Rakip', 'Rival', 'Gegner', 'Rival', 'Rival', 'الخصم', 'حریف', 'יריב', 'حریف', 'Соперник', 'Суперник', 'Rywal', 'Soupeř', 'Rival', 'Ellenfél', 'Αντίπαλος', 'Rivale', 'Rival', 'Tegenstander', 'Motståndare', 'Modstander', 'Motstander', 'Vastustaja', '相手', '상대', '对手', 'प्रतिद्वंद्वी', 'প্রতিদ্বন্দ্বী', 'Lawan', 'Lawan', 'คู่แข่ง', 'Đối thủ', 'Kalaban'];
const _tYourTurn = ['Senin sıran', 'Your turn', 'Du bist dran', 'Tu turno', 'À vous', 'دورك', 'نوبت توست', 'תורך', 'آپ کی باری', 'Ваш ход', 'Ваш хід', 'Twój ruch', 'Jsi na tahu', 'Rândul tău', 'Te jössz', 'Σειρά σου', 'Tocca a te', 'Sua vez', 'Jouw beurt', 'Din tur', 'Din tur', 'Din tur', 'Sinun vuorosi', 'あなたの番', '내 차례', '轮到你了', 'आपकी बारी', 'তোমার পালা', 'Giliranmu', 'Giliran anda', 'ตาของคุณ', 'Lượt của bạn', 'Iyong turno'];
const _tRivalTurn = ['Rakibin sırası', 'Rival’s turn', 'Gegner ist dran', 'Turno del rival', 'Tour de l’adversaire', 'دور الخصم', 'نوبت حریف', 'תור היריב', 'حریف کی باری', 'Ход соперника', 'Хід суперника', 'Ruch rywala', 'Na tahu je soupeř', 'Rândul adversarului', 'Az ellenfél jön', 'Σειρά του αντιπάλου', 'Tocca all’avversario', 'Vez do rival', 'Beurt van tegenstander', 'Motståndarens tur', 'Modstanderens tur', 'Motstanderens tur', 'Vastustajan vuoro', '相手の番', '상대 차례', '对手回合', 'प्रतिद्वंद्वी की बारी', 'প্রতিদ্বন্দ্বীর পালা', 'Giliran lawan', 'Giliran lawan', 'ตาของคู่แข่ง', 'Lượt đối thủ', 'Turno ng kalaban'];

/// İki kişilik karambol: bilgisayara ya da çevrimiçi rakibe karşı.
///
/// Çevrimiçi eşitleme: vuruşu yapan cihaz vuruşu kendi tahtasında çözer ve
/// tek hamlede gönderir (vurucu yeri, hız, sokulanlar, faul, son dizilim —
/// 2 basamak). Karşı cihaz vuruşu canlandırır, sonra gönderenin dizilimine
/// oturur; maç kuralları (ortaya dönen taşlar dahil) iki cihazda aynı
/// sırayla uygulanır, böylece tahtalar her vuruştan sonra birebir aynıdır.
class CarromDuelView extends StatefulWidget {
  final PlayContext ctx;
  final CarromLevel level;
  const CarromDuelView({super.key, required this.ctx, required this.level});

  @override
  State<CarromDuelView> createState() => _CarromDuelViewState();
}

class _CarromDuelViewState extends State<CarromDuelView> with SingleTickerProviderStateMixin {
  final List<Man> men = matchLayout();
  final CarromMatch match = CarromMatch();
  late final Ticker _ticker;
  late final SeededRandom _botRng;
  StreamSubscription<(int, String)>? _sub;
  final List<String> _queue = [];

  late final int me;
  late final int opp;
  MatchLink? get link => widget.ctx.match;
  bool _remoteOpp = false;

  bool _animating = false;
  int _steps = 0, _shooter = 0, _shots = 0;
  final List<int> _pots = [];
  bool _foul = false;
  CarromShotMsg? _incoming;
  bool _botBusy = false, _done = false;
  double _lastSx = 500, _lastVx = 0, _lastVy = 0;

  // nişan (ekran koordinatı: kendi tabanın hep altta)
  double _aimAngle = -math.pi / 2, _aimPower = 0.6;
  Offset? _press;
  bool _placing = false;
  String _flash = '';
  int _flashTicks = 0;

  bool get _flip => me == 1;
  String get lang => widget.ctx.lang;

  @override
  void initState() {
    super.initState();
    final l = link;
    me = l?.mySeat ?? 0;
    opp = 1 - me;
    _remoteOpp = l != null && widget.ctx.role(opp) == SeatRole.remote;
    _botRng = SeededRandom(mixSeed([widget.level.meta.seed, 0xCA77]));
    if (l != null) {
      // Maça geri dönüş: vuruşlar sırayla uygulanır (canlandırmasız).
      for (final (seat, mv) in l.history) {
        final s = CarromShotMsg.decode(mv);
        if (s != null && applyCarromLayout(men, s.layout)) match.apply(men, seat, s.pots, s.foul);
      }
      _sub = l.moves.listen((e) {
        if (e.$1 == opp) _queue.add(e.$2);
      });
    }
    _setStriker(500);
    _ticker = createTicker(_onFrame)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sub?.cancel();
    super.dispose();
  }

  bool get _oppIsBot => !_remoteOpp || (link?.dropped.contains(opp) ?? false);

  void _setStriker(double x) {
    final st = men.first;
    st
      ..live = true
      ..vx = 0
      ..vy = 0
      ..y = baseY(match.turn)
      ..x = placeStriker(men, x, match.turn);
  }

  void _say(String s) {
    _flash = s;
    _flashTicks = 70;
  }

  void _onFrame(Duration _) {
    if (!mounted) return;
    if (_flashTicks > 0) _flashTicks--;
    if (_animating) {
      _steps++;
      final moving = stepCarrom(men, (m) {
        if (m.kind == kStriker) {
          _foul = true;
        } else {
          _pots.add(men.indexOf(m));
        }
      });
      if (!moving || _steps >= kCarromMaxSteps) _shotDone();
      setState(() {});
      return;
    }
    if (_flashTicks > 0) setState(() {});
    if (_done) return;
    if (match.winner >= 0) return _finish();
    if (match.turn == opp) {
      if (_queue.isNotEmpty && _remoteOpp) {
        final s = CarromShotMsg.decode(_queue.removeAt(0));
        if (s != null) _start(opp, s.sx, s.vx, s.vy, incoming: s);
      } else if (_oppIsBot && !_botBusy) {
        _botBusy = true;
        Future.delayed(const Duration(milliseconds: 800), () {
          if (!mounted || _done || _animating || match.turn != opp) {
            _botBusy = false;
            return;
          }
          final shot = carromMatchBot(men, match, opp, widget.level.difficulty, _botRng);
          final sx = placeStriker(men, shot.$1, opp);
          final v = carromVelocity(shot.$2, shot.$3);
          _botBusy = false;
          _start(opp, sx, v.$1, v.$2);
        });
      }
    }
  }

  void _start(int shooter, double sx, double vx, double vy, {CarromShotMsg? incoming}) {
    _shooter = shooter;
    _pots.clear();
    _foul = false;
    _steps = 0;
    _incoming = incoming;
    _lastSx = sx;
    _lastVx = vx;
    _lastVy = vy;
    men.first
      ..live = true
      ..x = sx
      ..y = baseY(shooter)
      ..vx = vx
      ..vy = vy;
    _animating = true;
    widget.ctx.sfx(Sfx.place);
  }

  void _shotDone() {
    _animating = false;
    for (final m in men) {
      m
        ..vx = 0
        ..vy = 0;
    }
    final inc = _incoming;
    List<int> pots;
    bool foul;
    if (inc != null) {
      // Rakibin cihazındaki sonuç geçerlidir: tahta onun dizilimine oturur.
      applyCarromLayout(men, inc.layout);
      pots = inc.pots;
      foul = inc.foul;
    } else {
      pots = List.of(_pots);
      foul = _foul;
      final layout = carromLayout(men);
      applyCarromLayout(men, layout);
      final l = link;
      if (l != null && (_shooter == me || (_remoteOpp && (l.dropped.contains(opp))))) {
        final msg = CarromShotMsg(_lastSx, _lastVx, _lastVy, pots, foul, layout).encode();
        unawaited((_shooter == me ? l.send(msg) : l.send(msg, asSeat: _shooter)).catchError((Object _) {}));
      }
    }
    final mine = CarromMatch.kindOf(_shooter);
    final own = pots.where((i) => men[i].kind == mine).length;
    final queen = pots.any((i) => men[i].kind == kQueen);
    match.apply(men, _shooter, pots, foul);
    if (foul || match.lastFoul == _shooter) {
      _say('FOUL');
    } else if (match.queenOwner == _shooter && queen) {
      _say('♛');
    } else if (own > 0) {
      _say(own > 1 ? 'x$own!' : 'IN!');
    }
    widget.ctx.sfx(foul ? Sfx.error : (own > 0 ? Sfx.clear : Sfx.tap));
    _setStriker(match.turn == _shooter ? _lastSx : 500);
  }

  void _finish() {
    if (_done) return;
    _done = true;
    final w = match.winner;
    final pts = match.points(men);
    final mineLeft = match.onBoard(men, me), theirsLeft = match.onBoard(men, opp);
    final l = link;
    if (l != null) unawaited(l.finish(w, iWon: w == me).catchError((Object _) {}));
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      final won = w == me;
      widget.ctx.sfx(won ? Sfx.win : Sfx.lose);
      widget.ctx.finish(RoundResult(
        won: won,
        score: won ? 300 + pts * 100 : 30,
        stars: !won ? 0 : (pts >= 5 ? 3 : (pts >= 2 ? 2 : 1)),
        moves: _shots,
        gameStats: {
          'pieces_pocketed': 9 - mineLeft,
          'shots_taken': _shots,
          if (won) 'boards_cleared': 1,
          if (match.queenOwner == me) 'queens_covered': 1,
        },
        headline: won ? null : '${Strings.pick(_tYou, lang)} ${9 - mineLeft} — ${Strings.pick(_tRival, lang)} ${9 - theirsLeft}',
      ));
    });
  }

  bool get _canAct => !_animating && !_done && match.turn == me;

  Offset _toCanon(Offset p) => _flip ? Offset(kWorldW - p.dx, kWorldH - p.dy) : p;

  void _panStart(Offset p) {
    if (!_canAct) return;
    if ((p.dy - kBaseBottom).abs() < 48 && p.dx > kBoard.l && p.dx < kBoard.r) {
      _placing = true;
      setState(() => _setStriker(_toCanon(p).dx));
      return;
    }
    _press = p;
  }

  void _panUpdate(Offset p) {
    if (_placing) {
      setState(() => _setStriker(_toCanon(p).dx));
      return;
    }
    final s = _press;
    if (s == null) return;
    final vx = -(p.dx - s.dx), vy = -(p.dy - s.dy);
    final len = math.sqrt(vx * vx + vy * vy);
    if (len < 4) return;
    setState(() {
      _aimAngle = CarromSim.clampAngle(math.atan2(vy, vx));
      _aimPower = (len / 350).clamp(0.0, 1.0);
    });
  }

  void _panEnd() {
    if (_placing) {
      _placing = false;
      return;
    }
    final s = _press;
    _press = null;
    if (s == null || !_canAct || _aimPower <= 0.05) return;
    final a = _flip ? _aimAngle + math.pi : _aimAngle;
    final v = carromVelocity(a, _aimPower);
    _shots++;
    _start(me, men.first.x, v.$1, v.$2);
  }

  @override
  Widget build(BuildContext context) {
    final myTurn = match.turn == me;
    final head = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        Flexible(child: _chip('${Strings.pick(_tYou, lang)} ${9 - match.onBoard(men, me)}/9', myTurn, me)),
        Expanded(
          child: Text(
            Strings.pick(myTurn ? _tYourTurn : _tRivalTurn, lang),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ),
        Flexible(
            child: _chip('${link != null ? widget.ctx.seatName(opp) : Strings.pick(_tRival, lang)} ${9 - match.onBoard(men, opp)}/9', !myTurn, opp)),
      ]),
    );
    // Onaylı tasarımın degrade zemini; tahta çizimi kendi sanatını korur.
    return StudioBackdrop(
      child: Column(children: [
        head,
        Expanded(
          child: FittedBox(
            child: SizedBox(
              width: kWorldW,
              height: kWorldH,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => _panStart(d.localPosition),
                onPanUpdate: (d) => _panUpdate(d.localPosition),
                onPanEnd: (_) => _panEnd(),
                onPanCancel: () {
                  _press = null;
                  _placing = false;
                },
                child: CustomPaint(
                  painter: _DuelPainter(men, _flip, _canAct, _aimAngle, _aimPower, match.queenPending >= 0, _flashTicks > 0 ? _flash : '',
                      (_flashTicks / 70).clamp(0.0, 1.0), widget.ctx.pieceColors.first.toARGB32()),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _chip(String text, bool active, int seat) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2E9E62) : Colors.black.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: active ? Colors.white.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.25)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: seat == 0 ? const Color(0xFFF4E9D8) : const Color(0xFF2B2B2B),
              border: Border.all(color: Colors.white54),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
              child: Text(text,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
        ]),
      );
}

class _DuelPainter extends CustomPainter {
  final List<Man> men;
  final bool flip, aim, queenPending;
  final double angle, power, flashAlpha;
  final String flash;
  final int strikerColor;
  _DuelPainter(this.men, this.flip, this.aim, this.angle, this.power, this.queenPending, this.flash, this.flashAlpha, this.strikerColor);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (flip) {
      canvas.translate(kWorldW, kWorldH);
      canvas.rotate(math.pi);
    }
    paintCarromBoard(canvas);
    final st = men.first;
    if (aim) _aim(canvas, st.x, st.y, flip ? angle + math.pi : angle, power);
    for (final m in men.skip(1)) {
      _man(canvas, m);
    }
    _man(canvas, st, strikerColor: strikerColor);
    canvas.restore();
    if (aim) _powerBar(canvas, power);
    if (queenPending) paintText(canvas, '♛ ?', const Offset(840, 1355), 44, const Color(0xFFD62828));
    if (flash.isNotEmpty) paintText(canvas, flash, const Offset(500, 300), 84, Colors.white.withValues(alpha: flashAlpha));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
