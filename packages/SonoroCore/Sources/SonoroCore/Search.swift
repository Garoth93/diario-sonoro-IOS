import Foundation

/// Search and filters of the clip list (text, dates, place, emoji, favourites).
public struct ClipFilter: Equatable, Sendable {
    public var text: String
    public var from: DayDate?
    public var to: DayDate?
    public var place: String?
    public var emoji: String?
    public var favoritesOnly: Bool

    public init(text: String = "", from: DayDate? = nil, to: DayDate? = nil, place: String? = nil,
                emoji: String? = nil, favoritesOnly: Bool = false) {
        self.text = text
        self.from = from
        self.to = to
        self.place = place
        self.emoji = emoji
        self.favoritesOnly = favoritesOnly
    }

    public var isEmpty: Bool {
        text.trimmed.isEmpty && from == nil && to == nil && place == nil && emoji == nil && !favoritesOnly
    }

    public func matches(_ clip: Clip) -> Bool {
        if favoritesOnly && !clip.isFavorite { return false }
        if let from, clip.day < from { return false }
        if let to, clip.day > to { return false }
        if let place, clip.displayPlace != place { return false }
        if let emoji, clip.emoji != emoji { return false }
        let words = SearchText.normalize(text).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return true }
        let haystack = SearchText.haystack(clip)
        return words.allSatisfy { haystack.contains($0) }
    }

    /// Matching clips, newest first.
    public func apply(_ clips: [Clip]) -> [Clip] {
        clips.filter(matches).sorted { Clip.chronological($1, $0) }
    }
}

public enum SearchText {
    /// Lowercased, without accents, single spaces ("Città " → "citta").
    public static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
        return folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Everything a query can match: note, place, town, emoji, weather, date words.
    public static func haystack(_ c: Clip) -> String {
        let parts: [String] = [
            c.note, c.placeName ?? "", c.locality ?? "", c.emoji, c.weather?.condition ?? "",
            c.day.iso, ItalianFormat.dayTitle(c.day), ItalianFormat.monthName(c.day.month)
        ]
        return normalize(parts.joined(separator: " "))
    }

    /// Emojis used, most frequent first.
    public static func emojis(in clips: [Clip]) -> [(emoji: String, count: Int)] {
        counted(clips.map(\.emoji).filter { !$0.isEmpty })
    }

    /// Places, most recorded first.
    public static func places(in clips: [Clip]) -> [(name: String, count: Int)] {
        counted(clips.compactMap(\.displayPlace)).map { (name: $0.emoji, count: $0.count) }
    }

    private static func counted(_ values: [String]) -> [(emoji: String, count: Int)] {
        var counts: [String: Int] = [:]
        for v in values { counts[v, default: 0] += 1 }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (emoji: $0.key, count: $0.value) }
    }
}
