import Dispatch
import Foundation
import Testing

@Test @MainActor func mainActorFunction() async {
    expectMainThread()
    await Task.yield()
    expectMainThread()
}

@MainActor private func expectMainThread() {
    MainActor.assertIsolated()
    #expect(Thread.isMainThread)
}

@Suite @MainActor struct MainActorSuite {
    init() {
        MainActor.assertIsolated()
        #expect(Thread.isMainThread)
    }

    @Test func dispatchMainRoundTrip() async {
        let isMainThread = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                MainActor.assertIsolated()
                continuation.resume(returning: Thread.isMainThread)
            }
        }
        #expect(isMainThread)
        MainActor.assertIsolated()
    }
}

@Test func workerCanHopToMainActor() async {
    let isMainThread = await MainActor.run {
        MainActor.assertIsolated()
        return Thread.isMainThread
    }
    #expect(isMainThread)
}
