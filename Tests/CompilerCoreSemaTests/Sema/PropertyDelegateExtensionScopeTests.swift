@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite
struct PropertyDelegateExtensionScopeTests {
    @Test(arguments: [false, true])
    func selectsApplicableScopeAndPreservesMemberPriority(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let source = """
        package kuu2008
        import kotlin.reflect.KProperty
        interface Parser<out T>
        open class Tokenizer
        class DefaultTokenizer : Tokenizer()
        abstract class Grammar<out T> {
            protected operator fun <T> Parser<T>.provideDelegate(thisRef: Grammar<*>, property: KProperty<*>): Parser<T> = this
            protected operator fun <T> Parser<T>.getValue(thisRef: Grammar<*>, property: KProperty<*>): Parser<T> = this
            open val tokenizer: Tokenizer by lazy { DefaultTokenizer() }
        }
        class MemberGrammar {
            protected operator fun Lazy<Int>.getValue(thisRef: MemberGrammar, property: KProperty<*>): Int = 41
            val answer by lazy { 1 }
        }
        class ValueDelegate
        operator fun ValueDelegate.getValue(thisRef: Any?, property: KProperty<*>): Int = 42
        class LexicalGrammar {
            operator fun String.getValue(thisRef: LexicalGrammar, property: KProperty<*>): Int = 0
            val answer by ValueDelegate()
        }
        class WrongArgumentGrammar {
            operator fun ValueDelegate.getValue(thisRef: String, property: KProperty<*>): Int = 0
            val answer by ValueDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], emit: useArtifact ? .executable : .kirDump,
                allowDefaultStdlibLibrary: useArtifact
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            guard !ctx.diagnostics.hasError else { return }
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            func delegate(for owner: String, property: String) throws -> SymbolID {
                let symbol = try #require(sema.symbols.lookup(
                    fqName: ["kuu2008", owner, property].map(interner.intern)
                ))
                return try #require(sema.symbols.delegateGetValueSymbol(for: symbol))
            }
            let lazyGet = try delegate(for: "Grammar", property: "tokenizer")
            #expect(sema.symbols.symbol(lazyGet)?.fqName.dropLast().map(interner.resolve) == ["kotlin"])
            let memberOwner = try #require(sema.symbols.lookup(
                fqName: ["kuu2008", "MemberGrammar"].map(interner.intern)
            ))
            let memberGet = try delegate(for: "MemberGrammar", property: "answer")
            #expect(sema.symbols.memberExtensionOwnerSymbol(for: memberGet) == memberOwner)
            for owner in ["LexicalGrammar", "WrongArgumentGrammar"] {
                let outerGet = try delegate(for: owner, property: "answer")
                #expect(sema.symbols.symbol(outerGet)?.fqName.map(interner.resolve) == ["kuu2008", "getValue"])
            }
        }
    }

    @Test
    func hiddenOverloadDoesNotDisplaceVisibleConvention() throws {
        let source = """
        import kotlin.reflect.KProperty
        class ValueDelegate
        @Deprecated("gone", level = DeprecationLevel.HIDDEN)
        operator fun ValueDelegate.getValue(thisRef: Any?, property: KProperty<*>): Int = 0
        operator fun Any.getValue(thisRef: Any?, property: KProperty<*>): Int = 42
        val answer by ValueDelegate()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let property = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("answer")]))
            let getValue = try #require(sema.symbols.delegateGetValueSymbol(for: property))
            #expect(sema.symbols.functionSignature(for: getValue)?.receiverType == sema.types.anyType)
        }
    }

    @Test
    func unimportedBundledExtensionRemainsUnavailable() throws {
        let declaration = """
        package hidden.delegate
        import kotlin.reflect.KProperty
        class ValueDelegate
        operator fun ValueDelegate.getValue(thisRef: Any?, property: KProperty<*>): Int = 42
        """
        let usage = """
        import hidden.delegate.ValueDelegate
        import kotlin.reflect.KProperty
        class Grammar {
            operator fun String.getValue(thisRef: Grammar, property: KProperty<*>): Int = 0
            val answer by ValueDelegate()
        }
        """
        try withTemporaryFile(contents: usage) { path in
            let ctx = makeCompilationContext(inputs: [path])
            _ = ctx.sourceManager.addFile(
                path: "__bundled_delegate.kt", contents: Data(declaration.utf8), origin: .bundledStdlib
            )
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0103" }.count == 1,
                    "\(ctx.diagnostics.diagnostics)")
        }
    }
}
