import CompilerCore

/// Signatures and storage identities used by serialized inline bodies remain
/// implementation details, but consumers need them to reconstruct their ABI.
enum InlineMetadataDependencies {
    static func collect(module: KIRModule, sema: SemaModule) -> Set<SymbolID> {
        var required: Set<SymbolID> = []
        var pendingSymbols: [SymbolID] = []
        var pendingTypes: [TypeID] = []
        var visitedTypes: Set<TypeID> = []

        func include(_ symbol: SymbolID?) {
            guard let symbol, required.insert(symbol).inserted else { return }
            pendingSymbols.append(symbol)
        }

        for declaration in module.arena.declarations {
            guard case let .function(function) = declaration, function.isInline else { continue }
            // Default stubs can have no Sema symbol but still serialize a body.
            let body = module.inlineBodiesBeforeFinallyLowering[function.symbol]
                ?? module.inlineBodiesBeforeCoroutineLowering[function.symbol]
                ?? function.body
            for instruction in body {
                switch instruction {
                case let .call(symbol, _, _, _, _, _, _, _),
                     let .virtualCall(symbol, _, _, _, _, _, _, _):
                    include(symbol)
                case let .loadGlobal(_, symbol), let .storeGlobal(_, symbol):
                    include(symbol)
                case let .constValue(_, .symbolRef(symbol)):
                    include(symbol)
                default:
                    break
                }
            }
        }

        while !pendingSymbols.isEmpty || !pendingTypes.isEmpty {
            if let symbol = pendingSymbols.popLast() {
                guard sema.symbols.symbol(symbol) != nil else { continue }
                include(sema.symbols.parentSymbol(for: symbol))
                if let signature = sema.symbols.functionSignature(for: symbol) {
                    pendingTypes += signature.parameterTypes + [signature.returnType]
                    pendingTypes += signature.contextReceiverTypes
                    pendingTypes += signature.typeParameterUpperBoundsList.flatMap { $0 }
                    if let receiver = signature.receiverType { pendingTypes.append(receiver) }
                    for parameter in signature.typeParameterSymbols { include(parameter) }
                }
                if let type = sema.symbols.propertyType(for: symbol) { pendingTypes.append(type) }
                if let type = sema.symbols.valueClassUnderlyingType(for: symbol) { pendingTypes.append(type) }
                for parent in sema.symbols.directSupertypes(for: symbol) {
                    include(parent)
                    for argument in sema.types.nominalSupertypeTypeArgs(for: symbol, supertype: parent) {
                        switch argument {
                        case let .invariant(type), let .in(type), let .out(type): pendingTypes.append(type)
                        case .star: break
                        }
                    }
                }
                for parameter in sema.types.nominalTypeParameterSymbols(for: symbol) {
                    include(parameter)
                    pendingTypes += sema.symbols.typeParameterUpperBounds(for: parameter)
                }
            } else if let type = pendingTypes.popLast(), visitedTypes.insert(type).inserted {
                switch sema.types.kind(of: type) {
                case let .classType(nominal):
                    include(nominal.classSymbol)
                    for argument in nominal.args {
                        switch argument {
                        case let .invariant(type), let .in(type), let .out(type): pendingTypes.append(type)
                        case .star: break
                        }
                    }
                case let .typeParam(parameter):
                    include(parameter.symbol)
                    pendingTypes += sema.symbols.typeParameterUpperBounds(for: parameter.symbol)
                case let .functionType(function):
                    pendingTypes += function.params + function.contextReceivers + function.throws + [function.returnType]
                    if let receiver = function.receiver { pendingTypes.append(receiver) }
                case let .intersection(parts):
                    pendingTypes += parts
                case let .kClassType(kClass):
                    pendingTypes.append(kClass.argument)
                default:
                    break
                }
            }
        }
        return required
    }
}
