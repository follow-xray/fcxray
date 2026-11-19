import 'package:flutter/material.dart';

class Calm {
  const Calm._(this.dark);
  final bool dark;
  static const light = Calm._(false);
  static const night = Calm._(true);
  static Calm of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? night : light;

  Color get canvas => dark ? const Color(0xff22232c) : const Color(0xfff3f4f7);
  Color get paper => dark ? const Color(0xff2c2d38) : const Color(0xfffcfbfd);
  Color get ink => dark ? const Color(0xffeeeaf4) : const Color(0xff302f42);
  Color get muted => dark ? const Color(0xffc2becf) : const Color(0xff605e70);
  Color get iris => dark ? const Color(0xffcfb8ed) : const Color(0xff665490);
  Color get lilac => dark ? const Color(0xff453e56) : const Color(0xffe9e2f4);
  Color get mint => dark ? const Color(0xff344b43) : const Color(0xffdceedf);
  Color get pine => dark ? const Color(0xffacdbc0) : const Color(0xff356451);
  Color get peach => dark ? const Color(0xff50413c) : const Color(0xfff7e6da);
  Color get clay => dark ? const Color(0xffecc0a4) : const Color(0xff80503e);
  Color get line => dark ? const Color(0xff535260) : const Color(0xffdcd9e4);
  Color get error => dark ? const Color(0xffffb6bf) : const Color(0xff943d47);
  Color get blush => dark ? const Color(0xff51363f) : const Color(0xfffae6e6);
  Color get rim => dark ? const Color(0xff41424e) : Colors.white;
  Color get inset => dark ? const Color(0xff272832) : const Color(0xfff4f2f7);
  Color get onAccent => dark ? const Color(0xff282333) : Colors.white;
  List<BoxShadow> get relief => [
    BoxShadow(
      color: dark ? const Color(0x454d4c5b) : Colors.white,
      offset: const Offset(-4, -4),
      blurRadius: 11,
    ),
    BoxShadow(
      color: dark ? const Color(0x600d0e14) : const Color(0x24525670),
      offset: const Offset(4, 6),
      blurRadius: 14,
    ),
  ];
  ThemeData theme() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: iris,
          brightness: dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: iris,
          onPrimary: onAccent,
          primaryContainer: lilac,
          onPrimaryContainer: ink,
          secondary: pine,
          secondaryContainer: mint,
          onSecondaryContainer: pine,
          tertiary: clay,
          tertiaryContainer: peach,
          surface: paper,
          onSurface: ink,
          onSurfaceVariant: muted,
          outline: dark ? const Color(0xff9893a6) : const Color(0xff858092),
          outlineVariant: line,
          error: error,
          errorContainer: blush,
        );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
    );
    final inputShape = OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide(color: line),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      cardTheme: CardThemeData(
        color: paper,
        elevation: 1.5,
        shadowColor: dark ? Colors.black54 : const Color(0x38514b65),
        shape: shape.copyWith(side: BorderSide(color: rim)),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        shape: shape,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inset,
        border: inputShape,
        enabledBorder: inputShape,
        focusedBorder: inputShape.copyWith(
          borderSide: BorderSide(color: iris, width: 2),
        ),
        labelStyle: TextStyle(color: muted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: paper,
        indicatorColor: lilac,
        surfaceTintColor: Colors.transparent,
        height: 70,
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(color: ink, fontSize: 12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          minimumSize: const Size(48, 44),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: line),
          minimumSize: const Size(48, 44),
          foregroundColor: iris,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? lilac : paper,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled)
                ? const Color(0xff8b8794)
                : ink,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: line)),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: TextStyle(color: canvas, fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      dividerTheme: DividerThemeData(color: line, space: 24, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: TextStyle(color: canvas),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class SoftSurface extends StatelessWidget {
  const SoftSurface({
    super.key,
    required this.child,
    this.color,
    this.radius = 24,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final Color? color;
  final double radius;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color ?? Calm.of(context).paper,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: Calm.of(context).relief,
      border: Border.all(color: Calm.of(context).rim),
    ),
    child: Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(radius),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class TintIcon extends StatelessWidget {
  const TintIcon(this.icon, {super.key, this.fill, this.ink});
  final IconData icon;
  final Color? fill, ink;
  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      color: fill ?? Calm.of(context).lilac,
    ),
    child: Icon(icon, size: 20, color: ink ?? Calm.of(context).iris),
  );
}
