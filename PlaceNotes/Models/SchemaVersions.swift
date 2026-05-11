import Foundation
import SwiftData

enum PlaceNotesSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Place.self,
            Visit.self,
            CustomCategory.self,
            JournalEntry.self,
            RawLocationSample.self
        ]
    }
}

enum PlaceNotesMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PlaceNotesSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
