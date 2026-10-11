#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite
struct InheritedLiteralAndMemberScopeTests {
    private func context(_ sources: [String], library: Bool) throws -> CompilationContext {
        if library { TestStdlibCache.shared.prepare() }
        let artifact = library ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let paths = sources.indices.map { _ in
            FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        }
        let ctx = makeCompilationContext(inputs: paths, stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false)
        for (path, source) in zip(paths, sources) {
            _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        }
        #expect(ctx.options.stdlibLibraryPath == artifact)
        #expect(ctx.options.includeStdlib == !library)
        return ctx
    }

    private func fixture(_ name: String) throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
    }

    @Test(arguments: [false, true])
    func inheritedIOMethodKeepsLongLiteralAndChosenOwner(library: Bool) throws {
        let ctx = try context(["""
        import kotlinx.io.*
        import kotlin.test.*
        fun literal(source: Source): Long = source.readAtMostTo(Buffer(), 10)
        fun suffix(source: Source): Long = source.readAtMostTo(Buffer(), 10L)
        fun raw(source: RawSource): Long = source.readAtMostTo(Buffer(), 10)
        fun direct(source: Buffer): Long = source.readAtMostTo(Buffer(), 10)
        fun nested(source: Source) { assertEquals(-1, source.readAtMostTo(Buffer(), 10)) }
        fun unitContext(source: Source) { assertFailsWith<IllegalArgumentException> { source.readAtMostTo(Buffer(), 1) } }
        """], library: library)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let path = try #require(ctx.options.inputs.first)
        var rawRanges: Set<SourceRange> = []
        var typed: [SourceRange: ExprID] = [:]
        for (index, expr) in ast.arena.exprs.enumerated() {
            guard case let .memberCall(_, name, _, _, _) = expr,
                  ctx.interner.resolve(name) == "readAtMostTo" else { continue }
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id), ctx.sourceManager.path(of: range.start.file) == path else { continue }
            rawRanges.insert(range)
            if sema.bindings.callBinding(for: id) != nil { typed[range] = id }
        }
        #expect(rawRanges.count == 6)
        #expect(Set(typed.keys) == rawRanges)
        var owners: [String: Int] = [:]
        for id in typed.values {
            let binding = try #require(sema.bindings.callBinding(for: id))
            let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            try #require(signature.parameterTypes.count == 2)
            #expect(signature.parameterTypes[1] == sema.types.longType)
            #expect(signature.returnType == sema.types.longType)
            #expect(symbol.flags.contains(.importedLibrary) == library)
            let fqName = symbol.fqName.map(ctx.interner.resolve).joined(separator: ".")
            owners[fqName, default: 0] += 1
            guard case let .memberCall(_, _, _, arguments, _) = ast.arena.expr(id) else { continue }
            #expect(sema.bindings.exprType(for: arguments[1].expr) == sema.types.longType)
        }
        #expect(owners == ["kotlinx.io.RawSource.readAtMostTo": 5, "kotlinx.io.Buffer.readAtMostTo": 1])
    }

    @Test(arguments: [false, true])
    func sameNameFallbackKeepsApplicableMembersExtensionsAndOuterReceiver(library: Bool) throws {
        let ctx = try context([fixture("Scripts/diff_cases/inherited_literal_member_scope.kt")], library: library)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let path = try #require(ctx.options.inputs.first)
        var selectedNames: Set<String> = []
        var choseReceiverExtension = false
        for (index, expr) in ast.arena.exprs.enumerated() {
            guard case let .call(callee, _, _, _) = expr,
                  case let .nameRef(name, _) = ast.arena.expr(callee),
                  ["gate", "width", "choose", "route"].contains(ctx.interner.resolve(name)) else { continue }
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id), ctx.sourceManager.path(of: range.start.file) == path,
                  let binding = sema.bindings.callBinding(for: id), let symbol = sema.symbols.symbol(binding.chosenCallee) else { continue }
            selectedNames.insert(symbol.fqName.map(ctx.interner.resolve).joined(separator: "."))
            if ctx.interner.resolve(name) == "width" {
                #expect(symbol.fqName.map(ctx.interner.resolve) == ["collisioncontract", "width"])
                #expect(sema.symbols.functionSignature(for: binding.chosenCallee)?.parameterTypes == [sema.types.longType])
            }
            if ctx.interner.resolve(name) == "route" {
                #expect(symbol.fqName.map(ctx.interner.resolve) == ["collisioncontract", "Outer", "route"])
            }
            if symbol.fqName.map(ctx.interner.resolve) == ["collisioncontract", "choose"],
               let receiver = sema.symbols.functionSignature(for: binding.chosenCallee)?.receiverType,
               case let .classType(classType) = sema.types.kind(of: receiver),
               sema.symbols.symbol(classType.classSymbol)?.fqName.map(ctx.interner.resolve)
                   == ["collisioncontract", "ExtensionFallback"]
            {
                choseReceiverExtension = true
            }
        }
        #expect(selectedNames.contains("collisioncontract.gate"))
        #expect(selectedNames.contains("collisioncontract.Collision.gate"))
        #expect(selectedNames.contains("collisioncontract.Priority.choose"))
        #expect(selectedNames.contains("collisioncontract.choose"))
        #expect(selectedNames.contains("collisioncontract.Outer.route"))
        #expect(choseReceiverExtension, "An applicable receiver extension precedes the same-tier top-level function")
    }

    @Test(arguments: [false, true], [0, 1, 2, 3, 4])
    func typedInputsRangesSuffixesAndMemberPriorityRemainRejected(library: Bool, index: Int) throws {
        let source = try fixture("Scripts/compiler_fixtures/overload_scope/negative-\(index).kt")
        let ctx = try context([source], library: library)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "\(errors)")
        #expect(errors.first?.code == (index == 4 ? "KSWIFTK-SEMA-0003" : "KSWIFTK-SEMA-0002"))
        // Every file isolates one rejected call rather than hiding missed
        // diagnostics behind an aggregate count across several statements.
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let path = try #require(ctx.options.inputs.first)
        let rejected = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
            switch expr {
            case let .memberCall(_, name, _, _, _): return ctx.interner.resolve(name) == "read"
            case let .call(callee, _, _, _):
                guard case let .nameRef(name, _) = ast.arena.expr(callee) else { return false }
                return ["choose", "ambiguous"].contains(ctx.interner.resolve(name))
            default: return false
            }
        })
        #expect(sema.bindings.callBinding(for: rejected) == nil)
    }

    @Test(arguments: [false, true])
    func inheritedLiteralKeepsValidByteRangeBoundaries(library: Bool) throws {
        let ctx = try context(["""
        interface ByteBase { fun read(target: String, count: Byte): Int }
        interface ByteChild : ByteBase { fun read(target: Int, start: Int = 0): Int }
        fun boundaries(reader: ByteChild) { reader.read("sink", 127); reader.read("sink", -128) }
        """], library: library)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let path = try #require(ctx.options.inputs.first)
        var ranges: Set<SourceRange> = []
        for (index, expr) in ast.arena.exprs.enumerated() {
            guard case let .memberCall(_, name, _, arguments, _) = expr,
                  ctx.interner.resolve(name) == "read" else { continue }
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id), ctx.sourceManager.path(of: range.start.file) == path,
                  let binding = sema.bindings.callBinding(for: id) else { continue }
            ranges.insert(range)
            #expect(sema.symbols.symbol(binding.chosenCallee)?.fqName.map(ctx.interner.resolve) == ["ByteBase", "read"])
            #expect(sema.bindings.exprType(for: arguments[1].expr) == sema.types.byteType)
        }
        #expect(ranges.count == 2)
    }

    @Test(arguments: [false, true], [false, true])
    func fallbackPreservesFilePrivateExtensionVisibility(library: Bool, sameFile: Bool) throws {
        let declaration = """
        package visibilitycontract
        class Receiver { fun choose(value: String): Int = 1 }
        private fun Receiver.choose(value: Int): Int = 2
        """
        let use = """
        package visibilitycontract
        fun Receiver.use(): Int = choose(1)
        """
        let sources = sameFile ? [declaration + "\nfun Receiver.use(): Int = choose(1)"] : [declaration, use]
        let ctx = try context(sources, library: library)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError == !sameFile, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "typeParameter", "kClass", "functionContext", "functionReceiver",
        "functionParameter", "functionResult", "functionThrows", "classInvariant",
        "classOut", "classIn", "intersection", "error", "unknown", "star", "closedControl"
    ], [false, true])
    func openTypesDeferWithoutCommittingProbeBindings(shape: String, inSignature: Bool) throws {
        // Exercise the actual tower selection, rather than just testing the
        // structural predicate. A deferred probe keeps the member tier and
        // leaves the scalar argument's identifier/type bindings untouched.
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        types.symbolTable = symbols
        let bindings = BindingTable()
        let diagnostics = DiagnosticEngine()
        let sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)
        let arena = ASTArena()
        let ast = ASTModule(files: [], arena: arena, declarationCount: 0, tokenCount: 0)
        let resolver = OverloadResolver()
        let dataFlow = DataFlowAnalyzer()
        let driver = TypeCheckDriver(
            ast: ast, sema: sema, semaCtx: sema, solver: ConstraintSolver(),
            resolver: resolver, dataFlow: dataFlow, interner: interner, diagnostics: diagnostics
        )
        let ownerName = interner.intern("ProbeReceiver")
        let owner = symbols.define(kind: .class, name: ownerName, fqName: [ownerName], declSite: nil, visibility: .public)
        let receiverType = types.make(.classType(ClassType(classSymbol: owner)))
        let parameterName = interner.intern("T")
        let parameter = symbols.define(
            kind: .typeParameter, name: parameterName, fqName: [parameterName], declSite: nil, visibility: .public
        )
        let open = types.make(.typeParam(TypeParamType(symbol: parameter)))
        let testedType: TypeID
        switch shape {
        case "typeParameter": testedType = open
        case "kClass": testedType = types.make(.kClassType(KClassType(argument: open)))
        case "functionContext":
            testedType = types.make(.functionType(FunctionType(contextReceivers: [open], params: [], returnType: types.unitType)))
        case "functionReceiver":
            testedType = types.make(.functionType(FunctionType(receiver: open, params: [], returnType: types.unitType)))
        case "functionParameter":
            testedType = types.make(.functionType(FunctionType(params: [open], returnType: types.unitType)))
        case "functionResult":
            testedType = types.make(.functionType(FunctionType(params: [], returnType: open)))
        case "functionThrows":
            testedType = types.make(.functionType(FunctionType(params: [], returnType: types.unitType, throws: [open])))
        case "classInvariant": testedType = types.make(.classType(ClassType(classSymbol: owner, args: [.invariant(open)])))
        case "classOut": testedType = types.make(.classType(ClassType(classSymbol: owner, args: [.out(open)])))
        case "classIn": testedType = types.make(.classType(ClassType(classSymbol: owner, args: [.in(open)])))
        case "intersection": testedType = types.make(.intersection([types.anyType, open]))
        case "error": testedType = types.errorType
        case "unknown": testedType = TypeID(rawValue: Int32.max)
        case "star": testedType = types.make(.classType(ClassType(classSymbol: owner, args: [.star])))
        case "closedControl": testedType = types.intType
        default: preconditionFailure("Unexpected test shape")
        }
        let name = interner.intern("probe")
        let member = symbols.define(kind: .function, name: name, fqName: [ownerName, name], declSite: nil, visibility: .public)
        symbols.setParentSymbol(owner, for: member)
        symbols.setFunctionSignature(FunctionSignature(
            receiverType: receiverType, parameterTypes: [types.intType],
            returnType: inSignature ? testedType : types.intType,
            valueParameterHasDefaultValues: [false]
        ), for: member)
        let scope = ClassMemberScope(parent: nil, symbols: symbols, ownerSymbol: owner, thisType: receiverType)
        scope.insert(member)
        let inputName = interner.intern("input")
        let input = symbols.define(kind: .local, name: inputName, fqName: [inputName], declSite: nil, visibility: .private)
        let locals: LocalBindings = [inputName: (inSignature ? types.intType : testedType, input, false, true)]
        let range = SourceRange(start: SourceLocation(file: FileID(rawValue: 0), offset: 0),
                                end: SourceLocation(file: FileID(rawValue: 0), offset: 1))
        let expression = arena.appendExpr(.nameRef(inputName, range))
        let context = TypeInferenceContext(
            ast: ast, sema: sema, semaCtx: sema, resolver: resolver, dataFlow: dataFlow,
            interner: interner, scope: scope, implicitReceiverType: receiverType,
            loopDepth: 0, loopLabelStack: [], lambdaLabelStack: [], exportBlockLocalsForExpr: nil,
            flowState: DataFlowState(), currentFileID: FileID(rawValue: 0), enclosingClassSymbol: owner,
            visibilityChecker: VisibilityChecker(symbols: symbols), outerReceiverTypes: [],
            semaCacheContext: nil, useNewInference: false, useUnrestrictedBuilderInference: false,
            useProperTypeInferenceConstraintsProcessing: false, globalOptInMarkerNames: []
        )
        let selection = driver.callChecker.scopeCallCandidatesAfterInapplicableMembers(
            named: name, args: [CallArgument(expr: expression)], range: range,
            explicitTypeArgs: [], ctx: context, locals: locals
        )
        try #require(selection.candidates == [member])
        try #require(selection.excludedMembers.isEmpty)
        try #require(!diagnostics.hasError)
        if shape == "closedControl" {
            try #require(selection.knownApplicableMembers == [member])
            try #require(bindings.exprType(for: expression) == types.intType)
            try #require(bindings.identifierSymbol(for: expression) == input)
        } else {
            try #require(selection.knownApplicableMembers.isEmpty)
            try #require(bindings.exprType(for: expression) == nil)
            try #require(bindings.identifierSymbol(for: expression) == nil)
        }
    }
}
#endif
