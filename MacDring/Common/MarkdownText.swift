import SwiftUI

/// A lightweight Markdown renderer for the notes tab's **preview** mode. Handles the
/// "basic" Markdown a quick note uses: ATX headings (`#`–`###`), bullet lists
/// (`-`/`*`), and inline emphasis / code / links (via `AttributedString`). Block
/// parsing is line-based and **pure** (`classify`) so it's unit-testable; full
/// CommonMark (nested lists, tables, code fences, blockquotes, …) is out of scope.
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(text.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, raw in
                view(for: MarkdownText.classify(raw))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for line: Line) -> some View {
        switch line {
        case .blank:
            Color.clear.frame(height: 4)
        case .heading(let level, let text):
            inline(text).font(MarkdownText.headingFont(level)).bold()
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                inline(text)
            }
        case .paragraph(let text):
            inline(text)
        }
    }

    /// Inline emphasis / code / links via `AttributedString`; plain text on failure.
    private func inline(_ string: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(string)
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        default: return .headline
        }
    }

    // MARK: Pure line classification

    enum Line: Equatable {
        case blank
        case heading(level: Int, text: String)
        case bullet(text: String)
        case paragraph(text: String)
    }

    /// Classifies one line of Markdown. Pure, so it's unit-testable independently of
    /// the (hard-to-assert) inline `AttributedString` rendering.
    static func classify(_ raw: String) -> Line {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .blank }
        // ATX heading: 1–6 leading '#' followed by a space (rendered at up to 3 sizes).
        if trimmed.hasPrefix("#") {
            var level = 0
            var rest = Substring(trimmed)
            while rest.first == "#" { level += 1; rest = rest.dropFirst() }
            if level <= 6, rest.first == " " {
                return .heading(level: min(level, 3), text: String(rest).trimmingCharacters(in: .whitespaces))
            }
        }
        // Bullet list item: '- ' or '* '.
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            return .bullet(text: String(trimmed.dropFirst(2)))
        }
        return .paragraph(text: raw)
    }
}
