import SwiftUI

struct WhatsNewSheet: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(WhatsNew.title)
                .font(.headline)

            ForEach(WhatsNew.lines, id: \.self) { line in
                Text(line)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(WhatsNew.continueTitle, action: onContinue)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding(16)
        .frame(width: 420, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
