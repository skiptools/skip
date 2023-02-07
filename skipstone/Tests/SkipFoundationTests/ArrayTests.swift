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

        // TODO: FIXME
//        let emptyArray3 = [Int]()
//        XCTAssertEqual(emptyArray3.count, 0)

        let emptyArray4 = Array<Int>()
        XCTAssertEqual(emptyArray4.count, 0)

        let singleElementArray = [1]
        XCTAssertEqual(singleElementArray.count, 1)
        XCTAssertEqual(singleElementArray[0], 1)

        let multipleElementArray = [1, 2]
        XCTAssertEqual(multipleElementArray.count, 2)
        XCTAssertEqual(multipleElementArray[0], 1)
        XCTAssertEqual(multipleElementArray[1], 2)
    }

    func testArrayAppend() {
        var array = [1, 2]
        array.append(3)
        XCTAssertEqual(array.count, 3)
        XCTAssertEqual(array[2], 3)

        var array2 = array
        array2.append(4)
        XCTAssertEqual(array2.count, 4)
        XCTAssertEqual(array2[3], 4)

        XCTAssertEqual(array.count, 3)
    }
}
