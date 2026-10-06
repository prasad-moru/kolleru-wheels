class Village {
  const Village({
    required this.id,
    required this.name,
    required this.teluguName,
  });
  final String id;
  final String name;
  final String teluguName;
  String get label => '$teluguName / $name';
}

class Mandal {
  const Mandal({
    required this.id,
    required this.name,
    required this.teluguName,
    required this.villages,
  });
  final String id;
  final String name;
  final String teluguName;
  final List<Village> villages;
}

abstract final class KolleruVillages {
  // Supplied directory clusters; border hamlets are a catch-all locality.
  static const mandals = <Mandal>[
    Mandal(
      id: 'kaikaluru',
      name: 'Kaikaluru',
      teluguName: 'కైకలూరు',
      villages: [
        Village(
          id: 'kaikaluru-town',
          name: 'Kaikaluru Town',
          teluguName: 'కైకలూరు పట్టణం',
        ),
        Village(
          id: 'kovvadalanka',
          name: 'Kovvadalanka',
          teluguName: 'కొవ్వాడలంక',
        ),
        Village(
          id: 'gudivakalanka',
          name: 'Gudivakalanka',
          teluguName: 'గుడివాకలంక',
        ),
        Village(id: 'atapaka', name: 'Atapaka', teluguName: 'ఆటపాక'),
        Village(
          id: 'bhujabalapatnam',
          name: 'Bhujabalapatnam',
          teluguName: 'భుజబలపట్నం',
        ),
        Village(id: 'pallevada', name: 'Pallevada', teluguName: 'పల్లెవాడ'),
        Village(
          id: 'kolletikota',
          name: 'Kolletikota',
          teluguName: 'కొల్లేటికోట',
        ),
        Village(id: 'alapadu', name: 'Alapadu', teluguName: 'ఆలపాడు'),
        Village(
          id: 'singarayapalem',
          name: 'Singarayapalem',
          teluguName: 'సింగరాయపాలెం',
        ),
      ],
    ),
    Mandal(
      id: 'mandavalli',
      name: 'Mandavalli',
      teluguName: 'మండవల్లి',
      villages: [
        Village(id: 'mandavalli', name: 'Mandavalli', teluguName: 'మండవల్లి'),
        Village(id: 'chintapadu', name: 'Chintapadu', teluguName: 'చింతపాడు'),
        Village(id: 'pulaparru', name: 'Pulaparru', teluguName: 'పులపర్రు'),
        Village(
          id: 'penumakalanka',
          name: 'Penumakalanka',
          teluguName: 'పెనుమాకలంక',
        ),
        Village(
          id: 'prathikollalanka',
          name: 'Prathikollalanka',
          teluguName: 'ప్రతికోళ్ళలంక',
        ),
        Village(id: 'lokamudi', name: 'Lokamudi', teluguName: 'లోకమూడి'),
        Village(
          id: 'ingilipakalanka',
          name: 'Ingilipakalanka',
          teluguName: 'ఇంగిలిపాకలంక',
        ),
      ],
    ),
    Mandal(
      id: 'kalidindi',
      name: 'Kalidindi',
      teluguName: 'కాళిదిండి',
      villages: [
        Village(id: 'kalidindi', name: 'Kalidindi', teluguName: 'కాళిదిండి'),
        Village(
          id: 'sanrudraram',
          name: 'Sanrudraram',
          teluguName: 'సానరుద్రవరం',
        ),
        Village(id: 'guraja', name: 'Guraja', teluguName: 'గురజ'),
        Village(id: 'korukollu', name: 'Korukollu', teluguName: 'కొరుకొల్లు'),
        Village(id: 'pothumarru', name: 'Pothumarru', teluguName: 'పోతుమర్రు'),
      ],
    ),
    Mandal(
      id: 'akividu',
      name: 'Akividu',
      teluguName: 'ఆకివీడు',
      villages: [
        Village(
          id: 'akividu-town',
          name: 'Akividu Town',
          teluguName: 'ఆకివీడు పట్టణం',
        ),
        Village(id: 'dumpagadapa', name: 'Dumpagadapa', teluguName: 'దుంపగడప'),
        Village(id: 'taratava', name: 'Taratava', teluguName: 'తరటావ'),
        Village(id: 'ajjamuru', name: 'Ajjamuru', teluguName: 'అజ్జమూరు'),
        Village(
          id: 'kolleru-border',
          name: 'Kolleru border hamlets',
          teluguName: 'కొల్లేరు సరిహద్దు పల్లెలు',
        ),
      ],
    ),
  ];
  static List<Village> get all =>
      List.unmodifiable(mandals.expand((m) => m.villages));
  static Village? find(String? id) {
    for (final village in all) {
      if (village.id == id) return village;
    }
    return null;
  }
}
