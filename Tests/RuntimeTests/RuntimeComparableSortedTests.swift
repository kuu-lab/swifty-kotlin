import Foundation
@testable import Runtime
import Testing

// BUG-161: sorting a list of user-defined `Comparable` implementations used to
// dispatch `compareTo` through a two-argument function pointer, so the callee
// read the thrown-channel pointer from an uninitialized register and crashed
// with SIGSEGV. Compiler-emitted members follow the
// `(receiver, args..., outThrown)` ABI and may return a boxed `Int`, which is
// what the trampolines below emulate.

private let userClassTypeID: Int64 = runtimeStableNominalTypeID(fqName: "test.Version")
private let comparableTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.Comparable")
private let comparableInterfaceSlot = 1

private func userValue(_ raw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let box = tryCast(ptr, to: RuntimeObjectBox.self)
    else {
        return Int.min
    }
    return box.elements[0]
}

private let userCompareTo: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { receiver, other, outThrown in
    outThrown?.pointee = 0
    let lhs = userValue(receiver)
    let rhs = userValue(other)
    if lhs == rhs { return kk_box_int(0) }
    return kk_box_int(lhs < rhs ? -1 : 1)
}

private func makeUserComparable(_ value: Int) -> Int {
    let object = kk_object_new(1, 0)
    if let payload = UnsafeMutableRawPointer(bitPattern: object),
       let box = tryCast(payload, to: RuntimeObjectBox.self)
    {
        box.elements[0] = value
    }
    runtimeRegisterObjectType(rawValue: object, classID: userClassTypeID)
    runtimeRegisterTypeEdge(childTypeID: userClassTypeID, parentTypeID: comparableTypeID)
    _ = kk_object_register_itable_iface(object, Int(comparableTypeID), comparableInterfaceSlot)
    _ = kk_object_register_itable_method(
        object,
        comparableInterfaceSlot,
        0,
        unsafeBitCast(userCompareTo, to: Int.self)
    )
    return object
}

private func sortedUserValues(_ handles: [Int]) -> [Int] {
    let listRaw = registerRuntimeObject(RuntimeListBox(elements: handles))
    let sortedRaw = kk_list_sorted(listRaw)
    guard let ptr = UnsafeMutableRawPointer(bitPattern: sortedRaw),
          let box = tryCast(ptr, to: RuntimeListBox.self)
    else {
        return []
    }
    return box.elements.map(userValue)
}

@Suite(.runtimeIsolation(.all))
struct RuntimeComparableSortedTests {
    @Test
    func listSortedUsesUserCompareToWithThrownChannel() {
        let handles = [makeUserComparable(2), makeUserComparable(1), makeUserComparable(3)]
        #expect(sortedUserValues(handles) == [1, 2, 3])
    }

    @Test
    func compareValuesUnboxesUserCompareToResult() {
        let smaller = makeUserComparable(1)
        let larger = makeUserComparable(2)
        #expect(runtimeCompareValues(smaller, larger) == -1)
        #expect(runtimeCompareValues(larger, smaller) == 1)
        #expect(runtimeCompareValues(larger, makeUserComparable(2)) == 0)
    }
}
