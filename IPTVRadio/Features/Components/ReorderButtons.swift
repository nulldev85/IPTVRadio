import SwiftUI

/// One-step controls keep a saved list's identity and position unambiguous.
struct ReorderButtons: View {
    let name: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: moveUp) {
                Image(systemName: "chevron.up")
                    .frame(width: 44, height: 28)
            }
            .disabled(!canMoveUp)
            .accessibilityLabel("Move \(name) up")
            .accessibilityIdentifier("reorder.up.\(name)")

            Button(action: moveDown) {
                Image(systemName: "chevron.down")
                    .frame(width: 44, height: 28)
            }
            .disabled(!canMoveDown)
            .accessibilityLabel("Move \(name) down")
            .accessibilityIdentifier("reorder.down.\(name)")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AetherTheme.mutedIcon)
        .buttonStyle(.plain)
    }
}
