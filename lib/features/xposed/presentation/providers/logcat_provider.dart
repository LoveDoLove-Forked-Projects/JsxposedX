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
  final String source;
  final String scriptName;
  final String sessionId;
  final String pid;
  final String tid;
  final String stackTrace;
  late final String searchText;

  LogcatEntry({
    required this.rawLine,
    required this.level,
    this.tag = '',
    this.message = '',
    this.timestamp = '',
    this.source = 'system',
    this.scriptName = '',
    this.sessionId = '',
    this.pid = '',
    this.tid = '',
    this.stackTrace = '',
  }) {
    searchText = [
      rawLine,
      message,
      source,
      scriptName,
      tag,
      stackTrace,
      pid,
    ].join('\n').toLowerCase();
  }
}

@riverpod
class Logcat extends _$Logcat {
  static const _maxEntries = 2000;
  static const _maxPausedEntries = 4000;
  static const _flushBatchSize = 32;
  static const _flushInterval = Duration(milliseconds: 50);

  Process? _process;
  int _processGeneration = 0;
  bool _isStarting = false;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  Timer? _flushTimer;
  final List<LogcatEntry> _pendingEntries = <LogcatEntry>[];
  final List<LogcatEntry> _pausedEntries = <LogcatEntry>[];
  bool _isAutoScroll = true;
  bool _isPaused = false;
  String _targetPackage = '';
  String _searchQuery = '';
  String _sessionId = '';
  String _sessionSource = 'all';
  String _sessionScriptName = '';
  bool _isDisposed = false;

  @override
  List<LogcatEntry> build() {
    _isDisposed = false;
    ref.onDispose(() {
      _isDisposed = true;
      _stopProcess();
      _pendingEntries.clear();
      _pausedEntries.clear();
    });
    return [];
  }

  bool get isAutoScroll => _isAutoScroll;
  bool get isPaused => _isPaused;
  bool get isRunning => _process != null;
  bool get isStarting => _isStarting;
  String get searchQuery => _searchQuery;
  String get sessionId => _sessionId;
  String get sessionSource => _sessionSource;
  String get sessionScriptName => _sessionScriptName;
  String get targetPackage => _targetPackage;

  void setAutoScroll(bool value) {
    if (_isAutoScroll == value) return;
    _isAutoScroll = value;
    // This is a low-frequency UI action; notify consumers without mutating entries.
    state = List<LogcatEntry>.unmodifiable(state);
  }

  void setPaused(bool value) {
    if (_isPaused == value) return;
    if (value) {
      _flushPending();
      _isPaused = true;
    } else {
      _isPaused = false;
      if (_pausedEntries.isNotEmpty) {
        _pendingEntries.addAll(_pausedEntries);
        _pausedEntries.clear();
      }
      _flushPending();
    }
    state = List<LogcatEntry>.unmodifiable(state);
  }

  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    // Search changes are user-driven and infrequent compared with log events.
    state = List<LogcatEntry>.unmodifiable(state);
  }

  void configureSession(String source, String scriptName) {
    _sessionSource = source;
    _sessionScriptName = scriptName;
  }

  Future<void> start(String packageName) async {
    _targetPackage = packageName;
    if (_process != null || _isStarting) return;
    _isStarting = true;
    final generation = ++_processGeneration;
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _isPaused = false;

    // Auto clear on start.
    _pendingEntries.clear();
    _pausedEntries.clear();
    _flushTimer?.cancel();
    _flushTimer = null;
    state = const [];

    try {
      // threadtime exposes pid/tid, which lets the Dart side classify entries reliably.
      final process = await Process.start('su', [
        '-c',
        'logcat -v threadtime -T 1',
      ]);
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
              final entry = _parseLine(line);
              if (!_passesFilter(entry)) return;
              if (_isPaused) {
                _pausedEntries.add(entry);
                if (_pausedEntries.length > _maxPausedEntries) {
                  _pausedEntries.removeRange(
                    0,
                    _pausedEntries.length - _maxPausedEntries,
                  );
                }
                return;
              }
              _pendingEntries.add(entry);
              if (_pendingEntries.length >= _flushBatchSize) {
                _flushPending();
              } else {
                _scheduleFlush();
              }
            },
            onDone: () => _handleProcessDone(process),
            onError: (_, __) => _handleProcessDone(process),
          );
      _stderrSubscription = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) {
            if (line.trim().isEmpty) return;
            _enqueueEntry(
              LogcatEntry(
                rawLine: line,
                level: 'E',
                message: line,
                source: 'system',
                sessionId: _sessionId,
                tag: 'logcat',
              ),
            );
          });
      _enqueueEntry(
        LogcatEntry(
          rawLine: '',
          level: 'I',
          message: 'Console connected to $packageName',
          source: 'session',
          scriptName: _sessionScriptName,
          sessionId: _sessionId,
          tag: _sessionSource,
        ),
      );
      unawaited(process.exitCode.then((_) => _handleProcessDone(process)));
    } catch (e) {
      debugPrint("Logcat error: $e");
      _enqueueEntry(
        LogcatEntry(
          rawLine: e.toString(),
          level: 'E',
          message: 'Unable to start console: $e',
          source: 'session',
          scriptName: _sessionScriptName,
          sessionId: _sessionId,
          tag: _sessionSource,
        ),
      );
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
    _pausedEntries.clear();
    _flushTimer?.cancel();
    _flushTimer = null;
    if (state.isNotEmpty) state = const [];
  }

  void addSessionEvent({
    required String message,
    String level = 'I',
    String? source,
    String? scriptName,
  }) {
    _enqueueEntry(
      LogcatEntry(
        rawLine: message,
        level: level,
        message: message,
        source: 'session',
        scriptName: scriptName ?? _sessionScriptName,
        sessionId: _sessionId,
        tag: source ?? _sessionSource,
      ),
    );
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
    _stderrSubscription?.cancel();
    _stderrSubscription = null;
    _process = null;
    state = List<LogcatEntry>.unmodifiable(state);
  }

  void _stopProcess() {
    _processGeneration += 1;
    _isStarting = false;
    _flushTimer?.cancel();
    _flushTimer = null;
    _stdoutSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription?.cancel();
    _stderrSubscription = null;
    _process?.kill();
    _process = null;
  }

  void _enqueueEntry(LogcatEntry entry) {
    if (_isPaused) {
      _pausedEntries.add(entry);
      if (_pausedEntries.length > _maxPausedEntries) {
        _pausedEntries.removeRange(
          0,
          _pausedEntries.length - _maxPausedEntries,
        );
      }
      return;
    }
    _pendingEntries.add(entry);
    if (_pendingEntries.length >= _flushBatchSize) {
      _flushPending();
    } else {
      _scheduleFlush();
    }
  }

  bool _passesFilter(LogcatEntry entry) {
    if (entry.rawLine.isEmpty && entry.message.isEmpty) return false;

    // Script markers are session-scoped. A Frida console must not display
    // Xposed output (and vice versa), even though both share Logcat.
    if (entry.source == 'frida' || entry.source == 'xposed') {
      return _sessionSource == 'all' || entry.source == _sessionSource;
    }

    // Core filter for JsxposedX 业务日志
    bool isRelevant =
        entry.rawLine.contains('JsxposedX') || // LogX 统一日志
        entry.rawLine.contains('FridaInjectTest') || // Frida 注入日志
        entry.rawLine.contains('HookJsXposed') || // Xposed Hook 日志
        entry.rawLine.contains('JsxposedProvider') || // Provider 日志
        entry.rawLine.contains('AttachHooker') || // Hook 附加日志
        entry.rawLine.contains('StatusManagement') || // 状态管理日志
        entry.rawLine.contains('AuditLogProvider');

    // 包含目标应用包名的日志也显示
    if (_targetPackage.isNotEmpty && entry.rawLine.contains(_targetPackage)) {
      isRelevant = true;
    }

    return isRelevant;
  }

  static final _threadtimeRegex = RegExp(
    r'^(\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)\s+(\d+)\s+(\d+)\s+([VDIWEF])\s+([^:]+):\s?(.*)$',
  );
  static final _timeRegex = RegExp(
    r'^(\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)\s+([VDIWEF])\/([^(:]+)(?:\(\s*(\d+)\))?:\s?(.*)$',
  );

  LogcatEntry _parseLine(String line) {
    final threadMatch = _threadtimeRegex.firstMatch(line);
    final timeMatch = _timeRegex.firstMatch(line);
    final timestamp = threadMatch?.group(1) ?? timeMatch?.group(1) ?? '';
    final pid = threadMatch?.group(2) ?? timeMatch?.group(4) ?? '';
    final tid = threadMatch?.group(3) ?? '';
    final level = threadMatch?.group(4) ?? timeMatch?.group(2) ?? 'I';
    final tag = (threadMatch?.group(5) ?? timeMatch?.group(3) ?? '').trim();
    final message = threadMatch?.group(6) ?? timeMatch?.group(5) ?? line;

    var entry = LogcatEntry(
      rawLine: line,
      level: level,
      timestamp: timestamp,
      tag: tag,
      message: message,
      source: _sourceForTag(tag),
      sessionId: _sessionId,
      pid: pid,
      tid: tid,
    );

    final marker = _parseStructuredMessage(message);
    if (marker != null) {
      entry = LogcatEntry(
        rawLine: line,
        level: marker.level,
        timestamp: timestamp,
        tag: tag,
        message: marker.message,
        source: marker.source,
        scriptName: marker.scriptName,
        sessionId: _sessionId,
        pid: pid,
        tid: tid,
        stackTrace: marker.stackTrace,
      );
    }
    return entry;
  }

  String _sourceForTag(String tag) {
    final normalized = tag.toLowerCase();
    if (normalized.contains('frida')) return 'frida';
    if (normalized.contains('jsxposed')) return 'framework';
    if (normalized.contains('xposed') || normalized.contains('lsposed')) {
      return 'xposed';
    }
    if (_targetPackage.isNotEmpty &&
        normalized.contains(_targetPackage.toLowerCase())) {
      return 'app';
    }
    return 'system';
  }

  _StructuredLog? _parseStructuredMessage(String message) {
    const prefix = 'JXCONSOLE|v1|';
    if (!message.startsWith(prefix)) return null;
    final parts = message.split('|');
    if (parts.length < 6) return null;
    final source = parts[2];
    final scriptName = _decode(parts[3]);
    final level = parts[4].isEmpty ? 'I' : parts[4];
    final decodedMessage = _decode(parts.sublist(5).join('|'));
    final stackSeparator = decodedMessage.indexOf('\n--STACK--\n');
    if (stackSeparator < 0) {
      return _StructuredLog(source, scriptName, level, decodedMessage, '');
    }
    return _StructuredLog(
      source,
      scriptName,
      level,
      decodedMessage.substring(0, stackSeparator),
      decodedMessage.substring(stackSeparator + '\n--STACK--\n'.length),
    );
  }

  String _decode(String value) {
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }
}

class _StructuredLog {
  final String source;
  final String scriptName;
  final String level;
  final String message;
  final String stackTrace;

  const _StructuredLog(
    this.source,
    this.scriptName,
    this.level,
    this.message,
    this.stackTrace,
  );
}
