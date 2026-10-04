import Foundation
@testable import Runtime
import Testing

// BUG-170: comparison operators on an erased `T : Comparable<T>` receiver lower
// to `kk_compare_any`, which used to require both operands to have the exact
// same runtime type. Subclass/base pairs and siblings sharing a Comparable
// interface therefore fell through to raw heap-address comparison instead of
// the user `compareTo`. Unrelated Comparable classes must still fall back,
// because their `compareTo` parameter types are incompatible.

private let comparableTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.Comparable")
private let rankedTypeID: Int64 = runtimeStableNominalTypeID(fqName: "test.Ranked")
private let bronzeTypeID: Int64 = runtimeStableNominalTypeID(fqName: "test.Bronze")
private let goldTypeID: Int64 = runtimeStableNominalTypeID(fqName: "test.Gold")
private let animalTypeID: Int64 = runtimeStableNominalTypeID(fqName: "test.Animal")
private let elephantTypeID: Int64 = runtimeStableNominalTypeID(fqName: "test.Elephant")
private let moneyTypeID: Int64 = runtimeStableNominalTypeID(fqName: "test.Money")
private let comparableInterfaceSlot = 1

private nonisolated(unsafe) var compareToInvocations = 0

private func objectValue(_ raw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let box = tryCast(ptr, to: RuntimeObjectBox.self)
    else {
        return Int.min
    }
    return box.elements[0]
}

private let valueCompareTo: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { receiver, other, outThrown in
    outThrown?.pointee = 0
    compareToInvocations += 1
    let lhs = objectValue(receiver)
    let rhs = objectValue(other)
    if lhs == rhs { return kk_box_int(0) }
    return kk_box_int(lhs < rhs ? -1 : 1)
}

private func makeComparable(value: Int, typeID: Int64, supertypes: [Int64]) -> Int {
    let object = kk_object_new(1, 0)
    if let payload = UnsafeMutableRawPointer(bitPattern: object),
       let box = tryCast(payload, to: RuntimeObjectBox.self)
    {
        box.elements[0] = value
    }
    runtimeRegisterObjectType(rawValue: object, classID: typeID)
    for supertype in supertypes {
        runtimeRegisterTypeEdge(childTypeID: typeID, parentTypeID: supertype)
    }
    _ = kk_object_register_itable_iface(object, Int(comparableTypeID), comparableInterfaceSlot)
    _ = kk_object_register_itable_method(
        object,
        comparableInterfaceSlot,
        0,
        unsafeBitCast(valueCompareTo, to: Int.self)
    )
    return object
}

// `Bronze`/`Gold` both implement `Ranked : Comparable<Ranked>`.
private func makeBronze(_ value: Int) -> Int {
    runtimeRegisterTypeEdge(childTypeID: rankedTypeID, parentTypeID: comparableTypeID)
    return makeComparable(value: value, typeID: bronzeTypeID, supertypes: [rankedTypeID])
}

private func makeGold(_ value: Int) -> Int {
    runtimeRegisterTypeEdge(childTypeID: rankedTypeID, parentTypeID: comparableTypeID)
    return makeComparable(value: value, typeID: goldTypeID, supertypes: [rankedTypeID])
}

// `Elephant : Animal`, where `Animal : Comparable<Animal>`.
private func makeAnimal(_ value: Int) -> Int {
    makeComparable(value: value, typeID: animalTypeID, supertypes: [comparableTypeID])
}

private func makeElephant(_ value: Int) -> Int {
    makeComparable(value: value, typeID: elephantTypeID, supertypes: [animalTypeID])
}

// `Money : Comparable<Money>` shares no supertype with `Animal` beyond Comparable.
private func makeMoney(_ value: Int) -> Int {
    makeComparable(value: value, typeID: moneyTypeID, supertypes: [comparableTypeID])
}

@Suite(.runtimeIsolation(.all))
struct RuntimeErasedComparableDispatchTests {
    @Test
    func compareAnyDispatchesCompareToAcrossSubclassAndBase() {
        let animal = makeAnimal(10)
        let elephant = makeElephant(100)
        #expect(kk_compare_any(animal, elephant) == -1)
        #expect(kk_compare_any(elephant, animal) == 1)
        #expect(kk_compare_any(elephant, makeAnimal(100)) == 0)
    }

    @Test
    func compareAnyDispatchesCompareToAcrossSiblingsSharingComparableInterface() {
        let bronze = makeBronze(1)
        let gold = makeGold(3)
        #expect(kk_compare_any(bronze, gold) == -1)
        #expect(kk_compare_any(gold, bronze) == 1)
    }

    @Test
    func compareAnySkipsCompareToForUnrelatedComparableTypes() {
        let animal = makeAnimal(1)
        let money = makeMoney(2)
        compareToInvocations = 0
        _ = kk_compare_any(animal, money)
        #expect(compareToInvocations == 0)
    }
}
