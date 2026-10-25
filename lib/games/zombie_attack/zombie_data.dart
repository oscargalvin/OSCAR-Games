import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A gun you can buy and carry into a match.
class Gun {
  final String id;
  final String name;
  final String blurb;
  final int price;
  final double damage; // per bullet
  final double fireRate; // shots a second
  final int pellets; // bullets per shot
  final double spread; // radians across all pellets
  final double speed; // bullet speed, metres a second
  final double range; // metres before a bullet fades
  final bool pierce; // goes through zombies
  final double blast; // explosion radius (0 = none)
  final bool melee; // swung, not shot: hits everything in front of you
  final bool dropOnly; // not in the shop: only sword zombies drop it
  final Color colour;

  const Gun({
    required this.id,
    required this.name,
    required this.blurb,
    required this.price,
    required this.damage,
    required this.fireRate,
    this.pellets = 1,
    this.spread = 0.06,
    this.speed = 45,
    this.range = 18,
    this.pierce = false,
    this.blast = 0,
    this.melee = false,
    this.dropOnly = false,
    required this.colour,
  });
}

const List<Gun> kGuns = [
  Gun(
    id: 'pistol',
    name: 'Pistol',
    blurb: 'A trusty starter gun.',
    price: 0,
    damage: 1,
    fireRate: 4,
    colour: Color(0xFFFFE082),
  ),
  Gun(
    id: 'shotgun',
    name: 'Shotgun',
    blurb: 'Five pellets at once. Great up close.',
    price: 300,
    damage: 1,
    fireRate: 1.6,
    pellets: 5,
    spread: 0.5,
    range: 11,
    colour: Color(0xFFFFAB40),
  ),
  Gun(
    id: 'rifle',
    name: 'Rapid Rifle',
    blurb: 'Sprays bullets super fast.',
    price: 500,
    damage: 1,
    fireRate: 10,
    spread: 0.12,
    colour: Color(0xFF80D8FF),
  ),
  Gun(
    id: 'laser',
    name: 'Laser Gun',
    blurb: 'Zaps straight through a whole line of zombies.',
    price: 800,
    damage: 2,
    fireRate: 3,
    spread: 0,
    speed: 70,
    range: 24,
    pierce: true,
    colour: Color(0xFFFF4081),
  ),
  Gun(
    id: 'rocket',
    name: 'Rocket Launcher',
    blurb: 'Slow, but blows up a whole crowd.',
    price: 1200,
    damage: 6,
    fireRate: 0.9,
    spread: 0,
    speed: 26,
    range: 22,
    blast: 4,
    colour: Color(0xFFFF5252),
  ),
  Gun(
    id: 'sword',
    name: 'Zombie Sword',
    blurb: 'Dropped by sword zombies. Slices everything in front of you.',
    price: 0,
    damage: 3,
    fireRate: 2.4,
    spread: 0,
    range: 3.4,
    melee: true,
    dropOnly: true,
    colour: Color(0xFFCFD8DC),
  ),
];

/// The chance that a sword you pick up is yours to keep after the game.
const double kKeepSwordChance = 0.05;

Gun gunById(String id) =>
    kGuns.firstWhere((g) => g.id == id, orElse: () => kGuns.first);

/// Where the zombies attack.
enum ZombieMap {
  town(
    'Town',
    'Houses and parked cars to hide behind.',
    Color(0xFF6D8B5A),
    Color(0xFF8D6E63),
  ),
  graveyard(
    'Graveyard',
    'Gravestones everywhere, and it is getting dark.',
    Color(0xFF3E4F3A),
    Color(0xFF90A4AE),
  ),
  school(
    'School',
    'The playground at break time. Run!',
    Color(0xFF9E8F6E),
    Color(0xFFEF5350),
  ),
  farm(
    'Farm',
    'Barns and hay bales. Watch out in the fields!',
    Color(0xFF7C9A4E),
    Color(0xFFC62828),
  ),
  beach(
    'Beach',
    'Sand, palm trees and beach huts by the sea.',
    Color(0xFFE8D29A),
    Color(0xFF8D6E63),
  ),
  snow(
    'Snowy Forest',
    'Pine trees and snowmen. Brrr!',
    Color(0xFFE3EEF5),
    Color(0xFF2E7D32),
  );

  final String title;
  final String blurb;
  final Color ground;
  final Color block;
  const ZombieMap(this.title, this.blurb, this.ground, this.block);

  static ZombieMap byName(String? name) => ZombieMap.values.firstWhere(
    (m) => m.name == name,
    orElse: () => ZombieMap.town,
  );
}

const List<String> kZombieLevels = ['Easy', 'Normal', 'Hard'];

/// Coins for each wave you survive (more on harder levels).
const List<int> kWaveCoins = [10, 15, 25];

/// Your coins, guns and best wave, kept on this device.
class ZombieSave {
  ZombieSave._();
  static final ZombieSave instance = ZombieSave._();

  SharedPreferences? _prefs;

  int coins = 0;
  Set<String> guns = {'pistol'};
  String gun = 'pistol';
  int bestWave = 0;
  int kills = 0;

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString('zombie_attack_save');
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      coins = m['coins'] as int? ?? 0;
      guns = {...(m['guns'] as List? ?? []).cast<String>(), 'pistol'};
      gun = m['gun'] as String? ?? 'pistol';
      if (!guns.contains(gun)) gun = 'pistol';
      bestWave = m['bestWave'] as int? ?? 0;
      kills = m['kills'] as int? ?? 0;
    } catch (_) {
      // A broken save starts fresh.
    }
  }

  Future<void> save() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(
      'zombie_attack_save',
      jsonEncode({
        'coins': coins,
        'guns': guns.toList(),
        'gun': gun,
        'bestWave': bestWave,
        'kills': kills,
      }),
    );
  }
}
