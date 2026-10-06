import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'presentation/farmer/home_directory_screen.dart';

void main() => runApp(const KolleruWheelsApp());

class KolleruWheelsApp extends StatelessWidget {
  const KolleruWheelsApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Kolleru Wheels',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: const HomeDirectoryScreen(),
  );
}
