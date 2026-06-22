//
//  FootprintStore.swift
//  AltiPin
//
//  脚印 FIFO 窗口的 SwiftData 持久化。
//

import Foundation
import SwiftData

@MainActor
final class FootprintStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func loadRecent(maxCount: Int = FootprintConfig.maxFootprints) -> [FootprintPoint] {
        let descriptor = FetchDescriptor<FootprintEntity>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )

        guard let records = try? modelContext.fetch(descriptor) else {
            return []
        }

        return Array(records.suffix(maxCount)).map(\.asFootprintPoint)
    }

    func save(_ footprint: FootprintPoint) {
        let entity = FootprintEntity(from: footprint)
        modelContext.insert(entity)
        trimToMax(FootprintConfig.maxFootprints)
        try? modelContext.save()
    }

    func replaceAll(with footprints: [FootprintPoint]) {
        if let existing = try? modelContext.fetch(FetchDescriptor<FootprintEntity>()) {
            for record in existing {
                modelContext.delete(record)
            }
        }

        for footprint in footprints {
            modelContext.insert(FootprintEntity(from: footprint))
        }

        trimToMax(FootprintConfig.maxFootprints)
        try? modelContext.save()
    }

    private func trimToMax(_ maxCount: Int) {
        var descriptor = FetchDescriptor<FootprintEntity>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        guard let records = try? modelContext.fetch(descriptor),
              records.count > maxCount else {
            return
        }

        let overflow = records.count - maxCount
        for record in records.prefix(overflow) {
            modelContext.delete(record)
        }
    }
}
