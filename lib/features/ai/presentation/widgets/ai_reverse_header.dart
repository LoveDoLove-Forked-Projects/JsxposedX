import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/ai/presentation/providers/runtime/ai_chat_runtime_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AiReverseHeader extends HookConsumerWidget {
  final String packageName;
  final VoidCallback? onSessionDrawerTap;

  const AiReverseHeader({
    super.key,
    required this.packageName,
    this.onSessionDrawerTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(
      aiChatRuntimeProvider(packageName: packageName),
    );
    final sessions = ref
        .read(aiChatRuntimeProvider(packageName: packageName).notifier)
        .getSessions();

    return Container(
      padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 16.h),
      decoration: BoxDecoration(
        color: context.isDark
            ? context.colorScheme.surfaceContainerHigh
            : context.colorScheme.surface,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24.r),
          bottomRight: Radius.circular(24.r),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _ChatDrawerButton(
            sessionCount: sessions.length,
            onTap: onSessionDrawerTap,
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Text(
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

class _HeaderActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _HeaderActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: Container(
          padding: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
            color: (color ?? context.colorScheme.primary).withValues(
              alpha: 0.1,
            ),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Icon(
            icon,
            size: 20.sp,
            color: color ?? context.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
