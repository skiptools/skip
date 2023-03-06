//#if !SKIP
//import XCTest
//#endif
//
//final class StructTests: XCTestCase {
//    func testStructMutate() {
//        var struct1a = Struct1(i: 2)
//        struct1a.i += 1
//        XCTAssertEqual(struct1a.i, 3)
//
//        var struct1b = struct1a
//        struct1b.i += 1
//        XCTAssertEqual(struct1b.i, 4)
//        XCTAssertEqual(struct1a.i, 3)
//    }
//
//    func testStructMutateDidSet() {
//        let holder = StructHolder()
//        XCTAssertEqual(holder.structSetCount, 0)
//
//        holder.struct1.i += 1
//        XCTAssertEqual(holder.struct1.i, 1)
//        XCTAssertEqual(holder.structSetCount, 1)
//
//        var struct1 = holder.struct1
//        XCTAssertEqual(struct1.i, 1)
//        struct1.i += 1
//        XCTAssertEqual(struct1.i, 2)
//        XCTAssertEqual(holder.struct1.i, 1)
//        XCTAssertEqual(holder.structSetCount, 1)
//
//        holder.struct1.i += 2
//        XCTAssertEqual(holder.struct1.i, 3)
//        XCTAssertEqual(holder.structSetCount, 2)
//        XCTAssertEqual(struct1.i, 2)
//    }
//
//    func testNestedStructDidSet() {
//        let holder = StructHolder()
//        holder.struct2.s1.i = 3
//        XCTAssertEqual(holder.struct2.s1.i, 3)
//        XCTAssertEqual(holder.structSetCount, 1)
//
//        var struct2 = holder.struct2
//        struct2.s1.i = 2
//        XCTAssertEqual(holder.struct2.s1.i, 3)
//        XCTAssertEqual(holder.structSetCount, 1)
//
//        holder.struct2.s1.i = 1
//        XCTAssertEqual(holder.struct2.s1.i, 1)
//        XCTAssertEqual(holder.structSetCount, 2)
//        XCTAssertEqual(struct2.s1.i, 2)
//    }
//
//    func testStructReferences() {
//        var struct1a = Struct1()
//        struct1a.i += 1
//        var struct1b = struct1a
//        struct1b.i += 1
//        var struct1c = struct1b
//        struct1c.i += 1
//
//        struct1a.i += 1
//
//        XCTAssertEqual(struct1a.i, 2)
//        XCTAssertEqual(struct1b.i, 2)
//        XCTAssertEqual(struct1c.i, 3)
//
//    }
//}
//
//private struct Struct1 {
//    var i = 0
//}
//
//private struct Struct2 {
//    var s1 = Struct1()
//}
//
//private class StructHolder {
//    var struct1 = Struct1() {
//        didSet {
//            structSetCount += 1
//        }
//    }
//    var struct2 = Struct2() {
//        didSet {
//            structSetCount += 1
//        }
//    }
//    var structSetCount = 0
//}
