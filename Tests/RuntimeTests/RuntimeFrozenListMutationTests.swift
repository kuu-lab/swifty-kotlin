import Testing
@testable import Runtime

@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeFrozenListMutationTests {
    @Test
    func checkedBridgesRejectFrozenRootsAndViews() throws {
        let mutations: [(Int, UnsafeMutablePointer<Int>?) -> Int] = [
            { kk_mutable_collection_add_checked($0, 3, $1) },
            { kk_mutable_collection_remove_checked($0, 1, $1) },
            kk_mutable_collection_clear_checked,
            { kk_mutable_collection_addAll_checked($0, kk_emptyList(), $1) },
            { kk_mutable_collection_removeAll_checked($0, kk_emptyList(), $1) },
            { kk_mutable_collection_retainAll_checked($0, kk_emptyList(), $1) },
            { kk_mutable_list_add($0, 3, $1) },
            { kk_mutable_list_remove_checked($0, 99, $1) },
            kk_mutable_list_clear_checked,
            { kk_mutable_list_addAll_checked($0, kk_emptyList(), $1) },
            { kk_mutable_list_removeAll_checked($0, kk_emptyList(), $1) },
            { kk_mutable_list_retainAll_checked($0, kk_emptyList(), $1) },
            { kk_mutable_list_set($0, 0, 3, $1) },
            { kk_mutable_list_add_at($0, 0, 3, $1) },
            { kk_mutable_list_removeAt($0, 0, $1) },
            { kk_mutable_list_addAll_at($0, 0, kk_emptyList(), $1) },
        ]
        for mutation in mutations {
            let raw = __kk_builder_list_new(2)
            _ = kk_mutable_list_add(raw, 1, nil)
            _ = kk_mutable_list_add(raw, 2, nil)
            let sub = kk_list_subList(raw, 0, 1, nil)
            let reversed = kk_list_as_reversed(sub)
            let nested = kk_list_subList(reversed, 0, 1, nil)
            let views = [raw, sub, reversed, nested]
            _ = __kk_builder_list_freeze(raw)
            for view in views {
                var thrown = 123
                _ = mutation(view, &thrown)
                let exception = try #require(runtimeThrowableBox(from: thrown))
                #expect(runtimeThrowableBoxHasExactType(exception, RuntimeUnsupportedOperationExceptionBox.self))
                #expect(runtimeListBox(from: raw)?.elements == [1, 2])
                #expect(runtimeListBox(from: view)?.count == (view == raw ? 2 : 1))
            }
        }
    }

    @Test
    func frozenIteratorRejectionPreservesCursorAndSnapshot() throws {
        for mutation in [
            runtimeListIteratorRemove,
            { runtimeListIteratorSet($0, 3, $1) },
            { runtimeListIteratorAdd($0, 3, $1) },
        ] as [(Int, UnsafeMutablePointer<Int>?) -> Int] {
            let raw = __kk_builder_list_new(2)
            _ = kk_mutable_list_add(raw, 1, nil)
            _ = kk_mutable_list_add(raw, 2, nil)
            let iterators = [raw, kk_list_subList(raw, 0, 2, nil), kk_list_as_reversed(raw)].map { view in
                let iterator = kk_list_iterator_at(view, 0, nil)
                _ = kk_list_iterator_next(iterator, nil)
                return iterator
            }
            _ = __kk_builder_list_freeze(raw)
            for iterator in iterators {
                let box = try #require(runtimeListIteratorBox(from: iterator))
                let before = box.elements
                let index = box.index
                var thrown = 0
                _ = mutation(iterator, &thrown)
                let exception = try #require(runtimeThrowableBox(from: thrown))
                #expect(runtimeThrowableBoxHasExactType(exception, RuntimeUnsupportedOperationExceptionBox.self))
                #expect(box.elements == before)
                #expect(box.index == index)
                #expect(box.lastReturnedIndex == 0)
                #expect(runtimeListBox(from: raw)?.elements == [1, 2])
            }
        }
    }

    @Test
    func mutableViewsAndLegacySignaturesRemainUsable() {
        let raw = __kk_builder_list_new(2)
        let legacyAdd: (Int, Int) -> Int = kk_mutable_collection_add
        let legacyRemove: (Int, Int) -> Int = kk_mutable_list_remove
        let legacyClear: (Int) -> Int = kk_mutable_collection_clear
        _ = legacyAdd(raw, 1)
        _ = legacyAdd(raw, 2)
        let sub = kk_list_subList(raw, 0, 1, nil)
        var thrown = 123
        _ = kk_mutable_list_set(sub, 0, 3, &thrown)
        #expect(thrown == 0)
        #expect(runtimeListBox(from: raw)?.elements == [3, 2])
        _ = kk_mutable_collection_add_checked(raw, 4, &thrown)
        #expect(thrown == 0)
        #expect(runtimeListBox(from: raw)?.elements == [3, 2, 4])
        _ = legacyRemove(raw, 4)
        let freshSub = kk_list_subList(raw, 0, 1, nil)
        _ = kk_mutable_list_clear_checked(freshSub, &thrown)
        #expect(thrown == 0)
        #expect(runtimeListBox(from: raw)?.elements == [2])
        _ = legacyClear(raw)
        #expect(kk_list_size(raw) == 0)
    }

    @Test
    func checkedBridgesRejectStructurallyInvalidViews() throws {
        let mutations: [(Int, UnsafeMutablePointer<Int>?) -> Int] = [
            { kk_mutable_collection_add_checked($0, 3, $1) },
            { kk_mutable_collection_remove_checked($0, 1, $1) },
            kk_mutable_collection_clear_checked,
            { kk_mutable_collection_addAll_checked($0, kk_emptyList(), $1) },
            { kk_mutable_collection_removeAll_checked($0, kk_emptyList(), $1) },
            { kk_mutable_collection_retainAll_checked($0, kk_emptyList(), $1) },
            { kk_mutable_list_remove_checked($0, 1, $1) },
            kk_mutable_list_clear_checked,
            { kk_mutable_list_addAll_checked($0, kk_emptyList(), $1) },
            { kk_mutable_list_removeAll_checked($0, kk_emptyList(), $1) },
            { kk_mutable_list_retainAll_checked($0, kk_emptyList(), $1) },
            { kk_mutable_list_remove_dispatch($0, 1, $1) },
        ]
        for mutation in mutations {
            let raw = __kk_builder_list_new(2)
            _ = kk_mutable_list_add(raw, 1, nil)
            _ = kk_mutable_list_add(raw, 2, nil)
            let sub = kk_list_subList(raw, 0, 1, nil)
            let reversed = kk_list_as_reversed(sub)
            let nested = kk_list_subList(reversed, 0, 1, nil)
            _ = kk_mutable_list_removeAt(raw, 0, nil)
            _ = kk_mutable_list_removeAt(raw, 0, nil)
            for view in [sub, reversed, nested] {
                var thrown = 123
                _ = mutation(view, &thrown)
                let exception = try #require(runtimeThrowableBox(from: thrown))
                #expect(runtimeThrowableBoxHasExactType(exception, RuntimeConcurrentModificationExceptionBox.self))
                #expect(runtimeListBox(from: raw)?.elements == [])
            }
        }
    }
}
