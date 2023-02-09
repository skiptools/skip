#if !SKIP
@testable import SkipFoundation
import XCTest
#endif

final class RandomTests: XCTestCase {
    var logger = Logger(subsystem: "test", category: "RandomNumberGeneratorTests")

    /// Verify that the system RNG is at least a little bit random.
    func testSystemRandomNumberGenerator() throws {
        var rng = SystemRandomNumberGenerator()
        XCTAssertNotEqual(rng.next(), rng.next())
        XCTAssertNotEqual(rng.next(), rng.next())
        XCTAssertNotEqual(rng.next(), rng.next())
        XCTAssertNotEqual(rng.next(), rng.next())
        XCTAssertNotEqual(rng.next(), rng.next())
    }

    /// Verifies that a sequence of seeded longs returns the same numbers in Swift and Java.
    func testGenerateLongs() throws {
        var rng = PseudoRandomNumberGenerator.seeded(seed: 1153443)
        XCTAssertEqual(778315946, rng.nextInt())
        XCTAssertEqual(-1911835035, rng.nextInt())

        var rng2 = PseudoRandomNumberGenerator.seeded(seed: 1153443)
        XCTAssertEqual(3342841532113466981, rng2.nextLong())
        XCTAssertEqual(-1937911856631837073, rng2.nextLong())
        XCTAssertEqual(-5162554212297512938, rng2.nextLong())
        XCTAssertEqual(4631059369955418223, rng2.nextLong())
        XCTAssertEqual(5587727113876742984, rng2.nextLong())
        XCTAssertEqual(8208775721452975439, rng2.nextLong())
        XCTAssertEqual(6820644158221888535, rng2.nextLong())
        XCTAssertEqual(-2248895836959927114, rng2.nextLong())
        XCTAssertEqual(3805200544954129882, rng2.nextLong())
        XCTAssertEqual(283760875724908671, rng2.nextLong())
        XCTAssertEqual(-883510693287642453, rng2.nextLong())
    }

    func testGenerateBools() throws {
        var rng = PseudoRandomNumberGenerator.seeded(seed: 34789)
        XCTAssertEqual(true, rng.nextBoolean())
        XCTAssertEqual(true, rng.nextBoolean())
        XCTAssertEqual(false, rng.nextBoolean())
    }

    func testGenerateInts() throws {
        var rng = PseudoRandomNumberGenerator.seeded(seed: 8832)
        XCTAssertEqual(-160123848, rng.nextInt())
        XCTAssertEqual(222216155, rng.nextInt())
        XCTAssertEqual(1087824573, rng.nextInt())
    }

    func testGenerateUUIDs() throws {
        var rng = PseudoRandomNumberGenerator.seeded(seed: 487903)
        XCTAssertEqual("0DFDC8B1-78A0-417C-AB5D-A7F833BD7F4C", rng.nextUUID().uuidString)
        XCTAssertEqual("FE6726B6-80C6-7445-E8C2-8425B244CEEB", rng.nextUUID().uuidString)
        XCTAssertEqual("50E99788-4980-3E68-B3FD-766EBA3EBF2B", rng.nextUUID().uuidString)
        XCTAssertEqual("F7B264C1-5E7E-1AFB-EF21-654034C63FAA", rng.nextUUID().uuidString)
        XCTAssertEqual("EDEDD29D-5FED-E7D7-DD17-FC618D57435D", rng.nextUUID().uuidString)
    }
}
