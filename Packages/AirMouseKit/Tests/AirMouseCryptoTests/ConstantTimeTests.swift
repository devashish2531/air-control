import Testing
import Foundation
@testable import AirMouseCrypto

@Suite struct ConstantTimeTests {
    @Test func equalBytesReportEqual() {
        #expect(ConstantTime.isEqual([1, 2, 3], [1, 2, 3]))
    }

    @Test func differingBytesReportUnequal() {
        #expect(ConstantTime.isEqual([1, 2, 3], [1, 2, 4]) == false)
    }

    @Test func differingLengthsReportUnequal() {
        #expect(ConstantTime.isEqual([1, 2, 3], [1, 2]) == false)
        #expect(ConstantTime.isEqual([], [1]) == false)
    }

    @Test func emptyArraysAreEqual() {
        #expect(ConstantTime.isEqual([], []))
    }

    @Test func dataOverload() {
        #expect(ConstantTime.isEqual(Data([1, 2, 3]), Data([1, 2, 3])))
        #expect(ConstantTime.isEqual(Data([1, 2, 3]), Data([1, 2, 4])) == false)
    }

    @Test func arraySliceOverload() {
        let base: [UInt8] = [0, 1, 2, 3, 4]
        #expect(ConstantTime.isEqual(base[1..<3], base[1..<3]))
        #expect(ConstantTime.isEqual(base[1..<3], base[2..<4]) == false)
    }

    @Test func singleBitDifferenceIsDetected() {
        var a = [UInt8](repeating: 0, count: 32)
        var b = [UInt8](repeating: 0, count: 32)
        a[17] = 0b0000_0001
        b[17] = 0b0000_0000
        #expect(ConstantTime.isEqual(a, b) == false)
    }
}
