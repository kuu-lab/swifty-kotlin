#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct StringPlusReceiverTests {
    // KUU-1124: a textual RHS does not provide plus on a primitive receiver.
    @Test(arguments: ["1", "true", "1.5", "1L"])
    func rejectsNonStringReceiver(lhs: String) throws {
        let source = """
        fun literal() = \(lhs) + "x"
        fun string(s: String) = \(lhs) + s
        fun nullableString(s: String?) = \(lhs) + s
        fun sequence(s: CharSequence) = \(lhs) + s
        fun nullableSequence(s: CharSequence?) = \(lhs) + s
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-0002" && $0.message.contains("operator 'plus'")
        }
        #expect(errors.count == 5, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let names = Set(["literal", "string", "nullableString", "sequence", "nullableSequence"])
        let expressions = ast.files.flatMap(\.topLevelDecls).compactMap { declID -> ExprID? in
            guard case let .funDecl(function) = ast.arena.decl(declID),
                  names.contains(ctx.interner.resolve(function.name)),
                  case let .expr(expr, _) = function.body
            else { return nil }
            return expr
        }
        #expect(expressions.count == 5)
        for expr in expressions {
            #expect(sema.bindings.exprTypes[expr] == sema.types.errorType)
        }
    }

    @Test
    func acceptsStringCharAndDeclaredExtensionReceivers() throws {
        let source = """
        fun string(n: Int, b: Boolean, d: Double, l: Long, a: Any?, s: CharSequence): String =
            "x" + n + b + d + l + a + s
        fun nullableString(s: String?): String = s + 1
        fun char(c: Char, s: String): String = c + s
        operator fun Int.plus(s: String): String = s
        fun extension(n: Int, s: String): String = n + s
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
