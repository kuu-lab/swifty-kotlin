import RuntimeABI

extension ABILoweringPass {
    /// Per-symbol predicate equivalent to membership in the set of every
    /// `kotlin.collections` list-view owner member. Evaluated on demand so the
    /// pass no longer scans the whole symbol table up front.
    struct ListViewMemberMatcher {
        let symbols: SymbolTable?
        let kotlin: InternedString
        let collections: InternedString
        let owners: Set<InternedString>
        let checkedMembers: Set<InternedString>
        let listOwners: Set<InternedString>

        func contains(_ id: SymbolID) -> Bool {
            guard let symbols, let symbol = symbols.symbol(id) else { return false }
            let fqName = symbol.fqName
            guard fqName.count == 4, fqName[0] == kotlin, fqName[1] == collections,
                  owners.contains(fqName[2])
            else { return false }
            if listOwners.contains(fqName[2]), checkedMembers.contains(symbol.name) { return false }
            return true
        }
    }

    func listViewMemberMatcher(symbols: SymbolTable?, interner: StringInterner) -> ListViewMemberMatcher {
        ListViewMemberMatcher(
            symbols: symbols,
            kotlin: interner.intern("kotlin"),
            collections: interner.intern("collections"),
            owners: Set([
                "List", "MutableList", "Collection", "MutableCollection",
                "Iterable", "MutableIterable", "AbstractList", "AbstractMutableList",
            ].map(interner.intern)),
            checkedMembers: Set(["get", "set", "add", "removeAt", "subList"].map(interner.intern)),
            listOwners: Set(["List", "MutableList"].map(interner.intern))
        )
    }

    func listViewCheckedArguments(interner: StringInterner) -> [InternedString: [Int]] {
        var result: [InternedString: [Int]] = [:]
        let checkedBridges: Set<String> = [
            "__kk_list_check_modification", "__kk_list_get", "kk_list_iterator_at", "kk_list_subList",
            "__kk_list_as_reversed", "__kk_mutable_list_as_reversed",
            "__kk_mutable_list_set", "__kk_mutable_list_add", "__kk_mutable_list_add_at",
            "__kk_mutable_list_addAll_at", "__kk_mutable_list_removeAt",
        ]
        for spec in RuntimeABISpec.allFunctions where !checkedBridges.contains(spec.name) {
            let indices = spec.parameters.indices.filter {
                ["listRaw", "collRaw", "collectionRaw", "iterableRaw"].contains(spec.parameters[$0].name)
            }
            if !indices.isEmpty {
                result[interner.intern(spec.name)] = indices
            }
        }
        // For-loop bridges accept both ranges and collections.
        result[interner.intern("__kk_range_iterator")] = [0]
        result[interner.intern("__kk_range_for_in_iterator")] = [0]
        return result
    }

    func appendListViewChecks(
        arguments: [KIRExprID],
        checkedIndices: [Int],
        thrownResult: KIRExprID?,
        followingInstructions: ArraySlice<KIRInstruction>,
        checkCallee: InternedString,
        newBody: inout KIRLoweringEmitContext
    ) {
        // Reuse the original call's catch/rethrow continuation before invoking
        // the legacy bridge, which may not have an exception channel at all.
        var continuation: [KIRInstruction] = []
        var thrownSlots = Set(thrownResult.map { [$0] } ?? [])
        if thrownResult != nil {
            for instruction in followingInstructions {
                switch instruction {
                case .constValue:
                    continuation.append(instruction)
                case let .copy(from, to):
                    if thrownSlots.contains(from) { thrownSlots.insert(to) }
                    continuation.append(instruction)
                case let .jumpIfNotNull(value, _) where thrownSlots.contains(value):
                    continuation.append(instruction)
                default:
                    continuation.removeAll()
                }
                if case .jumpIfNotNull = instruction { break }
                if continuation.isEmpty { break }
            }
            if !continuation.contains(where: {
                if case .jumpIfNotNull = $0 { return true }
                return false
            }) {
                continuation.removeAll()
            }
        }
        for index in checkedIndices where arguments.indices.contains(index) {
            newBody.append(.call(
                callee: checkCallee,
                arguments: [arguments[index]],
                result: nil,
                canThrow: true,
                thrownResult: continuation.isEmpty ? nil : thrownResult
            ))
            newBody.append(contentsOf: continuation)
        }
    }
}
