import Foundation

/// The type-check result of one function body, stored without any compiler
/// IDs (KUU-3019). Expressions are addressed by their position relative to the
/// first expression of the declaration, symbols by `SnapshotSymbol`, types by
/// `SnapshotType`, so the snapshot stays valid when unrelated edits renumber
/// everything else in the program.
///
/// Only the binding maps listed in `FunctionBodySemaSnapshot.coveredBindings`
/// are captured. `BindingTable` has many more; until each is covered a
/// snapshot cannot replace type checking, which is why this type currently
/// serves capture → restore → *compare* only (see `SemaSnapshotCoverage`).
public struct FunctionBodySemaSnapshot: Codable, Equatable, Sendable {
    public struct Entry<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
        public let index: Int
        public let value: Value
    }

    /// Number of expression slots between the declaration's first and last
    /// expression; a loader whose declaration spans a different count has a
    /// different AST shape and must not use the snapshot.
    public var exprSpan: Int
    public var localSymbolCount: Int
    public var exprTypes: [Entry<SnapshotType>]
    public var identifierSymbols: [Entry<SnapshotSymbol>]
    public var callBindings: [Entry<SnapshotCallBinding>]

    /// Names of the `BindingTable` properties this snapshot reproduces.
    public static let coveredBindings: Set<String> = ["exprTypes", "identifierSymbols", "callBindings"]
}

/// Result of decoding a snapshot against a live compilation: the bindings
/// keyed by that compilation's own IDs.
struct RestoredFunctionBodyBindings {
    var exprTypes: [ExprID: TypeID] = [:]
    var identifierSymbols: [ExprID: SymbolID] = [:]
    var callBindings: [ExprID: CallBinding] = [:]
}

/// Locates a function declaration's expressions and local symbols in a
/// compilation, and converts between live bindings and snapshots.
struct FunctionBodySemaScope {
    let functionSymbol: SymbolID
    /// Expressions whose source range lies inside the declaration, ascending.
    let exprIDs: [ExprID]
    let localSymbols: [SymbolID]
    private let exprSet: Set<ExprID>
    private let lambdaExprs: Set<ExprID>

    var firstExpr: Int32? { exprIDs.first?.rawValue }

    var exprSpan: Int {
        guard let first = exprIDs.first, let last = exprIDs.last else { return 0 }
        return Int(last.rawValue - first.rawValue) + 1
    }

    init?(declID: DeclID, ast: ASTModule, sema: SemaModule) {
        guard case let .funDecl(function) = ast.arena.decl(declID),
              let symbol = sema.bindings.declSymbols[declID]
        else { return nil }
        functionSymbol = symbol
        let range = function.range
        var exprs: [ExprID] = []
        let count = ast.arena.exprs.count
        for raw in 0 ..< count {
            let id = ExprID(rawValue: Int32(raw))
            if let exprRange = ast.arena.exprRange(id), range.contains(exprRange) { exprs.append(id) }
        }
        exprIDs = exprs
        exprSet = Set(exprs)
        lambdaExprs = Set(exprs.filter { id in
            if case .lambdaLiteral = ast.arena.expr(id) { return true }
            return false
        })
        localSymbols = sema.symbols.allSymbols()
            .filter { candidate in
                guard candidate.id != symbol, let site = candidate.declSite else { return false }
                return range.contains(site)
            }
            .map(\.id)
            .sorted { $0.rawValue < $1.rawValue }
    }

    func relativeIndex(of id: ExprID) -> Int? {
        guard let first = firstExpr, exprSet.contains(id) else { return nil }
        return Int(id.rawValue - first)
    }

    func expr(atRelativeIndex index: Int) -> ExprID? {
        guard let first = firstExpr else { return nil }
        let id = ExprID(rawValue: first + Int32(index))
        return exprSet.contains(id) ? id : nil
    }

    var exprMapping: SnapshotExprMapping {
        SnapshotExprMapping(
            relativeIndex: { relativeIndex(of: $0) },
            expr: { expr(atRelativeIndex: $0) },
            isLambda: { lambdaExprs.contains($0) }
        )
    }
}

extension FunctionBodySemaSnapshot {
    /// Captures the covered bindings of `declID`'s body, or nil if any binding
    /// inside it cannot be represented (the declaration is then uncacheable).
    static func capture(
        declID: DeclID, ast: ASTModule, sema: SemaModule, interner: StringInterner
    ) -> FunctionBodySemaSnapshot? {
        guard let scope = FunctionBodySemaScope(declID: declID, ast: ast, sema: sema) else { return nil }
        let codec = SemaSnapshotCodec(
            interner: interner, symbols: sema.symbols, types: sema.types, localSymbols: scope.localSymbols,
            exprMapping: scope.exprMapping
        )
        var snapshot = FunctionBodySemaSnapshot(
            exprSpan: scope.exprSpan, localSymbolCount: scope.localSymbols.count,
            exprTypes: [], identifierSymbols: [], callBindings: []
        )
        for id in scope.exprIDs {
            guard let index = scope.relativeIndex(of: id) else { continue }
            if let type = sema.bindings.exprTypes[id] {
                guard let ref = codec.encode(type: type) else { return nil }
                snapshot.exprTypes.append(.init(index: index, value: ref))
            }
            if let symbol = sema.bindings.identifierSymbols[id] {
                guard let ref = codec.encode(symbol: symbol) else { return nil }
                snapshot.identifierSymbols.append(.init(index: index, value: ref))
            }
            if let binding = sema.bindings.callBindings[id] {
                guard let ref = codec.encode(callBinding: binding) else { return nil }
                snapshot.callBindings.append(.init(index: index, value: ref))
            }
        }
        return snapshot
    }

    /// Decodes the snapshot against the declaration `declID` of the current
    /// compilation. Returns nil when the declaration's shape does not match or
    /// any reference fails to resolve — the caller must then type-check.
    func restore(
        declID: DeclID, ast: ASTModule, sema: SemaModule, interner: StringInterner
    ) -> RestoredFunctionBodyBindings? {
        guard let scope = FunctionBodySemaScope(declID: declID, ast: ast, sema: sema),
              scope.exprSpan == exprSpan,
              scope.localSymbols.count == localSymbolCount
        else { return nil }
        let codec = SemaSnapshotCodec(
            interner: interner, symbols: sema.symbols, types: sema.types, localSymbols: scope.localSymbols,
            exprMapping: scope.exprMapping
        )
        var restored = RestoredFunctionBodyBindings()
        for entry in exprTypes {
            guard let expr = scope.expr(atRelativeIndex: entry.index), let type = codec.decode(type: entry.value)
            else { return nil }
            restored.exprTypes[expr] = type
        }
        for entry in identifierSymbols {
            guard let expr = scope.expr(atRelativeIndex: entry.index), let symbol = codec.decode(symbol: entry.value)
            else { return nil }
            restored.identifierSymbols[expr] = symbol
        }
        for entry in callBindings {
            guard let expr = scope.expr(atRelativeIndex: entry.index),
                  let binding = codec.decode(callBinding: entry.value)
            else { return nil }
            restored.callBindings[expr] = binding
        }
        return restored
    }

    /// Differences between a restored snapshot and what type checking
    /// actually produced for the same declaration. Empty means identical.
    static func differences(
        restored: RestoredFunctionBodyBindings, declID: DeclID, ast: ASTModule, sema: SemaModule
    ) -> [String] {
        guard let scope = FunctionBodySemaScope(declID: declID, ast: ast, sema: sema) else {
            return ["declaration not found"]
        }
        var problems: [String] = []
        let inScope = Set(scope.exprIDs)
        let liveTypes = sema.bindings.exprTypes.filter { inScope.contains($0.key) }
        if liveTypes != restored.exprTypes { problems.append("exprTypes differ") }
        let liveSymbols = sema.bindings.identifierSymbols.filter { inScope.contains($0.key) }
        if liveSymbols != restored.identifierSymbols { problems.append("identifierSymbols differ") }
        let liveCalls = sema.bindings.callBindings.filter { inScope.contains($0.key) }
        if Set(liveCalls.keys) != Set(restored.callBindings.keys) {
            problems.append("callBindings keys differ")
        } else {
            for (expr, live) in liveCalls {
                guard let other = restored.callBindings[expr], Self.same(live, other) else {
                    problems.append("callBinding differs at expr \(expr.rawValue)")
                    continue
                }
            }
        }
        return problems
    }

    private static func same(_ lhs: CallBinding, _ rhs: CallBinding) -> Bool {
        lhs.chosenCallee == rhs.chosenCallee
            && lhs.substitutedTypeArguments == rhs.substitutedTypeArguments
            && lhs.parameterMapping == rhs.parameterMapping
            && lhs.contextParameterArgumentMapping == rhs.contextParameterArgumentMapping
            && lhs.defaultArgumentOwner == rhs.defaultArgumentOwner
            && lhs.dispatchReceiverSymbol == rhs.dispatchReceiverSymbol
            && lhs.isCallableReferenceAdapter == rhs.isCallableReferenceAdapter
            && lhs.hidesKCallable == rhs.hidesKCallable
            && lhs.boundContextParameterTypes == rhs.boundContextParameterTypes
    }
}
