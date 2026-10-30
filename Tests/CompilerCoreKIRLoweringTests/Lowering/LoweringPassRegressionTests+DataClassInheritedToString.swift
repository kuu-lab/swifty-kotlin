#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension LoweringPassRegressionTests {
    @Test
    func testDataClassInheritedFinalGeneratedMembersSuppressSynthesis() throws {
        let source = """
        abstract class FinalBase {
            final override fun toString(): String = "base"
            final override fun hashCode(): Int = 42
            final override fun equals(other: Any?): Boolean = false
        }
        abstract class FinalMiddle : FinalBase()
        data class FinalChild(val field: String) : FinalMiddle()

        abstract class FinalHashCodeBase {
            final override fun hashCode() = 7
        }
        data class PartialChild(val field: String) : FinalHashCodeBase()

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
                inputs: [path], moduleName: "DataClassInheritedFinalToString",
                emit: .kirDump, includeStdlib: false
            )
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)

            let sema = try #require(ctx.sema)
            let module = try #require(ctx.kir)
            let generatedMemberNames = ["equals", "hashCode", "toString"]

            func owner(named name: String) throws -> SemanticSymbol {
                try #require(sema.symbols.allSymbols().first {
                    $0.kind == .class && $0.name == ctx.interner.intern(name)
                })
            }

            func members(of name: String, method: String) throws -> [SymbolID] {
                let owner = try owner(named: name)
                return sema.symbols.lookupAll(fqName: owner.fqName + [ctx.interner.intern(method)])
            }

            for method in generatedMemberNames {
                let finalBaseMembers = try members(of: "FinalBase", method: method)
                #expect(finalBaseMembers.contains {
                    guard let symbol = sema.symbols.symbol($0) else { return false }
                    return !symbol.flags.contains(.synthetic) && symbol.flags.contains(.finalMember)
                }, "FinalBase must declare a final (method)()")

                let finalChildMembers = try members(of: "FinalChild", method: method)
                #expect(!finalChildMembers.contains {
                    sema.symbols.symbol($0)?.flags.contains(.synthetic) == true
                }, "a final inherited \(method)() must suppress the data-class synthetic member")

                let partialChildMembers = try members(of: "PartialChild", method: method)
                let expectedSynthetic = method != "hashCode"
                let partialSyntheticMembers = partialChildMembers.filter {
                    sema.symbols.symbol($0)?.flags.contains(.synthetic) == true
                }
                #expect(partialSyntheticMembers.count == (expectedSynthetic ? 1 : 0))
            }

            for name in ["OpenChild", "PlainChild"] {
                for method in generatedMemberNames {
                    let syntheticMembers = try members(of: name, method: method).filter {
                        sema.symbols.symbol($0)?.flags.contains(.synthetic) == true
                    }
                    #expect(syntheticMembers.count == 1, "\(name) must retain its data-class \(method)()")
                    #expect(findAllKIRFunctions(in: module).contains {
                        $0.symbol == syntheticMembers.first
                    }, "\(name)'s synthetic \(method)() must still have a KIR body")
                }
            }

            let explicitMembers = try members(of: "ExplicitChild", method: "toString")
            #expect(explicitMembers.count == 1)
            #expect(sema.symbols.symbol(explicitMembers[0])?.flags.contains(.synthetic) != true)
        }
    }
}
#endif
