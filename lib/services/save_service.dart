import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SaveService {
  SaveService._();
  static final SaveService _instance = SaveService._();
  static SaveService get instance => _instance;

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // --- Target Shooter Player Data ---

  Future<void> savePlayerData({
    required int diamonds,
    required List<String> ownedBowIds,
    required List<String> ownedArrowIds,
    required String equippedBowId,
    required String equippedArrowId,
    required bool hasVip,
    required bool hasShieldKeychain,
    required bool has67Keychain,
    required bool hasComboKeychain,
    required Map<String, int> worldProgress,
    required int totalTargetsHit,
    required int totalLevelsCompleted,
  }) async {
    await _prefs.setInt('diamonds', diamonds);
    await _prefs.setStringList('ownedBowIds', ownedBowIds);
    await _prefs.setStringList('ownedArrowIds', ownedArrowIds);
    await _prefs.setString('equippedBowId', equippedBowId);
    await _prefs.setString('equippedArrowId', equippedArrowId);
    await _prefs.setBool('hasVip', hasVip);
    await _prefs.setBool('hasShieldKeychain', hasShieldKeychain);
    await _prefs.setBool('has67Keychain', has67Keychain);
    await _prefs.setBool('hasComboKeychain', hasComboKeychain);
    await _prefs.setString('worldProgress', jsonEncode(worldProgress));
    await _prefs.setInt('totalTargetsHit', totalTargetsHit);
    await _prefs.setInt('totalLevelsCompleted', totalLevelsCompleted);
  }

  int get diamonds => _prefs.getInt('diamonds') ?? 25;
  List<String> get ownedBowIds =>
      _prefs.getStringList('ownedBowIds') ?? ['default'];
  List<String> get ownedArrowIds =>
      _prefs.getStringList('ownedArrowIds') ?? ['default'];
  String get equippedBowId => _prefs.getString('equippedBowId') ?? 'default';
  String get equippedArrowId =>
      _prefs.getString('equippedArrowId') ?? 'default';
  bool get hasVip => _prefs.getBool('hasVip') ?? false;
  bool get hasShieldKeychain => _prefs.getBool('hasShieldKeychain') ?? false;
  bool get has67Keychain => _prefs.getBool('has67Keychain') ?? false;
  bool get hasComboKeychain => _prefs.getBool('hasComboKeychain') ?? false;
  int get totalTargetsHit => _prefs.getInt('totalTargetsHit') ?? 0;
  int get totalLevelsCompleted => _prefs.getInt('totalLevelsCompleted') ?? 0;

  Map<String, int> get worldProgress {
    final raw = _prefs.getString('worldProgress');
    if (raw == null) {
      return {
        'playground': 1,
        'jupiter': 1,
        'backrooms': 1,
        'bedroom': 1,
      };
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final result = decoded.map((k, v) => MapEntry(k, v as int));
    result.putIfAbsent('bedroom', () => 1);
    return result;
  }

  bool get hasPlayerData => _prefs.getInt('diamonds') != null;

  // --- Game High Scores ---

  Future<void> saveHighScore(String gameId, int score) async {
    final key = 'highscore_$gameId';
    final current = _prefs.getInt(key) ?? 0;
    if (score > current) {
      await _prefs.setInt(key, score);
    }
  }

  int getHighScore(String gameId) {
    return _prefs.getInt('highscore_$gameId') ?? 0;
  }

  Future<void> saveSnakeHighScore(int score) =>
      saveHighScore('snake', score);
  int get snakeHighScore => getHighScore('snake');

  Future<void> saveTicTacToeStats({
    required int winsX,
    required int winsO,
    required int draws,
  }) async {
    await _prefs.setInt('ttt_winsX', winsX);
    await _prefs.setInt('ttt_winsO', winsO);
    await _prefs.setInt('ttt_draws', draws);
  }

  int get tttWinsX => _prefs.getInt('ttt_winsX') ?? 0;
  int get tttWinsO => _prefs.getInt('ttt_winsO') ?? 0;
  int get tttDraws => _prefs.getInt('ttt_draws') ?? 0;

  Future<void> saveMemoryBestMoves(int gridSize, int moves) async {
    final key = 'memory_best_${gridSize}x$gridSize';
    final current = _prefs.getInt(key);
    if (current == null || moves < current) {
      await _prefs.setInt(key, moves);
    }
  }

  Future<void> saveMemoryBestTime(int gridSize, int seconds) async {
    final key = 'memory_time_${gridSize}x$gridSize';
    final current = _prefs.getInt(key);
    if (current == null || seconds < current) {
      await _prefs.setInt(key, seconds);
    }
  }

  int? memoryBestMoves(int gridSize) =>
      _prefs.getInt('memory_best_${gridSize}x$gridSize');
  int? memoryBestTime(int gridSize) =>
      _prefs.getInt('memory_time_${gridSize}x$gridSize');

  Future<void> saveReactionBest(int ms) async {
    final current = _prefs.getInt('reaction_best');
    if (current == null || ms < current) {
      await _prefs.setInt('reaction_best', ms);
    }
  }

  Future<void> saveReactionGamesPlayed(int count) async {
    await _prefs.setInt('reaction_played', count);
  }

  int? get reactionBest => _prefs.getInt('reaction_best');
  int get reactionGamesPlayed => _prefs.getInt('reaction_played') ?? 0;

  // --- Lucky Fish (boat_fishing prefs) ---

  static const String _fishCoinsKey = 'fish_coins';
  static const String _fishingBoatsKey = 'fishing_boats_owned';
  static const String _fishingRodsKey = 'fishing_rods_owned';
  static const String _fishingBoatEquippedKey = 'fishing_boat_equipped';
  static const String _fishingRodEquippedKey = 'fishing_rod_equipped';
  static const String _fishingInventoryKey = 'fishing_inventory';
  static const String _fishingTotalCaughtKey = 'fishing_total_caught';
  static const String _fishingRedeemedCodesKey = 'fishing_redeemed_codes';

  int get fishCoins => _prefs.getInt(_fishCoinsKey) ?? 0;

  Future<void> setFishCoins(int value) async {
    await _prefs.setInt(_fishCoinsKey, value.clamp(0, 1 << 30));
  }

  List<String> get fishingOwnedBoats =>
      _prefs.getStringList(_fishingBoatsKey) ?? const ['dinghy'];

  List<String> get fishingOwnedRods =>
      _prefs.getStringList(_fishingRodsKey) ?? const ['bamboo'];

  String get fishingEquippedBoatId =>
      _prefs.getString(_fishingBoatEquippedKey) ?? 'dinghy';

  String get fishingEquippedRodId =>
      _prefs.getString(_fishingRodEquippedKey) ?? 'bamboo';

  int get fishingTotalCaught => _prefs.getInt(_fishingTotalCaughtKey) ?? 0;

  Future<void> saveFishingProgress({
    required int fishCoins,
    required List<String> ownedBoats,
    required List<String> ownedRods,
    required String equippedBoatId,
    required String equippedRodId,
    required Map<String, int> inventory,
    required int totalCaught,
  }) async {
    await _prefs.setInt(_fishCoinsKey, fishCoins);
    await _prefs.setStringList(_fishingBoatsKey, ownedBoats);
    await _prefs.setStringList(_fishingRodsKey, ownedRods);
    await _prefs.setString(_fishingBoatEquippedKey, equippedBoatId);
    await _prefs.setString(_fishingRodEquippedKey, equippedRodId);
    await _prefs.setString(_fishingInventoryKey, jsonEncode(inventory));
    await _prefs.setInt(_fishingTotalCaughtKey, totalCaught);
  }

  Map<String, int> get fishingInventory {
    final raw = _prefs.getString(_fishingInventoryKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as int));
    } catch (_) {
      return {};
    }
  }

  List<String> get fishingRedeemedCodes =>
      _prefs.getStringList(_fishingRedeemedCodesKey) ?? const [];

  Future<void> saveFishingRedeemedCodes(List<String> codes) async {
    await _prefs.setStringList(_fishingRedeemedCodesKey, codes);
  }

  // --- World Cup ---

  static const String _worldCupTournamentsKey = 'world_cup_tournaments_started';
  static const String _worldCupWinsKey = 'world_cup_wins';
  static const String _worldCupActiveRunKey = 'world_cup_active_run';

  int get worldCupTournamentsStarted =>
      _prefs.getInt(_worldCupTournamentsKey) ?? 0;

  int get worldCupWins => _prefs.getInt(_worldCupWinsKey) ?? 0;

  String? get worldCupActiveRunJson => _prefs.getString(_worldCupActiveRunKey);

  Future<void> saveWorldCupProgress({
    required int tournamentsStarted,
    required int wins,
    String? activeRunJson,
    int? coins,
    List<String>? ownedNationIds,
  }) async {
    await _prefs.setInt(_worldCupTournamentsKey, tournamentsStarted);
    await _prefs.setInt(_worldCupWinsKey, wins);
    if (activeRunJson == null) {
      await _prefs.remove(_worldCupActiveRunKey);
    } else {
      await _prefs.setString(_worldCupActiveRunKey, activeRunJson);
    }
    if (coins != null) {
      await _prefs.setInt(_worldCupCoinsKey, coins.clamp(0, 999999));
    }
    if (ownedNationIds != null) {
      await _prefs.setStringList(_worldCupOwnedNationsKey, ownedNationIds);
    }
  }

  static const String _worldCupCoinsKey = 'world_cup_coins';
  static const String _worldCupOwnedNationsKey = 'world_cup_owned_nations';
  static const String _worldCupSaveVersionKey = 'world_cup_save_version';
  static const int kWorldCupSaveVersion = 4;

  int get worldCupCoins => _prefs.getInt(_worldCupCoinsKey) ?? 0;

  List<String> get worldCupOwnedNationIds {
    final stored = _prefs.getStringList(_worldCupOwnedNationsKey);
    if (stored == null || stored.isEmpty) {
      return const ['jpn', 'alg', 'aut'];
    }
    return stored;
  }

  Future<void> ensureWorldCupDefaults() async {
    if (!_prefs.containsKey(_worldCupOwnedNationsKey)) {
      await _prefs.setStringList(_worldCupOwnedNationsKey, const ['jpn', 'alg', 'aut']);
    } else {
      final stored = List<String>.from(_prefs.getStringList(_worldCupOwnedNationsKey) ?? []);
      if (!stored.contains('jpn')) {
        stored.insert(0, 'jpn');
        await _prefs.setStringList(_worldCupOwnedNationsKey, stored);
      }
    }

    final version = _prefs.getInt(_worldCupSaveVersionKey) ?? 0;
    if (version < kWorldCupSaveVersion) {
      await _prefs.remove(_worldCupActiveRunKey);
      await _prefs.setInt(_worldCupSaveVersionKey, kWorldCupSaveVersion);
    }
  }
}
