import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';

import 'carrom_engine.dart';

class CarromRules extends ArcadeRules<CarromLevel> {
  @override
  String get gameId => 'oyun-karambol';

  @override
  List<String> get optionalMechanics => const [];

  /// İki kişilik: "Bilgisayara karşı" ve "Çevrimiçi masa" (sırayla vuruş).
  @override
  int get localPlayers => 2;

  @override
  List<GameStat> get gameStats => const [
        GameStat('pieces_pocketed', 'Cebe giren taş', 'Pieces pocketed', scale: 300),
        GameStat('boards_cleared', 'Kazanılan tahta', 'Boards won', scale: 30),
        GameStat('shots_taken', 'Yapılan vuruş', 'Shots taken', scale: 300),
        GameStat('queens_covered', 'Örtülen kraliçe', 'Queens covered', scale: 20),
      ];

  @override
  List<MissionTemplate> get missionTemplates => const [
        MissionTemplate('pieces_pocketed', 'pieces_pocketed', [60, 150, 300]),
        MissionTemplate('boards_cleared', 'boards_cleared', [3, 7, 15], coinReward: 80),
        MissionTemplate('queens_covered', 'queens_covered', [1, 4, 10]),
      ];

  @override
  CarromLevel generate(LevelSpec spec) => generateCarrom(spec);

  @override
  ArcadeMeta metaOf(CarromLevel l) => l.meta;

  @override
  ArcadeSim createSim(CarromLevel l) => CarromSim(l);

  @override
  ArcadeInput bot(ArcadeSim sim) => carromBot(sim);
}

ArcadeRules createRules() => CarromRules();
