class UserProfile {
  const UserProfile({
    required this.phone,
    required this.role,
    this.name = '',
    this.villageId,
  });
  final String phone;
  final String role;
  final String name;
  final String? villageId;
  Map<String, dynamic> toJson() => {
    'phone': phone,
    'role': role,
    'name': name,
    'village_id': villageId,
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
    );
  }
}
