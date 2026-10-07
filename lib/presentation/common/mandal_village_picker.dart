import 'package:flutter/material.dart';

import '../../core/constants/villages.dart';
import '../../core/constants/app_strings.dart';

class MandalVillagePicker extends StatefulWidget {
  const MandalVillagePicker({
    super.key,
    required this.onChanged,
    this.initialVillageId,
  });
  final ValueChanged<String?> onChanged;
  final String? initialVillageId;
  @override
  State<MandalVillagePicker> createState() => _MandalVillagePickerState();
}

class _MandalVillagePickerState extends State<MandalVillagePicker> {
  String? _mandal;
  String? _village;
  @override
  void initState() {
    super.initState();
    _village = widget.initialVillageId;
    _mandal = KolleruVillages.mandals
        .where((m) => m.villages.any((v) => v.id == _village))
        .firstOrNull
        ?.id;
  }

  @override
  Widget build(BuildContext context) {
    final villages =
        KolleruVillages.mandals
            .where((m) => m.id == _mandal)
            .firstOrNull
            ?.villages ??
        const <Village>[];
    return Column(
      children: [
        DropdownButtonFormField<String>(
          key: const ValueKey('mandal-picker'),
          initialValue: _mandal,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'మండలం / Mandal'),
          validator: (value) =>
              value == null ? 'మండలం ఎంచుకోండి / Choose a mandal' : null,
          items: [
            for (final mandal in KolleruVillages.mandals)
              DropdownMenuItem(
                value: mandal.id,
                child: Text(
                  '${mandal.teluguName} / ${mandal.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) {
            setState(() {
              _mandal = id;
              _village = null;
            });
            widget.onChanged(null);
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey('village-picker-$_mandal'),
          initialValue: _village,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'గ్రామం / Village'),
          validator: (value) =>
              value == null ? AppStrings.villageRequired : null,
          items: [
            for (final village in villages)
              DropdownMenuItem(
                value: village.id,
                child: Text(village.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _mandal == null
              ? null
              : (id) {
                  setState(() => _village = id);
                  widget.onChanged(id);
                },
        ),
      ],
    );
  }
}
