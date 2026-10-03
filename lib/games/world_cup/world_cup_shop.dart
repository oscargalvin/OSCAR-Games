import 'world_cup_data.dart';
import 'world_cup_fixtures.dart';
import 'world_cup_ratings.dart';
import 'world_cup_models.dart';
import 'world_cup_nations.dart';

/// Free starter nations — Japan plus two more to pick from at the start.
const Set<String> kWorldCupStarterNationIds = {'jpn', 'alg', 'aut'};

/// Coin rewards by furthest round reached (group exit = 0).
const int kWorldCupCoinsGroupExit = 0;
const int kWorldCupCoinsRoundOf32 = 15;
const int kWorldCupCoinsRoundOf16 = 50;
const int kWorldCupCoinsQuarterFinal = 75;
const int kWorldCupCoinsSemiFinal = 100;
const int kWorldCupCoinsFinal = 200;
const int kWorldCupCoinsChampion = 300;

int nationShopPrice(String nationId) {
  if (kWorldCupStarterNationIds.contains(nationId)) return 0;
  final legacy = kNationSquadBaseRating[nationId] ?? 70.0;
  final rating = nationBaseSeasonRating(nationId, legacy);
  return ((rating - kPlayerRatingFloor) * 2.5).round().clamp(25, 280);
}

int coinRewardForRun(WorldCupRun run, {bool champion = false}) {
  if (champion || run.stage == TournamentStage.champion) {
    return kWorldCupCoinsChampion;
  }
  if (run.stage != TournamentStage.eliminated) return 0;

  final qualified = _userQualifiedForKnockout(run);
  if (!qualified) return kWorldCupCoinsGroupExit;

  return switch (run.knockoutRoundIndex.clamp(0, 4)) {
    0 => kWorldCupCoinsRoundOf32,
    1 => kWorldCupCoinsRoundOf16,
    2 => kWorldCupCoinsQuarterFinal,
    3 => kWorldCupCoinsSemiFinal,
    4 => kWorldCupCoinsFinal,
    _ => kWorldCupCoinsGroupExit,
  };
}

bool _userQualifiedForKnockout(WorldCupRun run) {
  for (final f in run.fixtureJson) {
    if (f['kind'] == FixtureKind.knockout.name &&
        (f['homeNationId'] == run.userNationId ||
            f['awayNationId'] == run.userNationId)) {
      return true;
    }
  }
  return run.knockoutRoundIndex > 0 || run.stage == TournamentStage.knockout;
}

List<WorldCupPlayer> pickablePlayersForNation(String nationId) {
  final squad = initialSquadForNation(nationId);
  return pickablePlayersFromSquad(squad);
}

List<WorldCupPlayer> pickablePlayersFromSquad(WorldCupSquad squad) {
  return squadPlayers(squad)
      .where((p) => p.rating2526 <= kWorldCupMaxPickRating)
      .toList()
    ..sort((a, b) => b.rating2526.compareTo(a.rating2526));
}

String coinRewardLabel(int coins) {
  if (coins <= 0) return 'No coins';
  return '+$coins coins';
}
