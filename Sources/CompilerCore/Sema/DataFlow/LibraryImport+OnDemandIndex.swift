import Foundation

extension DataFlowSemaPhase {
    final class IndexedLibrarySource: IndexedLibraryEntryProvider {
        let importOrder: Int
        let isStdlibArtifact: Bool

        private let indexedFile: IndexedMetadataFile
        private let interner: StringInterner
        private let moduleFQN: InternedString?
        private weak var symbols: SymbolTable?
        private let registerEntry: (Int, (String) -> String?) -> SymbolID?
        private let rejectedIndices: Set<Int>

        init(
            importOrder: Int,
            indexedFile: IndexedMetadataFile,
            interner: StringInterner,
            moduleFQN: InternedString?,
            isStdlibArtifact: Bool,
            symbols: SymbolTable,
            rejectedEntryIndices: Set<Int> = [],
            registerEntry: @escaping (Int, (String) -> String?) -> SymbolID?
        ) {
            self.importOrder = importOrder
            self.indexedFile = indexedFile
            self.interner = interner
            self.moduleFQN = moduleFQN
            self.isStdlibArtifact = isStdlibArtifact
            self.symbols = symbols
            self.rejectedIndices = rejectedEntryIndices
            self.claimed = rejectedEntryIndices
            self.registerEntry = registerEntry
        }

        private static let machineryKinds: Set<SymbolKind> = [
            .valueParameter, .typeParameter, .backingField, .local, .label,
        ]
        private static let packageOwnerKinds: Set<SymbolKind> = [
            .class, .interface, .object, .enumClass, .annotationClass,
            .typeAlias, .function, .property, .constructor,
        ]
        private static let initializerOwnerKinds: Set<SymbolKind> = [
            .object, .class, .interface, .annotationClass, .enumClass,
        ]

        private var claimed: Set<Int> = []
        private var drainedFQNames: Set<String> = []
        private var drainedParents: Set<String> = []
        private var drainedShortNames: Set<String> = []
        private var drainedTypeParameterOwners: Set<String> = []
        private var expectEntriesDrained = false
        private var pendingLinks: [Substring: LinkTarget] = [:]
        private var linksBuilt = false
        private var childPackagePrefixesByParent: [String: [[InternedString]]] = [:]
        private var nestedEntriesByFQName: [String: Bool] = [:]
        private var stdlibMemberKeysCache: Set<BundledMemberKey>?

        enum LinkTarget {
            case symbol(Int)
            case defaultStub(Int)
            case propertyGetter(Int)
        }

        private func render(_ fqName: [InternedString]) -> String {
            fqName.map { interner.resolve($0) }.joined(separator: ".")
        }

        @discardableResult
        private func claim(index: Int) -> SymbolID? {
            guard claimed.insert(index).inserted else { return nil }
            return registerEntry(index) { [indexedFile] fqName in
                indexedFile.nominalTypeParametersSignature(forFQName: fqName)
            }
        }

        private func buildLinkMapIfNeeded() {
            guard !linksBuilt else { return }
            linksBuilt = true
            for (index, entry) in indexedFile.entries.enumerated() {
                guard let record = entry.compactRecord, !rejectedIndices.contains(index) else { continue }
                if let link = record.externalLinkName, !link.isEmpty {
                    pendingLinks[Substring(link)] = .symbol(index)
                }
                if let link = record.defaultStubExternalLinkName, !link.isEmpty {
                    pendingLinks[Substring(link)] = .defaultStub(index)
                }
                if let link = record.propertyGetterExternalLinkName, !link.isEmpty {
                    pendingLinks[Substring(link)] = .propertyGetter(index)
                }
            }
        }

        private func hasClaimableEntry(fqName: String) -> Bool {
            for position in indexedFile.fQNameRange(matching: fqName) {
                let index = indexedFile.entryIndex(sortedByFQNameAt: position)
                if !rejectedIndices.contains(index) { return true }
            }
            return false
        }

        private func hasCompanionObject(fqName: String) -> Bool {
            for position in indexedFile.fQNameRange(matching: fqName) {
                let index = indexedFile.entryIndex(sortedByFQNameAt: position)
                guard !rejectedIndices.contains(index),
                      let kind = indexedFile.entries[index].compactRecord?.kind
                else { continue }
                if kind == .object || kind == .class || kind == .interface { return true }
            }
            return false
        }

        private func packagePrefixNames(under parentFQName: String) -> Set<String> {
            guard !parentFQName.isEmpty else { return [] }
            let searchPrefix = parentFQName + "."
            var packagePrefixes: Set<String> = []
            var constructorParents: Set<String> = []
            for position in indexedFile.fQNamePrefixRange(searchPrefix) {
                let index = indexedFile.entryIndex(sortedByFQNameAt: position)
                guard !rejectedIndices.contains(index),
                      let record = indexedFile.entries[index].compactRecord,
                      Self.packageOwnerKinds.contains(record.kind)
                else { continue }
                var cursor = Substring(record.fqName)
                var isDirectParent = true
                while let dot = cursor.lastIndex(of: ".") {
                    let prefix = cursor[..<dot]
                    if prefix == parentFQName { break }
                    if record.kind == .constructor, isDirectParent {
                        constructorParents.insert(String(prefix))
                    } else {
                        packagePrefixes.insert(String(prefix))
                    }
                    isDirectParent = false
                    cursor = prefix
                }
            }
            for candidate in constructorParents where !hasClaimableEntry(fqName: candidate) {
                packagePrefixes.insert(candidate)
            }
            return packagePrefixes
        }

        private func allPackagePrefixNames() -> Set<String> {
            var entryFQNames: Set<String> = []
            var packagePrefixes: Set<String> = []
            var constructorParents: Set<String> = []
            for (index, entry) in indexedFile.entries.enumerated() {
                guard let record = entry.compactRecord, !rejectedIndices.contains(index) else { continue }
                entryFQNames.insert(record.fqName)
                guard Self.packageOwnerKinds.contains(record.kind) else { continue }
                var cursor = Substring(record.fqName)
                var isDirectParent = true
                while let dot = cursor.lastIndex(of: ".") {
                    let prefix = cursor[..<dot]
                    if record.kind == .constructor, isDirectParent {
                        constructorParents.insert(String(prefix))
                    } else {
                        packagePrefixes.insert(String(prefix))
                    }
                    isDirectParent = false
                    cursor = prefix
                }
            }
            for candidate in constructorParents where !entryFQNames.contains(candidate) {
                packagePrefixes.insert(candidate)
            }
            return packagePrefixes
        }

        func drainEntries(fqName: [InternedString]) {
            let name = render(fqName)
            guard drainedFQNames.insert(name).inserted else { return }
            for position in indexedFile.fQNameRange(matching: name) {
                let index = indexedFile.entryIndex(sortedByFQNameAt: position)
                guard !rejectedIndices.contains(index) else { continue }
                claim(index: index)
            }
        }

        func drainChildren(parentFQName: [InternedString]) {
            let parent = render(parentFQName)
            guard drainedParents.insert(parent).inserted else { return }
            var indexes: Set<Int> = []
            if parent.isEmpty {
                for (index, entry) in indexedFile.entries.enumerated() {
                    guard !rejectedIndices.contains(index),
                          let record = entry.compactRecord,
                          !record.fqName.contains(".")
                    else { continue }
                    indexes.insert(index)
                }
            } else {
                for position in indexedFile.fQNamePrefixRange(parent + ".") {
                    let index = indexedFile.entryIndex(sortedByFQNameAt: position)
                    guard !rejectedIndices.contains(index),
                          let record = indexedFile.entries[index].compactRecord,
                          record.fqName.lastIndex(of: ".").map({ String(record.fqName[..<$0]) }) == parent
                    else { continue }
                    indexes.insert(index)
                }
            }
            for position in indexedFile.receiverOwnerRange(matching: parent) {
                let index = indexedFile.entryIndex(sortedByReceiverOwnerAt: position)
                if !rejectedIndices.contains(index) { indexes.insert(index) }
            }
            for index in indexes.sorted() {
                claim(index: index)
            }
        }

        func drainEntries(shortName: InternedString) {
            let name = interner.resolve(shortName)
            guard drainedShortNames.insert(name).inserted else { return }
            for position in indexedFile.shortNameRange(matching: name) {
                let index = indexedFile.entryIndex(sortedByShortNameAt: position)
                guard !rejectedIndices.contains(index),
                      let record = indexedFile.entries[index].compactRecord,
                      !Self.machineryKinds.contains(record.kind)
                else { continue }
                claim(index: index)
            }
        }

        func drainExpectEntries() {
            guard !expectEntriesDrained else { return }
            expectEntriesDrained = true
            for index in indexedFile.entries.indices {
                guard let record = indexedFile.entries[index].compactRecord,
                      record.isExpect
                else { continue }
                claim(index: index)
            }
        }

        func eagerInitializerLinks(
            markingSeenOwners seenOwners: inout Set<String>
        ) -> IndexedLibraryInitializerLinks {
            var result = IndexedLibraryInitializerLinks()
            for (index, entry) in indexedFile.entries.enumerated() {
                guard !rejectedIndices.contains(index),
                      let record = entry.compactRecord,
                      Self.initializerOwnerKinds.contains(record.kind),
                      seenOwners.insert(record.fqName).inserted
                else { continue }

                switch record.kind {
                case .object:
                    if let link = record.objectInitializerLinkName, !link.isEmpty {
                        result.beforeEnumEntries.append(link)
                    }
                case .class, .interface, .annotationClass, .enumClass:
                    if let companionFQName = record.companionObjectFQName,
                       hasCompanionObject(fqName: companionFQName),
                       let link = record.companionInitializerLinkName,
                       !link.isEmpty
                    {
                        result.beforeEnumEntries.append(link)
                    }
                    if record.kind == .enumClass,
                       let link = record.enumStaticInitLinkName,
                       !link.isEmpty
                    {
                        result.enumStatic.append(link)
                    }
                default:
                    break
                }
            }
            return result
        }

        func containsEntriesNested(under fqName: [InternedString]) -> Bool {
            let path = render(fqName)
            if let cached = nestedEntriesByFQName[path] { return cached }
            for position in indexedFile.fQNamePrefixRange(path + ".") {
                let index = indexedFile.entryIndex(sortedByFQNameAt: position)
                guard !rejectedIndices.contains(index),
                      let record = indexedFile.entries[index].compactRecord,
                      Self.packageOwnerKinds.contains(record.kind)
                else { continue }
                let directParent = record.fqName.lastIndex(of: ".")
                    .map { String(record.fqName[..<$0]) }
                if record.kind == .constructor, directParent == path {
                    if !hasClaimableEntry(fqName: path) {
                        nestedEntriesByFQName[path] = true
                        return true
                    }
                } else {
                    nestedEntriesByFQName[path] = true
                    return true
                }
            }
            nestedEntriesByFQName[path] = false
            return false
        }

        func packagePrefixes(under parentFQName: [InternedString]) -> [[InternedString]] {
            let parent = render(parentFQName)
            if let cached = childPackagePrefixesByParent[parent] { return cached }
            let prefix = parent + "."
            let packagePrefixes = packagePrefixNames(under: parent)
            var result: [[InternedString]] = []
            for packagePrefix in packagePrefixes {
                guard packagePrefix.hasPrefix(prefix) else { continue }
                let remainder = packagePrefix.dropFirst(prefix.count)
                guard !remainder.isEmpty, !remainder.contains(".") else { continue }
                result.append(packagePrefix.split(separator: ".").map { interner.intern(String($0)) })
            }
            // `packagePrefixes` is a set; sort so claim order — and therefore
            // byFQName order — is deterministic.
            let sorted = result.sorted { render($0) < render($1) }
            childPackagePrefixesByParent[parent] = sorted
            return sorted
        }

        func packageModuleFQN(for fqName: [InternedString]) -> InternedString? {
            containsEntriesNested(under: fqName) ? moduleFQN : nil
        }

        func materializeAll(into symbols: SymbolTable) {
            for index in indexedFile.entries.indices {
                claim(index: index)
            }
            for prefix in allPackagePrefixNames().sorted() {
                let fqName = prefix.split(separator: ".").map { interner.intern(String($0)) }
                _ = symbols.lookupAll(fqName: fqName)
            }
        }

        func resolveLinkName(_ name: String) -> SymbolID? {
            buildLinkMapIfNeeded()
            guard let target = pendingLinks.removeValue(forKey: Substring(name)),
                  let symbols
            else { return nil }
            switch target {
            case let .symbol(index):
                return claim(index: index)
            case let .defaultStub(index):
                return claim(index: index).map(SyntheticSymbolScheme.defaultStubSymbol)
            case let .propertyGetter(index):
                guard let property = claim(index: index) else {
                    return nil
                }
                symbols.ensureLazyImportedMetadataLoaded(for: property)
                return symbols.extensionPropertyGetterAccessor(for: property)
            }
        }

        func pendingCallableCount(fqName: [InternedString]) -> Int {
            let name = render(fqName)
            return indexedFile.fQNameRange(matching: name).reduce(0) { count, position in
                let index = indexedFile.entryIndex(sortedByFQNameAt: position)
                guard !claimed.contains(index),
                      !rejectedIndices.contains(index),
                      let kind = indexedFile.entries[index].compactRecord?.kind,
                      kind == .function || kind == .constructor
                else { return count }
                return count + 1
            }
        }

        func claimTypeParameterSymbols(forOwner fqName: [InternedString]) -> [SymbolID] {
            let owner = render(fqName)
            guard drainedTypeParameterOwners.insert(owner).inserted else { return [] }
            let prefix = owner + ".$"
            var indexes: [Int] = []
            for position in indexedFile.fQNamePrefixRange(prefix) {
                let index = indexedFile.entryIndex(sortedByFQNameAt: position)
                guard !rejectedIndices.contains(index),
                      let record = indexedFile.entries[index].compactRecord,
                      record.kind == .typeParameter,
                      let lastDot = record.fqName.lastIndex(of: "."),
                      let ownerIDDot = record.fqName[..<lastDot].lastIndex(of: "."),
                      record.fqName[record.fqName.index(after: ownerIDDot) ..< lastDot].hasPrefix("$"),
                      record.fqName[..<ownerIDDot] == owner
                else { continue }
                indexes.append(index)
            }
            return indexes.sorted().compactMap { claim(index: $0) }
        }

        func memberKeys() -> Set<BundledMemberKey> {
            if let cached = stdlibMemberKeysCache { return cached }
            var keys: Set<BundledMemberKey> = []
            keys.reserveCapacity(indexedFile.entries.count)
            for (index, entry) in indexedFile.entries.enumerated() {
                guard let record = entry.compactRecord, !rejectedIndices.contains(index)
                else { continue }
                let arity: Int
                switch record.kind {
                case .function, .constructor:
                    arity = record.arity
                case .property, .field:
                    arity = 0
                default:
                    continue
                }
                let ownerString = record.receiverOwnerFQName.flatMap { $0.isEmpty ? nil : $0 }
                    ?? record.fqName.lastIndex(of: ".").map { String(record.fqName[..<$0]) } ?? ""
                let nameString = record.fqName.lastIndex(of: ".").map { String(record.fqName[record.fqName.index(after: $0)...]) } ?? record.fqName
                let owner = ownerString.isEmpty
                    ? []
                    : ownerString.split(separator: ".").map { interner.intern(String($0)) }
                keys.insert(BundledMemberKey(
                    ownerFQName: owner,
                    name: interner.intern(nameString),
                    arity: arity
                ))
            }
            stdlibMemberKeysCache = keys
            return keys
        }
    }
}
