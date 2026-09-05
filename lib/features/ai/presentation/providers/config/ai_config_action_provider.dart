import 'package:JsxposedX/core/models/ai_config.dart';
import 'package:JsxposedX/core/providers/pinia_provider.dart';
import 'package:JsxposedX/features/ai/data/datasources/config/ai_config_action_datasource.dart';
import 'package:JsxposedX/features/ai/data/models/ai_config_dto.dart';
import 'package:JsxposedX/features/ai/data/repositories/config/ai_config_action_repository_impl.dart'
    as impl;
import 'package:JsxposedX/features/ai/infrastructure/migration/legacy_ai_config_importer.dart';
import 'package:JsxposedX/features/ai/domain/constants/builtin_ai_config.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_model.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';
import 'package:JsxposedX/features/ai/domain/repositories/config/ai_config_action_repository.dart';
import 'package:JsxposedX/features/ai/presentation/providers/config/ai_config_query_provider.dart';
import 'package:JsxposedX/features/ai/presentation/providers/system/ai_system_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ai_config_action_provider.g.dart';

@riverpod
AiConfigActionRepository aiConfigActionRepository(Ref ref) {
  final storage = ref.watch(piniaStorageLocalProvider);
  final dataSource = AiConfigActionDatasource(storage: storage);
  return impl.AiConfigActionRepositoryImpl(dataSource: dataSource);
}

/// 保存 AI 配置 Action Provider
@riverpod
class AiConfigAction extends _$AiConfigAction {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> save(AiConfig config) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(aiConfigActionRepositoryProvider).saveConfig(config);
      await _syncStandardCatalog(config);
      state = const AsyncValue.data(null);
      // 刷新查询 provider
      ref.invalidate(aiConfigProvider);
      ref.invalidate(aiConfigListProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addConfig(AiConfig config) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(aiConfigActionRepositoryProvider).addConfig(config);
      await _syncStandardCatalog(config);
      state = const AsyncValue.data(null);
      ref.invalidate(aiConfigListProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateConfig(AiConfig config) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(aiConfigActionRepositoryProvider).updateConfig(config);
      await _syncStandardCatalog(config);
      state = const AsyncValue.data(null);
      ref.invalidate(aiConfigListProvider);
      // 如果更新的是当前配置，也刷新当前配置
      ref.invalidate(aiConfigProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteConfig(String id) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(aiConfigActionRepositoryProvider).deleteConfig(id);
      await _removeStandardCatalog(id);
      state = const AsyncValue.data(null);
      ref.invalidate(aiConfigListProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> switchConfig(String id) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(aiConfigActionRepositoryProvider).switchConfig(id);
      state = const AsyncValue.data(null);
      // 刷新当前配置
      ref.invalidate(aiConfigProvider);
      final activeConfig = await ref.read(aiConfigProvider.future);
      await _syncStandardCatalog(activeConfig);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> saveAssistantSettings({
    required String configId,
    required String? systemPrompt,
    required AiContextMode contextMode,
    required int? recentMessageLimit,
    required AiToolApprovalMode approvalMode,
    required int maxToolRounds,
  }) async {
    state = const AsyncValue.loading();
    try {
      final catalog = ref.read(aiCatalogRepositoryProvider);
      final assistant = await catalog.getAssistant(
        'legacy-assistant-$configId',
      );
      if (assistant == null) {
        throw StateError('Assistant for config $configId does not exist');
      }
      await catalog.saveAssistant(
        assistant.copyWith(
          systemPrompt: systemPrompt?.trim().isEmpty == true
              ? null
              : systemPrompt?.trim(),
          contextPolicy: assistant.contextPolicy.copyWith(
            mode: contextMode,
            recentMessageLimit: recentMessageLimit,
          ),
          toolPolicy: assistant.toolPolicy.copyWith(
            approvalMode: approvalMode,
            maxRounds: maxToolRounds.clamp(0, 32).toInt(),
          ),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      state = const AsyncValue.data(null);
      ref.invalidate(aiAssistantsV2Provider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> saveDiscoveredModelMetadata({
    required String configId,
    required AiModel model,
  }) async {
    await saveDiscoveredModelsMetadata(configId: configId, models: [model]);
  }

  Future<void> saveDiscoveredModelsMetadata({
    required String configId,
    required List<AiModel> models,
  }) async {
    if (models.isEmpty) return;
    final connectionId = 'legacy-connection-$configId';
    final catalog = ref.read(aiCatalogRepositoryProvider);
    final existing = await catalog.getModels(connectionId);
    final existingById = {
      for (final definition in existing) definition.id: definition,
    };
    final definitions = <AiModelDefinition>[];
    for (final model in models) {
      final definition = existingById[model.id];
      definitions.add(
        (definition ??
                AiModelDefinition(
                  id: model.id,
                  connectionId: connectionId,
                  displayName: model.id,
                  capabilities: const AiModelCapabilities(
                    streaming: true,
                    toolCalling: true,
                  ),
                  limits: const AiModelLimits(),
                ))
            .copyWith(
              limits: (definition?.limits ?? const AiModelLimits()).copyWith(
                contextTokens:
                    model.contextTokens ?? definition?.limits.contextTokens,
                maxOutputTokens:
                    model.maxOutputTokens ?? definition?.limits.maxOutputTokens,
              ),
              source: 'discovered',
            ),
      );
    }
    await catalog.saveModels(connectionId, definitions);
    ref.invalidate(aiModelsV2Provider(connectionId));
  }

  Future<void> _syncStandardCatalog(AiConfig config) async {
    final importer = LegacyAiConfigImporter.forImport(
      catalogRepository: ref.read(aiCatalogRepositoryProvider),
      credentialStore: ref.read(aiCredentialStoreProvider),
    );
    final report = await importer.importConfigs([
      AiConfigDto.fromEntity(config),
    ]);
    if (!report.isSuccessful) {
      throw StateError(
        report.failures.map((failure) => failure.reason).join('; '),
      );
    }
    ref.invalidate(aiConnectionsV2Provider);
    ref.invalidate(aiAssistantsV2Provider);
    ref.invalidate(aiSystemMigrationProvider);
  }

  Future<void> _removeStandardCatalog(String configId) async {
    if (isBuiltinAiConfigId(configId)) return;
    await ref.read(aiCredentialStoreProvider).delete('legacy-$configId');
    final catalog = ref.read(aiCatalogRepositoryProvider);
    final connectionId = 'legacy-connection-$configId';
    final assistantId = 'legacy-assistant-$configId';
    final assistant = await catalog.getAssistant(assistantId);
    if (assistant != null) {
      // Drift conversations retain their assistant reference. Keep the
      // catalog row until those conversations are explicitly archived rather
      // than leaving dangling historical messages after config deletion.
      try {
        await catalog.deleteAssistant(assistant.id);
      } on StateError {
        return;
      }
    }
    final models = await catalog.getModels(connectionId);
    for (final model in models) {
      await catalog.deleteModel(connectionId, model.id);
    }
    if (await catalog.getConnection(connectionId) != null) {
      await catalog.deleteConnection(connectionId);
    }
    ref.invalidate(aiConnectionsV2Provider);
    ref.invalidate(aiAssistantsV2Provider);
  }
}
