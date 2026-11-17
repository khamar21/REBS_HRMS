import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'core/theme.dart';
import 'data/db.dart';
import 'presentation/providers.dart';
import 'presentation/screens/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  final db = await AppDb.open();
  runApp(
    DevicePreview(
      enabled: !kReleaseMode,
      builder: (context) => ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: const RebsApp(),
      ),
    ),
  );
}

class RebsApp extends StatelessWidget {
  const RebsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'REBS HRMS',
      debugShowCheckedModeBanner: false,
      locale: DevicePreview.locale(context),
      theme: buildTheme(),
      builder: (context, child) => DevicePreview.appBuilder(
        context,
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: FocusManager.instance.primaryFocus?.unfocus,
          child: child,
        ),
      ),
      home: const Shell(),
    );
  }
}
