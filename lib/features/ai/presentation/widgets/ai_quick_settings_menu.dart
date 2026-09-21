import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/core/models/ai_config.dart';
import 'package:JsxposedX/features/ai/domain/constants/builtin_ai_config.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';
import 'package:JsxposedX/features/ai/presentation/providers/config/ai_config_action_provider.dart';
import 'package:JsxposedX/features/ai/presentation/providers/config/ai_config_query_provider.dart';
import 'package:JsxposedX/features/ai/presentation/providers/runtime/ai_chat_runtime_provider.dart';
import 'package:JsxposedX/features/ai/presentation/providers/system/ai_system_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 聊天界面快捷设置菜单：模型选择 + 工具审批
class AiQuickSettingsMenu extends HookConsumerWidget {
  const AiQuickSettingsMenu({super.key});

  /// 显示快捷设置底部弹窗
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (_) => const AiQuickSettingsMenu(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 保持 aiConfigActionProvider 在菜单打开期间存活，避免异步操作时被 auto-dispose
    ref.watch(aiConfigActionProvider);
    final configAsync = ref.watch(aiConfigProvider);
    final assistantsAsync = ref.watch(aiAssistantsV2Provider);
    final isZh = context.isZh;

    return configAsync.when(
      loading: () => _LoadingContent(),
      error: (error, _) => _ErrorContent(
        message: error.toString(),
        onRetry: () => ref.invalidate(aiConfigProvider),
      ),
      data: (config) {
        final isBuiltin = isBuiltinAiConfig(config);
        final assistantId = 'legacy-assistant-${config.id}';
        final assistant = assistantsAsync.when(
          data: (list) => list.where((a) => a.id == assistantId).firstOrNull,
          loading: () => null,
          error: (_, __) => null,
        );

        return _MenuContent(
          config: config,
          isBuiltin: isBuiltin,
          assistant: assistant,
        );
      },
    );
  }
}

class _LoadingContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300.h,
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorContent extends StatelessWidget {
  const _ErrorContent({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200.h,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40.sp, color: Colors.red),
            SizedBox(height: 12.h),
            Text(message, style: TextStyle(fontSize: 13.sp)),
            SizedBox(height: 12.h),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _MenuContent extends HookConsumerWidget {
  const _MenuContent({
    required this.config,
    required this.isBuiltin,
    required this.assistant,
  });

  final AiConfig config;
  final bool isBuiltin;
  final AiAssistantProfile? assistant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isZh = context.isZh;
    final currentModelId = config.moduleName.trim();
    final currentApprovalMode =
        assistant?.toolPolicy.approvalMode ?? AiToolApprovalMode.riskyOnly;

    // Load available models
    final modelsAsync = ref.watch(aiModelsProvider);
    final modelsLoading = useState(false);

    // Track the selected model ID locally (for optimistic UI)
    final selectedModelId = useState(currentModelId);
    final selectedApprovalMode = useState(currentApprovalMode);
    final isSaving = useState(false);

    // Sync when config changes externally
    useEffect(() {
      selectedModelId.value = currentModelId;
      return null;
    }, [currentModelId]);

    useEffect(() {
      selectedApprovalMode.value = currentApprovalMode;
      return null;
    }, [currentApprovalMode]);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 24.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 36.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: context.theme.hintColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),
              SizedBox(height: 16.h),

              // Title
              Text(
                isZh ? '快捷设置' : 'Quick Settings',
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 4.h),
              Text(
                isBuiltin
                    ? (isZh
                          ? '内置配置 - $currentModelId'
                          : 'Built-in - $currentModelId')
                    : config.name,
                style: TextStyle(
                  fontSize: 12.sp,
                  color: context.theme.hintColor,
                ),
              ),
              SizedBox(height: 20.h),

              // ── Model Selection ──
              _sectionHeader(
                context,
                zh: '模型选择',
                en: 'Model Selection',
                icon: Icons.smart_toy_outlined,
              ),
              SizedBox(height: 8.h),
              modelsAsync.when(
                loading: () => Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.h),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16.w,
                        height: 16.w,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12.w),
                      Text(
                        isZh ? '加载模型列表...' : 'Loading models...',
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: context.theme.hintColor,
                        ),
                      ),
                    ],
                  ),
                ),
                error: (error, _) => Column(
                  children: [
                    _infoRow(
                      context,
                      icon: Icons.warning_amber_rounded,
                      iconColor: Colors.orange,
                      label: isZh ? '无法加载模型列表' : 'Cannot load models',
                      detail: error.toString(),
                    ),
                    SizedBox(height: 8.h),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          modelsLoading.value = true;
                          ref.invalidate(aiModelsProvider);
                          // Reset loading after a short delay
                          Future.delayed(
                            const Duration(seconds: 1),
                            () => modelsLoading.value = false,
                          );
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: Text(
                          isZh ? '重试加载' : 'Retry',
                          style: TextStyle(fontSize: 12.sp),
                        ),
                      ),
                    ),
                  ],
                ),
                data: (models) {
                  if (models.isEmpty) {
                    return _infoRow(
                      context,
                      icon: Icons.info_outline,
                      iconColor: context.theme.hintColor,
                      label: isZh ? '暂无可用模型' : 'No models available',
                    );
                  }

                  return Container(
                    decoration: BoxDecoration(
                      color: context.isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Column(
                      children: models.asMap().entries.map((entry) {
                        final index = entry.key;
                        final model = entry.value;
                        final isSelected = model.id == selectedModelId.value;
                        final isFirst = index == 0;
                        final isLast = index == models.length - 1;

                        return _ModelListItem(
                          model: model,
                          isSelected: isSelected,
                          isFirst: isFirst,
                          isLast: isLast,
                          isSaving: isSaving.value && isSelected,
                          onTap: () async {
                            if (isSelected || isSaving.value) return;
                            selectedModelId.value = model.id;
                            isSaving.value = true;
                            try {
                              final updatedConfig = config.copyWith(
                                moduleName: model.id,
                              );
                              await ref
                                  .read(aiConfigActionProvider.notifier)
                                  .updateConfig(updatedConfig);
                              if (!context.mounted) return;
                              ref.invalidate(aiChatRuntimeStatusProvider);
                              if (context.mounted) {
                                ToastMessage.show(
                                  isZh ? '模型已切换' : 'Model switched',
                                );
                              }
                            } catch (e) {
                              if (!context.mounted) return;
                              selectedModelId.value = currentModelId;
                              if (context.mounted) {
                                ToastMessage.show(
                                  isZh
                                      ? '切换失败: $e'
                                      : 'Switch failed: $e',
                                );
                              }
                            } finally {
                              if (context.mounted) {
                                isSaving.value = false;
                              }
                            }
                          },
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
              SizedBox(height: 24.h),

              // ── Tool Approval ──
              _sectionHeader(
                context,
                zh: '工具审批',
                en: 'Tool Approval',
                icon: Icons.security_outlined,
              ),
              SizedBox(height: 8.h),
              Text(
                isZh
                    ? '控制 AI 执行工具前是否需要用户确认'
                    : 'Control whether AI tool calls require user approval',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: context.theme.hintColor,
                ),
              ),
              SizedBox(height: 12.h),

              // Approval mode selector
              Container(
                padding: EdgeInsets.all(4.w),
                decoration: BoxDecoration(
                  color: context.isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.grey[200],
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Row(
                  children: AiToolApprovalMode.values.map((mode) {
                    final isSelected = mode == selectedApprovalMode.value;
                    final label = _approvalModeShortLabel(context, mode);
                    return Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          if (isSelected || isSaving.value) return;
                          selectedApprovalMode.value = mode;
                          isSaving.value = true;
                          try {
                            await ref
                                .read(aiConfigActionProvider.notifier)
                                .saveAssistantSettings(
                                  configId: config.id,
                                  systemPrompt: assistant?.systemPrompt,
                                  contextMode:
                                      assistant?.contextPolicy.mode ??
                                      AiContextMode.tokenBudget,
                                  recentMessageLimit: assistant
                                      ?.contextPolicy
                                      .recentMessageLimit,
                                  approvalMode: mode,
                                  maxToolRounds:
                                      assistant?.toolPolicy.maxRounds ?? 8,
                                );
                            if (context.mounted) {
                              ref.invalidate(aiAssistantsV2Provider);
                              ToastMessage.show(
                                isZh ? '审批模式已更新' : 'Approval mode updated',
                              );
                            }
                          } catch (e) {
                            if (!context.mounted) return;
                            selectedApprovalMode.value = currentApprovalMode;
                            if (context.mounted) {
                              ToastMessage.show(
                                isZh
                                    ? '更新失败: $e'
                                    : 'Update failed: $e',
                              );
                            }
                          } finally {
                            if (context.mounted) {
                              isSaving.value = false;
                            }
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: EdgeInsets.symmetric(vertical: 10.h),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (context.isDark
                                      ? context.colorScheme.primary
                                      : Colors.white)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10.r),
                            boxShadow: isSelected && !context.isDark
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.06,
                                      ),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? (context.isDark
                                        ? Colors.white
                                        : context.colorScheme.primary)
                                  : context.theme.hintColor,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              // Approval mode description
              SizedBox(height: 10.h),
              _approvalModeDescription(context, selectedApprovalMode.value),

              SizedBox(height: 20.h),

              // Available tools info
              _sectionHeader(
                context,
                zh: '可用工具列表',
                en: 'Available Tools',
                icon: Icons.build_outlined,
              ),
              SizedBox(height: 8.h),
              _infoRow(
                context,
                icon: Icons.info_outline,
                iconColor: context.colorScheme.primary.withValues(alpha: 0.7),
                label: isZh
                    ? '以下工具将受审批设置影响'
                    : 'The following tools are affected by approval settings',
                detail: isZh
                    ? '设置为"始终确认"时，AI调用任何工具都需要你手动批准'
                    : 'When set to "Always", every tool call requires your manual approval',
              ),

              SizedBox(height: 32.h),
            ],
          ),
        );
      },
    );
  }

  static String _approvalModeShortLabel(
    BuildContext context,
    AiToolApprovalMode mode,
  ) {
    if (context.isZh) {
      return switch (mode) {
        AiToolApprovalMode.never => '不审批',
        AiToolApprovalMode.riskyOnly => '仅危险',
        AiToolApprovalMode.always => '始终审批',
      };
    }
    return switch (mode) {
      AiToolApprovalMode.never => 'Never',
      AiToolApprovalMode.riskyOnly => 'Risky only',
      AiToolApprovalMode.always => 'Always',
    };
  }

  static Widget _approvalModeDescription(
    BuildContext context,
    AiToolApprovalMode mode,
  ) {
    final isZh = context.isZh;
    final (icon, text) = switch (mode) {
      AiToolApprovalMode.never => (
        Icons.speed_rounded,
        isZh
            ? 'AI 可直接执行所有工具，无需确认'
            : 'AI executes all tools directly without confirmation',
      ),
      AiToolApprovalMode.riskyOnly => (
        Icons.shield_outlined,
        isZh
            ? 'AI 调用工具时需你手动确认每个操作'
            : 'You must manually approve each tool call',
      ),
      AiToolApprovalMode.always => (
        Icons.verified_user_rounded,
        isZh
            ? '每次工具调用都需要你确认后再执行'
            : 'Every tool call requires your confirmation',
      ),
    };

    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: context.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(
          color: context.colorScheme.primary.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18.sp, color: context.colorScheme.primary),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5.sp,
                height: 1.4,
                color: context.textTheme.bodyMedium?.color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _sectionHeader(
    BuildContext context, {
    required String zh,
    required String en,
    required IconData icon,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18.sp, color: context.colorScheme.primary),
        SizedBox(width: 8.w),
        Text(
          context.isZh ? zh : en,
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w700,
            color: context.textTheme.titleMedium?.color,
          ),
        ),
      ],
    );
  }

  static Widget _infoRow(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String label,
    String? detail,
  }) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: context.isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.grey[50],
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(
          color: context.isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.grey[300]!,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18.sp, color: iconColor),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail != null) ...[
                  SizedBox(height: 4.h),
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 11.5.sp,
                      color: context.theme.hintColor,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelListItem extends StatelessWidget {
  const _ModelListItem({
    required this.model,
    required this.isSelected,
    required this.isFirst,
    required this.isLast,
    required this.isSaving,
    required this.onTap,
  });

  final dynamic model; // AiModel from config provider
  final bool isSelected;
  final bool isFirst;
  final bool isLast;
  final bool isSaving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final modelId = (model.id as String?) ?? '';
    final isZh = context.isZh;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.vertical(
        top: isFirst ? Radius.circular(12.r) : Radius.zero,
        bottom: isLast ? Radius.circular(12.r) : Radius.zero,
      ),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        decoration: BoxDecoration(
          border: !isLast
              ? Border(
                  bottom: BorderSide(
                    color: context.isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.grey[300]!,
                    width: 0.5,
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            // Radio indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20.w,
              height: 20.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? context.colorScheme.primary
                      : context.theme.hintColor.withValues(alpha: 0.4),
                  width: isSelected ? 6 : 2,
                ),
                color: isSelected ? null : Colors.transparent,
              ),
            ),
            SizedBox(width: 12.w),
            // Model info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          modelId,
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSelected
                                ? context.colorScheme.primary
                                : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSelected) ...[
                        SizedBox(width: 6.w),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6.w,
                            vertical: 2.h,
                          ),
                          decoration: BoxDecoration(
                            color: context.colorScheme.primary.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                          child: Text(
                            isZh ? '当前' : 'Active',
                            style: TextStyle(
                              fontSize: 10.sp,
                              color: context.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (model.contextTokens != null &&
                      (model.contextTokens as int?) != null) ...[
                    SizedBox(height: 2.h),
                    Text(
                      '${model.contextTokens} tokens',
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: context.theme.hintColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isSaving)
              SizedBox(
                width: 16.w,
                height: 16.w,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
