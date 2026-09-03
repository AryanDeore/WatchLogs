import SwiftUI

@main
struct AppLogoConceptsApp: App {
    var body: some Scene {
        // Concept A, live in the actual menu bar — not a swatch mockup.
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                Text("Concept A — logs + watch").font(.headline)
                LogPlayMark(size: 60, color: AppLogoTheme.accent)
                    .padding(8)
            }
            .padding(12)
        } label: {
            Image(nsImage: .logPlayMarkTemplate(pointSize: 18))
        }

        WindowGroup {
            GalleryView()
                .frame(width: 900, height: 640)
        }
        .windowResizability(.contentSize)
    }
}

struct GalleryView: View {
    var body: some View {
        HStack(spacing: 0) {
            ConceptColumn(
                title: "A — logs + watch",
                subtitle: "Three log-entry bars stepped into a play triangle.",
                mark: { size, color in AnyView(LogPlayMark(size: size, color: color)) }
            )
            Divider()
            ConceptColumn(
                title: "B — Watch_Dogs mark",
                subtitle: "Circle, pillars, and a woven hourglass — the WatchLogs / Watch Dogs pun.",
                mark: { size, color in AnyView(WatchDogsMark(size: size, color: color)) }
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ConceptColumn: View {
    let title: String
    let subtitle: String
    let mark: (CGFloat, Color) -> AnyView

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .padding(.top, 20)

            swatch(background: .white, label: "app icon, light", size: 160)
            swatch(background: .black, label: "app icon, dark", size: 160)

            HStack(spacing: 16) {
                menuBarSwatch(background: .white)
                menuBarSwatch(background: .black)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 20)
    }

    private func swatch(background: Color, label: String, size: CGFloat) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(background)
                .frame(width: size, height: size)
                .overlay {
                    mark(size * 0.62, background == .white ? .black.opacity(0.85) : .white)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .stroke(.gray.opacity(0.2), lineWidth: 1)
                }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func menuBarSwatch(background: Color) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(background)
                .frame(width: 44, height: 28)
                .overlay {
                    mark(16, background == .white ? .black.opacity(0.85) : .white)
                }
            Text("menu bar, \(background == .white ? "light" : "dark")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
