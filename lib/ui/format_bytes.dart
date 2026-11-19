String formatBytes(num value) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var n = value.toDouble();
  var unit = 0;
  while (n >= 1024 && unit < units.length - 1) {
    n /= 1024;
    unit++;
  }
  return '${n.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}
