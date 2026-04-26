import 'package:flutter/material.dart';

/// Global Navigator Key to prevent 'Empty history' assertion errors
/// by providing a stable reference to the root Navigator.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Safely pops the current route if and only if there's a route to pop,
/// ensuring the root history stack is never emptied.
void safePop<T>([BuildContext? context, T? result]) {
  try {
    // 1. Try popping from the provided context first (e.g. closing a dialog)
    if (context != null && context.mounted) {
      final NavigatorState? nav = Navigator.maybeOf(context);
      if (nav != null && nav.canPop()) {
        nav.pop(result);
        return;
      }
    }
    
    // 2. Fallback to root navigator if context-based pop failed or context was null
    final state = rootNavigatorKey.currentState;
    if (state != null && state.mounted && state.canPop()) {
      state.pop(result);
    }
  } catch (_) {
    // Silent fail to prevent crash during rapid navigation
  }
}
