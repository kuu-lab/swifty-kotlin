#if canImport(Testing)
@testable import Runtime
import Testing

@Suite(.serialized)
struct RuntimeRegexNamedGroupTests {
    init() {
        kk_runtime_force_reset()
    }

    private func withFlatString<T>(
        _ value: String,
        _ body: (UnsafePointer<UInt8>?, Int, Int, Int) -> T
    ) -> T {
        Array(value.utf8).withUnsafeBufferPointer { buffer in
            body(buffer.baseAddress, value.unicodeScalars.count, value.utf8.count, 0)
        }
    }

    private func makeRegex(_ pattern: String) -> Int {
        withFlatString(pattern) { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash)
        }
    }

    private func find(regexRaw: Int, input: String) -> Int {
        withFlatString(input) { data, length, byteCount, hash in
            kk_regex_find_flat(regexRaw, data, length, byteCount, hash)
        }
    }

    private func group(_ groupsRaw: Int, named name: String) -> Int {
        withFlatString(name) { data, length, byteCount, hash in
            kk_match_group_collection_get_flat(groupsRaw, data, length, byteCount, hash)
        }
    }

    private func runtimeString(_ raw: Int) -> String {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeStringBox.self) else {
            return ""
        }
        return box.value
    }

    @Test
    func testNamedGroupsExposeValuesByName() {
        defer { kk_runtime_force_reset() }
        let regexRaw = makeRegex("(?<lhs>ab)(?<rhs>cd)")
        let matchRaw = find(regexRaw: regexRaw, input: "zzabcdyy")
        let groupsRaw = kk_match_result_groups(matchRaw)

        let lhsGroupRaw = group(groupsRaw, named: "lhs")
        let rhsGroupRaw = group(groupsRaw, named: "rhs")

        #expect(lhsGroupRaw != runtimeNullSentinelInt)
        #expect(rhsGroupRaw != runtimeNullSentinelInt)
        #expect(runtimeString(kk_match_group_value(lhsGroupRaw)) == "ab")
        #expect(runtimeString(kk_match_group_value(rhsGroupRaw)) == "cd")
    }

    @Test
    func testMissingNamedGroupReturnsNullSentinel() {
        defer { kk_runtime_force_reset() }
        let regexRaw = makeRegex("(?<lhs>ab)(?<rhs>cd)")
        let matchRaw = find(regexRaw: regexRaw, input: "zzabcdyy")
        let groupsRaw = kk_match_result_groups(matchRaw)

        let missing = group(groupsRaw, named: "missing")
        #expect(missing == runtimeNullSentinelInt)
    }

    @Test
    func testGroupNamesReturnsAllNamedGroups() {
        defer { kk_runtime_force_reset() }
        let regexRaw = makeRegex("(?<year>\\d{4})-(?<month>\\d{2})-(?<day>\\d{2})")
        let setRaw = kk_regex_group_names(regexRaw)

        guard let ptr = UnsafeMutableRawPointer(bitPattern: setRaw),
              let setBox = tryCast(ptr, to: RuntimeSetBox.self) else {
            Issue.record("Expected RuntimeSetBox")
            return
        }
        let names = Set(setBox.elements.map { runtimeString($0) })
        #expect(names == Set(["year", "month", "day"]))
    }

    @Test
    func testGroupNamesEmptyForUnnamedPattern() {
        defer { kk_runtime_force_reset() }
        let regexRaw = makeRegex("(\\d+)-(\\d+)")
        let setRaw = kk_regex_group_names(regexRaw)

        guard let ptr = UnsafeMutableRawPointer(bitPattern: setRaw),
              let setBox = tryCast(ptr, to: RuntimeSetBox.self) else {
            Issue.record("Expected RuntimeSetBox")
            return
        }
        #expect(setBox.elements.isEmpty)
    }
}
#endif
