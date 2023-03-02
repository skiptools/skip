#if !SKIP
import XCTest
#endif

final class DictionaryTests: XCTestCase {
    func testDictionaryLiteralInit() {
        let emptyDictionary: [String: Int] = [:]
        XCTAssertEqual(emptyDictionary.count, 0)

        let emptyDictionary2: Dictionary<String, Int> = [:]
        XCTAssertEqual(emptyDictionary2.count, 0)

        let emptyDictionary3 = [String: Int]()
        XCTAssertEqual(emptyDictionary3.count, 0)

        let emptyDictionary4 = Dictionary<String, Int>()
        XCTAssertEqual(emptyDictionary4.count, 0)

        let singleElementDictionary = ["a": 1]
        XCTAssertEqual(singleElementDictionary.count, 1)
        XCTAssertEqual(singleElementDictionary["a"], 1)

        let multipleElementDictionary = ["a": 1, "b": 2]
        XCTAssertEqual(multipleElementDictionary.count, 2)
        XCTAssertEqual(multipleElementDictionary["a"], 1)
        XCTAssertEqual(multipleElementDictionary["b"], 2)
    }

    func testSubscriptDidSet() {
        let holder = DictionaryHolder()
        holder.dictionary["a"] = 1
        XCTAssertEqual(holder.dictionary.count, 1)
        XCTAssertEqual(holder.dictionarySetCount, 1)

        var dictionary = holder.dictionary
        dictionary["a"] = 100
        XCTAssertEqual(holder.dictionary["a"], 1)
        XCTAssertEqual(holder.dictionary.count, 1)
        XCTAssertEqual(holder.dictionarySetCount, 1)

        holder.dictionary["a"] = 99
        XCTAssertEqual(holder.dictionary["a"], 99)
        XCTAssertEqual(holder.dictionary.count, 1)
        XCTAssertEqual(holder.dictionarySetCount, 2)
        XCTAssertEqual(dictionary["a"], 100)
    }

//    func testNestedSubscriptDidSet() {
//        let holder = DictionaryHolder()
//        holder.dictionaryOfDictionaries["a"] = ["a": 1, "b": 2, "c": 3]
//        XCTAssertEqual(holder.dictionaryOfDictionaries.count, 1)
//        XCTAssertEqual(holder.dictionarySetCount, 1)
//
//        var dictionary = holder.dictionaryOfDictionaries
//        dictionary["a"]!["b"] = 200
//        XCTAssertEqual(holder.dictionaryOfDictionaries["a"], ["a": 1, "b": 2, "c": 3])
//        XCTAssertEqual(holder.dictionaryOfDictionaries.count, 1)
//        XCTAssertEqual(holder.dictionarySetCount, 1)
//
//        holder.dictionaryOfDictionaries["a"]!["b"] = 199
//        XCTAssertEqual(holder.dictionaryOfDictionaries["a"]!["b"], 199)
//        XCTAssertEqual(holder.dictionaryOfDictionaries.count, 1)
//        XCTAssertEqual(holder.dictionarySetCount, 2)
//        XCTAssertEqual(dictionary["a"]!["b"], 200)
//    }

    func testDictionaryReferences() {
        var dict: [String: Int] = [:]
        dict["a"] = 1
        var dict2 = dict
        dict2["b"] = 2
        var dict3 = dict2
        dict3["c"] = 3

        dict["z"] = 0

        XCTAssertEqual(dict.count, 2)
        XCTAssertEqual(dict2.count, 2)
        XCTAssertEqual(dict3.count, 3)

    }
}

private class DictionaryHolder {
    var dictionary: [String: Int] = [:] {
        didSet {
            dictionarySetCount += 1
        }
    }
    var dictionarySetCount = 0

    var dictionaryOfDictionaries: [String: [String: Int]] = [:] {
        didSet {
            dictionarySetCount += 1
        }
    }
}
