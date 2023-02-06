#if !SKIP
@testable import SkipDemoLib
import SkipTest
#endif
import SkipFoundation

final class SkipDemoLibTests: SkipTestCase {
    #if !SKIP
    /// The modules that should be transpiled and tested
    override var targets: SkipTargetSet? {
        SkipTargetSet(.lib("SkipDemoLib"), dependencies: [SkipTargetSet(.lib("SkipFoundation"))])
    }
    #endif

    func testSkipDemoLib() throws {
        XCTAssertEqual(3, 1 + 2)
        XCTAssertEqual("SkipDemoLib", SkipDemoLibInternalModuleName())
        XCTAssertEqual("SkipDemoLib", SkipDemoLibPublicModuleName())
        XCTAssertEqual("SkipFoundation", SkipFoundationPublicModuleName())
    }
}
