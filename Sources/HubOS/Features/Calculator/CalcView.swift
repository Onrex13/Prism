import SwiftUI
import AppKit

/// Text-first calculator: type an expression, see the result live, copy it, and
/// reuse past calculations from the history.
struct CalcView: View {
    @Bindable private var calc = CalcManager.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            inputCard
            if !calc.history.isEmpty { historySection }
            else { hint }
        }
        .padding(18)
        .frame(width: Theme.panelWidth)
        .animation(.smooth(duration: 0.2), value: calc.history)
        .onAppear { focused = true }
    }

    private var inputCard: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "plusminus").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.teal)
                TextField(L(fr: "ex. 20% of 350", en: "e.g. 20% of 350"), text: $calc.input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .focused($focused)
                    .onSubmit { calc.commit() }
                if !calc.input.isEmpty {
                    Button { calc.input = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }.buttonStyle(.plain)
                }
            }
            Divider().opacity(0.12)
            HStack {
                Text("=").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(.tertiary)
                Text(calc.liveResult ?? "—")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(calc.liveResult == nil ? .secondary : .primary)
                    .contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer()
                if let r = calc.liveResult {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(r, forType: .string)
                        Notifier.shared.success(L(fr: "Copié · \(r)", en: "Copied · \(r)"))
                        calc.commit()
                    } label: {
                        Label(L(fr: "Copier", en: "Copy"), systemImage: "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.glassProminent).controlSize(.small).tint(Theme.teal)
                }
            }
        }
        .padding(14).glassCard(radius: 18)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: L(fr: "Historique", en: "History"))
                Spacer()
                Button { calc.clear() } label: {
                    Text(L(fr: "Effacer", en: "Clear")).font(.system(size: 10, weight: .medium))
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }.padding(.horizontal, 2)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(calc.history) { entry in
                        Button { calc.reuse(entry) } label: {
                            HStack {
                                Text(entry.expr)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 8)
                                Text("= \(entry.result)")
                                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if entry.id != calc.history.last?.id {
                            Divider().opacity(0.1).padding(.horizontal, 12)
                        }
                    }
                }
            }
            .frame(maxHeight: 220).scrollIndicators(.hidden)
            .glassCard(radius: 14)
        }
    }

    private var hint: some View {
        VStack(spacing: 8) {
            Image(systemName: "plusminus").font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.teal.opacity(0.8))
            Text(L(fr: "Tape un calcul", en: "Type a calculation")).font(.system(size: 13, weight: .semibold))
            Text(L(fr: "+ − × ÷ ( ) ^ %, et « % of ». Entrée pour enregistrer.",
                   en: "+ − × ÷ ( ) ^ %, and “% of”. Return to save."))
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(height: 150)
    }
}
