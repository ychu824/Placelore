import Foundation
import SwiftData

/// Builds the raw-location CSV export for offline ST-DBSCAN analysis.
/// Columns match the dimension table in the project docs.
enum LocationExporter {
    static let csvHeader = "id,latitude,longitude,timestamp,horizontalAccuracy,speed,altitude,verticalAccuracy,course,filterStatus,motionActivity"

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func csvRow(for sample: RawLocationSample) -> String {
        let row: [String] = [
            sample.id.uuidString,
            "\(sample.latitude)",
            "\(sample.longitude)",
            iso8601.string(from: sample.timestamp),
            "\(sample.horizontalAccuracy)",
            "\(sample.speed)",
            sample.altitude.map { "\($0)" } ?? "",
            sample.verticalAccuracy.map { "\($0)" } ?? "",
            sample.course.map { "\($0)" } ?? "",
            sample.filterStatus,
            sample.motionActivity ?? ""
        ]
        return row.joined(separator: ",")
    }

    /// Fetches samples in batches so a month of high-frequency fixes is never
    /// materialized in one array, yielding between batches to keep the main
    /// actor responsive while the export builds.
    @MainActor
    static func exportCSV(from context: ModelContext, batchSize: Int = 5000) async -> Data {
        var lines = [csvHeader]
        var offset = 0
        while true {
            var descriptor = FetchDescriptor<RawLocationSample>(sortBy: [SortDescriptor(\.timestamp)])
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            let batch = (try? context.fetch(descriptor)) ?? []
            guard !batch.isEmpty else { break }
            lines.append(contentsOf: batch.map(csvRow(for:)))
            offset += batch.count
            if batch.count < batchSize { break }
            await Task.yield()
        }
        return Data(lines.joined(separator: "\n").utf8)
    }
}
