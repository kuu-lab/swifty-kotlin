#if canImport(Testing)
@testable import Runtime
import Testing

@Suite(.serialized)
struct RuntimeRegexNamedGroupTests {
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
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
    }

    private func find(regexRaw: Int, input: String) -> Int {
        withFlatString(input) { data, length, byteCount, hash in
            kk_regex_find_flat(regexRaw, data, length, byteCount, hash)
        }
    }

    private func makeStringRaw(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
                Int(bitPattern: kk_string_from_utf8(pointer, Int32(value.utf8.count)))
            }
        }
    }

    private func groupIndex(_ matchRaw: Int, named name: String) -> Int {
        __kk_match_result_group_index_of_name(matchRaw, makeStringRaw(name))
    }

    private func groupValue(_ matchRaw: Int, named name: String) -> String {
        let index = groupIndex(matchRaw, named: name)
        guard index >= 0 else { return "" }
        return runtimeString(__kk_match_result_group_value(matchRaw, index))
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
        let lease = RuntimeTestIsolationLease(lockSet: .all)
        defer { lease.release() }
        let regexRaw = makeRegex("(?<lhs>ab)(?<rhs>cd)")
        let matchRaw = find(regexRaw: regexRaw, input: "zzabcdyy")

        #expect(groupIndex(matchRaw, named: "lhs") == 1)
        #expect(groupIndex(matchRaw, named: "rhs") == 2)
        #expect(groupValue(matchRaw, named: "lhs") == "ab")
        #expect(groupValue(matchRaw, named: "rhs") == "cd")
    }

    @Test
    func testMissingNamedGroupReturnsNullSentinel() {
        let lease = RuntimeTestIsolationLease(lockSet: .all)
        defer { lease.release() }
        let regexRaw = makeRegex("(?<lhs>ab)(?<rhs>cd)")
        let matchRaw = find(regexRaw: regexRaw, input: "zzabcdyy")

        #expect(groupIndex(matchRaw, named: "missing") == -1)
    }

    @Test
    func testGroupNamesReturnsAllNamedGroups() {
        let lease = RuntimeTestIsolationLease(lockSet: .all)
        defer { lease.release() }
        let regexRaw = makeRegex("(?<year>\\d{4})-(?<month>\\d{2})-(?<day>\\d{2})")
        let listRaw = __kk_regex_group_name_list(regexRaw)

        guard let ptr = UnsafeMutableRawPointer(bitPattern: listRaw),
              let listBox = tryCast(ptr, to: RuntimeListBox.self) else {
            Issue.record("Expected RuntimeListBox")
            return
        }
        let names = Set(listBox.elements.map { runtimeString($0) })
        #expect(names == Set(["year", "month", "day"]))
    }

    @Test
    func testGroupNamesEmptyForUnnamedPattern() {
        let lease = RuntimeTestIsolationLease(lockSet: .all)
        defer { lease.release() }
        let regexRaw = makeRegex("(\\d+)-(\\d+)")
        let listRaw = __kk_regex_group_name_list(regexRaw)

        guard let ptr = UnsafeMutableRawPointer(bitPattern: listRaw),
              let listBox = tryCast(ptr, to: RuntimeListBox.self) else {
            Issue.record("Expected RuntimeListBox")
            return
        }
        #expect(listBox.elements.isEmpty)
    }
}
#endif
