import 'package:flutter/foundation.dart';

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
  });

  final String id;
  final String role;
  final String content;
  final bool isError;
  final bool isToolResultBubble;
}
