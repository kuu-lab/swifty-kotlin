#if canImport(Testing)
@testable import CompilerCore
import RuntimeABI
import Testing

extension BuildKIRRegressionTests {
    /// Test-facing selectors must resolve to an ABI declaration or internal callee.
    /// Missing catalogue entries fail even when the caller asserts their absence.
    enum RuntimeCall: String, CaseIterable {
        case arraySize = "__kk_array_size"
        case stringConcat = "__kk_string_concat_flat"
        case stringSplit = "__kk_string_split"
        case stringLength = "__kk_string_struct_get_length"
        case arrayGet = "kk_array_get"
        case arrayGetInbounds = "kk_array_get_inbounds"
        case arrayNew = "kk_array_new"
        case arraySet = "kk_array_set"
        case boxDoubleNonnull = "kk_box_double_nonnull"
        case boxInt = "kk_box_int"
        case boxIntStatic = "kk_box_int_static"
        case boxLong = "kk_box_long"
        case boxLongNonnullStatic = "kk_box_long_nonnull_static"
        case functionCreate0 = "kk_function_create_0"
        case functionCreate1 = "kk_function_create_1"
        case functionCreate2 = "kk_function_create_2"
        case functionInvoke = "kk_function_invoke"
        case jobCancel = "kk_job_cancel"
        case jobJoin = "kk_job_join"
        case asyncAwait = "kk_kxmini_async_await"
        case objectNew = "kk_object_new"
        case greaterOrEqual = "kk_op_ge"
        case greater = "kk_op_gt"
        case inv = "kk_op_inv"
        case isType = "kk_op_is"
        case lessOrEqual = "kk_op_le"
        case less = "kk_op_lt"
        case multiply = "kk_op_mul"
        case notEqual = "kk_op_ne"
        case rangeHasNext = "kk_range_hasNext"
        case rangeIterator = "kk_range_iterator"
        case rangeNext = "kk_range_next"
        case legacyStringSplit = "kk_string_split_flat"
        case legacyStringLength = "kk_string_struct_get_length"
        case legacyStringTrim = "kk_string_trim_flat"
        case structuralNotEqual = "kk_structural_ne"
        case isCancellation = "kk_throwable_is_cancellation"
        case unboxInt = "kk_unbox_int"
        case workerExecute = "kk_worker_execute"
    }

    struct RuntimeNames {
        private let names: [RuntimeCall: String]

        init() throws {
            names = Dictionary(uniqueKeysWithValues: try RuntimeCall.allCases.map { call in
                let name: String?
                switch call {
                case .stringLength, .legacyStringLength:
                    name = RuntimeABISpec.compilerInternalBuiltinCalleeNames.first { $0 == call.rawValue }
                case .multiply:
                    name = RuntimeABISpec.compilerInternalNonThrowingCalleeNames.first { $0 == call.rawValue }
                default:
                    name = RuntimeABIExterns.externDecl(named: call.rawValue)?.name
                }
                return (call, try #require(name, "Missing ABI or internal callee declaration for \(call)"))
            })
        }

        subscript(_ call: RuntimeCall) -> String {
            // Initialization requires an entry for every enum case.
            names[call]!
        }

        var boxingNames: Set<String> {
            Set((RuntimeABISpec.boxingFunctions + RuntimeABISpec.staticPrimitiveBoxingFunctions)
                .filter { $0.name.hasPrefix("kk_box_") }.map(\.name))
        }

        var doubleBoxingNames: Set<String> {
            Set((RuntimeABISpec.boxingFunctions + RuntimeABISpec.staticPrimitiveBoxingFunctions)
                .filter { $0.name.hasPrefix("kk_box_double") }.map(\.name))
        }

        var operatorNames: Set<String> {
            Set(RuntimeABISpec.allFunctions.map(\.name))
                .union(RuntimeABISpec.compilerInternalNonThrowingCalleeNames)
                .filter { $0.hasPrefix("kk_op_") }
        }

        func functionInvoke(arity: Int) throws -> String {
            let key = arity == 1 ? self[.functionInvoke] : "kk_function_invoke_\(arity)"
            return try #require(RuntimeABIExterns.externDecl(named: key)).name
        }
    }

    /// Fixture names are resolved to semantic identities, including their owner.
    func sourceSymbol(
        named name: String,
        kind: SymbolKind = .function,
        in ctx: CompilationContext
    ) throws -> SymbolID {
        let sema = try #require(ctx.sema)
        let internedName = ctx.interner.intern(name)
        let candidates = sema.symbols.allSymbols().filter { symbol in
            symbol.kind == kind && symbol.name == internedName
                && symbol.declSite != nil
                && ctx.options.inputs.contains { path in
                    ctx.sourceManager.fileID(forPath: path) == symbol.declSite?.start.file
                }
        }
        try #require(candidates.count == 1, "Expected one source symbol for \(name), found \(candidates.count)")
        return candidates[0].id
    }

    /// Callable metadata identifies generated adapters and their unboxed targets
    /// without relying on generated function names or symbol-number ranges.
    func callableAdapterSymbols(in module: KIRModule) -> Set<SymbolID> {
        Set(module.arena.callableValueInfoByExprID.values
            .filter(\.hasClosureParam).map(\.symbol))
    }

    func unboxedCallableSymbols(in module: KIRModule) -> Set<SymbolID> {
        Set(module.arena.callableValueInfoByExprID.values.map { $0.unboxedSymbol ?? $0.symbol })
    }

    func isCallableAdapter(_ callee: InternedString, in module: KIRModule) -> Bool {
        let symbols = callableAdapterSymbols(in: module)
        return findAllKIRFunctions(in: module).contains { $0.name == callee && symbols.contains($0.symbol) }
    }

    func callsSymbol(_ symbol: SymbolID, in body: [KIRInstruction]) -> Bool {
        body.contains { instruction in
            guard case let .call(calleeSymbol, _, _, _, _, _, _, _) = instruction else { return false }
            return calleeSymbol == symbol
        }
    }

    func defaultStubSymbol(named originalName: String, in ctx: CompilationContext) throws -> SymbolID {
        SyntheticSymbolScheme.defaultStubSymbol(for: try sourceSymbol(named: originalName, in: ctx))
    }

    func expressionBodyCallSymbol(named functionName: String, in ctx: CompilationContext) throws -> SymbolID {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let expr = try #require(topLevelExpressionBodyExprID(named: functionName, ast: ast, interner: ctx.interner))
        return try #require(sema.bindings.callBinding(for: expr)).chosenCallee
    }

    func samImplementation(named interfaceName: String, in ctx: CompilationContext) throws -> KIRFunction {
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let interfaceSymbol = try sourceSymbol(named: interfaceName, kind: .interface, in: ctx)
        let interface = try #require(sema.symbols.symbol(interfaceSymbol))
        let method = try #require(sema.symbols.children(ofFQName: interface.fqName).compactMap {
            sema.symbols.symbol($0)
        }.first { $0.kind == .function && $0.flags.contains(.abstractType) })
        let implementations = findAllKIRFunctions(in: module).filter { function in
            guard function.name == method.name,
                  sema.symbols.symbol(function.symbol)?.flags.contains(.synthetic) == true,
                  let ownerID = sema.symbols.parentSymbol(for: function.symbol),
                  let owner = sema.symbols.symbol(ownerID)
            else { return false }
            return owner.kind == .class && owner.flags.contains(.synthetic)
                && sema.symbols.directSupertypes(for: ownerID).contains(interfaceSymbol)
        }
        try #require(implementations.count == 1, "Expected one generated SAM implementation for \(interfaceName)")
        return implementations[0]
    }
}
#endif
