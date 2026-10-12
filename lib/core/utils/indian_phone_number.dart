abstract final class IndianPhoneNumber {
  static String normalize(String phone) {
    var value = phone.replaceAll(RegExp(r'[\s()-]'), '');
    if (value.startsWith('+91')) {
      value = value.substring(3);
    } else if (value.length == 12 && value.startsWith('91')) {
      value = value.substring(2);
    }
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(value)) {
      throw const FormatException('Enter a valid 10-digit mobile number');
    }
    return '+91$value';
  }
}
