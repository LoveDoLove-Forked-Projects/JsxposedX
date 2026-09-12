import 'package:JsxposedX/features/ai/application/chat/ai_stream_snapshot.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_thinking_markup.dart';
import 'package:JsxposedX/features/ai/presentation/states/ai_chat_view_message.dart';

class AiChatViewMessageMapper {
  const AiChatViewMessageMapper();

  List<AiChatViewMessage> mapHistory(List<AiMessage> messages) {
    final display = <AiChatViewMessage>[];
    final pendingCalls = <String, AiToolCall>{};
    final pendingOrder = <String>[];

    void flushPending() {
      for (final id in pendingOrder) {
        final call = pendingCalls[id];
        if (call == null) continue;
        display.add(
          AiChatViewMessage(
            id: 'tool-pending-$id',
            role: AiMessageRole.assistant.name,
            content: '`${call.name}`',
            isToolResultBubble: true,
          ),
        );
      }
      pendingCalls.clear();
      pendingOrder.clear();
    }

    for (final message in messages) {
      if (message.role == AiMessageRole.system) continue;
      final calls = message.parts.whereType<AiToolCallPart>();
      if (message.role == AiMessageRole.assistant && calls.isNotEmpty) {
        flushPending();
        for (final part in calls) {
          final id = part.toolCall.id;
          if (id.isEmpty) continue;
          pendingCalls[id] = part.toolCall;
          pendingOrder.add(id);
        }
        continue;
      }

      final results = message.parts.whereType<AiToolResultPart>();
      if (message.role == AiMessageRole.tool && results.isNotEmpty) {
        for (final part in results) {
          final result = part.toolResult;
          final call = pendingCalls.remove(result.toolCallId);
          pendingOrder.remove(result.toolCallId);
          final name = call?.name.isNotEmpty == true ? call!.name : result.name;
          display.add(
            AiChatViewMessage(
              id: 'tool-result-${message.id}-${result.toolCallId}',
              role: AiMessageRole.assistant.name,
              content:
                  '${result.success ? '✅' : '❌'} `$name`:\n\n${result.content}',
              isError: !result.success,
              isToolResultBubble: true,
            ),
          );
        }
        continue;
      }

      flushPending();
      final text = message.parts
          .whereType<AiTextPart>()
          .map((part) => part.text)
          .join();
      final reasoning = message.parts
          .whereType<AiReasoningPart>()
          .map((part) => part.text)
          .join();
      final content = message.role == AiMessageRole.assistant
          ? AiThinkingMarkup.compose(thinking: reasoning, answer: text)
          : text;
      if (content.isEmpty && message.status != AiMessageStatus.failed) continue;
      display.add(
        AiChatViewMessage(
          id: message.id,
          role: message.role.name,
          content: content.isNotEmpty
              ? content
              : _failureDetail(message.failure),
          isError: message.status == AiMessageStatus.failed,
        ),
      );
    }
    flushPending();
    return List<AiChatViewMessage>.unmodifiable(display);
  }

  AiChatViewMessage mapStreaming({
    required String messageId,
    required AiStreamSnapshot snapshot,
  }) {
    return AiChatViewMessage(
      id: messageId,
      role: AiMessageRole.assistant.name,
      content: AiThinkingMarkup.compose(
        thinking: snapshot.reasoning,
        answer: snapshot.text,
      ),
      isError: snapshot.status == AiStreamStatus.failed,
    );
  }

  static String _failureDetail(AiFailure? failure) {
    if (failure == null) return '';
    return failure.messageKey.startsWith('ai.error.')
        ? failure.code.name
        : failure.messageKey;
  }
}
