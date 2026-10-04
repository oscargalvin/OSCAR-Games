import 'dart:convert';

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
  fist,
  knife,
  pan,
  slapper,
  scythe,
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

  const Melee({
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
      }),
    );
    await _prefs!.setInt('highscore_outplay', wins);
  }

  int levelOf(String id) => levels[id] ?? 1;
}
