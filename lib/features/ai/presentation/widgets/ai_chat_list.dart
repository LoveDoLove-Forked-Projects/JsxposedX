import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/core/utils/url_helper.dart';
import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_response_issue.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_session_init_state.dart';
import 'package:JsxposedX/features/ai/presentation/providers/runtime/ai_chat_runtime_provider.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_bubble/ai_chat_bubble.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_compact_scope.dart';
import 'package:JsxposedX/features/ai/presentation/states/ai_chat_view_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef AiChatBubbleBuilder =
    Widget Function({
      required AiChatViewMessage message,
      required String retryLabel,
      required VoidCallback onRetry,
      required String packageName,
    });

typedef AiChatStreamingBubbleBuilder =
    Widget Function({
      required AiChatViewMessage message,
      required String retryLabel,
      required VoidCallback onRetry,
      required String packageName,
      required Stream<String> streamingContentStream,
      required Stream<bool> streamingThinkingStream,
    });

class AiChatList extends HookConsumerWidget {
  const AiChatList({
    super.key,
    required this.messages,
    required this.scrollController,
    required this.packageName,
    this.isCompact = false,
    this.systemPrompt,
    this.customTitle,
    this.customSubtitle,
    this.bubbleBuilder,
    this.streamingBubbleBuilder,
  });

  final List<AiChatViewMessage> messages;
  final ScrollController scrollController;
  final String packageName;
  final bool isCompact;
  final String? systemPrompt;
  final String? customTitle;
  final String? customSubtitle;
  final AiChatBubbleBuilder? bubbleBuilder;
  final AiChatStreamingBubbleBuilder? streamingBubbleBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scopeCompact = AiChatCompactScope.of(context);
    final scopeScale = AiChatCompactScope.scaleOf(context);
    final effectiveCompact = isCompact || scopeCompact;
    final chatState = ref.watch(
      aiChatRuntimeProvider(packageName: packageName),
    );
    final chatNotifier = ref.read(
      aiChatRuntimeProvider(packageName: packageName).notifier,
    );
    final showJumpToLatest = useState(false);

    useEffect(() {
      void updateJumpButton() {
        if (!scrollController.hasClients) return;
        final shouldShow = scrollController.offset > 120;
        if (showJumpToLatest.value != shouldShow) {
          showJumpToLatest.value = shouldShow;
        }
      }

      scrollController.addListener(updateJumpButton);
      updateJumpButton();
      return () => scrollController.removeListener(updateJumpButton);
    }, [scrollController]);

    if (messages.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final isCompactLayout =
              effectiveCompact || constraints.maxHeight < (220 * scopeScale);
          final horizontalPadding = (effectiveCompact ? 12 : 20) * scopeScale;
          final topPadding = (isCompactLayout ? 10 : 18) * scopeScale;
          final bottomPadding = 12 * scopeScale;
          final minHeight = constraints.maxHeight - topPadding - bottomPadding;

          return SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              topPadding,
              horizontalPadding,
              bottomPadding,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: minHeight > 0 ? minHeight : 0,
              ),
              child: Align(
                alignment: isCompactLayout
                    ? Alignment.topLeft
                    : Alignment.centerLeft,
                child: _EmptyChatState(isCompact: isCompactLayout),
              ),
            ),
          );
        },
      );
    }

    final totalVisibleCount = chatState.totalVisibleMessagesCount;
    final hasMore =
        chatState.hasOlderMessages || messages.length < totalVisibleCount;
    final remainingCount =
        (totalVisibleCount - messages.length).clamp(0, totalVisibleCount) +
        (chatState.hasOlderMessages ? 1 : 0);
    final reversedMessages = messages.reversed.toList(growable: false);
    final retryLabel =
        chatState.lastResponseIssue == AiResponseIssue.partialResponse
        ? (chatState.sessionContext.hasPendingToolPhase
              ? context.l10n.aiResumeToolPhase
              : context.l10n.aiContinue)
        : context.l10n.retry;

    final responseError =
        chatState.error != null &&
        !chatState.isStreaming &&
        chatState.lastResponseIssue != null &&
        chatState.sessionInitState == AiSessionInitState.ready;

    return Column(
      children: [
        if (responseError)
          _ChatErrorBanner(
            detail: chatState.error!,
            retryLabel: retryLabel,
            onRetry: chatState.canRetryLastTurn
                ? chatNotifier.retryLastTurn
                : null,
          ),
        Expanded(
          child: Stack(
            children: [
              ListView.builder(
                controller: scrollController,
                reverse: true,
                padding: EdgeInsets.symmetric(
                  horizontal: (effectiveCompact ? 12 : 20) * scopeScale,
                  vertical: (effectiveCompact ? 6 : 10) * scopeScale,
                ),
                itemCount: reversedMessages.length + (hasMore ? 1 : 0),
                cacheExtent: 500,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                itemBuilder: (context, index) {
                  if (index == reversedMessages.length) {
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 8 * scopeScale),
                      child: TextButton(
                        onPressed: chatNotifier.loadMore,
                        child: Text(
                          context.l10n.aiShowMoreMessages(remainingCount),
                          style: TextStyle(color: context.colorScheme.primary),
                        ),
                      ),
                    );
                  }

                  final message = reversedMessages[index];
                  final shouldShowStreaming =
                      index == 0 &&
                      chatState.isStreaming &&
                      message.role == 'assistant' &&
                      !message.isError &&
                      !message.isToolResultBubble;

                  if (shouldShowStreaming) {
                    if (streamingBubbleBuilder != null) {
                      return RepaintBoundary(
                        child: streamingBubbleBuilder!(
                          message: message,
                          retryLabel: retryLabel,
                          onRetry: () =>
                              chatNotifier.retryByMessageId(message.id),
                          packageName: packageName,
                          streamingContentStream:
                              chatNotifier.streamingContentStream,
                          streamingThinkingStream:
                              chatNotifier.streamingThinkingStream,
                        ),
                      );
                    }
                    return _StreamingAiChatBubble(
                      key: ValueKey(message.id),
                      initialContent: message.content,
                      role: message.role,
                      isError: message.isError,
                      isToolCalling: message.isToolResultBubble,
                      retryLabel: retryLabel,
                      streamingContentStream:
                          chatNotifier.streamingContentStream,
                      streamingThinkingStream:
                          chatNotifier.streamingThinkingStream,
                      onRetry: () => chatNotifier.retryByMessageId(message.id),
                      packageName: packageName,
                    );
                  }

                  return RepaintBoundary(
                    child: bubbleBuilder != null
                        ? bubbleBuilder!(
                            message: message,
                            retryLabel: retryLabel,
                            onRetry: () =>
                                chatNotifier.retryByMessageId(message.id),
                            packageName: packageName,
                          )
                        : AiChatBubble(
                            key: ValueKey(message.id),
                            content: message.content,
                            role: message.role,
                            isError: message.isError,
                            isToolCalling:
                                message.isToolResultBubble &&
                                !message.content.startsWith('✅') &&
                                !message.content.startsWith('❌'),
                            retryLabel: retryLabel,
                            onRetry: () =>
                                chatNotifier.retryByMessageId(message.id),
                            packageName: packageName,
                          ),
                  );
                },
              ),
              Positioned(
                right: (effectiveCompact ? 14 : 20) * scopeScale,
                bottom: (effectiveCompact ? 10 : 16) * scopeScale,
                child: AnimatedScale(
                  scale: showJumpToLatest.value ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: IgnorePointer(
                    ignoring: !showJumpToLatest.value,
                    child: FloatingActionButton.small(
                      heroTag: null,
                      tooltip: context.isZh ? '回到最新消息' : 'Jump to latest',
                      onPressed: () {
                        scrollController.animateTo(
                          0,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                        );
                      },
                      child: const Icon(Icons.keyboard_double_arrow_down),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatErrorBanner extends HookWidget {
  const _ChatErrorBanner({
    required this.detail,
    required this.retryLabel,
    required this.onRetry,
  });

  final String detail;
  final String retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scale = AiChatCompactScope.scaleOf(context);
    final expanded = useState(false);
    final color = context.colorScheme.error;
    final canExpand = detail.length > 180;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(16 * scale, 8 * scale, 16 * scale, 0),
      padding: EdgeInsets.fromLTRB(12 * scale, 9 * scale, 8 * scale, 9 * scale),
      decoration: BoxDecoration(
        color: context.colorScheme.errorContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10 * scale),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 1 * scale),
            child: Icon(
              Icons.error_outline_rounded,
              size: 18 * scale,
              color: color,
            ),
          ),
          SizedBox(width: 8 * scale),
          Expanded(
            child: GestureDetector(
              onTap: canExpand ? () => expanded.value = !expanded.value : null,
              onLongPress: () async {
                await Clipboard.setData(ClipboardData(text: detail));
                if (context.mounted) {
                  ToastMessage.show(
                    context.isZh ? '错误详情已复制' : 'Error details copied',
                  );
                }
              },
              child: Text(
                detail,
                maxLines: expanded.value ? null : 3,
                overflow: expanded.value ? null : TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.colorScheme.onErrorContainer,
                  fontSize: 12 * scale,
                  height: 1.35,
                ),
              ),
            ),
          ),
          if (canExpand)
            IconButton(
              onPressed: () => expanded.value = !expanded.value,
              tooltip: expanded.value
                  ? (context.isZh ? '收起详情' : 'Collapse details')
                  : (context.isZh ? '展开详情' : 'Expand details'),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(
                minWidth: 30 * scale,
                minHeight: 30 * scale,
              ),
              icon: Icon(
                expanded.value ? Icons.expand_less : Icons.expand_more,
                size: 18 * scale,
                color: color,
              ),
            ),
          if (onRetry != null)
            IconButton(
              onPressed: onRetry,
              tooltip: retryLabel,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(
                minWidth: 30 * scale,
                minHeight: 30 * scale,
              ),
              icon: Icon(Icons.refresh_rounded, size: 18 * scale, color: color),
            ),
        ],
      ),
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState({required this.isCompact});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final scopeScale = AiChatCompactScope.scaleOf(context);
    final lines = context.isZh ? const ['欢迎使用'] : const ['Welcome'];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: (isCompact ? 24 : 28) * scopeScale,
              height: (isCompact ? 24 : 28) * scopeScale,
              decoration: BoxDecoration(
                color: context.colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: (isCompact ? 14 : 16) * scopeScale,
                color: context.colorScheme.primary,
              ),
            ),
            SizedBox(width: 8 * scopeScale),
            Text(
              context.isZh ? '助手' : 'Assistant',
              style: TextStyle(
                fontSize: (isCompact ? 11 : 12) * scopeScale,
                fontWeight: FontWeight.w700,
                color: context.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        SizedBox(height: (isCompact ? 8 : 10) * scopeScale),
        Container(
          constraints: BoxConstraints(
            maxWidth: (isCompact ? 240 : 320) * scopeScale,
          ),
          padding: EdgeInsets.fromLTRB(
            (isCompact ? 12 : 16) * scopeScale,
            (isCompact ? 10 : 14) * scopeScale,
            (isCompact ? 12 : 16) * scopeScale,
            (isCompact ? 10 : 14) * scopeScale,
          ),
          decoration: BoxDecoration(
            color: context.isDark
                ? context.colorScheme.surfaceContainer
                : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20 * scopeScale),
              topRight: Radius.circular(20 * scopeScale),
              bottomLeft: Radius.circular(6 * scopeScale),
              bottomRight: Radius.circular(20 * scopeScale),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12 * scopeScale,
                offset: Offset(0, 4 * scopeScale),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < lines.length; index++) ...[
                if (index > 0)
                  SizedBox(height: (isCompact ? 6 : 8) * scopeScale),
                Text(
                  lines[index],
                  style: TextStyle(
                    fontSize: (isCompact ? 13 : 15) * scopeScale,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: context.colorScheme.onSurface,
                  ),
                ),
              ],
              SizedBox(height: (isCompact ? 10 : 12) * scopeScale),
              OutlinedButton(
                onPressed: () {
                  UrlHelper.openUrlInBrowser(url: 'https://api.muxueai.pro');
                },
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: (isCompact ? 10 : 12) * scopeScale,
                    vertical: (isCompact ? 8 : 10) * scopeScale,
                  ),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: BorderSide(
                    color: context.colorScheme.primary.withValues(alpha: 0.35),
                  ),
                  foregroundColor: context.colorScheme.primary,
                  textStyle: TextStyle(
                    fontSize: (isCompact ? 11 : 12) * scopeScale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('官方满血GPT接口'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StreamingAiChatBubble extends HookWidget {
  const _StreamingAiChatBubble({
    super.key,
    required this.initialContent,
    required this.role,
    required this.isError,
    required this.isToolCalling,
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
  final String retryLabel;
  final Stream<String> streamingContentStream;
  final Stream<bool> streamingThinkingStream;
  final VoidCallback? onRetry;
  final String? packageName;

  @override
  Widget build(BuildContext context) {
    final content = useState(initialContent);
    final isThinking = useState(false);

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

    return RepaintBoundary(
      child: AiChatBubble(
        content: content.value,
        role: role,
        isError: isError,
        isToolCalling: isToolCalling,
        retryLabel: retryLabel,
        onRetry: onRetry,
        packageName: packageName,
        loadingHint: isThinking.value
            ? (context.isZh ? 'AI 正在深度思考...' : 'AI is thinking deeply...')
            : null,
      ),
    );
  }
}
