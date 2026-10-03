import 'dart:math';

import 'world_cup_data.dart';
import 'world_cup_fixtures.dart';
import 'world_cup_groups.dart';
import 'world_cup_nations.dart';
import 'world_cup_logic.dart';
import 'world_cup_models.dart';

List<WorldCupFixture> fixturesOf(WorldCupRun run) =>
    run.fixtureJson.map(WorldCupFixture.fromJson).toList();

WorldCupRun withFixtures(WorldCupRun run, List<WorldCupFixture> fixtures) =>
    run.copyWith(fixtureJson: fixtures.map((f) => f.toJson()).toList());

Map<String, WorldCupSquad> buildAllSquads() => {
      for (final n in kWorldCupNations) n.id: initialSquadForNation(n.id),
    };

WorldCupSquad reconcileSquad(WorldCupSquad squad) {
  if (squadLooksCorrupt(squad)) {
    return initialSquadForNation(squad.nationId);
  }

  final canonical = playersForNation(squad.nationId);
  final canonicalIds = canonical.map((p) => p.id).toSet();

  var ids = squad.playerIds.where((id) {
    if (isBannedPlayerId(id)) return false;
    if (id.startsWith('${squad.nationId}_') && canonicalIds.contains(id)) {
      return true;
    }
    if (!id.startsWith('${squad.nationId}_')) {
      final foreign = playerById(id);
      return foreign.nationId != squad.nationId && foreign.id == id;
    }
    return false;
  }).toList();

  for (final p in canonical) {
    if (ids.length >= kWorldCupSquadSize) break;
    if (!ids.contains(p.id)) ids.add(p.id);
  }
  ids = ids.take(kWorldCupSquadSize).toList();

  var xi = squad.startingXiIds.where(ids.contains).take(kWorldCupStartingXi).toList();
  for (final id in ids) {
    if (xi.length >= kWorldCupStartingXi) break;
    if (!xi.contains(id)) xi.add(id);
  }

  return squad.copyWith(
    playerIds: ids,
    startingXiIds: xi.take(kWorldCupStartingXi).toList(),
  );
}

WorldCupRun rehydrateWorldCupRun(WorldCupRun run) {
  final squads = <String, WorldCupSquad>{
    for (final e in run.squads.entries) e.key: reconcileSquad(e.value),
  };
  return run.copyWith(squads: squads);
}

WorldCupRun createTournament(String userNationId) {
  validateWorldCup2026Field();
  final letter = groupLetterForNation(userNationId)!;
  final fixtures = buildAllGroupFixtures();
  return WorldCupRun(
    userNationId: userNationId,
    squads: buildAllSquads(),
    fixtureJson: fixtures.map((f) => f.toJson()).toList(),
    groupLetter: letter,
  );
}

WorldCupSquad squadOf(WorldCupRun run, String nationId) => run.squads[nationId]!;

double liveSquadStrength(WorldCupRun run, String nationId) {
  if (!run.squads.containsKey(nationId)) {
    return nationFieldStrength(nationId);
  }
  return squadFieldStrength(run.squads[nationId]!);
}

WorldCupFixture? nextUserFixture(WorldCupRun run) {
  for (final f in fixturesOf(run)) {
    if (!f.played && f.involves(run.userNationId)) return f;
  }
  return null;
}

WorldCupFixture? fixtureById(WorldCupRun run, String id) {
  for (final f in fixturesOf(run)) {
    if (f.id == id) return f;
  }
  return null;
}

WorldCupRun updateFixture(WorldCupRun run, WorldCupFixture updated) {
  final list = fixturesOf(run);
  final i = list.indexWhere((f) => f.id == updated.id);
  if (i >= 0) list[i] = updated;
  return withFixtures(run, list);
}

WorldCupRun updateSquad(WorldCupRun run, WorldCupSquad squad) {
  final squads = Map<String, WorldCupSquad>.from(run.squads);
  squads[squad.nationId] = squad;
  return run.copyWith(squads: squads);
}

(String? winner, String? loser, bool draw) matchOutcome(WorldCupFixture f) {
  if (f.homeGoals > f.awayGoals) return (f.homeNationId, f.awayNationId, false);
  if (f.awayGoals > f.homeGoals) return (f.awayNationId, f.homeNationId, false);
  return (null, null, true);
}

WorldCupSquad addPlayerToSquad(WorldCupSquad squad, WorldCupPlayer player) {
  if (isBannedPlayer(player)) return squad;
  if (squad.playerIds.contains(player.id)) return squad;
  final ids = [...squad.playerIds, player.id];
  var xi = List<String>.from(squad.startingXiIds);
  if (xi.length < kWorldCupStartingXi) xi.add(player.id);
  return squad.copyWith(playerIds: ids, startingXiIds: xi);
}

WorldCupSquad removePlayerFromSquad(WorldCupSquad squad, String playerId) {
  final ids = squad.playerIds.where((id) => id != playerId).toList();
  var xi = squad.startingXiIds.where((id) => id != playerId).toList();
  if (xi.length < kWorldCupStartingXi && ids.isNotEmpty) {
    final bench = ids.where((id) => !xi.contains(id)).toList()
      ..sort(
        (a, b) => playerFromSquad(squad, b).rating2526.compareTo(playerFromSquad(squad, a).rating2526),
      );
    for (final id in bench) {
      if (xi.length >= kWorldCupStartingXi) break;
      xi.add(id);
    }
  }
  return squad.copyWith(playerIds: ids, startingXiIds: xi);
}

List<WorldCupPlayer> stealablePlayers(WorldCupRun run, String loserId) {
  final squad = squadOf(run, loserId);
  return squadPlayers(squad)..sort((a, b) => b.rating2526.compareTo(a.rating2526));
}

({WorldCupRun run, String news}) applyAutoTransfer(
  WorldCupRun run,
  String winnerId,
  String loserId,
  Random rng,
) {
  final loserSquad = squadOf(run, loserId);
  if (loserSquad.playerIds.isEmpty) {
    return (run: run, news: '${nationById(winnerId).name} beat ${nationById(loserId).name}');
  }
  final pick = stealablePlayers(run, loserId).where((p) => !isBannedPlayer(p)).toList();
  if (pick.isEmpty) {
    return (run: run, news: '${nationById(winnerId).name} beat ${nationById(loserId).name}');
  }
  final stolen = pick[rng.nextInt(pick.length)];
  var updated = run;
  updated = updateSquad(
    updated,
    removePlayerFromSquad(squadOf(updated, loserId), stolen.id),
  );
  updated = updateSquad(
    updated,
    addPlayerToSquad(squadOf(updated, winnerId), stolen),
  );
  return (
    run: updated,
    news:
        '${nationById(winnerId).name} stole ${stolen.name} from ${nationById(loserId).name}',
  );
}

class MatchApplyResult {
  final WorldCupRun run;
  final String? winnerId;
  final String? loserId;
  final bool wasDraw;
  final List<String> newsLines;

  const MatchApplyResult({
    required this.run,
    this.winnerId,
    this.loserId,
    this.wasDraw = false,
    this.newsLines = const [],
  });
}

MatchApplyResult recordMatchResult(
  WorldCupRun run,
  String fixtureId,
  int homeGoals,
  int awayGoals,
  Random rng,
) {
  var updated = run;
  final f = fixtureById(updated, fixtureId)!;
  final played =
      f.copyWith(played: true, homeGoals: homeGoals, awayGoals: awayGoals);
  updated = updateFixture(updated, played);

  final (winner, loser, draw) = matchOutcome(played);
  final news = <String>[];

  if (!draw && winner != null && loser != null) {
    if (winner == updated.userNationId || loser == updated.userNationId) {
      updated = updated.copyWith(
        pendingTransferFixtureId: fixtureId,
        transferWinnerId: winner,
        transferLoserId: loser,
      );
      return MatchApplyResult(
        run: updated,
        winnerId: winner,
        loserId: loser,
        wasDraw: draw,
        newsLines: news,
      );
    } else {
      final auto = applyAutoTransfer(updated, winner, loser, rng);
      updated = auto.run;
      news.add(auto.news);
      updated = updated.copyWith(
        recentNews: [...updated.recentNews, auto.news].take(24).toList(),
      );
    }
  }

  updated = _syncStage(updated, rng);

  return MatchApplyResult(
    run: updated,
    winnerId: winner,
    loserId: loser,
    wasDraw: draw,
    newsLines: news,
  );
}

WorldCupRun applyUserSteal(WorldCupRun run, String playerId) {
  if (isBannedPlayerId(playerId)) return run.copyWith(clearTransfer: true);
  final w = run.transferWinnerId!;
  final l = run.transferLoserId!;
  var updated = run;
  final player = playerById(playerId);
  if (isBannedPlayer(player)) return run.copyWith(clearTransfer: true);
  updated = updateSquad(updated, removePlayerFromSquad(squadOf(updated, l), playerId));
  updated = updateSquad(updated, addPlayerToSquad(squadOf(updated, w), player));
  final line =
      '${nationById(w).name} stole ${player.name} from ${nationById(l).name}';
  return updated.copyWith(
    clearTransfer: true,
    recentNews: [...updated.recentNews, line].take(24).toList(),
  );
}

WorldCupRun applyUserSurrenderPlayer(WorldCupRun run, String playerId) {
  final w = run.transferWinnerId!;
  final l = run.transferLoserId!;
  var updated = run;
  final player = playerById(playerId);
  updated = updateSquad(updated, removePlayerFromSquad(squadOf(updated, l), playerId));
  updated = updateSquad(updated, addPlayerToSquad(squadOf(updated, w), player));
  final line =
      '${nationById(w).name} took ${player.name} from ${nationById(l).name}';
  return updated.copyWith(
    clearTransfer: true,
    recentNews: [...updated.recentNews, line].take(24).toList(),
  );
}

WorldCupRun finishTransferAndSimBatch(WorldCupRun run, Random rng) {
  var updated = run.copyWith(clearTransfer: true);
  updated = _simPendingBatch(updated, rng);
  updated = _syncStage(updated, rng);
  return updated;
}

WorldCupRun _simPendingBatch(WorldCupRun run, Random rng) {
  var updated = run;
  final fixtures = fixturesOf(updated);

  if (updated.stage == TournamentStage.group) {
    final md = _currentGroupMatchday(updated);
    for (final peer in fixturesForGroupMatchday(fixtures, md)) {
      if (peer.played || peer.involves(updated.userNationId)) continue;
      final sim = simulateFullMatch(
        rng: rng,
        homeStrength: liveSquadStrength(updated, peer.homeNationId),
        awayStrength: liveSquadStrength(updated, peer.awayNationId),
      );
      final res = recordMatchResult(
        updated,
        peer.id,
        sim.homeGoals,
        sim.awayGoals,
        rng,
      );
      updated = res.run;
    }
    updated = updated.copyWith(groupMatchday: _currentGroupMatchday(updated));
    return updated;
  }

  if (updated.stage == TournamentStage.knockout) {
    final round = updated.currentKnockoutRound!;
    for (final leg in fixturesForKnockoutRound(fixtures, round)) {
      if (leg.played || leg.involves(updated.userNationId)) continue;
      final sim = simulateFullMatch(
        rng: rng,
        homeStrength: liveSquadStrength(updated, leg.homeNationId),
        awayStrength: liveSquadStrength(updated, leg.awayNationId),
      );
      final res = recordMatchResult(
        updated,
        leg.id,
        sim.homeGoals,
        sim.awayGoals,
        rng,
      );
      updated = res.run;
    }
  }
  return updated;
}

WorldCupRun _syncStage(WorldCupRun run, Random rng) {
  if (run.stage == TournamentStage.group && _allGroupFixturesPlayed(run)) {
    return _startKnockoutPhase(run, rng);
  }
  if (run.stage == TournamentStage.knockout) {
    return _advanceKnockoutIfNeeded(run, rng);
  }
  if (run.stage == TournamentStage.group) {
    return run.copyWith(groupMatchday: _currentGroupMatchday(run));
  }
  return run;
}

bool _allGroupFixturesPlayed(WorldCupRun run) =>
    fixturesOf(run).where((f) => f.kind == FixtureKind.group).every((f) => f.played);

int _currentGroupMatchday(WorldCupRun run) {
  final fixtures = fixturesOf(run);
  for (var md = 0; md < kGroupMatchdayPairings.length; md++) {
    final batch = fixturesForGroupMatchday(fixtures, md);
    if (batch.any((f) => !f.played)) return md;
  }
  return kGroupMatchdayPairings.length;
}

List<GroupStandingRow> groupStandingsForLetter(WorldCupRun run, String letter) {
  final teams = nationsInGroup(letter);
  final results = fixturesOf(run)
      .where((f) => f.kind == FixtureKind.group && f.groupLetter == letter && f.played)
      .map(
        (f) => GroupMatchResult(
          homeNationId: f.homeNationId,
          awayNationId: f.awayNationId,
          homeGoals: f.homeGoals,
          awayGoals: f.awayGoals,
          matchday: f.groupMatchday ?? 0,
        ),
      )
      .toList();
  return groupStandings(teams, results);
}

List<String> qualifyForRoundOf32(WorldCupRun run) {
  final qualified = <String>[];
  final thirdPlaces = <GroupStandingRow>[];

  for (final letter in kWorldCupGroupLetters) {
    final standings = groupStandingsForLetter(run, letter);
    qualified.add(standings[0].nationId);
    qualified.add(standings[1].nationId);
    if (standings.length > 2) thirdPlaces.add(standings[2]);
  }

  thirdPlaces.sort((a, b) {
    if (b.points != a.points) return b.points.compareTo(a.points);
    if (b.gd != a.gd) return b.gd.compareTo(a.gd);
    if (b.gf != a.gf) return b.gf.compareTo(a.gf);
    return a.nationId.compareTo(b.nationId);
  });
  qualified.addAll(thirdPlaces.take(8).map((r) => r.nationId));
  return qualified;
}

bool isNationActive(WorldCupRun run, String nationId) {
  if (squadOf(run, nationId).playerIds.length < kWorldCupMinSquad) return false;
  if (run.eliminatedNationIds.contains(nationId)) return false;
  return true;
}

WorldCupRun _startKnockoutPhase(WorldCupRun run, Random rng) {
  var teams = qualifyForRoundOf32(run)
      .where((id) => isNationActive(run, id))
      .toList();
  if (teams.length > 32) teams = teams.take(32).toList();
  while (teams.length < 32) {
    teams = qualifyForRoundOf32(run)
        .where((id) => isNationActive(run, id))
        .take(32)
        .toList();
    if (teams.length >= 32) break;
    break;
  }
  teams.shuffle(rng);

  var fixtures = fixturesOf(run);
  fixtures.addAll(buildKnockoutFixtures(KnockoutRound.roundOf32, teams));

  if (!teams.contains(run.userNationId) ||
      squadOf(run, run.userNationId).playerIds.length < kWorldCupMinSquad) {
    return withFixtures(run, fixtures).copyWith(
      stage: TournamentStage.eliminated,
      groupMatchday: kGroupMatchdayPairings.length,
      knockoutRoundIndex: 0,
    );
  }

  return withFixtures(run, fixtures).copyWith(
    stage: TournamentStage.knockout,
    groupMatchday: kGroupMatchdayPairings.length,
    knockoutRoundIndex: 0,
  );
}

WorldCupRun _advanceKnockoutIfNeeded(WorldCupRun run, Random rng) {
  var updated = run;
  final allFixtures = fixturesOf(updated);

  for (final round in KnockoutRound.values) {
    final roundFixtures = fixturesForKnockoutRound(allFixtures, round);
    if (roundFixtures.isEmpty) continue;
    if (roundFixtures.any((f) => !f.played)) continue;

    final winners = <String>[];
    for (final f in roundFixtures) {
      if (!f.played) continue;
      final (w, _, draw) = matchOutcome(f);
      if (!draw && w != null && isNationActive(updated, w)) winners.add(w);
    }

    if (winners.length == 1 && round == KnockoutRound.finalMatch) {
      if (winners.first == updated.userNationId) {
        return updated.copyWith(stage: TournamentStage.champion);
      }
      return updated.copyWith(stage: TournamentStage.eliminated);
    }

    if (winners.isEmpty) continue;

    final nextIndex = round.index + 1;
    if (nextIndex >= KnockoutRound.values.length) continue;

    if (fixturesForKnockoutRound(allFixtures, KnockoutRound.values[nextIndex])
        .isNotEmpty) {
      continue;
    }

    if (winners.length == 1) {
      if (winners.first == updated.userNationId) {
        return updated.copyWith(stage: TournamentStage.champion);
      }
      return updated.copyWith(stage: TournamentStage.eliminated);
    }

    winners.shuffle(rng);
    var fixtures = fixturesOf(updated);
    fixtures.addAll(
      buildKnockoutFixtures(KnockoutRound.values[nextIndex], winners),
    );

    if (!winners.contains(updated.userNationId)) {
      return withFixtures(updated, fixtures).copyWith(
        knockoutRoundIndex: nextIndex,
        stage: TournamentStage.eliminated,
      );
    }

    return withFixtures(updated, fixtures).copyWith(knockoutRoundIndex: nextIndex);
  }
  return updated;
}

List<WorldCupFixture> fixturesForKnockoutRound(
  List<WorldCupFixture> all,
  KnockoutRound round,
) =>
    all.where((f) => f.kind == FixtureKind.knockout && f.knockoutRound == round).toList();

bool userNeedsTransfer(WorldCupRun run) =>
    run.transferWinnerId != null && run.transferLoserId != null;

bool userMustSteal(WorldCupRun run) =>
    userNeedsTransfer(run) && run.transferWinnerId == run.userNationId;

bool userMustSurrender(WorldCupRun run) =>
    userNeedsTransfer(run) && run.transferLoserId == run.userNationId;

bool userAdvancesFromGroup(WorldCupRun run) {
  if (_allGroupFixturesPlayed(run)) {
    return qualifyForRoundOf32(run).contains(run.userNationId);
  }
  final standings = groupStandingsForLetter(run, run.groupLetter);
  final idx = standings.indexWhere((s) => s.nationId == run.userNationId);
  return idx >= 0 && idx < 2;
}

int userGroupRank(WorldCupRun run) {
  final standings = groupStandingsForLetter(run, run.groupLetter);
  final idx = standings.indexWhere((s) => s.nationId == run.userNationId);
  return idx < 0 ? 4 : idx + 1;
}

bool isUserEliminated(WorldCupRun run) {
  if (run.stage == TournamentStage.eliminated) return true;
  if (squadOf(run, run.userNationId).playerIds.length < kWorldCupMinSquad) {
    return true;
  }
  if (run.stage == TournamentStage.group && _allGroupFixturesPlayed(run)) {
    return !qualifyForRoundOf32(run).contains(run.userNationId);
  }
  return false;
}

double strengthForSide(WorldCupRun run, String nationId) =>
    liveSquadStrength(run, nationId);

String tournamentProgressLabel(WorldCupRun run) {
  if (run.stage == TournamentStage.group) {
    return 'Group ${run.groupLetter} · Matchday ${run.groupMatchday + 1}/3';
  }
  if (run.stage == TournamentStage.knockout) {
    return run.currentKnockoutRound?.label ?? 'Knockout';
  }
  return 'World Cup';
}

List<WorldCupFixture> fixturesForCurrentMatchday(WorldCupRun run) {
  final fixtures = fixturesOf(run);
  if (run.stage == TournamentStage.group) {
    return fixturesForGroupMatchday(fixtures, run.groupMatchday);
  }
  return fixtures
      .where((f) =>
          f.kind == FixtureKind.knockout &&
          f.knockoutRound == run.currentKnockoutRound &&
          !f.played)
      .toList();
}

(String home, String away)? pendingFixtureSides(WorldCupRun run) {
  final id = run.pendingFixtureId;
  if (id == null) return null;
  final f = fixtureById(run, id);
  if (f == null) return null;
  return (f.homeNationId, f.awayNationId);
}

bool pendingFixtureIsKnockout(WorldCupRun run) {
  final id = run.pendingFixtureId;
  if (id == null) return false;
  return fixtureById(run, id)?.kind == FixtureKind.knockout;
}
