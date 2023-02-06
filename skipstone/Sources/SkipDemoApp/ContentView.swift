#if !SKIP
import SkipDemoLib
import SkipUI

struct ContentView {
    @State private var automaton = CellularAutomaton(width: 100, height: 100)
    @State private var isResetting = false
    @State private var task: Task<Void, Error>?
    private var isRunning: Bool { self.task != nil }

    private func start() {
        self.task = Task.detached(priority: .userInitiated) {
            while true {
                try await Task.sleep(nanoseconds: 100_000_000)
                self.automaton.next()
            }
        }
    }

    private func stop() {
        self.task?.cancel()
        self.task = nil
    }
}

extension ContentView: View {
    var body: some View {
        VStack(spacing: 5) {
            Text(self.automaton.time, format: .number)
            VStack(spacing: 1) {
                ForEach(0..<self.automaton.height, id: \.self) { y in
                    HStack(spacing: 1) {
                        ForEach(0..<self.automaton.width, id: \.self) { x in
                            Rectangle()
                                .fill(self.automaton[x, y] ? .white : .black)
                                .scaledToFit()
                        }
                    }
                }
            }
            .background(.black)
            .drawingGroup()
            .onAppear {
                self.automaton.putRPentomino()
            }
            self.controls
        }
        .buttonStyle(.borderedProminent)
    }

    private var controls: some View {
        HStack {
            Button("Reset", role: .destructive) {
                self.isResetting.toggle()
            }
            //.hoverEffect()
            .disabled(self.isRunning)
            .confirmationDialog("", isPresented: self.$isResetting) { 
                Button("R-pentomino") {
                    self.automaton.clear()
                    self.automaton.putRPentomino()
                }
                Button("Random") {
                    self.automaton.clear()
                    self.automaton.putRandomly()
                }
            }
            Button(!self.isRunning ? "Start" : "Stop") {
                !self.isRunning ? self.start() : self.stop()
            }
            //hoverEffect()
            Button("Next") {
                self.automaton.next()
            }
            .keyboardShortcut("n", modifiers: .shift)
            //.hoverEffect()
            .disabled(self.isRunning)
        }
    }
}
#endif
