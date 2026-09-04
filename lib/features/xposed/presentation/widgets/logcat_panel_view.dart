import 'dart:async';
import 'dart:convert';

import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/xposed/presentation/providers/logcat_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

const _kSourceFilters = [
  (label: 'Session', value: 'session'),
  (label: 'Frida', value: 'frida'),
  (label: 'Xposed', value: 'xposed'),
  (label: 'App', value: 'app'),
  (label: 'Core', value: 'framework'),
  (label: 'System', value: 'system'),
];

const _kLevelFilters = [
  (label: 'Debug', value: 'D'),
  (label: 'Info', value: 'I'),
  (label: 'Warn', value: 'W'),
  (label: 'Error', value: 'E'),
];

class LogcatPanelView extends HookConsumerWidget {
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;

  const LogcatPanelView({
    super.key,
    required this.isFullscreen,
    required this.onToggleFullscreen,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logEntries = ref.watch(logcatProvider);
    final logcatNotifier = ref.read(logcatProvider.notifier);
    final autoScroll = logcatNotifier.isAutoScroll;
    final searchQuery = logcatNotifier.searchQuery;
    final scrollController = useScrollController();
    final selectedSource = useState<String?>(null);
    final selectedLevel = useState<String?>(null);
    final searchDebounce = useRef<Timer?>(null);

    useEffect(() {
      return () => searchDebounce.value?.cancel();
    }, const []);

    // 使用 useMemoized 缓存过滤结果，避免每次都重新计算
    final filteredEntries = useMemoized(() {
      final normalizedQuery = searchQuery.toLowerCase();
      final hasFilter =
          normalizedQuery.isNotEmpty ||
          selectedSource.value != null ||
          selectedLevel.value != null;
      if (!hasFilter) return logEntries;
      return logEntries.where((entry) {
        // Text search filter (from provider search query)
        if (normalizedQuery.isNotEmpty &&
            !entry.searchText.contains(normalizedQuery)) {
          return false;
        }
        if (selectedSource.value != null &&
            entry.source != selectedSource.value) {
          return false;
        }
        if (selectedLevel.value != null && entry.level != selectedLevel.value) {
          return false;
        }
        return true;
      }).toList();
    }, [logEntries, searchQuery, selectedSource.value, selectedLevel.value]);

    final scrollScheduled = useRef(false);
    ref.listen(logcatProvider, (previous, next) {
      if (logcatNotifier.isAutoScroll && scrollController.hasClients) {
        if (scrollScheduled.value) return;
        scrollScheduled.value = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          scrollScheduled.value = false;
          if (scrollController.hasClients) {
            scrollController.jumpTo(scrollController.position.maxScrollExtent);
          }
        });
      }
    });

    final isAnyFiltered =
        searchQuery.isNotEmpty ||
        selectedSource.value != null ||
        selectedLevel.value != null;

    Future<void> copyVisibleLogs() async {
      final text = filteredEntries.map(_formatEntry).join('\n');
      await Clipboard.setData(ClipboardData(text: text));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${filteredEntries.length} logs copied')),
      );
    }

    Future<void> exportVisibleLogs() async {
      final text = filteredEntries.map(_formatEntry).join('\n');
      await FilePicker.platform.saveFile(
        dialogTitle: 'Export console logs',
        fileName: 'jsxposed-console-${logcatNotifier.sessionId}.log',
        bytes: utf8.encode(text),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        border: Border(
          top: BorderSide(
            color: context.theme.dividerColor.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: Column(
        children: [
          // ── Toolbar ──
          _LogcatToolbar(
            autoScroll: autoScroll,
            filteredCount: filteredEntries.length,
            totalCount: logEntries.length,
            isFullscreen: isFullscreen,
            isPaused: logcatNotifier.isPaused,
            isRunning: logcatNotifier.isRunning,
            onSearchChanged: (query) {
              searchDebounce.value?.cancel();
              searchDebounce.value = Timer(
                const Duration(milliseconds: 200),
                () => logcatNotifier.setSearchQuery(query),
              );
            },
            onAutoScrollToggle: () => logcatNotifier.setAutoScroll(!autoScroll),
            onPauseToggle: () =>
                logcatNotifier.setPaused(!logcatNotifier.isPaused),
            onCopy: copyVisibleLogs,
            onExport: exportVisibleLogs,
            onClear: logcatNotifier.clear,
            onToggleFullscreen: onToggleFullscreen,
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: Colors.white.withValues(alpha: 0.06),
          ),
          // ── Source and level filters ──
          _FilterRow(
            selectedSource: selectedSource.value,
            selectedLevel: selectedLevel.value,
            onSourceSelected: (source) => selectedSource.value = source,
            onLevelSelected: (level) => selectedLevel.value = level,
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: Colors.white.withValues(alpha: 0.04),
          ),
          // ── Log List ──
          Expanded(
            child: filteredEntries.isEmpty
                ? _EmptyState(isFiltered: isAnyFiltered)
                : ListView.builder(
                    controller: scrollController,
                    padding: EdgeInsets.symmetric(vertical: 4.h),
                    itemCount: filteredEntries.length,
                    itemBuilder: (context, index) =>
                        _LogRow(entry: filteredEntries[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Toolbar
// ─────────────────────────────────────────────

class _LogcatToolbar extends StatelessWidget {
  final bool autoScroll;
  final int filteredCount;
  final int totalCount;
  final bool isFullscreen;
  final bool isPaused;
  final bool isRunning;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onAutoScrollToggle;
  final VoidCallback onPauseToggle;
  final VoidCallback onCopy;
  final VoidCallback onExport;
  final VoidCallback onClear;
  final VoidCallback onToggleFullscreen;

  const _LogcatToolbar({
    required this.autoScroll,
    required this.filteredCount,
    required this.totalCount,
    required this.isFullscreen,
    required this.isPaused,
    required this.isRunning,
    required this.onSearchChanged,
    required this.onAutoScrollToggle,
    required this.onPauseToggle,
    required this.onCopy,
    required this.onExport,
    required this.onClear,
    required this.onToggleFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    final isFiltered = filteredCount != totalCount;
    return Container(
      height: 38.h,
      padding: EdgeInsets.symmetric(horizontal: 8.w),
      color: const Color(0xFF1A1A1A),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 400;
          return Row(
            children: [
              if (!compact) ...[
                Icon(
                  Icons.terminal_rounded,
                  size: 13.sp,
                  color: Colors.grey[500],
                ),
                SizedBox(width: 5.w),
              ],
              Container(
                width: 7.w,
                height: 7.w,
                decoration: BoxDecoration(
                  color: isPaused
                      ? Colors.orange
                      : isRunning
                      ? const Color(0xFF66BB6A)
                      : Colors.grey[700],
                  shape: BoxShape.circle,
                ),
              ),
              if (!compact) ...[
                SizedBox(width: 5.w),
                Text(
                  context.l10n.terminal,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[300],
                  ),
                ),
              ],
              SizedBox(width: 6.w),
              // Entry count badge
              if (totalCount > 0)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? 48.w : 64.w),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 5.w,
                      vertical: 1.h,
                    ),
                    decoration: BoxDecoration(
                      color: isFiltered
                          ? Colors.blue.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text(
                      isFiltered ? '$filteredCount/$totalCount' : '$totalCount',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9.sp,
                        color: isFiltered ? Colors.blue[300] : Colors.grey[500],
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              SizedBox(width: 6.w),
              // Search takes the space left after the fixed-size actions.
              Expanded(
                child: SizedBox(
                  height: 26.h,
                  child: TextField(
                    style: TextStyle(fontSize: 11.sp, color: Colors.grey[200]),
                    decoration: InputDecoration(
                      hintText: compact
                          ? null
                          : context.l10n.terminalFilterHint,
                      hintStyle: TextStyle(
                        fontSize: 11.sp,
                        color: Colors.grey[700],
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 13.sp,
                        color: Colors.grey[600],
                      ),
                      prefixIconConstraints: BoxConstraints(minWidth: 26.w),
                      contentPadding: EdgeInsets.symmetric(vertical: 4.h),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6.r),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6.r),
                        borderSide: BorderSide(
                          color: Colors.grey[600]!,
                          width: 0.8,
                        ),
                      ),
                    ),
                    onChanged: onSearchChanged,
                  ),
                ),
              ),
              SizedBox(width: 4.w),
              _ToolbarIconButton(
                icon: autoScroll
                    ? Icons.vertical_align_bottom_rounded
                    : Icons.pause_circle_outline_rounded,
                tooltip: context.l10n.autoScroll,
                color: autoScroll ? const Color(0xFF66BB6A) : Colors.grey[600]!,
                onPressed: onAutoScrollToggle,
              ),
              _ToolbarIconButton(
                icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                tooltip: isPaused ? 'Resume output' : 'Pause output',
                color: isPaused ? Colors.orange : Colors.grey[600]!,
                onPressed: onPauseToggle,
              ),
              SizedBox(
                width: 27.w,
                height: 28.h,
                child: PopupMenuButton<String>(
                  tooltip: 'Console actions',
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  iconSize: 15.sp,
                  icon: Icon(Icons.more_vert_rounded, color: Colors.grey[600]),
                  onSelected: (value) {
                    if (value == 'copy') onCopy();
                    if (value == 'export') onExport();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'copy',
                      child: Text('Copy visible logs'),
                    ),
                    PopupMenuItem(
                      value: 'export',
                      child: Text('Export visible logs'),
                    ),
                  ],
                ),
              ),
              _ToolbarIconButton(
                icon: Icons.delete_sweep_outlined,
                tooltip: context.l10n.clearPanel,
                color: Colors.grey[600]!,
                onPressed: onClear,
              ),
              _ToolbarIconButton(
                icon: isFullscreen
                    ? Icons.close_fullscreen_rounded
                    : Icons.open_in_full_rounded,
                tooltip: context.l10n.logcatFullscreen,
                color: isFullscreen ? Colors.blue[300]! : Colors.grey[600]!,
                onPressed: onToggleFullscreen,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Tag Filter Row
// ─────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  final String? selectedSource;
  final String? selectedLevel;
  final ValueChanged<String?> onSourceSelected;
  final ValueChanged<String?> onLevelSelected;

  const _FilterRow({
    required this.selectedSource,
    required this.selectedLevel,
    required this.onSourceSelected,
    required this.onLevelSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32.h,
      color: const Color(0xFF161616),
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _kSourceFilters.length + _kLevelFilters.length + 2,
        separatorBuilder: (_, __) => SizedBox(width: 6.w),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _TagChip(
              label: 'All',
              isSelected: selectedSource == null && selectedLevel == null,
              onTap: () {
                onSourceSelected(null);
                onLevelSelected(null);
              },
            );
          }
          if (index <= _kSourceFilters.length) {
            final filter = _kSourceFilters[index - 1];
            return _TagChip(
              label: filter.label,
              isSelected: selectedSource == filter.value,
              onTap: () => onSourceSelected(
                selectedSource == filter.value ? null : filter.value,
              ),
            );
          }
          if (index == _kSourceFilters.length + 1) {
            return VerticalDivider(
              width: 8.w,
              indent: 7.h,
              endIndent: 7.h,
              color: Colors.white.withValues(alpha: 0.12),
            );
          }
          final filter = _kLevelFilters[index - _kSourceFilters.length - 2];
          return _TagChip(
            label: filter.label,
            isSelected: selectedLevel == filter.value,
            onTap: () => onLevelSelected(
              selectedLevel == filter.value ? null : filter.value,
            ),
          );
        },
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TagChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        alignment: Alignment.center,
        margin: EdgeInsets.symmetric(vertical: 5.h),
        padding: EdgeInsets.symmetric(horizontal: 8.w),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.blue.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
            color: isSelected
                ? Colors.blue.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.07),
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.sp,
            fontFamily: 'monospace',
            color: isSelected ? Colors.blue[200] : Colors.grey[500],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Log Row
// ─────────────────────────────────────────────

class _LogRow extends StatelessWidget {
  final LogcatEntry entry;

  const _LogRow({required this.entry});

  Color get _levelColor => switch (entry.level) {
    'E' => const Color(0xFFEF5350),
    'F' => const Color(0xFFEC407A),
    'W' => const Color(0xFFFFA726),
    'D' => const Color(0xFF42A5F5),
    _ => const Color(0xFFB0BEC5),
  };

  Color get _rowBgColor => switch (entry.level) {
    'E' || 'F' => const Color(0x14EF5350),
    'W' => const Color(0x0DFFA726),
    _ => Colors.transparent,
  };

  Color get _sourceColor => switch (entry.source) {
    'frida' => const Color(0xFFFFB74D),
    'xposed' => const Color(0xFF81C784),
    'app' => const Color(0xFF64B5F6),
    'framework' => const Color(0xFFBA68C8),
    _ => const Color(0xFF90A4AE),
  };

  @override
  Widget build(BuildContext context) {
    final hasStructured = entry.tag.isNotEmpty || entry.source.isNotEmpty;
    // Show only HH:MM:SS.mmm from "MM-DD HH:MM:SS.mmm" (skip first 6 chars)
    final timeDisplay = entry.timestamp.length > 6
        ? entry.timestamp.substring(6)
        : '';

    return InkWell(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: _formatEntry(entry)));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Log copied')));
      },
      child: Container(
        color: _rowBgColor,
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 3.h),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Level badge
            Container(
              width: 16.w,
              height: 16.h,
              margin: EdgeInsets.only(top: 2.h),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _levelColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3.r),
              ),
              child: Text(
                entry.level,
                style: TextStyle(
                  fontSize: 9.5.sp,
                  fontWeight: FontWeight.bold,
                  color: _levelColor,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            SizedBox(width: 8.w),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasStructured)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            [
                              entry.source.toUpperCase(),
                              if (entry.scriptName.isNotEmpty) entry.scriptName,
                              if (entry.tag.isNotEmpty) entry.tag,
                            ].join('  ·  '),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.sp,
                              color: _sourceColor.withValues(alpha: 0.85),
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (timeDisplay.isNotEmpty)
                          Text(
                            timeDisplay,
                            style: TextStyle(
                              fontSize: 9.sp,
                              color: Colors.grey[700],
                              fontFamily: 'monospace',
                            ),
                          ),
                      ],
                    ),
                  Text(
                    hasStructured ? entry.message : entry.rawLine,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.sp,
                      color: entry.level == 'E' || entry.level == 'F'
                          ? const Color(0xFFEF9A9A)
                          : entry.level == 'W'
                          ? const Color(0xFFFFCC80)
                          : Colors.white70,
                      height: 1.35,
                    ),
                  ),
                  if (entry.stackTrace.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 3.h),
                      child: Text(
                        entry.stackTrace,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10.sp,
                          color: const Color(0xFFEF9A9A),
                          height: 1.3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatEntry(LogcatEntry entry) {
  final buffer = StringBuffer();
  if (entry.timestamp.isNotEmpty) buffer.write('${entry.timestamp} ');
  buffer.write('${entry.level} [${entry.source.toUpperCase()}]');
  if (entry.scriptName.isNotEmpty) buffer.write('[${entry.scriptName}]');
  if (entry.pid.isNotEmpty) buffer.write('[pid:${entry.pid}]');
  buffer.write(' ${entry.message}');
  if (entry.stackTrace.isNotEmpty) buffer.write('\n${entry.stackTrace}');
  return buffer.toString();
}

// ─────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isFiltered;

  const _EmptyState({required this.isFiltered});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isFiltered ? Icons.filter_list_off : Icons.terminal_rounded,
              size: 28.sp,
              color: Colors.grey[800],
            ),
            SizedBox(height: 8.h),
            Text(
              isFiltered ? context.l10n.noLogsFiltered : context.l10n.noLogs,
              style: TextStyle(fontSize: 12.sp, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Toolbar Icon Button
// ─────────────────────────────────────────────

class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 27.w,
        height: 28.h,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4.r),
          child: Center(
            child: Icon(icon, size: 15.sp, color: color),
          ),
        ),
      ),
    );
  }
}
