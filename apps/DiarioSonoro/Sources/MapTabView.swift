import SwiftUI
import MapKit
import SonoroCore

/// Every place where something was recorded, grouped by area.
struct MapTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var filter = MapFilter()
    @State private var position: MapCameraPosition = .automatic
    @State private var latitudeDelta: Double = 1.5
    @State private var selected: PlaceSpot?

    var body: some View {
        let clips = filter.apply(model.data.clips)
        let spots = PlaceSpots.spots(from: clips)
        let clusters = MapClusterer.clusters(spots, cell: MapClusterer.cellSize(latitudeDelta: latitudeDelta))
        let maxCount = max(1, clusters.map(\.clipCount).max() ?? 1)
        Map(position: $position) {
            ForEach(clusters) { c in
                Annotation(c.title, coordinate: CLLocationCoordinate2D(latitude: c.center.lat, longitude: c.center.lon)) {
                    Button {
                        tap(c)
                    } label: {
                        ClusterMarker(cluster: c, size: size(c.clipCount, max: maxCount))
                    }
                    .buttonStyle(.plain)
                }
                .annotationTitles(.hidden)
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { ctx in
            latitudeDelta = ctx.region.span.latitudeDelta
        }
        .safeAreaInset(edge: .top) { controls }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selected) { spot in
            SpotSheet(spot: spot)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(32)
        }
        .overlay {
            if clips.isEmpty {
                EmptyStateView(icon: "map", title: filter.isEmpty ? "La mappa è vuota" : "Nessuna clip con questi filtri",
                               message: filter.isEmpty
                               ? "Le clip registrate con la posizione attiva compaiono qui, raggruppate per zona."
                               : "Prova a cambiare anno o periodo.")
                    .background(m3.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(24)
            }
        }
        .onAppear { fit(spots) }
    }

    private func size(_ count: Int, max: Int) -> CGFloat {
        CGFloat(34 + 30 * sqrt(Double(count) / Double(max)))
    }

    private func tap(_ c: MapCluster) {
        if c.isSingleSpot {
            selected = c.spots[0]
        } else {
            fit(c.spots, animated: true)
        }
    }

    private func fit(_ spots: [PlaceSpot], animated: Bool = false) {
        guard let r = MapClusterer.region(fitting: spots.map(\.center), margin: 1.6, minimumSpan: 0.01) else { return }
        let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: r.center.lat, longitude: r.center.lon),
                                        span: MKCoordinateSpan(latitudeDelta: r.latitudeDelta, longitudeDelta: r.longitudeDelta))
        latitudeDelta = r.latitudeDelta
        if animated {
            withAnimation(.easeInOut(duration: 0.6)) { position = .region(region) }
        } else {
            position = .region(region)
        }
    }

    private var controls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("Tutti gli anni") { filter.year = nil }
                    ForEach(model.data.years, id: \.self) { y in
                        Button(String(y)) { filter.year = y }
                    }
                } label: {
                    ChipLabel(title: filter.year.map(String.init) ?? "Anno", icon: "calendar", selected: filter.year != nil, showsChevron: true)
                }
                Menu {
                    Button("Tutto l'anno") { filter.season = nil }
                    ForEach(Season.allCases) { s in
                        Button { filter.season = s } label: { Label(s.label, systemImage: s.symbol) }
                    }
                } label: {
                    ChipLabel(title: filter.season?.label ?? "Stagione", icon: filter.season?.symbol ?? "leaf",
                              selected: filter.season != nil, showsChevron: true)
                }
                Menu {
                    Button("Tutto il giorno") { filter.timeOfDay = nil }
                    ForEach(TimeOfDay.allCases) { t in
                        Button { filter.timeOfDay = t } label: { Label(t.label, systemImage: t.symbol) }
                    }
                } label: {
                    ChipLabel(title: filter.timeOfDay?.label ?? "Ora", icon: filter.timeOfDay?.symbol ?? "clock",
                              selected: filter.timeOfDay != nil, showsChevron: true)
                }
                Chip(title: "Preferiti", icon: "star", selected: filter.favoritesOnly) { filter.favoritesOnly.toggle() }
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}

/// Round marker: the bigger, the more clips. Clusters show how many places.
struct ClusterMarker: View {
    @Environment(\.m3) private var m3
    let cluster: MapCluster
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(cluster.isSingleSpot ? m3.primary : m3.primaryContainer)
                .overlay(Circle().strokeBorder(.white.opacity(0.92), lineWidth: 2.5))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            VStack(spacing: -1) {
                if cluster.isSingleSpot {
                    Image(systemName: "waveform")
                        .font(.system(size: size * 0.32, weight: .bold))
                    if cluster.clipCount > 1 {
                        Text("\(cluster.clipCount)")
                            .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                    }
                } else {
                    Text("\(cluster.clipCount)")
                        .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                }
            }
            .monospacedDigit()
            .foregroundStyle(cluster.isSingleSpot ? m3.onPrimary : m3.onPrimaryContainer)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(cluster.title), \(ItalianFormat.clips(cluster.clipCount))")
    }
}

/// The clips of one place.
struct SpotSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    let spot: PlaceSpot

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(spot.name)
                                .font(.m3HeadlineSmall)
                                .foregroundStyle(m3.onSurface)
                            Text(subtitle)
                                .font(.m3BodyMedium)
                                .foregroundStyle(m3.onSurfaceVariant)
                        }
                        Spacer()
                        PlayButton(playing: false, size: 52) { model.playAll(spot.clips) }
                    }
                    .padding(.top, 20)
                    VStack(spacing: 0) {
                        ForEach(Array(spot.clips.prefix(100).enumerated()), id: \.element.id) { i, clip in
                            ClipRow(clip: clip, list: spot.clips, isFirst: i == 0, isLast: i == min(spot.clips.count, 100) - 1, showDate: true)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(m3.surface)
        }
    }

    private var subtitle: String {
        let days = Set(spot.clips.map(\.day)).count
        var parts = [ItalianFormat.clips(spot.count), ItalianFormat.days(days)]
        if let first = spot.clips.last?.day { parts.append("dal \(ItalianFormat.dayShort(first))") }
        return parts.joined(separator: " · ")
    }
}
