import Dispatch
import Runtime

let iterations = 200_000

@inline(never)
func legacyRoundTrip(_ value: Int) -> Int {
    kk_unbox_int(kk_box_int(value))
}

@inline(never)
func staticRoundTrip(_ value: Int) -> Int {
    kk_unbox_int_static(kk_box_int_static(value))
}

func elapsed(_ body: () -> Int) -> (UInt64, Int) {
    let start = DispatchTime.now().uptimeNanoseconds
    let checksum = body()
    return (DispatchTime.now().uptimeNanoseconds - start, checksum)
}

func median(_ values: [UInt64]) -> UInt64 {
    values.sorted()[values.count / 2]
}

func runRounds(_ label: String, roundTrip: (Int) -> Int) {
    var timings: [UInt64] = []
    var checksum = 0
    for _ in 0..<5 {
        let result = elapsed {
            var value = 0
            var roundChecksum = 0
            while value < iterations {
                roundChecksum &+= roundTrip(value)
                value += 1
            }
            return roundChecksum
        }
        timings.append(result.0)
        checksum = result.1
    }
    print("\(label) median_ns=\(median(timings)) checksum=\(checksum)")
}

switch CommandLine.arguments.dropFirst().first {
case "legacy":
    runRounds("legacy", roundTrip: legacyRoundTrip)
case "static":
    runRounds("static", roundTrip: staticRoundTrip)
default:
    runRounds("legacy", roundTrip: legacyRoundTrip)
    runRounds("static", roundTrip: staticRoundTrip)
}
