#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct DataClassUserHashCodeOverrideTests {
    @Test
    func testUserHashCodeSuppressesSyntheticHashCode() throws {
        let source = """
        data class OnlyHash(val a: Int) { override fun hashCode() = a * 7 }
        data class Typed(val a: Int) { override fun hashCode(): Int = 1 }
        fun main() { println(OnlyHash(3).hashCode()); println(Typed(3).hashCode()) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map(\.message))")

            let sema = try #require(ctx.sema)
            for owner in ["OnlyHash", "Typed"] {
                let fqName = [ctx.interner.intern(owner), ctx.interner.intern("hashCode")]
                let candidates = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
                    .filter { $0.kind == .function }
                #expect(candidates.count == 1, "\(owner): expected only the user hashCode, got \(candidates.count)")
                #expect(candidates.first?.flags.contains(.synthetic) == false)
                #expect(candidates.first?.flags.contains(.overrideMember) == true)
            }
        }
    }

    @Test
    func testDataClassWithoutUserHashCodeKeepsSyntheticHashCode() throws {
        let source = "data class Plain(val a: Int)\nfun main() { println(Plain(1).hashCode()) }"
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError)
            let sema = try #require(ctx.sema)
            let fqName = [ctx.interner.intern("Plain"), ctx.interner.intern("hashCode")]
            let synthetic = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
                .filter { $0.kind == .function && $0.flags.contains(.synthetic) }
            #expect(synthetic.count == 1)
        }
    }
}
#endif
