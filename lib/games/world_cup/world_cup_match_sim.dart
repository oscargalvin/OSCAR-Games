import 'dart:math';

import 'world_cup_data.dart';
import 'world_cup_lineup.dart';
import 'world_cup_logic.dart';
import 'world_cup_models.dart';

/// One goal in a simulated or live match.
class MatchGoal {
  final int minute;
  final String playerId;
  final String playerName;
  final String nationId;
  final bool isHome;

  const MatchGoal({
    required this.minute,
    required this.playerId,
    required this.playerName,
    required this.nationId,
    required this.isHome,
  });
}

class SimulatedMatch {
  final int homeGoals;
  final int awayGoals;
  final List<MatchGoal> goals;

  const SimulatedMatch({
    required this.homeGoals,
    required this.awayGoals,
    required this.goals,
  });
}

WorldCupPlayer pickGoalScorer(WorldCupSquad squad, Random rng) {
  final xi = startingPlayers(squad);
  if (xi.isEmpty) {
    final all = squadPlayers(squad);
    return all.isNotEmpty
        ? all.first
        : const WorldCupPlayer(
            id: 'unknown',
            name: 'Unknown',
            nationId: '',
            position: 'FWD',
            rating2526: 70,
          );
  }
  final weights = xi.map((p) {
    return switch (p.position) {
      'FWD' => 4.0 + p.rating2526 / 30,
      'MID' => 2.5 + p.rating2526 / 40,
      'DEF' => 0.8 + p.rating2526 / 80,
      'GK' => 0.15,
      _ => 1.0,
    };
  }).toList();
  final total = weights.fold<double>(0, (a, b) => a + b);
  var roll = rng.nextDouble() * total;
  for (var i = 0; i < xi.length; i++) {
    roll -= weights[i];
    if (roll <= 0) return xi[i];
  }
  return xi.last;
}

int _gameMinute(int second, int totalSeconds) =>
    ((second + 1) * 90 / totalSeconds).ceil().clamp(1, 90);

SimulatedMatch simulateMatchDetailed({
  required Random rng,
  required WorldCupSquad homeSquad,
  required WorldCupSquad awaySquad,
  required double homeStrength,
  required double awayStrength,
  int seconds = kWorldCupMatchSeconds,
  String? preferredHomeScorerId,
  String? preferredAwayScorerId,
}) {
  var home = 0;
  var away = 0;
  final goals = <MatchGoal>[];

  for (var sec = 0; sec < seconds; sec++) {
    final tick = tickMatchSecond(
      rng: rng,
      homeStrength: homeStrength,
      awayStrength: awayStrength,
    );
    final minute = _gameMinute(sec, seconds);
    if (tick.homeScored) {
      home++;
      WorldCupPlayer scorer;
      if (preferredHomeScorerId != null &&
          homeSquad.startingXiIds.contains(preferredHomeScorerId) &&
          rng.nextDouble() < 0.55) {
        scorer = playerFromSquad(homeSquad, preferredHomeScorerId);
      } else {
        scorer = pickGoalScorer(homeSquad, rng);
      }
      goals.add(
        MatchGoal(
          minute: minute,
          playerId: scorer.id,
          playerName: scorer.name,
          nationId: scorer.nationId,
          isHome: true,
        ),
      );
    } else if (tick.awayScored) {
      away++;
      WorldCupPlayer scorer;
      if (preferredAwayScorerId != null &&
          awaySquad.startingXiIds.contains(preferredAwayScorerId) &&
          rng.nextDouble() < 0.55) {
        scorer = playerFromSquad(awaySquad, preferredAwayScorerId);
      } else {
        scorer = pickGoalScorer(awaySquad, rng);
      }
      goals.add(
        MatchGoal(
          minute: minute,
          playerId: scorer.id,
          playerName: scorer.name,
          nationId: scorer.nationId,
          isHome: false,
        ),
      );
    }
  }

  return SimulatedMatch(homeGoals: home, awayGoals: away, goals: goals);
}

MatchGoal liveGoalEvent({
  required WorldCupSquad squad,
  required bool isHome,
  required int secondsElapsed,
  required int totalSeconds,
  required Random rng,
  String? preferredScorerId,
}) {
  WorldCupPlayer scorer;
  if (preferredScorerId != null &&
      squad.startingXiIds.contains(preferredScorerId) &&
      rng.nextDouble() < 0.6) {
    scorer = playerFromSquad(squad, preferredScorerId);
  } else {
    scorer = pickGoalScorer(squad, rng);
  }
  return MatchGoal(
    minute: _gameMinute(secondsElapsed, totalSeconds),
    playerId: scorer.id,
    playerName: scorer.name,
    nationId: scorer.nationId,
    isHome: isHome,
  );
}
