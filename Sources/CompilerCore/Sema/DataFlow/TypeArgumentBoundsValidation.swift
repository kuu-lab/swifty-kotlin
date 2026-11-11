final class TypeArgumentBoundsValidator {
    private struct Substitution: Hashable {
        let symbol: SymbolID
        let argument: TypeArg
    }

    private struct AliasUse: Hashable {
        let symbol: SymbolID
        let arguments: [TypeArg]
        let substitutions: [Substitution]
    }

    private struct TypeUse: Hashable {
        let type: TypeID
        let substitutions: [Substitution]
    }

    private let symbols: SymbolTable
    private let types: TypeSystem
    private let diagnostics: DiagnosticEngine
    private var visitedAliases: Set<AliasUse> = []
    private var visitedTypes: Set<TypeUse> = []

    init(symbols: SymbolTable, types: TypeSystem, diagnostics: DiagnosticEngine) {
        self.symbols = symbols
        self.types = types
        self.diagnostics = diagnostics
    }

    func validate(
        symbol: SymbolID,
        arguments: [TypeArg],
        range: SourceRange?,
        allowsTypeParameterArguments: Bool = false
    ) {
        visitedAliases.removeAll(keepingCapacity: true)
        visitedTypes.removeAll(keepingCapacity: true)
        visitNominal(
            symbol,
            arguments: arguments,
            substitutions: [:],
            depth: 0,
            range: range,
            allowsTypeParameterArguments: allowsTypeParameterArguments
        )
    }

    func validate(type: TypeID, range: SourceRange?, allowsTypeParameterArguments: Bool = false) {
        visitedAliases.removeAll(keepingCapacity: true)
        visitedTypes.removeAll(keepingCapacity: true)
        visit(type, substitutions: [:], depth: 0, range: range, allowsTypeParameterArguments: allowsTypeParameterArguments)
    }

    private func visitNominal(
        _ symbol: SymbolID,
        arguments: [TypeArg],
        substitutions: [SymbolID: TypeArg],
        depth: Int,
        range: SourceRange?,
        allowsTypeParameterArguments: Bool
    ) {
        guard depth < DataFlowSemaPhase.maxStructuralRecursionDepth else { return }
        if symbols.symbol(symbol)?.kind == .typeAlias {
            guard let underlying = symbols.typeAliasUnderlyingType(for: symbol) else { return }
            let parameters = symbols.typeAliasTypeParameters(for: symbol)
            guard parameters.count == arguments.count else { return }
            let replacements = arguments.map { resolve($0, substitutions: substitutions) }
            let use = AliasUse(symbol: symbol, arguments: replacements, substitutions: substitutionKey(substitutions))
            guard visitedAliases.insert(use).inserted else { return }
            var nested = substitutions
            for (parameter, replacement) in zip(parameters, replacements) {
                nested[parameter] = replacement
            }
            visit(underlying, substitutions: nested, depth: depth + 1, range: range, allowsTypeParameterArguments: allowsTypeParameterArguments)
            return
        }

        let parameters = types.nominalTypeParameterSymbols(for: symbol)
        let checkBoundsEnabled = symbols.symbol(symbol)?.flags.contains(.synthetic) != true
        let resolvedArguments = arguments.map { resolve($0, substitutions: substitutions) }
        var substitution: [TypeVarID: TypeID] = [:]
        let typeVarBySymbol = types.makeTypeVarBySymbol(parameters)
        for (parameter, argument) in zip(parameters, resolvedArguments) {
            guard let variable = typeVarBySymbol[parameter] else { continue }
            switch argument {
            case let .invariant(type), let .out(type), let .in(type):
                substitution[variable] = type
            case .star:
                substitution[variable] = types.anyType
            }
        }

        for (index, argument) in resolvedArguments.enumerated() {
            let (_, inner) = split(argument)
            guard let inner else { continue }
            if checkBoundsEnabled, index < parameters.count {
                checkBounds(
                    argumentType: inner,
                    parameter: parameters[index],
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol,
                    range: range,
                    allowsTypeParameterArguments: allowsTypeParameterArguments
                )
            }
            visit(inner, substitutions: substitutions, depth: depth + 1, range: range, allowsTypeParameterArguments: allowsTypeParameterArguments)
        }
    }

    private func visit(
        _ type: TypeID,
        substitutions: [SymbolID: TypeArg],
        depth: Int,
        range: SourceRange?,
        allowsTypeParameterArguments: Bool
    ) {
        guard depth < DataFlowSemaPhase.maxStructuralRecursionDepth else { return }
        let use = TypeUse(type: type, substitutions: substitutionKey(substitutions))
        guard visitedTypes.insert(use).inserted else { return }
        switch types.kind(of: type) {
        case let .classType(classType):
            visitNominal(
                classType.classSymbol,
                arguments: classType.args,
                substitutions: substitutions,
                depth: depth,
                range: range,
                allowsTypeParameterArguments: allowsTypeParameterArguments
            )
            for argument in classType.enclosingTypeArgs {
                if let inner = split(resolve(argument, substitutions: substitutions)).1 {
                    visit(inner, substitutions: substitutions, depth: depth + 1, range: range, allowsTypeParameterArguments: allowsTypeParameterArguments)
                }
            }
        case let .functionType(function):
            for input in function.contextReceivers + (function.receiver.map { [$0] } ?? []) + function.params {
                visit(input, substitutions: substitutions, depth: depth + 1, range: range, allowsTypeParameterArguments: allowsTypeParameterArguments)
            }
            visit(function.returnType, substitutions: substitutions, depth: depth + 1, range: range, allowsTypeParameterArguments: allowsTypeParameterArguments)
        case let .kClassType(kClassType):
            visit(kClassType.argument, substitutions: substitutions, depth: depth + 1, range: range, allowsTypeParameterArguments: allowsTypeParameterArguments)
        case let .intersection(parts):
            for part in parts {
                visit(part, substitutions: substitutions, depth: depth + 1, range: range, allowsTypeParameterArguments: allowsTypeParameterArguments)
        }
        case let .typeParam(typeParam):
            if let capture = typeParam.capture {
                visit(capture.lower, substitutions: substitutions, depth: depth + 1, range: range, allowsTypeParameterArguments: allowsTypeParameterArguments)
                visit(capture.upper, substitutions: substitutions, depth: depth + 1, range: range, allowsTypeParameterArguments: allowsTypeParameterArguments)
            }
        default:
            break
        }
    }

    private func checkBounds(
        argumentType: TypeID,
        parameter: SymbolID,
        substitution: [TypeVarID: TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID],
        range: SourceRange?,
        allowsTypeParameterArguments: Bool
    ) {
        if case .error = types.kind(of: argumentType) { return }
        if allowsTypeParameterArguments, types.typeContainsAnyTypeParam(argumentType) { return }
        for bound in types.declaredUpperBounds(for: parameter) {
            let substitutedBound = types.substituteTypeParameters(
                in: bound,
                substitution: substitution,
                typeVarBySymbol: typeVarBySymbol
            )
            if !types.isSubtype(argumentType, substitutedBound) {
                diagnostics.error(
                    "KSWIFTK-SEMA-BOUND",
                    "Type argument does not satisfy upper bound constraint.",
                    range: range
                )
            }
        }
    }

    private func resolve(_ argument: TypeArg, substitutions: [SymbolID: TypeArg], seen: Set<SymbolID> = []) -> TypeArg {
        let (projection, inner) = split(argument)
        guard let projection, let inner,
              case let .typeParam(parameter) = types.kind(of: inner),
              !seen.contains(parameter.symbol),
              let replacement = substitutions[parameter.symbol]
        else { return argument }
        let resolved = resolve(replacement, substitutions: substitutions, seen: seen.union([parameter.symbol]))
        let (replacementProjection, replacementType) = split(resolved)
        guard let replacementProjection, let replacementType else { return .star }
        switch projection == .invariant ? replacementProjection : projection {
        case .invariant: return .invariant(replacementType)
        case .in: return .in(replacementType)
        case .out: return .out(replacementType)
        }
    }

    private func split(_ argument: TypeArg) -> (TypeVariance?, TypeID?) {
        switch argument {
        case let .invariant(type): (.invariant, type)
        case let .in(type): (.in, type)
        case let .out(type): (.out, type)
        case .star: (nil, nil)
        }
    }

    private func substitutionKey(_ substitutions: [SymbolID: TypeArg]) -> [Substitution] {
        substitutions.map { Substitution(symbol: $0.key, argument: $0.value) }
            .sorted { $0.symbol.rawValue < $1.symbol.rawValue }
    }
}
