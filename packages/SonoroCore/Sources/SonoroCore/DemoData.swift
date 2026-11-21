import Foundation

/// Deterministic pseudo-random generator (SplitMix64): same seed, same diary.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    public mutating func int(_ range: ClosedRange<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.count)) }
    public mutating func chance(_ p: Double) -> Bool { unit() < p }
    public mutating func pick<T>(_ a: [T]) -> T { a[Int(next() % UInt64(a.count))] }
}

/// Synthetic diary for tests and for the screenshots taken in CI
/// (launch argument `-demo`). No real audio, places or people.
public enum DemoData {
    public struct Place: Sendable {
        public let name: String
        public let locality: String
        public let lat: Double
        public let lon: Double
        public let sounds: [(note: String, emoji: String)]
        /// Preferred hours.
        public let hours: ClosedRange<Int>
        public let seasons: [Season]
    }

    public static let places: [Place] = [
        Place(name: "Bosco del Cansiglio", locality: "Fregona", lat: 46.0612, lon: 12.4021,
              sounds: [("Vento tra i faggi", "🌲"), ("Picchio lontano", "🐦"), ("Passi sulle foglie", "🍂")], hours: 7...17, seasons: Season.allCases),
        Place(name: "Lungo Sile", locality: "Treviso", lat: 45.6638, lon: 12.2533,
              sounds: [("Corsa lungo il fiume", "🏃"), ("Anatre sul Sile", "🦆"), ("Acqua al mulino", "💧")], hours: 6...20, seasons: Season.allCases),
        Place(name: "Piazza dei Signori", locality: "Treviso", lat: 45.6669, lon: 12.2430,
              sounds: [("Campane di mezzogiorno", "🔔"), ("Mercato del sabato", "🛒"), ("Aperitivo in piazza", "🥂")], hours: 9...21, seasons: Season.allCases),
        Place(name: "Spiaggia di Jesolo", locality: "Jesolo", lat: 45.4950, lon: 12.6450,
              sounds: [("Onde al tramonto", "🌊"), ("Gabbiani", "🐦"), ("Bambini che giocano", "🏖️")], hours: 9...20, seasons: [.summer, .spring]),
        Place(name: "Pista Tofana", locality: "Cortina d'Ampezzo", lat: 46.5390, lon: 12.1160,
              sounds: [("Sci sulla neve fresca", "⛷️"), ("Seggiovia", "🚡"), ("Neve che scricchiola", "❄️")], hours: 9...16, seasons: [.winter]),
        Place(name: "Rifugio Lagazuoi", locality: "Cortina d'Ampezzo", lat: 46.5292, lon: 11.9570,
              sounds: [("Silenzio in quota", "🏔️"), ("Vento sul crinale", "💨")], hours: 10...17, seasons: [.summer, .autumn]),
        Place(name: "Mercato di Rialto", locality: "Venezia", lat: 45.4385, lon: 12.3355,
              sounds: [("Voci del mercato", "🐟"), ("Vaporetto", "⛴️")], hours: 8...13, seasons: Season.allCases),
        Place(name: "Stazione di Mestre", locality: "Venezia", lat: 45.4825, lon: 12.2320,
              sounds: [("Treno in arrivo", "🚆"), ("Annuncio al binario", "📢")], hours: 6...22, seasons: Season.allCases),
        Place(name: "Giardino di casa", locality: "Treviso", lat: 45.6905, lon: 12.2702,
              sounds: [("Pioggia sul tetto", "🌧️"), ("Merli al mattino", "🐦"), ("Grilli di sera", "🦗"), ("Cena con amici", "🍝")], hours: 6...23, seasons: Season.allCases),
        Place(name: "Colli Asolani", locality: "Asolo", lat: 45.8003, lon: 11.9135,
              sounds: [("Vendemmia", "🍇"), ("Pedalata in salita", "🚴")], hours: 8...18, seasons: [.autumn, .summer, .spring]),
        Place(name: "Lago di Santa Croce", locality: "Farra d'Alpago", lat: 46.1140, lon: 12.3330,
              sounds: [("Kitesurf e vento", "🪁"), ("Onde sul lago", "🌊")], hours: 10...18, seasons: [.summer, .spring])
    ]

    static let weathers: [(symbol: String, condition: String)] = [
        ("sun.max.fill", "Sereno"), ("cloud.sun.fill", "Poco nuvoloso"), ("cloud.fill", "Nuvoloso"),
        ("cloud.rain.fill", "Pioggia"), ("cloud.fog.fill", "Nebbia"), ("wind", "Ventoso"), ("cloud.snow.fill", "Neve")
    ]

    /// A diary of `years` years ending on `today`, with an anniversary on
    /// `today` one and two years ago and a recording streak in the last days.
    public static func make(today: DayDate, years: Int = 3, seed: UInt64 = 2026, timeZone: TimeZone = TimeZone(identifier: "Europe/Rome")!,
                            nowMinute: Int = 18 * 60 + 40) -> DiaryData {
        var rng = SeededRandom(seed: seed)
        let start = DayDate(year: today.year - years, month: today.month, day: min(today.day, 28))!
        var clips: [Clip] = []
        var settings = DiarySettings()
        settings.saveWeather = true

        var day = start
        while day <= today {
            let back = DayDate.daysBetween(day, today)
            let forced = back <= 12 || back == 365 || back == 366 || back == 730 || back == 731
            let probability = back < 60 ? 0.85 : (back < 365 ? 0.55 : 0.35)
            if forced || rng.chance(probability) {
                let n = back == 0 ? 3 : rng.int(1...(back < 60 ? 6 : 4))
                clips += makeDay(day, count: n, today: today, nowMinute: nowMinute, rng: &rng, timeZone: timeZone, quality: settings.quality)
            }
            day = day.adding(days: 1)
        }
        // A few favourites.
        for i in clips.indices where rng.chance(0.08) { clips[i].isFavorite = true }

        var data = DiaryData(clips: clips, settings: settings)
        for d in data.recordedDays where d < today {
            let list = data.clips(on: d)
            let plan = SoundtrackPlan(clips: list, crossfade: settings.crossfade)
            let wave = Waveform.concat(list.map { (Waveform.dequantize($0.waveform), $0.duration) }, bins: 64)
            data.setSoundtrack(DailySoundtrack(
                day: d, fileName: FileNaming.soundtrackPath(day: d), duration: plan.totalDuration, clipIDs: list.map(\.id),
                createdAt: d.date(minuteOfDay: settings.soundtrackTime.minutes, timeZone: timeZone),
                byteSize: settings.quality.estimatedBytes(seconds: plan.totalDuration), waveform: Waveform.quantize(wave)))
        }
        return data
    }

    static func makeDay(_ day: DayDate, count: Int, today: DayDate, nowMinute: Int, rng: inout SeededRandom,
                        timeZone: TimeZone, quality: AudioQuality) -> [Clip] {
        let season = Season.of(month: day.month)
        let candidates = places.filter { $0.seasons.contains(season) }
        // Mostly one or two places a day, like real life.
        let home = places.first { $0.name == "Giardino di casa" }!
        let outing = rng.pick(candidates)
        var minutes: [Int] = []
        let maxMinute = day == today ? max(7 * 60, nowMinute - 30) : 23 * 60
        for _ in 0..<count { minutes.append(rng.int(6 * 60 + 30...maxMinute)) }
        return minutes.sorted().enumerated().map { (i, minute) -> Clip in
            let place = rng.chance(0.6) ? (outing.hours.contains(minute / 60) ? outing : home) : rng.pick(candidates)
            let sound = rng.pick(place.sounds)
            let dur = Double(rng.chance(0.75) ? 10 : rng.int(4...30))
            let jitterLat = (rng.unit() - 0.5) * 0.0012
            let jitterLon = (rng.unit() - 0.5) * 0.0012
            let w = rng.pick(weathers.filter { $0.symbol != "cloud.snow.fill" || season == .winter })
            let base: Double = [Season.winter: 2, .spring: 14, .summer: 26, .autumn: 13][season]!
            let id = UUID(uuid: uuidBytes(&rng))
            let second = rng.int(0...59)
            var date = day.date(minuteOfDay: minute, timeZone: timeZone)
            date.addTimeInterval(TimeInterval(second))
            let note = rng.chance(0.7) ? sound.note : ""
            let emoji = rng.chance(0.8) ? sound.emoji : ""
            _ = i
            return Clip(id: id, recordedAt: date, day: day, minuteOfDay: minute, duration: dur,
                        fileName: FileNaming.clipPath(id: id, recordedAt: date, timeZone: timeZone),
                        byteSize: quality.estimatedBytes(seconds: dur),
                        location: GeoPoint(lat: place.lat + jitterLat, lon: place.lon + jitterLon, accuracy: 12),
                        placeName: place.name, locality: place.locality,
                        weather: WeatherInfo(symbol: w.symbol, condition: w.condition, temperatureC: base + (rng.unit() - 0.5) * 10),
                        note: note, emoji: emoji, waveform: waveform(&rng))
        }
    }

    static func uuidBytes(_ rng: inout SeededRandom) -> uuid_t {
        var b = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 { b[i] = UInt8(truncatingIfNeeded: rng.next()) }
        b[6] = (b[6] & 0x0F) | 0x40
        b[8] = (b[8] & 0x3F) | 0x80
        return (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])
    }

    /// Smooth random envelope with a few peaks, like a real ambience.
    public static func waveform(_ rng: inout SeededRandom, bins: Int = Waveform.defaultBins) -> [UInt8] {
        var v: [Float] = []
        var x = Float(rng.unit()) * 0.5 + 0.2
        for _ in 0..<bins {
            x += Float(rng.unit() - 0.5) * 0.35
            x = min(1, max(0.08, x))
            let peak: Float = rng.chance(0.08) ? Float(rng.unit()) * 0.6 : 0
            v.append(min(1, x * 0.8 + peak))
        }
        return Waveform.quantize(Waveform.normalize(v))
    }
}
