import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:JsxposedX/features/ai/data/models/ai_config_dto.dart';
import 'package:JsxposedX/features/ai/data/repositories/drift_ai_catalog_repository.dart';
import 'package:JsxposedX/features/ai/domain/ports/ai_credential_store.dart';
import 'package:JsxposedX/features/ai/infrastructure/migration/legacy_ai_config_importer.dart';
import 'package:JsxposedX/features/ai/infrastructure/persistence/ai_database.dart';

void main() {
  late AiDatabase database;
  late DriftAiCatalogRepository catalog;
  late _MemoryCredentialStore credentials;
  late LegacyAiConfigImporter importer;

  setUp(() {
    database = AiDatabase.forTesting(NativeDatabase.memory());
    catalog = DriftAiCatalogRepository(database);
    credentials = _MemoryCredentialStore();
    importer = LegacyAiConfigImporter.forImport(
      catalogRepository: catalog,
      credentialStore: credentials,
      now: () => DateTime.utc(2026, 9, 5),
    );
  });

  tearDown(() => database.close());

  test('imports legacy endpoint, key reference, model and assistant', () async {
    const legacy = AiConfigDto(
      id: 'old',
      name: 'Old config',
      apiKey: 'secret',
      apiUrl: 'https://example.test/v1/chat/completions?route=a',
      moduleName: 'model-1',
      maxToken: 2048,
      temperature: 0.5,
      memoryRounds: 7,
      apiType: 'openai',
    );

    final report = await importer.importConfigs([legacy]);

    expect(report.isSuccessful, isTrue);
    final connection = await catalog.getConnection('legacy-connection-old');
    expect(connection?.baseUri.toString(), 'https://example.test/v1/');
    expect(
      connection?.endpointOverrides.values.single.toString(),
      'https://example.test/v1/chat/completions?route=a',
    );
    expect(connection?.credentialRef, 'legacy-old');
    expect(credentials.values['legacy-old'], 'secret');
    expect(
      (await catalog.getModel(
        'legacy-connection-old',
        'model-1',
      ))?.capabilities.toolCalling,
      isTrue,
    );
    final assistant = await catalog.getAssistant('legacy-assistant-old');
    expect(assistant?.contextPolicy.recentMessageLimit, 7);
  });

  test('is idempotent and reports invalid entries independently', () async {
    const valid = AiConfigDto(
      id: 'valid',
      apiUrl: 'https://example.test/v1',
      moduleName: 'model',
    );
    const invalid = AiConfigDto(
      id: 'invalid',
      apiUrl: 'not a uri',
      moduleName: 'model',
    );

    await importer.importConfigs([valid]);
    final report = await importer.importConfigs([valid, invalid]);

    expect(report.importedConfigIds, ['valid']);
    expect(report.failures.single.configId, 'invalid');
    expect(await catalog.getConnections(), hasLength(1));
  });

  test('rolls back catalog data and a new credential on failure', () async {
    await database.customStatement('''
      CREATE TRIGGER reject_legacy_assistant
      BEFORE INSERT ON ai_assistant_profiles
      BEGIN
        SELECT RAISE(ABORT, 'test failure');
      END;
    ''');
    const legacy = AiConfigDto(
      id: 'broken',
      apiKey: 'secret',
      apiUrl: 'https://example.test/v1',
      moduleName: 'model',
    );

    final report = await importer.importConfigs([legacy]);

    expect(report.failures, hasLength(1));
    expect(await catalog.getConnection('legacy-connection-broken'), isNull);
    expect(credentials.values, isEmpty);
  });
}

class _MemoryCredentialStore implements AiCredentialStore {
  final Map<String, String> values = {};

  @override
  Future<String> put(AiSecret secret, {String? credentialRef}) async {
    final reference = credentialRef ?? 'generated';
    values[reference] = secret.value;
    return reference;
  }

  @override
  Future<AiSecret?> read(String credentialRef) async {
    final value = values[credentialRef];
    return value == null ? null : AiSecret(value);
  }

  @override
  Future<void> delete(String credentialRef) async {
    values.remove(credentialRef);
  }
}
