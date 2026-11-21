import SwiftUI
import WidgetKit
import SonoroCore

/// The widgets drawn inside the app, on a Lock Screen–like background.
/// Opened with `-demo -screen widgets` to take the CI screenshot.
struct WidgetGalleryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3

    var body: some View {
        let snapshot = WidgetSnapshot.make(data: model.data, today: model.today)
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 2) {
                    Text(ItalianFormat.capitalized(ItalianFormat.dayTitleNoYear(model.today)))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("9:41")
                        .font(.system(size: 88, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.top, 36)

                HStack(spacing: 14) {
                    TodayWidgetContent(snapshot: snapshot, family: .accessoryCircular)
                        .frame(width: 72, height: 72)
                    TodayWidgetContent(snapshot: snapshot, family: .accessoryRectangular)
                        .frame(width: 172, height: 72)
                }
                .foregroundStyle(.white)
                .environment(\.colorScheme, .dark)

                TodayWidgetContent(snapshot: snapshot, family: .accessoryInline)
                    .foregroundStyle(.white)
                    .font(.system(size: 15, weight: .semibold))

                Text("Home")
                    .font(.m3LabelLarge)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 18)
                HStack(spacing: 16) {
                    widget(snapshot, .systemSmall).frame(width: 170, height: 170)
                    controlPreview
                }
                widget(snapshot, .systemMedium).frame(width: 356, height: 170)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 40)
        }
        .background(
            LinearGradient(colors: [Color(red: 0.16, green: 0.12, blue: 0.11), Color(red: 0.45, green: 0.22, blue: 0.15)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    private func widget(_ s: WidgetSnapshot, _ family: WidgetFamily) -> some View {
        TodayWidgetContent(snapshot: s, family: family)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WidgetBackground())
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }

    /// Control Center button look.
    private var controlPreview: some View {
        VStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(m3.primary, in: Circle())
            Text("Registra suono")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 170, height: 170)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}
