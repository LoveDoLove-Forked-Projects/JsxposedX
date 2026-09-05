import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';

abstract interface class AiTokenEstimator {
  int estimate(AiMessage message);
}

class ConservativeAiTokenEstimator implements AiTokenEstimator {
  const ConservativeAiTokenEstimator();

  @override
  int estimate(AiMessage message) {
    var characters = 0;
    for (final part in message.parts) {
      characters += switch (part) {
        AiTextPart(:final text) => text.length,
        AiReasoningPart(:final text) => text.length,
        AiImagePart() => 1024,
        AiToolCallPart(:final toolCall) =>
          toolCall.name.length + toolCall.arguments.toString().length,
        AiToolResultPart(:final toolResult) =>
          toolResult.name.length + toolResult.content.length,
      };
    }
    return 12 + (characters / 3).ceil();
  }
}

class AiChatContextBuilder {
  const AiChatContextBuilder({
    AiTokenEstimator tokenEstimator = const ConservativeAiTokenEstimator(),
  }) : _tokenEstimator = tokenEstimator;

  final AiTokenEstimator _tokenEstimator;

  List<AiMessage> build({
    required AiAssistantProfile assistant,
    required AiModelDefinition model,
    required List<AiMessage> messages,
    required String Function() idFactory,
    required DateTime now,
    String? environmentSystemPrompt,
  }) {
    final eligible = messages
        .where((message) => message.status == AiMessageStatus.completed)
        .map(
          (message) => assistant.contextPolicy.includeToolResults
              ? message
              : message.copyWith(
                  parts: message.parts
                      .where((part) => part is! AiToolResultPart)
                      .toList(growable: false),
                ),
        )
        .where((message) => message.parts.isNotEmpty)
        .toList(growable: false);

    final selected = switch (assistant.contextPolicy.mode) {
      AiContextMode.fullHistory => eligible,
      AiContextMode.recentMessages => _recentMessages(
        eligible,
        assistant.contextPolicy.recentMessageLimit,
      ),
      AiContextMode.tokenBudget => _withinTokenBudget(
        eligible,
        assistant.contextPolicy,
        model.limits.contextTokens,
      ),
    };

    final profilePrompt = assistant.systemPrompt?.trim();
    final environmentPrompt = environmentSystemPrompt?.trim();
    final systemPrompt = [
      if (environmentPrompt != null && environmentPrompt.isNotEmpty)
        environmentPrompt,
      if (profilePrompt != null && profilePrompt.isNotEmpty) profilePrompt,
    ].join('\n\n');
    if (systemPrompt.isEmpty) return selected;
    return [
      AiMessage(
        id: idFactory(),
        conversationId: messages.firstOrNull?.conversationId ?? '',
        role: model.capabilities.systemRole
            ? AiMessageRole.system
            : AiMessageRole.user,
        parts: [AiContentPart.text(systemPrompt)],
        createdAt: now,
      ),
      ...selected,
    ];
  }

  static List<AiMessage> _recentMessages(
    List<AiMessage> messages,
    int? configuredLimit,
  ) {
    if (messages.isEmpty) return messages;
    if (configuredLimit == null || configuredLimit <= 0) return messages;
    final limit = configuredLimit.clamp(1, messages.length);
    return messages.sublist(messages.length - limit);
  }

  List<AiMessage> _withinTokenBudget(
    List<AiMessage> messages,
    AiContextPolicy policy,
    int? contextTokens,
  ) {
    if (contextTokens == null || contextTokens <= 0) return messages;
    final budget = (contextTokens - policy.reservedOutputTokens).clamp(
      1,
      contextTokens,
    );
    final selected = <AiMessage>[];
    var used = 0;
    for (final message in messages.reversed) {
      final estimated = _tokenEstimator.estimate(message);
      if (selected.length >= policy.recentMessageMinimum &&
          used + estimated > budget) {
        break;
      }
      selected.add(message);
      used += estimated;
    }
    return selected.reversed.toList(growable: false);
  }
}
