#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Pins the JSON compatibility contract of `RawInt32ID`: the AST arena snapshot
/// stores thousands of these IDs in `frontend.json`, so the encoded form and the
/// legacy `{"rawValue": N}` read path must stay stable across compiler versions.
@Suite
struct RawInt32IDCodableTests {
    @Test
    func testEncodesAsBareJSONNumber() throws {
        try assertBareNumberRoundTrip(ASTNodeID(rawValue: 7))
        try assertBareNumberRoundTrip(ExprID(rawValue: 7))
        try assertBareNumberRoundTrip(TypeRefID(rawValue: 7))
        try assertBareNumberRoundTrip(TokenID(rawValue: 7))
        try assertBareNumberRoundTrip(NodeID(rawValue: 7))
        try assertBareNumberRoundTrip(DeclID(rawValue: 7))
        try assertBareNumberRoundTrip(FileID(rawValue: 7))
        try assertBareNumberRoundTrip(InternedString(rawValue: 7))
    }

    @Test
    func testDecodesBareJSONNumber() throws {
        #expect(try decode(ExprID.self, from: "7") == ExprID(rawValue: 7))
        #expect(try decode(TypeRefID.self, from: "-1") == TypeRefID(rawValue: -1))
    }

    @Test
    func testDecodesLegacyObjectForm() throws {
        // Caches written before the bare-number encoding store {"rawValue": N}.
        #expect(try decode(ExprID.self, from: #"{"rawValue": 42}"#) == ExprID(rawValue: 42))
        #expect(try decode(FileID.self, from: #"{"rawValue": -1}"#) == FileID(rawValue: -1))
        #expect(try decode(InternedString.self, from: #"{"rawValue": 0}"#) == InternedString(rawValue: 0))
    }

    @Test
    func testInt32BoundariesAndInvalidRoundTrip() throws {
        try assertBareNumberRoundTrip(ExprID(rawValue: Int32.max))
        try assertBareNumberRoundTrip(ExprID(rawValue: Int32.min))
        try assertBareNumberRoundTrip(ExprID.invalid)
        try assertBareNumberRoundTrip(InternedString.invalid)
        #expect(try decode(ExprID.self, from: "\(Int32.max)") == ExprID(rawValue: Int32.max))
        #expect(try decode(ExprID.self, from: "\(Int32.min)") == ExprID(rawValue: Int32.min))
    }

    @Test
    func testExprIDKeyedDictionariesRoundTrip() throws {
        // The arena side tables key by ExprID (loopLabels, whenSubjectTypeRefs, ...).
        let labels: [ExprID: InternedString] = [
            ExprID(rawValue: 1): InternedString(rawValue: 10),
            ExprID(rawValue: 2): InternedString(rawValue: 20),
            ExprID(rawValue: 3): InternedString.invalid,
        ]
        try assertRoundTrip(labels)

        let typeRefs: [ExprID: TypeRefID] = [
            ExprID(rawValue: 5): TypeRefID(rawValue: 50),
            ExprID(rawValue: 6): TypeRefID(rawValue: 60),
        ]
        try assertRoundTrip(typeRefs)

        let exprMap: [ExprID: ExprID] = [
            ExprID(rawValue: 7): ExprID(rawValue: 70),
        ]
        try assertRoundTrip(exprMap)
    }

    @Test
    func testFileIDKeyedDictionaryRoundTrip() throws {
        // filesByID / entriesByFile key by FileID.
        let byFile: [FileID: [ExprID]] = [
            FileID(rawValue: 1): [ExprID(rawValue: 1), ExprID(rawValue: 2)],
            FileID(rawValue: 2): [],
        ]
        try assertRoundTrip(byFile)
    }

    @Test
    func testMixedBareAndLegacyArrayDecodes() throws {
        // A hand-written legacy cache stores objects; the new one stores numbers.
        // Decoding must accept whichever form each element takes.
        let legacy = #"[{"rawValue": 1}, {"rawValue": 2}, {"rawValue": 3}]"#
        #expect(try decode([ExprID].self, from: legacy) == [ExprID(rawValue: 1), .init(rawValue: 2), .init(rawValue: 3)])

        let current = #"[1, 2, 3]"#
        #expect(try decode([ExprID].self, from: current) == [ExprID(rawValue: 1), .init(rawValue: 2), .init(rawValue: 3)])
    }

    private func assertBareNumberRoundTrip<ID: RawInt32ID>(_ id: ID) throws {
        let data = try JSONEncoder().encode(id)
        let json = try #require(String(data: data, encoding: .utf8), "UTF-8")
        // The whole payload must be the bare integer, never a {"rawValue": N} object.
        #expect(json == "\(id.rawValue)", "encoded \(ID.self) as \(json)")
        #expect(!json.contains("rawValue"))

        let decoded = try JSONDecoder().decode(ID.self, from: data)
        #expect(decoded == id)
    }

    private func assertRoundTrip<Value: Codable & Equatable>(_ value: Value) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)
    }

    private func decode<ID: RawInt32ID>(_ type: ID.Type, from json: String) throws -> ID {
        try JSONDecoder().decode(ID.self, from: Data(json.utf8))
    }

    private func decode<Value: Codable>(_ type: Value.Type, from json: String) throws -> Value {
        try JSONDecoder().decode(Value.self, from: Data(json.utf8))
    }
}
#endif
