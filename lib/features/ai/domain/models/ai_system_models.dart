import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:JsxposedX/features/ai/application/chat/ai_transport_trace.dart';

part 'ai_system_models.freezed.dart';

enum AiMessageRole { system, user, assistant, tool }

enum AiMessageStatus {
  draft,
  queued,
  streaming,
  completed,
  failed,
  cancelled,
  interrupted,
}

enum AiContextMode { tokenBudget, recentMessages, fullHistory }

enum AiToolApprovalMode { never, riskyOnly, always }

enum AiFinishReason {
  stop,
  length,
  toolCall,
  contentFilter,
  cancelled,
  unknown,
}

enum AiEndpointKind { chatCompletions, responses, messages, models }

enum AiAuthScheme { bearer, apiKeyHeader, queryParameter, oauth, none }

enum AiFailureCode {
  invalidConfiguration,
  credentialMissing,
  authenticationFailed,
  permissionDenied,
  modelNotFound,
  unsupportedCapability,
  contextLimitExceeded,
  rateLimited,
  quotaExceeded,
  networkUnavailable,
  connectTimeout,
  receiveTimeout,
  protocolMalformed,
  protocolTruncated,
  serverFailure,
  toolRejected,
  toolFailed,
  cancelled,
  unknown,
}

@freezed
sealed class AiContentPart with _$AiContentPart {
  const factory AiContentPart.text(String text) = AiTextPart;
  const factory AiContentPart.reasoning(String text) = AiReasoningPart;
  const factory AiContentPart.image({required String attachmentId}) =
      AiImagePart;
  const factory AiContentPart.toolCall({required AiToolCall toolCall}) =
      AiToolCallPart;
  const factory AiContentPart.toolResult({required AiToolResult toolResult}) =
      AiToolResultPart;
}

@freezed
abstract class AiToolCall with _$AiToolCall {
  const factory AiToolCall({
    required String id,
    required String name,
    required Map<String, Object?> arguments,
  }) = _AiToolCall;
}

@freezed
abstract class AiToolResult with _$AiToolResult {
  const factory AiToolResult({
    required String toolCallId,
    required String name,
    required bool success,
    required String content,
  }) = _AiToolResult;
}

@freezed
abstract class AiToolSpec with _$AiToolSpec {
  const factory AiToolSpec({
    required String name,
    required String description,
    required Map<String, Object?> inputSchema,
  }) = _AiToolSpec;
}

@freezed
abstract class AiMessage with _$AiMessage {
  const factory AiMessage({
    required String id,
    required String conversationId,
    required AiMessageRole role,
    required List<AiContentPart> parts,
    @Default(AiMessageStatus.completed) AiMessageStatus status,
    AiUsage? usage,
    AiFailure? failure,
    AiTransportTrace? transportTrace,
    String? parentId,
    required DateTime createdAt,
    DateTime? completedAt,
  }) = _AiMessage;
}

@freezed
abstract class AiGenerationOptions with _$AiGenerationOptions {
  const factory AiGenerationOptions({
    int? maxOutputTokens,
    double? temperature,
    double? topP,
    double? presencePenalty,
    double? frequencyPenalty,
    String? reasoningEffort,
    @Default(true) bool stream,
  }) = _AiGenerationOptions;
}

@freezed
abstract class AiModelCapabilities with _$AiModelCapabilities {
  const factory AiModelCapabilities({
    @Default(false) bool streaming,
    @Default(false) bool visionInput,
    @Default(false) bool fileInput,
    @Default(false) bool reasoning,
    @Default(false) bool toolCalling,
    @Default(false) bool parallelToolCalling,
    @Default(false) bool structuredOutput,
    @Default(true) bool systemRole,
  }) = _AiModelCapabilities;
}

@freezed
abstract class AiModelLimits with _$AiModelLimits {
  const factory AiModelLimits({
    int? contextTokens,
    int? maxOutputTokens,
    int? maxImages,
    int? maxTools,
    int? maxToolResultBytes,
  }) = _AiModelLimits;
}

@freezed
abstract class AiModelDefinition with _$AiModelDefinition {
  const factory AiModelDefinition({
    required String id,
    required String connectionId,
    required String displayName,
    required AiModelCapabilities capabilities,
    required AiModelLimits limits,
    @Default('discovered') String source,
  }) = _AiModelDefinition;
}

@freezed
abstract class AiProviderDefinition with _$AiProviderDefinition {
  const factory AiProviderDefinition({
    required String id,
    required String displayName,
    required String adapterId,
    @Default(AiAuthScheme.bearer) AiAuthScheme authScheme,
    String? authParameterName,
  }) = _AiProviderDefinition;
}

@freezed
abstract class AiProviderConnection with _$AiProviderConnection {
  const factory AiProviderConnection({
    required String id,
    required String providerId,
    required String displayName,
    required Uri baseUri,
    String? credentialRef,
    @Default(<AiEndpointKind, Uri>{})
    Map<AiEndpointKind, Uri> endpointOverrides,
    @Default(<String, String>{}) Map<String, String> customHeaders,
    @Default(<String, Object?>{}) Map<String, Object?> adapterOptions,
    @Default(true) bool enabled,
  }) = _AiProviderConnection;
}

@freezed
abstract class AiContextPolicy with _$AiContextPolicy {
  const factory AiContextPolicy({
    @Default(AiContextMode.tokenBudget) AiContextMode mode,
    @Default(1024) int reservedOutputTokens,
    @Default(4) int recentMessageMinimum,
    int? recentMessageLimit,
    @Default(true) bool includeToolResults,
    @Default(false) bool enableSummarization,
  }) = _AiContextPolicy;
}

@freezed
abstract class AiToolPolicy with _$AiToolPolicy {
  const factory AiToolPolicy({
    @Default(AiToolApprovalMode.riskyOnly) AiToolApprovalMode approvalMode,
    @Default(8) int maxRounds,
    @Default(1024 * 1024) int maxResultBytes,
  }) = _AiToolPolicy;
}

@freezed
abstract class AiAssistantProfile with _$AiAssistantProfile {
  const factory AiAssistantProfile({
    required String id,
    required String name,
    required String connectionId,
    required String modelId,
    String? systemPrompt,
    @Default(AiGenerationOptions()) AiGenerationOptions generation,
    @Default(AiContextPolicy()) AiContextPolicy contextPolicy,
    @Default(AiToolPolicy()) AiToolPolicy toolPolicy,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _AiAssistantProfile;
}

@freezed
abstract class AiConversation with _$AiConversation {
  const factory AiConversation({
    required String id,
    required String title,
    required String assistantId,
    @Default('general') String environmentId,
    String? scopeId,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? archivedAt,
  }) = _AiConversation;
}

@freezed
abstract class AiRequest with _$AiRequest {
  const factory AiRequest({
    required String requestId,
    required AiProviderConnection connection,
    required AiModelDefinition model,
    required List<AiMessage> messages,
    @Default(AiGenerationOptions()) AiGenerationOptions options,
    @Default(<AiToolSpec>[]) List<AiToolSpec> tools,
  }) = _AiRequest;
}

@freezed
abstract class AiUsage with _$AiUsage {
  const factory AiUsage({
    @Default(0) int inputTokens,
    @Default(0) int outputTokens,
    @Default(0) int totalTokens,
  }) = _AiUsage;
}

@freezed
abstract class AiFailure with _$AiFailure {
  const factory AiFailure({
    required AiFailureCode code,
    required String messageKey,
    @Default(false) bool retryable,
    int? httpStatus,
    String? providerRequestId,
    String? detail,
  }) = _AiFailure;
}
