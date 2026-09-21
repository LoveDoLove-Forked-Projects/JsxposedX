import 'dart:async';

import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_session_init_state.dart';
import 'package:JsxposedX/features/ai/presentation/providers/environments/apk_reverse_chat_environment_provider.dart';
import 'package:JsxposedX/features/ai/presentation/providers/runtime/ai_chat_runtime_provider.dart';
import 'package:JsxposedX/features/ai/presentation/runtime/ai_chat_environment_initializer.dart';
import 'package:JsxposedX/features/ai/presentation/states/ai_chat_runtime_state.dart';
import 'package:JsxposedX/features/ai/presentation/states/ai_chat_session_view.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_input.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_chat_list.dart';
import 'package:JsxposedX/features/ai/presentation/widgets/ai_conversation_drawer.dart';

import 'package:JsxposedX/features/apk_analysis/presentation/pages/apk_analysis_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AiReversePage extends HookConsumerWidget {
  const AiReversePage({super.key, required this.packageName});

  final String packageName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatNotifier = ref.read(
      aiChatRuntimeProvider(packageName: packageName).notifier,
    );
    final chatState = ref.watch(
      aiChatRuntimeProvider(packageName: packageName),
    );
    final sessions = ref
        .read(aiChatRuntimeProvider(packageName: packageName).notifier)
        .getSessions();
    final isZh = context.isZh;
    final environment = ref.watch(
      apkReverseChatEnvironmentProvider(
        ApkReverseChatEnvironmentArgs(packageName: packageName, isZh: isZh),
      ),
    );
    final scrollController = useScrollController();
    final pageController = usePageController();
    final sessionId = useState<String>('');
    final currentPage = useState(0);
    final scaffoldKey = useMemoized(() => GlobalKey<ScaffoldState>());

    Future<void> initializeReverseSession() async {
      sessionId.value = '';
      SmartDialog.showLoading();
      await initializeAiChatEnvironment(
        notifier: chatNotifier,
        environment: environment,
        initErrorPrefix: '逆向会话初始化失败',
        onSnapshotReady: (_) {
          sessionId.value = environment.sessionId ?? '';
        },
      );
      SmartDialog.dismiss();
    }

    final followScheduled = useRef(false);
    useEffect(() {
      const followThreshold = 80.0;
      final subscription = chatNotifier.streamingContentStream.listen((
        content,
      ) {
        if (content.isEmpty || !scrollController.hasClients) {
          return;
        }
        if (scrollController.offset > followThreshold) {
          return;
        }
        if (followScheduled.value) return;
        followScheduled.value = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          followScheduled.value = false;
          if (!scrollController.hasClients ||
              scrollController.offset > followThreshold) {
            return;
          }
          scrollController.jumpTo(0.0);
        });
      });
      return subscription.cancel;
    }, [chatNotifier, scrollController]);

    useEffect(() {
      Future.microtask(initializeReverseSession);
      return () => unawaited(environment.dispose());
    }, [environment]);

    final lastBackPressTime = useRef<DateTime?>(null);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final now = DateTime.now();
        final last = lastBackPressTime.value;
        if (last != null && now.difference(last) < const Duration(seconds: 2)) {
          Navigator.of(context).pop();
        } else {
          lastBackPressTime.value = now;
          ToastMessage.show(context.l10n.pressBackAgainToExit);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: context.isDark
              ? context.colorScheme.surfaceContainerHigh
              : context.colorScheme.surface,
          elevation: 4,
          shadowColor: Colors.black.withOpacity(0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(24.r),
              bottomRight: Radius.circular(24.r),
            ),
          ),
          leading: _ChatDrawerButton(
            sessionCount: sessions.length,
            onTap: () => scaffoldKey.currentState?.openDrawer(),
          ),
          title: Text(
            chatState.currentSessionId != null && sessions.isNotEmpty
                ? sessions
                      .firstWhere(
                        (session) => session.id == chatState.currentSessionId,
                        orElse: () => sessions.first,
                      )
                      .name
                : context.l10n.aiNewSession,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: context.textTheme.titleLarge?.color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        key: scaffoldKey,
        drawer: AiConversationDrawer(
          packageName: packageName,
          onSessionSelected: (id) => chatNotifier.switchSession(id),
        ),
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              _ReverseInitBanner(
                chatState: chatState,
                onRetry: initializeReverseSession,
              ),
              Expanded(
                child: PageView(
                  controller: pageController,
                  onPageChanged: (page) => currentPage.value = page,
                  children: [
                    AiChatList(
                      messages: chatState.visibleViewMessages,
                      scrollController: scrollController,
                      packageName: packageName,
                      customTitle: chatState.currentSessionId == null
                          ? (isZh ? '请选择一个对话' : 'Choose a conversation')
                          : null,
                      customSubtitle: chatState.currentSessionId == null
                          ? (isZh
                                ? '点击左上角的对话图标打开聊天列表'
                                : 'Tap the conversation icon to open your chats')
                          : null,
                    ),
                    ApkAnalysisPage(
                      packageName: packageName,
                      sessionId: sessionId.value,
                    ),
                  ],
                ),
              ),
              if (currentPage.value == 0)
                AiChatInput(
                  packageName: packageName,
                  onRetryInitialization: initializeReverseSession,
                  onOpenAnalysis: () {
                    currentPage.value = 1;
                    pageController.animateToPage(
                      1,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReverseInitBanner extends StatelessWidget {
  const _ReverseInitBanner({required this.chatState, required this.onRetry});

  final AiChatRuntimeState chatState;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (chatState.sessionInitState == AiSessionInitState.ready) {
      return const SizedBox.shrink();
    }
    final isInitializing =
        chatState.sessionInitState == AiSessionInitState.initializing;
    final backgroundColor = isInitializing
        ? context.colorScheme.primaryContainer
        : context.colorScheme.errorContainer;
    final foregroundColor = isInitializing
        ? context.colorScheme.onPrimaryContainer
        : context.colorScheme.onErrorContainer;
    final message = isInitializing
        ? context.l10n.aiReverseSessionInitializingBanner
        : (chatState.error ?? context.l10n.aiReverseSessionInitFailedBanner);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isInitializing
                ? Icons.hourglass_top_rounded
                : Icons.error_outline_rounded,
            color: foregroundColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: foregroundColor)),
          ),
          if (!isInitializing)
            TextButton(
              onPressed: onRetry,
              child: Text(
                context.l10n.retry,
                style: TextStyle(color: foregroundColor),
              ),
            ),
        ],
      ),
    );
  }
}



/// 对话列表入口图标（位于 app icon 左边）
class _ChatDrawerButton extends StatelessWidget {
  const _ChatDrawerButton({required this.sessionCount, this.onTap});

  final int sessionCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44.w,
      height: 44.w,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: context.isZh ? '对话列表' : 'Conversations',
            onPressed: onTap,
            padding: EdgeInsets.zero,
            icon: Icon(
              Icons.menu_rounded,
              size: 25.sp,
              color: context.colorScheme.primary,
            ),
          ),
          if (sessionCount > 0)
            Positioned(
              top: 2.w,
              right: 1.w,
              child: IgnorePointer(
                child: Container(
                  constraints: BoxConstraints(minWidth: 16.w, minHeight: 16.w),
                  padding: EdgeInsets.symmetric(horizontal: 4.w),
                  decoration: BoxDecoration(
                    color: context.colorScheme.primary,
                    borderRadius: BorderRadius.circular(999.r),
                    border: Border.all(
                      color: context.theme.scaffoldBackgroundColor,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    sessionCount > 99 ? '99+' : '$sessionCount',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.colorScheme.onPrimary,
                      fontSize: 9.sp,
                      fontWeight: FontWeight.bold,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
