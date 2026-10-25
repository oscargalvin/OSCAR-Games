import 'dart:math';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How a car is drawn.
enum CarBody {
  sport,
  truck,
  hornet,
  goatKart,
  monster,
  hatchback,
  saloon,
  suv,
  van,
  estate,
  rally,
  police,
  hyper,
}

/// A car you can drive. Faster cars turn worse; heavy cars hit harder.
class CarSpec {
  final String id;
  final String name;
  final String blurb;
  final CarBody body;
  final int price;
  final double speed; // top speed without boost
  final double accel;
  final double turn; // radians per second
  final double hit; // how hard it smacks the ball
  final double jump; // jump speed
  final double weight; // for bumping other cars

  const CarSpec({
    required this.id,
    required this.name,
    required this.blurb,
    required this.body,
    required this.price,
    required this.speed,
    required this.accel,
    required this.turn,
    required this.hit,
    required this.jump,
    required this.weight,
  });
}

const List<CarSpec> kCars = [
  CarSpec(
    id: 'zoomer',
    name: 'Zoomer',
    blurb: 'A sporty all-rounder.',
    body: CarBody.sport,
    price: 0,
    speed: 22,
    accel: 30,
    turn: 4.2,
    hit: 1,
    jump: 12,
    weight: 1,
  ),
  CarSpec(
    id: 'hornet',
    name: 'Hornet',
    blurb: 'Super fast and twisty, but light.',
    body: CarBody.hornet,
    price: 250,
    speed: 25,
    accel: 34,
    turn: 4.8,
    hit: 0.9,
    jump: 12,
    weight: 0.8,
  ),
  CarSpec(
    id: 'bulldog',
    name: 'Bulldog Truck',
    blurb: 'Slow, but smashes the ball miles.',
    body: CarBody.truck,
    price: 300,
    speed: 20,
    accel: 26,
    turn: 3.6,
    hit: 1.35,
    jump: 11,
    weight: 1.5,
  ),
  CarSpec(
    id: 'goat_kart',
    name: 'Goat Kart',
    blurb: 'Driven by a goat. Jumps really high!',
    body: CarBody.goatKart,
    price: 350,
    speed: 21,
    accel: 32,
    turn: 4.6,
    hit: 1,
    jump: 15,
    weight: 0.9,
  ),
  CarSpec(
    id: 'monster',
    name: 'Monster Truck',
    blurb: 'Giant wheels. Bumps cars out of the way.',
    body: CarBody.monster,
    price: 500,
    speed: 23,
    accel: 30,
    turn: 4,
    hit: 1.25,
    jump: 13,
    weight: 1.8,
  ),
  // Everyday cars, like the ones on your street.
  CarSpec(
    id: 'hatch',
    name: 'Family Hatch',
    blurb: 'A normal little car. Easy to drive.',
    body: CarBody.hatchback,
    price: 200,
    speed: 21,
    accel: 31,
    turn: 4.5,
    hit: 0.95,
    jump: 12,
    weight: 0.95,
  ),
  CarSpec(
    id: 'saloon',
    name: 'City Saloon',
    blurb: 'A smooth, steady everyday car.',
    body: CarBody.saloon,
    price: 250,
    speed: 23,
    accel: 30,
    turn: 4.1,
    hit: 1,
    jump: 12,
    weight: 1.05,
  ),
  CarSpec(
    id: 'estate',
    name: 'Estate Car',
    blurb: 'Long and roomy, with a big flat back.',
    body: CarBody.estate,
    price: 300,
    speed: 22,
    accel: 29,
    turn: 4,
    hit: 1.1,
    jump: 12,
    weight: 1.15,
  ),
  CarSpec(
    id: 'suv',
    name: 'Big SUV',
    blurb: 'Tall and tough. Good for bumping.',
    body: CarBody.suv,
    price: 350,
    speed: 21,
    accel: 28,
    turn: 3.8,
    hit: 1.2,
    jump: 13,
    weight: 1.4,
  ),
  CarSpec(
    id: 'van',
    name: 'Delivery Van',
    blurb: 'A big box on wheels. Hits like a wall.',
    body: CarBody.van,
    price: 400,
    speed: 20,
    accel: 27,
    turn: 3.6,
    hit: 1.3,
    jump: 11,
    weight: 1.6,
  ),
  CarSpec(
    id: 'rally',
    name: 'Rally Car',
    blurb: 'Built for mud and jumps. Grippy and quick.',
    body: CarBody.rally,
    price: 600,
    speed: 23,
    accel: 34,
    turn: 4.7,
    hit: 1.05,
    jump: 14,
    weight: 1,
  ),
  CarSpec(
    id: 'police',
    name: 'Police Car',
    blurb: 'Flashing lights and a push bar for bumping.',
    body: CarBody.police,
    price: 800,
    speed: 24,
    accel: 32,
    turn: 4.3,
    hit: 1.2,
    jump: 12,
    weight: 1.3,
  ),
  CarSpec(
    id: 'hyper',
    name: 'Golden Hypercar',
    blurb: 'The best car in the game. Fast, strong, covered in gold.',
    body: CarBody.hyper,
    price: 12000,
    speed: 26,
    accel: 37,
    turn: 4.7,
    hit: 1.3,
    jump: 14,
    weight: 1.35,
  ),
];

/// Cars too special for the VIP pass to give away.
bool vipCanGive(CarSpec c) => c.price <= 1000;

CarSpec carById(String id) =>
    kCars.firstWhere((c) => c.id == id, orElse: () => kCars.first);

/// Paint colours for your car (free to switch).
const List<Color> kCarColours = [
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFF8E24AA),
  Color(0xFFFFD600),
  Color(0xFF00ACC1),
  Color(0xFFEC407A),
  Color(0xFF212121),
  Color(0xFFFFFFFF),
];

/// The VIP pass: coins for 7 random cars you don't have yet.
const int kVipPrice = 1000;
const int kVipCars = 7;

/// Coins for winning a match, by how hard the bots were.
const List<int> kWinCoins = [25, 40, 60, 100];

const List<String> kDifficultyNames = ['Easy', 'Medium', 'Hard', 'Extreme'];

/// The different ways to play a match.
enum BoostMode {
  classic('Classic', 'Most goals when the clock runs out wins.'),
  suddenDeath('Sudden Death', 'No clock. The first goal wins the match.'),
  firstTo5('First to 5', 'No clock. First team to score 5 goals wins.'),
  noBoost('No Boost', 'A normal match, but nobody gets any boost.'),
  winnerWall(
    'Winner Wall',
    'The goals are high up on the end walls. Climb the wall to score!',
  ),
  freePlay('Free Play', 'Just you and the ball. Practise your shots!');

  final String title;
  final String blurb;
  const BoostMode(this.title, this.blurb);

  /// Modes with a match clock (the others end on goals).
  bool get timed => this == classic || this == noBoost || this == winnerWall;

  static BoostMode byName(String? name) => BoostMode.values.firstWhere(
    (m) => m.name == name,
    orElse: () => BoostMode.classic,
  );
}

/// 12000 -> "12,000".
String commas(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// What a quest counts.
enum QuestStat {
  matches,
  wins,
  goals,
  wallGoals,
  demos,
  fastShot, // your hardest shot, not a running total
  suddenDeathWins,
  extremeWins,
}

/// Something to do for bonus coins. Each quest pays out once.
class Quest {
  final String id;
  final String title;
  final QuestStat stat;
  final int target;
  final int reward;
  const Quest(this.id, this.title, this.stat, this.target, this.reward);
}

const List<Quest> kQuests = [
  Quest('wall7', 'Score 7 goals in Winner Wall', QuestStat.wallGoals, 7, 500),
  Quest('goals20', 'Score 20 goals in any game', QuestStat.goals, 20, 250),
  Quest('play5', 'Play 5 matches', QuestStat.matches, 5, 100),
  Quest('win3', 'Win 3 matches', QuestStat.wins, 3, 150),
  Quest('fast', 'Hit the ball at 130 KPH', QuestStat.fastShot, 130, 150),
  Quest('demo5', 'Demolish 5 cars', QuestStat.demos, 5, 200),
  Quest(
    'sudden',
    'Win a Sudden Death match',
    QuestStat.suddenDeathWins,
    1,
    150,
  ),
  Quest('extreme', 'Beat the Extreme bots', QuestStat.extremeWins, 1, 600),
];

/// Turns the ball's speed (metres a second) into kilometres an hour.
int kph(double metresPerSecond) => (metresPerSecond * 3.6).round();

/// Your coins, cars and paint, kept on this device.
class BoostBallSave {
  BoostBallSave._();
  static final BoostBallSave instance = BoostBallSave._();

  SharedPreferences? _prefs;

  int coins = 0;
  Set<String> cars = {'zoomer'};
  String car = 'zoomer';
  int colour = 0;
  int wins = 0;
  int losses = 0;
  int goals = 0;
  int bestKph = 0; // your hardest ever shot
  String name = ''; // shown to other people online
  bool vip = false; // bought the VIP pass
  bool ballCam = true; // the camera you picked last (ball cam or car cam)
  Map<String, int> quest = {}; // quest counters, by QuestStat name
  Set<String> claimed = {}; // quests already paid out

  int questCount(Quest q) => min(q.target, quest[q.stat.name] ?? 0);
  bool questDone(Quest q) => questCount(q) >= q.target;

  /// Counts a finished match towards the quests. Returns the quests it
  /// just completed.
  List<Quest> recordMatch({
    required bool won,
    required int goals,
    required int demos,
    required int topKph,
    required BoostMode mode,
    required bool extreme,
  }) {
    final before = {
      for (final q in kQuests)
        if (questDone(q)) q.id,
    };
    void add(QuestStat s, int n) => quest[s.name] = (quest[s.name] ?? 0) + n;
    add(QuestStat.matches, 1);
    add(QuestStat.goals, goals);
    add(QuestStat.demos, demos);
    if (mode == BoostMode.winnerWall) add(QuestStat.wallGoals, goals);
    if (won) add(QuestStat.wins, 1);
    if (won && mode == BoostMode.suddenDeath) add(QuestStat.suddenDeathWins, 1);
    if (won && extreme) add(QuestStat.extremeWins, 1);
    final fast = QuestStat.fastShot.name;
    quest[fast] = max(quest[fast] ?? 0, topKph);
    return [
      for (final q in kQuests)
        if (questDone(q) && !before.contains(q.id)) q,
    ];
  }

  /// Pays out a finished quest.
  bool claim(Quest q) {
    if (!questDone(q) || claimed.contains(q.id)) return false;
    claimed.add(q.id);
    coins += q.reward;
    return true;
  }

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString('boost_ball_save');
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      coins = m['coins'] as int? ?? 0;
      cars = {...(m['cars'] as List? ?? []).cast<String>(), 'zoomer'};
      car = m['car'] as String? ?? 'zoomer';
      if (!cars.contains(car)) car = 'zoomer';
      colour = ((m['colour'] as int?) ?? 0).clamp(0, kCarColours.length - 1);
      wins = m['wins'] as int? ?? 0;
      losses = m['losses'] as int? ?? 0;
      goals = m['goals'] as int? ?? 0;
      bestKph = m['bestKph'] as int? ?? 0;
      name = m['name'] as String? ?? '';
      vip = m['vip'] == true;
      ballCam = m['ballCam'] as bool? ?? true;
      quest = {
        for (final e in ((m['quest'] as Map?) ?? {}).entries)
          '${e.key}': (e.value as num).toInt(),
      };
      claimed = {...(m['claimed'] as List? ?? []).cast<String>()};
    } catch (_) {
      // A broken save starts fresh.
    }
  }

  Future<void> save() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(
      'boost_ball_save',
      jsonEncode({
        'coins': coins,
        'cars': cars.toList(),
        'car': car,
        'colour': colour,
        'wins': wins,
        'losses': losses,
        'goals': goals,
        'bestKph': bestKph,
        'name': name,
        'vip': vip,
        'ballCam': ballCam,
        'quest': quest,
        'claimed': claimed.toList(),
      }),
    );
  }
}
