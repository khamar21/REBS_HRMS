import 'package:geolocator/geolocator.dart';

enum LocationFailure { servicesDisabled, denied, deniedForever, unavailable }

class LocationException implements Exception {
  final LocationFailure kind;
  const LocationException(this.kind);

  String get message {
    switch (kind) {
      case LocationFailure.servicesDisabled:
        return 'Location is turned off. Please enable GPS.';
      case LocationFailure.denied:
        return 'Location permission is needed to check in.';
      case LocationFailure.deniedForever:
        return 'Location permission is blocked. Enable it in app settings.';
      case LocationFailure.unavailable:
        return 'Could not get your location. Try again outdoors.';
    }
  }
}

class LocationService {
  Future<Position> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(LocationFailure.servicesDisabled);
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied) {
      throw const LocationException(LocationFailure.denied);
    }
    if (p == LocationPermission.deniedForever) {
      throw const LocationException(LocationFailure.deniedForever);
    }
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (_) {
      throw const LocationException(LocationFailure.unavailable);
    }
  }

  Future<void> openSettings() => Geolocator.openAppSettings();
}
