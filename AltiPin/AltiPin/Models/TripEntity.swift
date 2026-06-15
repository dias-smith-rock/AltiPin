//
//  TripEntity.swift
//  AltiPin
//

import Foundation
import SwiftData

@Model
final class TripEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var dateCreated: Date
    var isMerged: Bool
    var subGpxFileNames: [String]

    var totalDistance: Double
    var totalAscent: Double
    var maxElevation: Double
    var startTime: Date
    var endTime: Date

    init(
        title: String,
        subGpxFileNames: [String],
        startTime: Date,
        endTime: Date,
        totalDistance: Double = 0,
        totalAscent: Double = 0,
        maxElevation: Double = 0,
        isMerged: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.dateCreated = Date()
        self.subGpxFileNames = subGpxFileNames
        self.totalDistance = totalDistance
        self.isMerged = isMerged
        self.totalAscent = totalAscent
        self.maxElevation = maxElevation
        self.startTime = startTime
        self.endTime = endTime
    }
}
