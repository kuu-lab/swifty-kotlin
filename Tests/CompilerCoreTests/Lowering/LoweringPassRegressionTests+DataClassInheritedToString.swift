#if canImport(Testing)
@testable import CompilerCore
import Testing

extension LoweringPassRegressionTests {
    @Test
    func testDataClassInheritedFinalToStringSuppressesSynthesis() throws {
        let source = """
        abstract class FinalBase {
            final override fun toString(): String = "base"
        }
        abstract class FinalMiddle : FinalBase()
        data class FinalChild(val field: String) : FinalMiddle()

        open class OpenBase {
            override fun toString(): String = "base"
        }
        data class OpenChild(val field: String) : OpenBase()

        abstract class PlainBase
        data class PlainChild(val field: String) : PlainBase()

        data class ExplicitChild(val field: String) : OpenBase() {
            override fun toString(): String = "own"
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], moduleName: "DataClassInheritedFinalToString", emit: .kirDump
            )
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)

            let sema = try #require(ctx.sema)
            let module = try #require(ctx.kir)
            let toStringName = ctx.interner.intern("toString")

            func owner(named name: String) throws -> SemanticSymbol {
                try #require(sema.symbols.allSymbols().first {
                    $0.kind == .class && $0.name == ctx.interner.intern(name)
                })
            }

            func toStringMembers(of name: String) throws -> [SymbolID] {
                let owner = try owner(named: name)
                return sema.symbols.lookupAll(fqName: owner.fqName + [toStringName])
            }

            let finalChildMembers = try toStringMembers(of: "FinalChild")
            #expect(!finalChildMembers.contains {
                sema.symbols.symbol($0)?.flags.contains(.synthetic) == true
            }, "a final inherited toString() must suppress the data-class synthetic member")

            for name in ["OpenChild", "PlainChild"] {
                let syntheticMembers = try toStringMembers(of: name).filter {
                    sema.symbols.symbol($0)?.flags.contains(.synthetic) == true
                }
                #expect(syntheticMembers.count == 1, "\(name) must retain its data-class toString()")
                #expect(findAllKIRFunctions(in: module).contains {
                    $0.symbol == syntheticMembers.first
                }, "\(name)'s synthetic toString() must still have a KIR body")
            }

            let explicitMembers = try toStringMembers(of: "ExplicitChild")
            #expect(explicitMembers.count == 1)
            #expect(sema.symbols.symbol(explicitMembers[0])?.flags.contains(.synthetic) != true)
        }
    }
}
#endif
