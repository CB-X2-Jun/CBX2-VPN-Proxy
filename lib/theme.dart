import 'package:flutter/material.dart';

const _primary = Color(0xFF6C5CE7); // 浅紫色
const _primaryLight = Color(0xFFA29BFE);
const _background = Color(0xFFF8F7FF);
const _surface = Colors.white;

final appTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: _primary,
    brightness: Brightness.light,
    primary: _primary,
    secondary: _primaryLight,
    surface: _surface,
    background: _background,
  ),
  scaffoldBackgroundColor: _background,
  appBarTheme: const AppBarTheme(
    backgroundColor: _surface,
    foregroundColor: _primary,
    elevation: 0,
    centerTitle: false,
  ),
  cardTheme: CardThemeData(
    color: _surface,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: _primary.withOpacity(0.12)),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: _primary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    ),
  ),
);
