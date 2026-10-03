import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/save_service.dart';
import '../../services/sound_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/game_scaffold.dart';
import 'world_cup_celebration.dart';
import 'world_cup_data.dart';
import 'world_cup_fixtures.dart';
import 'world_cup_groups.dart';
import 'world_cup_logic.dart';
import 'world_cup_match.dart';
import 'world_cup_models.dart';
import 'world_cup_joystick.dart';
import 'world_cup_lineup.dart';
import 'world_cup_match_sim.dart';
import 'world_cup_pitch.dart';
import 'world_cup_score_band.dart';
import 'world_cup_shop.dart';
import 'world_cup_tournament.dart';

class WorldCupScreen extends StatefulWidget {
  const WorldCupScreen({super.key});

  @override
  State<WorldCupScreen> createState() => _WorldCupScreenState();
}

class _WorldCupScreenState extends State<WorldCupScreen> {
  WorldCupPhase _phase = WorldCupPhase.hub;
  WorldCupRun? _run;
  late int _tournamentsStarted;
  late int _wins;
  late int _coins;
  late List<String> _ownedNationIds;
  int _lastCoinReward = 0;
  bool _pendingAutoSim = false;

  Timer? _matchTimer;
  int _secondsLeft = kWorldCupMatchSeconds;
  int _liveHomeGoals = 0;
  int _liveAwayGoals = 0;
  int _lastHomeGoals = 0;
  int _lastAwayGoals = 0;
  String? _lastHomeId;
  String? _lastAwayId;
  bool _lastMatchWasAutoSim = false;
  List<MatchGoal> _lastMatchGoals = [];
  String? _championNationName;
  final _liveMatch = WorldCupLiveMatch();
  final _rng = Random();
  Offset _playerPos = defaultPickSpawn(userIsHome: true);
  Offset _ballPos = defaultPickSpawn(userIsHome: true);
  Offset _joystickDir = Offset.zero;
  Timer? _moveTimer;
  final _countrySearchController = TextEditingController();
  String? _countryLetterFilter;

  @override
  void initState() {
    super.initState();
    final save = SaveService.instance;
    save.ensureWorldCupDefaults();
    _tournamentsStarted = save.worldCupTournamentsStarted;
    _wins = save.worldCupWins;
    _coins = save.worldCupCoins;
    _ownedNationIds = List<String>.from(save.worldCupOwnedNationIds);
    _run = decodeWorldCupRun(save.worldCupActiveRunJson);
    if (_run != null) {
      _run = rehydrateWorldCupRun(_run!);
      _persist(runOverride: _run);
    }
    if (_run != null) {
      if (userMustSteal(_run!)) {
        _phase = WorldCupPhase.stealPlayer;
      } else if (userMustSurrender(_run!)) {
        _phase = WorldCupPhase.surrenderPlayer;
      } else {
        _phase = switch (_run!.stage) {
          TournamentStage.group => WorldCupPhase.groupStage,
          TournamentStage.knockout => WorldCupPhase.knockout,
          TournamentStage.champion => WorldCupPhase.champion,
          TournamentStage.eliminated => WorldCupPhase.eliminated,
        };
        if (_run!.stage == TournamentStage.champion) {
          _championNationName = nationById(_run!.userNationId).name;
        }
      }
    }
  }

  @override
  void dispose() {
    _matchTimer?.cancel();
    _moveTimer?.cancel();
    _countrySearchController.dispose();
    super.dispose();
  }

  List<WorldCupNation> _filteredNations() {
    final query = _countrySearchController.text.trim().toLowerCase();
    return kWorldCupNations.where((n) {
      if (_countryLetterFilter != null &&
          !n.name.toUpperCase().startsWith(_countryLetterFilter!)) {
        return false;
      }
      if (query.isEmpty) return true;
      return n.name.toLowerCase().contains(query) ||
          n.countryCode.toLowerCase().contains(query) ||
          n.id.contains(query);
    }).toList();
  }

  void _clearCountryFilters() {
    _countrySearchController.clear();
    setState(() => _countryLetterFilter = null);
  }

  Future<void> _persist({WorldCupRun? runOverride, bool clearRun = false}) async {
    await SaveService.instance.saveWorldCupProgress(
      tournamentsStarted: _tournamentsStarted,
      wins: _wins,
      activeRunJson: clearRun ? null : encodeWorldCupRun(runOverride ?? _run),
      coins: _coins,
      ownedNationIds: _ownedNationIds,
    );
  }

  double _pickPlayerBoost() {
    final id = _run?.matchPickPlayerId;
    if (id == null) return 0;
    final eff = effectiveRatingForStrength(playerById(id).rating2526);
    return ((eff - kPlayerRatingFloor) / 5).clamp(0, 18);
  }

  WorldCupPlayer? _pickedPlayer() {
    final id = _run?.matchPickPlayerId;
    if (id == null || _run == null) return null;
    return playerFromSquad(_run!.squad, id);
  }

  void _grantCoinReward(WorldCupRun run, {required bool champion}) {
    _lastCoinReward = coinRewardForRun(run, champion: champion);
    _coins += _lastCoinReward;
  }

  void _go(WorldCupPhase phase) => setState(() => _phase = phase);

  void _startNewTournament() {
    SoundService.instance.play(GameSound.tap);
    _go(WorldCupPhase.pickCountry);
  }

  void _pickCountry(String nationId) {
    SoundService.instance.play(GameSound.win);
    HapticFeedback.mediumImpact();
    _run = createTournament(nationId);
    _tournamentsStarted += 1;
    _persist();
    _go(WorldCupPhase.groupStage);
  }

  void _pickRandomOwnedCountry() {
    final owned = _filteredNations().where((n) => _ownedNationIds.contains(n.id)).toList();
    if (owned.isEmpty) return;
    _pickCountry(owned[Random().nextInt(owned.length)].id);
  }

  void _beginUserFixture({required bool autoSim}) {
    final fix = nextUserFixture(_run!);
    if (fix == null) return;
    _pendingAutoSim = autoSim;
    setState(() {
      _run = _run!.copyWith(pendingFixtureId: fix.id, clearMatchPick: true);
    });
    if (autoSim) {
      _autoPickPlayer();
      _go(WorldCupPhase.editLineup);
    } else {
      _go(WorldCupPhase.pickPlayer);
    }
  }

  void _autoPickPlayer() {
    final players = pickablePlayersFromSquad(_run!.squad);
    final pickId = players.isNotEmpty ? players.first.id : null;
    setState(() => _run = _run!.copyWith(matchPickPlayerId: pickId));
  }

  void _onPickPlayer(String playerId) {
    SoundService.instance.play(GameSound.tap);
    setState(() => _run = _run!.copyWith(matchPickPlayerId: playerId));
    _go(WorldCupPhase.editLineup);
  }

  void _continueFromLineup() {
    if (_pendingAutoSim) {
      _runQuickPlay();
    } else {
      _go(WorldCupPhase.preMatch);
    }
  }

  void _runQuickPlay() {
    SoundService.instance.play(GameSound.tap);
    final run = _run!;
    final sides = pendingFixtureSides(run)!;
    final homeId = sides.$1;
    final awayId = sides.$2;
    _lastHomeId = homeId;
    _lastAwayId = awayId;
    _lastMatchGoals = [];
    final sim = simulateMatchDetailed(
      rng: _rng,
      homeSquad: squadOf(run, homeId),
      awaySquad: squadOf(run, awayId),
      homeStrength: strengthForSide(run, homeId),
      awayStrength: strengthForSide(run, awayId),
      preferredHomeScorerId: homeId == run.userNationId ? run.matchPickPlayerId : null,
      preferredAwayScorerId: awayId == run.userNationId ? run.matchPickPlayerId : null,
    );
    _lastHomeGoals = sim.homeGoals;
    _lastAwayGoals = sim.awayGoals;
    _lastMatchGoals = sim.goals;
    _lastMatchWasAutoSim = true;
    _go(WorldCupPhase.quickPlaySummary);
  }

  void _finishQuickPlaySummary() {
    _applyPendingMatchResult(_lastHomeGoals, _lastAwayGoals);
  }

  void _playLive() {
    SoundService.instance.play(GameSound.tap);
    final run = _run!;
    final sides = pendingFixtureSides(run)!;
    _lastHomeId = sides.$1;
    _lastAwayId = sides.$2;
    _liveMatch.reset();
    _lastMatchGoals = [];
    final userIsHome = sides.$1 == run.userNationId;
    _playerPos = defaultPickSpawn(userIsHome: userIsHome);
    _ballPos = ballOffsetFromPlayer(_playerPos, userIsHome: userIsHome);
    _joystickDir = Offset.zero;
    _liveMatch
      ..feedback = 'Joystick = move · Pass · Cross · Shoot · Sprint on the right'
      ..feedbackTicks = 0;
    setState(() {
      _secondsLeft = kWorldCupMatchSeconds;
      _liveHomeGoals = 0;
      _liveAwayGoals = 0;
      _lastMatchWasAutoSim = false;
      _phase = WorldCupPhase.matchLive;
    });
    _matchTimer?.cancel();
    _matchTimer = Timer.periodic(const Duration(seconds: 1), _onMatchTick);
    _moveTimer?.cancel();
    _moveTimer = Timer.periodic(const Duration(milliseconds: 50), _onMoveTick);
  }

  void _onJoystick(Offset dir) {
    _joystickDir = dir;
  }

  void _onMoveTick(Timer _) {
    if (_phase != WorldCupPhase.matchLive || _run == null) return;
    if (_joystickDir.distance < 0.08) return;

    final run = _run!;
    final sides = pendingFixtureSides(run)!;
    final userIsHome = sides.$1 == run.userNationId;
    const speed = 0.016;
    final sprintMult = _liveMatch.sprintTicks > 0 ? 1.55 : 1.0;
    final moveY = userIsHome ? _joystickDir.dy : -_joystickDir.dy;

    setState(() {
      _playerPos = Offset(
        (_playerPos.dx + _joystickDir.dx * speed * sprintMult).clamp(0.08, 0.92),
        (_playerPos.dy + moveY * speed * sprintMult).clamp(0.08, 0.92),
      );
      _ballPos = ballOffsetFromPlayer(_playerPos, userIsHome: userIsHome);
      _liveMatch.onDribble(forwardMotion(_joystickDir, userIsHome: userIsHome));
    });
  }

  void _onMatchAction(MatchAction action) {
    if (_phase != WorldCupPhase.matchLive || _run == null) return;
    SoundService.instance.play(GameSound.tap);
    final run = _run!;
    final sides = pendingFixtureSides(run)!;
    final homeId = sides.$1;
    final awayId = sides.$2;
    final userId = run.userNationId;
    final userIsHome = homeId == userId;
    final userStr = strengthForSide(run, userId);
    final oppId = userIsHome ? awayId : homeId;
    final oppStr = strengthForSide(run, oppId);

    _nudgePlayerForAction(action, userIsHome);

    var boost = _pickPlayerBoost();
    if (action == MatchAction.shoot) {
      boost += _shootZoneBoost(userIsHome);
    }

    final result = _liveMatch.handle(
      action,
      rng: _rng,
      userIsHome: userIsHome,
      userStrength: userStr,
      oppStrength: oppStr,
      pickBoost: boost,
    );
    _applyLiveGoal(result);
    HapticFeedback.selectionClick();
    setState(() {});
  }

  void _nudgePlayerForAction(MatchAction action, bool userIsHome) {
    final step = userIsHome ? -1.0 : 1.0;
    switch (action) {
      case MatchAction.pass:
        _playerPos = Offset(
          _playerPos.dx.clamp(0.08, 0.92),
          (_playerPos.dy + step * 0.05).clamp(0.08, 0.92),
        );
      case MatchAction.cross:
        _playerPos = Offset(
          (_playerPos.dx + (_playerPos.dx < 0.5 ? -0.06 : 0.06)).clamp(0.08, 0.92),
          (_playerPos.dy + step * 0.04).clamp(0.08, 0.92),
        );
      case MatchAction.shoot:
        _playerPos = Offset(
          _playerPos.dx.clamp(0.08, 0.92),
          (_playerPos.dy + step * 0.08).clamp(0.08, 0.92),
        );
      case MatchAction.sprint:
      case MatchAction.tackle:
      case MatchAction.freeKick:
        break;
    }
    _ballPos = ballOffsetFromPlayer(_playerPos, userIsHome: userIsHome);
  }

  double _shootZoneBoost(bool userIsHome) {
    if (userIsHome && _playerPos.dy < 0.42) return 15;
    if (!userIsHome && _playerPos.dy > 0.58) return 15;
    return 0;
  }

  void _applyLiveGoal(MatchActionResult result) {
    if (_run == null || _lastHomeId == null || _lastAwayId == null) return;
    final run = _run!;
    final elapsed = kWorldCupMatchSeconds - _secondsLeft;

    if (result == MatchActionResult.homeGoal) {
      _liveHomeGoals++;
      _lastMatchGoals.add(
        liveGoalEvent(
          squad: squadOf(run, _lastHomeId!),
          isHome: true,
          secondsElapsed: elapsed,
          totalSeconds: kWorldCupMatchSeconds,
          rng: _rng,
          preferredScorerId: _lastHomeId == run.userNationId ? run.matchPickPlayerId : null,
        ),
      );
      SoundService.instance.play(GameSound.hit);
      HapticFeedback.mediumImpact();
    } else if (result == MatchActionResult.awayGoal) {
      _liveAwayGoals++;
      _lastMatchGoals.add(
        liveGoalEvent(
          squad: squadOf(run, _lastAwayId!),
          isHome: false,
          secondsElapsed: elapsed,
          totalSeconds: kWorldCupMatchSeconds,
          rng: _rng,
          preferredScorerId: _lastAwayId == run.userNationId ? run.matchPickPlayerId : null,
        ),
      );
      SoundService.instance.play(GameSound.countdownTick);
    }
  }

  void _openLineupEditor({bool inMatch = false}) {
    final run = _run!;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: inMatch ? 0.72 : 0.85,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (_, scroll) => Material(
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      inMatch ? 'In-match substitutions' : 'Edit line-up',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                ],
              ),
              if (inMatch)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Swap starters with bench — changes apply immediately.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary.withValues(alpha: 0.9)),
                  ),
                ),
              WorldCupLineupEditor(
                run: run,
                compact: inMatch,
                onChanged: (updated) {
                  setState(() => _run = updated);
                  _persist();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onMatchTick(Timer t) {
    if (!mounted || _run == null) return;
    final run = _run!;
    final sides = pendingFixtureSides(run)!;
    final homeId = sides.$1;
    final userId = run.userNationId;
    final userIsHome = homeId == userId;
    final userStr = strengthForSide(run, userId);
    final oppId = userIsHome ? sides.$2 : homeId;
    final oppStr = strengthForSide(run, oppId);

    final tick = _liveMatch.tickSecond(
      rng: _rng,
      userIsHome: userIsHome,
      userStrength: userStr,
      oppStrength: oppStr,
      pickBoost: _pickPlayerBoost(),
    );
    _applyLiveGoal(tick);

    setState(() => _secondsLeft--);

    if (_secondsLeft <= 0) {
      t.cancel();
      _moveTimer?.cancel();
      _lastHomeGoals = _liveHomeGoals;
      _lastAwayGoals = _liveAwayGoals;
      _applyPendingMatchResult(_liveHomeGoals, _liveAwayGoals);
    }
  }

  void _applyPendingMatchResult(int homeGoals, int awayGoals) {
    var run = _run!;
    final fixtureId = run.pendingFixtureId!;
    final fix = fixtureById(run, fixtureId)!;
    _lastHomeId ??= fix.homeNationId;
    _lastAwayId ??= fix.awayNationId;

    final result = recordMatchResult(run, fixtureId, homeGoals, awayGoals, _rng);
    run = result.run.copyWith(clearPendingFixture: true, clearMatchPick: true);

    setState(() => _run = run);
    _persist();
    _go(WorldCupPhase.matchResult);
  }

  void _forfeitRun() {
    _matchTimer?.cancel();
    _moveTimer?.cancel();
    setState(() => _run = null);
    _persist(clearRun: true);
    _go(WorldCupPhase.hub);
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'World Cup',
      body: switch (_phase) {
        WorldCupPhase.hub => _buildHub(),
        WorldCupPhase.nationShop => _buildNationShop(),
        WorldCupPhase.pickCountry => _buildPickCountry(),
        WorldCupPhase.pickPlayer => _buildPickPlayer(),
        WorldCupPhase.editLineup => _buildEditLineup(),
        WorldCupPhase.quickPlaySummary => _buildQuickPlaySummary(),
        WorldCupPhase.groupStage => _buildGroupStage(),
        WorldCupPhase.preMatch => _buildPreMatch(),
        WorldCupPhase.matchLive => _buildMatchLive(),
        WorldCupPhase.matchResult => _buildMatchResult(),
        WorldCupPhase.stealPlayer => _buildStealPlayer(),
        WorldCupPhase.surrenderPlayer => _buildSurrenderPlayer(),
        WorldCupPhase.knockout => _buildKnockout(),
        WorldCupPhase.champion => _buildChampion(),
        WorldCupPhase.eliminated => _buildEliminated(),
      },
    );
  }

  Widget _coinBanner() {
    return Card(
      color: AppTheme.warning.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.monetization_on_rounded, color: AppTheme.warning.withValues(alpha: 0.95)),
            const SizedBox(width: 10),
            Text('$_coins coins', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(
              'R32:15 · R16:50 · QF:75 · SF:100 · Final:200 · Win:300',
              style: TextStyle(fontSize: 9, color: AppTheme.textSecondary.withValues(alpha: 0.75)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNationShop() {
    final nations = List<WorldCupNation>.from(kWorldCupNations)
      ..sort((a, b) => nationShopPrice(a.id).compareTo(nationShopPrice(b.id)));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        const Text('Nation shop', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'Prices match squad strength (1–99 scale). Japan are all 99, England all 1. You start with Japan, Algeria & Austria.',
          style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.9)),
        ),
        const SizedBox(height: 12),
        _coinBanner(),
        const SizedBox(height: 12),
        ...nations.map((n) {
          final owned = _ownedNationIds.contains(n.id);
          final price = nationShopPrice(n.id);
          final affordable = _coins >= price;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                child: Text(n.countryCode, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              title: Text(n.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                owned
                    ? 'Owned · Group ${groupLetterForNation(n.id)}'
                    : '$price coins · Group ${groupLetterForNation(n.id)}',
              ),
              trailing: owned
                  ? Icon(Icons.check_circle_rounded, color: AppTheme.success)
                  : FilledButton(
                      onPressed: affordable && price > 0
                          ? () {
                              SoundService.instance.play(GameSound.win);
                              setState(() {
                                _coins -= price;
                                _ownedNationIds = [..._ownedNationIds, n.id];
                              });
                              _persist();
                            }
                          : null,
                      child: Text(price == 0 ? 'Free' : '$price'),
                    ),
            ),
          );
        }),
        TextButton(onPressed: () => _go(WorldCupPhase.hub), child: const Text('Back to hub')),
      ],
    );
  }

  Widget _buildPickPlayer() {
    final run = _run!;
    final fix = fixtureById(run, run.pendingFixtureId!);
    final players = pickablePlayersFromSquad(run.squad);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        const Text('Pick your player', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          fix != null
              ? '${fix.label} — choose a player up to $kWorldCupMaxPickRating rating to play as on the pitch.'
              : 'Choose a player up to $kWorldCupMaxPickRating rating.',
          style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.9), height: 1.35),
        ),
        const SizedBox(height: 16),
        if (players.isEmpty)
          Text('No eligible players up to $kWorldCupMaxPickRating — pick any from squad anyway is unavailable.'),
        ...players.map((p) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.accent.withValues(alpha: 0.2),
                  child: Text(p.position, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${p.position} · ${p.ratingLabel}'),
                trailing: const Icon(Icons.sports_soccer_rounded),
                onTap: () => _onPickPlayer(p.id),
              ),
            )),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => _go(
            run.stage == TournamentStage.knockout ? WorldCupPhase.knockout : WorldCupPhase.groupStage,
          ),
          child: const Text('Back'),
        ),
      ],
    );
  }

  Widget _buildEditLineup() {
    final run = _run!;
    final fix = fixtureById(run, run.pendingFixtureId!);
    final pick = _pickedPlayer();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        const Text('Edit line-up', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          fix != null
              ? '${fix.label} · Tap a starter to substitute, or a bench player to bring on.'
              : 'Set your starting XI before kick-off.',
          style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.9), height: 1.35),
        ),
        if (pick != null) ...[
          const SizedBox(height: 8),
          Text(
            'On-pitch icon: ${pick.name} (${pick.ratingLabel})',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.accent),
          ),
        ],
        const SizedBox(height: 16),
        WorldCupLineupEditor(
          run: run,
          onChanged: (updated) {
            setState(() => _run = updated);
            _persist();
          },
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _continueFromLineup,
          icon: Icon(_pendingAutoSim ? Icons.auto_mode_rounded : Icons.sports_soccer_rounded),
          label: Text(_pendingAutoSim ? 'Quick play' : 'Continue to kick-off'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _go(WorldCupPhase.pickPlayer),
          child: const Text('Change on-pitch player'),
        ),
      ],
    );
  }

  Widget _buildQuickPlaySummary() {
    final homeId = _lastHomeId!;
    final awayId = _lastAwayId!;
    return WorldCupScoreBand(
      homeNationId: homeId,
      awayNationId: awayId,
      homeGoals: _lastHomeGoals,
      awayGoals: _lastAwayGoals,
      goals: _lastMatchGoals,
      onDone: _finishQuickPlaySummary,
    );
  }

  Widget _buildHub() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heroBanner(),
          const SizedBox(height: 14),
          Center(child: worldCupFortyEightTeamsBadge()),
          const SizedBox(height: 12),
          _coinBanner(),
          const SizedBox(height: 16),
          if (_tournamentsStarted > 0 || _wins > 0) _statRow(),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                '48 nations qualified for the 2026 FIFA World Cup (Groups A–L). '
            'Group stage first → Round of 32 → Round of 16 → '
                'quarter-finals → semi-finals → Final. Win to steal a player; lose and '
                'they take one of yours. Other nations play at the same time. Season ratings '
                'run 1 (weakest) to 99 (best) — every England player is 1, every Japan player is 99. '
                'The other 46 nations are spread across the scale. '
                'Pick a player up to $kWorldCupMaxPickRating to control on the pitch. '
                'Start with Japan, Algeria & Austria — buy stronger nations with coins!',
                style: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: 0.95),
                  height: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _go(WorldCupPhase.nationShop),
            icon: const Icon(Icons.storefront_rounded),
            label: const Text('Nation shop'),
          ),
          if (_run != null) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _go(
                _run!.stage == TournamentStage.knockout
                    ? WorldCupPhase.knockout
                    : WorldCupPhase.groupStage,
              ),
              child: const Text('Continue tournament'),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _startNewTournament,
            icon: const Icon(Icons.sports_soccer_rounded),
            label: Text(_run != null ? 'New tournament' : 'Start World Cup'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
        ],
      ),
    );
  }

  Widget _buildPickCountry() {
    final nations = _filteredNations();
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        const Text('Choose your nation',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'Only the $kWorldCupQualifiedTeamCount nations that qualified for the '
          '2026 FIFA World Cup — Groups A to L.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.9), height: 1.35),
        ),
        const SizedBox(height: 14),
        FilledButton.tonalIcon(
          onPressed: _pickRandomOwnedCountry,
          icon: const Icon(Icons.casino_rounded),
          label: const Text('Random nation'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
        const SizedBox(height: 14),
        Center(child: worldCupFortyEightTeamsBadge()),
        const SizedBox(height: 12),
        Text(
          'Search all $kWorldCupQualifiedTeamCount qualifiers (A–Z) · Groups A–L',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.9)),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _countrySearchController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search teams…',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: (_countrySearchController.text.isNotEmpty || _countryLetterFilter != null)
                ? IconButton(icon: const Icon(Icons.clear_rounded), onPressed: _clearCountryFilters)
                : null,
            filled: true,
            fillColor: AppTheme.surface.withValues(alpha: 0.5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: letters.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              if (index == 0) {
                return FilterChip(
                  label: const Text('All'),
                  selected: _countryLetterFilter == null,
                  onSelected: (_) => setState(() => _countryLetterFilter = null),
                  visualDensity: VisualDensity.compact,
                );
              }
              final letter = letters[index - 1];
              final selected = _countryLetterFilter == letter;
              return FilterChip(
                label: Text(letter),
                selected: selected,
                onSelected: (_) => setState(() {
                  _countryLetterFilter = selected ? null : letter;
                }),
                visualDensity: VisualDensity.compact,
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${nations.length} of $kWorldCupQualifiedTeamCount national teams',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 8),
        ...nations.map((n) {
          final group = groupLetterForNation(n.id);
          final owned = _ownedNationIds.contains(n.id);
          final price = nationShopPrice(n.id);
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: owned
                    ? AppTheme.success.withValues(alpha: 0.2)
                    : AppTheme.textSecondary.withValues(alpha: 0.15),
                child: Text(n.countryCode, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              title: Text(n.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                owned
                    ? 'Group $group · ${confederationForNation(n.id)} · Owned'
                    : 'Group $group · ${confederationForNation(n.id)} · $price coins',
              ),
              trailing: owned
                  ? const Icon(Icons.chevron_right_rounded)
                  : Icon(Icons.lock_outline, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
              onTap: () {
                if (owned) {
                  _pickCountry(n.id);
                } else {
                  _go(WorldCupPhase.nationShop);
                }
              },
            ),
          );
        }),
        TextButton(onPressed: () => _go(WorldCupPhase.hub), child: const Text('Back')),
      ],
    );
  }

  Widget _buildTournamentPath(WorldCupRun run) {
    int active;
    if (run.stage == TournamentStage.group) {
      active = 0;
    } else if (run.stage == TournamentStage.knockout) {
      active = 1 + run.knockoutRoundIndex;
    } else {
      active = kWorldCupTournamentStages.length - 1;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tournament path', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 12),
            ...List.generate(kWorldCupTournamentStages.length, (i) {
              final stage = kWorldCupTournamentStages[i];
              final done = i < active;
              final current = i == active;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      done
                          ? Icons.check_circle_rounded
                          : current
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                      size: 20,
                      color: done
                          ? AppTheme.success
                          : current
                              ? AppTheme.accent
                              : AppTheme.textSecondary.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        stage.$2,
                        style: TextStyle(
                          fontWeight: current ? FontWeight.bold : FontWeight.w500,
                          color: current ? AppTheme.accent : null,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (current)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('Now', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              );
            }),
            const Divider(height: 8),
            Row(
              children: [
                Icon(Icons.emoji_events_outlined, size: 18, color: AppTheme.warning.withValues(alpha: 0.9)),
                const SizedBox(width: 8),
                Text(
                  active >= kWorldCupTournamentStages.length - 1 && run.stage != TournamentStage.group
                      ? 'Winner celebration next!'
                      : 'Win the Final for a celebration',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupStage() => _buildTournamentHub(isKnockout: false);

  Widget _buildKnockout() => _buildTournamentHub(isKnockout: true);

  Widget _buildTournamentHub({required bool isKnockout}) {
    final run = _run!;
    final userId = run.userNationId;
    final nextFix = nextUserFixture(run);
    final standings = groupStandingsForLetter(run, run.groupLetter);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          isKnockout
              ? (run.currentKnockoutRound?.label ?? 'Knockout')
              : 'Group ${run.groupLetter}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          tournamentProgressLabel(run),
          style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.9)),
        ),
        const SizedBox(height: 8),
        _buildTournamentPath(run),
        const SizedBox(height: 14),
        if (!isKnockout) _standingsTable(standings, userId),
        if (!isKnockout) const SizedBox(height: 16),
        if (nextFix != null)
          _matchCard(
            title: nextFix.label,
            home: nationById(nextFix.homeNationId).name,
            away: nationById(nextFix.awayNationId).name,
            onPlay: () => _beginUserFixture(autoSim: false),
            onSim: () => _beginUserFixture(autoSim: true),
          )
        else if (run.stage == TournamentStage.group)
          const Text('Waiting for knockout draw…'),
        const SizedBox(height: 16),
        _buildAllFixturesSection(run),
        const SizedBox(height: 16),
        if (run.recentNews.isNotEmpty) _buildTransferNews(run),
        const SizedBox(height: 16),
        _buildSquadCard(run.squad),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _forfeitRun, child: const Text('Quit tournament')),
      ],
    );
  }

  Widget _buildAllFixturesSection(WorldCupRun run) {
    final fixtures = fixturesOf(run);
    final title = run.stage == TournamentStage.group
        ? 'Matchday ${run.groupMatchday + 1} · all groups'
        : '${run.currentKnockoutRound?.label ?? 'Knockout'} fixtures';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            ...fixtures.where((f) {
              if (run.stage == TournamentStage.group) {
                return f.kind == FixtureKind.group && f.groupMatchday == run.groupMatchday;
              }
              return f.kind == FixtureKind.knockout &&
                  f.knockoutRound == run.currentKnockoutRound;
            }).map((f) => _fixtureRow(f, run.userNationId)),
          ],
        ),
      ),
    );
  }

  Widget _fixtureRow(WorldCupFixture f, String userId) {
    final home = nationById(f.homeNationId).name;
    final away = nationById(f.awayNationId).name;
    final involvesUser = f.involves(userId);
    final score = f.played ? '${f.homeGoals}–${f.awayGoals}' : 'vs';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (f.groupLetter != null)
            SizedBox(
              width: 28,
              child: Text(f.groupLetter!,
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary.withValues(alpha: 0.7))),
            ),
          Expanded(
            child: Text(
              '$home $score $away',
              style: TextStyle(
                fontSize: 12,
                fontWeight: involvesUser ? FontWeight.bold : FontWeight.w500,
                color: involvesUser ? AppTheme.accent : null,
              ),
            ),
          ),
          if (f.played)
            Icon(Icons.check_circle_outline, size: 16, color: AppTheme.success.withValues(alpha: 0.8))
          else if (involvesUser)
            Icon(Icons.sports_soccer_rounded, size: 16, color: AppTheme.accent)
          else
            Icon(Icons.schedule_rounded, size: 16, color: AppTheme.textSecondary.withValues(alpha: 0.4)),
        ],
      ),
    );
  }

  Widget _buildTransferNews(WorldCupRun run) {
    return Card(
      color: AppTheme.warning.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Transfer news', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            ...run.recentNews.take(8).map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(line, style: const TextStyle(fontSize: 12)),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _matchCard({
    required String title,
    required String home,
    required String away,
    required VoidCallback onPlay,
    required VoidCallback onSim,
  }) {
    return Card(
      color: AppTheme.accent.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            Text('$home vs $away', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Quick play shows the score & goal scorers instantly.',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onPlay,
              icon: const Icon(Icons.sports_soccer_rounded),
              label: const Text('Play'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onSim,
              icon: const Icon(Icons.auto_mode_rounded),
              label: const Text('Quick play'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreMatch() {
    final run = _run!;
    final fix = fixtureById(run, run.pendingFixtureId!)!;
    final home = nationById(fix.homeNationId);
    final away = nationById(fix.awayNationId);
    final stageLabel = fix.label;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(stageLabel, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Text('${home.name} vs ${away.name}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(
            'Play with Pass, Cross, Shoot, Tackle on the pitch — or edit your line-up first.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.9), height: 1.35),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _go(WorldCupPhase.editLineup),
            icon: const Icon(Icons.groups_rounded),
            label: const Text('Edit line-up'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _playLive,
            icon: const Icon(Icons.sports_soccer_rounded),
            label: const Text('Kick off'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => _go(WorldCupPhase.editLineup),
            child: const Text('Back to line-up'),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => _go(
              pendingFixtureIsKnockout(run) ? WorldCupPhase.knockout : WorldCupPhase.groupStage,
            ),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchLive() {
    final run = _run!;
    final fix = fixtureById(run, run.pendingFixtureId!)!;
    final mm = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final ss = (_secondsLeft % 60).toString().padLeft(2, '0');
    final pick = _pickedPlayer();
    final homeXi = startingXiPlayers(squadOf(run, fix.homeNationId));
    final awayXi = startingXiPlayers(squadOf(run, fix.awayNationId));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openLineupEditor(inMatch: true),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text('Substitutions'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              children: [
                Text('$mm:$ss', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
                if (pick != null)
                  Text('Playing as ${pick.name} (${pick.ratingLabel})',
                      style: TextStyle(fontSize: 12, color: AppTheme.accent, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Expanded(
                  child: WorldCupPitchView(
                    homeNationId: fix.homeNationId,
                    awayNationId: fix.awayNationId,
                    userNationId: run.userNationId,
                    homeGoals: _liveHomeGoals,
                    awayGoals: _liveAwayGoals,
                    homePlayers: homeXi,
                    awayPlayers: awayXi,
                    pickPlayer: pick,
                    playerPos: _playerPos,
                    ballPos: _ballPos,
                    fuel: _liveMatch.fuel,
                    buildup: _liveMatch.buildup,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _liveMatch.freeKickActive
                          ? AppTheme.warning.withValues(alpha: 0.6)
                          : AppTheme.textSecondary.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Text(
                    _liveMatch.feedback,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: _liveMatch.freeKickActive ? AppTheme.warning : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        _mobileControls(),
      ],
    );
  }

  Widget _mobileControls() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: 0.92),
          border: Border(top: BorderSide(color: AppTheme.textSecondary.withValues(alpha: 0.15))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            VirtualJoystick(onDirectionChanged: _onJoystick, size: 128),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _ctrlBtn('Pass', Icons.swap_horiz_rounded, AppTheme.blue, MatchAction.pass),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ctrlBtn(
                          'Shoot',
                          Icons.sports_soccer_rounded,
                          AppTheme.warning,
                          MatchAction.shoot,
                          emphasized: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _ctrlBtn('Cross', Icons.upload_rounded, AppTheme.purple, MatchAction.cross),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ctrlBtn(
                          'Sprint',
                          Icons.directions_run_rounded,
                          AppTheme.success,
                          MatchAction.sprint,
                        ),
                      ),
                    ],
                  ),
                  if (_liveMatch.freeKickActive) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: _ctrlBtn(
                        'Free Kick',
                        Icons.flag_rounded,
                        AppTheme.warning,
                        MatchAction.freeKick,
                        emphasized: true,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ctrlBtn(
    String label,
    IconData icon,
    Color color,
    MatchAction action, {
    bool emphasized = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onMatchAction(action),
      child: Container(
        decoration: BoxDecoration(
          color: emphasized ? color.withValues(alpha: 0.28) : color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: emphasized ? 0.7 : 0.35), width: emphasized ? 2 : 1),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Icon(icon, color: color, size: emphasized ? 30 : 26),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: emphasized ? 14 : 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchResult() {
    final homeId = _lastHomeId!;
    final awayId = _lastAwayId!;
    final hName = nationById(homeId).name;
    final aName = nationById(awayId).name;
    final userId = _run?.userNationId;
    final run = _run;
    final userStr = run != null ? strengthForSide(run, userId!) : 50.0;
    final oppId = userId == homeId ? awayId : homeId;
    final oppStr = run != null ? strengthForSide(run, oppId) : 50.0;
    final won = userId != null &&
        userWonMatch(
          userNationId: userId,
          homeId: homeId,
          awayId: awayId,
          homeGoals: _lastHomeGoals,
          awayGoals: _lastAwayGoals,
          userStrength: userStr,
          oppStrength: oppStr,
        );
    final drew = _lastHomeGoals == _lastAwayGoals;
    final needsSteal = run != null && userMustSteal(run);
    final needsSurrender = run != null && userMustSurrender(run);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _lastMatchWasAutoSim ? Icons.auto_mode_rounded : Icons.sports_soccer_rounded,
            size: 56,
            color: AppTheme.accent,
          ),
          const SizedBox(height: 12),
          Text(_lastMatchWasAutoSim ? 'Match complete' : 'Full time',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Text(
            singleMatchScoreline(hName, aName, _lastHomeGoals, _lastAwayGoals),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          if (_lastMatchGoals.isNotEmpty) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Scorers', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textSecondary.withValues(alpha: 0.9))),
            ),
            const SizedBox(height: 8),
            ..._lastMatchGoals.map(
              (g) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: Text("${g.minute}'", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    Expanded(child: Text('${g.playerName} (${nationById(g.nationId).name})', style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (needsSteal)
            Text(
              'You win — pick a player to steal!',
              style: TextStyle(fontSize: 16, color: AppTheme.success, fontWeight: FontWeight.w600),
            )
          else if (needsSurrender)
            Text(
              'You lose — pick a player to give to the winner.',
              style: TextStyle(fontSize: 16, color: AppTheme.danger, fontWeight: FontWeight.w600),
            )
          else if (drew)
            Text('Draw — no transfer',
                style: TextStyle(fontSize: 16, color: AppTheme.textSecondary, fontWeight: FontWeight.w600))
          else
            Text(
              won ? 'You win!' : 'You lose',
              style: TextStyle(
                fontSize: 16,
                color: won ? AppTheme.success : AppTheme.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _continueFromResult,
            child: Text(needsSteal || needsSurrender ? 'Next' : 'Continue'),
          ),
        ],
      ),
    );
  }

  void _continueFromResult() {
    final run = _run;
    if (run == null) {
      _go(WorldCupPhase.hub);
      return;
    }
    if (userMustSteal(run)) {
      _go(WorldCupPhase.stealPlayer);
      return;
    }
    if (userMustSurrender(run)) {
      _go(WorldCupPhase.surrenderPlayer);
      return;
    }
    _goToTournamentPhase(run);
  }

  void _finishTransferFlow() {
    var run = finishTransferAndSimBatch(_run!, _rng);
    if (run.stage == TournamentStage.champion) {
      _wins += 1;
      _championNationName = nationById(run.userNationId).name;
      _grantCoinReward(run, champion: true);
      setState(() => _run = null);
      _persist(clearRun: true);
      _go(WorldCupPhase.champion);
      return;
    }
    if (isUserEliminated(run) || run.stage == TournamentStage.eliminated) {
      _grantCoinReward(run, champion: false);
      setState(() => _run = null);
      _persist(clearRun: true);
      _go(WorldCupPhase.eliminated);
      return;
    }
    setState(() => _run = run);
    _persist();
    _goToTournamentPhase(run);
  }

  void _goToTournamentPhase(WorldCupRun run) {
    _go(switch (run.stage) {
      TournamentStage.group => WorldCupPhase.groupStage,
      TournamentStage.knockout => WorldCupPhase.knockout,
      TournamentStage.eliminated => WorldCupPhase.eliminated,
      TournamentStage.champion => WorldCupPhase.champion,
    });
  }

  Widget _buildStealPlayer() {
    final run = _run!;
    final loserId = run.transferLoserId!;
    final players = stealablePlayers(run, loserId);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        const Text('Steal a player',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'Pick anyone from ${nationById(loserId).name} to join your squad.',
          style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.9)),
        ),
        const SizedBox(height: 16),
        ...players.map((p) => Card(
              child: ListTile(
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${p.position} · ${p.ratingLabel}'),
                trailing: const Icon(Icons.add_circle_outline_rounded),
                onTap: () {
                  SoundService.instance.play(GameSound.win);
                  setState(() => _run = applyUserSteal(_run!, p.id));
                  _finishTransferFlow();
                },
              ),
            )),
      ],
    );
  }

  Widget _buildSurrenderPlayer() {
    final run = _run!;
    final winnerId = run.transferWinnerId!;
    final squad = run.squad;
    final players = squadPlayers(squad)
      ..sort((a, b) => b.rating2526.compareTo(a.rating2526));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        const Text('Give up a player',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'You lost — ${nationById(winnerId).name} takes one of your players.',
          style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.9)),
        ),
        const SizedBox(height: 16),
        ...players.map((p) => Card(
              child: ListTile(
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${p.position} · ${p.ratingLabel}'),
                trailing: Icon(Icons.arrow_forward_rounded, color: AppTheme.danger),
                onTap: () {
                  SoundService.instance.play(GameSound.hit);
                  setState(() => _run = applyUserSurrenderPlayer(_run!, p.id));
                  _finishTransferFlow();
                },
              ),
            )),
      ],
    );
  }

  Widget _standingsTable(List<GroupStandingRow> rows, String userId) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            const Row(
              children: [
                Expanded(flex: 3, child: Text('Team', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 36, child: Text('P', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                SizedBox(width: 36, child: Text('GD', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                SizedBox(width: 36, child: Text('Pts', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
              ],
            ),
            const Divider(height: 16),
            ...rows.map((r) {
              final isUser = r.nationId == userId;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        nationById(r.nationId).name,
                        style: TextStyle(
                          fontWeight: isUser ? FontWeight.bold : FontWeight.w500,
                          color: isUser ? AppTheme.accent : null,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    SizedBox(width: 36, child: Text('${r.played}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                    SizedBox(width: 36, child: Text('${r.gd >= 0 ? '+' : ''}${r.gd}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                    SizedBox(width: 36, child: Text('${r.points}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSquadCard(WorldCupSquad squad) {
    final players = squadPlayers(squad)
      ..sort((a, b) => b.rating2526.compareTo(a.rating2526));
    final xi = squad.startingXiIds.toSet();
    final starters = players.where((p) => xi.contains(p.id)).toList();
    final bench = players.where((p) => !xi.contains(p.id)).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Your squad', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                Text(
                  '${squad.playerIds.length}/$kWorldCupSquadSize',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accent,
                  ),
                ),
              ],
            ),
            Text(
              '$kWorldCupStartingXi starting · $kWorldCupBenchSize bench · '
              'Strength ${squadFieldStrength(squad).toStringAsFixed(1)}',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary.withValues(alpha: 0.85)),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _openLineupEditor(),
              icon: const Icon(Icons.groups_rounded, size: 18),
              label: const Text('Edit line-up'),
            ),
            const SizedBox(height: 12),
            Text('Starting XI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.success)),
            const SizedBox(height: 6),
            ...starters.map((p) => _squadRow(p, isStarter: true)),
            const SizedBox(height: 10),
            Text('Bench', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
            const SizedBox(height: 6),
            ...bench.map((p) => _squadRow(p, isStarter: false)),
          ],
        ),
      ),
    );
  }

  Widget _squadRow(WorldCupPlayer p, {required bool isStarter}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(p.position, style: TextStyle(fontSize: 11, color: AppTheme.textSecondary.withValues(alpha: 0.8))),
          ),
          Expanded(child: Text(p.name, style: TextStyle(fontSize: 13, fontWeight: isStarter ? FontWeight.w600 : FontWeight.normal))),
          Text(p.ratingLabel, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isStarter ? AppTheme.accent : AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildChampion() {
    return WorldCupCelebration(
      nationName: _championNationName ?? 'Champions',
      onDone: () => _go(WorldCupPhase.hub),
    );
  }

  Widget _buildEliminated() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.flag_rounded, size: 64, color: AppTheme.danger.withValues(alpha: 0.8)),
            const SizedBox(height: 16),
            const Text('Eliminated', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(
              'Group stage → Round of 32 → Round of 16 → quarter-finals → semi-finals → Final. '
              'Win a match to steal a player; lose and they take yours.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.9), height: 1.4),
            ),
            if (_lastCoinReward > 0) ...[
              const SizedBox(height: 16),
              Text(
                coinRewardLabel(_lastCoinReward),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.warning),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'Out in the group — no coins this run.',
                style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.85)),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton(onPressed: () => _go(WorldCupPhase.hub), child: const Text('Back to hub')),
          ],
        ),
      ),
    );
  }

  Widget _heroBanner() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            AppTheme.success.withValues(alpha: 0.35),
            AppTheme.primaryMid,
            AppTheme.blue.withValues(alpha: 0.4),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Icon(Icons.emoji_events_rounded, size: 56, color: AppTheme.warning.withValues(alpha: 0.95)),
          const SizedBox(height: 12),
          const Text('World Cup 2026', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            '48 nations · 2026 FIFA World Cup qualifiers',
            style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.95)),
          ),
        ],
      ),
    );
  }

  Widget _statRow() {
    return Row(
      children: [
        Expanded(child: _miniStat('Runs', '$_tournamentsStarted', Icons.flag_rounded)),
        const SizedBox(width: 8),
        Expanded(child: _miniStat('Trophies', '$_wins', Icons.emoji_events_outlined)),
        const SizedBox(width: 8),
        Expanded(child: _miniStat('Coins', '$_coins', Icons.monetization_on_outlined)),
      ],
    );
  }

  Widget _miniStat(String label, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.accent, size: 22),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary.withValues(alpha: 0.85))),
                Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
