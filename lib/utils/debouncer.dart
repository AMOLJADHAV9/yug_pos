import 'dart:async';

/// A simple utility to prevent multiple rapid taps/actions.
class Debouncer {
  final int milliseconds;
  Timer? _timer;
  bool _isBusy = false;

  Debouncer({this.milliseconds = 500});

  /// Run an action only if the debouncer is not already busy.
  /// This is "Single Tap Prevention" — it ignores subsequent taps 
  /// until the delay has passed.
  void run(void Function() action) {
    if (_isBusy) return;

    _isBusy = true;
    action();

    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: milliseconds), () {
      _isBusy = false;
    });
  }

  void dispose() {
    _timer?.cancel();
  }
}
