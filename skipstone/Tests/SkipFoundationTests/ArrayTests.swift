#if !SKIP
@testable import SkipFoundation
import SkipUnit
#endif

final class ArrayTests: XCTestCase {
    func testArrayLiteralInit() {
        let emptyArray: [Int] = []
        XCTAssertEqual(emptyArray.count, 0)

        let emptyArray2: Array<Int> = []
        XCTAssertEqual(emptyArray2.count, 0)

        let singleElementArray = [1]
        XCTAssertEqual(singleElementArray.count, 1)

        let multipleElementArray = [1, 2]
        XCTAssertEqual(multipleElementArray.count, 2)
    }

    func testArrayAppend() {
        var array = [1, 2]
        array.append(3)
        XCTAssertEqual(array.count, 3)

        var array2 = array
        array2.append(4)
        XCTAssertEqual(array2.count, 4)
//        XCTAssertEqual(array.count, 3)
    }
}
