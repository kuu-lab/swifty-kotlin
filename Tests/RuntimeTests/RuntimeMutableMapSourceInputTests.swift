@testable import Runtime
import Testing

private func sourceObject(_ fields: [Int]) -> Int {
    let raw = kk_object_new(fields.count, 0)
    let pointer = UnsafeMutableRawPointer(bitPattern: raw)!
    let box = tryCast(pointer, to: RuntimeObjectBox.self)!
    for (index, value) in fields.enumerated() { box.elements[index] = value }
    return raw
}

private func sourceObjectField(_ raw: Int, _ index: Int) -> Int {
    let pointer = UnsafeMutableRawPointer(bitPattern: raw)!
    return tryCast(pointer, to: RuntimeObjectBox.self)!.elements[index]
}

private let sourceMapEntries: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    thrown?.pointee = 0
    return sourceObjectField(raw, 0)
}

private let sourceEntryKey: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    thrown?.pointee = 0
    return sourceObjectField(raw, 0)
}

private let sourceEntryValue: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    thrown?.pointee = 0
    return sourceObjectField(raw, 1)
}

private let throwingMapEntries: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    thrown?.pointee = sourceObjectField(raw, 0)
    return 0
}

private let throwingEntryValue: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    thrown?.pointee = sourceObjectField(raw, 1)
    return 0
}

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeMutableMapSourceInputTests {
    private func sourceMap(entries: Int, throwing: Bool = false) -> Int {
        let raw = sourceObject([entries])
        let type = runtimeStableNominalTypeID(fqName: "kotlin.collections.Map")
        _ = kk_object_register_itable_iface(raw, Int(type), 0)
        _ = kk_object_register_itable_method(
            raw, 0, 2, unsafeBitCast(throwing ? throwingMapEntries : sourceMapEntries, to: Int.self)
        )
        return raw
    }

    @Test
    func putAllCopiesCustomMapAndCustomEntryGetters() throws {
        let entry = sourceObject([7, 9])
        let type = runtimeStableNominalTypeID(fqName: "kotlin.collections.Map.Entry")
        _ = kk_object_register_itable_iface(entry, Int(type), 0)
        _ = kk_object_register_itable_method(entry, 0, 0, unsafeBitCast(sourceEntryKey, to: Int.self))
        _ = kk_object_register_itable_method(entry, 0, 1, unsafeBitCast(sourceEntryValue, to: Int.self))
        let entries = registerRuntimeObject(RuntimeSetBox(elements: [entry]))
        let source = sourceMap(entries: entries)
        let target = registerRuntimeObject(RuntimeMapBox(keys: [7], values: [1]))
        var thrown = 0
        #expect(kk_mutable_map_putAll(target, source, &thrown) == 0)
        #expect(thrown == 0)
        let map = try #require(runtimeMapBox(from: target))
        #expect(map.keys == [7])
        #expect(map.values == [9])
    }

    @Test
    func putAllPropagatesCustomMapGetterException() throws {
        let exception = kk_object_new(0, 0)
        let source = sourceMap(entries: exception, throwing: true)
        let target = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        var thrown = 0
        #expect(kk_mutable_map_putAll(target, source, &thrown) == 0)
        #expect(thrown == exception)
        #expect(runtimeMapBox(from: target)?.count == 0)
    }

    @Test
    func putAllCopiesCustomMapWithRuntimeEntries() throws {
        let backing = registerRuntimeObject(RuntimeMapBox(keys: [1, 3], values: [4, runtimeNullSentinelInt]))
        let source = sourceMap(entries: kk_map_entries(backing))
        let target = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        var thrown = 0
        _ = kk_mutable_map_putAll(target, source, &thrown)
        #expect(thrown == 0)
        let map = try #require(runtimeMapBox(from: target))
        #expect(map.keys == [1, 3])
        #expect(map.values == [4, runtimeNullSentinelInt])
    }

    @Test
    func putAllPropagatesCustomEntryGetterException() throws {
        let exception = kk_object_new(0, 0)
        let entry = sourceObject([7, exception])
        let type = runtimeStableNominalTypeID(fqName: "kotlin.collections.Map.Entry")
        _ = kk_object_register_itable_iface(entry, Int(type), 0)
        _ = kk_object_register_itable_method(entry, 0, 0, unsafeBitCast(sourceEntryKey, to: Int.self))
        _ = kk_object_register_itable_method(entry, 0, 1, unsafeBitCast(throwingEntryValue, to: Int.self))
        let source = sourceMap(entries: registerRuntimeObject(RuntimeSetBox(elements: [entry])))
        let target = registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
        var thrown = 0
        _ = kk_mutable_map_putAll(target, source, &thrown)
        #expect(thrown == exception)
        #expect(runtimeMapBox(from: target)?.count == 0)
    }

    @Test
    func putAllCopiesRuntimeMapIncludingSelfAndNull() throws {
        let target = registerRuntimeObject(RuntimeMapBox(keys: [1], values: [2]))
        let source = registerRuntimeObject(RuntimeMapBox(keys: [1, 3], values: [4, runtimeNullSentinelInt]))
        var thrown = 0
        _ = kk_mutable_map_putAll(target, source, &thrown)
        _ = kk_mutable_map_putAll(target, target, &thrown)
        #expect(thrown == 0)
        let map = try #require(runtimeMapBox(from: target))
        #expect(map.keys == [1, 3])
        #expect(map.values == [4, runtimeNullSentinelInt])
    }
}
