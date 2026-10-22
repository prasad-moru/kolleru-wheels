import 'package:flutter/material.dart';

import '../../core/constants/villages.dart';
import '../../core/constants/app_strings.dart';
import '../../core/localization/app_language_provider.dart';

class MandalVillagePicker extends StatefulWidget {
  const MandalVillagePicker({
    super.key,
    required this.onChanged,
    this.initialVillageId,
    this.language,
  });
  final ValueChanged<String?> onChanged;
  final String? initialVillageId;
  final AppLanguageProvider? language;
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
          decoration: InputDecoration(labelText: widget.language?.tr(
            te: 'మండలం', en: 'Mandal',
          ) ?? 'మండలం / Mandal'),
          validator: (value) =>
              value == null ? (widget.language?.tr(
                te: 'మండలం ఎంచుకోండి', en: 'Choose a mandal',
              ) ?? 'మండలం ఎంచుకోండి / Choose a mandal') : null,
          items: [
            for (final mandal in KolleruVillages.mandals)
              DropdownMenuItem(
                key: ValueKey('mandal-option-${mandal.id}'),
                value: mandal.id,
                child: Text(
                  widget.language?.tr(te: mandal.teluguName, en: mandal.name) ??
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
          decoration: InputDecoration(labelText: widget.language?.tr(
            te: 'గ్రామం', en: 'Village',
          ) ?? 'గ్రామం / Village'),
          validator: (value) =>
              value == null ? (widget.language?.label(AppStrings.villageRequired) ??
                  AppStrings.villageRequired) : null,
          items: [
            for (final village in villages)
              DropdownMenuItem(
                key: ValueKey('village-option-${village.id}'),
                value: village.id,
                child: Text(widget.language?.tr(
                  te: village.teluguName, en: village.name,
                ) ?? village.label, overflow: TextOverflow.ellipsis),
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
