#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct WhenSubjectDeclarationParsingTests {
    @Test(arguments: ["Int?", "Long", "List<String?>", "(Int) -> String", "kotlin.Int?"])
    func preservesSubjectAnnotationAndSnapshot(_ annotation: String) throws {
        let lexed = lex("when (val value: \(annotation) = null) { null -> 1; else -> 2 }")
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(), interner: lexed.interner,
            astArena: arena, diagnostics: lexed.diagnostics
        )
        let id = try #require(parser.parse())
        guard case let .whenExpr(subject, branches, elseExpr, _) = arena.expr(id) else {
            Issue.record("Expected a when expression")
            return
        }
        let subjectID = try #require(subject)
        guard case .nullLiteral = arena.expr(subjectID) else {
            Issue.record("Expected the subject initializer to be preserved")
            return
        }
        #expect(branches.count == 1)
        #expect(elseExpr != nil)
        #expect(arena.whenSubjectVarName(for: id) == lexed.interner.intern("value"))
        let typeRef = try #require(arena.whenSubjectTypeRef(for: id))
        #expect(parser.current() == nil)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
        let encoded = try JSONEncoder().encode(arena.snapshot())
        let restored = ASTArena(snapshot: try JSONDecoder().decode(ASTArenaSnapshot.self, from: encoded))
        #expect(restored.whenSubjectTypeRef(for: id) == typeRef)
        #expect(restored.typeRef(typeRef) == arena.typeRef(typeRef))

        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "whenSubjectTypeRefs")
        let legacySnapshot = try JSONDecoder().decode(
            ASTArenaSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy)
        )
        #expect(legacySnapshot.whenSubjectTypeRefs.isEmpty)
    }

    @Test(arguments: [
        "when (val value = 1) { else -> value }",
        "when (val get = 1) { else -> get }",
        "when (1) { else -> 2 }",
    ])
    func unannotatedSubjectsRemainUnannotated(_ source: String) throws {
        let lexed = lex(source)
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(), interner: lexed.interner,
            astArena: arena, diagnostics: lexed.diagnostics
        )
        let id = try #require(parser.parse())
        #expect(arena.whenSubjectTypeRef(for: id) == nil)
        #expect(parser.current() == nil)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }
}
#endif
