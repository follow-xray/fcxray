import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../services/config_builder.dart';
import 'calm_theme.dart';

class ConnectionPanel extends StatelessWidget {
  const ConnectionPanel(
    this.c, {
    super.key,
    required this.onImport,
    required this.onManageNodes,
  });
  final AppController c;
  final VoidCallback onImport, onManageNodes;
  @override
  Widget build(BuildContext context) {
    final title = switch (c.status) {
      VpnStatus.connected => '隧道已启动',
      VpnStatus.connecting => '正在连接…',
      VpnStatus.disconnecting => '正在断开…',
      VpnStatus.failed => '连接失败',
      _ => '尚未连接',
    };
    final node = c.displayProfile?.name;
    final large = MediaQuery.sizeOf(context).width >= 820;
    final powerColor = c.connected
        ? Calm.of(context).pine
        : Calm.of(context).iris;
    return SoftSurface(
      padding: EdgeInsets.zero,
      radius: 28,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CustomPaint(
              painter: _Landscape(Calm.of(context)),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: large ? 32 : 18,
                  vertical: large ? 30 : 24,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.shield_outlined,
                                size: 16,
                                color: Calm.of(context).iris,
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  c.mode == ConnectionMode.vpn
                                      ? 'VPN 隧道'
                                      : '本地代理',
                                  style: TextStyle(
                                    color: Calm.of(context).muted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1.2,
                              fontSize: large ? 38 : 27,
                              color: Calm.of(context).ink,
                            ),
                          ),
                          if (c.connected) const SizedBox(height: 8),
                          if (c.connected)
                            Text(
                              '已运行 ${_time(c.uptime)}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Calm.of(context).muted,
                                height: 1.5,
                              ),
                            ),
                          if (node == null && c.routing != RoutingMode.direct)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: FilledButton.icon(
                                onPressed: c.editable ? onImport : null,
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('导入节点'),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: EdgeInsets.all(large ? 13 : 7),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Calm.of(context).inset,
                        boxShadow: Calm.of(context).relief,
                        border: Border.all(color: Calm.of(context).rim),
                      ),
                      child: SizedBox.square(
                        dimension: large ? 86 : 62,
                        child: IconButton.filled(
                          tooltip: c.connected ? '断开连接' : '连接',
                          onPressed: c.canToggle ? c.toggle : null,
                          style: IconButton.styleFrom(
                            backgroundColor: powerColor,
                            foregroundColor: Calm.of(context).onAccent,
                            disabledBackgroundColor: Calm.of(context).lilac,
                            disabledForegroundColor: Calm.of(context).muted,
                          ),
                          icon: c.busy
                              ? const CircularProgressIndicator(strokeWidth: 2)
                              : Icon(
                                  Icons.power_settings_new,
                                  size: large ? 39 : 30,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (c.displayProfile case final profile?)
              ListTile(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: large ? 28 : 16,
                ),
                leading: const Icon(Icons.hub_outlined),
                title: Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  profile.endpointLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: onManageNodes,
              ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: large ? 28 : 16,
                vertical: 14,
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '路由模式',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Calm.of(context).muted,
                      fontSize: 13,
                    ),
                  ),
                  SegmentedButton<RoutingMode>(
                    segments: [
                      for (final mode in RoutingMode.values)
                        ButtonSegment(value: mode, label: Text(mode.label)),
                    ],
                    selected: {c.routing},
                    onSelectionChanged: c.resourcesEditable
                        ? (v) => c.switchRouting(v.single)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _time(int seconds) => [
    seconds ~/ 3600,
    seconds ~/ 60 % 60,
    seconds % 60,
  ].map((v) => '$v'.padLeft(2, '0')).join(':');
}

// A lightweight landscape for the connection control. Coordinates scale with
// the panel, leaving the left side clear for long status and node names.
class _Landscape extends CustomPainter {
  const _Landscape(this.palette);
  final Calm palette;
  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: palette.dark
              ? const [Color(0xff31303e), Color(0xff3d394e), Color(0xff34464b)]
              : const [Color(0xfff4f1f7), Color(0xffebe5f3), Color(0xffe2eced)],
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipRect(rect);
    canvas.scale(s.width, s.height);
    final paint = Paint()..isAntiAlias = true;
    final sun = Offset(.78, .23);
    canvas.drawOval(
      Rect.fromCenter(
        center: sun,
        width: .20,
        height: .20 * s.width / s.height,
      ),
      paint
        ..color = palette.dark
            ? const Color(0xff655960)
            : const Color(0x80ffe8c9),
    );
    for (final (layer, color) in [
      (.70, palette.dark ? const Color(0xff464353) : const Color(0xffdbd9e7)),
      (.83, palette.dark ? const Color(0xff3f5554) : const Color(0xffc9d9d8)),
      (.95, palette.dark ? const Color(0xff364b46) : const Color(0xffbbccc4)),
    ]) {
      final p = Path()
        ..moveTo(.16, 1.03)
        ..cubicTo(.40, 1.03, .45, layer - .35, .62, layer - .18)
        ..cubicTo(.80, layer, .84, layer - .59, 1.08, layer - .66)
        ..lineTo(1.08, 1.04)
        ..close();
      canvas.drawPath(p, paint..color = color);
    }
    canvas.restore();
    // Fine, widely spaced contour lines echo a topographic map.
    canvas.save();
    canvas.clipRect(rect);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = palette.dark
          ? const Color(0x408ec0b2)
          : const Color(0x82ffffff);
    for (var i = 0; i < 6; i++) {
      final y = s.height * (.95 + i * .045);
      final p = Path()
        ..moveTo(s.width * .53, y)
        ..cubicTo(
          s.width * .71,
          y - s.height * .33,
          s.width * .81,
          y + s.height * .02,
          s.width * 1.06,
          y - s.height * .51,
        );
      canvas.drawPath(p, pen);
    }
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: palette.dark
              ? const [Color(0xff31303e), Color(0x0031303e)]
              : const [Color(0xfff4f1f7), Color(0x00f4f1f7)],
          stops: [math.min(.34, 120 / s.width), .70],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Landscape oldDelegate) => oldDelegate.palette != palette;
}
