enum VehicleType {
  boleroPickup('బొలెరో పికప్', 'Bolero pickup'),
  tataAce('టాటా ఏస్', 'Tata Ace'),
  dost('దోస్త్', 'Dost'),
  eicher14ft('ఐషర్ 14 అడుగులు', 'Eicher 14 ft'),
  tractor('ట్రాక్టర్', 'Tractor');

  const VehicleType(this.teluguName, this.englishName);
  final String teluguName;
  final String englishName;
  String get label => '$teluguName / $englishName';
}
