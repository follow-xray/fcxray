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
  if (kReleaseMode) {
    // This fallback must paint even when Material ancestors or image assets
    // are unavailable. Keep diagnostics in Flutter's normal error reporter.
    ErrorWidget.builder = (_) => Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xff302f42),
        child: Center(
          child: GestureDetector(
            onTap: controller.openRecovery,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '界面加载失败 · 打开恢复页',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ),
      ),
    );
  }
  runApp(FcxrayApp(controller: controller));
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => unawaited(controller.initialize()),
  );
  if (Platform.isMacOS) {
    unawaited(
      WidgetsBinding.instance.waitUntilFirstFrameRasterized.then(
        (_) => const MethodChannel(
          'com.fcxray.client/window',
        ).invokeMethod<void>('firstFrame'),
      ),
    );
  }
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
