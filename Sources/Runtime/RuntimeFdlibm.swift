import Foundation

// Ports of the fdlibm (e_exp.c / e_asin.c / e_acos.c) kernels that back
// java.lang.StrictMath. The host libm differs from fdlibm by 1-3 ULP for these
// functions, so kotlin.math output would not match the JVM bit-for-bit.

private let fdlibmPio2Hi = 1.57079632679489655800e+00
private let fdlibmPio2Lo = 6.12323399573676603587e-17
private let fdlibmPio4Hi = 7.85398163397448278999e-01

private let fdlibmPS0 = 1.66666666666666657415e-01
private let fdlibmPS1 = -3.25565818622400915405e-01
private let fdlibmPS2 = 2.01212532134862925881e-01
private let fdlibmPS3 = -4.00555345006794114027e-02
private let fdlibmPS4 = 7.91534994289814532176e-04
private let fdlibmPS5 = 3.47933107596021167570e-05
private let fdlibmQS1 = -2.40339491173441421878e+00
private let fdlibmQS2 = 2.02094576023350569471e+00
private let fdlibmQS3 = -6.88283971605453293030e-01
private let fdlibmQS4 = 7.70381505559019352791e-02

private func fdlibmHighWord(_ x: Double) -> Int32 {
    Int32(truncatingIfNeeded: x.bitPattern >> 32)
}

private func fdlibmLowWord(_ x: Double) -> UInt32 {
    UInt32(truncatingIfNeeded: x.bitPattern)
}

private func fdlibmClearLowWord(_ x: Double) -> Double {
    Double(bitPattern: x.bitPattern & 0xFFFF_FFFF_0000_0000)
}

private func fdlibmAsinRational(_ t: Double) -> (p: Double, q: Double) {
    let p = t * (fdlibmPS0 + t * (fdlibmPS1 + t * (fdlibmPS2 + t * (fdlibmPS3 + t * (fdlibmPS4 + t * fdlibmPS5)))))
    let q = 1.0 + t * (fdlibmQS1 + t * (fdlibmQS2 + t * (fdlibmQS3 + t * fdlibmQS4)))
    return (p, q)
}

func fdlibmExp(_ input: Double) -> Double {
    let halF: [Double] = [0.5, -0.5]
    let ln2HI: [Double] = [6.93147180369123816490e-01, -6.93147180369123816490e-01]
    let ln2LO: [Double] = [1.90821492927058770002e-10, -1.90821492927058770002e-10]
    let invln2 = 1.44269504088896338700e+00
    let p1 = 1.66666666666666019037e-01
    let p2 = -2.77777777770155933842e-03
    let p3 = 6.61375632143793436117e-05
    let p4 = -1.65339022054652515390e-06
    let p5 = 4.13813679705723846039e-08
    let oThreshold = 7.09782712893383973096e+02
    let uThreshold = -7.45133219101941108420e+02
    let twom1000 = 9.33263618503218878990e-302

    var x = input
    var hi = 0.0
    var lo = 0.0
    var k: Int32 = 0
    var hx = fdlibmHighWord(x)
    let xsb = Int((hx >> 31) & 1)
    hx &= 0x7FFF_FFFF

    if hx >= 0x4086_2E42 {
        if hx >= 0x7FF0_0000 {
            if (hx & 0xF_FFFF) | Int32(bitPattern: fdlibmLowWord(x)) != 0 {
                return x + x
            }
            return xsb == 0 ? x : 0.0
        }
        if x > oThreshold { return Double.infinity }
        if x < uThreshold { return 0.0 }
    }

    if hx > 0x3FD6_2E42 {
        if hx < 0x3FF0_A2B2 {
            hi = x - ln2HI[xsb]
            lo = ln2LO[xsb]
            k = Int32(1 - xsb - xsb)
        } else {
            k = Int32(invln2 * x + halF[xsb])
            let t = Double(k)
            hi = x - t * ln2HI[0]
            lo = t * ln2LO[0]
        }
        x = hi - lo
    } else if hx < 0x3E30_0000 {
        if 1.0e300 + x > 1.0 { return 1.0 + x }
    } else {
        k = 0
    }

    let t = x * x
    let c = x - t * (p1 + t * (p2 + t * (p3 + t * (p4 + t * p5))))
    if k == 0 {
        return 1.0 - ((x * c) / (c - 2.0) - x)
    }
    let y = 1.0 - ((lo - (x * c) / (2.0 - c)) - hi)
    if k >= -1021 {
        if k == 1024 {
            return y * 2.0 * 0x1p1023
        }
        return y * Double(bitPattern: UInt64(Int64(k) + 1023) << 52)
    }
    return y * Double(bitPattern: UInt64(Int64(k) + 1000 + 1023) << 52) * twom1000
}

func fdlibmAsin(_ x: Double) -> Double {
    let hx = fdlibmHighWord(x)
    let ix = hx & 0x7FFF_FFFF
    if ix >= 0x3FF0_0000 {
        if (ix - 0x3FF0_0000) | Int32(bitPattern: fdlibmLowWord(x)) == 0 {
            return x * fdlibmPio2Hi + x * fdlibmPio2Lo
        }
        return Double.nan
    } else if ix < 0x3FE0_0000 {
        if ix < 0x3E40_0000 {
            if 1.0e300 + x > 1.0 { return x }
        }
        let t = x * x
        let (p, q) = fdlibmAsinRational(t)
        return x + x * (p / q)
    }
    let w0 = 1.0 - abs(x)
    let t0 = w0 * 0.5
    let (p, q) = fdlibmAsinRational(t0)
    let s = t0.squareRoot()
    let result: Double
    if ix >= 0x3FEF_3333 {
        let w = p / q
        result = fdlibmPio2Hi - (2.0 * (s + s * w) - fdlibmPio2Lo)
    } else {
        let w = fdlibmClearLowWord(s)
        let c = (t0 - w * w) / (s + w)
        let r = p / q
        let pp = 2.0 * s * r - (fdlibmPio2Lo - 2.0 * c)
        let qq = fdlibmPio4Hi - 2.0 * w
        result = fdlibmPio4Hi - (pp - qq)
    }
    return hx > 0 ? result : -result
}

func fdlibmAcos(_ x: Double) -> Double {
    let pi = 3.14159265358979311600e+00
    let hx = fdlibmHighWord(x)
    let ix = hx & 0x7FFF_FFFF
    if ix >= 0x3FF0_0000 {
        if (ix - 0x3FF0_0000) | Int32(bitPattern: fdlibmLowWord(x)) == 0 {
            return hx > 0 ? 0.0 : pi + 2.0 * fdlibmPio2Lo
        }
        return Double.nan
    }
    if ix < 0x3FE0_0000 {
        if ix <= 0x3C60_0000 { return fdlibmPio2Hi + fdlibmPio2Lo }
        let z = x * x
        let (p, q) = fdlibmAsinRational(z)
        let r = p / q
        return fdlibmPio2Hi - (x - (fdlibmPio2Lo - x * r))
    }
    if hx < 0 {
        let z = (1.0 + x) * 0.5
        let (p, q) = fdlibmAsinRational(z)
        let s = z.squareRoot()
        let r = p / q
        let w = r * s - fdlibmPio2Lo
        return pi - 2.0 * (s + w)
    }
    let z = (1.0 - x) * 0.5
    let s = z.squareRoot()
    let df = fdlibmClearLowWord(s)
    let c = (z - df * df) / (s + df)
    let (p, q) = fdlibmAsinRational(z)
    let r = p / q
    let w = r * s + c
    return 2.0 * (df + w)
}
