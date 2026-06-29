@testable import CompilerCore
import Foundation

final class StableRenderContext {
    let sema: SemaModule
    let interner: StringInterner

    private let symbolFQ: [Int32: String]
    private let overloadSuffix: [Int32: String]
    private(set) var requiredSymbols = Set<Int32>()

    // swiftlint:disable:next force_try
    private static let typeRefRegex = try! NSRegularExpression(pattern: "(Class#|T#)(\\d+)")

    init(sema: SemaModule, interner: StringInterner) {
        self.sema = sema
        self.interner = interner

        var fqMap: [Int32: String] = [:]
        var fqGroups: [String: [SemanticSymbol]] = [:]

        for symbol in sema.symbols.allSymbols() {
            let fq = GoldenHarnessSemaFormat.renderFQName(symbol.fqName, interner: interner)
            fqMap[symbol.id.rawValue] = fq
            fqGroups[fq, default: []].append(symbol)
        }

        self.symbolFQ = fqMap

        var suffixes: [Int32: String] = [:]
        for (_, symbols) in fqGroups where symbols.count > 1 {
            let sorted = symbols.sorted { a, b in
                Self.overloadSortKey(a, sema: sema, fqMap: fqMap) < Self.overloadSortKey(b, sema: sema, fqMap: fqMap)
            }
            for (idx, sym) in sorted.enumerated() {
                suffixes[sym.id.rawValue] = "#\(idx)"
            }
        }
        self.overloadSuffix = suffixes
    }

    func stableKey(for symbolID: SymbolID) -> String {
        let fq = symbolFQ[symbolID.rawValue] ?? "_"
        let suffix = overloadSuffix[symbolID.rawValue] ?? ""
        return fq + suffix
    }

    func requireSymbol(_ symbolID: SymbolID) {
        requiredSymbols.insert(symbolID.rawValue)
    }

    func renderType(_ typeID: TypeID) -> String {
        let raw = sema.types.renderType(typeID)
        return stabilizeTypeRefs(in: raw)
    }

    func renderSignature(_ signature: FunctionSignature) -> String {
        let raw = GoldenHarnessSemaFormat.renderFunctionSignature(signature, types: sema.types)
        return stabilizeTypeRefs(in: raw)
    }

    func expandRequiredSymbols() {
        var queue = Array(requiredSymbols)
        var visited = Set<Int32>()
        while !queue.isEmpty {
            let rawID = queue.removeFirst()
            guard visited.insert(rawID).inserted else { continue }
            let symID = SymbolID(rawValue: rawID)
            if let sig = sema.symbols.functionSignature(for: symID) {
                collectTypeSymbols(sig.receiverType, into: &queue)
                for paramType in sig.parameterTypes {
                    collectTypeSymbols(paramType, into: &queue)
                }
                collectTypeSymbols(sig.returnType, into: &queue)
                for bounds in sig.typeParameterUpperBoundsList {
                    for bound in bounds {
                        collectTypeSymbols(bound, into: &queue)
                    }
                }
                for tpSym in sig.typeParameterSymbols {
                    if requiredSymbols.insert(tpSym.rawValue).inserted {
                        queue.append(tpSym.rawValue)
                    }
                }
                for vpSym in sig.valueParameterSymbols {
                    if requiredSymbols.insert(vpSym.rawValue).inserted {
                        queue.append(vpSym.rawValue)
                    }
                }
            }
            if let propType = sema.symbols.propertyType(for: symID) {
                collectTypeSymbols(propType, into: &queue)
            }
        }
        requiredSymbols = visited
    }

    // MARK: - Private

    private func stabilizeTypeRefs(in text: String) -> String {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = Self.typeRefRegex.matches(in: text, range: range)
        guard !matches.isEmpty else { return text }

        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            let idRange = match.range(at: 2)
            guard idRange.location != NSNotFound,
                  let rawID = Int32(nsText.substring(with: idRange)),
                  let fq = symbolFQ[rawID]
            else { continue }
            requiredSymbols.insert(rawID)
            mutable.replaceCharacters(in: match.range, with: fq)
        }
        return mutable as String
    }

    private func collectTypeSymbols(_ typeID: TypeID?, into queue: inout [Int32]) {
        guard let typeID else { return }
        switch sema.types.kind(of: typeID) {
        case let .classType(ct):
            if requiredSymbols.insert(ct.classSymbol.rawValue).inserted {
                queue.append(ct.classSymbol.rawValue)
            }
            for arg in ct.args {
                switch arg {
                case let .invariant(t), let .out(t), let .in(t):
                    collectTypeSymbols(t, into: &queue)
                case .star:
                    break
                }
            }
        case let .typeParam(tp):
            if requiredSymbols.insert(tp.symbol.rawValue).inserted {
                queue.append(tp.symbol.rawValue)
            }
        case let .functionType(ft):
            for cr in ft.contextReceivers { collectTypeSymbols(cr, into: &queue) }
            collectTypeSymbols(ft.receiver, into: &queue)
            for p in ft.params { collectTypeSymbols(p, into: &queue) }
            collectTypeSymbols(ft.returnType, into: &queue)
        case let .kClassType(kc):
            collectTypeSymbols(kc.argument, into: &queue)
        case let .intersection(parts):
            for part in parts { collectTypeSymbols(part, into: &queue) }
        case .error, .unit, .nothing, .any, .primitive, .stringStruct:
            break
        }
    }

    private static func overloadSortKey(
        _ symbol: SemanticSymbol,
        sema: SemaModule,
        fqMap: [Int32: String]
    ) -> String {
        guard let sig = sema.symbols.functionSignature(for: symbol.id) else {
            return ""
        }
        let recv = sig.receiverType.map { stabilizeTypeRefsStatic(sema.types.renderType($0), fqMap: fqMap) } ?? "_"
        let params = sig.parameterTypes.map { stabilizeTypeRefsStatic(sema.types.renderType($0), fqMap: fqMap) }
        return "\(recv)|\(params.joined(separator: ","))"
    }

    private static func stabilizeTypeRefsStatic(_ text: String, fqMap: [Int32: String]) -> String {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = typeRefRegex.matches(in: text, range: range)
        guard !matches.isEmpty else { return text }

        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            let idRange = match.range(at: 2)
            guard idRange.location != NSNotFound,
                  let rawID = Int32(nsText.substring(with: idRange)),
                  let fq = fqMap[rawID]
            else { continue }
            mutable.replaceCharacters(in: match.range, with: fq)
        }
        return mutable as String
    }
}
