import Foundation

// MARK: - Filters

public enum Season: String, CaseIterable, Sendable, Identifiable {
    case spring, summer, autumn, winter

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .spring: return "Primavera"
        case .summer: return "Estate"
        case .autumn: return "Autunno"
        case .winter: return "Inverno"
        }
    }

    public var symbol: String {
        switch self {
        case .spring: return "leaf.fill"
        case .summer: return "sun.max.fill"
        case .autumn: return "wind"
        case .winter: return "snowflake"
        }
    }

    /// Meteorological seasons (spring = March–May …).
    public static func of(month: Int) -> Season {
        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }
}

public enum TimeOfDay: String, CaseIterable, Sendable, Identifiable {
    case morning, afternoon, evening, night

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .morning: return "Mattina"
        case .afternoon: return "Pomeriggio"
        case .evening: return "Sera"
        case .night: return "Notte"
        }
    }

    public var symbol: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }

    /// Mattina 5–12, pomeriggio 12–18, sera 18–22, notte 22–5.
    public static func of(hour: Int) -> TimeOfDay {
        switch hour {
        case 5..<12: return .morning
        case 12..<18: return .afternoon
        case 18..<22: return .evening
        default: return .night
        }
    }
}

/// Filters of the map (year and period of the year / of the day).
public struct MapFilter: Equatable, Sendable {
    public var year: Int?
    public var season: Season?
    public var timeOfDay: TimeOfDay?
    public var favoritesOnly: Bool

    public init(year: Int? = nil, season: Season? = nil, timeOfDay: TimeOfDay? = nil, favoritesOnly: Bool = false) {
        self.year = year
        self.season = season
        self.timeOfDay = timeOfDay
        self.favoritesOnly = favoritesOnly
    }

    public var isEmpty: Bool { year == nil && season == nil && timeOfDay == nil && !favoritesOnly }

    public func matches(_ c: Clip) -> Bool {
        guard c.location != nil else { return false }
        if let year, c.day.year != year { return false }
        if let season, Season.of(month: c.day.month) != season { return false }
        if let timeOfDay, TimeOfDay.of(hour: c.hour) != timeOfDay { return false }
        if favoritesOnly && !c.isFavorite { return false }
        return true
    }

    public func apply(_ clips: [Clip]) -> [Clip] { clips.filter(matches) }
}

// MARK: - Spots (clips recorded in the same place)

/// Clips recorded within `radius` of each other: one pin, one list to listen to.
public struct PlaceSpot: Identifiable, Equatable, Sendable {
    public let id: String
    public let center: GeoPoint
    public let name: String
    /// Newest first.
    public let clips: [Clip]

    public var count: Int { clips.count }
    public var totalDuration: Double { clips.reduce(0) { $0 + $1.duration } }
}

public enum PlaceSpots {
    /// Greedy grouping: each clip joins the nearest spot within `radius`
    /// meters, otherwise starts a new one. Deterministic (oldest clips first).
    public static func spots(from clips: [Clip], radius: Double = 150) -> [PlaceSpot] {
        struct Acc { var lat: Double; var lon: Double; var clips: [Clip] }
        var acc: [Acc] = []
        for c in clips.filter({ $0.location != nil }).sorted(by: Clip.chronological) {
            let p = c.location!
            var best: (Int, Double)?
            for (i, a) in acc.enumerated() {
                let d = GeoPoint(lat: a.lat, lon: a.lon).distance(to: p)
                if d <= radius, best == nil || d < best!.1 { best = (i, d) }
            }
            if let (i, _) = best {
                let n = Double(acc[i].clips.count)
                acc[i].lat = (acc[i].lat * n + p.lat) / (n + 1)
                acc[i].lon = (acc[i].lon * n + p.lon) / (n + 1)
                acc[i].clips.append(c)
            } else {
                acc.append(Acc(lat: p.lat, lon: p.lon, clips: [c]))
            }
        }
        return acc.map { a in
            let clips = a.clips.sorted { Clip.chronological($1, $0) }
            let first = a.clips.first!
            return PlaceSpot(id: first.id.uuidString, center: GeoPoint(lat: a.lat, lon: a.lon),
                             name: mostCommonName(a.clips) ?? "Luogo senza nome", clips: clips)
        }
    }

    static func mostCommonName(_ clips: [Clip]) -> String? {
        var counts: [String: Int] = [:]
        for c in clips { if let n = c.displayPlace { counts[n, default: 0] += 1 } }
        return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }
}

// MARK: - Clusters (spots close together at the current zoom)

public struct MapCluster: Identifiable, Equatable, Sendable {
    public let id: String
    public let center: GeoPoint
    public let spots: [PlaceSpot]

    public var clipCount: Int { spots.reduce(0) { $0 + $1.count } }
    public var isSingleSpot: Bool { spots.count == 1 }
    public var title: String {
        spots.count == 1 ? spots[0].name : "\(spots.count) luoghi"
    }
}

public enum MapClusterer {
    /// Grid size (degrees) for a visible latitude span: ~`cellsAcross` cells on screen.
    public static func cellSize(latitudeDelta: Double, cellsAcross: Double = 6) -> Double {
        max(0.0005, abs(latitudeDelta) / cellsAcross)
    }

    /// Groups spots closer than `cell` degrees to the biggest spot of a
    /// cluster (no fixed grid: two close spots are never split by a grid line).
    /// Cluster ids are stable (the ids of their spots), the center is weighted
    /// by clip count.
    public static func clusters(_ spots: [PlaceSpot], cell: Double) -> [MapCluster] {
        guard cell > 0 else { return spots.map { MapCluster(id: $0.id, center: $0.center, spots: [$0]) } }
        let ordered = spots.sorted { $0.count != $1.count ? $0.count > $1.count : $0.id < $1.id }
        var groups: [(seed: GeoPoint, spots: [PlaceSpot])] = []
        for s in ordered {
            if let i = groups.firstIndex(where: {
                abs($0.seed.lat - s.center.lat) <= cell && abs($0.seed.lon - s.center.lon) <= cell * 1.4
            }) {
                groups[i].spots.append(s)
            } else {
                groups.append((s.center, [s]))
            }
        }
        return groups.map(\.spots).map { group in
            let sorted = group.sorted { $0.count != $1.count ? $0.count > $1.count : $0.id < $1.id }
            let w = Double(sorted.reduce(0) { $0 + $1.count })
            let lat = sorted.reduce(0) { $0 + $1.center.lat * Double($1.count) } / w
            let lon = sorted.reduce(0) { $0 + $1.center.lon * Double($1.count) } / w
            return MapCluster(id: sorted.map(\.id).sorted().joined(separator: "+"), center: GeoPoint(lat: lat, lon: lon), spots: sorted)
        }
        .sorted { $0.clipCount != $1.clipCount ? $0.clipCount > $1.clipCount : $0.id < $1.id }
    }

    /// Region (center + spans in degrees) that fits all points with a margin.
    public static func region(fitting points: [GeoPoint], margin: Double = 1.4, minimumSpan: Double = 0.02)
        -> (center: GeoPoint, latitudeDelta: Double, longitudeDelta: Double)? {
        guard let first = points.first else { return nil }
        var minLat = first.lat, maxLat = first.lat, minLon = first.lon, maxLon = first.lon
        for p in points {
            minLat = min(minLat, p.lat); maxLat = max(maxLat, p.lat)
            minLon = min(minLon, p.lon); maxLon = max(maxLon, p.lon)
        }
        return (GeoPoint(lat: (minLat + maxLat) / 2, lon: (minLon + maxLon) / 2),
                max(minimumSpan, (maxLat - minLat) * margin), max(minimumSpan, (maxLon - minLon) * margin))
    }
}
