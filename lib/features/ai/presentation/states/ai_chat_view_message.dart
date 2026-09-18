import 'package:flutter/foundation.dart';

import 'package:JsxposedX/features/ai/presentation/states/ai_tool_invocation_view.dart';

/// Presentation-only message model. The chat widgets do not depend on the
/// legacy storage/protocol message shape.
@immutable
class AiChatViewMessage {
  const AiChatViewMessage({
    required this.id,
    required this.role,
    required this.content,
    this.isError = false,
    this.isToolResultBubble = false,
    this.rawDetails,
    this.sourceMessageId,
    this.toolInvocations = const <AiToolInvocationView>[],
  });

  final String id;
  final String role;
  final String content;
  final bool isError;
  final bool isToolResultBubble;
  final String? rawDetails;
  final String? sourceMessageId;
  final List<AiToolInvocationView> toolInvocations;
}
