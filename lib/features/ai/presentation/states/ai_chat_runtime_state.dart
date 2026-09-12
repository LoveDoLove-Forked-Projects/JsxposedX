import 'package:JsxposedX/features/ai/domain/contracts/ai_chat_tool_executor_contract.dart';
import 'package:JsxposedX/features/ai/domain/contracts/ai_chat_tools_spec.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_chat_session_context.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_response_issue.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_session_init_state.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';
import 'package:JsxposedX/features/ai/presentation/states/ai_chat_view_message.dart';
import 'package:JsxposedX/features/ai/presentation/states/ai_chat_session_view.dart';

class AiChatRuntimeState {
  const AiChatRuntimeState({
    this.standardMessages = const [],
    this.viewMessages = const [],
    this.sessions = const [],
    this.isStreaming = false,
    this.error,
    this.currentSessionId,
    this.systemPrompt,
    this.environmentVersion,
    this.visibleMessageCount = 10,
    this.hasOlderMessages = false,
    this.lastResponseIssue,
    this.sessionInitState = AiSessionInitState.ready,
    this.sessionContext = const AiChatSessionContext(),
    this.contextStats = const AiChatContextStats(),
    this.contextVersion = AiChatSessionContext.currentVersion,
    this.toolsSpec,
    this.toolExecutor,
  });

  final List<AiMessage> standardMessages;
  final List<AiChatViewMessage> viewMessages;
  final List<AiChatSessionView> sessions;
  final bool isStreaming;
  final String? error;
  final String? currentSessionId;
  final String? systemPrompt;
  final String? environmentVersion;
  final int visibleMessageCount;
  final bool hasOlderMessages;
  final AiResponseIssue? lastResponseIssue;
  final AiSessionInitState sessionInitState;
  final AiChatSessionContext sessionContext;
  final AiChatContextStats contextStats;
  final int contextVersion;
  final AiChatToolsSpec? toolsSpec;
  final AiChatToolExecutorContract? toolExecutor;
  List<AiChatViewMessage> get visibleViewMessages {
    if (viewMessages.length <= visibleMessageCount) {
      return List<AiChatViewMessage>.unmodifiable(viewMessages);
    }
    return List<AiChatViewMessage>.unmodifiable(
      viewMessages.sublist(viewMessages.length - visibleMessageCount),
    );
  }

  int get totalVisibleMessagesCount => viewMessages.length;

  bool get canSend =>
      !isStreaming &&
      sessionInitState != AiSessionInitState.initializing &&
      sessionInitState != AiSessionInitState.failed;

  bool get hasUserMessages =>
      standardMessages.any((message) => message.role == AiMessageRole.user);

  bool get canRetryLastTurn =>
      !isStreaming && hasUserMessages && lastResponseIssue != null;

  bool get canContinueGeneration =>
      canRetryLastTurn &&
      lastResponseIssue == AiResponseIssue.partialResponse &&
      !sessionContext.hasPendingToolPhase;

  bool get canResumeToolPhase =>
      canRetryLastTurn &&
      lastResponseIssue == AiResponseIssue.partialResponse &&
      sessionContext.hasPendingToolPhase;

  AiChatViewMessage? get latestSessionSummary {
    if (!sessionContext.sessionMemory.hasContent) {
      return null;
    }
    final buffer = StringBuffer('[session_summary]');
    void write(String title, List<String> items) {
      if (items.isEmpty) {
        return;
      }
      buffer
        ..writeln()
        ..writeln('$title：');
      for (final item in items) {
        buffer.writeln('- $item');
      }
    }

    write('历史诉求', sessionContext.sessionMemory.userGoals);
    write('已知结论', sessionContext.sessionMemory.confirmedFacts);
    write('工具发现', sessionContext.sessionMemory.toolFindings);
    write('待继续', sessionContext.sessionMemory.openHypotheses);
    write('阻塞', sessionContext.sessionMemory.blockers);
    return AiChatViewMessage(
      id: 'context-summary',
      role: 'system',
      content: buffer.toString().trim(),
    );
  }

  bool get hasSessionSummary => latestSessionSummary != null;

  AiChatRuntimeState copyWith({
    List<AiMessage>? standardMessages,
    List<AiChatViewMessage>? viewMessages,
    List<AiChatSessionView>? sessions,
    bool? isStreaming,
    Object? error = _runtimeStateSentinel,
    Object? currentSessionId = _runtimeStateSentinel,
    Object? systemPrompt = _runtimeStateSentinel,
    Object? environmentVersion = _runtimeStateSentinel,
    int? visibleMessageCount,
    bool? hasOlderMessages,
    Object? lastResponseIssue = _runtimeStateSentinel,
    AiSessionInitState? sessionInitState,
    AiChatSessionContext? sessionContext,
    AiChatContextStats? contextStats,
    int? contextVersion,
    Object? toolsSpec = _runtimeStateSentinel,
    Object? toolExecutor = _runtimeStateSentinel,
  }) {
    return AiChatRuntimeState(
      standardMessages: standardMessages ?? this.standardMessages,
      viewMessages: viewMessages ?? this.viewMessages,
      sessions: sessions ?? this.sessions,
      isStreaming: isStreaming ?? this.isStreaming,
      error: identical(error, _runtimeStateSentinel)
          ? this.error
          : error as String?,
      currentSessionId: identical(currentSessionId, _runtimeStateSentinel)
          ? this.currentSessionId
          : currentSessionId as String?,
      systemPrompt: identical(systemPrompt, _runtimeStateSentinel)
          ? this.systemPrompt
          : systemPrompt as String?,
      environmentVersion: identical(environmentVersion, _runtimeStateSentinel)
          ? this.environmentVersion
          : environmentVersion as String?,
      visibleMessageCount: visibleMessageCount ?? this.visibleMessageCount,
      hasOlderMessages: hasOlderMessages ?? this.hasOlderMessages,
      lastResponseIssue: identical(lastResponseIssue, _runtimeStateSentinel)
          ? this.lastResponseIssue
          : lastResponseIssue as AiResponseIssue?,
      sessionInitState: sessionInitState ?? this.sessionInitState,
      sessionContext: sessionContext ?? this.sessionContext,
      contextStats: contextStats ?? this.contextStats,
      contextVersion: contextVersion ?? this.contextVersion,
      toolsSpec: identical(toolsSpec, _runtimeStateSentinel)
          ? this.toolsSpec
          : toolsSpec as AiChatToolsSpec?,
      toolExecutor: identical(toolExecutor, _runtimeStateSentinel)
          ? this.toolExecutor
          : toolExecutor as AiChatToolExecutorContract?,
    );
  }
}

const Object _runtimeStateSentinel = Object();
