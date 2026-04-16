class ApiKeys {
  /// DO NOT HARDCODE SECRETS.
  /// Use: flutter run --dart-define=GOOGLE_CLOUD_KEY='{your_json_here}'
  static const String googleCloudServiceAccount = String.fromEnvironment('GOOGLE_CLOUD_KEY');
}
