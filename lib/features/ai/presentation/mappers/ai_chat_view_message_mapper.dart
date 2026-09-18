import 'package:JsxposedX/features/ai/application/chat/ai_stream_snapshot.dart';
import 'package:JsxposedX/features/ai/application/chat/ai_transport_trace.dart';
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
              sourceMessageId: message.id,
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
          sourceMessageId: message.id,
          role: message.role.name,
          content: content.isNotEmpty
              ? content
              : _failureDetail(message.failure),
          isError: message.status == AiMessageStatus.failed,
          rawDetails: _historyDetails(message),
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
      sourceMessageId: messageId,
      role: AiMessageRole.assistant.name,
      content: AiThinkingMarkup.compose(
        thinking: snapshot.reasoning,
        answer: snapshot.text,
      ),
      isError: snapshot.status == AiStreamStatus.failed,
      rawDetails: _snapshotDetails(snapshot),
    );
  }

  static String _snapshotDetails(AiStreamSnapshot snapshot) {
    final buffer = StringBuffer()
      ..writeln('request_id: ${snapshot.requestId}')
      ..writeln('sequence: ${snapshot.sequence}')
      ..writeln('status: ${snapshot.status.name}');
    if (snapshot.finishReason != null) {
      buffer.writeln('finish_reason: ${snapshot.finishReason!.name}');
    }
    if (snapshot.usage != null) {
      buffer.writeln('usage: ${snapshot.usage}');
    }
    for (final call in snapshot.toolCalls) {
      buffer.writeln('tool: ${call.name} (${call.id ?? 'pending'})');
      if (call.argumentsJson.isNotEmpty) {
        buffer.writeln('arguments: ${call.argumentsJson}');
      }
    }
    if (snapshot.failure != null) {
      buffer.writeln('failure: ${snapshot.failure}');
    }
    if (snapshot.transportTrace case final trace?) {
      buffer
        ..writeln()
        ..writeln(_transportTraceDetails(trace));
    } else {
      buffer.writeln('transport: server did not provide metadata');
    }
    return buffer.toString().trim();
  }

  static String _historyDetails(AiMessage message) {
    final buffer = StringBuffer()
      ..writeln('message_id: ${message.id}')
      ..writeln('conversation_id: ${message.conversationId}')
      ..writeln('role: ${message.role.name}')
      ..writeln('status: ${message.status.name}')
      ..writeln('created_at: ${message.createdAt.toIso8601String()}');
    if (message.completedAt != null) {
      buffer.writeln('completed_at: ${message.completedAt!.toIso8601String()}');
    }
    if (message.usage != null) buffer.writeln('usage: ${message.usage}');
    if (message.failure != null) buffer.writeln('failure: ${message.failure}');
    buffer.writeln('transport: metadata unavailable for persisted message');
    return buffer.toString().trim();
  }

  static String _transportTraceDetails(AiTransportTrace trace) {
    final buffer = StringBuffer()
      ..writeln('transport:')
      ..writeln('  url: ${trace.requestUrl}')
      ..writeln(
        '  status: ${trace.statusCode?.toString() ?? 'server did not provide'}',
      )
      ..writeln(
        '  content_type: ${trace.contentType ?? 'server did not provide'}',
      )
      ..writeln(
        '  request_start: ${trace.requestStartTime?.toIso8601String() ?? 'server did not provide'}',
      )
      ..writeln(
        '  request_end: ${trace.requestEndTime?.toIso8601String() ?? 'server did not provide'}',
      )
      ..writeln(
        '  duration_ms: ${trace.responseDuration?.inMilliseconds.toString() ?? 'server did not provide'}',
      )
      ..writeln(
        '  provider_request_id: ${trace.providerRequestId ?? 'server did not provide'}',
      );
    if (trace.rawSseEvents.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('raw_sse:')
        ..writeln(trace.rawSseEvents.join('\n'));
    } else if (trace.rawResponseText != null &&
        trace.rawResponseText!.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('raw_response:')
        ..writeln(trace.rawResponseText!.trim());
    }
    if (trace.rawErrorJson != null && trace.rawErrorJson!.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('raw_error:')
        ..writeln(trace.rawErrorJson!.trim());
    }
    return buffer.toString().trimRight();
  }

  static String _failureDetail(AiFailure? failure) {
    if (failure == null) return '';
    return failure.messageKey.startsWith('ai.error.')
        ? failure.code.name
        : failure.messageKey;
  }
}
