#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension LoweringPassRegressionTests {
    @Test
    func testDataObjectHashCodeSynthesisIncludesNestedObjects() throws {
        let source = """
        data object DataObject {
            data object Inner
        }
        class Host {
            data object Inner
        }
        fun dataObjectHashCodes(): Int =
            DataObject.hashCode() + DataObject.Inner.hashCode() + Host.Inner.hashCode()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], moduleName: "DataObjectHashCode", emit: .kirDump
            )
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)

            let sema = try #require(ctx.sema)
            let module = try #require(ctx.kir)
            let hashCodeName = ctx.interner.intern("hashCode")
            let objectNames = [
                [ctx.interner.intern("DataObject")],
                [ctx.interner.intern("DataObject"), ctx.interner.intern("Inner")],
                [ctx.interner.intern("Host"), ctx.interner.intern("Inner")],
            ]
            let hashCodeSymbols = try objectNames.map { objectFQName -> SymbolID in
                let symbol = try #require(
                    sema.symbols.lookupAll(fqName: objectFQName + [hashCodeName]).first {
                        sema.symbols.symbol($0)?.flags.contains(.synthetic) == true
                    },
                    "a data object must have a synthetic hashCode() declaration"
                )
                let function = try #require(
                    findAllKIRFunctions(in: module).first { $0.symbol == symbol },
                    "the synthetic hashCode() declaration must have a KIR body"
                )
                let constants = function.body.compactMap { instruction -> Int64? in
                    guard case let .constValue(_, .intLiteral(value)) = instruction else { return nil }
                    return value
                }
                #expect(constants.contains(where: { $0 != 0 }), "hashCode() should return a non-zero name hash")
                return symbol
            }

            let callerBody = try findKIRFunctionBody(
                named: "dataObjectHashCodes", in: module, interner: ctx.interner
            )
            let calledSymbols = callerBody.compactMap { instruction -> SymbolID? in
                guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return nil }
                return symbol
            }
            for hashCodeSymbol in hashCodeSymbols {
                #expect(calledSymbols.contains(hashCodeSymbol), "calls should resolve to each generated hashCode() body")
            }
        }
    }

    @Test
    func testDataObjectToStringSatisfiesInheritedAbstractMember() throws {
        let source = """
        abstract class WithAbstractToString {
            abstract override fun toString(): String
        }
        data object InheritedFromAbstract : WithAbstractToString()
        fun renderDataObject(): String = InheritedFromAbstract.toString()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], moduleName: "DataObjectAbstractToString", emit: .kirDump
            )
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)

            let sema = try #require(ctx.sema)
            let module = try #require(ctx.kir)
            let objectName = ctx.interner.intern("InheritedFromAbstract")
            let toStringName = ctx.interner.intern("toString")
            let toStringSymbol = try #require(
                sema.symbols.lookupAll(fqName: [objectName, toStringName]).first {
                    sema.symbols.symbol($0)?.flags.contains(.synthetic) == true
                }
            )
            let function = try #require(findAllKIRFunctions(in: module).first { $0.symbol == toStringSymbol })
            let stringConstants = function.body.compactMap { instruction -> String? in
                guard case let .constValue(_, .stringLiteral(value)) = instruction else { return nil }
                return ctx.interner.resolve(value)
            }
            #expect(stringConstants.contains("InheritedFromAbstract"))
        }
    }
}
#endif
