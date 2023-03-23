@testable import SkipSyntax
import XCTest

final class KotlinCodebaseInfoTests: XCTestCase {
    func testIsMutableStructType() async throws {
        let context = try await symbols.context()
        XCTAssertNil(context.isMutableStruct(type: .named("NonExistantTypeName", [])))

        XCTAssertEqual(false, context.isMutableStruct(type: .named("KotlinCodebaseInfoTestsClass", [])))
        XCTAssertEqual(false, context.isMutableStruct(type: .named("KotlinCodebaseInfoTestsEnum", [])))
        XCTAssertEqual(false, context.isMutableStruct(type: .named("KotlinCodebaseInfoTestsImmutableStruct", [])))

        XCTAssertEqual(true, context.isMutableStruct(type: .named("KotlinCodebaseInfoTestsMutableVarStruct", [])))
        XCTAssertEqual(true, context.isMutableStruct(type: .named("KotlinCodebaseInfoTestsMutableComputedVarStruct", [])))
        XCTAssertEqual(true, context.isMutableStruct(type: .named("KotlinCodebaseInfoTestsMutableFuncStruct", [])))

        XCTAssertEqual(true, context.isMutableStruct(type: .named("KotlinCodebaseInfoTestsNonAnyObjectRestrictedProtocol", [])))
        XCTAssertEqual(false, context.isMutableStruct(type: .named("KotlinCodebaseInfoTestsAnyObjectRestrictedProtocol", [])))
        XCTAssertEqual(false, context.isMutableStruct(type: .named("KotlinCodebaseInfoTestsTransitiveAnyObjectRestrictedProtocol", [])))
    }

    func testEnumHasAssociatedValues() async throws {
        let context = try await symbols.context()
        XCTAssertNil(context.enumHasAssociatedValues(type: .named("NonExistantTypeName", [])))

        XCTAssertEqual(false, context.enumHasAssociatedValues(type: .named("KotlinCodebaseInfoTestsEnum", [])))
        XCTAssertEqual(true, context.enumHasAssociatedValues(type: .named("KotlinCodebaseInfoTestsEnumWithAssociatedValues", [])))
    }

    func testProtocolTypeHasMember() async throws {
        let context = try await symbols.context()
        XCTAssertNil(context.protocolOf(.named("NonExistantTypeName", []), hasMember: "protocolVar", kind: .property, type: nil))

        XCTAssertEqual(false, context.protocolOf(.named("KotlinCodebaseInfoTestsNonAnyObjectRestrictedProtocol", []), hasMember: "baseProtocolVar", kind: .property, type: nil))
        XCTAssertEqual(true, context.protocolOf(.named("KotlinCodebaseInfoTestsAnyObjectRestrictedProtocol", []), hasMember: "baseProtocolVar", kind: .property, type: nil))
        XCTAssertEqual(true, context.protocolOf(.named("KotlinCodebaseInfoTestsAnyObjectRestrictedProtocol", []), hasMember: "baseProtocolVar", kind: .property, type: .int))
        XCTAssertEqual(false, context.protocolOf(.named("KotlinCodebaseInfoTestsAnyObjectRestrictedProtocol", []), hasMember: "baseProtocolVar", kind: .property, type: .string))

        let functionType: TypeSignature = .function([.init(label: "i", type: .int)], .string)
        XCTAssertEqual(false, context.protocolOf(.named("KotlinCodebaseInfoTestsNonAnyObjectRestrictedProtocol", []), hasMember: "baseProtocolFunc", kind: .method, type: functionType))
        XCTAssertEqual(true, context.protocolOf(.named("KotlinCodebaseInfoTestsAnyObjectRestrictedProtocol", []), hasMember: "baseProtocolFunc", kind: .method, type: functionType))
        XCTAssertEqual(false, context.protocolOf(.named("KotlinCodebaseInfoTestsAnyObjectRestrictedProtocol", []), hasMember: "baseProtocolFunc", kind: .method, type: .function([.init(label: "i", type: .string)], .string)))

        XCTAssertEqual(true, context.protocolOf(.named("KotlinCodebaseInfoTestsTransitiveAnyObjectRestrictedProtocol", []), hasMember: "baseProtocolVar", kind: .property, type: nil))
        XCTAssertEqual(true, context.protocolOf(.named("KotlinCodebaseInfoTestsTransitiveAnyObjectRestrictedProtocol", []), hasMember: "baseProtocolFunc", kind: .method, type: functionType))

        XCTAssertEqual(true, context.protocolOf(.named("KotlinCodebaseInfoTestsProtocolImpl", []), hasMember: "baseProtocolVar", kind: .property, type: nil))
        XCTAssertEqual(true, context.protocolOf(.named("KotlinCodebaseInfoTestsProtocolImpl", []), hasMember: "baseProtocolFunc", kind: .method, type: functionType))
    }
}

class KotlinCodebaseInfoTestsClass {
}

enum KotlinCodebaseInfoTestsEnum: Int {
    case case1
    case case2 = 100
}
enum KotlinCodebaseInfoTestsEnumWithAssociatedValues {
    case case1
    case case2(Int)
}

struct KotlinCodebaseInfoTestsImmutableStruct {
    let letVar = 1
}

struct KotlinCodebaseInfoTestsMutableVarStruct {
    var v = 1
}

struct KotlinCodebaseInfoTestsMutableComputedVarStruct {
    var computedVar: Int {
        get {
            return 1
        }
        set {
        }
    }
}

struct KotlinCodebaseInfoTestsMutableFuncStruct {
    mutating func f() -> Int {
        return 1
    }
}

protocol KotlinCodebaseInfoTestsNonAnyObjectRestrictedProtocol: Codable {}
protocol KotlinCodebaseInfoTestsAnyObjectRestrictedProtocol: AnyObject {
    var baseProtocolVar: Int { get }
    func baseProtocolFunc(i: Int) -> String
}
protocol KotlinCodebaseInfoTestsTransitiveAnyObjectRestrictedProtocol: KotlinCodebaseInfoTestsAnyObjectRestrictedProtocol {
}
class KotlinCodebaseInfoTestsProtocolImpl: KotlinCodebaseInfoTestsTransitiveAnyObjectRestrictedProtocol {
    var baseProtocolVar = 1
    func baseProtocolFunc(i: Int) -> String {
        return ""
    }
}
