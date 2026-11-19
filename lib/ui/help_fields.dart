import 'calm_theme.dart';
import 'package:flutter/material.dart';

/// Tooltip's hover works on desktop; explicit activation makes taps work on touch.
class HelpIcon extends StatefulWidget {
  const HelpIcon(this.message, {super.key, this.label = '参数说明'});
  final String message, label;
  @override
  State<HelpIcon> createState() => _HelpIconState();
}

class _HelpIconState extends State<HelpIcon> {
  final _tooltip = GlobalKey<TooltipState>();
  @override
  Widget build(BuildContext context) => Tooltip(
    key: _tooltip,
    message: widget.message,
    waitDuration: const Duration(milliseconds: 350),
    showDuration: const Duration(seconds: 12),
    constraints: const BoxConstraints(maxWidth: 340),
    triggerMode: TooltipTriggerMode.manual,
    child: IconButton(
      visualDensity: VisualDensity.compact,
      onPressed: () => _tooltip.currentState?.ensureTooltipVisible(),
      icon: Icon(Icons.help_outline, size: 18, semanticLabel: widget.label),
      color: Calm.of(context).muted,
      tooltip: null,
    ),
  );
}

InputDecoration helpDecoration(String label, String help, {String? hint}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: HelpIcon(help, label: '$label说明'),
    );

class HelpDropdown<T> extends StatelessWidget {
  const HelpDropdown({
    super.key,
    required this.label,
    required this.help,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String label, help;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
    key: ValueKey('$label:$value'),
    initialValue: value,
    isExpanded: true,
    decoration: helpDecoration(label, help),
    items: items,
    onChanged: onChanged,
  );
}
