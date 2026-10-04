import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How a weapon looks in the shop and in the arena.
enum WeaponLook {
  rifle,
  pistol,
  smg,
  shotgun,
  revolver,
  burst,
  sniper,
  flamer,
  minigun,
  rocket,
  fist,
  knife,
  scythe,
}

class Gun {
  final String id;
  final String name;
  final String blurb;
  final int price;
  final double damage;
  final double fireInterval; // seconds between shots (or bursts)
  final int pellets;
  final double spread; // radians either side
  final double bulletSpeed;
  final double range;
  final int mag;
  final double reload;
  final int burst; // bullets per trigger pull
  final double moveMul; // walking speed while holding it
  final double splash; // explosion radius (rockets)
  final Color color;
  final WeaponLook look;

  const Gun({
    required this.id,
    required this.name,
    required this.blurb,
    required this.price,
    required this.damage,
    required this.fireInterval,
    this.pellets = 1,
    this.spread = 0.04,
    this.bulletSpeed = 950,
    this.range = 650,
    required this.mag,
    required this.reload,
    this.burst = 1,
    this.moveMul = 1,
    this.splash = 0,
    required this.color,
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
  final double reach;
  final double arc; // full swing angle in radians
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
    mag: 30,
    reload: 1.6,
    color: Color(0xFF7FB3FF),
    look: WeaponLook.rifle,
  ),
  Gun(
    id: 'handgun',
    name: 'Handgun',
    blurb: 'Light and quick. Great as a backup.',
    price: 100,
    damage: 19,
    fireInterval: 0.24,
    mag: 12,
    reload: 1.1,
    moveMul: 1.08,
    color: Color(0xFFB0BEC5),
    look: WeaponLook.pistol,
  ),
  Gun(
    id: 'smg',
    name: 'SMG',
    blurb: 'Sprays bullets super fast up close.',
    price: 250,
    damage: 8,
    fireInterval: 0.065,
    spread: 0.1,
    range: 480,
    mag: 35,
    reload: 1.4,
    moveMul: 1.06,
    color: Color(0xFF9CCC65),
    look: WeaponLook.smg,
  ),
  Gun(
    id: 'shotgun',
    name: 'Shotgun',
    blurb: 'Seven pellets. Huge damage up close.',
    price: 300,
    damage: 9,
    fireInterval: 0.8,
    pellets: 7,
    spread: 0.32,
    range: 330,
    bulletSpeed: 820,
    mag: 6,
    reload: 2.0,
    color: Color(0xFFFFB74D),
    look: WeaponLook.shotgun,
  ),
  Gun(
    id: 'revolver',
    name: 'Revolver',
    blurb: 'Six big shots. Make them count.',
    price: 350,
    damage: 38,
    fireInterval: 0.45,
    spread: 0.02,
    mag: 6,
    reload: 1.8,
    color: Color(0xFFE0C097),
    look: WeaponLook.revolver,
  ),
  Gun(
    id: 'burst_rifle',
    name: 'Burst Rifle',
    blurb: 'Fires three bullets at once.',
    price: 450,
    damage: 14,
    fireInterval: 0.5,
    burst: 3,
    spread: 0.03,
    mag: 24,
    reload: 1.7,
    color: Color(0xFF4DD0E1),
    look: WeaponLook.burst,
  ),
  Gun(
    id: 'sniper',
    name: 'Sniper',
    blurb: 'One huge hit from across the map.',
    price: 600,
    damage: 75,
    fireInterval: 1.3,
    spread: 0,
    bulletSpeed: 1900,
    range: 1200,
    mag: 4,
    reload: 2.2,
    moveMul: 0.9,
    color: Color(0xFF81C784),
    look: WeaponLook.sniper,
  ),
  Gun(
    id: 'flamethrower',
    name: 'Flamethrower',
    blurb: 'Short range fire that never stops.',
    price: 700,
    damage: 3.2,
    fireInterval: 0.05,
    pellets: 2,
    spread: 0.22,
    bulletSpeed: 520,
    range: 230,
    mag: 80,
    reload: 2.2,
    color: Color(0xFFFF7043),
    look: WeaponLook.flamer,
  ),
  Gun(
    id: 'minigun',
    name: 'Minigun',
    blurb: 'Endless bullets, but you walk slowly.',
    price: 900,
    damage: 7,
    fireInterval: 0.045,
    spread: 0.12,
    mag: 120,
    reload: 3.0,
    moveMul: 0.65,
    color: Color(0xFFB39DDB),
    look: WeaponLook.minigun,
  ),
  Gun(
    id: 'rocket_launcher',
    name: 'Rocket Launcher',
    blurb: 'Boom! Splash damage hits around corners.',
    price: 1200,
    damage: 55,
    fireInterval: 1.4,
    spread: 0,
    bulletSpeed: 560,
    range: 900,
    mag: 1,
    reload: 1.6,
    moveMul: 0.85,
    splash: 75,
    color: Color(0xFFEF5350),
    look: WeaponLook.rocket,
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
    reach: 34,
    arc: 1.2,
    moveMul: 1.1,
    color: Color(0xFFFFCC80),
    look: WeaponLook.fist,
  ),
  Melee(
    id: 'knife',
    name: 'Knife',
    blurb: 'Fast stabs and you run faster.',
    price: 200,
    damage: 26,
    cooldown: 0.3,
    reach: 40,
    arc: 1.1,
    moveMul: 1.2,
    color: Color(0xFFCFD8DC),
    look: WeaponLook.knife,
  ),
  Melee(
    id: 'scythe',
    name: 'Scythe',
    blurb: 'A giant sweep that hits wide.',
    price: 800,
    damage: 48,
    cooldown: 0.7,
    reach: 66,
    arc: 2.6,
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
      wins = m['wins'] as int? ?? 0;
      losses = m['losses'] as int? ?? 0;
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
      }),
    );
    await _prefs!.setInt('highscore_outplay', wins);
  }

  int levelOf(String id) => levels[id] ?? 1;
}
