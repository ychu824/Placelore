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

enum PlaceNotesSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 1, 0)

    static var models: [any PersistentModel.Type] {
        [
            Place.self,
            Visit.self,
            CustomCategory.self,
            JournalEntry.self,
            RawLocationSample.self,
            PredictionFeedback.self
        ]
    }
}

enum PlaceNotesMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PlaceNotesSchemaV1.self, PlaceNotesSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: PlaceNotesSchemaV1.self, toVersion: PlaceNotesSchemaV2.self)
        ]
    }
}
