#if canImport(Testing)
@testable import Runtime
import Foundation
import Testing

@Suite
struct RuntimeSerializationTests {
    private func makeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    private func extractSwiftString(_ raw: Int) -> String? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
            return nil
        }
        return extractString(from: ptr)
    }

    private func jsonObject(from raw: Int) throws -> Any {
        let string = try #require(extractSwiftString(raw))
        let data = try #require(string.data(using: .utf8))
        return try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
    }

    @Test
    func testEncodeMapProducesJSONObject() throws {
        let json = kk_json_default()
        let mapRaw = registerRuntimeObject(RuntimeMapBox(
            keys: [makeString("name"), makeString("age"), makeString("active")],
            values: [makeString("Alice"), makeString("30"), makeString("true")]
        ))

        let encoded = kk_json_encodeToString(json, mapRaw)
        let object = try #require(try jsonObject(from: encoded) as? [String: String])

        #expect(object["name"] == "Alice")
        #expect(object["age"] == "30")
        #expect(object["active"] == "true")
    }

    @Test
    func testEncodeListProducesJSONArray() throws {
        let json = kk_json_default()
        let listRaw = registerRuntimeObject(RuntimeListBox(elements: [
            makeString("a"),
            makeString("b"),
            makeString("c"),
        ]))

        let encoded = kk_json_encodeToString(json, listRaw)
        let array = try #require(try jsonObject(from: encoded) as? [String])
        #expect(array == ["a", "b", "c"])
    }

    @Test
    func testDecodeObjectReturnsRuntimeMap() {
        let json = kk_json_default()
        var thrown = 0
        let decoded = kk_json_decodeFromString(
            json,
            makeString("{\"greeting\":\"hello\",\"count\":\"42\"}"),
            &thrown
        )

        #expect(thrown == 0)
        let map = runtimeMapBox(from: decoded)
        #expect(map != nil)
        #expect(map?.keys.count == 2)
        #expect(map?.values.count == 2)

        let entries: [(String, String)] = zip(map?.keys ?? [], map?.values ?? []).compactMap { key, value in
            guard let k = extractSwiftString(key), let v = extractSwiftString(value) else {
                return nil
            }
            return (k, v)
        }
        let decodedDict = Dictionary(uniqueKeysWithValues: entries)
        #expect(decodedDict == ["greeting": "hello", "count": "42"])
    }

    @Test
    func testDecodeArrayReturnsRuntimeList() {
        let json = kk_json_default()
        var thrown = 0
        let decoded = kk_json_decodeFromString(
            json,
            makeString("[\"x\",\"y\",\"z\"]"),
            &thrown
        )

        #expect(thrown == 0)
        let list = runtimeListBox(from: decoded)
        #expect(list?.elements.compactMap(extractSwiftString) == ["x", "y", "z"])
    }

    @Test
    func testDecodeInvalidJSONSetsThrowable() {
        let json = kk_json_default()
        var thrown = 0
        let decoded = kk_json_decodeFromString(
            json,
            makeString("{invalid"),
            &thrown
        )

        #expect(decoded == runtimeNullSentinelInt)
        #expect(thrown != 0)
    }

    @Test
    func testEncodeSetUsesJSONArrayRepresentation() throws {
        let json = kk_json_default()
        let setRaw = registerRuntimeObject(RuntimeSetBox(elements: [
            makeString("left"),
            makeString("right"),
        ]))

        let encoded = kk_json_encodeToString(json, setRaw)
        let array = try #require(try jsonObject(from: encoded) as? [String])
        #expect(array == ["left", "right"])
    }
}
#endif
