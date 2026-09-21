import 'package:JsxposedX/features/ai/domain/contracts/ai_chat_tool_handler.dart';
import 'package:JsxposedX/features/ai/domain/environments/ai_tool_runtime_context.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_tool_call.dart';

// ═══ 基类 ═══

abstract class MultimodalHandler implements AiChatToolHandler {
  const MultimodalHandler(this.context);

  final ApkReverseToolRuntimeContext context;

  String get _pkg => context.packageName;

  bool get _isZh => context.isZh;
}

// ═══ E1. capture_screenshot（P2） ═══

class CaptureScreenshotHandler extends MultimodalHandler {
  const CaptureScreenshotHandler(super.context);

  @override
  String get toolName => 'capture_screenshot';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    return _isZh
        ? '截图功能需 root shell (screencap) + 视觉模型支持，开发中。'
        : 'Screenshot requires root shell (screencap) + vision model support, under development.';
  }
}

// ═══ E2. dump_ui_hierarchy（P2） ═══

class DumpUiHierarchyHandler extends MultimodalHandler {
  const DumpUiHierarchyHandler(super.context);

  @override
  String get toolName => 'dump_ui_hierarchy';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    return _isZh
        ? 'UI 层级 dump 需 uiautomator 或 Xposed 侧视图树遍历支持，开发中。'
        : 'UI hierarchy dump requires uiautomator or Xposed-side view tree traversal, under development.';
  }
}

// ═══ E3. extract_apk_resource（P2） ═══

class ExtractApkResourceHandler extends MultimodalHandler {
  const ExtractApkResourceHandler(super.context);

  @override
  String get toolName => 'extract_apk_resource';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    final resourcePath = call.getString('resourcePath');
    if (resourcePath.isEmpty) throw ArgumentError('resourcePath 不能为空');

    return _isZh
        ? 'APK 资源提取功能需 native 解包支持，开发中。'
        : 'APK resource extraction requires native unpacking, under development.';
  }
}