@testable import CompilerCore
import Foundation

/// The classification deliberately does NOT trust `declSite` or the
/// `synthetic` flag as identity: reused compatibility shells for bundled
/// nominals keep `declSite == nil` while still tracking a bundled
/// `sourceFileID`, and fixture code
/// synthesizes declarations (data-class members, object literals, accessors)
/// that are still fixture-owned. Instead it uses registration-time facts that
/// production semantics do not depend on:
///
///   1. `SymbolTable.sourceFileID` — recorded at declaration collection for
///      every source-declared symbol — mapped through `SourceManager.origin`.
///   2. `declSite`'s file — the declared range's home file.
///   3. `.importedLibrary` — set when a symbol comes from a compiled library.
///   4. The source-backed member-alias shape (KSP-443): a nil-site synthetic
///      function sharing parent + signature + `externalLinkName` with a
///      source-backed sibling.
///   5. `parentSymbol` chains for parameters / accessors / nested decls.
///   6. Package membership: a nil-site symbol under a package whose declared
///      members come from bundled sources is a bundled synthetic stub.
enum GoldenSymbolOrigin: String, Sendable {
    case fixture
    case bundledSource
    case stdlibStub
    case sourceBackedAlias
    case importedLibrary
    case unknown
}

final class GoldenSymbolOriginClassifier {
    private let sema: SemaModule
    private let sourceManager: SourceManager
    private var memo: [Int32: GoldenSymbolOrigin] = [:]
    private var sourceBackedFunctionsByName: [InternedString: [SemanticSymbol]]?

    init(sema: SemaModule, sourceManager: SourceManager) {
        self.sema = sema
        self.sourceManager = sourceManager
    }

    func origin(of symbolID: SymbolID) -> GoldenSymbolOrigin {
        if let cached = memo[symbolID.rawValue] {
            return cached
        }
        memo[symbolID.rawValue] = .unknown
        let resolved = resolveOrigin(of: symbolID)
        memo[symbolID.rawValue] = resolved
        return resolved
    }

    func sourceBackedAliasTarget(of symbolID: SymbolID) -> SymbolID? {
        guard origin(of: symbolID) == .sourceBackedAlias,
              let symbol = sema.symbols.symbol(symbolID)
        else {
            return nil
        }
        let candidates = sourceBackedAliasCandidates(for: symbol)
            .filter { origin(of: $0.id) == .bundledSource }
        guard candidates.count == 1 else { return nil }
        return candidates[0].id
    }

    private func resolveOrigin(of symbolID: SymbolID) -> GoldenSymbolOrigin {
        guard let symbol = sema.symbols.symbol(symbolID) else {
            return .unknown
        }

        if let fileID = sema.symbols.sourceFileID(for: symbolID) ?? symbol.declSite?.start.file {
            switch sourceManager.origin(of: fileID) {
            case .user:
                return .fixture
            case .bundledStdlib, .residualStdlib:
                return .bundledSource
            case nil:
                return .unknown
            }
        }

        if symbol.flags.contains(.importedLibrary) {
            return .importedLibrary
        }

        if isSourceBackedMemberAlias(symbol) {
            return .sourceBackedAlias
        }

        if let parent = sema.symbols.parentSymbol(for: symbolID),
           let parentSymbol = sema.symbols.symbol(parent),
           parentSymbol.kind != .package {
            let parentOrigin = origin(of: parent)
            if parentOrigin != .unknown {
                return parentOrigin
            }
        }

        if case let packageOrigin = packageHomeOrigin(of: Array(symbol.fqName.dropLast())),
           packageOrigin == .bundledSource {
            return .stdlibStub
        }

        return .unknown
    }

    private func isSourceBackedMemberAlias(_ symbol: SemanticSymbol) -> Bool {
        guard symbol.kind == .function,
              symbol.declSite == nil,
              symbol.flags.contains(.synthetic)
        else {
            return false
        }
        if sourceBackedFunctionsByName == nil {
            var index: [InternedString: [SemanticSymbol]] = [:]
            for candidate in sema.symbols.allSymbols()
            where candidate.kind == .function
                && !candidate.flags.contains(.synthetic)
                && candidate.declSite != nil {
                index[candidate.name, default: []].append(candidate)
            }
            sourceBackedFunctionsByName = index
        }
        return !sourceBackedAliasCandidates(for: symbol).isEmpty
    }

    private func sourceBackedAliasCandidates(for symbol: SemanticSymbol) -> [SemanticSymbol] {
        guard let parent = sema.symbols.parentSymbol(for: symbol.id),
              let signature = sema.symbols.functionSignature(for: symbol.id),
              let linkName = sema.symbols.externalLinkName(for: symbol.id),
              !linkName.isEmpty
        else {
            return []
        }
        return (sourceBackedFunctionsByName?[symbol.name] ?? []).filter { candidate in
            candidate.id != symbol.id
                && candidate.fqName != symbol.fqName
                && sema.symbols.parentSymbol(for: candidate.id) == parent
                && sema.symbols.functionSignature(for: candidate.id) == signature
                && sema.symbols.externalLinkName(for: candidate.id) == linkName
                && origin(of: candidate.id) == .bundledSource
        }
    }

    private func packageHomeOrigin(of packageFQName: [InternedString]) -> GoldenSymbolOrigin {
        guard !packageFQName.isEmpty else { return .unknown }
        let members = sema.symbols.children(ofFQName: packageFQName)
        var sawUser = false
        for memberID in members {
            guard let member = sema.symbols.symbol(memberID) else { continue }
            if let fileID = sema.symbols.sourceFileID(for: memberID) ?? member.declSite?.start.file {
                switch sourceManager.origin(of: fileID) {
                case .user:
                    sawUser = true
                case .bundledStdlib, .residualStdlib:
                    return .bundledSource
                case nil:
                    continue
                }
            }
        }
        return sawUser ? .fixture : .unknown
    }
}
