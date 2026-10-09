@testable import CompilerCore
import Testing

@Suite
struct LocalDataClassTests {
    @Test
    func testSyntheticHeadersAndConstructorProperties() throws {
        let source = """
        fun main() {
            data class Local(val i: Int) { val extra = 9 }
            val value = Local(1).copy(i = 2)
            val (i) = value
            println(value.toString())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let owner = try #require(sema.symbols.allSymbols().first {
                $0.kind == .class && $0.name == ctx.interner.intern("Local")
            })
            #expect(owner.flags.contains(.dataType))
            for name in ["equals", "hashCode", "toString", "copy", "component1"] {
                let members = sema.symbols.lookupAll(fqName: owner.fqName + [ctx.interner.intern(name)])
                    .compactMap { sema.symbols.symbol($0) }.filter { $0.kind == .function }
                #expect(members.count == 1, "\(name): expected one synthetic member")
                #expect(members.first?.flags.contains(.synthetic) == true)
            }
            let property = try #require(sema.symbols.lookup(fqName: owner.fqName + [ctx.interner.intern("i")]))
            #expect(sema.symbols.symbol(property)?.flags.contains(.synthetic) == false)
            #expect(sema.symbols.nominalLayout(for: owner.id)?.fieldOffsets[property] != nil)
        }
    }
}
