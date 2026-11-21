import Foundation
@testable import SonoroCore

// Fake services used ONLY by the automated tests.

let rome = TimeZone(identifier: "Europe/Rome")!

func day(_ s: String) -> DayDate { DayDate(iso: s)! }

/// Date at `hh:mm` of an ISO day in Rome.
func at(_ iso: String, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
    day(iso).date(minuteOfDay: hour * 60 + minute, timeZone: rome).addingTimeInterval(TimeInterval(second))
}

func makeClip(_ iso: String, _ hour: Int, _ minute: Int = 0, duration: Double = 10, place: String? = nil,
              locality: String? = nil, location: GeoPoint? = nil, note: String = "", emoji: String = "",
              favorite: Bool = false, bytes: Int = 80_000, id: UUID = UUID()) -> Clip {
    let date = at(iso, hour, minute)
    return Clip(id: id, recordedAt: date, day: day(iso), minuteOfDay: hour * 60 + minute, duration: duration,
                fileName: FileNaming.clipPath(id: id, recordedAt: date, timeZone: rome), byteSize: bytes,
                location: location, placeName: place, locality: locality, note: note, emoji: emoji,
                isFavorite: favorite, waveform: Array(repeating: 128, count: Waveform.defaultBins))
}

func tempFolder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("sonoro-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Writes fake bytes instead of audio; elapsed time is set by the test.
final class FakeRecorder: AudioRecording {
    var elapsed: Double = 10
    var levels: [Float] = (0..<200).map { Float($0 % 20) / 20 }
    var fail = false
    private(set) var startedURL: URL?
    private(set) var quality: AudioQuality?
    private(set) var stops = 0

    var currentLevel: Float { 0.5 }

    func start(to url: URL, quality: AudioQuality) async throws {
        if fail { throw NSError(domain: "fake", code: 1) }
        startedURL = url
        self.quality = quality
        try Data(repeating: 7, count: 1_000).write(to: url)
    }

    func stop() async -> RecordedAudio {
        stops += 1
        return RecordedAudio(duration: elapsed, levels: levels)
    }
}

final class FakeLocation: LocationProviding {
    var access: LocationAccess
    var grantOnRequest = true
    var point: GeoPoint? = GeoPoint(lat: 46.0612, lon: 12.4021, accuracy: 10)
    var info: PlaceInfo? = PlaceInfo(name: "Bosco del Cansiglio", locality: "Fregona")
    private(set) var requests = 0
    private(set) var fixes = 0

    init(access: LocationAccess) { self.access = access }

    func requestAccess() async -> LocationAccess {
        requests += 1
        access = grantOnRequest ? .allowed : .denied
        return access
    }

    func currentLocation() async -> GeoPoint? {
        fixes += 1
        return access == .allowed ? point : nil
    }

    func placeInfo(for point: GeoPoint) async -> PlaceInfo? { info }
}

final class FakeWeather: WeatherProviding {
    var calls = 0
    func weather(at point: GeoPoint, date: Date) async -> WeatherInfo? {
        calls += 1
        return WeatherInfo(symbol: "cloud.rain.fill", condition: "Pioggia", temperatureC: 8.4)
    }
}

/// Concatenates the input bytes and remembers the plan.
final class FakeMerger: AudioMerging {
    private(set) var lastPlan: SoundtrackPlan?
    private(set) var lastInputs: [URL] = []
    var fail = false

    func merge(inputs: [URL], plan: SoundtrackPlan, output: URL, quality: AudioQuality) async throws {
        if fail { throw NSError(domain: "fake-merge", code: 2) }
        lastPlan = plan
        lastInputs = inputs
        var data = Data()
        for url in inputs { data.append(try Data(contentsOf: url)) }
        try data.write(to: output)
    }
}
