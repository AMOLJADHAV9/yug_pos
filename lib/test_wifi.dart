import 'package:wifi_iot/wifi_iot.dart';

void main() {
  WifiNetwork nw = WifiNetwork();
  nw.ssid = "Test";
  nw.level = -50;
  print("Success");
}
