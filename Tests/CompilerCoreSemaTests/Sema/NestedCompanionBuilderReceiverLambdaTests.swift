#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

/// KUU-2398: member calls in a nested companion builder receiver lambda must
/// resolve against the lambda's `Builder` receiver.
@Suite
struct NestedCompanionBuilderReceiverLambdaTests {

    @Test
    func nestedCompanionBuilderResolvesAddInDirectAndElseBranchLambdas() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        class JSONObject {
            class Builder { fun add(key: String, value: Int?) {} }
            companion object {
                fun build(size: Int, block: Builder.() -> Unit): JSONObject = JSONObject()
            }
        }

        fun use(): JSONObject = JSONObject.build(size = 1) { add("key", null) }

        fun useElse(flag: Boolean): JSONObject = if (flag) JSONObject() else
            JSONObject.build(size = 1) { add("key", null) }

        fun useSameLine(flag: Boolean): JSONObject =
            if (flag) JSONObject() else JSONObject.build(size = 1) { add("key", null) }
        """, allowDefaultStdlibLibrary: true)

        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let jsonObjectName = ctx.interner.intern("JSONObject")
        let builderName = ctx.interner.intern("Builder")
        let addName = ctx.interner.intern("add")
        let jsonObject = try #require(sema.symbols.lookup(fqName: [jsonObjectName]))
        let builder = try #require(sema.symbols.lookup(fqName: [jsonObjectName, builderName]))
        let hasAddMember = sema.symbols.children(ofFQName: [jsonObjectName, builderName]).contains { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID) else { return false }
            return symbol.kind == .function && symbol.name == addName
        }
        #expect(hasAddMember, "JSONObject.Builder should declare add")

        let companion = try #require(sema.symbols.companionObjectSymbol(for: jsonObject))
        let companionFQName = try #require(sema.symbols.symbol(companion)?.fqName)
        let build = try #require(sema.symbols.children(ofFQName: companionFQName).first { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID) else { return false }
            return symbol.kind == .function && symbol.name == ctx.interner.intern("build")
        })
        let buildSignature = try #require(sema.symbols.functionSignature(for: build))
        let blockReceiverSymbol: SymbolID? = {
            guard let blockType = buildSignature.parameterTypes.last,
                  case let .functionType(blockFunctionType) = sema.types.kind(of: blockType),
                  let receiver = blockFunctionType.receiver,
                  case let .classType(classType) = sema.types.kind(of: receiver)
            else {
                return nil
            }
            return classType.classSymbol
        }()
        #expect(blockReceiverSymbol == builder, "build's lambda receiver should resolve to JSONObject.Builder")
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
