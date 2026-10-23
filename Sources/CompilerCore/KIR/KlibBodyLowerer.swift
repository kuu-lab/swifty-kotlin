/// Runs during ``KIRLoweringDriver.lowerModule`` after every source file has
/// been lowered, so the consumer `SymbolTable`/`TypeSystem` already hold the
/// materialized declarations (PR4) and their synthesized layouts. Declarations
/// without a serialized body keep their external/precompiled identity — only
/// `bodyIndex`-carrying functions, constructors, accessors and field
/// initializers become `KIRFunction`/`KIRGlobal` declarations here.
final class KlibBodyLowerer {
    private let loaded: DataFlowSemaPhase.LoadedKlibModule
    private let driver: KIRLoweringDriver
    private let sema: SemaModule
    private let arena: KIRArena
    private let interner: StringInterner
    private let diagnostics: DiagnosticEngine
    private var topLevelInit = KIRLoweringEmitContext()
    /// Object allocations must complete before any initializer can touch the
    /// singleton — they run ahead of every other klib init instruction.
    private var eagerObjectInit = KIRLoweringEmitContext()

    /// All serialized tables (types/signatures/strings/bodies) are file-local.
    private var fileIndex = 0


    /// Serialized value-symbol signature index → bound KIR expression. Plays
    /// the role `ctx.localValuesBySymbol` plays for source lowering: value
    /// parameters map to their `.symbolRef` param expr, local `variable`s map
    /// to a temporary slot.
    private var valueExprs: [Int: KIRExprID] = [:]
    private var mutableValues: Set<Int> = []
    private var mutableCells: [Int: KIRExprID] = [:]
    private struct LiftedLambda {
        let symbol: SymbolID
        let name: InternedString
        let returnType: TypeID
        let captures: [(index: Int, isCell: Bool)]
    }
    private var liftedLambdas: [KlibSignatureKey: LiftedLambda] = [:]
    private var typeParameterSymbols: [KlibSignatureKey: SymbolID] = [:]
    private var returnTargetSignatureIndexes: Set<Int> = []
    /// The callable being translated, used to seed instance fields before a
    /// serialized constructor delegates to its superclass.
    private var currentCallableSymbol: SymbolID?
    /// `returnableBlock` symbol → (end label, result temp) so `return`s aimed
    /// at it jump to its epilogue instead of returning from the function.
    private var returnableBlocks: [Int: (label: Int32, result: KIRExprID?)] = [:]
    /// Kotlin `loopId` → KIR labels for `break`/`continue`.
    private var loopLabels: [Int32: (continueLabel: Int32, breakLabel: Int32)] = [:]
    /// The `this` binding of the current constructor (its dispatch-receiver
    /// parameter), used by `delegatingConstructorCall` and
    /// `instanceInitializerCall`.
    private var thisExpr: KIRExprID?


    /// Member field initializer bodies and anonymous-init bodies per class —
    /// collected before emitting the class's members so a ctor's
    /// `instanceInitializerCall` can expand them in member-declaration order.
    private var classInitBySymbol: [SymbolID: ClassInitInfo] = [:]
    private var emittedGlobals: Set<SymbolID> = []
    /// Objects whose init functions were already synthesized — distinct from
    /// `emittedGlobals` since a forward reference can create the slot first.
    private var emittedObjectInits: Set<SymbolID> = []
    private var reportedUnsupported: Set<String> = []

    private struct ClassInitInfo {
        /// In member-declaration order.
        var fieldInitializers: [(field: SymbolID, bodyIndex: Int32, typeIndex: Int32)] = []
        /// `IrAnonymousInitializer` bodies, also in declaration order.
        var anonymousInitBodyIndices: [Int32] = []
        var fileIndex: Int = 0
    }

    init(
        loaded: DataFlowSemaPhase.LoadedKlibModule,
        driver: KIRLoweringDriver,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        diagnostics: DiagnosticEngine
    ) {
        self.loaded = loaded
        self.driver = driver
        self.sema = sema
        self.arena = arena
        self.interner = interner
        self.diagnostics = diagnostics
    }

    private var ir: KlibIrModule { loaded.ir }
    private var symbols: SymbolTable { sema.symbols }
    private var types: TypeSystem { sema.types }

    /// Non-source KIR file holding every declaration materialized from this
    /// klib plus the top-level initialization instructions the driver must
    /// splice into the module initializer.
    struct Result {
        var file: KIRFile?
        var topLevelInitInstructions = KIRLoweringEmitContext()
    }

    func lowerModule() -> Result {
        var declIDs: [KIRDeclID] = []
        for index in 0 ..< ir.fileCount {
            fileIndex = index
            for declaration in (try? ir.declarations(fileIndex: index)) ?? [] {
                bindTypeParameters(declaration)
            }
        }
        for index in 0 ..< ir.fileCount {
            fileIndex = index
            guard let file = try? ir.file(index) else { continue }
            for declarationId in file.declarationIds {
                guard let declaration = try? ir.declaration(declarationId, fileIndex: index) else {
                    continue
                }
                declIDs.append(contentsOf: emitDeclaration(declaration))
            }
        }
        var orderedInit = KIRLoweringEmitContext()
        declIDs.append(contentsOf: driver.ctx.drainGeneratedCallableDecls())
        orderedInit.appendRelocatingLabels(contentsOf: eagerObjectInit)
        orderedInit.appendRelocatingLabels(contentsOf: topLevelInit)
        return Result(
            file: declIDs.isEmpty
                ? nil
                : KIRFile(fileID: .invalid, decls: declIDs),
            topLevelInitInstructions: orderedInit
        )
    }

    /// A type-parameter signature is a local/composite signature, not its
    /// containing class/function symbol. Preserve the metadata binder's IDs.
    private func bindTypeParameters(_ declaration: KlibIrDeclaration) {
        func bind(_ parameters: [KlibTypeParameter], to symbols: [SymbolID]) {
            for (parameter, symbol) in zip(parameters, symbols.suffix(parameters.count)) {
                typeParameterSymbols[KlibSignatureKey(
                    fileIndex: fileIndex, signatureIndex: parameter.base.symbol.signatureIndex
                )] = symbol
            }
        }
        switch declaration {
        case .class(let klass):
            if let symbol = symbol(for: klass.base.symbol) {
                bind(klass.typeParameters, to: types.allTypeParameterSymbols(for: symbol))
            }
            for member in klass.declarations { bindTypeParameters(member) }
        case .function(let function):
            if let symbol = symbol(for: function.base.base.symbol),
               let signature = symbols.functionSignature(for: symbol) {
                bind(function.base.typeParameters, to: signature.typeParameterSymbols)
            }
        case .constructor(let constructor):
            if let symbol = symbol(for: constructor.base.base.symbol),
               let signature = symbols.functionSignature(for: symbol) {
                bind(constructor.base.typeParameters, to: signature.typeParameterSymbols)
            }
        default: break
        }
    }


    private func emitDeclaration(_ declaration: KlibIrDeclaration) -> [KIRDeclID] {
        switch declaration {
        case .function(let function):
            return emitCallable(function.base)
        case .constructor(let constructor):
            return emitCallable(constructor.base)
        case .property(let property):
            let declIDs = emitPropertyAccessors(property)
            // Top-level backing fields are real globals, not class slots.
            if let field = property.backingField {
                emitTopLevelField(field)
            }
            return declIDs
        case .field(let field):
            emitTopLevelField(field)
            return []
        case .class(let klass):
            return emitClass(klass)
        case .enumEntry:
            // Ordinal slot + static init are synthesized by the enum pass
            // once the enclosing class's `.nominalType` lands in the arena.
            return []
        case .anonymousInit, .typeParameter, .typeAlias,
             .valueParameter, .variable, .localDelegatedProperty:
            return []
        }
    }

    /// `(fileIndex, signatureIndex)` → consumer `SymbolID`. The materializer
    /// keyed every registered record; references outside this module (stdlib
    /// artifacts, `depends` klibs) resolve by fully-qualified name.
    private func symbol(for ref: KlibSymbolRef) -> SymbolID? {
        let key = KlibSignatureKey(fileIndex: fileIndex, signatureIndex: ref.signatureIndex)
        if let symbol = typeParameterSymbols[key] { return symbol }
        if let symbol = loaded.symbolBySignature[key] {
            return symbol
        }
        if let signature = try? ir.publicSignature(ref.signatureIndex, fileIndex: fileIndex),
           let symbol = loaded.symbolByPublicSignature[signature] {
            return symbol
        }
        return resolveExternalSymbol(ref)
    }

    private func resolveExternalSymbol(_ ref: KlibSymbolRef, visited: Set<Int> = []) -> SymbolID? {
        guard !visited.contains(ref.signatureIndex), visited.count < 64 else { return nil }
        var visited = visited
        visited.insert(ref.signatureIndex)
        guard let signature = try? ir.signature(ref.signatureIndex, fileIndex: fileIndex) else {
            return nil
        }
        func ownModuleSymbol(_ signatureIndex: Int32) -> SymbolID? {
            loaded.symbolBySignature[KlibSignatureKey(
                fileIndex: fileIndex, signatureIndex: Int(signatureIndex)
            )]
        }
        switch signature {
        case .common(let packageFqName, let declarationFqName, _, _, _):
            let segments = packageFqName + declarationFqName
            guard !segments.isEmpty else { return nil }
            let fqName = segments.compactMap { try? ir.string($0, fileIndex: fileIndex) }
            guard fqName.count == segments.count else { return nil }
            let interned = fqName.map { interner.intern($0) }
            return symbols.lookupAll(fqName: interned).first ?? symbols.lookup(fqName: interned)
        case .accessor(let propertySignature, let name, _, _, _):
            // External accessor → the property's synthetic accessor symbol,
            // mirroring `finalizeKlibModule`'s synthetic-key registration.
            guard propertySignature >= 0,
                  let propertyRef = KlibSymbolRef((Int64(propertySignature) << 8) | Int64(KlibSymbolKind.property.rawValue)),
                  let propertySymbol = ownModuleSymbol(propertySignature)
                    ?? resolveExternalSymbol(propertyRef, visited: visited)
            else { return nil }
            let accessorName = (try? ir.string(name, fileIndex: fileIndex)) ?? ""
            if accessorName.hasPrefix("<set-") {
                return SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySymbol)
            }
            return symbols.extensionPropertyGetterAccessor(for: propertySymbol)
                ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
        case .composite(let container, let inner):
            // Composite signatures wrap a nested signature inside a container
            // (backing fields live as `<prop>+<field>` composites) — resolve
            // the inner entry first, then the container.
            return ownModuleSymbol(inner) ?? ownModuleSymbol(container)
        case .fileLocal, .scopedLocal, .local, .file:
            return nil
        }
    }

    /// FQ name of the declaration a symbol ref points at — used to detect
    /// compiler-intrinsic member calls (`kotlin.Int.plus` & friends) whose
    /// symbols have no body anywhere and must map onto `kk_op_*` stubs.
    private func resolvedFqName(of ref: KlibSymbolRef, depth: Int = 0) -> String? {
        guard depth < 64, let signature = try? ir.signature(ref.signatureIndex, fileIndex: fileIndex) else { return nil }
        switch signature {
        case .common(let packageFqName, let declarationFqName, _, _, _):
            guard let package = try? ir.fqName(packageFqName, fileIndex: fileIndex),
                  let declaration = try? ir.fqName(declarationFqName, fileIndex: fileIndex) else { return nil }
            return package.isEmpty ? declaration : "\(package).\(declaration)"
        case .accessor(let property, _, _, _, _):
            guard property >= 0,
                  let propertyRef = KlibSymbolRef((Int64(property) << 8) | Int64(KlibSymbolKind.property.rawValue)) else { return nil }
            return resolvedFqName(of: propertyRef, depth: depth + 1)
        default:
            return nil
        }
    }


    private enum AccessorKind {
        case getter
        case setter
    }

    /// The consumer symbol is the synthetic accessor ID `finalizeKlibModule`
    /// registered, so call sites and vtable slots resolve through the same key
    /// space as source.
    /// Synthetic accessor symbols have no `FunctionSignature` entry — the
    /// signature is rebuilt from the property's recorded metadata instead.
    private func emitAccessor(
        _ function: KlibFunction,
        accessor: AccessorKind,
        propertySymbol: SymbolID
    ) -> [KIRDeclID] {
        let key = KlibSignatureKey(
            fileIndex: fileIndex,
            signatureIndex: function.base.base.symbol.signatureIndex
        )
        guard let accessorSymbol = loaded.symbolBySignature[key],
              let bodyIndex = function.base.bodyIndex
        else { return [] }

        let propertyType = symbols.propertyType(for: propertySymbol) ?? types.anyType
        let receiverType = symbols.extensionPropertyReceiverType(for: propertySymbol)
            ?? symbols.parentSymbol(for: propertySymbol).flatMap { parent -> TypeID? in
                guard let kind = symbols.symbol(parent)?.kind,
                      kind != .package else { return nil }
                return types.make(.classType(ClassType(
                    classSymbol: parent, args: [], nullability: .nonNull
                )))
            }

        var params: [KIRParameter] = []
        if let receiverType {
            params.append(KIRParameter(
                symbol: driver.callSupportLowerer.syntheticReceiverParameterSymbol(
                    functionSymbol: accessorSymbol
                ),
                type: receiverType
            ))
        }
        if accessor == .setter {
            params.append(KIRParameter(
                symbol: driver.ctx.allocateSyntheticGeneratedSymbol(),
                type: propertyType
            ))
        }
        return emitCallableBody(
            base: function.base,
            symbol: accessorSymbol,
            params: params,
            returnType: accessor == .getter ? propertyType : types.unitType,
            bodyIndex: bodyIndex,
            isSuspend: false,
            isInline: function.base.base.flags.isInline,
            isTailrec: false
        )
    }

    private func emitCallable(_ base: KlibFunctionBase) -> [KIRDeclID] {
        let key = KlibSignatureKey(
            fileIndex: fileIndex,
            signatureIndex: base.base.symbol.signatureIndex
        )
        guard let symbol = loaded.symbolBySignature[key],
              let signature = symbols.functionSignature(for: symbol)
        else { return [] }

        var params: [KIRParameter] = []
        if let receiverType = signature.receiverType {
            params.append(KIRParameter(
                symbol: driver.callSupportLowerer.syntheticReceiverParameterSymbol(
                    functionSymbol: symbol
                ),
                type: receiverType
            ))
        }
        // `valueParameterSymbols` may be absent for imported records — bind by
        // position then, synthesizing a unique symbol per slot.
        for (index, paramType) in signature.parameterTypes.enumerated() {
            let paramSymbol = index < signature.valueParameterSymbols.count
                ? signature.valueParameterSymbols[index]
                : driver.ctx.allocateSyntheticGeneratedSymbol()
            let storageType = index < base.regularParameters.count && base.regularParameters[index].varargElementType != nil
                ? decodeType(base.regularParameters[index].nameType.typeIndex) ?? paramType
                : paramType
            params.append(KIRParameter(symbol: paramSymbol, type: storageType))
        }
        // Reified type parameters arrive as trailing `Int` token arguments at
        // call sites — the params mirror source lowering so the body can read
        // them via the same indices.
        if base.base.flags.isInline, !signature.reifiedTypeParameterIndices.isEmpty {
            for index in signature.reifiedTypeParameterIndices.sorted()
            where index < signature.typeParameterSymbols.count {
                params.append(KIRParameter(
                    symbol: SyntheticSymbolScheme.reifiedTypeTokenSymbol(
                        for: signature.typeParameterSymbols[index]
                    ),
                    type: types.intType
                ))
                if symbols.symbol(symbol)?.flags.contains(.legacyReifiedClassTokenABI) != true {
                    params.append(KIRParameter(
                        symbol: SyntheticSymbolScheme.reifiedArrayComponentTokenSymbol(
                            for: signature.typeParameterSymbols[index]
                        ), type: types.intType
                    ))
                }
            }
        }

        var declarations: [KIRDeclID] = []
        if let bodyIndex = base.bodyIndex {
            declarations = emitCallableBody(
                base: base,
                symbol: symbol,
                params: params,
                returnType: signature.returnType,
                bodyIndex: bodyIndex,
                isSuspend: signature.isSuspend || base.base.flags.isSuspend,
                isInline: base.base.flags.isInline,
                isTailrec: base.base.flags.isTailrec
            )
        }
        if base.regularParameters.contains(where: { $0.defaultValueIndex != nil }) {
            declarations.append(emitDefaultStub(base: base, symbol: symbol, signature: signature, params: params))
        }
        return declarations
    }

    /// KLIBs serialize default expressions rather than KSwiftK's `$default`
    /// function. Rebuild that function with the same mask ABI used by source
    /// calls. Bind resolved parameters in order so a default can read `this`
    /// and earlier parameters, and evaluate defaults only when requested.
    private func emitDefaultStub(
        base: KlibFunctionBase,
        symbol: SymbolID,
        signature: FunctionSignature,
        params: [KIRParameter]
    ) -> KIRDeclID {
        valueExprs = [:]
        mutableValues = []
        mutableCells = [:]
        returnableBlocks = [:]
        loopLabels = [:]
        returnTargetSignatureIndexes = []
        thisExpr = nil
        currentCallableSymbol = nil

        let maskSymbols = driver.callSupportLowerer.defaultStubMaskSymbols(
            for: symbol,
            wordCount: DefaultArgumentMask(parameterCount: base.regularParameters.count).stubWords.count
        )
        let maskExprs = maskSymbols.map { arena.appendExpr(.symbolRef($0), type: types.longType) }
        var body: KIRLoweringEmitContext = [.beginBlock]
        for (symbol, expression) in zip(maskSymbols, maskExprs) {
            body.append(.constValue(result: expression, value: .symbolRef(symbol)))
        }
        var forwarded: [KIRExprID] = []
        let receiverCount = signature.receiverType == nil ? 0 : 1
        for (index, parameter) in params.enumerated() {
            let provided = arena.appendExpr(.symbolRef(parameter.symbol), type: parameter.type)
            body.append(.constValue(result: provided, value: .symbolRef(parameter.symbol)))
            if index < receiverCount {
                thisExpr = provided
                for receiver in [base.dispatchReceiver, base.extensionReceiver].compactMap({ $0 }) {
                    valueExprs[receiver.base.symbol.signatureIndex] = provided
                }
                forwarded.append(provided)
                continue
            }
            let regularIndex = index - receiverCount
            guard regularIndex < base.regularParameters.count else {
                forwarded.append(provided) // Reified type tokens.
                continue
            }
            let serialized = base.regularParameters[regularIndex]
            var resolved = provided
            if let defaultIndex = serialized.defaultValueIndex {
                let selected = defaultMaskBit(regularIndex, masks: maskExprs, into: &body)
                let zero = arena.appendExpr(.intLiteral(0), type: types.longType)
                body.append(.constValue(result: zero, value: .intLiteral(0)))
                resolved = arena.appendTemporary(type: parameter.type)
                body.append(.copy(from: provided, to: resolved))
                let after = driver.ctx.makeLoopLabel()
                body.append(.jumpIfEqual(lhs: selected, rhs: zero, target: after))
                do {
                    let expression = try ir.expressionBody(defaultIndex, fileIndex: fileIndex)
                    let value = translateExpression(expression, into: &body)
                    body.append(.copy(from: value, to: resolved))
                } catch {
                    reportUnsupported("undecodable default value for \(debugName(of: base.base.symbol)): \(error)")
                }
                body.append(.label(after))
            }
            valueExprs[serialized.base.symbol.signatureIndex] = resolved
            forwarded.append(resolved)
        }
        let result = arena.appendTemporary(type: signature.returnType)
        let name = symbols.symbol(symbol)?.name ?? interner.intern("<klib>")
        let directCall = KIRInstruction.call(
            symbol: symbol, callee: name, arguments: forwarded,
            result: result, canThrow: true, thrownResult: nil
        )
        if let receiver = thisExpr,
           symbols.symbol(symbol)?.kind != .constructor,
           let dispatch = resolveVirtualDispatchKind(
               callee: symbol, receiverTypeID: arena.exprType(receiver), sema: sema, interner: interner
           ) {
            // Kotlin forbids omitted arguments in super calls. Every mask
            // bit therefore belongs to a parameter, including bit 30.
            body.append(.virtualCall(
                symbol: symbol, callee: name, receiver: receiver,
                arguments: Array(forwarded.dropFirst()), result: result,
                canThrow: true, thrownResult: nil, dispatch: dispatch
            ))
        } else {
            body.append(directCall)
        }
        body.append(.returnValue(result))
        body.append(.endBlock)
        let stubSymbol = driver.callSupportLowerer.defaultStubSymbol(for: symbol)
        let stubParams = params + maskSymbols.map { KIRParameter(symbol: $0, type: types.longType) }
        // The stub's receiver is an ordinary KIR parameter. Register its
        // complete erased ABI so Any/T receivers and values are boxed at
        // source and serialized call sites, including constructors.
        func erased(_ type: TypeID) -> TypeID {
            if case .typeParam = types.kind(of: type) { return types.anyType }
            return type
        }
        symbols.setFunctionSignature(FunctionSignature(
            parameterTypes: stubParams.map { erased($0.type) },
            returnType: erased(signature.returnType),
            isSuspend: signature.isSuspend,
            canThrow: true
        ), for: stubSymbol)
        return arena.appendDecl(.function(KIRFunction(
            symbol: stubSymbol,
            name: interner.intern(interner.resolve(name) + "$default"),
            params: stubParams,
            returnType: signature.returnType,
            body: body.instructions,
            isSuspend: signature.isSuspend,
            isInline: base.base.flags.isInline
        )))
    }

    private func defaultMaskBit(
        _ index: Int,
        masks: [KIRExprID],
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let bit = Int64(1) << (index % DefaultArgumentMask.bitsPerWord)
        let bitMask = arena.appendExpr(.intLiteral(bit), type: types.longType)
        body.append(.constValue(result: bitMask, value: .intLiteral(bit)))
        let selected = arena.appendTemporary(type: types.longType)
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_bitwise_and"),
            arguments: [masks[index / DefaultArgumentMask.bitsPerWord], bitMask],
            result: selected,
            canThrow: false,
            thrownResult: nil
        ))
        return selected
    }

    private func emitCallableBody(
        base: KlibFunctionBase,
        symbol: SymbolID,
        params: [KIRParameter],
        returnType: TypeID,
        bodyIndex: Int32,
        isSuspend: Bool,
        isInline: Bool,
        isTailrec: Bool,
        captures: [(signatureIndex: Int, parameter: KIRParameter, isCell: Bool)] = []
    ) -> [KIRDeclID] {
        valueExprs = [:]
        mutableValues = []
        mutableCells = [:]
        returnableBlocks = [:]
        loopLabels = [:]
        returnTargetSignatureIndexes = [base.base.symbol.signatureIndex]
        thisExpr = nil
        currentCallableSymbol = symbol

        // Member extensions carry both a dispatch and an extension receiver —
        // the consumer signature only models one receiver, so there is no
        // second binding slot. Rare enough to diagnose rather than support.
        if base.dispatchReceiver != nil && base.extensionReceiver != nil {
            reportUnsupported("member-extension receiver in \(debugName(of: base.base.symbol))")
        }

        var body: KIRLoweringEmitContext = [.beginBlock]
        for capture in captures {
            let parameter = capture.parameter
            let value = arena.appendExpr(.symbolRef(parameter.symbol), type: parameter.type)
            body.append(.constValue(result: value, value: .symbolRef(parameter.symbol)))
            valueExprs[capture.signatureIndex] = value
            if capture.isCell { mutableCells[capture.signatureIndex] = value }
        }

        // Serialized `getValue`s on the dispatch/extension receiver parameter
        // resolve to the receiver binding — the same convention source
        // lowering establishes via `ctx.setImplicitReceiver`. Constructors
        // have no serialized dispatch receiver, but `this` still occupies
        // `params[0]` and is referenced implicitly by
        // `delegatingConstructorCall`/`instanceInitializerCall`.
        let isConstructor = symbols.symbol(symbol)?.kind == .constructor
        var paramIndex = captures.count
        if !params.isEmpty,
           isConstructor || base.dispatchReceiver != nil || base.extensionReceiver != nil
        {
            let receiverParam = params[paramIndex]
            let receiverExpr = arena.appendExpr(.symbolRef(receiverParam.symbol), type: receiverParam.type)
            body.append(.constValue(result: receiverExpr, value: .symbolRef(receiverParam.symbol)))
            for parameter in [base.dispatchReceiver, base.extensionReceiver].compactMap({ $0 }) {
                valueExprs[parameter.base.symbol.signatureIndex] = receiverExpr
            }
            thisExpr = receiverExpr
            paramIndex += 1
        }
        // Context parameters precede regular parameters in serialized call
        // order; both map onto `signature.parameterTypes` slots in sequence.
        for parameter in base.contextParameters + base.regularParameters {
            guard paramIndex < params.count else { break }
            let param = params[paramIndex]
            let expr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: expr, value: .symbolRef(param.symbol)))
            valueExprs[parameter.base.symbol.signatureIndex] = expr
            paramIndex += 1
        }

        if let statement = try? ir.body(bodyIndex, fileIndex: fileIndex) {
            translateStatement(statement, into: &body)
        } else {
            reportUnsupported("undecodable body for \(debugName(of: base.base.symbol))")
        }
        if body.instructions.last.map(Self.isTerminator) != true {
            // KIR convention: `<init>` returns `this` — the call site uses the
            // call result as the constructed object.
            if isConstructor, let thisExpr {
                body.append(.returnValue(thisExpr))
            } else {
                body.append(.returnUnit)
            }
        }
        body.append(.endBlock)

        let kirID = arena.appendDecl(.function(KIRFunction(
            symbol: symbol,
            name: symbols.symbol(symbol)?.name ?? interner.intern("<klib>"),
            params: params,
            returnType: returnType,
            body: body.instructions,
            isSuspend: isSuspend,
            isInline: isInline,
            isTailrec: isTailrec
        )))
        currentCallableSymbol = nil
        return [kirID]
    }

    /// Lift the serialized body into a capture-first function and reuse the
    /// same escaping-callable adapter as source lambdas. Rich references may
    /// also bind an explicit prefix of the invoke function's parameters.
    private func translateLambda(
        _ function: KlibFunction,
        boundValues: [KlibIrExpression],
        resultType: TypeID,
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        guard case .functionType(let functionType) = types.kind(of: resultType),
              !functionType.isSuspend, functionType.contextReceivers.isEmpty,
              functionType.params.count + (functionType.receiver == nil ? 0 : 1) <= 6,
              function.base.dispatchReceiver == nil, function.base.contextParameters.isEmpty,
              !function.base.base.flags.isSuspend,
              let bodyIndex = function.base.bodyIndex else {
            reportUnsupported("lambda signature or suspend/context lambda")
            return errorExpr(type: resultType, into: &body)
        }
        let serializedParameters = [function.base.extensionReceiver].compactMap { $0 }
            + function.base.regularParameters
        let invocationCount = functionType.params.count + (functionType.receiver == nil ? 0 : 1)
        guard serializedParameters.count == boundValues.count + invocationCount else {
            reportUnsupported("lambda bound/invocation parameter count")
            return errorExpr(type: resultType, into: &body)
        }
        // Bound expressions execute once, in their serialized order.
        let boundArguments = boundValues.map { translateExpression($0, into: &body) }
        let key = KlibSignatureKey(fileIndex: fileIndex, signatureIndex: function.base.base.symbol.signatureIndex)
        let lifted: LiftedLambda
        if let existing = liftedLambdas[key] {
            lifted = existing
        } else {
            let indices: [Int]
            do {
                indices = try KlibLambdaCaptureAnalysis.captures(
                    of: function, module: ir, fileIndex: fileIndex, available: Set(valueExprs.keys)
                )
            } catch {
                reportUnsupported("undecodable lambda captures: \(error)")
                return errorExpr(type: resultType, into: &body)
            }
            let captures = indices.map { (index: $0, isCell: mutableValues.contains($0) || mutableCells[$0] != nil) }
            var captureParameters: [(signatureIndex: Int, parameter: KIRParameter, isCell: Bool)] = []
            for capture in captures {
                let value = capture.isCell ? ensureMutableCell(capture.index, into: &body) : valueExprs[capture.index]
                guard let value else {
                    reportUnsupported("unbound lambda capture")
                    return errorExpr(type: resultType, into: &body)
                }
                captureParameters.append((capture.index, KIRParameter(
                    symbol: driver.ctx.allocateSyntheticGeneratedSymbol(),
                    type: arena.exprType(value) ?? types.anyType
                ), capture.isCell))
            }
            var parameters = captureParameters.map(\.parameter)
            for parameter in serializedParameters {
                guard let type = decodeType(parameter.nameType.typeIndex) else {
                    reportUnsupported("lambda parameter type")
                    return errorExpr(type: resultType, into: &body)
                }
                parameters.append(KIRParameter(symbol: driver.ctx.allocateSyntheticGeneratedSymbol(), type: type))
            }
            guard let returnType = decodeType(function.base.nameType.typeIndex) else {
                reportUnsupported("lambda return type")
                return errorExpr(type: resultType, into: &body)
            }
            let name = interner.intern("__klib_lambda_\(driver.ctx.allocateSyntheticGeneratedSymbol().rawValue)")
            let symbol = symbols.define(
                kind: .function, name: name, fqName: [name], declSite: nil,
                visibility: .private, flags: [.synthetic]
            )
            func erased(_ type: TypeID) -> TypeID {
                if case .typeParam = types.kind(of: type) { return types.anyType }
                return type
            }
            symbols.setFunctionSignature(FunctionSignature(
                parameterTypes: parameters.map { erased($0.type) }, returnType: erased(returnType), canThrow: true
            ), for: symbol)
            lifted = LiftedLambda(symbol: symbol, name: name, returnType: returnType, captures: captures)
            liftedLambdas[key] = lifted

            let savedValues = valueExprs
            let savedMutableValues = mutableValues
            let savedCells = mutableCells
            let savedReturns = returnTargetSignatureIndexes
            let savedBlocks = returnableBlocks
            let savedLoops = loopLabels
            let savedThis = thisExpr
            let savedCallable = currentCallableSymbol
            defer {
                valueExprs = savedValues
                mutableValues = savedMutableValues
                mutableCells = savedCells
                returnTargetSignatureIndexes = savedReturns
                returnableBlocks = savedBlocks
                loopLabels = savedLoops
                thisExpr = savedThis
                currentCallableSymbol = savedCallable
            }
            for declaration in emitCallableBody(
                base: function.base, symbol: symbol, params: parameters, returnType: returnType,
                bodyIndex: bodyIndex, isSuspend: false, isInline: false, isTailrec: false,
                captures: captureParameters
            ) {
                driver.ctx.appendGeneratedCallableDecl(declaration)
            }
        }
        let captureArguments = lifted.captures.compactMap { capture in
            capture.isCell ? ensureMutableCell(capture.index, into: &body) : valueExprs[capture.index]
        } + boundArguments
        guard captureArguments.count == lifted.captures.count + boundArguments.count,
              let callable = driver.lambdaLowerer.materializeEscapingCallableValue(
                  lambdaSymbol: lifted.symbol, lambdaName: lifted.name, lambdaReturnType: lifted.returnType,
                  functionType: functionType, captureArguments: captureArguments,
                  sema: sema, arena: arena, interner: interner, instructions: &body.instructions
              ) else {
            reportUnsupported("lambda callable materialization")
            return errorExpr(type: resultType, into: &body)
        }
        return callable
    }

    private func ensureMutableCell(_ index: Int, into body: inout KIRLoweringEmitContext) -> KIRExprID? {
        if let cell = mutableCells[index] { return cell }
        guard let value = valueExprs[index] else { return nil }
        let count = appendIntegerConstant(1, into: &body)
        let cell = arena.appendTemporary(type: types.anyType)
        body.append(.call(
            symbol: nil, callee: interner.intern("kk_array_new"), arguments: [count],
            result: cell, canThrow: false, thrownResult: nil
        ))
        storeCell(value, cell: cell, into: &body)
        mutableCells[index] = cell
        return cell
    }

    private func loadCell(_ cell: KIRExprID, type: TypeID, into body: inout KIRLoweringEmitContext) -> KIRExprID {
        let zero = appendIntegerConstant(0, into: &body)
        let value = arena.appendTemporary(type: type)
        body.append(.call(
            symbol: nil, callee: interner.intern("kk_array_get_inbounds"), arguments: [cell, zero],
            result: value, canThrow: false, thrownResult: nil
        ))
        return value
    }

    private func storeCell(_ value: KIRExprID, cell: KIRExprID, into body: inout KIRLoweringEmitContext) {
        let zero = appendIntegerConstant(0, into: &body)
        let result = arena.appendTemporary(type: types.anyType)
        body.append(.call(
            symbol: nil, callee: interner.intern("kk_array_set"), arguments: [cell, zero, value],
            result: result, canThrow: false, thrownResult: nil
        ))
    }

    private static func isTerminator(_ instruction: KIRInstruction) -> Bool {
        switch instruction {
        case .returnUnit, .returnValue, .returnIfEqual, .rethrow, .nonLocalReturn:
            true
        default:
            false
        }
    }

    private func emitPropertyAccessors(_ property: KlibProperty) -> [KIRDeclID] {
        guard let propertySymbol = symbol(for: property.base.symbol) else { return [] }
        var declIDs: [KIRDeclID] = []
        if let getter = property.getter {
            declIDs.append(contentsOf: emitAccessor(
                getter, accessor: .getter, propertySymbol: propertySymbol
            ))
        }
        if let setter = property.setter {
            declIDs.append(contentsOf: emitAccessor(
                setter, accessor: .setter, propertySymbol: propertySymbol
            ))
        }
        return declIDs
    }


    private func emitClass(_ klass: KlibClass) -> [KIRDeclID] {
        guard let classSymbol = symbol(for: klass.base.symbol) else { return [] }

        // Pre-collect init data so `instanceInitializerCall` inside any ctor
        // expands field stores + anonymous-init bodies in declaration order.
        var initInfo = ClassInitInfo(fileIndex: fileIndex)
        for member in klass.declarations {
            switch member {
            case .property(let property):
                if let field = property.backingField,
                   let initializerIndex = field.initializerIndex,
                   let fieldSymbol = symbol(for: field.base.symbol)
                {
                    initInfo.fieldInitializers.append(
                        (
                            field: fieldSymbol,
                            bodyIndex: initializerIndex,
                            typeIndex: field.nameType.typeIndex
                        )
                    )
                }
            case .anonymousInit(let initializer):
                initInfo.anonymousInitBodyIndices.append(initializer.bodyIndex)
            default:
                break
            }
        }
        classInitBySymbol[classSymbol] = initInfo

        var memberDeclIDs: [KIRDeclID] = []
        for member in klass.declarations {
            switch member {
            case .function(let function):
                memberDeclIDs.append(contentsOf: emitCallable(function.base))
            case .constructor(let constructor):
                memberDeclIDs.append(contentsOf: emitCallable(constructor.base))
            case .property(let property):
                memberDeclIDs.append(contentsOf: emitPropertyAccessors(property))
            case .class(let nested):
                memberDeclIDs.append(contentsOf: emitClass(nested))
            case .enumEntry:
                // Ordinal slot + init are synthesized by the enum pass.
                break
            case .field(let field) where field.base.flags.isStaticField:
                emitStaticField(field)
            default:
                break
            }
        }

        var declIDs = [arena.appendDecl(.nominalType(KIRNominalType(
            symbol: classSymbol, memberDecls: memberDeclIDs
        )))]
        declIDs.append(contentsOf: memberDeclIDs)

        let classKind = klass.base.flags.classKind
        if classKind == .object || classKind == .companionObject {
            declIDs.append(contentsOf: emitObjectSingleton(
                klass: klass, objectSymbol: classSymbol
            ))
        }
        // Enum classes need no special-casing here: the `.nominalType` decl
        // above is picked up by DataEnumSealedSynthesisPass, which emits the
        // ordinal entry slots, `__enum_static_init`, values/valueOf/entries
        // and helper functions exactly as it does for source enums.
        return declIDs
    }


    private func emitTopLevelField(_ field: KlibField) {
        guard let fieldSymbol = symbol(for: field.base.symbol) else { return }
        emitGlobal(for: field.base.symbol, typeIndex: field.nameType.typeIndex)
        guard let initializerIndex = field.initializerIndex,
              let initExpr = try? ir.expressionBody(initializerIndex, fileIndex: fileIndex)
        else { return }
        var initContext = KIRLoweringEmitContext()
        let value = translateExpression(initExpr, into: &initContext)
        initContext.append(.storeGlobal(value: value, symbol: fieldSymbol))
        topLevelInit.appendRelocatingLabels(contentsOf: initContext)
    }

    /// Static (companion-object-scoped) fields — stored in globals too.
    private func emitStaticField(_ field: KlibField) {
        emitTopLevelField(field)
    }

    /// Creates the global slot for a declaration owned by *this* klib module.
    /// Symbols resolved through another module's records (`resolveExternalSymbol`)
    /// already have storage in their own artifact — creating a local slot for
    /// them would shadow the extern reference with an uninitialized variable.
    private func emitGlobal(for ref: KlibSymbolRef, typeIndex: Int32?) {
        let key = KlibSignatureKey(fileIndex: fileIndex, signatureIndex: ref.signatureIndex)
        guard let globalSymbol = loaded.symbolBySignature[key],
              !emittedGlobals.contains(globalSymbol)
        else { return }
        emittedGlobals.insert(globalSymbol)
        let type = typeIndex.flatMap { decodeType($0) }
            ?? symbols.propertyType(for: globalSymbol)
            ?? types.anyType
        let isThreadLocal = symbols.annotations(for: globalSymbol).contains {
            KnownCompilerAnnotation.nativeThreadLocal.matches($0.annotationFQName)
        }
        _ = arena.appendDecl(.global(KIRGlobal(
            symbol: globalSymbol, type: type, isThreadLocal: isThreadLocal
        )))
        // `.importedLibrary`-flagged globals normally resolve to extern
        // storage owned by a precompiled `.kklib` object. `.klib` modules
        // carry no precompiled object, so this compilation owns the slot.
        symbols.markKlibDefinedGlobal(globalSymbol)
    }


    /// Mirrors `synthesizeObjectInitializer`/`synthesizeObjectLazyInit` for an
    /// imported object: an eager allocation+registration function invoked from
    /// module init, and a `$initialized`-guarded lazy body that delegates to
    /// the object's own `<init>` (which performs the super constructor call,
    /// field stores and init blocks through its serialized body).
    private func emitObjectSingleton(klass: KlibClass, objectSymbol: SymbolID) -> [KIRDeclID] {
        let objectType = types.make(.classType(ClassType(
            classSymbol: objectSymbol, args: [], nullability: .nonNull
        )))
        // The global slot may already exist — `translateGetObject` creates it
        // when a body in an earlier file references this object. Init
        // synthesis must still run once per object.
        if emittedGlobals.insert(objectSymbol).inserted {
            _ = arena.appendDecl(.global(KIRGlobal(symbol: objectSymbol, type: objectType)))
            symbols.markKlibDefinedGlobal(objectSymbol)
        }
        guard emittedObjectInits.insert(objectSymbol).inserted else { return [] }

        var declIDs: [KIRDeclID] = []

        let eagerSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let eagerName = interner.intern("__klib_object_init_\(objectSymbol.rawValue)")
        var eager: KIRLoweringEmitContext = [.beginBlock]
        let (allocated, _) = emitObjectAllocation(
            classSymbol: objectSymbol, objectType: objectType, into: &eager
        )
        eager.append(.storeGlobal(value: allocated, symbol: objectSymbol))
        eager.append(.returnUnit)
        eager.append(.endBlock)
        declIDs.append(arena.appendDecl(.function(KIRFunction(
            symbol: eagerSymbol, name: eagerName, params: [],
            returnType: types.unitType, body: eager.instructions, isSuspend: false, isInline: false
        ))))
        let eagerResult = arena.appendTemporary(type: types.unitType)
        eagerObjectInit.append(.call(
            symbol: eagerSymbol, callee: eagerName, arguments: [],
            result: eagerResult, canThrow: false, thrownResult: nil
        ))

        let flagName = interner.intern("$initialized")
        let flagSymbol = symbols.define(
            kind: .field, name: flagName,
            fqName: (symbols.symbol(objectSymbol)?.fqName ?? []) + [flagName],
            declSite: nil, visibility: .private, flags: [.synthetic]
        )
        _ = arena.appendDecl(.global(KIRGlobal(symbol: flagSymbol, type: types.booleanType)))

        let lazySymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let lazyName = interner.intern("__klib_object_lazy_init_\(objectSymbol.rawValue)")
        var lazy: KIRLoweringEmitContext = [.beginBlock]
        let handle = arena.appendTemporary(type: objectType)
        lazy.append(.loadGlobal(result: handle, symbol: objectSymbol))
        let boolType = types.booleanType
        let trueExpr = arena.appendExpr(.boolLiteral(true), type: boolType)
        lazy.append(.constValue(result: trueExpr, value: .boolLiteral(true)))
        let flagLoad = arena.appendTemporary(type: boolType)
        lazy.append(.loadGlobal(result: flagLoad, symbol: flagSymbol))
        let done = driver.ctx.makeLoopLabel()
        lazy.append(.jumpIfEqual(lhs: flagLoad, rhs: trueExpr, target: done))
        lazy.append(.storeGlobal(value: trueExpr, symbol: flagSymbol))
        if let ctorSymbol = primaryConstructorSymbol(of: klass),
           symbols.functionSignature(for: ctorSymbol)?.parameterTypes.isEmpty == true
        {
            let initResult = arena.appendTemporary(type: types.unitType)
            lazy.append(.call(
                symbol: ctorSymbol, callee: interner.intern("<init>"),
                arguments: [handle], result: initResult,
                canThrow: true, thrownResult: nil
            ))
        } else {
            reportUnsupported("object without a no-arg primary constructor")
        }
        lazy.append(.label(done))
        lazy.append(.returnUnit)
        lazy.append(.endBlock)
        declIDs.append(arena.appendDecl(.function(KIRFunction(
            symbol: lazySymbol, name: lazyName, params: [],
            returnType: types.unitType, body: lazy.instructions, isSuspend: false, isInline: false
        ))))
        driver.ctx.registerObjectLazyInit(
            for: objectSymbol,
            ensureInitSymbol: lazySymbol,
            ensureInitName: lazyName,
            flagSymbol: flagSymbol
        )
        return declIDs
    }

    private func primaryConstructorSymbol(of klass: KlibClass) -> SymbolID? {
        for member in klass.declarations {
            guard case .constructor(let ctor) = member,
                  ctor.base.base.flags.isPrimaryConstructor
            else { continue }
            return symbol(for: ctor.base.base.symbol)
        }
        return nil
    }


    private func translateStatement(
        _ statement: KlibIrStatement,
        into body: inout KIRLoweringEmitContext
    ) {
        switch statement.kind {
        case .blockBody(let statements):
            for child in statements { translateStatement(child, into: &body) }
        case .expression(let expression):
            _ = translateExpression(expression, into: &body)
        case .declaration(let declaration):
            translateLocalDeclaration(declaration, into: &body)
        case .branch, .catch:
            // Only meaningful inside `when`/`try`, which consume them directly.
            reportUnsupported("stray branch/catch statement")
        case .syntheticBody:
            // Enum `values`/`valueOf`/`entries` synthetic bodies — those
            // functions are re-synthesized by import, not emitted here.
            break
        }
    }

    private func translateLocalDeclaration(
        _ declaration: KlibIrDeclaration,
        into body: inout KIRLoweringEmitContext
    ) {
        switch declaration {
        case .variable(let variable):
            let declaredType = decodeType(variable.nameType.typeIndex) ?? types.anyType
            let slot = arena.appendTemporary(type: declaredType)
            let index = variable.base.symbol.signatureIndex
            valueExprs[index] = slot
            if variable.base.flags.isLocalVar {
                mutableValues.insert(index)
                // Allocate at the declaration so a lambda created on only one
                // control-flow path cannot leave another path without a cell.
                let seed = deferredLocalCaptureCellSeedValue(
                    for: declaredType, sema: sema, arena: arena, instructions: &body.instructions
                )
                body.append(.copy(from: seed, to: slot))
                _ = ensureMutableCell(index, into: &body)
            }
            if let initializer = variable.initializer {
                let value = translateExpression(initializer, into: &body)
                if let cell = mutableCells[index] {
                    storeCell(value, cell: cell, into: &body)
                } else {
                    body.append(.copy(from: value, to: slot))
                }
            }
        case .localDelegatedProperty(let delegated):
            reportUnsupported("local delegated property")
            if let delegate = delegated.delegate {
                translateLocalDeclaration(.variable(delegate), into: &body)
            }
        case .function(let function):
            reportUnsupported("local function \(debugName(of: function.base.base.symbol))")
        case .class(let klass):
            reportUnsupported("local class \(debugName(of: klass.base.symbol))")
        default:
            reportUnsupported("local declaration")
        }
    }


    @discardableResult
    private func translateExpression(
        _ expression: KlibIrExpression,
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let resultType = decodeType(expression.typeIndex) ?? types.anyType
        switch expression.kind {
        case .constNull:
            let expr = arena.appendExpr(.null, type: resultType)
            body.append(.constValue(result: expr, value: .null))
            return expr
        case .constBool(let value):
            let expr = arena.appendExpr(.boolLiteral(value), type: resultType)
            body.append(.constValue(result: expr, value: .boolLiteral(value)))
            return expr
        case .constChar(let value):
            let bits = UInt32(bitPattern: value)
            let expr = arena.appendExpr(.charLiteral(bits), type: resultType)
            body.append(.constValue(result: expr, value: .charLiteral(bits)))
            return expr
        case .constByte(let value), .constShort(let value), .constInt(let value):
            let expr = arena.appendExpr(.intLiteral(Int64(value)), type: resultType)
            body.append(.constValue(result: expr, value: .intLiteral(Int64(value))))
            return expr
        case .constLong(let value):
            let expr = arena.appendExpr(.longLiteral(value), type: resultType)
            body.append(.constValue(result: expr, value: .longLiteral(value)))
            return expr
        case .constFloat(let bits):
            let value = Double(Float(bitPattern: bits))
            let expr = arena.appendExpr(.floatLiteral(value), type: resultType)
            body.append(.constValue(result: expr, value: .floatLiteral(value)))
            return expr
        case .constDouble(let bits):
            let value = Double(bitPattern: bits)
            let expr = arena.appendExpr(.doubleLiteral(value), type: resultType)
            body.append(.constValue(result: expr, value: .doubleLiteral(value)))
            return expr
        case .constString(let index):
            let text: String
            do {
                text = try ir.stringLiteral(index, fileIndex: fileIndex)
            } catch {
                reportUnsupported("invalid string literal: \(error)")
                return errorExpr(type: resultType, into: &body)
            }
            let interned = interner.intern(text)
            let expr = arena.appendExpr(.stringLiteral(interned), type: resultType)
            body.append(.constValue(result: expr, value: .stringLiteral(interned)))
            return expr

        case .getValue(let ref, _):
            if let cell = mutableCells[ref.signatureIndex] {
                return loadCell(cell, type: resultType, into: &body)
            }
            if let bound = valueExprs[ref.signatureIndex] {
                return bound
            }
            if ref.kind == .receiverParameter, let thisExpr {
                // Some Klib producers encode the dispatch receiver as a
                // scoped receiver local rather than the declaration's
                // signature-table parameter. It still denotes this instance.
                return thisExpr
            }
            if let symbol = symbol(for: ref) {
                let expr = arena.appendExpr(.symbolRef(symbol), type: resultType)
                body.append(.constValue(result: expr, value: .symbolRef(symbol)))
                valueExprs[ref.signatureIndex] = expr
                return expr
            }
            reportUnsupported("unbound getValue \(debugName(of: ref))")
            return errorExpr(type: resultType, into: &body)

        case .setValue(let ref, let value, _):
            let lowered = translateExpression(value, into: &body)
            if let cell = mutableCells[ref.signatureIndex] {
                storeCell(lowered, cell: cell, into: &body)
                return lowered
            }
            guard let target = valueExprs[ref.signatureIndex] else {
                reportUnsupported("unbound setValue \(debugName(of: ref))")
                return lowered
            }
            body.append(.copy(from: lowered, to: target))
            return lowered

        case .call(let ref, let memberAccess, let superRef, _):
            return translateCall(
                ref, memberAccess: memberAccess, superRef: superRef,
                resultType: resultType, into: &body
            )

        case .constructorCall(let ref, _, let memberAccess, _),
             .enumConstructorCall(let ref, let memberAccess):
            return translateConstructorCall(
                ref, memberAccess: memberAccess, resultType: resultType, into: &body
            )

        case .delegatingConstructorCall(let ref, let memberAccess):
            translateDelegatingConstructorCall(ref, memberAccess: memberAccess, into: &body)
            return unitExpr(into: &body)

        case .instanceInitializerCall(let ref):
            emitInstanceInitializers(classSymbol: symbol(for: ref), into: &body)
            return unitExpr(into: &body)

        case .block(let statements, _), .composite(let statements, _):
            return translateStatementSequence(statements, into: &body)

        case .returnableBlock(let ref, let statements, _):
            return translateReturnableBlock(
                ref, statements: statements, resultType: resultType, into: &body
            )

        case .inlinedFunctionBlock(_, _, _, let statements, _, _, _):
            return translateStatementSequence(statements, into: &body)

        case .return(let target, let value):
            let lowered = translateExpression(value, into: &body)
            if let blockTarget = returnableBlocks[target.signatureIndex] {
                if let result = blockTarget.result {
                    body.append(.copy(from: lowered, to: result))
                }
                body.append(.jump(blockTarget.label))
            } else if returnTargetSignatureIndexes.contains(target.signatureIndex) {
                if decodeType(value.typeIndex) == types.unitType {
                    body.append(.returnUnit)
                } else {
                    body.append(.returnValue(lowered))
                }
            } else {
                // Return through an inlined lambda boundary.
                body.append(.nonLocalReturn(lowered))
            }
            return lowered

        case .when(let branches, _):
            return translateWhen(branches, resultType: resultType, into: &body)

        case .while(let loop):
            return translateLoop(loop, isDoWhile: false, into: &body)
        case .doWhile(let loop):
            return translateLoop(loop, isDoWhile: true, into: &body)
        case .break(let loopId, _):
            if let labels = loopLabels[loopId] {
                body.append(.jump(labels.breakLabel))
            } else {
                reportUnsupported("break to unknown loop \(loopId)")
            }
            return unitExpr(into: &body)
        case .continue(let loopId, _):
            if let labels = loopLabels[loopId] {
                body.append(.jump(labels.continueLabel))
            } else {
                reportUnsupported("continue to unknown loop \(loopId)")
            }
            return unitExpr(into: &body)

        case .typeOp(let op, let operandType, let argument):
            return translateTypeOp(
                op, operandType: operandType, argument: argument,
                resultType: resultType, into: &body
            )

        case .getField(let access, _):
            return translateGetField(access, resultType: resultType, into: &body)
        case .setField(let access, let value, _):
            return translateSetField(access, value: value, into: &body)

        case .getObject(let ref):
            return translateGetObject(ref, resultType: resultType, into: &body)
        case .getEnumValue(let ref):
            guard let entrySymbol = symbol(for: ref) else {
                reportUnsupported("unresolvable enum entry \(debugName(of: ref))")
                return errorExpr(type: resultType, into: &body)
            }
            // Source convention (`referenceStdlibEnumEntry`): an enum entry
            // reference is a `.symbolRef` on its ordinal slot — boxing into a
            // heap object happens at Any boundaries via `kk_enum_box_ordinal`.
            let expr = arena.appendExpr(.symbolRef(entrySymbol), type: resultType)
            body.append(.constValue(result: expr, value: .symbolRef(entrySymbol)))
            return expr

        case .stringConcat(let arguments):
            return translateStringConcat(arguments, into: &body)

        case .throw(let value):
            let thrown = translateExpression(value, into: &body)
            body.append(.rethrow(value: thrown))
            return thrown

        case .try(let result, let catches, let finallyBody):
            // KIR exception routing (`thrownTarget` + finally guards) is a
            // dedicated lowering in source. Keep the value path and diagnose
            // the missing catch/finally semantics for now.
            if !catches.isEmpty || finallyBody != nil {
                reportUnsupported("try/catch/finally")
            }
            return translateExpression(result, into: &body)

        case .vararg(_, let elements):
            return translateVararg(
                elements: elements,
                resultType: resultType, into: &body
            )

        case .functionExpression(let function, _):
            return translateLambda(function, boundValues: [], resultType: resultType, into: &body)

        case .richFunctionReference(let boundValues, let reflectionTarget, _, let function, _, _):
            guard reflectionTarget == nil else {
                reportUnsupported("reflective function reference")
                return errorExpr(type: resultType, into: &body)
            }
            return translateLambda(function, boundValues: boundValues, resultType: resultType, into: &body)

        case .getClass, .classReference, .functionReference, .propertyReference,
             .richPropertyReference, .localDelegatedPropertyReference:
            reportUnsupported("callable/class reference")
            return errorExpr(type: resultType, into: &body)

        case .dynamicMember, .dynamicOperator:
            reportUnsupported("dynamic member/operator")
            return errorExpr(type: resultType, into: &body)

        case .errorExpression, .errorCallExpression, .missingExpression:
            reportUnsupported("error expression")
            return errorExpr(type: resultType, into: &body)
        }
    }

    private func translateStatementSequence(
        _ statements: [KlibIrStatement],
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        var lastValue: KIRExprID?
        for statement in statements {
            if case .expression(let expression) = statement.kind {
                lastValue = translateExpression(expression, into: &body)
            } else {
                translateStatement(statement, into: &body)
                lastValue = nil
            }
        }
        return lastValue ?? unitExpr(into: &body)
    }


    /// Splits a serialized member access into receiver and regular-argument
    /// lists. Kotlin 2.4 folds receivers into `arguments` (dispatch receiver
    /// first, then extension receiver, then value parameters); pre-2.4
    /// payloads carry them in dedicated fields. `nil` entries mark
    /// default-argument slots — Kotlin resolves them through the callee's
    /// `$default` stub, synthesized from the callee's serialized defaults.
    private func splitArguments(
        _ access: KlibMemberAccess,
        signature: FunctionSignature?
    ) -> (receivers: [KlibIrExpression], regular: [KlibIrExpression?]) {
        if !access.arguments.isEmpty || !access.argumentsPre240.isEmpty {
            let arguments = access.arguments.isEmpty
                ? access.argumentsPre240
                : access.arguments.map { expression -> KlibIrExpression? in
                    if case .missingExpression = expression.kind { return nil }
                    return expression
                }
            let regularCount = signature?.parameterTypes.count ?? 0
            let receiverCount = max(0, arguments.count - regularCount)
            return (
                receivers: arguments.prefix(receiverCount).compactMap { $0 },
                regular: Array(arguments.dropFirst(receiverCount))
            )
        }
        let receivers = [access.dispatchReceiver, access.extensionReceiver].compactMap { $0 }
        let regular = access.regularArguments.isEmpty
            ? access.argumentsPre240
            : access.regularArguments
        return (receivers: receivers, regular: regular)
    }

    private func lowerArguments(
        _ arguments: [KlibIrExpression?],
        signature: FunctionSignature?,
        into body: inout KIRLoweringEmitContext
    ) -> (values: [KIRExprID], masks: [Int64]) {
        var values: [KIRExprID] = []
        var mask = DefaultArgumentMask(parameterCount: signature?.parameterTypes.count ?? arguments.count)
        for (index, argument) in arguments.enumerated() {
            if let argument {
                values.append(translateExpression(argument, into: &body))
                continue
            }
            guard let signature, index < signature.parameterTypes.count else {
                reportUnsupported("missing argument without a parameter")
                continue
            }
            let parameterType = signature.parameterTypes[index]
            if index < signature.valueParameterHasDefaultValues.count,
               signature.valueParameterHasDefaultValues[index] {
                mask.insert(index)
                let placeholder = arena.appendExpr(.intLiteral(0), type: parameterType)
                body.append(.constValue(result: placeholder, value: .intLiteral(0)))
                values.append(placeholder)
            } else if index < signature.valueParameterIsVararg.count, signature.valueParameterIsVararg[index] {
                let arrayType = primitiveVarargArrayType(elementType: parameterType, sema: sema, interner: interner)
                    ?? referenceVarargArrayType(elementType: parameterType, sema: sema, interner: interner)
                    ?? parameterType
                values.append(translateVararg(elements: [], resultType: arrayType, into: &body))
            } else {
                reportUnsupported("missing argument for parameter \(index)")
            }
        }
        return (values, mask.stubWords)
    }

    private func appendIntegerConstant(_ mask: Int64, into body: inout KIRLoweringEmitContext) -> KIRExprID {
        let expression = arena.appendExpr(.intLiteral(mask), type: types.intType)
        body.append(.constValue(result: expression, value: .intLiteral(mask)))
        return expression
    }

    private func appendDefaultMaskConstants(_ masks: [Int64], into body: inout KIRLoweringEmitContext) -> [KIRExprID] {
        masks.map { value in
            let expression = arena.appendExpr(.intLiteral(value), type: types.longType)
            body.append(.constValue(result: expression, value: .intLiteral(value)))
            return expression
        }
    }

    private func translateCall(
        _ ref: KlibSymbolRef,
        memberAccess: KlibMemberAccess,
        superRef: KlibSymbolRef?,
        resultType: TypeID,
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        // Intrinsic member calls on primitives: the callee has no body in any
        // artifact — source lowering maps the same member onto `kk_op_*`.
        if let intrinsic = intrinsicCall(
            ref, memberAccess: memberAccess, resultType: resultType, into: &body
        ) {
            return intrinsic
        }

        guard let calleeSymbol = symbol(for: ref) else {
            reportUnsupported("unresolvable call \(debugName(of: ref))")
            return errorExpr(type: resultType, into: &body)
        }
        let signature = symbols.functionSignature(for: calleeSymbol)
        let split = splitArguments(memberAccess, signature: signature)

        var loweredReceivers: [KIRExprID] = []
        for receiver in split.receivers {
            loweredReceivers.append(translateExpression(receiver, into: &body))
        }
        let lowered = lowerArguments(split.regular, signature: signature, into: &body)
        let loweredArguments = lowered.values

        // The expression type includes the call site's generic substitution.
        let result = arena.appendTemporary(type: resultType)
        let calleeName = self.calleeName(for: calleeSymbol, ref: ref)

        if lowered.masks.contains(where: { $0 != 0 }) {
            guard superRef == nil else {
                reportUnsupported("super call with omitted default arguments")
                return errorExpr(type: resultType, into: &body)
            }
            let owner = driver.callSupportLowerer.defaultStubOwnerSymbol(for: calleeSymbol, sema: sema)
            let masks = appendDefaultMaskConstants(lowered.masks, into: &body)
            body.append(.call(
                symbol: driver.callSupportLowerer.defaultStubSymbol(for: owner),
                callee: interner.intern(interner.resolve(calleeName) + "$default"),
                arguments: loweredReceivers + loweredArguments + masks,
                result: result, canThrow: true, thrownResult: nil
            ))
        } else if superRef == nil, !loweredReceivers.isEmpty,
           let dispatch = resolveVirtualDispatchKind(
               callee: calleeSymbol,
               receiverTypeID: arena.exprType(loweredReceivers[0]),
               sema: sema, interner: interner
           )
        {
            body.append(.virtualCall(
                symbol: calleeSymbol, callee: calleeName,
                receiver: loweredReceivers[0],
                arguments: Array(loweredReceivers.dropFirst()) + loweredArguments,
                result: result, canThrow: true, thrownResult: nil,
                dispatch: dispatch
            ))
        } else {
            body.append(.call(
                symbol: calleeSymbol, callee: calleeName,
                arguments: loweredReceivers + loweredArguments,
                result: result, canThrow: true, thrownResult: nil,
                isSuperCall: superRef != nil,
                qualifiedSuperType: superRef.flatMap { symbol(for: $0) }
            ))
        }
        return result
    }

    private func translateConstructorCall(
        _ ref: KlibSymbolRef,
        memberAccess: KlibMemberAccess,
        resultType: TypeID,
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        if resolvedFqName(of: ref) == "kotlin.internal.SharedVariableBox.<init>" {
            let values = intrinsicArguments(memberAccess, into: &body)
            guard values.count == 1 else {
                reportUnsupported("shared-variable box constructor arguments")
                return errorExpr(type: resultType, into: &body)
            }
            let count = appendIntegerConstant(1, into: &body)
            let cell = arena.appendTemporary(type: types.anyType)
            body.append(.call(
                symbol: nil, callee: interner.intern("kk_array_new"), arguments: [count],
                result: cell, canThrow: false, thrownResult: nil
            ))
            storeCell(values[0], cell: cell, into: &body)
            return cell
        }
        guard let ctorSymbol = symbol(for: ref),
              let classSymbol = symbols.parentSymbol(for: ctorSymbol)
        else {
            reportUnsupported("unresolvable constructor \(debugName(of: ref))")
            return errorExpr(type: resultType, into: &body)
        }
        let signature = symbols.functionSignature(for: ctorSymbol)
        let objectType = signature?.receiverType ?? resultType

        // The KIR convention allocates the instance at the call site and
        // passes it as `this` (arg 0) — same as source ctor calls.
        let (allocated, _) = emitObjectAllocation(
            classSymbol: classSymbol, objectType: objectType, into: &body
        )
        let split = splitArguments(memberAccess, signature: signature)
        let lowered = lowerArguments(split.regular, signature: signature, into: &body)
        var arguments: [KIRExprID] = [allocated] + lowered.values
        let hasOmittedDefaults = lowered.masks.contains(where: { $0 != 0 })
        if hasOmittedDefaults { arguments.append(contentsOf: appendDefaultMaskConstants(lowered.masks, into: &body)) }
        let initResult = arena.appendTemporary(type: types.unitType)
        body.append(.call(
            symbol: hasOmittedDefaults ? driver.callSupportLowerer.defaultStubSymbol(for: ctorSymbol) : ctorSymbol,
            callee: interner.intern(hasOmittedDefaults ? "<init>$default" : "<init>"),
            arguments: arguments, result: initResult,
            canThrow: true, thrownResult: nil
        ))
        return allocated
    }

    private func translateDelegatingConstructorCall(
        _ ref: KlibSymbolRef,
        memberAccess: KlibMemberAccess,
        into body: inout KIRLoweringEmitContext
    ) {
        guard let ctorSymbol = symbol(for: ref), let thisExpr else { return }
        if let currentCallableSymbol,
           symbols.symbol(currentCallableSymbol)?.kind == .constructor,
           let currentClass = symbols.parentSymbol(for: currentCallableSymbol),
           symbols.parentSymbol(for: ctorSymbol) != currentClass
        {
            emitNullFieldInitializers(classSymbol: currentClass, receiver: thisExpr, into: &body)
        }
        // `kotlin.Any.<init>` is the compiler-provided empty constructor —
        // allocation already happened at the call site; no call is emitted.
        if let ctorInfo = symbols.symbol(ctorSymbol),
           ctorInfo.flags.contains(.synthetic),
           symbols.parentSymbol(for: ctorSymbol) == types.anyClassSymbol
        {
            return
        }
        let signature = symbols.functionSignature(for: ctorSymbol)
        let split = splitArguments(memberAccess, signature: signature)
        let lowered = lowerArguments(split.regular, signature: signature, into: &body)
        var arguments: [KIRExprID] = [thisExpr] + lowered.values
        let hasOmittedDefaults = lowered.masks.contains(where: { $0 != 0 })
        if hasOmittedDefaults { arguments.append(contentsOf: appendDefaultMaskConstants(lowered.masks, into: &body)) }
        let result = arena.appendTemporary(type: types.unitType)
        body.append(.call(
            symbol: hasOmittedDefaults ? driver.callSupportLowerer.defaultStubSymbol(for: ctorSymbol) : ctorSymbol,
            callee: interner.intern(hasOmittedDefaults ? "<init>$default" : "<init>"),
            arguments: arguments, result: result,
            canThrow: true, thrownResult: nil
        ))
    }

    /// Seeds nullable `null` defaults before a serialized constructor invokes
    /// its superclass. Its later `instanceInitializerCall` omits the same
    /// default stores so virtual writes from super init remain intact.
    private func emitNullFieldInitializers(
        classSymbol: SymbolID,
        receiver: KIRExprID,
        into body: inout KIRLoweringEmitContext
    ) {
        guard let initInfo = classInitBySymbol[classSymbol] else { return }
        let savedFileIndex = fileIndex
        fileIndex = initInfo.fileIndex
        defer { fileIndex = savedFileIndex }

        for fieldInit in initInfo.fieldInitializers {
            guard let initExpr = try? ir.expressionBody(fieldInit.bodyIndex, fileIndex: fileIndex),
                  let value = defaultFieldInitializerValue(initExpr),
                  case .null = value,
                  let fieldType = decodeType(fieldInit.typeIndex),
                  KIRDefaultFieldInitializer.isDefaultValue(value, for: fieldType, types: types),
                  let offset = fieldOffsetExpr(fieldSymbol: fieldInit.field, into: &body)
            else {
                continue
            }
            let nullValue = arena.appendExpr(.null, type: fieldType)
            body.append(.constValue(result: nullValue, value: .null))
            let result = arena.appendTemporary(type: types.anyType)
            body.append(.call(
                symbol: nil, callee: interner.intern("kk_array_set"),
                arguments: [receiver, offset, nullValue], result: result,
                canThrow: true, thrownResult: nil
            ))
        }
    }

    /// `kk_object_new` + the same type/vtable/itable/KClass registration block
    /// source constructor call sites emit (the `CallLowerer` ctor path).
    private func emitObjectAllocation(
        classSymbol: SymbolID,
        objectType: TypeID,
        into body: inout KIRLoweringEmitContext
    ) -> (allocated: KIRExprID, classIDExpr: KIRExprID) {
        let intType = types.intType
        let layout = symbols.nominalLayout(for: classSymbol)
        let slotCount = Int64(max(layout?.instanceSizeWords ?? 1, 1))
        let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
        body.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
        let classIDValue = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: classSymbol, sema: sema, interner: interner
        )
        let classIDExpr = arena.appendExpr(.intLiteral(classIDValue), type: intType)
        body.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))
        let allocated = arena.appendTemporary(type: objectType)
        body.append(.call(
            symbol: nil, callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: allocated, canThrow: false, thrownResult: nil
        ))

        if symbols.symbol(classSymbol)?.flags.contains(.dataType) == true {
            let registerResult = arena.appendTemporary(type: intType)
            emitNonThrowingCall(
                callee: interner.intern("kk_runtime_register_data_class"),
                arg: classIDExpr, result: registerResult, into: &body.instructions
            )
        }
        appendNominalSupertypeEdgeRegistrations(
            childSymbol: classSymbol, sema: sema, arena: arena,
            interner: interner, instructions: &body.instructions
        )
        appendObjectItableMethodRegistrations(
            objectValue: allocated, nominalSymbol: classSymbol,
            driver: driver, sema: sema, arena: arena, interner: interner,
            instructions: &body.instructions
        )
        appendObjectItablePropertyGetterRegistrations(
            objectValue: allocated, nominalSymbol: classSymbol,
            sema: sema, cache: driver.ctx.nominalDispatchCache,
            arena: arena, interner: interner, instructions: &body.instructions
        )
        appendObjectItablePropertySetterRegistrations(
            objectValue: allocated, nominalSymbol: classSymbol,
            sema: sema, cache: driver.ctx.nominalDispatchCache,
            arena: arena, interner: interner, instructions: &body.instructions
        )
        appendObjectVtableMethodRegistrations(
            objectValue: allocated, nominalSymbol: classSymbol,
            driver: driver, sema: sema, arena: arena,
            interner: interner, instructions: &body.instructions
        )
        appendObjectAnyToStringRegistration(
            objectValue: allocated, nominalSymbol: classSymbol,
            driver: driver, sema: sema, arena: arena,
            interner: interner, instructions: &body.instructions
        )
        driver.callLowerer.emitKClassMetadataRegistration(
            objectSymbol: classSymbol, typeID: classIDValue,
            sema: sema, arena: arena, interner: interner,
            instructions: &body.instructions
        )
        // Throwable subclasses capture a stack trace at allocation.
        if let throwableSymbol = symbols.lookup(fqName: [
            interner.intern("kotlin"), interner.intern("Throwable")
        ]) {
            let ownerType = types.make(.classType(ClassType(
                classSymbol: classSymbol, args: [], nullability: .nonNull
            )))
            let throwableType = types.make(.classType(ClassType(
                classSymbol: throwableSymbol, args: [], nullability: .nonNull
            )))
            if types.isSubtype(ownerType, throwableType) {
                let captureResult = arena.appendTemporary(type: intType)
                emitNonThrowingCall(
                    callee: interner.intern("__kk_throwable_captureStackTrace"),
                    arg: allocated, result: captureResult, into: &body.instructions
                )
            }
        }
        return (allocated, classIDExpr)
    }

    /// `instanceInitializerCall` expansion: member field initializer
    /// expressions (e.g. ctor-parameter `val` captures) plus anonymous-init
    /// bodies, in member-declaration order — what the Kotlin/Native
    /// deserializer re-synthesizes into the class's anonymous initializer.
    private func emitInstanceInitializers(
        classSymbol: SymbolID?,
        into body: inout KIRLoweringEmitContext
    ) {
        guard let classSymbol,
              let initInfo = classInitBySymbol[classSymbol],
              let thisExpr
        else { return }
        let savedFileIndex = fileIndex
        fileIndex = initInfo.fileIndex
        defer { fileIndex = savedFileIndex }

        for fieldInit in initInfo.fieldInitializers {
            guard let initExpr = try? ir.expressionBody(
                fieldInit.bodyIndex, fileIndex: fileIndex
            ) else { continue }
            let fieldType = decodeType(fieldInit.typeIndex) ?? decodeType(initExpr.typeIndex)
            if let fieldType,
               let value = defaultFieldInitializerValue(initExpr),
               KIRDefaultFieldInitializer.isDefaultValue(value, for: fieldType, types: types)
            {
                continue
            }
            let value = translateExpression(initExpr, into: &body)
            guard let offset = fieldOffsetExpr(fieldSymbol: fieldInit.field, into: &body) else {
                reportUnsupported("no field offset for init store")
                continue
            }
            let result = arena.appendTemporary(type: types.anyType)
            body.append(.call(
                symbol: nil, callee: interner.intern("kk_array_set"),
                arguments: [thisExpr, offset, value], result: result,
                canThrow: true, thrownResult: nil
            ))
        }
        for bodyIndex in initInfo.anonymousInitBodyIndices {
            if let statement = try? ir.body(bodyIndex, fileIndex: fileIndex) {
                translateStatement(statement, into: &body)
            }
        }
    }

    private func defaultFieldInitializerValue(_ expression: KlibIrExpression) -> KIRExprKind? {
        switch expression.kind {
        case .constNull:
            .null
        case let .constBool(value):
            .boolLiteral(value)
        case let .constChar(value):
            .charLiteral(UInt32(bitPattern: value))
        case let .constByte(value), let .constShort(value), let .constInt(value):
            .intLiteral(Int64(value))
        case let .constLong(value):
            .longLiteral(value)
        case let .constFloat(bits):
            .floatLiteral(Double(Float(bitPattern: bits)))
        case let .constDouble(bits):
            .doubleLiteral(Double(bitPattern: bits))
        case let .typeOp(op, _, argument) where op == .implicitCast || op == .implicitIntegerCoercion:
            defaultFieldInitializerValue(argument)
        default:
            nil
        }
    }


    private func translateReturnableBlock(
        _ ref: KlibSymbolRef,
        statements: [KlibIrStatement],
        resultType: TypeID,
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let result: KIRExprID? = resultType == types.unitType
            ? nil
            : arena.appendTemporary(type: resultType)
        let endLabel = driver.ctx.makeLoopLabel()
        returnableBlocks[ref.signatureIndex] = (label: endLabel, result: result)
        _ = translateStatementSequence(statements, into: &body)
        body.append(.label(endLabel))
        returnableBlocks.removeValue(forKey: ref.signatureIndex)
        return result ?? unitExpr(into: &body)
    }

    private func translateWhen(
        _ branches: [KlibIrStatement],
        resultType: TypeID,
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let producesValue = resultType != types.unitType && resultType != types.nothingType
        let result: KIRExprID? = producesValue ? arena.appendTemporary(type: resultType) : nil
        let endLabel = driver.ctx.makeLoopLabel()
        let boolType = types.booleanType

        for branch in branches {
            guard case .branch(let condition, let branchResult) = branch.kind else {
                reportUnsupported("non-branch statement inside when")
                continue
            }
            // Kotlin's else-branch condition is `const(true)`.
            if isConstTrue(condition) {
                let value = translateExpression(branchResult, into: &body)
                if let result { body.append(.copy(from: value, to: result)) }
                body.append(.jump(endLabel))
                continue
            }
            let cond = translateExpression(condition, into: &body)
            let nextLabel = driver.ctx.makeLoopLabel()
            let falseExpr = arena.appendExpr(.boolLiteral(false), type: boolType)
            body.append(.constValue(result: falseExpr, value: .boolLiteral(false)))
            body.append(.jumpIfEqual(lhs: cond, rhs: falseExpr, target: nextLabel))
            let value = translateExpression(branchResult, into: &body)
            if let result { body.append(.copy(from: value, to: result)) }
            body.append(.jump(endLabel))
            body.append(.label(nextLabel))
        }
        body.append(.label(endLabel))
        return result ?? unitExpr(into: &body)
    }

    private func translateLoop(
        _ loop: KlibLoop,
        isDoWhile: Bool,
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let headLabel = driver.ctx.makeLoopLabel()
        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        loopLabels[loop.loopId] = (continueLabel: continueLabel, breakLabel: breakLabel)
        defer { loopLabels.removeValue(forKey: loop.loopId) }
        let boolType = types.booleanType

        body.append(.label(headLabel))
        if !isDoWhile {
            let cond = translateExpression(loop.condition, into: &body)
            let falseExpr = arena.appendExpr(.boolLiteral(false), type: boolType)
            body.append(.constValue(result: falseExpr, value: .boolLiteral(false)))
            body.append(.jumpIfEqual(lhs: cond, rhs: falseExpr, target: breakLabel))
        }
        if let loopBody = loop.body {
            _ = translateExpression(loopBody, into: &body)
        }
        if isDoWhile {
            body.append(.label(continueLabel))
            let cond = translateExpression(loop.condition, into: &body)
            let trueExpr = arena.appendExpr(.boolLiteral(true), type: boolType)
            body.append(.constValue(result: trueExpr, value: .boolLiteral(true)))
            body.append(.jumpIfEqual(lhs: cond, rhs: trueExpr, target: headLabel))
        } else {
            body.append(.label(continueLabel))
            body.append(.jump(headLabel))
        }
        body.append(.label(breakLabel))
        return unitExpr(into: &body)
    }


    private func fieldOffsetExpr(
        fieldSymbol: SymbolID,
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID? {
        guard let owner = symbols.parentSymbol(for: fieldSymbol),
              let layout = symbols.nominalLayout(for: owner),
              let offset = layout.fieldOffsets[fieldSymbol]
        else { return nil }
        let expr = arena.appendExpr(.intLiteral(Int64(offset)), type: types.intType)
        body.append(.constValue(result: expr, value: .intLiteral(Int64(offset))))
        return expr
    }

    private func translateGetField(
        _ access: KlibFieldAccess,
        resultType: TypeID,
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        guard let fieldSymbol = symbol(for: access.symbol) else {
            reportUnsupported("unresolvable field \(debugName(of: access.symbol))")
            return errorExpr(type: resultType, into: &body)
        }
        if let receiverExpr = access.receiver {
            let receiver = translateExpression(receiverExpr, into: &body)
            guard let offset = fieldOffsetExpr(fieldSymbol: fieldSymbol, into: &body) else {
                reportUnsupported("no field offset for \(debugName(of: access.symbol))")
                return errorExpr(type: resultType, into: &body)
            }
            let result = arena.appendTemporary(type: resultType)
            body.append(.call(
                symbol: nil, callee: interner.intern("kk_array_get_inbounds"),
                arguments: [receiver, offset], result: result,
                canThrow: false, thrownResult: nil
            ))
            return result
        }
        let result = arena.appendTemporary(type: resultType)
        body.append(.loadGlobal(result: result, symbol: fieldSymbol))
        return result
    }

    private func translateSetField(
        _ access: KlibFieldAccess,
        value: KlibIrExpression,
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let lowered = translateExpression(value, into: &body)
        guard let fieldSymbol = symbol(for: access.symbol) else {
            reportUnsupported("unresolvable field \(debugName(of: access.symbol))")
            return lowered
        }
        if let receiverExpr = access.receiver {
            let receiver = translateExpression(receiverExpr, into: &body)
            guard let offset = fieldOffsetExpr(fieldSymbol: fieldSymbol, into: &body) else {
                reportUnsupported("no field offset for \(debugName(of: access.symbol))")
                return lowered
            }
            let result = arena.appendTemporary(type: types.anyType)
            body.append(.call(
                symbol: nil, callee: interner.intern("kk_array_set"),
                arguments: [receiver, offset, lowered], result: result,
                canThrow: true, thrownResult: nil
            ))
        } else {
            body.append(.storeGlobal(value: lowered, symbol: fieldSymbol))
        }
        return lowered
    }

    private func translateGetObject(
        _ ref: KlibSymbolRef,
        resultType: TypeID,
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        guard let objectSymbol = symbol(for: ref) else {
            reportUnsupported("unresolvable object \(debugName(of: ref))")
            return errorExpr(type: resultType, into: &body)
        }
        emitGlobal(for: ref, typeIndex: nil)
        driver.emitObjectLazyInitGuardIfNeeded(
            objectSymbol: objectSymbol, arena: arena,
            sema: sema, interner: interner, instructions: &body.instructions
        )
        let result = arena.appendTemporary(type: resultType)
        body.append(.loadGlobal(result: result, symbol: objectSymbol))
        return result
    }


    private func translateStringConcat(
        _ arguments: [KlibIrExpression],
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let stringType = types.stringType
        var partIDs: [KIRExprID] = []
        for argument in arguments {
            let lowered = translateExpression(argument, into: &body)
            let argumentType = decodeType(argument.typeIndex) ?? arena.exprType(lowered)
            if let argumentType, argumentType != stringType {
                partIDs.append(driver.callLowerer.emitAnyToStringWithNullGuard(
                    valueID: lowered, valueType: argumentType,
                    sema: sema, arena: arena, interner: interner,
                    instructions: &body.instructions
                ))
            } else {
                partIDs.append(lowered)
            }
        }
        if partIDs.isEmpty {
            let empty = interner.intern("")
            let expr = arena.appendExpr(.stringLiteral(empty), type: stringType)
            body.append(.constValue(result: expr, value: .stringLiteral(empty)))
            return expr
        }
        var accumulated = partIDs[0]
        for part in partIDs.dropFirst() {
            let next = arena.appendTemporary(type: stringType)
            body.append(.call(
                symbol: nil, callee: interner.intern("__kk_string_concat_flat"),
                arguments: [accumulated, part], result: next,
                canThrow: false, thrownResult: nil
            ))
            accumulated = next
        }
        return accumulated
    }


    private func translateTypeOp(
        _ op: KlibTypeOperator,
        operandType: Int32,
        argument: KlibIrExpression,
        resultType: TypeID,
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let operand = translateExpression(argument, into: &body)
        switch op {
        case .is, .notIs:
            let token = typeCheckToken(
                typeIndex: operandType,
                subjectType: decodeType(argument.typeIndex) ?? arena.exprType(operand),
                into: &body
            )
            let boolType = types.booleanType
            let isResult = arena.appendTemporary(type: boolType)
            body.append(.call(
                symbol: nil, callee: interner.intern("kk_op_is"),
                arguments: [operand, token], result: isResult,
                canThrow: false, thrownResult: nil
            ))
            if op == .is { return isResult }
            let falseExpr = arena.appendExpr(.boolLiteral(false), type: boolType)
            body.append(.constValue(result: falseExpr, value: .boolLiteral(false)))
            let negated = arena.appendTemporary(type: boolType)
            body.append(.binary(op: .equal, lhs: isResult, rhs: falseExpr, result: negated))
            return negated

        case .cast, .safeCast:
            let token = typeCheckToken(typeIndex: operandType, into: &body)
            let result = arena.appendTemporary(type: resultType)
            body.append(.call(
                symbol: nil,
                callee: interner.intern(op == .safeCast ? "kk_op_safe_cast" : "kk_op_cast"),
                arguments: [operand, token], result: result,
                canThrow: op == .cast, thrownResult: nil
            ))
            return result

        case .implicitNotNull:
            let result = arena.appendTemporary(type: resultType)
            body.append(.nullAssert(operand: operand, result: result))
            return result

        case .implicitCast, .reinterpretCast, .implicitDynamicCast, .samConversion,
             .implicitIntegerCoercion:
            let result = arena.appendTemporary(type: resultType)
            body.append(.copy(from: operand, to: result))
            return result

        case .implicitCoercionToUnit:
            return unitExpr(into: &body)
        }
    }

    private func typeCheckToken(
        typeIndex: Int32,
        subjectType: TypeID? = nil,
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        if let targetType = decodeType(typeIndex) {
            return driver.exprLowerer.lowerTypeCheckTokenExpr(
                targetType: driver.exprLowerer.runtimeIsCheckTargetType(
                    subjectType: subjectType, targetType: targetType, sema: sema
                ),
                sema: sema, interner: interner,
                arena: arena, instructions: &body.instructions
            )
        }
        // Unknown target type → token 0 (runtime reports mismatch).
        let expr = arena.appendExpr(.intLiteral(0), type: types.intType)
        body.append(.constValue(result: expr, value: .intLiteral(0)))
        return expr
    }


    private func translateVararg(
        elements: [KlibVarargElement],
        resultType: TypeID,
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let intType = types.intType
        let sizeExpr = arena.appendExpr(.intLiteral(Int64(elements.count)), type: intType)
        body.append(.constValue(result: sizeExpr, value: .intLiteral(Int64(elements.count))))
        let array = arena.appendTemporary(type: resultType)
        body.append(.call(
            symbol: nil, callee: interner.intern("kk_array_new"),
            arguments: [sizeExpr], result: array,
            canThrow: false, thrownResult: nil
        ))
        for (index, element) in elements.enumerated() {
            switch element {
            case .expression(let elementExpr):
                let value = translateExpression(elementExpr, into: &body)
                let indexExpr = arena.appendExpr(.intLiteral(Int64(index)), type: intType)
                body.append(.constValue(result: indexExpr, value: .intLiteral(Int64(index))))
                let store = arena.appendTemporary(type: types.anyType)
                body.append(.call(
                    symbol: nil, callee: interner.intern("kk_array_set"),
                    arguments: [array, indexExpr, value], result: store,
                    canThrow: true, thrownResult: nil
                ))
            case .spread(let spread, _, _):
                reportUnsupported("vararg spread")
                _ = translateExpression(spread, into: &body)
            }
        }
        return array
    }


    /// `kotlin.<Prim>.<op>` members have no serialized body anywhere — they are
    /// compiler intrinsics that source lowering maps onto `kk_op_*`/`kk_*`
    /// runtime stubs (the ABI lowering pass inserts unboxing afterwards).
    /// Mirrors that mapping for serialized bodies so e.g. `a + b` inside an
    /// imported function emits the same `kk_op_add` a source body would.
    private func intrinsicCall(
        _ ref: KlibSymbolRef,
        memberAccess: KlibMemberAccess,
        resultType: TypeID,
        into body: inout KIRLoweringEmitContext
    ) -> KIRExprID? {
        guard let fqName = resolvedFqName(of: ref) else { return nil }
        let parts = fqName.split(separator: ".").map(String.init)
        guard parts.count >= 3, parts[0] == "kotlin" else { return nil }
        let owner = parts.dropLast().joined(separator: ".")
        let member = parts.last ?? ""

        if member == "invoke", let shape = KlibFunctionTypeShape(classifierName: owner), !shape.isSuspend {
            let arguments = intrinsicArguments(memberAccess, into: &body)
            guard shape.arity <= 6, arguments.count == shape.arity + 1 else {
                reportUnsupported("function-value invocation arity")
                return errorExpr(type: resultType, into: &body)
            }
            let result = arena.appendTemporary(type: resultType)
            body.append(.call(
                symbol: nil,
                callee: interner.intern(shape.arity == 1 ? "kk_function_invoke" : "kk_function_invoke_\(shape.arity)"),
                arguments: arguments, result: result, canThrow: true, thrownResult: nil
            ))
            return result
        }
        if owner == "kotlin.internal.SharedVariableBox", member == "element" {
            let arguments = intrinsicArguments(memberAccess, into: &body)
            switch arguments.count {
            case 1: return loadCell(arguments[0], type: resultType, into: &body)
            case 2:
                storeCell(arguments[1], cell: arguments[0], into: &body)
                return unitExpr(into: &body)
            default:
                reportUnsupported("shared-variable box accessor arguments")
                return errorExpr(type: resultType, into: &body)
            }
        }

        // Native models array `size` as a member, while the bundled stdlib
        // supplies an extension property backed by these typed intrinsics.
        if parts.count == 3, parts[0] == "kotlin", member == "size",
           KnownCompilerNames(interner: interner).isArrayLikeName(interner.intern(parts[1])),
           let bridge = symbols.lookup(fqName: [
               interner.intern("kotlin"), interner.intern("__kk\(parts[1])Size"),
           ]), let linkName = symbols.externalLinkName(for: bridge) {
            let arguments = intrinsicArguments(memberAccess, into: &body)
            let result = arena.appendTemporary(type: resultType)
            body.append(.call(
                symbol: bridge, callee: interner.intern(linkName), arguments: arguments,
                result: result, canThrow: false, thrownResult: nil
            ))
            return result
        }

        let floatPrefix: String? = switch owner {
        case "kotlin.Double": "d"
        case "kotlin.Float": "f"
        default: nil
        }
        let isUnsigned = owner.hasPrefix("kotlin.U")
        let isNumericOrChar = floatPrefix != nil || isUnsigned
            || ["kotlin.Int", "kotlin.Long", "kotlin.Short", "kotlin.Byte", "kotlin.Char"]
                .contains(owner)

        // Member → runtime callee, validated per-owner so `String.plus` or a
        // user class's `get` never route through a numeric intrinsic.
        let opName: String? = switch member {
        case "plus":
            if owner == "kotlin.String" { "__kk_string_concat_flat" }
            else if isNumericOrChar { floatPrefix.map { "kk_op_\($0)add" } ?? (isUnsigned ? "kk_op_uadd" : "kk_op_add") }
            else { nil }
        case "minus":
            isNumericOrChar ? floatPrefix.map { "kk_op_\($0)sub" } ?? (isUnsigned ? "kk_op_usub" : "kk_op_sub") : nil
        case "times":
            isNumericOrChar ? floatPrefix.map { "kk_op_\($0)mul" } ?? (isUnsigned ? "kk_op_umul" : "kk_op_mul") : nil
        case "div":
            isNumericOrChar ? floatPrefix.map { "kk_op_\($0)div" } ?? (isUnsigned ? "kk_op_udiv" : "kk_op_div") : nil
        case "rem", "mod":
            isNumericOrChar ? floatPrefix.map { "kk_op_\($0)mod" } ?? (isUnsigned ? "kk_op_urem" : "kk_op_mod") : nil
        case "floorDiv":
            isNumericOrChar ? (isUnsigned ? "kk_op_udiv" : "kk_op_floor_div") : nil
        case "unaryMinus":
            isNumericOrChar ? floatPrefix.map { "kk_op_\($0)neg" } ?? "kk_op_uminus" : nil
        case "inv":
            isNumericOrChar ? "kk_op_inv" : nil
        case "not":
            owner == "kotlin.Boolean" ? "kk_op_not" : nil
        case "and":
            isNumericOrChar || owner == "kotlin.Boolean" ? "kk_bitwise_and" : nil
        case "or":
            isNumericOrChar || owner == "kotlin.Boolean" ? "kk_bitwise_or" : nil
        case "xor":
            isNumericOrChar || owner == "kotlin.Boolean" ? "kk_bitwise_xor" : nil
        case "shl":
            isNumericOrChar && floatPrefix == nil ? "kk_op_shl" : nil
        case "shr":
            isNumericOrChar && floatPrefix == nil ? "kk_op_shr" : nil
        case "ushr":
            isNumericOrChar && floatPrefix == nil ? "kk_op_ushr" : nil
        case "equals":
            // Only the Any/primitive declarations are bodiless intrinsics —
            // a data class's own `equals` override must keep its body.
            isNumericOrChar || ["kotlin.Boolean", "kotlin.String", "kotlin.Any"].contains(owner)
                ? "kk_op_eq" : nil
        case "hashCode":
            isNumericOrChar || ["kotlin.Boolean", "kotlin.String", "kotlin.Any"].contains(owner)
                ? "kk_any_hashCode" : nil
        case "compareTo":
            if owner == "kotlin.Char" { "kk_char_compareTo" }
            else if owner == "kotlin.String" { "kk_string_compareTo_flat" }
            else if isNumericOrChar { "kk_primitive_compareTo" }
            else { nil }
        default: nil
        }
        let isSpecialMember = member == "toString" || member == "unaryPlus"
            || member == "inc" || member == "dec"
        guard opName != nil || isSpecialMember else { return nil }
        if isSpecialMember,
           !(isNumericOrChar || ["kotlin.Boolean", "kotlin.String", "kotlin.Any"].contains(owner))
        {
            return nil
        }

        let loweredArguments = intrinsicArguments(memberAccess, into: &body)

        if member == "unaryPlus" {
            return loweredArguments.first
        }
        if member == "inc" || member == "dec" {
            guard let operand = loweredArguments.first else { return nil }
            let oneExpr = arena.appendExpr(.intLiteral(1), type: resultType)
            body.append(.constValue(result: oneExpr, value: .intLiteral(1)))
            let result = arena.appendTemporary(type: resultType)
            body.append(.call(
                symbol: nil,
                callee: interner.intern(member == "inc" ? "kk_op_add" : "kk_op_sub"),
                arguments: [operand, oneExpr], result: result,
                canThrow: false, thrownResult: nil
            ))
            return result
        }
        if member == "toString" {
            guard let value = loweredArguments.first else { return nil }
            let valueType = memberAccess.arguments.first.flatMap { decodeType($0.typeIndex) }
                ?? arena.exprType(value)
                ?? types.anyType
            return driver.callLowerer.emitAnyToStringWithNullGuard(
                valueID: value, valueType: valueType,
                sema: sema, arena: arena, interner: interner,
                instructions: &body.instructions
            )
        }
        guard let opName else { return nil }
        let result = arena.appendTemporary(type: resultType)
        body.append(.call(
            symbol: nil, callee: interner.intern(opName),
            arguments: loweredArguments, result: result,
            canThrow: false, thrownResult: nil
        ))
        return result
    }

    private func intrinsicArguments(_ access: KlibMemberAccess, into body: inout KIRLoweringEmitContext) -> [KIRExprID] {
        let arguments: [KlibIrExpression?]
        if !access.arguments.isEmpty {
            arguments = access.arguments
        } else if !access.argumentsPre240.isEmpty {
            arguments = access.argumentsPre240
        } else {
            arguments = [access.dispatchReceiver, access.extensionReceiver].compactMap { $0 }
                + access.regularArguments
        }
        return arguments.compactMap { argument in
            guard let argument else {
                reportUnsupported("missing intrinsic argument")
                return nil
            }
            return translateExpression(argument, into: &body)
        }
    }


    /// Reuses the primitive-mapping rules the declaration materializer encodes
    /// through signature text, so `kotlin.Int` lands on `types.intType`
    /// (required for correct boxing).
    private func decodeType(_ typeIndex: Int32) -> TypeID? {
        guard typeIndex >= 0,
              let type = try? ir.type(typeIndex, fileIndex: fileIndex)
        else { return nil }
        switch type {
        case .simple(let classifier, let nullability, let arguments, _):
            return decodeSimpleType(
                classifier: classifier,
                nullable: nullability == .markedNullable,
                arguments: arguments
            )
        case .legacySimple(let classifier, let hasQuestionMark, let arguments, _):
            return decodeSimpleType(
                classifier: classifier,
                nullable: hasQuestionMark,
                arguments: arguments
            )
        case .definitelyNotNull(let constituents):
            for constituent in constituents {
                if let decoded = decodeType(constituent) {
                    return types.makeNonNullable(decoded)
                }
            }
            return nil
        case .dynamic:
            return types.anyType
        case .error:
            return types.errorType
        }
    }

    private func decodeSimpleType(
        classifier: KlibSymbolRef,
        nullable: Bool,
        arguments: [KlibTypeArgument]
    ) -> TypeID? {
        if classifier.kind == .typeParameter {
            let key = KlibSignatureKey(fileIndex: fileIndex, signatureIndex: classifier.signatureIndex)
            // Imported signature placeholders have stable synthetic IDs but
            // no standalone SymbolTable entry. The declaration binder is the
            // authority for these IDs; composite resolution may instead find
            // the containing function, which is not a type parameter.
            let paramSymbol = typeParameterSymbols[key] ?? symbol(for: classifier).flatMap {
                symbols.symbol($0)?.kind == .typeParameter ? $0 : nil
            }
            guard let paramSymbol else { return nil }
            return types.make(.typeParam(TypeParamType(
                symbol: paramSymbol,
                nullability: nullable ? .nullable : .nonNull
            )))
        }
        if let name = resolvedFqName(of: classifier) {
            if let primitive = primitiveType(fqName: name, nullable: nullable) { return primitive }
            if name == "kotlin.internal.SharedVariableBox" { return types.anyType }
            if let shape = KlibFunctionTypeShape(classifierName: name) {
                guard arguments.count == shape.arity + 1 else { return nil }
                var decoded: [TypeID] = []
                for argument in arguments {
                    guard case .type(let index, _) = argument, let type = decodeType(index) else { return nil }
                    decoded.append(type)
                }
                return types.make(.functionType(FunctionType(
                    params: Array(decoded.dropLast()), returnType: decoded.last!,
                    isSuspend: shape.isSuspend, nullability: nullable ? .nullable : .nonNull
                )))
            }
        }
        guard let classSymbol = symbol(for: classifier) else { return nil }
        if let primitive = primitiveType(classSymbol: classSymbol, nullable: nullable) {
            return primitive
        }
        let args = arguments.map { argument -> TypeArg in
            switch argument {
            case .star:
                return .star
            case .type(let index, let variance):
                let decoded = decodeType(index) ?? types.anyType
                switch variance {
                case .in: return .in(decoded)
                case .out: return .out(decoded)
                case .invariant: return .invariant(decoded)
                }
            }
        }
        return types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: args,
            nullability: nullable ? .nullable : .nonNull
        )))
    }

    private func primitiveType(classSymbol: SymbolID, nullable: Bool) -> TypeID? {
        guard let info = symbols.symbol(classSymbol) else { return nil }
        let fqName = info.fqName.map { interner.resolve($0) }.joined(separator: ".")
        return primitiveType(fqName: fqName, nullable: nullable)
    }

    private func primitiveType(fqName: String, nullable: Bool) -> TypeID? {
        let base: TypeID?
        switch fqName {
        case "kotlin.Boolean": base = types.booleanType
        case "kotlin.Char": base = types.charType
        case "kotlin.Byte": base = types.byteType
        case "kotlin.Short": base = types.shortType
        case "kotlin.Int": base = types.intType
        case "kotlin.Long": base = types.longType
        case "kotlin.Float": base = types.floatType
        case "kotlin.Double": base = types.doubleType
        case "kotlin.UByte": base = types.ubyteType
        case "kotlin.UShort": base = types.ushortType
        case "kotlin.UInt": base = types.uintType
        case "kotlin.ULong": base = types.ulongType
        case "kotlin.String": base = types.stringType
        case "kotlin.Unit": base = types.unitType
        case "kotlin.Any": base = types.anyType
        case "kotlin.Nothing": base = types.nothingType
        default: base = nil
        }
        guard let base else { return nil }
        return nullable ? types.makeNullable(base) : base
    }


    private func calleeName(for symbol: SymbolID, ref: KlibSymbolRef) -> InternedString {
        if let decoded = SyntheticSymbolScheme.decodedPropertyAccessor(symbol) {
            return interner.intern(decoded.kind == .getter ? "get" : "set")
        }
        if let info = symbols.symbol(symbol) {
            return info.name
        }
        return interner.intern(debugName(of: ref))
    }

    private func debugName(of ref: KlibSymbolRef) -> String {
        (try? ir.symbolDescription(ref, fileIndex: fileIndex)) ?? "sig[\(ref.signatureIndex)]"
    }

    private func unitExpr(into body: inout KIRLoweringEmitContext) -> KIRExprID {
        let expr = arena.appendExpr(.unit, type: types.unitType)
        body.append(.constValue(result: expr, value: .unit))
        return expr
    }

    /// Result temp for unsupported constructs — emits `kk_abort_unreachable`
    /// so a successfully-linked program can never silently observe the value.
    private func errorExpr(type: TypeID, into body: inout KIRLoweringEmitContext) -> KIRExprID {
        let result = arena.appendTemporary(type: type)
        body.append(.call(
            symbol: nil, callee: interner.intern("kk_abort_unreachable"),
            arguments: [], result: result,
            canThrow: true, thrownResult: nil
        ))
        return result
    }

    private func isConstTrue(_ expression: KlibIrExpression) -> Bool {
        if case .constBool(let value) = expression.kind { return value }
        return false
    }

    private func reportUnsupported(_ what: String) {
        guard reportedUnsupported.insert(what).inserted else { return }
        diagnostics.warning(
            "KSWIFTK-LIB-0029",
            "unsupported serialized IR form in .klib body: \(what)",
            range: nil
        )
    }
}
