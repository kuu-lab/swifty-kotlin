#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct InferredNestedMemberReturnPropertyTests {
    @Test
    func inferredMemberReturnsReachPropertyInitializersAndDelegates() throws {
        let source = """
        object Host {
            class Reader {
                fun text() = "OK"
            }

            class StringDelegate(val s: String) {
                operator fun getValue(receiver: String, property: Any) = receiver + s
            }

            operator fun String.provideDelegate(host: Any?, property: Any) = StringDelegate(this)

            val initialized = Reader().text()
            val String.plusK by "K"
            val ok = "O".plusK
        }

        fun read(): String = Host.ok
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Expected inferred nested member returns to reach property types, got: \(ctx.diagnostics.diagnostics)"
            )

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let initialized = try #require(sema.symbols.lookup(
                fqName: ["Host", "initialized"].map(interner.intern)
            ))
            #expect(sema.symbols.propertyType(for: initialized) == sema.types.stringType)

            for propertyName in ["plusK", "ok"] {
                let property = try #require(sema.symbols.lookup(
                    fqName: ["Host", propertyName].map(interner.intern)
                ))
                #expect(sema.symbols.propertyType(for: property) == sema.types.stringType)
            }

            let getValue = try #require(sema.symbols.lookup(
                fqName: ["Host", "StringDelegate", "getValue"].map(interner.intern)
            ))
            #expect(sema.symbols.functionSignature(for: getValue)?.returnType == sema.types.stringType)
        }
    }
}
#endif
