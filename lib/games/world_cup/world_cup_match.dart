import 'dart:math';

/// Player actions during a live match.
enum MatchAction { pass, cross, shoot, freeKick, sprint, tackle }

enum MatchActionResult { none, homeGoal, awayGoal }

/// Interactive 2-minute match — Pass → Cross → Shoot, Tackle, Sprint & fuel.
class WorldCupLiveMatch {
  double buildup = 25;
  double fuel = 100;
  int sprintTicks = 0;
  int tackleCooldown = 0;
  bool freeKickActive = false;
  bool crossReady = false;
  String feedback = 'Pass to build up · Tackle to win the ball';
  int feedbackTicks = 0;

  void reset() {
    buildup = 25;
    fuel = 100;
    sprintTicks = 0;
    tackleCooldown = 0;
    freeKickActive = false;
    crossReady = false;
    feedback = 'Pass to build up · Tackle to win the ball';
    feedbackTicks = 0;
  }

  void _say(String msg) {
    feedback = msg;
    feedbackTicks = 4;
  }

  void tickFeedback() {
    if (feedbackTicks > 0) feedbackTicks--;
  }

  MatchActionResult handle(
    MatchAction action, {
    required Random rng,
    required bool userIsHome,
    required double userStrength,
    required double oppStrength,
    double pickBoost = 0,
  }) {
    final strength = userStrength + pickBoost;
    switch (action) {
      case MatchAction.pass:
        return _pass(strength, oppStrength);
      case MatchAction.cross:
        return _cross(strength);
      case MatchAction.shoot:
        return _shoot(
          rng: rng,
          userIsHome: userIsHome,
          userStrength: strength,
          oppStrength: oppStrength,
        );
      case MatchAction.freeKick:
        return _freeKick(rng: rng, userIsHome: userIsHome, userStrength: strength);
      case MatchAction.sprint:
        return _sprint();
      case MatchAction.tackle:
        return _tackle(rng: rng, userStrength: strength, oppStrength: oppStrength);
    }
  }

  MatchActionResult tickSecond({
    required Random rng,
    required bool userIsHome,
    required double userStrength,
    required double oppStrength,
    double pickBoost = 0,
  }) {
    tickFeedback();
    if (sprintTicks > 0) sprintTicks--;
    if (tackleCooldown > 0) tackleCooldown--;

    fuel = (fuel + 2.5).clamp(0, 100);

    final strength = userStrength + pickBoost;
    final sprintGuard = sprintTicks > 0 ? 0.65 : 1.0;
    final oppChance =
        (oppStrength / (strength + oppStrength)) * 0.038 * sprintGuard;
    if (rng.nextDouble() < oppChance) {
      _say('They hit on the counter!');
      return userIsHome ? MatchActionResult.awayGoal : MatchActionResult.homeGoal;
    }

    if (!freeKickActive && rng.nextDouble() < 0.07) {
      freeKickActive = true;
      _say('Free kick! Tap Free Kick');
    }

    buildup = (buildup - 1.5).clamp(0, 100);
    if (crossReady && buildup < 30) crossReady = false;
    return MatchActionResult.none;
  }

  MatchActionResult _pass(double userStrength, double oppStrength) {
    final gain = 20 + (sprintTicks > 0 ? 12 : 0) + (userStrength / oppStrength) * 5;
    buildup = (buildup + gain).clamp(0, 100);
    fuel = (fuel - 4).clamp(0, 100);
    _say('Pass · Build ${buildup.round()}%');
    return MatchActionResult.none;
  }

  MatchActionResult _cross(double userStrength) {
    if (buildup < 15) {
      _say('Pass more before you cross');
      return MatchActionResult.none;
    }
    crossReady = true;
    buildup = (buildup + 12).clamp(0, 100);
    fuel = (fuel - 8).clamp(0, 100);
    _say('Cross in the box — Shoot!');
    return MatchActionResult.none;
  }

  MatchActionResult _shoot({
    required Random rng,
    required bool userIsHome,
    required double userStrength,
    required double oppStrength,
  }) {
    if (freeKickActive) {
      return _freeKick(rng: rng, userIsHome: userIsHome, userStrength: userStrength);
    }
    final need = crossReady ? 18.0 : 28.0;
    if (buildup < need) {
      _say('Build up with Pass first');
      return MatchActionResult.none;
    }
    final mult = (crossReady ? 1.4 : 1.0) * (sprintTicks > 0 ? 1.25 : 1.0);
    final chance =
        ((userStrength / (userStrength + oppStrength)) * 0.52 * mult).clamp(0.06, 0.72);
    crossReady = false;
    buildup *= 0.45;
    fuel = (fuel - 12).clamp(0, 100);
    if (rng.nextDouble() < chance) {
      _say('GOOOAL!');
      return userIsHome ? MatchActionResult.homeGoal : MatchActionResult.awayGoal;
    }
    _say('Off target!');
    return MatchActionResult.none;
  }

  void onDribble(double forward) {
    if (forward <= 0.05) return;
    buildup = (buildup + forward * 3.5).clamp(0, 100);
    fuel = (fuel - 0.4).clamp(0, 100);
    if (sprintTicks > 0) buildup = (buildup + 1.5).clamp(0, 100);
    if (feedbackTicks == 0) _say('Dribbling · ${buildup.round()}%');
  }

  MatchActionResult _freeKick({
    required Random rng,
    required bool userIsHome,
    required double userStrength,
  }) {
    if (!freeKickActive) {
      _say('No free kick right now');
      return MatchActionResult.none;
    }
    freeKickActive = false;
    final chance = (0.38 + userStrength / 220).clamp(0.15, 0.68);
    fuel = (fuel - 10).clamp(0, 100);
    if (rng.nextDouble() < chance) {
      _say('Free kick goal!');
      return userIsHome ? MatchActionResult.homeGoal : MatchActionResult.awayGoal;
    }
    _say('Free kick saved');
    return MatchActionResult.none;
  }

  MatchActionResult _sprint() {
    if (fuel < 15) {
      _say('Need more fuel to sprint');
      return MatchActionResult.none;
    }
    sprintTicks = 10;
    buildup = (buildup + 8).clamp(0, 100);
    fuel = (fuel - 18).clamp(0, 100);
    _say('Sprint! Attack boost');
    return MatchActionResult.none;
  }

  MatchActionResult _tackle({
    required Random rng,
    required double userStrength,
    required double oppStrength,
  }) {
    if (tackleCooldown > 0) {
      _say('Tackle cooling down…');
      return MatchActionResult.none;
    }
    if (fuel < 12) {
      _say('Need fuel to tackle');
      return MatchActionResult.none;
    }
    tackleCooldown = 4;
    fuel = (fuel - 14).clamp(0, 100);
    final winChance =
        (userStrength / (userStrength + oppStrength) * 0.72).clamp(0.25, 0.85);
    if (rng.nextDouble() < winChance) {
      buildup = (buildup + 22).clamp(0, 100);
      _say('Tackle won — push forward!');
    } else {
      buildup = (buildup * 0.6).clamp(0, 100);
      _say('Tackle missed');
    }
    return MatchActionResult.none;
  }
}
