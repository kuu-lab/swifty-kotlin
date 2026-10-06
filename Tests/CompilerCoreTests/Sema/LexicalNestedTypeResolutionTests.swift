@testable import CompilerCore
import Foundation
import Testing

@Suite
struct LexicalNestedTypeResolutionTests {
    private func context(_ source: String) -> CompilationContext {
        let ctx = makeCompilationContext(inputs: ["/lexical-nested-type/input.kt"], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: ctx.options.inputs[0], contents: Data(source.utf8))
        return ctx
    }

    @Test(arguments: [true, false], ["", "package model"])
    func qualifiedNestedReturnAnnotationResolves(memberFirst: Bool, packageLine: String) throws {
        let nested = """
        private sealed interface Slot {
            data class Closed(val cause: Throwable?) : Slot
        }
        """
        let member = "private fun closed(cause: Throwable?): Slot.Closed = Slot.Closed(cause)"
        let source = """
        \(packageLine)
        class Ch {
            \((memberFirst ? [member, nested] : [nested, member]).joined(separator: "\n"))
        }
        fun main() {}
        """
        let ctx = context(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let prefix = packageLine.isEmpty ? [] : ["model"]
        try expectSignature(["Ch", "closed"], returns: ["Ch", "Slot", "Closed"], prefix: prefix, in: ctx)
    }

    @Test
    func enclosingRootWinsOverPackageRootAndPreservesArguments() throws {
        let ctx = context("""
        package model
        class Slot { class Closed<T> }
        class Ch {
            interface Slot { class Closed<T> }
            class Inner {
                fun closed(value: Slot.Closed<String>?): Slot.Closed<String>? = value
            }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let signature = try expectSignature(
            ["Ch", "Inner", "closed"], returns: ["Ch", "Slot", "Closed"], prefix: ["model"], in: ctx
        )
        let sema = try #require(ctx.sema)
        #expect(signature.parameterTypes == [signature.returnType])
        guard case let .classType(type) = sema.types.kind(of: signature.returnType) else { return }
        #expect(type.nullability == .nullable)
        #expect(type.args == [.invariant(sema.types.stringType)])
    }

    @Test
    func missingLexicalNestedMemberFallsBackToPackageRoot() throws {
        let ctx = context("""
        class Slot { class Closed }
        class Ch {
            interface Slot
            fun closed(value: Slot.Closed): Slot.Closed = value
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        try expectSignature(["Ch", "closed"], returns: ["Slot", "Closed"], prefix: [], in: ctx)
    }

    @Test
    func missingQualifierDoesNotBindAnUnrelatedNestedType() throws {
        let ctx = context("""
        class Other { class Closed }
        class Ch {
            interface Slot
            fun closed(value: Slot.Closed): Slot.Closed = value
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0025" })
    }

    @discardableResult
    private func expectSignature(
        _ function: [String], returns target: [String], prefix: [String], in ctx: CompilationContext
    ) throws -> FunctionSignature {
        let sema = try #require(ctx.sema)
        let symbol = try #require(sema.symbols.lookup(fqName: (prefix + function).map(ctx.interner.intern)))
        let signature = try #require(sema.symbols.functionSignature(for: symbol))
        guard case let .classType(type) = sema.types.kind(of: signature.returnType) else {
            Issue.record("Expected a nominal return type")
            throw CompilerPipelineError.invalidInput("Expected a nominal return type")
        }
        #expect(sema.symbols.symbol(type.classSymbol)?.fqName == (prefix + target).map(ctx.interner.intern))
        return signature
    }
}
