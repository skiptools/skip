#if !SKIP
import XCTest
#endif

final class ArrayTests: XCTestCase {
    func testArrayLiteralInit() {
        let emptyArray: [Int] = []
        XCTAssertEqual(emptyArray.count, 0)

        let emptyArray2: Array<Int> = []
        XCTAssertEqual(emptyArray2.count, 0)

        let emptyArray3 = [Int]()
        XCTAssertEqual(emptyArray3.count, 0)

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

    func testAppendDidSet() {
        let holder = ArrayHolder()
        XCTAssertEqual(holder.arraySetCount, 0)

        holder.array.append(1)
        XCTAssertEqual(holder.array.count, 1)
        XCTAssertEqual(holder.arraySetCount, 1)

        var array = holder.array
        XCTAssertEqual(array.count, 1)
        array.append(2)
        XCTAssertEqual(array.count, 2)
        XCTAssertEqual(holder.array.count, 1)
        XCTAssertEqual(holder.arraySetCount, 1)

        holder.array.append(3)
        holder.array.append(4)
        XCTAssertEqual(holder.array.count, 3)
        XCTAssertEqual(holder.arraySetCount, 3)
        XCTAssertEqual(array.count, 2)
    }

    func testSubscriptDidSet() {
        let holder = ArrayHolder()
        holder.array.append(1)
        XCTAssertEqual(holder.array.count, 1)
        XCTAssertEqual(holder.arraySetCount, 1)

        var array = holder.array
        array[0] = 100
        XCTAssertEqual(holder.array[0], 1)
        XCTAssertEqual(holder.array.count, 1)
        XCTAssertEqual(holder.arraySetCount, 1)

        holder.array[0] = 99
        XCTAssertEqual(holder.array[0], 99)
        XCTAssertEqual(holder.array.count, 1)
        XCTAssertEqual(holder.arraySetCount, 2)
        XCTAssertEqual(array[0], 100)
    }

    func testNestedSubscriptDidSet() {
        let holder = ArrayHolder()
        holder.arrayOfArrays.append([1, 2, 3])
        XCTAssertEqual(holder.arrayOfArrays.count, 1)
        XCTAssertEqual(holder.arraySetCount, 1)

        var array = holder.arrayOfArrays
        array[0][1] = 200
        XCTAssertEqual(holder.arrayOfArrays[0], [1, 2, 3])
        XCTAssertEqual(holder.arrayOfArrays.count, 1)
        XCTAssertEqual(holder.arraySetCount, 1)

        holder.arrayOfArrays[0][1] = 199
        XCTAssertEqual(holder.arrayOfArrays[0][1], 199)
        XCTAssertEqual(holder.arrayOfArrays.count, 1)
        XCTAssertEqual(holder.arraySetCount, 2)
        XCTAssertEqual(array[0][1], 200)
    }

    func testDeepNestedArrays() {
        var nested: [[[[[Int]]]]] = [[[[[1]]]]]
        let nested0: [[[Int]]] = [[[-1]]]

        nested[0][0][0][0][0] = nested[0][0][0][0][0] + 1
        nested[0][0] = nested0
        nested[0][0][0][0][0] = nested[0][0][0][0][0] + 1
        XCTAssertEqual(nested[0][0][0][0][0], 0)
    }

    func testArrayReferences() {
        var arr: [Int] = []
        arr.append(1)
        var arr2 = arr
        arr2.append(2)
        var arr3 = arr2
        arr3.append(3)

        arr.append(0)

        XCTAssertEqual(arr.count, 2)
        XCTAssertEqual(arr2.count, 2)
        XCTAssertEqual(arr3.count, 3)

    }
}

private class ArrayHolder {
    var array: [Int] = [] {
        didSet {
            arraySetCount += 1
        }
    }
    var arraySetCount = 0

    var arrayOfArrays: [[Int]] = [] {
        didSet {
            arraySetCount += 1
        }
    }
}
