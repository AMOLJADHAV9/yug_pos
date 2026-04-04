import 'package:flutter/material.dart';

class V2Colors {
  static const Color bg = Color(0xFF161616);
  static const Color s1 = Color(0xFF1E1E1E);
  static const Color s2 = Color(0xFF242424);
  static const Color s3 = Color(0xFF2C2C2C);
  static const Color yellow = Color(0xFFFFD600);
  static final Color yellowDark = Color(0xFFB39700).withOpacity(0.8);
  static const Color border = Color(0xFF2E2E2E);
  static const Color text = Color(0xFFF0F0F0);
  static const Color muted = Color(0xFF666666);
  static const Color red = Color(0xFFE53935);
  static const Color green = Color(0xFF43A047);
  static const Color blue = Color(0xFF1E88E5);
  static const Color orange = Color(0xFFFB8C00);
}

class V2Styles {
  static const TextStyle logo = TextStyle(
    color: V2Colors.yellow,
    fontWeight: FontWeight.w800,
    fontSize: 13,
    letterSpacing: 1,
  );

  static const TextStyle tpill = TextStyle(
    fontSize: 10,
    color: V2Colors.muted,
  );

  static const TextStyle colTitle = TextStyle(
    fontSize: 9,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
    color: V2Colors.muted,
  );

  static BoxDecoration cardDecoration = BoxDecoration(
    color: V2Colors.s2,
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: V2Colors.border),
  );

  static BoxDecoration selectedDecoration = BoxDecoration(
    color: V2Colors.s2,
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: V2Colors.yellow, width: 1.5),
  );
}
