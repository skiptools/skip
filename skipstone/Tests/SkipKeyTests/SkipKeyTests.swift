import XCTest
import SkipBuild
import SkipSyntax
import struct JSON.JSON
import TSCBasic

public class SkipKeyTests : XCTestCase {
    public func testLicenseCreation() async throws {
        do {
            let key = try await tool("create", "-jM", "--nonce", "000000000000000000000000", "--id", "ABC", "--expiration", "2023-07-01T00:00:00Z")
            // keys are not always identical, even with the same nonce
            //XCTAssertEqual("SKP000000000000000000000000EB195AE8771A919718D475EA9DED4EC0FE8A7952ABB659EB45EEB2C490FD9510E1FF8B20D3862F2F51D218PKS", try key.json()["key"]?.string)
            XCTAssertNotEqual(0, try key.json()["key"]?.string?.count)
        }
        do {
            let key = try await tool("create", "-jM", "--nonce", "000000000000000000000000", "--id", "123", "--expiration", "2023-07-01T00:00:00Z")
            // keys are not always identical, even with the same nonce
            //XCTAssertEqual("SKP000000000000000000000000EB195AE8771A91E768A475EA9DED4EC0FE8A7952ABB659EB45EEB2A7BAC8BE555CE63AD8675978803DF8D4PKS", try key.json()["key"]?.string)
            XCTAssertNotEqual(0, try key.json()["key"]?.string?.count)
        }
    }

    public func testLicenseInfo() async throws {
        let key = "SKPA0774FE5E6799A1DDBF57B5A16D66498F578FAB36A4D88B93917DBCEF6FADC3FE3E936E6EDACF1E83F89EEC90D011212597075083APKS"
        let keyInfo = try await tool("info", "-jM", "--key", key).json()

        XCTAssertEqual(key, keyInfo["key"]?.string)
        XCTAssertEqual("2023-07-01T00:00:00Z", keyInfo["expiration"]?.string)
        XCTAssertEqual("*", keyInfo["id"]?.string)

        for key in [
            key + "X",
            "X" + key,
        ] {
            do {
                let _ = try await tool("info", "-jM", "--key", key)
                XCTFail("should not have been able to parse)")
            } catch {
                guard case LicenseError.invalidLicenseFormat = error else {
                    throw error // expected
                }
            }
        }
    }

    /// Runs the tool with the given arguments, returning the entire output string as well as a function to parse it to `JSON`
    func tool(_ args: String...) async throws -> (out: String, err: String, json: () throws -> JSON) {
        let out = BufferedOutputByteStream()
        let err = BufferedOutputByteStream()
        try await SkipKeyExecutor.run(args, out: out, err: err)
        return (out.bytes.description.trimmingCharacters(in: .whitespacesAndNewlines), err.bytes.description.trimmingCharacters(in: .whitespacesAndNewlines), { try JSON.parse(out.bytes.description.utf8Data) })
    }
}
