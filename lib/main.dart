import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'services/desktop_tray.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'controllers/app_controller.dart';
import 'ui/home_page.dart';
import 'ui/calm_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final index =
        jsonDecode(await rootBundle.loadString('assets/licenses/index.json'))
            as List;
    for (final entry in index) {
      yield LicenseEntryWithLineBreaks([
        entry['name'] as String,
      ], await rootBundle.loadString(entry['asset'] as String));
    }
  });
  final controller = createController();
  runApp(FcxrayApp(controller: controller));
  unawaited(controller.initialize());
  if (Platform.isMacOS || Platform.isWindows) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await DesktopTray(controller).install();
      } catch (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      }
    });
  }
}

class FcxrayApp extends StatelessWidget {
  const FcxrayApp({super.key, required this.controller});
  final AppController controller;
  static final _light = Calm.light.theme();
  static final _dark = Calm.night.theme();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: controller.themeMode,
    child: HomePage(controller: controller),
    builder: (_, mode, home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'fcxray',
      theme: _light,
      darkTheme: _dark,
      themeMode: mode,
      home: home,
    ),
  );
}
