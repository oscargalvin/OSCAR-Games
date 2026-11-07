import 'package:flutter/material.dart';

class GameInfo {
  final String id;
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color color;
  final Color secondaryColor;
  final Widget Function() screenBuilder;
  final int minPlayers;
  final int maxPlayers;
  final String difficulty;

  /// What kind of game it is, shown on the home card (Comedy, Survival...).
  final String genre;

  const GameInfo({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.color,
    required this.secondaryColor,
    required this.screenBuilder,
    this.minPlayers = 1,
    this.maxPlayers = 1,
    this.difficulty = 'Easy',
    this.genre = '',
  });
}
