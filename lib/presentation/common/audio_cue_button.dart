import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../core/constants/app_strings.dart';

/// Spoken via an enabled screen reader; no network download required.
class AudioCueButton extends StatelessWidget {
  const AudioCueButton({super.key, this.message = AppStrings.audioHint});
  final String message;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    child: const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.volume_up),
        SizedBox(width: 8),
        Flexible(
          child: Text(
            AppStrings.audio,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
    onPressed: () {
      if (MediaQuery.supportsAnnounceOf(context)) {
        SemanticsService.sendAnnouncement(
          View.of(context),
          message,
          Directionality.of(context),
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$message\n${AppStrings.audioRequiresReader}'),
          duration: const Duration(seconds: 8),
        ),
      );
    },
  );
}
