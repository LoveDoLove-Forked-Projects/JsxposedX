import 'dart:async';

import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/ai_chat_bubble.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_ai_bubble/memory_ai_bubble_container.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_ai_bubble/memory_ai_bubble_content.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_ai_bubble/memory_ai_bubble_state.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_ai_bubble/memory_ai_bubble_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class MemoryAiChatBubble extends BaseAiChatBubble {
  const MemoryAiChatBubble({
    super.key,
    required super.content,
    required super.role,
    super.isError,
    super.onRetry,
    super.isToolCalling,
    super.packageName,
    super.retryLabel,
    super.loadingHint,
    this.isToolResultBubble = false,
  });

  final bool isToolResultBubble;

  @override
  MemoryAiBubbleState createBubbleState() {
    return MemoryAiBubbleState(
      content: content,
      role: role,
      isError: isError,
      onRetry: onRetry,
      isToolCalling: isToolCalling,
      packageName: packageName,
      retryLabel: retryLabel,
      loadingHint: loadingHint,
      isToolResultBubble: isToolResultBubble,
    );
  }

  @override
  MemoryAiBubbleContainerPart createContainerPart() {
    return const MemoryAiBubbleContainerPart();
  }

  @override
  MemoryAiBubbleContentPart createContentPart() {
    return const MemoryAiBubbleContentPart();
  }

  @override
  MemoryAiBubbleToolbarPart createToolbarPart() {
    return const MemoryAiBubbleToolbarPart();
  }
}

class MemoryAiStreamingChatBubble extends HookWidget {
  const MemoryAiStreamingChatBubble({
    super.key,
    required this.initialContent,
    required this.role,
    required this.isError,
    required this.isToolCalling,
    required this.isToolResultBubble,
    required this.retryLabel,
    required this.streamingContentStream,
    required this.streamingThinkingStream,
    this.onRetry,
    this.packageName,
  });

  final String initialContent;
  final String role;
  final bool isError;
  final bool isToolCalling;
  final bool isToolResultBubble;
  final String retryLabel;
  final Stream<String> streamingContentStream;
  final Stream<bool> streamingThinkingStream;
  final VoidCallback? onRetry;
  final String? packageName;

  @override
  Widget build(BuildContext context) {
    final content = useState(initialContent);
    final isThinking = useState(false);
    final cursorVisible = useState(true);

    useEffect(() {
      final timer = Timer.periodic(const Duration(milliseconds: 520), (_) {
        if (context.mounted) cursorVisible.value = !cursorVisible.value;
      });
      return timer.cancel;
    }, const []);

    useEffect(() {
      final subscription = streamingContentStream.listen((data) {
        if (!context.mounted) {
          return;
        }

        if (data != content.value) {
          content.value = data;
        }
      });
      return subscription.cancel;
    }, [streamingContentStream]);

    useEffect(() {
      final subscription = streamingThinkingStream.listen((value) {
        if (!context.mounted) {
          return;
        }
        isThinking.value = value;
      });
      return subscription.cancel;
    }, [streamingThinkingStream]);

    final cursor =
        !isThinking.value && content.value.isNotEmpty && cursorVisible.value
        ? '▍'
        : '';
    return AnimatedSize(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 120),
        reverseDuration: const Duration(milliseconds: 80),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: MemoryAiChatBubble(
          key: ValueKey(content.value),
          content: '${content.value}$cursor',
          role: role,
          isError: isError,
          isToolCalling: isToolCalling,
          isToolResultBubble: isToolResultBubble,
          retryLabel: retryLabel,
          onRetry: onRetry,
          packageName: packageName,
          loadingHint: isThinking.value ? _memoryLoadingHint(context) : null,
        ),
      ),
    );
  }
}

String _memoryLoadingHint(BuildContext context) {
  return context.isZh
      ? '正在整理当前内存上下文...'
      : 'Analyzing current memory context...';
}
