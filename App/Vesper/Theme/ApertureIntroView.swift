import SwiftUI

/// Launch sequence: a run of white dots, a gold aperture that opens, the name in Didot.
struct ApertureIntroView: View {
    var done: () -> Void
    @State private var dotsX: CGFloat = -0.2
    @State private var ring: CGFloat = 0
    @State private var open: CGFloat = 0
    @State private var title = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Color.black
                ForEach(0..<6, id: \.self) { k in
                    Circle().fill(.white)
                        .frame(width: 14, height: 14)
                        .position(x: (dotsX - CGFloat(k) * 0.08) * w, y: h * 0.45)
                        .opacity(dotsX > 0.9 ? 0 : 1)
                }
                Circle()
                    .stroke(Theme.gold, lineWidth: 2)
                    .frame(width: w * 0.5 * ring + w * 2.4 * open, height: w * 0.5 * ring + w * 2.4 * open)
                    .position(x: w / 2, y: h * 0.45)
                    .opacity(1 - Double(open))
                VStack(spacing: 10) {
                    Text("VESPER").font(Theme.title(54)).foregroundStyle(Theme.gold).tracking(10)
                    Text("Private driving films").tracked(11)
                }
                .position(x: w / 2, y: h * 0.45)
                .opacity(title ? 1 : 0)
            }
            .ignoresSafeArea()
        }
        .task {
            withAnimation(.easeIn(duration: 1.0)) { dotsX = 1.2 }
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.spring(duration: 0.5)) { ring = 1 }
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation(.easeIn(duration: 0.6)) { title = true }
            try? await Task.sleep(for: .milliseconds(1100))
            withAnimation(.easeIn(duration: 0.5)) { open = 1 }
            try? await Task.sleep(for: .milliseconds(450))
            done()
        }
        .onTapGesture { done() }
    }
}
