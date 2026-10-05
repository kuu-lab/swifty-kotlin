import RuntimeABI

extension ABILoweringPass {
    func listViewMemberSymbols(symbols: SymbolTable?, interner: StringInterner) -> Set<SymbolID> {
        guard let symbols else { return [] }
        let owners: Set<[InternedString]> = Set([
            "List", "MutableList", "Collection", "MutableCollection",
            "Iterable", "MutableIterable", "AbstractList", "AbstractMutableList",
        ].map { ["kotlin", "collections", $0].map(interner.intern) })
        let checkedMembers: Set<InternedString> = Set(["get", "set", "add", "removeAt", "subList"].map(interner.intern))
        let listOwners: Set<InternedString> = Set(["List", "MutableList"].map(interner.intern))
        return Set(symbols.allSymbols().compactMap {
            guard owners.contains(Array($0.fqName.dropLast())) else { return nil }
            if listOwners.contains($0.fqName[2]), checkedMembers.contains($0.name) { return nil }
            return $0.id
        })
    }

    func listViewCheckedArguments(interner: StringInterner) -> [InternedString: [Int]] {
        var result: [InternedString: [Int]] = [:]
        let checkedBridges: Set<String> = [
            "__kk_list_check_modification", "__kk_list_get", "kk_list_iterator_at", "kk_list_subList",
            "__kk_list_as_reversed",
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
        result[interner.intern("kk_range_iterator")] = [0]
        result[interner.intern("kk_range_for_in_iterator")] = [0]
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
                symbol: nil,
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
