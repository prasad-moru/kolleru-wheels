/// Operations approval is separate from phone verification and availability.
enum DriverVerification {
  pending,
  approved,
  rejected;

  static DriverVerification fromValue(Object? value) => value == null
      ? approved // Existing installations retain their previously listed fleet.
      : values.firstWhere((item) => item.name == value, orElse: () => pending);
}
