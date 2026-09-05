import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';

abstract interface class AiConversationRepository {
  Future<List<AiConversation>> getConversations({
    AiConversationCursor? before,
    int limit = 30,
  });

  Future<AiConversation?> getConversation(String id);

  Future<void> saveConversation(AiConversation conversation);

  Future<void> deleteConversation(String id);

  Future<List<AiMessage>> getMessages(
    String conversationId, {
    AiMessageCursor? before,
    int limit = 50,
  });

  Future<void> saveMessage(AiMessage message);

  Future<void> saveMessages(List<AiMessage> messages);

  Future<void> deleteMessagesAfter(String conversationId, DateTime createdAt);

  Future<void> deleteMessagesById(String conversationId, Iterable<String> ids);
}

class AiConversationCursor {
  const AiConversationCursor({required this.updatedAt, required this.id});

  final DateTime updatedAt;
  final String id;
}

class AiMessageCursor {
  const AiMessageCursor({required this.createdAt, required this.id});

  final DateTime createdAt;
  final String id;
}
