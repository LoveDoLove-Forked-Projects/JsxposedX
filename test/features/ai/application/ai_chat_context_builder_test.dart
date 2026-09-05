import 'package:flutter_test/flutter_test.dart';
import 'package:JsxposedX/features/ai/application/chat/ai_chat_context_builder.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';

void main() {
  test(
    'uses a bounded recent-message context and drops orphan tool results',
    () {
      final messages = [
        for (var index = 0; index < 4; index++)
          AiMessage(
            id: 'message-$index',
            conversationId: 'conversation',
            role: AiMessageRole.user,
            parts: [
              AiContentPart.text('$index'),
              const AiContentPart.toolResult(
                toolResult: AiToolResult(
                  toolCallId: 'call',
                  name: 'tool',
                  success: true,
                  content: 'result',
                ),
              ),
            ],
            createdAt: _epoch.add(Duration(seconds: index)),
          ),
      ];
      final result = const AiChatContextBuilder().build(
        assistant: _assistant(
          contextPolicy: const AiContextPolicy(
            mode: AiContextMode.recentMessages,
            recentMessageLimit: 2,
            includeToolResults: false,
          ),
        ),
        model: _model(),
        messages: messages,
        idFactory: () => 'system',
        now: _epoch,
      );

      expect(result.map((message) => message.id), ['message-2', 'message-3']);
      expect(
        result.expand((message) => message.parts).whereType<AiToolResultPart>(),
        isEmpty,
      );
    },
  );

  test('uses user-role fallback when a model has no system role', () {
    final result = const AiChatContextBuilder().build(
      assistant: _assistant(systemPrompt: 'instructions'),
      model: _model(systemRole: false),
      messages: [_message('message')],
      idFactory: () => 'prompt',
      now: _epoch,
    );

    expect(result.first.id, 'prompt');
    expect(result.first.role, AiMessageRole.user);
    expect((result.first.parts.single as AiTextPart).text, 'instructions');
  });

  test('keeps the recent minimum when the token budget is exceeded', () {
    final result = AiChatContextBuilder(tokenEstimator: const _FixedEstimator())
        .build(
          assistant: _assistant(
            contextPolicy: const AiContextPolicy(
              reservedOutputTokens: 10,
              recentMessageMinimum: 2,
            ),
          ),
          model: _model(contextTokens: 20),
          messages: [_message('one'), _message('two'), _message('three')],
          idFactory: () => 'unused',
          now: _epoch,
        );

    expect(result.map((message) => message.id), ['two', 'three']);
  });

  test('keeps Responses function calls paired with their results', () {
    final call = AiMessage(
      id: 'assistant-call',
      conversationId: 'conversation',
      role: AiMessageRole.assistant,
      parts: const [
        AiContentPart.toolCall(
          toolCall: AiToolCall(id: 'fc_1', name: 'inspect', arguments: {}),
        ),
      ],
      createdAt: _epoch,
    );
    final resultMessage = AiMessage(
      id: 'tool-result',
      conversationId: 'conversation',
      role: AiMessageRole.tool,
      parts: const [
        AiContentPart.toolResult(
          toolResult: AiToolResult(
            toolCallId: 'fc_1',
            name: 'inspect',
            success: true,
            content: 'ok',
          ),
        ),
      ],
      createdAt: _epoch.add(const Duration(seconds: 1)),
    );
    final result = const AiChatContextBuilder().build(
      assistant: _assistant(
        contextPolicy: const AiContextPolicy(
          mode: AiContextMode.recentMessages,
          recentMessageLimit: 1,
        ),
      ),
      model: _model(),
      messages: [call, resultMessage],
      idFactory: () => 'unused',
      now: _epoch,
    );

    expect(result.map((message) => message.id), [
      'assistant-call',
      'tool-result',
    ]);
  });

  test('drops incomplete calls from a multi-call assistant turn', () {
    final assistantCall = AiMessage(
      id: 'assistant-call',
      conversationId: 'conversation',
      role: AiMessageRole.assistant,
      parts: const [
        AiContentPart.toolCall(
          toolCall: AiToolCall(
            id: 'fc_complete',
            name: 'inspect',
            arguments: {},
          ),
        ),
        AiContentPart.toolCall(
          toolCall: AiToolCall(id: 'fc_missing', name: 'search', arguments: {}),
        ),
      ],
      createdAt: _epoch,
    );
    final resultMessage = AiMessage(
      id: 'tool-result',
      conversationId: 'conversation',
      role: AiMessageRole.tool,
      parts: const [
        AiContentPart.toolResult(
          toolResult: AiToolResult(
            toolCallId: 'fc_complete',
            name: 'inspect',
            success: true,
            content: 'ok',
          ),
        ),
      ],
      createdAt: _epoch.add(const Duration(seconds: 1)),
    );

    final result = const AiChatContextBuilder().build(
      assistant: _assistant(),
      model: _model(),
      messages: [assistantCall, resultMessage],
      idFactory: () => 'unused',
      now: _epoch,
    );

    final calls = result
        .expand((message) => message.parts)
        .whereType<AiToolCallPart>()
        .map((part) => part.toolCall.id);
    final outputs = result
        .expand((message) => message.parts)
        .whereType<AiToolResultPart>()
        .map((part) => part.toolResult.toolCallId);
    expect(calls, ['fc_complete']);
    expect(outputs, ['fc_complete']);
  });

  test('keeps a complete tool exchange even with a legacy false flag', () {
    final call = AiMessage(
      id: 'assistant-call',
      conversationId: 'conversation',
      role: AiMessageRole.assistant,
      parts: const [
        AiContentPart.toolCall(
          toolCall: AiToolCall(id: 'fc_1', name: 'inspect', arguments: {}),
        ),
      ],
      createdAt: _epoch,
    );
    final output = AiMessage(
      id: 'tool-result',
      conversationId: 'conversation',
      role: AiMessageRole.tool,
      parts: const [
        AiContentPart.toolResult(
          toolResult: AiToolResult(
            toolCallId: 'fc_1',
            name: 'inspect',
            success: true,
            content: 'ok',
          ),
        ),
      ],
      createdAt: _epoch.add(const Duration(seconds: 1)),
    );

    final result = const AiChatContextBuilder().build(
      assistant: _assistant(
        contextPolicy: const AiContextPolicy(includeToolResults: false),
      ),
      model: _model(),
      messages: [call, output],
      idFactory: () => 'unused',
      now: _epoch,
    );

    expect(
      result.expand((message) => message.parts).whereType<AiToolCallPart>(),
      hasLength(1),
    );
    expect(
      result.expand((message) => message.parts).whereType<AiToolResultPart>(),
      hasLength(1),
    );
  });
}

AiAssistantProfile _assistant({
  String? systemPrompt,
  AiContextPolicy contextPolicy = const AiContextPolicy(),
}) {
  return AiAssistantProfile(
    id: 'assistant',
    name: 'Assistant',
    connectionId: 'connection',
    modelId: 'model',
    systemPrompt: systemPrompt,
    contextPolicy: contextPolicy,
    createdAt: _epoch,
    updatedAt: _epoch,
  );
}

AiModelDefinition _model({bool systemRole = true, int? contextTokens}) {
  return AiModelDefinition(
    id: 'model',
    connectionId: 'connection',
    displayName: 'Model',
    capabilities: AiModelCapabilities(systemRole: systemRole),
    limits: AiModelLimits(contextTokens: contextTokens),
  );
}

AiMessage _message(String id) => AiMessage(
  id: id,
  conversationId: 'conversation',
  role: AiMessageRole.user,
  parts: [AiContentPart.text(id)],
  createdAt: _epoch,
);

final _epoch = DateTime.utc(2026, 9, 5);

class _FixedEstimator implements AiTokenEstimator {
  const _FixedEstimator();

  @override
  int estimate(AiMessage message) => 8;
}
