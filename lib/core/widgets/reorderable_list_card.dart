import 'package:flutter/material.dart';

/// Shared "reorderable list inside a card" scaffolding — the drag mechanics,
/// proxy styling, and divider-separated rows first proven for per-day crew
/// editing (day_detail_screen.dart), generalized so Crew Roster and
/// Emergency Contacts can offer the same drag-to-reorder gesture without
/// each reimplementing `ReorderableListView` from scratch.
///
/// Callers decide when to show this vs. their own read-only view (e.g. only
/// while in an explicit edit mode) — the read view otherwise differs enough
/// per list (tappable rows vs. a plain display) that unifying it too
/// wouldn't remove real duplication, just add indirection.
class ReorderableListCard<T> extends StatelessWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final void Function(int oldIndex, int newIndex) onReorder;
  /// Identifies each row across reorders/rebuilds — must track the item's
  /// own identity, not its position (a plain index key would let Flutter
  /// misattribute widget state across a reorder). Defaults to [ObjectKey],
  /// which is only a safe default if [T] has real value equality.
  final Key Function(T item) keyOf;
  /// Row separator color; omit for no divider between rows.
  final Color? dividerColor;
  final EdgeInsets padding;

  ReorderableListCard({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.onReorder,
    Key Function(T item)? keyOf,
    this.dividerColor,
    this.padding = const EdgeInsets.all(12),
  }) : keyOf = keyOf ?? ((item) => ObjectKey(item));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      padding: padding,
      onReorderItem: onReorder,
      proxyDecorator: (child, index, animation) => Material(
        elevation: 4,
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        child: child,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final isLast = i == items.length - 1;
        return Column(
          key: keyOf(items[i]),
          children: [
            itemBuilder(context, items[i], i),
            if (!isLast && dividerColor != null)
              Divider(color: dividerColor, height: 16),
          ],
        );
      },
    );
  }
}
