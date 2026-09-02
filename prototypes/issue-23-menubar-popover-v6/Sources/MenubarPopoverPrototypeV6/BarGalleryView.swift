import SwiftUI

// Same shell trick as v3's SwitcherGalleryView: real chrome above (title,
// range, summary strip) so the bar is judged in context, a fixed set of
// history rows below it, and a bottom bar to page through height options.
struct BarGalleryView: View {
    @State private var variant: BarVariant = .stock

    private var variantIndex: Int {
        BarVariant.allCases.firstIndex(of: variant) ?? 0
    }

    // Six rows straight out of MockData.history, chosen to spread across the
    // full coverage range (35% through 100%) plus one live view — the case
    // no variant touches, since a live view has no fixed length to bar.
    private let rows: [MockView] = [
        MockView(service: .youtube, title: "The Untold History of the Spreadsheet", author: "Veritasium", format: "standard", embedded: false, watched: "48m", coverage: 0.72, at: "7:20 PM"),
        MockView(service: .youtube, title: "How the ILC-2 landed 6 boosters in one night", author: "Scott Manley", format: "standard", embedded: false, watched: "1h 04m", coverage: 0.98, at: "7:02 PM"),
        MockView(service: .other, title: "Type design lecture 04 (embedded on typo.blog)", author: "typo.blog", format: "standard", embedded: true, watched: "27m", coverage: 0.35, at: "8:30 PM"),
        MockView(service: .youtube, title: "#Shorts — the one-pan trick", author: "Adam Ragusea", format: "short", embedded: false, watched: "3m", coverage: 1.0, at: "8:11 PM"),
        MockView(service: .other, title: "MIT 6.006 lecture 3 (ocw.mit.edu)", author: "ocw.mit.edu", format: "standard", embedded: false, watched: "40m", coverage: 0.5, at: "1:40 AM (Tue clock)"),
        MockView(service: .youtube, title: "lofi hip hop radio — beats to relax/study to", author: "Lofi Girl", format: "live", embedded: false, watched: "52m", coverage: nil, at: "8:30 PM"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            Divider()
            rangeRow
            Divider()
            summaryStrip
            Divider()
            historyStub
            Divider()
            variantBar
        }
        .frame(width: 380, height: 560)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text("WatchLogs").font(.headline)
            Spacer()
            Text("This Week · 13h 17m")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Image(systemName: "gearshape").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var rangeRow: some View {
        Picker("", selection: .constant(1)) {
            Text("Today").tag(0)
            Text("This Week").tag(1)
            Text("This Month").tag(2)
            Text("Custom").tag(3)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var summaryStrip: some View {
        HStack(spacing: 16) {
            ForEach([Service.youtube, .netflix, .twitch], id: \.self) { service in
                HStack(spacing: 5) {
                    ServiceLogo(service: service, size: 14)
                    Text(MockData.formatMinutes(MockData.serviceTotals(over: 25...29)[service] ?? 0))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var historyStub: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History")
                .font(.title3.weight(.semibold))
            Text("Same six rows, six coverage levels (35%–100%, plus one live). Only the bar below each title changes between variants.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: variant.rowSpacing) {
                ForEach(rows) { row in
                    BarRow(view: row, variant: variant)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }

    private var variantBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    let all = BarVariant.allCases
                    variant = all[(variantIndex - 1 + all.count) % all.count]
                } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)

                Text(variant.name)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)

                Button {
                    let all = BarVariant.allCases
                    variant = all[(variantIndex + 1) % all.count]
                } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)

                Text("\(variantIndex + 1)/\(BarVariant.allCases.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Text(variant.note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(height: 118, alignment: .top)
        .background(Color.primary.opacity(0.04))
    }
}

// Same row shape as HistoryPane's ViewRow (logo, title, author/time/format
// pills, watched duration) — only the bar underneath swaps with `variant`.
private struct BarRow: View {
    let view: MockView
    let variant: BarVariant

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                ServiceLogo(service: view.service, size: 14)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 1) {
                    Text(view.title)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 5) {
                        Text(view.author)
                        Text("·")
                        Text(view.at)
                        if view.format != "standard" {
                            Text(view.format)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .background(view.format == "live" ? view.service.color.opacity(0.15) : Color.secondary.opacity(0.12))
                                .foregroundStyle(view.format == "live" ? view.service.color : .secondary)
                                .clipShape(Capsule())
                        }
                        if view.embedded {
                            Text("embedded")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .background(.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(view.watched)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if let coverage = view.coverage {
                if let height = variant.height {
                    DurationBar(coverage: coverage, height: height, tint: .accentColor)
                        .padding(.leading, 22)
                        .padding(.top, variant.barTopGap - 4) // 4pt is the VStack's own spacing, already accounted for
                } else {
                    ProgressView(value: coverage)
                        .tint(.accentColor)
                        .padding(.leading, 22)
                }
            } else {
                Text("Live · no fixed length")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 22)
            }
        }
    }
}
