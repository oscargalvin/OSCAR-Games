import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'world_cup_data.dart';
import 'world_cup_models.dart';
import 'world_cup_tournament.dart';

List<WorldCupPlayer> startingPlayers(WorldCupSquad squad) {
  final byId = {for (final p in squadPlayers(squad)) p.id: p};
  return squad.startingXiIds.map((id) => byId[id]).whereType<WorldCupPlayer>().toList();
}

List<WorldCupPlayer> benchPlayers(WorldCupSquad squad) {
  final xi = squad.startingXiIds.toSet();
  return squadPlayers(squad).where((p) => !xi.contains(p.id)).toList()
    ..sort((a, b) => b.rating2526.compareTo(a.rating2526));
}

WorldCupRun swapUserLineup(WorldCupRun run, String starterOutId, String benchInId) {
  final squad = squadOf(run, run.userNationId);
  if (!squad.startingXiIds.contains(starterOutId)) return run;
  if (squad.startingXiIds.contains(benchInId)) return run;
  if (!squad.playerIds.contains(benchInId)) return run;

  final xi = List<String>.from(squad.startingXiIds);
  final idx = xi.indexOf(starterOutId);
  xi[idx] = benchInId;
  return updateSquad(run, squad.copyWith(startingXiIds: xi));
}

/// Substitute editor — starting XI and bench with tap-to-swap.
class WorldCupLineupEditor extends StatelessWidget {
  const WorldCupLineupEditor({
    super.key,
    required this.run,
    required this.onChanged,
    this.compact = false,
  });

  final WorldCupRun run;
  final ValueChanged<WorldCupRun> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final squad = run.squad;
    final starters = startingPlayers(squad);
    final bench = benchPlayers(squad);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Starting XI (${starters.length}/$kWorldCupStartingXi)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: compact ? 13 : 14,
            color: AppTheme.success,
          ),
        ),
        const SizedBox(height: 6),
        ...starters.map((p) => _playerTile(context, p, isStarter: true)),
        const SizedBox(height: 10),
        Text(
          'Bench',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: compact ? 13 : 14,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        if (bench.isEmpty)
          Text(
            'No bench players available.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary.withValues(alpha: 0.8)),
          ),
        ...bench.map((p) => _playerTile(context, p, isStarter: false)),
      ],
    );
  }

  Widget _playerTile(BuildContext context, WorldCupPlayer p, {required bool isStarter}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: compact,
        visualDensity: compact ? VisualDensity.compact : null,
        leading: CircleAvatar(
          radius: compact ? 16 : 18,
          backgroundColor: isStarter
              ? AppTheme.success.withValues(alpha: 0.2)
              : AppTheme.surface.withValues(alpha: 0.5),
          child: Text(p.position, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
        ),
        title: Text(p.name, style: TextStyle(fontWeight: isStarter ? FontWeight.w600 : FontWeight.normal, fontSize: compact ? 13 : 14)),
        subtitle: Text('${p.ratingLabel} · ${isStarter ? 'Starter' : 'Bench'}', style: const TextStyle(fontSize: 11)),
        trailing: Icon(
          isStarter ? Icons.swap_horiz_rounded : Icons.add_circle_outline_rounded,
          color: isStarter ? AppTheme.accent : AppTheme.success,
          size: compact ? 20 : 24,
        ),
        onTap: () => _onTap(context, p, isStarter),
      ),
    );
  }

  void _onTap(BuildContext context, WorldCupPlayer p, bool isStarter) {
    if (isStarter) {
      final bench = benchPlayers(run.squad);
      if (bench.isEmpty) return;
      _showPickReplacement(context, p, bench);
    } else {
      final starters = startingPlayers(run.squad);
      _showPickStarterToReplace(context, p, starters);
    }
  }

  void _showPickReplacement(BuildContext context, WorldCupPlayer out, List<WorldCupPlayer> bench) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Substitute ${out.name}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ...bench.map(
              (b) => ListTile(
                title: Text(b.name),
                subtitle: Text('${b.position} · ${b.ratingLabel}'),
                onTap: () {
                  Navigator.pop(ctx);
                  onChanged(swapUserLineup(run, out.id, b.id));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPickStarterToReplace(BuildContext context, WorldCupPlayer benchIn, List<WorldCupPlayer> starters) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Bring on ${benchIn.name} — replace who?',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ...starters.map(
              (s) => ListTile(
                title: Text(s.name),
                subtitle: Text('${s.position} · ${s.ratingLabel}'),
                onTap: () {
                  Navigator.pop(ctx);
                  onChanged(swapUserLineup(run, s.id, benchIn.id));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
