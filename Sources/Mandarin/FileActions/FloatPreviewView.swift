import SwiftUI

struct FloatPreviewView: View {
    @ObservedObject var model: FloatPreviewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close floating preview")
            }

            Image(nsImage: model.image)
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 120)

            Text(model.url.lastPathComponent)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(10)
        .frame(width: 180)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
    }
}
