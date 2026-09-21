import 'package:JsxposedX/features/ai/domain/contracts/ai_chat_tool_handler.dart';
import 'package:JsxposedX/features/ai/domain/environments/ai_tool_runtime_context.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_tool_call.dart';

// ═══ 基类 ═══

abstract class SystemControlHandler implements AiChatToolHandler {
  const SystemControlHandler(this.context);

  final ApkReverseToolRuntimeContext context;

  String get _pkg => context.packageName;

  bool get _isZh => context.isZh;
}

// ═══ D1. get_device_info（P1） ═══

class GetDeviceInfoHandler extends SystemControlHandler {
  const GetDeviceInfoHandler(super.context);

  @override
  String get toolName => 'get_device_info';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    final buf = StringBuffer();
    buf.writeln(_isZh ? '## 设备信息\n' : '## Device Info\n');

    buf.writeln(_isZh
        ? '- **目标包**: $_pkg'
        : '- **Target**: $_pkg');

    buf.writeln(
      _isZh
          ? '- **设备架构/ABI**: arm64-v8a (默认)'
          : '- **Arch/ABI**: arm64-v8a (default)',
    );
    buf.writeln(
      _isZh
          ? '- **Android 版本**: 需 root shell 获取'
          : '- **Android Version**: requires root shell',
    );
    buf.writeln(
      _isZh
          ? '- **Root 状态**: 需 root 权限检测'
          : '- **Root Status**: requires root check',
    );
    buf.writeln(
      _isZh
          ? '- **Zygisk/LSPosed**: 需模块检测'
          : '- **Zygisk/LSPosed**: requires module detection',
    );
    buf.writeln(
      _isZh
          ? '\n> 注：部分信息需 native 桥接支持，开发中。'
          : '\n> Note: Some info requires native bridge support, under development.',
    );

    return buf.toString().trimRight();
  }
}

// ═══ D2. launch/stop_target_app（P1） ═══

class TargetAppControlHandler extends SystemControlHandler {
  const TargetAppControlHandler(super.context);

  @override
  String get toolName => 'target_app_control';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    if (_pkg.isEmpty) {
      throw ArgumentError(
        _isZh ? '当前无目标应用' : 'No target app',
      );
    }

    final action = call.getString('action', 'launch');

    switch (action) {
      case 'launch':
        return _isZh
            ? '拉起 $_pkg —— 需 root shell 支持，开发中'
            : 'Launch $_pkg —— requires root shell, under development';
      case 'stop':
        return _isZh
            ? '停止 $_pkg —— 需 root shell 支持，开发中'
            : 'Stop $_pkg —— requires root shell, under development';
      case 'restart':
        return _isZh
            ? '重启 $_pkg —— 需 root shell 支持，开发中'
            : 'Restart $_pkg —— requires root shell, under development';
      default:
        throw ArgumentError(
          _isZh ? 'action 仅支持 launch/stop/restart' : 'action must be launch/stop/restart',
        );
    }
  }
}

// ═══ D3. list_installed_apps（P2） ═══

class ListInstalledAppsHandler extends SystemControlHandler {
  const ListInstalledAppsHandler(super.context);

  @override
  String get toolName => 'list_installed_apps';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    return _isZh
        ? '已装应用列表功能需包管理器查询支持，开发中。'
        : 'Installed apps listing requires package manager query, under development.';
  }
}

// ═══ D4. read_target_logs（P2） ═══

class ReadTargetLogsHandler extends SystemControlHandler {
  const ReadTargetLogsHandler(super.context);

  @override
  String get toolName => 'read_target_logs';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    if (_pkg.isEmpty) {
      throw ArgumentError(
        _isZh ? '当前无目标应用' : 'No target app',
      );
    }

    return _isZh
        ? '日志读取功能需 root shell 支持，开发中。请先用 get_script_logs 查看脚本日志。'
        : 'Log reading requires root shell, under development. Use get_script_logs for script logs first.';
  }
}