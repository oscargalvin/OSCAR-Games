import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outplay_avatar.dart';

/// How a weapon looks in the shop and in your hands.
enum WeaponLook {
  rifle,
  laser,
  confetti,
  snowball,
  zapper,
  bubble,
  flamer,
  rpgMini,
  fist,
  knife,
  pan,
  slapper,
  scythe,
  snake,
}

/// How a gun's shots travel.
enum ShotKind {
  /// Hits instantly along a line.
  instant,

  /// A ball you can see flying (and dodge).
  ball,
}

class Gun {
  final String id;
  final String name;
  final String blurb;
  final int price;
  final double damage;
  final double fireInterval; // seconds between shots
  final int pellets;
  final double spread; // radians either side
  final double range; // in map squares
  final int mag;
  final double reload;
  final double moveMul; // walking speed while holding it
  final ShotKind kind;
  final double ballSpeed; // squares per second, for balls
  final double splash; // splash radius in squares, for balls
  final double slow; // seconds a hit slows the target down
  final bool custom; // an Outplay original
  final Color color;
  final Color shotColor;
  final WeaponLook look;

  const Gun({
    required this.id,
    required this.name,
    required this.blurb,
    required this.price,
    required this.damage,
    required this.fireInterval,
    this.pellets = 1,
    this.spread = 0.03,
    required this.range,
    required this.mag,
    required this.reload,
    this.moveMul = 1,
    this.kind = ShotKind.instant,
    this.ballSpeed = 0,
    this.splash = 0,
    this.slow = 0,
    this.custom = false,
    required this.color,
    required this.shotColor,
    required this.look,
  });
}

class Melee {
  final String id;
  final String name;
  final String blurb;
  final int price;
  final double damage;
  final double cooldown;
  final double reach; // in map squares
  final double arc; // full swing angle in radians
  final double knockback;
  final double moveMul;
  final Color color;
  final WeaponLook look;

  /// Pulls whoever it hits over to you instead of knocking them away.
  final bool hook;

  const Melee({
    this.hook = false,
    required this.id,
    required this.name,
    required this.blurb,
    required this.price,
    required this.damage,
    required this.cooldown,
    required this.reach,
    required this.arc,
    this.knockback = 0.3,
    required this.moveMul,
    required this.color,
    required this.look,
  });
}

const List<Gun> kGuns = [
  Gun(
    id: 'assault_rifle',
    name: 'Assault Rifle',
    blurb: 'Your trusty starter. Good at everything.',
    price: 0,
    damage: 13,
    fireInterval: 0.11,
    range: 14,
    mag: 30,
    reload: 1.6,
    color: Color(0xFF7FB3FF),
    shotColor: Color(0xFFFFF59D),
    look: WeaponLook.rifle,
  ),
  Gun(
    id: 'laser_blaster',
    name: 'Laser Blaster',
    blurb: 'Pew pew! A perfectly straight laser that reaches far.',
    price: 150,
    damage: 24,
    fireInterval: 0.32,
    spread: 0,
    range: 22,
    mag: 14,
    reload: 1.4,
    custom: true,
    color: Color(0xFFFF4D8D),
    shotColor: Color(0xFFFF4D8D),
    look: WeaponLook.laser,
  ),
  Gun(
    id: 'confetti_popper',
    name: 'Confetti Popper',
    blurb: 'A party blast of confetti. Huge damage up close.',
    price: 250,
    damage: 9,
    fireInterval: 0.75,
    pellets: 7,
    spread: 0.16,
    range: 6,
    mag: 5,
    reload: 1.8,
    custom: true,
    color: Color(0xFFFFD54F),
    shotColor: Color(0xFFFFD54F),
    look: WeaponLook.confetti,
  ),
  Gun(
    id: 'snowball_cannon',
    name: 'Snowball Cannon',
    blurb: 'Big snowballs that freeze people so they walk slowly.',
    price: 350,
    damage: 28,
    fireInterval: 0.7,
    spread: 0.01,
    range: 16,
    mag: 6,
    reload: 1.8,
    kind: ShotKind.ball,
    ballSpeed: 11,
    slow: 1.6,
    custom: true,
    color: Color(0xFFB3E5FC),
    shotColor: Colors.white,
    look: WeaponLook.snowball,
  ),
  Gun(
    id: 'thunder_zapper',
    name: 'Thunder Zapper',
    blurb: 'Zaps lightning at anyone close. Never misses up close.',
    price: 450,
    damage: 9,
    fireInterval: 0.08,
    spread: 0.08,
    range: 4.5,
    mag: 40,
    reload: 2.0,
    custom: true,
    color: Color(0xFF80DEEA),
    shotColor: Color(0xFF84FFFF),
    look: WeaponLook.zapper,
  ),
  Gun(
    id: 'bubble_blaster',
    name: 'Bubble Blaster',
    blurb: 'Slow giant bubbles that pop with a big splash.',
    price: 600,
    damage: 45,
    fireInterval: 1.0,
    spread: 0,
    range: 12,
    mag: 4,
    reload: 2.0,
    kind: ShotKind.ball,
    ballSpeed: 5,
    splash: 1.1,
    custom: true,
    color: Color(0xFFCE93D8),
    shotColor: Color(0xFFE1BEE7),
    look: WeaponLook.bubble,
  ),
  Gun(
    id: 'flamethrower',
    name: 'Flamethrower',
    blurb: 'Short range fire that never stops.',
    price: 700,
    damage: 3.6,
    fireInterval: 0.05,
    pellets: 2,
    spread: 0.2,
    range: 3.6,
    mag: 80,
    reload: 2.2,
    moveMul: 0.95,
    color: Color(0xFFFF7043),
    shotColor: Color(0xFFFF9800),
    look: WeaponLook.flamer,
  ),
  Gun(
    id: 'rpg_mini',
    name: 'RPG Mini',
    blurb: 'A mini rocket launcher that fires rockets as fast as a minigun!',
    price: 900,
    damage: 8,
    fireInterval: 0.08,
    spread: 0.07,
    range: 13,
    mag: 40,
    reload: 2.8,
    kind: ShotKind.ball,
    ballSpeed: 14,
    splash: 0.6,
    moveMul: 0.88,
    custom: true,
    color: Color(0xFF9E9D24),
    shotColor: Color(0xFFFF7043),
    look: WeaponLook.rpgMini,
  ),
];

const List<Melee> kMelees = [
  Melee(
    id: 'fist',
    name: 'Fist',
    blurb: 'Punch! Free, quick and always ready.',
    price: 0,
    damage: 16,
    cooldown: 0.35,
    reach: 1.1,
    arc: 1.0,
    moveMul: 1.1,
    color: Color(0xFFFFCC80),
    look: WeaponLook.fist,
  ),
  Melee(
    id: 'knife',
    name: 'Knife',
    blurb: 'Fast stabs and you run faster.',
    price: 150,
    damage: 26,
    cooldown: 0.3,
    reach: 1.2,
    arc: 1.0,
    moveMul: 1.22,
    color: Color(0xFFCFD8DC),
    look: WeaponLook.knife,
  ),
  Melee(
    id: 'frying_pan',
    name: 'Frying Pan',
    blurb: 'BONK! Knocks people back.',
    price: 250,
    damage: 32,
    cooldown: 0.55,
    reach: 1.3,
    arc: 1.4,
    knockback: 1.0,
    moveMul: 1.1,
    color: Color(0xFF90A4AE),
    look: WeaponLook.pan,
  ),
  Melee(
    id: 'slapper_machine',
    name: 'Slapper Machine',
    blurb: 'A machine with a big hand that slaps super fast.',
    price: 400,
    damage: 10,
    cooldown: 0.12,
    reach: 1.5,
    arc: 1.4,
    knockback: 0.45,
    moveMul: 1.05,
    color: Color(0xFFFF8A65),
    look: WeaponLook.slapper,
  ),
  Melee(
    id: 'sizzler',
    name: 'Sizzler',
    blurb: 'A snake that bites from far away and hooks people over to you!',
    price: 550,
    damage: 34,
    cooldown: 0.55,
    reach: 2.4,
    arc: 0.9,
    hook: true,
    moveMul: 1.1,
    color: Color(0xFF66BB6A),
    look: WeaponLook.snake,
  ),
  Melee(
    id: 'scythe',
    name: 'Scythe',
    blurb: 'A giant sweep that hits wide and far.',
    price: 700,
    damage: 48,
    cooldown: 0.7,
    reach: 1.9,
    arc: 2.4,
    knockback: 0.6,
    moveMul: 1.12,
    color: Color(0xFFCE93D8),
    look: WeaponLook.scythe,
  ),
];

Gun gunById(String id) =>
    kGuns.firstWhere((g) => g.id == id, orElse: () => kGuns.first);
Melee meleeById(String id) =>
    kMelees.firstWhere((m) => m.id == id, orElse: () => kMelees.first);

const int kMaxLevel = 5;
const int kSecondSlotPrice = 400;

/// Each level adds 15% damage and fires 4% faster.
double levelDamageMul(int level) => 1 + 0.15 * (level - 1);
double levelSpeedMul(int level) => 1 - 0.04 * (level - 1);

int gunUpgradeCost(Gun g, int level) =>
    ((60 + g.price * 0.12) * level / 5).round() * 5;
int meleeUpgradeCost(Melee m, int level) =>
    ((50 + m.price * 0.12) * level / 5).round() * 5;

/// Coins, unlocks, upgrade levels and loadout, saved on the device.
// ---- Skins ---------------------------------------------------------------

enum Rarity { common, rare, epic, legendary }

const Map<Rarity, String> kRarityNames = {
  Rarity.common: 'Common',
  Rarity.rare: 'Rare',
  Rarity.epic: 'Epic',
  Rarity.legendary: 'Legendary',
};

const Map<Rarity, Color> kRarityColours = {
  Rarity.common: Color(0xFFB0BEC5),
  Rarity.rare: Color(0xFF42A5F5),
  Rarity.epic: Color(0xFFAB47BC),
  Rarity.legendary: Color(0xFFFFC93C),
};

/// Chance out of 100 of each rarity coming out of a skin box.
const Map<Rarity, int> kBoxOdds = {
  Rarity.common: 50,
  Rarity.rare: 30,
  Rarity.epic: 15,
  Rarity.legendary: 5,
};

const int kSkinBoxPrice = 150;

/// Coins you get back when a box gives you a skin you already have.
const int kDuplicateRefund = 50;

/// The pattern painted over a skin's colours.
enum SkinPattern { none, camo, neon, cracks, stars, shine }

/// A paint job for a weapon. Skins only change how it looks.
class Skin {
  final String id;
  final String name;
  final Rarity rarity;
  final int price;
  final Color metal;
  final Color grip;
  final Color? accent;
  final SkinPattern pattern;
  final List<Color> patternColours;

  const Skin({
    required this.id,
    required this.name,
    required this.rarity,
    required this.price,
    required this.metal,
    required this.grip,
    this.accent,
    this.pattern = SkinPattern.none,
    this.patternColours = const [],
  });
}

const List<Skin> kSkins = [
  Skin(
    id: 'camo',
    name: 'Camo',
    rarity: Rarity.common,
    price: 100,
    metal: Color(0xFF5B6B3A),
    grip: Color(0xFF4A5530),
    pattern: SkinPattern.camo,
    patternColours: [Color(0xFF34401F), Color(0xFF8A8550), Color(0xFF25261A)],
  ),
  Skin(
    id: 'arctic',
    name: 'Arctic',
    rarity: Rarity.common,
    price: 100,
    metal: Color(0xFFDDE6EC),
    grip: Color(0xFFC3D1DB),
    pattern: SkinPattern.camo,
    patternColours: [Color(0xFFFFFFFF), Color(0xFF9FB4C4), Color(0xFF7890A2)],
  ),
  Skin(
    id: 'crimson',
    name: 'Crimson',
    rarity: Rarity.rare,
    price: 250,
    metal: Color(0xFF9A1C1C),
    grip: Color(0xFF5E1010),
    accent: Color(0xFFFF8A80),
    pattern: SkinPattern.shine,
  ),
  Skin(
    id: 'neon',
    name: 'Neon',
    rarity: Rarity.rare,
    price: 250,
    metal: Color(0xFF1A1A22),
    grip: Color(0xFF101014),
    accent: Color(0xFF00E5FF),
    pattern: SkinPattern.neon,
    patternColours: [Color(0xFF00E5FF), Color(0xFFFF4081)],
  ),
  Skin(
    id: 'lava',
    name: 'Lava',
    rarity: Rarity.epic,
    price: 500,
    metal: Color(0xFF2B1B17),
    grip: Color(0xFF1E1310),
    accent: Color(0xFFFF6D00),
    pattern: SkinPattern.cracks,
    patternColours: [Color(0xFFFF6D00), Color(0xFFFFD180)],
  ),
  Skin(
    id: 'galaxy',
    name: 'Galaxy',
    rarity: Rarity.epic,
    price: 500,
    metal: Color(0xFF3A1C7A),
    grip: Color(0xFF1E0F40),
    accent: Color(0xFFB388FF),
    pattern: SkinPattern.stars,
    patternColours: [Color(0xFFFFFFFF), Color(0xFFB388FF), Color(0xFF80D8FF)],
  ),
  Skin(
    id: 'gold',
    name: 'Gold',
    rarity: Rarity.legendary,
    price: 1000,
    metal: Color(0xFFD4A017),
    grip: Color(0xFFA67C00),
    accent: Color(0xFFFFF59D),
    pattern: SkinPattern.shine,
  ),
  Skin(
    id: 'diamond',
    name: 'Diamond',
    rarity: Rarity.legendary,
    price: 1000,
    metal: Color(0xFF8FE3F5),
    grip: Color(0xFF4FB3CC),
    accent: Color(0xFFFFFFFF),
    pattern: SkinPattern.stars,
    patternColours: [Color(0xFFFFFFFF), Color(0xFFE0F7FA)],
  ),
];

Skin? skinById(String? id) {
  for (final s in kSkins) {
    if (s.id == id) return s;
  }
  return null;
}

/// Every weapon id (guns and melees), for skins.
List<String> get kWeaponIds => [
  for (final g in kGuns) g.id,
  for (final m in kMelees) m.id,
];

String weaponName(String id) {
  for (final g in kGuns) {
    if (g.id == id) return g.name;
  }
  return meleeById(id).name;
}

/// What a skin box gives you: a skin for one of the weapons.
({String weapon, Skin skin}) openSkinBox(Random rnd) {
  var roll = rnd.nextInt(100);
  var rarity = Rarity.common;
  for (final e in kBoxOdds.entries) {
    if (roll < e.value) {
      rarity = e.key;
      break;
    }
    roll -= e.value;
  }
  final pool = kSkins.where((s) => s.rarity == rarity).toList();
  final ids = kWeaponIds;
  return (
    weapon: ids[rnd.nextInt(ids.length)],
    skin: pool[rnd.nextInt(pool.length)],
  );
}

class OutplaySave {
  OutplaySave._();
  static final OutplaySave instance = OutplaySave._();

  SharedPreferences? _prefs;

  int coins = 150;
  Set<String> ownedGuns = {'assault_rifle'};
  Set<String> ownedMelees = {'fist'};
  Map<String, int> levels = {};
  bool secondSlot = false;
  String primary = 'assault_rifle';
  String? secondary;
  String melee = 'fist';
  int wins = 0;
  int losses = 0;
  String name = ''; // shown to other players online
  Avatar avatar = const Avatar();

  /// Skins you own, as 'weaponId:skinId'.
  Set<String> skins = {};

  /// The skin showing on each weapon (weaponId -> skinId).
  Map<String, String> equippedSkins = {};

  bool ownsSkin(String weapon, String skin) => skins.contains('$weapon:$skin');
  Skin? skinOn(String weapon) => skinById(equippedSkins[weapon]);

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString('outplay_save');
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      coins = m['coins'] as int? ?? coins;
      ownedGuns = {
        ...(m['guns'] as List? ?? []).cast<String>(),
        'assault_rifle',
      };
      ownedMelees = {...(m['melees'] as List? ?? []).cast<String>(), 'fist'};
      levels = (m['levels'] as Map? ?? {}).map(
        (k, v) => MapEntry(k as String, v as int),
      );
      secondSlot = m['slot2'] as bool? ?? false;
      primary = m['primary'] as String? ?? primary;
      secondary = m['secondary'] as String?;
      melee = m['melee'] as String? ?? melee;
      if (!ownedGuns.contains(primary)) primary = 'assault_rifle';
      if (secondary != null && !ownedGuns.contains(secondary)) secondary = null;
      if (!ownedMelees.contains(melee)) melee = 'fist';
      wins = m['wins'] as int? ?? 0;
      losses = m['losses'] as int? ?? 0;
      name = m['name'] as String? ?? '';
      avatar = Avatar.fromList(m['avatar']);
      skins = {...(m['skins'] as List? ?? []).cast<String>()};
      equippedSkins = (m['skinOn'] as Map? ?? {}).map(
        (k, v) => MapEntry(k as String, v as String),
      )..removeWhere((w, sk) => !skins.contains('$w:$sk'));
    } catch (_) {
      // A broken save starts fresh rather than crashing the game.
    }
  }

  Future<void> save() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(
      'outplay_save',
      jsonEncode({
        'coins': coins,
        'guns': ownedGuns.toList(),
        'melees': ownedMelees.toList(),
        'levels': levels,
        'slot2': secondSlot,
        'primary': primary,
        'secondary': secondary,
        'melee': melee,
        'wins': wins,
        'losses': losses,
        'name': name,
        'avatar': avatar.toList(),
        'skins': skins.toList(),
        'skinOn': equippedSkins,
      }),
    );
    await _prefs!.setInt('highscore_outplay', wins);
  }

  int levelOf(String id) => levels[id] ?? 1;
}
