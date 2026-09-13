import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_compact_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class ToolCallingIndicator extends HookWidget {
  final String content;

  const ToolCallingIndicator({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    final scale = AiChatCompactScope.scaleOf(context);
    final animationController = useAnimationController(
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    final toolName = content.contains('get_manifest')
        ? context.l10n.aiToolNameManifest
        : content.contains('decompile')
        ? context.l10n.aiToolNameDecompile
        : content.contains('smali')
        ? context.l10n.aiToolNameSmali
        : content.contains('search')
        ? context.l10n.aiToolNameSearch
        : content.contains('package')
        ? context.l10n.aiToolNamePackages
        : content.contains('class')
        ? context.l10n.aiToolNameClasses
        : null;

    final normalized = content.toLowerCase();
    final status = normalized.contains('argument') || normalized.contains('参数')
        ? (context.isZh ? '正在准备工具参数' : 'Preparing tool arguments')
        : normalized.contains('execute') || normalized.contains('执行')
        ? (context.isZh ? '工具执行中' : 'Tool is running')
        : (context.isZh ? '正在调用工具' : 'Calling tool');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RotationTransition(
          turns: animationController,
          child: Icon(
            Icons.settings_outlined,
            size: 16 * scale,
            color: context.colorScheme.primary,
          ),
        ),
        SizedBox(width: 8 * scale),
        Text(
          toolName != null
              ? '$status · ${context.l10n.aiToolReading(toolName)}'
              : status,
          style: TextStyle(
            fontSize: 13 * scale,
            color: context.colorScheme.primary,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}
