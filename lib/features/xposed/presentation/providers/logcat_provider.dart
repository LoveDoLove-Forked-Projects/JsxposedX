import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'logcat_provider.g.dart';

class LogcatEntry {
  final String rawLine;
  final String level;
  final String tag;
  final String message;
  final String timestamp;

  LogcatEntry({
    required this.rawLine,
    required this.level,
    this.tag = '',
    this.message = '',
    this.timestamp = '',
  });
}

@riverpod
class Logcat extends _$Logcat {
  static const _maxEntries = 500;
  static const _flushBatchSize = 32;
  static const _flushInterval = Duration(milliseconds: 50);

  Process? _process;
  int _processGeneration = 0;
  bool _isStarting = false;
  StreamSubscription<String>? _stdoutSubscription;
  Timer? _flushTimer;
  final List<LogcatEntry> _pendingEntries = <LogcatEntry>[];
  bool _isAutoScroll = true;
  String _targetPackage = '';
  String _searchQuery = '';
  bool _isDisposed = false;

  @override
  List<LogcatEntry> build() {
    _isDisposed = false;
    ref.onDispose(() {
      _isDisposed = true;
      _stopProcess();
      _pendingEntries.clear();
    });
    return [];
  }

  bool get isAutoScroll => _isAutoScroll;
  String get searchQuery => _searchQuery;

  void setAutoScroll(bool value) {
    if (_isAutoScroll == value) return;
    _isAutoScroll = value;
    // This is a low-frequency UI action; notify consumers without mutating entries.
    state = List<LogcatEntry>.unmodifiable(state);
  }

  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    // Search changes are user-driven and infrequent compared with log events.
    state = List<LogcatEntry>.unmodifiable(state);
  }

  Future<void> start(String packageName) async {
    _targetPackage = packageName;
    if (_process != null || _isStarting) return;
    _isStarting = true;
    final generation = ++_processGeneration;

    // Auto clear on start.
    _pendingEntries.clear();
    _flushTimer?.cancel();
    _flushTimer = null;
    state = const [];

    try {
      final process = await Process.start('su', ['-c', 'logcat -v time']);
      if (_isDisposed || generation != _processGeneration) {
        process.kill();
        return;
      }
      _process = process;
      _stdoutSubscription = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (_isDisposed || generation != _processGeneration) return;
              if (_passesFilter(line)) {
                _pendingEntries.add(_parseLine(line));
                if (_pendingEntries.length >= _flushBatchSize) {
                  _flushPending();
                } else {
                  _scheduleFlush();
                }
              }
            },
            onDone: () => _handleProcessDone(process),
            onError: (_, __) => _handleProcessDone(process),
          );
      unawaited(process.exitCode.then((_) => _handleProcessDone(process)));
      // We ignore stderr to avoid clutter
    } catch (e) {
      debugPrint("Logcat error: $e");
    } finally {
      if (generation == _processGeneration) {
        _isStarting = false;
      }
    }
  }

  void stop() {
    _flushPending();
    _stopProcess();
  }

  void clear() {
    _pendingEntries.clear();
    _flushTimer?.cancel();
    _flushTimer = null;
    if (state.isNotEmpty) state = const [];
  }

  void _scheduleFlush() {
    if (_flushTimer != null || _isDisposed) return;
    _flushTimer = Timer(_flushInterval, () {
      _flushTimer = null;
      _flushPending();
    });
  }

  void _flushPending() {
    if (_pendingEntries.isEmpty || _isDisposed) return;
    final pending = List<LogcatEntry>.from(_pendingEntries, growable: false);
    _pendingEntries.clear();
    final combined = <LogcatEntry>[...state, ...pending];
    final start = combined.length > _maxEntries
        ? combined.length - _maxEntries
        : 0;
    state = List<LogcatEntry>.unmodifiable(combined.sublist(start));
  }

  void _handleProcessDone(Process process) {
    if (_isDisposed || !identical(_process, process)) return;
    _flushPending();
    _stdoutSubscription = null;
    _process = null;
  }

  void _stopProcess() {
    _processGeneration += 1;
    _isStarting = false;
    _flushTimer?.cancel();
    _flushTimer = null;
    _stdoutSubscription?.cancel();
    _stdoutSubscription = null;
    _process?.kill();
    _process = null;
  }

  bool _passesFilter(String line) {
    if (line.isEmpty) return false;

    // Core filter for JsxposedX 业务日志
    bool isRelevant =
        line.contains('JsxposedX') || // LogX 统一日志
        line.contains('FridaInjectTest') || // Frida 注入日志
        line.contains('HookJsXposed') || // Xposed Hook 日志
        line.contains('JsxposedProvider') || // Provider 日志
        line.contains('AttachHooker') || // Hook 附加日志
        line.contains('StatusManagement') || // 状态管理日志
        line.contains('AuditLogProvider'); // 审计日志

    // 包含目标应用包名的日志也显示
    if (_targetPackage.isNotEmpty && line.contains(_targetPackage)) {
      isRelevant = true;
    }

    return isRelevant;
  }

  static final _logcatRegex = RegExp(
    r'^(\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)\s+\d+\s+\d+\s+([A-Z])\/([^:]+):\s*(.*)$',
  );

  LogcatEntry _parseLine(String line) {
    final match = _logcatRegex.firstMatch(line);
    if (match != null) {
      return LogcatEntry(
        rawLine: line,
        level: match.group(2) ?? 'I',
        timestamp: match.group(1) ?? '',
        tag: match.group(3)?.trim() ?? '',
        message: match.group(4) ?? '',
      );
    }
    // Fallback for non-standard lines
    String level = 'I';
    if (line.contains(' W/')) {
      level = 'W';
    } else if (line.contains(' E/') ||
        line.contains('Exception') ||
        line.contains('Error')) {
      level = 'E';
    } else if (line.contains(' F/')) {
      level = 'F';
    } else if (line.contains(' D/')) {
      level = 'D';
    }
    return LogcatEntry(rawLine: line, level: level, message: line);
  }
}
