import 'package:flutter/material.dart';

/// Global Navigator Key to prevent 'Empty history' assertion errors
/// by providing a stable reference to the root Navigator.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Safely pops the current route if and only if there's a route to pop,
/// ensuring the root history stack is never emptied.
void safePop([BuildContext? context]) {
  try {
    if (context != null) {
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop();
        return;
      }
    }
    
    final state = rootNavigatorKey.currentState;
    if (state != null && state.canPop()) {
      state.pop();
    }
  } catch (e) {
    debugPrint("SafePop Error: $e");
  }
}
