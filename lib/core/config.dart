class Config {
  static const baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );
  static const scenario = String.fromEnvironment(
    'SCENARIO',
    defaultValue: 'success',
  );

  // Optional office override for simulating locations:
  // flutter run --dart-define=OFFICE_LAT=10.0159 --dart-define=OFFICE_LNG=76.3419
  static const _latRaw = String.fromEnvironment('OFFICE_LAT');
  static const _lngRaw = String.fromEnvironment('OFFICE_LNG');

  static double? get officeLat => double.tryParse(_latRaw);
  static double? get officeLng => double.tryParse(_lngRaw);
  static bool get hasOfficeOverride => officeLat != null && officeLng != null;
}
