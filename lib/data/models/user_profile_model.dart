class UserProfile {
  const UserProfile({
    required this.phone,
    required this.role,
    this.name = '',
    this.villageId,
    this.baseLocation,
  });
  final String phone;
  final String role;
  final String name;
  final String? villageId;
  final String? baseLocation;
  Map<String, dynamic> toJson() => {
    'phone': phone,
    'role': role,
    'name': name,
    'village_id': villageId,
    'base_location': baseLocation,
  };
  factory UserProfile.fromJson(Map<String, dynamic> row) {
    final role = row['role'] as String;
    if (!['driver', 'shipper', 'admin'].contains(role)) {
      throw const FormatException('Unknown role');
    }
    return UserProfile(
      phone: row['phone'] as String,
      role: role,
      name: row['name'] as String? ?? '',
      villageId: row['village_id'] as String?,
      baseLocation: row['base_location'] as String?,
    );
  }
}
