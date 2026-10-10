import SwiftUI

private struct GlassProbe: View {
    var body: some View {
        VStack {
            Text("Card")
                .appGlassCard()
            Text("Chrome")
                .appGlassChrome()
            Button("Plain") {}
                .appGlassButton()
            Button("Prominent") {}
                .appGlassButton(prominent: true)
        }
    }
}

@main
enum TestAppGlass {
    static func main() {
        _ = GlassProbe()
    }
}
