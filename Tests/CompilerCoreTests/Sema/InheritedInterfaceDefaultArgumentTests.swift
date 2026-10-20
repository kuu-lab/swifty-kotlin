#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct InheritedInterfaceDefaultArgumentTests {
    private func makeContext(_ source: String, cache: Bool = false) -> CompilationContext {
        let path = "/tmp/inherited-interface-default.kt"
        let ctx = makeCompilationContext(inputs: [path], frontendFlags: cache ? ["sema-cache"] : [], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }
    private let declarations = """
    interface Api { fun label(value: String = "ok"): String }
    open class Impl { fun label(value: String): String = value }
    class Leaf : Impl(), Api
    """

    @Test
    func inheritedImplementationKeepsReceiverScopedDefaultOwner() throws {
        let ctx = makeContext(declarations + "\nfun sample(): String = Leaf().label()")
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let implementation = try #require(sema.symbols.lookupAll(fqName: ["Impl", "label"].map(ctx.interner.intern)).first)
        let owner = try #require(sema.symbols.lookupAll(fqName: ["Api", "label"].map(ctx.interner.intern)).first)
        let binding = try #require(sema.bindings.callBindings.values.first { $0.chosenCallee == implementation })
        #expect(binding.defaultArgumentOwner == owner)
        #expect(sema.symbols.functionSignature(for: implementation)?.valueParameterHasDefaultValues == [false])
        #expect(sema.symbols.overrideDefaultsBaseSymbol(for: implementation) == nil)
    }

    @Test(arguments: [
        "fun sample(): String = Impl().label()",
        "fun sample(): String { val base: Impl = Leaf(); return base.label() }",
        "class Other : Impl(); fun sample(): String = Other().label()",
    ])
    func defaultsDoNotLeakOutsideTheInterfaceReceiver(source: String) throws {
        let ctx = makeContext(declarations + "\nfun warm(): String = Leaf().label()\n" + source)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
    }

    @Test(arguments: [
        "fun sample(): String { val api: Api = Leaf(); return api.label() }",
        "fun sample(): String = Leaf().label(value = \"explicit\")",
        "class Explicit : Api { override fun label(value: String) = value }; fun sample(): String = Explicit().label()",
        "interface Chain : Api; class Chained : Impl(), Chain; fun sample(): String = Chained().label()",
        "open class Generic<T> { fun label(value: T): T = value }; class Specialized : Generic<String>(), Api; fun sample(): String = Specialized().label()",
        "interface Left : Api; interface Right : Api; class Diamond : Impl(), Left, Right; fun sample(): String = Diamond().label()",
        "interface GenericMethod { fun <T> f(x: T, n: Int = 1): T }; open class MethodImpl { fun <U> f(x: U, n: Int): U = x }; class MethodLeaf : MethodImpl(), GenericMethod; fun sample(): String = MethodLeaf().f(\"ok\")",
    ])
    func existingAndTransitiveDefaultsRemainApplicable(source: String) throws {
        let ctx = makeContext(declarations + "\n" + source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func shorterOverloadWinsOverInheritedDefault() throws {
        let ctx = makeContext("""
        interface Api { fun f(x: Int = 1): Int }
        open class Impl { fun f(): Int = 0; fun f(x: Int): Int = x }
        class Leaf : Impl(), Api
        fun sample(): Int = Leaf().f()
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let overloads = sema.symbols.lookupAll(fqName: ["Impl", "f"].map(ctx.interner.intern))
        let chosen = try #require(sema.bindings.callBindings.values.first { overloads.contains($0.chosenCallee) })
        #expect(sema.symbols.functionSignature(for: chosen.chosenCallee)?.parameterTypes.isEmpty == true)
    }

    @Test
    func ambiguousDefaultOwnersRemainRejected() throws {
        let ctx = makeContext(declarations + """

        interface OtherApi { fun label(value: String = "other"): String }
        class Ambiguous : Impl(), Api, OtherApi
        fun sample(): String = Ambiguous().label()
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
    }

    @Test
    func differentSignaturesKeepDefaultsOnTheInterface() throws {
        let ctx = makeContext(declarations + """

        interface Different { fun label(value: Int = 1): String }
        abstract class Mismatch : Impl(), Different
        fun sample(x: Mismatch): String = x.label()
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let implementation = try #require(sema.symbols.lookupAll(fqName: ["Impl", "label"].map(ctx.interner.intern)).first)
        let interfaceMember = try #require(sema.symbols.lookupAll(fqName: ["Different", "label"].map(ctx.interner.intern)).first)
        #expect(sema.bindings.callBindings.values.contains { $0.chosenCallee == interfaceMember })
        #expect(!sema.bindings.callBindings.values.contains { $0.chosenCallee == implementation })
        #expect(sema.symbols.functionSignature(for: implementation)?.valueParameterHasDefaultValues == [false])
    }

    @Test(arguments: [false, true])
    func superCallsCannotUseReceiverScopedDefaults(warmFirst: Bool) throws {
        let declarations = """
        interface Api { fun label(value: String = "ok"): String }
        open class Impl { fun label(value: String): String = value }
        open class Leaf : Impl(), Api
        """
        let warm = "fun warm(): String = Leaf().label()\n"
        let child = "class Child : Leaf() { fun sample(): String = super.label() }\n"
        let ctx = makeContext(declarations + "\n" + (warmFirst ? warm + child : child + warm))
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test(arguments: [false, true], [false, true])
    func superCallsCannotOmitAnInheritedVarargDefault(warmFirst: Bool, cache: Bool) throws {
        let declarations = """
        interface Api { fun count(vararg values: String = arrayOf("api")): Int }
        open class Impl { fun count(vararg values: String): Int = 0 }
        open class Leaf : Impl(), Api
        """
        let warm = "fun warm(): Int = Leaf().count()\n"
        let child = "class Child : Leaf() { fun sample(): Int = super.count() }\n"
        let ctx = makeContext(declarations + "\n" + (warmFirst ? warm + child : child + warm), cache: cache)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0306" })
    }

    @Test
    func callableReferencesKeepReceiverScopedDefaultOwner() throws {
        let ctx = makeContext("""
        interface Api<T> { fun number(input: T, suffix: String = "!"): String }
        open class IntBase { fun number(input: Int, suffix: String): String = suffix }
        class IntLeaf: IntBase(), Api<Int>
        fun sample() {
            val bound: (Int) -> String = IntLeaf()::number
            val unbound: (IntLeaf, Int) -> String = IntLeaf::number
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let implementation = try #require(sema.symbols.lookupAll(fqName: ["IntBase", "number"].map(ctx.interner.intern)).first)
        let owner = try #require(sema.symbols.lookupAll(fqName: ["Api", "number"].map(ctx.interner.intern)).first)
        let bindings = sema.bindings.callableReferenceBindings.values.filter { $0.chosenCallee == implementation }
        #expect(bindings.count == 2)
        #expect(bindings.allSatisfy { $0.defaultArgumentOwner == owner && $0.isCallableReferenceAdapter })
        #expect(sema.symbols.functionSignature(for: implementation)?.valueParameterHasDefaultValues == [false, false])
        #expect(sema.symbols.overrideDefaultsBaseSymbol(for: implementation) == nil)
    }

    @Test(arguments: [
        "fun sample() { val bad: () -> String = Impl()::label }",
        "fun sample() { val bad: (Impl) -> String = Impl::label }",
        "class Other : Impl(); fun sample() { val bad: () -> String = Other()::label }",
    ])
    func callableReferenceDefaultsDoNotLeakToOtherReceivers(source: String) throws {
        let ctx = makeContext(declarations + "\nfun warm() { val valid: () -> String = Leaf()::label }\n" + source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-TYPE-0001" })
    }
}
#endif
