import Testing
@testable import Runtime

@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeListViewConformanceTests {
    private func isType(_ raw: Int, _ name: String) -> Bool {
        let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.\(name)")
        return kk_op_is(raw, Int(6 | (id << 9))) == 1
    }

    @Test
    func subListsPreserveMutableAndRandomAccessInterfaces() {
        let raw = registerRuntimeObject(RuntimeListBox(elements: [1, 2, 3]), typeID: arrayListRuntimeTypeID)
        let sub = kk_list_subList(raw, 0, 2, nil)
        let nested = kk_list_subList(sub, 0, 1, nil)
        for view in [sub, nested] {
            for name in ["MutableList", "MutableCollection", "List", "Collection", "Iterable", "RandomAccess"] {
                #expect(isType(view, name))
            }
            #expect(!isType(view, "ArrayList"))
            #expect(!isType(view, "Set"))
        }
        let deque = __kk_arraydeque_new()
        _ = __kk_arraydeque_addLast(deque, 1)
        let dequeSub = kk_list_subList(deque, 0, 1, nil)
        #expect(isType(dequeSub, "MutableList"))
        #expect(!isType(dequeSub, "RandomAccess"))
    }

    @Test
    func reversedOverloadsHaveDistinctMutabilityWithoutRandomAccess() {
        let raw = registerRuntimeObject(RuntimeListBox(elements: [1, 2, 3]), typeID: arrayListRuntimeTypeID)
        let mutable = kk_mutable_list_as_reversed(raw)
        let readOnly = kk_list_as_reversed(raw)
        for view in [mutable, readOnly] {
            #expect(isType(view, "List"))
            #expect(!isType(view, "RandomAccess"))
            #expect(!isType(view, "ArrayList"))
        }
        #expect(isType(mutable, "MutableList"))
        #expect(!isType(readOnly, "MutableList"))
        #expect(isType(kk_list_subList(mutable, 0, 1, nil), "MutableList"))
        #expect(!isType(kk_list_subList(readOnly, 0, 1, nil), "MutableList"))
        var thrown = 0
        _ = kk_mutable_list_set(mutable, 0, 9, &thrown)
        #expect(thrown == 0)
        #expect(runtimeListBox(from: raw)?.elements == [1, 2, 9])
    }
}
