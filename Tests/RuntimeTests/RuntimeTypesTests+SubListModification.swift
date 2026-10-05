@testable import Runtime
import Testing

extension RuntimeTypesTests {
    @Test(arguments: [(3, 2), (6, 4)])
    func subListReversedBoundsThrowIllegalArgumentException(bounds: (Int, Int)) throws {
        let raw = registerRuntimeObject(RuntimeListBox(elements: [1, 2, 3, 4, 5]), typeID: listRuntimeTypeID)
        var thrown = 0
        _ = kk_list_subList(raw, bounds.0, bounds.1, &thrown)
        let pointer = try #require(UnsafeMutableRawPointer(bitPattern: thrown))
        #expect(tryCast(pointer, to: RuntimeIllegalArgumentExceptionBox.self) != nil)
    }

    @Test(arguments: ["add", "remove", "same-size"])
    func subListDetectsBackingStructuralChanges(mutation: String) throws {
        let base = RuntimeListBox(elements: [1, 2, 3, 4])
        let view = RuntimeListBox(subListOf: base, fromIndex: 1, toIndex: 3)
        let raw = registerRuntimeObject(view, typeID: listRuntimeTypeID)
        #expect(view.isValidView)
        base.withMutableValues {
            if mutation != "add" { $0.removeLast() }
        }
        if mutation != "remove" { base.withMutableValues { $0.append(RuntimeValue(raw: 5)) } }
        #expect(!view.isValidView)

        var thrown = 0
        _ = kk_list_check_modification(raw, &thrown)
        let pointer = try #require(UnsafeMutableRawPointer(bitPattern: thrown))
        #expect(tryCast(pointer, to: RuntimeConcurrentModificationExceptionBox.self) != nil)
    }

    @Test(arguments: ["get", "set", "add", "add-at", "removeAt", "iterator"])
    func subListThrowingBridgesRejectInvalidViews(operation: String) throws {
        let base = RuntimeListBox(elements: [1, 2, 3, 4])
        let view = RuntimeListBox(subListOf: base, fromIndex: 1, toIndex: 3)
        let raw = registerRuntimeObject(view, typeID: listRuntimeTypeID)
        base.withMutableValues { $0.removeAll() }
        var thrown = 0
        switch operation {
        case "get": _ = kk_list_get(raw, 0, &thrown)
        case "set": _ = kk_mutable_list_set(raw, 0, 99, &thrown)
        case "add": _ = kk_mutable_list_add(raw, 99, &thrown)
        case "add-at": _ = kk_mutable_list_add_at(raw, 0, 99, &thrown)
        case "removeAt": _ = kk_mutable_list_removeAt(raw, 0, &thrown)
        default: _ = kk_list_iterator_at(raw, 0, &thrown)
        }
        let pointer = try #require(UnsafeMutableRawPointer(bitPattern: thrown))
        #expect(tryCast(pointer, to: RuntimeConcurrentModificationExceptionBox.self) != nil)
        #expect(base.count == 0)
    }

    @Test
    func subListCreatedFromInvalidViewRemainsInvalid() {
        let base = RuntimeListBox(elements: [1, 2, 3])
        let view = RuntimeListBox(subListOf: base, fromIndex: 0, toIndex: 2)
        let raw = registerRuntimeObject(view, typeID: listRuntimeTypeID)
        base.withMutableValues { $0.append(RuntimeValue(raw: 4)) }
        var thrown = 0
        let child = kk_list_subList(raw, 0, 1, &thrown)
        #expect(thrown == 0)
        #expect(runtimeListBox(from: child)?.isValidView == false)
        _ = kk_list_check_modification(child, &thrown)
        #expect(thrown != 0)
    }

    @Test(arguments: ["get", "set", "add-at", "removeAt"])
    func subListIndexBoundsChecksPrecedeModificationChecks(operation: String) throws {
        let base = RuntimeListBox(elements: [1, 2, 3])
        let view = RuntimeListBox(subListOf: base, fromIndex: 0, toIndex: 1)
        let raw = registerRuntimeObject(view, typeID: listRuntimeTypeID)
        base.withMutableValues { $0.append(RuntimeValue(raw: 4)) }
        var thrown = 0
        switch operation {
        case "get": _ = kk_list_get(raw, 99, &thrown)
        case "set": _ = kk_mutable_list_set(raw, 99, 1, &thrown)
        case "add-at": _ = kk_mutable_list_add_at(raw, 99, 1, &thrown)
        default: _ = kk_mutable_list_removeAt(raw, 99, &thrown)
        }
        let pointer = try #require(UnsafeMutableRawPointer(bitPattern: thrown))
        #expect(tryCast(pointer, to: RuntimeIndexOutOfBoundsExceptionBox.self) != nil)
    }

    @Test
    func subListOwnMutationsRefreshExpectedCount() {
        let base = RuntimeListBox(elements: [1, 2, 3, 4])
        let view = RuntimeListBox(subListOf: base, fromIndex: 1, toIndex: 3)
        let sibling = RuntimeListBox(subListOf: base, fromIndex: 0, toIndex: 1)
        let raw = registerRuntimeObject(view, typeID: listRuntimeTypeID)
        var thrown = 0
        base.setValue(RuntimeValue(raw: 20), at: 1)
        _ = kk_mutable_list_set(raw, 1, 30, &thrown)
        #expect(thrown == 0)
        #expect(view.isValidView && sibling.isValidView)

        _ = kk_mutable_list_add(raw, 40, &thrown)
        #expect(thrown == 0)
        #expect(view.isValidView && !sibling.isValidView)
        #expect(base.elements == [1, 20, 30, 40, 4])
        _ = kk_mutable_list_removeAt(raw, 0, &thrown)
        #expect(thrown == 0)
        #expect(view.isValidView)
        #expect(view.elements == [30, 40])
        _ = kk_mutable_list_clear(raw)
        #expect(view.isValidView && view.count == 0)
        #expect(base.elements == [1, 4])
    }

    @Test
    func nestedSubListMutationsRefreshAncestorsButInvalidateOtherViews() {
        let base = RuntimeListBox(elements: [1, 2, 3, 4, 5])
        let parent = RuntimeListBox(subListOf: base, fromIndex: 1, toIndex: 4)
        let child = RuntimeListBox(subListOf: parent, fromIndex: 1, toIndex: 2)
        let sibling = RuntimeListBox(subListOf: parent, fromIndex: 0, toIndex: 1)
        child.withMutableValues { $0.append(RuntimeValue(raw: 99)) }
        #expect(child.isValidView && parent.isValidView && !sibling.isValidView)
        #expect(base.elements == [1, 2, 3, 99, 4, 5])
        #expect(parent.elements == [2, 3, 99, 4])
        parent.withMutableValues { $0.append(RuntimeValue(raw: 100)) }
        #expect(parent.isValidView && !child.isValidView)
    }

    @Test
    func subListIteratorDetectsBackingMutation() {
        let base = RuntimeListBox(elements: [1, 2, 3, 4])
        let view = RuntimeListBox(subListOf: base, fromIndex: 1, toIndex: 3)
        let raw = registerRuntimeObject(view, typeID: listRuntimeTypeID)
        let iterator = kk_list_iterator(raw)
        base.withMutableValues { $0.append(RuntimeValue(raw: 5)) }
        var thrown = 0
        _ = kk_list_iterator_next(iterator, &thrown)
        #expect(thrown != 0)
    }
}
