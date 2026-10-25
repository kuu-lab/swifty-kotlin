/// Use-site projections are checked against their immediate parameter slot,
/// independently of declaration-site variance position analysis.
final class TypeProjectionValidator {
    let symbols: SymbolTable
    let types: TypeSystem
    let interner: StringInterner?
    let diagnostics: DiagnosticEngine?
    let range: SourceRange?

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

    private var visitedAliases: [AliasUse: Int] = [:]
    private var visitedTypes: [TypeUse: Int] = [:]

    init(symbols: SymbolTable, types: TypeSystem, interner: StringInterner?, diagnostics: DiagnosticEngine?, range: SourceRange?) {
        self.symbols = symbols
        self.types = types
        self.interner = interner
        self.diagnostics = diagnostics
        self.range = range
    }

    func validate(arguments: [TypeArg], of symbol: SymbolID) {
        visitedAliases.removeAll(keepingCapacity: true)
        visitedTypes.removeAll(keepingCapacity: true)
        guard diagnostics != nil else { return }
        visitNominal(symbol, arguments: arguments, substitutions: [:], depth: 0)
    }

    func validate(type: TypeID) {
        visitedAliases.removeAll(keepingCapacity: true)
        visitedTypes.removeAll(keepingCapacity: true)
        guard diagnostics != nil else { return }
        visit(type, substitutions: [:], depth: 0)
    }

    private func visitNominal(
        _ symbol: SymbolID, arguments: [TypeArg],
        substitutions: [SymbolID: TypeArg], depth: Int
    ) {
        guard depth < DataFlowSemaPhase.maxStructuralRecursionDepth else { return }
        if symbols.symbol(symbol)?.kind == .typeAlias {
            guard let underlying = symbols.typeAliasUnderlyingType(for: symbol) else { return }
            let parameters = symbols.typeAliasTypeParameters(for: symbol)
            guard parameters.count == arguments.count else { return }
            let replacements = arguments.map { resolve($0, substitutions: substitutions) }
            let use = AliasUse(
                symbol: symbol, arguments: replacements,
                substitutions: substitutionKey(substitutions)
            )
            if let previousDepth = visitedAliases[use], previousDepth <= depth { return }
            visitedAliases[use] = depth
            var nested = substitutions
            for (parameter, replacement) in zip(parameters, replacements) {
                nested[parameter] = replacement
            }
            visit(underlying, substitutions: nested, depth: depth + 1)
            return
        }
        let ownVariances = types.nominalTypeParameterVariances(for: symbol)
        let ownArity = max(types.nominalTypeParameterSymbols(for: symbol).count, ownVariances.count)
        // Unqualified Inner<T> supplies only its own arguments; a qualified
        // Outer<S>.Inner<T> supplies enclosing arguments as well.
        let variances = arguments.count <= ownArity ? ownVariances
            : types.allTypeParameterVariances(for: symbol, fallbackArity: ownArity)
        let owner = interner.flatMap { strings in
            symbols.symbol(symbol).map { strings.resolve($0.name) }
        } ?? "type"
        for (index, argument) in arguments.enumerated() {
            check(argument, formal: index < variances.count ? variances[index] : .invariant,
                  owner: owner, substitutions: substitutions, depth: depth + 1)
        }
    }

    private func visit(_ type: TypeID, substitutions: [SymbolID: TypeArg], depth: Int) {
        guard depth < DataFlowSemaPhase.maxStructuralRecursionDepth else { return }
        let use = TypeUse(type: type, substitutions: substitutionKey(substitutions))
        if let previousDepth = visitedTypes[use], previousDepth <= depth { return }
        visitedTypes[use] = depth
        switch types.kind(of: type) {
        case let .classType(nominal):
            visitNominal(nominal.classSymbol, arguments: types.allTypeArguments(for: nominal),
                         substitutions: substitutions, depth: depth)
        case let .functionType(function):
            for input in function.contextReceivers + (function.receiver.map { [$0] } ?? []) + function.params {
                check(.invariant(input), formal: .in, owner: "function type",
                      substitutions: substitutions, depth: depth + 1)
            }
            check(.invariant(function.returnType), formal: .out, owner: "function type",
                  substitutions: substitutions, depth: depth + 1)
        case let .kClassType(type):
            let variance = types.kClassInterfaceSymbol
                .flatMap { types.nominalTypeParameterVariances(for: $0).first } ?? .invariant
            check(.invariant(type.argument), formal: variance, owner: "KClass",
                  substitutions: substitutions, depth: depth + 1)
        case let .intersection(parts):
            for part in parts { visit(part, substitutions: substitutions, depth: depth + 1) }
        default:
            break
        }
    }

    private func substitutionKey(_ substitutions: [SymbolID: TypeArg]) -> [Substitution] {
        substitutions.map { Substitution(symbol: $0.key, argument: $0.value) }
            .sorted { $0.symbol.rawValue < $1.symbol.rawValue }
    }

    private func check(
        _ argument: TypeArg, formal: TypeVariance, owner: String,
        substitutions: [SymbolID: TypeArg], depth: Int
    ) {
        let effective = resolve(argument, substitutions: substitutions)
        let (projection, inner) = split(effective)
        if let projection, conflicts(projection, with: formal) {
            report("Projection conflicts with the declaration-site variance of '\(owner)'.")
        }
        if let inner { visit(inner, substitutions: substitutions, depth: depth) }
    }

    private func resolve(_ argument: TypeArg, substitutions: [SymbolID: TypeArg], seen: Set<SymbolID> = []) -> TypeArg {
        let (projection, inner) = split(argument)
        guard let projection, let inner,
              case let .typeParam(parameter) = types.kind(of: inner),
              !seen.contains(parameter.symbol), let replacement = substitutions[parameter.symbol]
        else { return argument }
        let resolved = resolve(replacement, substitutions: substitutions, seen: seen.union([parameter.symbol]))
        let (replacementProjection, replacementType) = split(resolved)
        guard let replacementProjection, let replacementType else { return .star }
        if conflicts(projection, with: replacementProjection) {
            report("Conflicting projections in typealias expansion.")
        }
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

    private func conflicts(_ projection: TypeVariance, with formal: TypeVariance) -> Bool {
        projection == .in && formal == .out || projection == .out && formal == .in
    }

    private func report(_ message: String) {
        diagnostics?.error("KSWIFTK-SEMA-PROJECTION-CONFLICT", message, range: range)
    }
}
