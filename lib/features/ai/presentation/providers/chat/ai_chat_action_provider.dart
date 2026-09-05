import 'dart:async';

import 'package:JsxposedX/core/enums/ai_api_type.dart';
import 'package:JsxposedX/core/models/ai_config.dart';
import 'package:JsxposedX/core/models/ai_message.dart';
import 'package:JsxposedX/core/models/ai_session.dart';
import 'package:JsxposedX/core/networks/http_service.dart';
import 'package:JsxposedX/core/providers/pinia_provider.dart';
import 'package:JsxposedX/features/ai/application/chat/ai_chat_session_controller.dart';
import 'package:JsxposedX/features/ai/application/chat/ai_chat_session_environment.dart';
import 'package:JsxposedX/features/ai/application/chat/ai_chat_session_state.dart';
import 'package:JsxposedX/features/ai/data/datasources/chat/ai_chat_action_datasource.dart';
import 'package:JsxposedX/features/ai/data/repositories/chat/ai_chat_action_repository_impl.dart';
import 'package:JsxposedX/features/ai/domain/contracts/ai_chat_tool_executor_contract.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_chat_environment_snapshot.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_chat_session_context.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_response_issue.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_session_init_state.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_thinking_markup.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_tool_call.dart';
import 'package:JsxposedX/features/ai/domain/repositories/ai_conversation_repository.dart';
import 'package:JsxposedX/features/ai/domain/repositories/chat/ai_chat_action_repository.dart';
import 'package:JsxposedX/features/ai/domain/services/ai_multimodal_message_codec.dart';
import 'package:JsxposedX/features/ai/infrastructure/migration/legacy_ai_conversation_migrator.dart';
import 'package:JsxposedX/features/ai/presentation/providers/chat/ai_chat_query_provider.dart';
import 'package:JsxposedX/features/ai/presentation/providers/config/ai_config_query_provider.dart';
import 'package:JsxposedX/features/ai/presentation/providers/system/ai_system_providers.dart';
import 'package:JsxposedX/features/ai/presentation/states/ai_chat_action_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart'
    as standard;
import 'package:JsxposedX/features/ai/domain/ports/ai_tool_executor.dart';

part 'ai_chat_action_provider.g.dart';

@Riverpod(keepAlive: true)
Future<bool> aiStatus(Ref ref) async {
  final config = ref.watch(aiConfigProvider).value;
  if (config == null || config.apiUrl.isEmpty) return false;
  try {
    await ref.read(aiChatActionRepositoryProvider).testConnection(config);
    return true;
  } catch (_) {
    return false;
  }
}

@riverpod
AiChatActionDatasource aiChatActionDatasource(Ref ref) {
  return AiChatActionDatasource(
    httpService: ref.watch(httpServiceProvider),
    storage: ref.watch(piniaStorageLocalProvider),
  );
}

@riverpod
AiChatActionRepository aiChatActionRepository(Ref ref) {
  return AiChatActionRepositoryImpl(
    dataSource: ref.watch(aiChatActionDatasourceProvider),
  );
}

@riverpod
class AiChatAction extends _$AiChatAction {
  final StreamController<String> _streamingContentController =
      StreamController<String>.broadcast();
  final StreamController<bool> _streamingThinkingController =
      StreamController<bool>.broadcast();
  final Set<String> _migratedPackages = <String>{};

  AiChatSessionController? _sessionController;
  StreamSubscription<AiChatSessionState>? _sessionSubscription;
  AiChatSessionEnvironment? _environment;
  bool _sessionReady = false;
  bool _disposed = false;

  Stream<String> get streamingContentStream =>
      _streamingContentController.stream;

  Stream<bool> get streamingThinkingStream =>
      _streamingThinkingController.stream;

  @override
  AiChatActionState build({required String packageName}) {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      unawaited(_sessionSubscription?.cancel());
      unawaited(_sessionController?.close());
      unawaited(_streamingContentController.close());
      unawaited(_streamingThinkingController.close());
    });
    ref.listen(aiConfigProvider, (previous, next) {
      final before = previous?.value;
      final after = next.value;
      if (_disposed || after == null) return;
      if (before?.id == after.id &&
          before?.moduleName == after.moduleName &&
          before?.apiType == after.apiType &&
          before?.apiUrl == after.apiUrl) {
        return;
      }
      unawaited(_attachSession());
    });
    Future.microtask(_initializeSessions);
    return const AiChatActionState();
  }

  void beginSessionInitialization() {
    _clearStreaming();
    state = state.copyWith(
      sessionInitState: AiSessionInitState.initializing,
      error: null,
      lastResponseIssue: null,
      toolsSpec: null,
      toolExecutor: null,
    );
  }

  void markSessionReady() {
    state = state.copyWith(
      sessionInitState: AiSessionInitState.ready,
      error: null,
      lastResponseIssue: null,
    );
  }

  void markSessionInitFailed(String message) {
    _clearStreaming();
    state = state.copyWith(
      sessionInitState: AiSessionInitState.failed,
      error: message,
      lastResponseIssue: AiResponseIssue.toolInitError,
      isStreaming: false,
      toolsSpec: null,
      toolExecutor: null,
    );
  }

  void applyEnvironmentSnapshot(AiChatEnvironmentSnapshot snapshot) {
    state = state.copyWith(
      systemPrompt: snapshot.systemPrompt,
      environmentVersion: snapshot.environmentVersion,
      sessionInitState: snapshot.sessionInitState,
      error: snapshot.error,
      lastResponseIssue: snapshot.sessionInitState == AiSessionInitState.failed
          ? AiResponseIssue.toolInitError
          : null,
      toolsSpec: snapshot.toolsSpec,
      toolExecutor: snapshot.toolExecutor,
      sessionContext: state.sessionContext.copyWith(
        sessionRules: snapshot.systemPrompt,
      ),
    );
    final previous = _environment;
    _environment = _standardEnvironment(snapshot);
    if (previous?.version != _environment?.version ||
        previous?.scopeId != _environment?.scopeId) {
      unawaited(_attachSession());
    }
  }

  AiChatSessionEnvironment _standardEnvironment(
    AiChatEnvironmentSnapshot snapshot,
  ) {
    final apiType =
        ref.read(aiConfigProvider).value?.apiType ?? AiApiType.openai;
    final tools =
        snapshot.toolsSpec?.buildToolsJson(apiType: apiType) ??
        const <Map<String, dynamic>>[];
    return AiChatSessionEnvironment(
      id: 'reverse-${snapshot.scopeId}',
      scopeId: snapshot.scopeId,
      version: snapshot.environmentVersion,
      systemPrompt: snapshot.systemPrompt,
      tools: tools
          .map((raw) {
            final rawFunction = raw['function'];
            final function = rawFunction is Map
                ? Map<String, dynamic>.from(rawFunction)
                : Map<String, dynamic>.from(raw);
            final rawParameters =
                function['parameters'] ?? function['input_schema'];
            return standard.AiToolSpec(
              name: function['name']?.toString() ?? '',
              description: function['description']?.toString() ?? '',
              inputSchema: rawParameters is Map
                  ? Map<String, Object?>.from(rawParameters)
                  : const <String, Object?>{},
            );
          })
          .where((tool) => tool.name.isNotEmpty)
          .toList(growable: false),
      toolExecutor: snapshot.toolExecutor == null
          ? null
          : _LegacyStandardToolExecutor(snapshot.toolExecutor!),
    );
  }

  Future<void> _initializeSessions() async {
    try {
      final config = await ref.read(aiConfigProvider.future);
      await _migrateLegacySessions(config);
      final sessions = await getSessionsAsync();
      if (_disposed || sessions.isEmpty) return;
      final lastActive = await ref
          .read(aiChatQueryRepositoryProvider)
          .getLastActiveSessionId(packageName);
      if (_disposed) return;
      final initial =
          lastActive != null &&
              sessions.any((session) => session.id == lastActive)
          ? lastActive
          : sessions.first.id;
      await switchSession(initial);
    } catch (error) {
      if (_disposed) return;
      state = state.copyWith(error: 'AI 会话加载失败：$error', isStreaming: false);
    }
  }

  Future<List<AiSession>> getSessionsAsync() async {
    final config = ref.read(aiConfigProvider).value;
    if (config != null) await _migrateLegacySessions(config);
    final repository = ref.read(aiConversationRepositoryV2Provider);
    final conversations = <standard.AiConversation>[];
    AiConversationCursor? cursor;
    while (true) {
      final page = await repository.getConversations(
        before: cursor,
        limit: 100,
      );
      conversations.addAll(page);
      if (page.length < 100) break;
      final last = page.last;
      cursor = AiConversationCursor(updatedAt: last.updatedAt, id: last.id);
    }
    final sessions =
        conversations
            .where((conversation) => conversation.scopeId == packageName)
            .map(
              (conversation) => AiSession(
                id: conversation.id,
                name: conversation.title,
                packageName: packageName,
                lastUpdateTime: conversation.updatedAt.toLocal(),
                lastMessage: '',
              ),
            )
            .toList(growable: true)
          ..sort(
            (left, right) =>
                right.lastUpdateTime.compareTo(left.lastUpdateTime),
          );
    if (!_disposed) {
      state = state.copyWith(sessions: List<AiSession>.unmodifiable(sessions));
    }
    return sessions;
  }

  List<AiSession> getSessions() => state.sessions;

  Future<void> switchSession(String sessionId) async {
    if (state.isStreaming) {
      state = state.copyWith(error: '请先停止当前响应，再切换会话');
      return;
    }
    final conversation = await ref
        .read(aiConversationRepositoryV2Provider)
        .getConversation(sessionId);
    if (conversation == null || conversation.scopeId != packageName) {
      state = state.copyWith(error: '会话不存在或不属于当前逆向目标');
      return;
    }
    _clearStreaming();
    state = state.copyWith(
      currentSessionId: sessionId,
      protocolMessages: const [],
      messages: const [],
      visibleMessageCount: 10,
      hasOlderMessages: false,
      error: null,
      isStreaming: false,
      lastResponseIssue: null,
      sessionContext: AiChatSessionContext(
        sessionRules: state.systemPrompt ?? '',
      ),
      contextStats: const AiChatContextStats(),
      contextVersion: AiChatSessionContext.currentVersion,
    );
    await ref
        .read(aiChatActionRepositoryProvider)
        .saveLastActiveSessionId(packageName, sessionId);
    await _attachSession();
  }

  Future<void> _attachSession() async {
    final sessionId = state.currentSessionId;
    final environment = _environment;
    if (_disposed || sessionId == null || environment == null) return;

    _sessionReady = false;
    final previousSubscription = _sessionSubscription;
    final previousController = _sessionController;
    _sessionSubscription = null;
    _sessionController = null;
    await previousSubscription?.cancel();
    await previousController?.close();

    AiChatSessionController? controller;
    try {
      controller = AiChatSessionController(
        conversationId: sessionId,
        catalogRepository: ref.read(aiCatalogRepositoryProvider),
        conversationRepository: ref.read(aiConversationRepositoryV2Provider),
        startRun: ref.read(aiChatOrchestratorProvider).start,
        idFactory: const Uuid().v4,
        environment: environment,
      );
      _sessionController = controller;
      _sessionSubscription = controller.states.listen(_applySessionState);
      await controller.initialize();
      if (!identical(_sessionController, controller)) {
        await controller.close();
        return;
      }
      _sessionReady = true;
      _applySessionState(controller.state);
    } catch (error) {
      if (controller != null && !identical(_sessionController, controller)) {
        await controller.close();
        return;
      }
      _sessionReady = false;
      state = state.copyWith(
        error: '标准 AI 会话初始化失败：$error',
        isStreaming: false,
        lastResponseIssue: AiResponseIssue.toolInitError,
      );
    }
  }

  void _applySessionState(AiChatSessionState next) {
    if (_disposed || next.conversationId != state.currentSessionId) return;
    final protocol = next.messages
        .map(LegacyAiConversationMigrator.toLegacyMessage)
        .toList(growable: false);
    var display = _displayMessages(protocol);
    final snapshot = next.runSnapshot;
    if (snapshot != null) {
      final content = _displayContent(snapshot.reasoning, snapshot.text);
      final id = next.activeAssistantMessageId ?? 'standard-streaming';
      final streaming = AiMessage(id: id, role: 'assistant', content: content);
      final index = display.indexWhere((message) => message.id == id);
      if (index < 0) {
        display = [...display, streaming];
      } else {
        final updated = List<AiMessage>.from(display);
        updated[index] = streaming;
        display = updated;
      }
      _pushStreaming(content);
      _pushThinking(snapshot.reasoning.isNotEmpty && snapshot.text.isEmpty);
    }

    final streaming =
        next.phase == AiChatSessionPhase.requesting ||
        next.phase == AiChatSessionPhase.streaming ||
        next.phase == AiChatSessionPhase.cancelling;
    if (!streaming && snapshot == null) _clearStreaming();
    state = state.copyWith(
      sessions: _updatedSessions(next.conversation),
      protocolMessages: List<AiMessage>.unmodifiable(protocol),
      messages: List<AiMessage>.unmodifiable(display),
      hasOlderMessages: next.hasOlderMessages,
      isStreaming: streaming,
      error: next.failure == null
          ? null
          : LegacyAiConversationMigrator.describeAiFailure(next.failure!),
      lastResponseIssue: _issueFor(next.failure),
    );
  }

  List<AiSession> _updatedSessions(standard.AiConversation? conversation) {
    if (conversation == null) return state.sessions;
    final sessions = List<AiSession>.from(state.sessions);
    final index = sessions.indexWhere((item) => item.id == conversation.id);
    final mapped = AiSession(
      id: conversation.id,
      name: conversation.title,
      packageName: packageName,
      lastUpdateTime: conversation.updatedAt.toLocal(),
      lastMessage: '',
    );
    if (index < 0) {
      sessions.add(mapped);
    } else {
      sessions[index] = mapped;
    }
    sessions.sort(
      (left, right) => right.lastUpdateTime.compareTo(left.lastUpdateTime),
    );
    return List<AiSession>.unmodifiable(sessions);
  }

  AiResponseIssue? _issueFor(standard.AiFailure? failure) {
    if (failure == null || failure.code == standard.AiFailureCode.cancelled) {
      return null;
    }
    return switch (failure.code) {
      standard.AiFailureCode.protocolMalformed => AiResponseIssue.parseError,
      standard.AiFailureCode.protocolTruncated =>
        AiResponseIssue.partialResponse,
      _ => AiResponseIssue.networkError,
    };
  }

  void loadMore() {
    if (state.visibleMessageCount < state.messages.length) {
      state = state.copyWith(
        visibleMessageCount: (state.visibleMessageCount + 10).clamp(
          0,
          state.messages.length,
        ),
      );
      return;
    }
    if (state.hasOlderMessages && _sessionReady) {
      unawaited(_loadOlderMessages());
    }
  }

  Future<void> _loadOlderMessages() async {
    try {
      await _sessionController?.loadOlderMessages();
      if (_disposed) return;
      state = state.copyWith(
        visibleMessageCount: (state.visibleMessageCount + 10).clamp(
          0,
          state.messages.length,
        ),
      );
    } catch (error) {
      if (!_disposed) state = state.copyWith(error: '加载历史消息失败：$error');
    }
  }

  Future<void> createSession(String name) async {
    final config = ref.read(aiConfigProvider).value;
    if (config == null) {
      state = state.copyWith(error: 'AI 配置未加载');
      return;
    }
    await _migrateLegacySessions(config);
    final assistantId = 'legacy-assistant-${config.id}';
    final assistant = await ref
        .read(aiCatalogRepositoryProvider)
        .getAssistant(assistantId);
    if (assistant == null) {
      state = state.copyWith(error: '标准 AI 配置尚未就绪，无法创建会话');
      return;
    }
    final now = DateTime.now();
    final id = const Uuid().v4();
    final title = name.trim().isEmpty ? assistant.name : name.trim();
    await ref
        .read(aiConversationRepositoryV2Provider)
        .saveConversation(
          standard.AiConversation(
            id: id,
            title: title,
            assistantId: assistantId,
            environmentId: 'general',
            scopeId: packageName,
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
    state = state.copyWith(
      currentSessionId: id,
      sessions: [
        AiSession(
          id: id,
          name: title,
          packageName: packageName,
          lastUpdateTime: now,
          lastMessage: '',
        ),
        ...state.sessions,
      ],
      protocolMessages: const [],
      messages: const [],
      visibleMessageCount: 10,
      hasOlderMessages: false,
      error: null,
      isStreaming: false,
      lastResponseIssue: null,
      sessionContext: AiChatSessionContext(
        sessionRules: state.systemPrompt ?? '',
      ),
      contextStats: const AiChatContextStats(),
      contextVersion: AiChatSessionContext.currentVersion,
    );
    await ref
        .read(aiChatActionRepositoryProvider)
        .saveLastActiveSessionId(packageName, id);
    await _attachSession();
  }

  Future<void> send(String text) async {
    if (text.trim().isEmpty || state.isStreaming) return;
    if (state.currentSessionId == null) {
      await createSession(
        '新对话 ${DateTime.now().hour}:${DateTime.now().minute}',
      );
    }
    if (state.sessionInitState == AiSessionInitState.initializing) {
      state = state.copyWith(
        error: '逆向会话仍在初始化，请稍后再试。',
        lastResponseIssue: AiResponseIssue.toolInitError,
      );
      return;
    }
    if (state.sessionInitState == AiSessionInitState.failed) {
      state = state.copyWith(
        error: state.error ?? '逆向会话初始化失败，当前无法发送消息。',
        lastResponseIssue: AiResponseIssue.toolInitError,
      );
      return;
    }
    final controller = _readyController();
    if (controller == null) return;
    final model = controller.state.model;
    if (AiMultimodalMessageCodec.hasImageAttachments(text) &&
        model?.capabilities.visionInput == false &&
        _looksExplicitlyTextOnlyModel(model?.id ?? '')) {
      state = state.copyWith(
        error: '当前模型不支持图片理解，请切换到支持视觉的模型后再发送图片。',
        lastResponseIssue: AiResponseIssue.parseError,
      );
      return;
    }
    try {
      await controller.sendText(text);
    } catch (error) {
      if (!_disposed) {
        state = state.copyWith(
          error: '消息发送失败：$error',
          isStreaming: false,
          lastResponseIssue: AiResponseIssue.networkError,
        );
      }
    }
  }

  Future<void> editUserMessageAndResend({
    required String messageId,
    required String updatedText,
  }) async {
    if (state.isStreaming) return;
    final index = state.protocolMessages.indexWhere(
      (message) => message.id == messageId && message.role == 'user',
    );
    if (index < 0) return;
    final original = state.protocolMessages[index];
    if (!AiMultimodalMessageCodec.canEditText(original.content)) return;
    final content = AiMultimodalMessageCodec.replaceUserText(
      original.content,
      updatedText,
    );
    if (content.trim().isEmpty) return;
    final controller = _readyController();
    if (controller == null) return;
    try {
      await controller.editUserMessageAndResend(
        messageId: messageId,
        updatedText: content,
      );
    } catch (error) {
      if (!_disposed) {
        state = state.copyWith(
          error: '消息发送失败：$error',
          lastResponseIssue: AiResponseIssue.networkError,
        );
      }
    }
  }

  Future<void> retryByMessageId(String messageId) async {
    if (state.isStreaming) return;
    final controller = _readyController();
    if (controller == null) return;
    try {
      await controller.retryByMessageId(messageId);
    } catch (error) {
      if (!_disposed) {
        state = state.copyWith(
          error: '重试失败：$error',
          lastResponseIssue: AiResponseIssue.networkError,
        );
      }
    }
  }

  Future<void> retryLastTurn() async {
    if (state.isStreaming || !state.hasUserMessages) return;
    final lastUser = state.messages.lastWhere(
      (message) => message.role == 'user',
    );
    await retryByMessageId(lastUser.id);
  }

  Future<void> stopStreaming() async {
    if (!state.isStreaming) return;
    final controller = _readyController(showError: false);
    if (controller == null) {
      state = state.copyWith(
        error: '标准 AI 会话尚未就绪，当前没有可取消的请求。',
        isStreaming: false,
        lastResponseIssue: AiResponseIssue.toolInitError,
      );
      return;
    }
    controller.cancel();
  }

  Future<void> deleteSession(String sessionId) async {
    if (state.currentSessionId == sessionId && state.isStreaming) {
      state = state.copyWith(error: '请先停止当前响应，再删除会话');
      return;
    }
    if (state.currentSessionId == sessionId) {
      await _sessionSubscription?.cancel();
      await _sessionController?.close();
      _sessionSubscription = null;
      _sessionController = null;
      _sessionReady = false;
    }
    await ref
        .read(aiConversationRepositoryV2Provider)
        .deleteConversation(sessionId);
    final remaining = List<AiSession>.from(state.sessions)
      ..removeWhere((session) => session.id == sessionId);
    if (state.currentSessionId != sessionId) {
      state = state.copyWith(sessions: List.unmodifiable(remaining));
      return;
    }
    if (remaining.isNotEmpty) {
      state = state.copyWith(sessions: List.unmodifiable(remaining));
      await switchSession(remaining.first.id);
      return;
    }
    _clearStreaming();
    state = state.copyWith(
      sessions: const [],
      currentSessionId: null,
      messages: const [],
      protocolMessages: const [],
      visibleMessageCount: 10,
      hasOlderMessages: false,
      isStreaming: false,
      error: null,
      lastResponseIssue: null,
      sessionContext: AiChatSessionContext(
        sessionRules: state.systemPrompt ?? '',
      ),
      contextStats: const AiChatContextStats(),
      contextVersion: AiChatSessionContext.currentVersion,
    );
    await ref
        .read(aiChatActionRepositoryProvider)
        .clearLastActiveSessionId(packageName);
  }

  Future<void> deleteHistory() async {
    final id = state.currentSessionId;
    if (id != null) await deleteSession(id);
  }

  Future<void> clear() async {
    await createSession('新对话 ${DateTime.now().hour}:${DateTime.now().minute}');
  }

  void revealMessage(String messageId) {
    final index = state.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (index < 0) return;
    final required = state.messages.length - index;
    if (required > state.visibleMessageCount) {
      state = state.copyWith(visibleMessageCount: required);
    }
  }

  Future<String> testConnection(AiConfig config) {
    return ref.read(aiChatActionRepositoryProvider).testConnection(config);
  }

  AiChatSessionController? _readyController({bool showError = true}) {
    final controller = _sessionController;
    if (_sessionReady && controller != null) return controller;
    if (showError) {
      state = state.copyWith(
        error: '标准 AI 会话尚未就绪，请重试会话初始化。',
        lastResponseIssue: AiResponseIssue.toolInitError,
      );
    }
    return null;
  }

  Future<void> _migrateLegacySessions(AiConfig config) async {
    if (_migratedPackages.contains(packageName)) return;
    await ref.read(aiSystemMigrationProvider.future);
    await LegacyAiConversationMigrator(
      queryRepository: ref.read(aiChatQueryRepositoryProvider),
      catalogRepository: ref.read(aiCatalogRepositoryProvider),
      conversationRepository: ref.read(aiConversationRepositoryV2Provider),
    ).migratePackage(packageName: packageName, config: config);
    _migratedPackages.add(packageName);
  }

  List<AiMessage> _displayMessages(List<AiMessage> protocol) {
    final display = <AiMessage>[];
    final calls = <String, AiToolCall>{};
    final order = <String>[];

    void flushPending() {
      for (final id in order) {
        final call = calls[id];
        if (call == null) continue;
        display.add(
          AiMessage(
            id: 'tool-pending-$id',
            role: 'assistant',
            content: '⏳ `${call.name}`:',
            isToolResultBubble: true,
          ),
        );
      }
      calls.clear();
      order.clear();
    }

    for (final message in protocol) {
      if (message.isSessionSummary) continue;
      if (message.role == 'assistant' && message.hasToolCalls) {
        flushPending();
        for (final raw in message.toolCalls ?? const []) {
          final call = AiToolCall.fromJson(raw);
          if (call.id.isEmpty) continue;
          calls[call.id] = call;
          order.add(call.id);
        }
        continue;
      }
      if (message.role == 'tool') {
        final id = message.toolCallId;
        final call = id == null ? null : calls.remove(id);
        if (call != null) {
          order.remove(id);
          display.add(
            AiMessage(
              id: 'tool-result-${message.id}',
              role: 'assistant',
              content:
                  '${message.isError ? '❌' : '✅'} `${call.name}`:\n\n${message.content}',
              isToolResultBubble: true,
            ),
          );
        }
        continue;
      }
      flushPending();
      if (!message.shouldDisplayInChatList) continue;
      if (message.role == 'assistant' &&
          message.reasoningContent?.trim().isNotEmpty == true) {
        display.add(
          message.copyWith(
            content: _displayContent(
              message.reasoningContent!,
              message.content,
            ),
          ),
        );
      } else {
        display.add(message);
      }
    }
    flushPending();
    return display;
  }

  String _displayContent(String reasoning, String answer) {
    return AiThinkingMarkup.compose(thinking: reasoning, answer: answer);
  }

  void _pushStreaming(String content) {
    if (!_streamingContentController.isClosed) {
      _streamingContentController.add(content);
    }
  }

  void _pushThinking(bool value) {
    if (!_streamingThinkingController.isClosed) {
      _streamingThinkingController.add(value);
    }
  }

  void _clearStreaming() {
    _pushStreaming('');
    _pushThinking(false);
  }

  bool _looksExplicitlyTextOnlyModel(String modelName) {
    final normalized = modelName.toLowerCase();
    if (normalized.isEmpty) return false;
    return normalized.contains('text-embedding') ||
        normalized.contains('embedding') ||
        normalized.contains('rerank') ||
        normalized.contains('whisper') ||
        normalized.contains('tts');
  }
}

class _LegacyStandardToolExecutor implements AiToolExecutor {
  const _LegacyStandardToolExecutor(this._delegate);

  final AiChatToolExecutorContract _delegate;

  @override
  Future<standard.AiToolResult> execute(
    standard.AiToolCall call, {
    AiToolProgress? onProgress,
  }) async {
    final result = await _delegate.execute(
      AiToolCall(
        id: call.id,
        name: call.name,
        arguments: Map<String, dynamic>.from(call.arguments),
      ),
      onProgress: onProgress,
    );
    return standard.AiToolResult(
      toolCallId: result.toolCallId,
      name: result.toolName,
      success: result.success,
      content: result.content,
    );
  }
}
