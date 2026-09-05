import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'ai_database.g.dart';

class AiProviderConnections extends Table {
  TextColumn get id => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AiModelDefinitions extends Table {
  TextColumn get connectionId => text()();
  TextColumn get modelId => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {connectionId, modelId};
}

class AiAssistantProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get connectionId => text()();
  TextColumn get modelId => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AiConversations extends Table {
  TextColumn get id => text()();
  TextColumn get assistantId => text()();
  TextColumn get title => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  TextColumn get payloadJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AiMessageRecords extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get status => text()();
  TextColumn get payloadJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    AiProviderConnections,
    AiModelDefinitions,
    AiAssistantProfiles,
    AiConversations,
    AiMessageRecords,
  ],
)
class AiDatabase extends _$AiDatabase {
  AiDatabase() : super(_openConnection());

  AiDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async => migrator.createAll(),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationSupportDirectory();
    final file = File(p.join(directory.path, 'jsxposedx_ai.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
