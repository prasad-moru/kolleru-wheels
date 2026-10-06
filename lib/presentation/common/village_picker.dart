import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../core/constants/villages.dart';

class VillagePicker extends StatelessWidget {
  const VillagePicker({
    super.key,
    required this.onChanged,
    this.initialVillageId,
  });
  final String? initialVillageId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: initialVillageId,
    isExpanded: true,
    decoration: const InputDecoration(labelText: AppStrings.baseVillage),
    validator: (id) => id == null ? AppStrings.villageRequired : null,
    items: [
      for (final mandal in KolleruVillages.mandals)
        for (final village in mandal.villages)
          DropdownMenuItem(
            value: village.id,
            child: Text(
              '${village.label} (${mandal.name})',
              overflow: TextOverflow.ellipsis,
            ),
          ),
    ],
    onChanged: onChanged,
  );
}
