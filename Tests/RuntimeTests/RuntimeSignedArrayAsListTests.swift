@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeSignedArrayAsListTests {
    @Test(arguments: ["Boolean", "Char", "Float", "Double", "Long", "Int", "Byte", "Short"])
    func typedLiveViewPreservesPrimitiveValues(kind: String) throws {
        let words: [Int]
        let expected: String
        let reversedExpected: String
        let second: String
        let makeView: (Int) -> Int
        switch kind {
        case "Boolean":
            words = [1, 0]
            expected = "[true, false]"
            reversedExpected = "[false, true]"
            second = "false"
            makeView = kk_booleanArray_asList
        case "Int", "Byte", "Short":
            // KUU-4016: the integer views must box their elements the same way
            // the floating/boolean/char views already did; a raw word leaks
            // into Comparable/`is`/toString generic consumers otherwise.
            words = [3, 1]
            expected = "[3, 1]"
            reversedExpected = "[1, 3]"
            second = "1"
            switch kind {
            case "Int": makeView = kk_intArray_asList
            case "Byte": makeView = kk_byteArray_asList
            default: makeView = kk_shortArray_asList
            }
        case "Char":
            words = [99, 97]
            expected = "[c, a]"
            reversedExpected = "[a, c]"
            second = "a"
            makeView = kk_charArray_asList
        case "Float":
            words = [Int(Float(1.5).bitPattern), Int(Float(-0.0).bitPattern)]
            expected = "[1.5, -0.0]"
            reversedExpected = "[-0.0, 1.5]"
            second = "-0.0"
            makeView = kk_floatArray_asList
        case "Double":
            words = [Int(bitPattern: UInt(Double(1.5).bitPattern)), Int.min]
            expected = "[1.5, -0.0]"
            reversedExpected = "[-0.0, 1.5]"
            second = "-0.0"
            makeView = kk_doubleArray_asList
        default:
            words = [Int.min, 7]
            expected = "[-9223372036854775808, 7]"
            reversedExpected = "[7, -9223372036854775808]"
            second = "7"
            makeView = kk_longArray_asList
        }
        let array = RuntimeArrayBox(length: words.count)
        array.elements = words
        let raw = makeView(registerRuntimeObject(array))
        let view = try #require(runtimeListBox(from: raw))
        #expect(runtimeElementToString(raw) == expected)

        // Writes keep primitive storage raw; reads and iterators stay typed.
        view[1] = view[0]
        #expect(array.elements == [words[0], words[0]])
        array.elements[0] = words[1]
        #expect(runtimeElementToString(raw) == reversedExpected)
        let iterator = kk_list_iterator(raw)
        var thrown = 0
        let element = kk_list_iterator_next(iterator, &thrown)
        #expect(thrown == 0)
        #expect(runtimeElementToString(element) == second)
        view.withMutableValues { $0.reverse() }
        #expect(array.elements == [words[0], words[1]])
        #expect(runtimeElementToString(makeView(kk_array_new(0))) == "[]")
    }
}
