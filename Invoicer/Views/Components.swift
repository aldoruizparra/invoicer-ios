import InvoicerKit
import SwiftUI

/// "Label   [text field]" hairline row (Business › Name, etc.).
struct FieldRow: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var first = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var capitalization: TextInputAutocapitalization = .words
    var labelWidth: CGFloat = 92
    var invalid = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(minWidth: labelWidth, alignment: .leading)
                .fixedSize()
            TextField(placeholder, text: $text, axis: .horizontal)
                .keyboardType(keyboard)
                .textContentType(contentType)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(keyboard != .default)
                .foregroundStyle(invalid ? Color.destructive : Color.inkSecondary)
                .accessibilityLabel(label)
        }
        .hairlineCell(first: first)
    }
}

/// "Label ............ [value field]" with an optional prefix/suffix (tax %, #number).
struct TrailingFieldRow: View {
    let label: String
    @Binding var text: String
    var prefix = ""
    var suffix = ""
    var placeholder = ""
    var first = false
    var keyboard: UIKeyboardType = .decimalPad
    var width: CGFloat = 90
    var invalid = false

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
            Spacer(minLength: 8)
            if !prefix.isEmpty { Text(prefix).foregroundStyle(Color.inkSecondary) }
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .fixedSize()
                .frame(minWidth: 44, maxWidth: width, alignment: .trailing)
                .foregroundStyle(invalid ? Color.destructive : Color.inkSecondary)
                .accessibilityLabel(label)
            if !suffix.isEmpty { Text(suffix).foregroundStyle(Color.inkSecondary) }
        }
        .hairlineCell(first: first)
    }
}

/// "Label ............ value" read-only row.
struct ValueRow: View {
    let label: String
    let value: String
    var first = false
    var minHeight: CGFloat = 44
    var secondary = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label).foregroundStyle(secondary ? Color.inkSecondary : Color.ink)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing).monospacedDigit()
        }
        .hairlineCell(first: first, minHeight: minHeight, verticalPadding: 10)
        .accessibilityElement(children: .combine)
    }
}

/// Title + subtitle, used in lists of saved entries.
struct TwoLineLabel: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).foregroundStyle(Color.ink)
            if !subtitle.isEmpty {
                Text(subtitle).font(.barlow(14, relativeTo: .subheadline)).foregroundStyle(Color.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }
}

/// Footnote under a group.
struct Footnote: View {
    let text: String
    var color: Color = .inkSecondary
    init(_ text: String, color: Color = .inkSecondary) { self.text = text; self.color = color }

    var body: some View {
        Text(text)
            .font(.barlow(13, relativeTo: .footnote))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .plainRow(top: 8, bottom: 0)
    }
}

/// Header for a List section, padded like the prototype.
@MainActor
func header(_ title: String) -> some View {
    SectionHeader(title).padding(.top, 14)
}

/// Total row: condensed uppercase label, large condensed amount.
struct TotalRow: View {
    let amount: String
    var size: CGFloat = 24

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Total").font(.condensed(20, relativeTo: .title3)).tracking(20 * 0.04).textCase(.uppercase)
            Spacer()
            Text(amount).font(.condensed(size, relativeTo: .title2)).monospacedDigit()
        }
        .hairlineCell(minHeight: 54)
        .accessibilityElement(children: .combine)
    }
}

/// Dismiss the keyboard from anywhere (number pads have no Return key).
@MainActor
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
