import Foundation
@testable import CompilerCore
import CompilerTestSupport
import Testing

@Suite
struct NonInlineRecursiveCallbackTests {
    @Test
    func mandatoryTemplatesKeepTheirRecursionDiagnostics() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let diagnostics = DiagnosticEngine()
        let explicit = symbols.define(
            kind: .function, name: interner.intern("explicit"), fqName: [interner.intern("explicit")],
            declSite: nil, visibility: .public, flags: [.inlineFunction]
        )
        bindings.bindDecl(DeclID(rawValue: 0), symbol: explicit)
        let lambda = symbols.define(
            kind: .function, name: interner.intern("lambda"), fqName: [interner.intern("lambda")],
            declSite: nil, visibility: .private, flags: []
        )
        let arena = KIRArena()
        for symbol in [explicit, lambda] {
            let name = try #require(symbols.symbol(symbol)?.name)
            _ = arena.appendDecl(.function(KIRFunction(
                symbol: symbol, name: name, params: [], returnType: types.unitType,
                body: [.call(symbol: symbol, callee: name, arguments: [], result: nil,
                             canThrow: false)],
                isSuspend: false, isInline: true, isInlineOnly: true
            )))
        }
        let sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)
        let options = makeCompilationContext(inputs: [], moduleName: "Templates", includeStdlib: false).options
        let context = KIRContext(diagnostics: diagnostics, options: options, interner: interner, sema: sema)
        let module = KIRModule(files: [], arena: arena)
        try InlineLoweringPass().run(module: module, ctx: context)
        let errors = diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 2)
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-INL-0001" && $0.message.contains("recursive") })
        #expect(findAllKIRFunctions(in: module).allSatisfy { $0.isInlineOnly })
    }

    @Test
    func recursiveDeclarationsKeepNativeBodiesAndCalls() throws {
        let source = """
        fun process(value: Int, handler: (Int) -> Int): Int {
            return if (value == 0) handler(value) else process(value - 1, handler)
        }
        fun Int.extension(handler: (Int) -> Int): Int {
            return if (this == 0) handler(this) else (this - 1).extension(handler)
        }
        fun even(value: Int, handler: (Int) -> Int): Int =
            if (value == 0) handler(value) else odd(value - 1, handler)
        fun odd(value: Int, handler: (Int) -> Int): Int =
            if (value == 0) handler(value) else even(value - 1, handler)
        fun plain(value: Int, handler: (Int) -> Int): Int = handler(value)
        inline fun explicitInline(value: Int, handler: (Int) -> Int): Int = handler(value)
        fun wrapped(value: Int, handler: (Int) -> Int): Int =
            if (value == 0) handler(value) else step(value - 1, handler)
        inline fun step(value: Int, noinline handler: (Int) -> Int): Int = wrapped(value, handler)
        """
        let path = "/tmp/noninline-recursive-callback.kt"
        let context = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = context.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runToKIR(context)
        try #require(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let module = try #require(context.kir)
        let recursiveNames: Set<String> = ["process", "extension", "even", "odd", "wrapped"]
        let before = findAllKIRFunctions(in: module).filter {
            recursiveNames.contains(context.interner.resolve($0.name))
        }
        #expect(before.count == 5)
        #expect(before.allSatisfy { $0.isInlineOnly })
        try LoweringPhase().run(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let functions = findAllKIRFunctions(in: module)
        let recursive = functions.filter { recursiveNames.contains(context.interner.resolve($0.name)) }
        #expect(recursive.count == 5)
        #expect(recursive.allSatisfy { !$0.isInline && !$0.isInlineOnly })
        let symbols = Set(recursive.map(\.symbol))
        for function in recursive {
            #expect(function.body.contains {
                if case let .call(symbol?, _, _, _, _, _, _, _) = $0 { return symbols.contains(symbol) }
                return false
            })
        }
        let plain = try #require(functions.first { context.interner.resolve($0.name) == "plain" })
        #expect(plain.isInline && plain.isInlineOnly)
        let explicit = try #require(functions.first { context.interner.resolve($0.name) == "explicitInline" })
        #expect(explicit.isInline && !explicit.isInlineOnly)
    }
}
