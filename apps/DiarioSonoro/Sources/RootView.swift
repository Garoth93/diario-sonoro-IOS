import SwiftUI
import SonoroCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(PlayerModel.self) private var player
    @Environment(\.m3) private var m3

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("Registra", systemImage: "mic.fill", value: AppTab.record) {
                NavigationStack { RecordView() }
                    .withMiniPlayer()
            }
            Tab("Calendario", systemImage: "calendar", value: AppTab.calendar) {
                NavigationStack(path: $model.calendarPath) {
                    CalendarView()
                        .navigationDestination(for: CalendarRoute.self) { route in
                            switch route {
                            case .day(let d): DayView(day: d)
                            case .search: SearchView()
                            case .anniversary: AnniversaryView()
                            }
                        }
                }
                .withMiniPlayer()
            }
            Tab("Mappa", systemImage: "map.fill", value: AppTab.map) {
                NavigationStack { MapTabView() }
                    .withMiniPlayer()
            }
            Tab("Statistiche", systemImage: "chart.bar.fill", value: AppTab.stats) {
                NavigationStack { StatsView() }
                    .withMiniPlayer()
            }
            Tab("Impostazioni", systemImage: "gearshape.fill", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .alert("Attenzione", isPresented: Binding(
            get: { model.errorMessage != nil || player.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil; player.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                model.errorMessage = nil
                player.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? player.errorMessage ?? "")
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { model.toast = nil }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.toast)
        .overlay {
            if model.isLocked {
                LockView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.isLocked)
    }
}

/// Face ID screen shown over everything when the lock is on.
struct LockView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            AppMark(size: 96)
            VStack(spacing: 6) {
                Text("Diario Sonoro")
                    .font(.m3HeadlineMedium)
                    .foregroundStyle(m3.onSurface)
                Text("Il tuo diario è protetto")
                    .font(.m3BodyMedium)
                    .foregroundStyle(m3.onSurfaceVariant)
            }
            Spacer()
            PillButton(title: "Sblocca con \(DeviceAuth.biometryName)", icon: "faceid", tones: m3.primaryTones) {
                Task { await model.unlock() }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(m3.surface)
        .task { await model.unlock() }
    }
}

extension View {
    /// Mini player above the tab bar, only while something is loaded.
    func withMiniPlayer() -> some View {
        modifier(MiniPlayerInset())
    }
}

private struct MiniPlayerInset: ViewModifier {
    @Environment(PlayerModel.self) private var player

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if player.isActive {
                MiniPlayerBar()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: player.isActive)
    }
}
