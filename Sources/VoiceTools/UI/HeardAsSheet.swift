import AppKit
import SwiftUI

/// A word's whole Heard-as list, for when it's too long for one comma-separated field: alphabetical, searchable,
/// one row per mishearing with its own remove button, and a field to add one. Results in another script (a Latin
/// word heard as Cyrillic) and all-dictionary-word results (which could change text you meant) are marked, since
/// they're the ones most worth removing.
struct HeardAsSheet: View {
    @Binding var entry: VocabularyEntry
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var adding = ""
    /// Dictionary checks are slow-ish (NSSpellChecker), so they're done once per list.
    @State private var ordinary: Set<String> = []

    private var sorted: [String] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return entry.heardAs
            .filter { q.isEmpty || $0.lowercased().contains(q) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var otherScript: [String] {
        guard !VocabularyTrainer.hasOtherScript(entry.write.lowercased()) else { return [] }
        return entry.heardAs.filter { VocabularyTrainer.hasOtherScript($0.lowercased()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Heard as · \(entry.write)").font(VPFont.title)
                    Text("\(entry.heardAs.count) \(entry.heardAs.count == 1 ? "spelling" : "spellings") replaced with “\(entry.write)” wherever they come out.")
                        .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                VPTextField("Search", text: $search).frame(maxWidth: 220)
                Spacer()
                VPTextField("Add a spelling", text: $adding, onSubmit: add).frame(maxWidth: 240)
                Button("Add", action: add).buttonStyle(.vpSecondary)
                    .disabled(adding.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !otherScript.isEmpty {
                HStack(spacing: 10) {
                    Text("\(otherScript.count) in another script (the model guessing another language): these never match what you write.")
                        .font(VPFont.caption).foregroundStyle(Palette.orange).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Remove them") {
                        let drop = Set(otherScript)
                        set(entry.heardAs.filter { !drop.contains($0) })
                    }
                    .buttonStyle(.vpGhost)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element) { index, heard in
                        if index > 0 { Hairline() }
                        row(heard)
                    }
                }
                .vpCard()
            }
            .frame(minHeight: 200, maxHeight: 460)
            if sorted.isEmpty {
                Text(search.isEmpty ? "None yet. Train the word, or add spellings above." : "Nothing matches “\(search)”.")
                    .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
            }
            HStack {
                Text("Changes save as you make them.").font(VPFont.caption).foregroundStyle(Palette.comment)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.vpPrimary).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620)
        .background(Palette.bg100)
        .vpWindow()
        .onAppear(perform: checkOrdinary)
        .onChange(of: entry.heardAs) { _, _ in checkOrdinary() }
    }

    private func row(_ heard: String) -> some View {
        HStack(spacing: 10) {
            Text(heard).font(VPFont.body).foregroundStyle(Palette.fg).lineLimit(1).truncationMode(.tail)
            if VocabularyTrainer.hasOtherScript(heard.lowercased()), !VocabularyTrainer.hasOtherScript(entry.write.lowercased()) {
                Text("other script").font(VPFont.caption).foregroundStyle(Palette.orange)
            } else if ordinary.contains(heard) {
                Text("ordinary words").font(VPFont.caption).foregroundStyle(Palette.orange)
                    .help("Every word is in the dictionary, so replacing it could change text you meant")
            }
            Spacer()
            Button {
                // A copy, not a read through the binding while it changes (exclusive access).
                let drop = heard
                set(entry.heardAs.filter { $0 != drop })
            } label: { Image(systemName: "xmark") }
                .buttonStyle(.vpIcon)
                .help("Remove “\(heard)”")
        }
        .padding(.horizontal, 12).frame(minHeight: 34)
    }

    private func add() {
        let new = adding.trimmingCharacters(in: .whitespaces)
        guard !new.isEmpty else { return }
        if !entry.heardAs.contains(where: { $0.caseInsensitiveCompare(new) == .orderedSame }) { set(entry.heardAs + [new]) }
        adding = ""
    }

    private func set(_ heard: [String]) {
        entry.heardAs = heard
        entry.heardAsText = nil  // the row's comma field shows the list again
    }

    private func checkOrdinary() {
        ordinary = Set(entry.heardAs.filter { VocabularyTrainer.isAllDictionaryWords($0.lowercased()) })
    }
}
