#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ExpectActualAbstractCompletenessTests {
    @Test
    func concreteActualMayImplementAnAbstractMemberInheritedByExpectClass() throws {
        let ctx = makeContextFromSources([
            """
            abstract class Token { abstract fun match(): Int }
            expect class RegexToken : Token { constructor() }
            """,
            """
            actual class RegexToken actual constructor() : Token() {
                override fun match() = 3
            }
            """,
        ])

        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "The expect declaration must defer completeness to its actual: \(errors)")

        let sema = try #require(ctx.sema)
        let regexToken = [ctx.interner.intern("RegexToken")]
        let classes = sema.symbols.lookupAll(fqName: regexToken)
            .compactMap { sema.symbols.symbol($0) }
        let expectClass = try #require(classes.first { $0.flags.contains(.expectDeclaration) })
        let actualClass = try #require(classes.first { $0.flags.contains(.actualDeclaration) })
        #expect(sema.symbols.actualSymbol(for: expectClass.id) == actualClass.id)
    }

    @Test
    func concreteActualStillMustImplementAnInheritedAbstractMember() throws {
        let ctx = makeContextFromSources([
            """
            abstract class Token { abstract fun match(): Int }
            expect class RegexToken : Token { constructor() }
            """,
            """
            actual class RegexToken actual constructor() : Token()
            """,
        ])

        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "Only the concrete actual should report the missing implementation: \(errors)")
        #expect(errors.first?.code == "KSWIFTK-SEMA-ABSTRACT")
        #expect(errors.first?.message.contains("'match'") == true)
    }

}
#endif
