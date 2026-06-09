const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Returns a human-readable relative time string for [dt], e.g. "just now",
/// "5 min ago", "3h ago", "Yesterday", or "Jan 7" / "Jan 7, 2025".
String relativeTime(DateTime dt, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  final m = _months[dt.month - 1];
  return dt.year == reference.year
      ? '$m ${dt.day}'
      : '$m ${dt.day}, ${dt.year}';
}
