import Testing
import Foundation
@testable import AirMouseCrypto

@Suite struct KeyEpochTests {
    @Test func notDueImmediately() {
        let issued = Date(timeIntervalSince1970: 1_000_000)
        let epoch = KeyEpoch(sessionID: 1, issuedAt: issued)
        #expect(epoch.isRotationDue(datagramsSent: 0, now: issued) == false)
    }

    @Test func dueAfterFourHours() {
        let issued = Date(timeIntervalSince1970: 1_000_000)
        let epoch = KeyEpoch(sessionID: 1, issuedAt: issued)
        let justBefore = issued.addingTimeInterval(KeyEpoch.rotationInterval - 1)
        let atOrAfter = issued.addingTimeInterval(KeyEpoch.rotationInterval)
        #expect(epoch.isRotationDue(datagramsSent: 0, now: justBefore) == false)
        #expect(epoch.isRotationDue(datagramsSent: 0, now: atOrAfter) == true)
    }

    @Test func dueAfterMaxDatagrams() {
        let issued = Date(timeIntervalSince1970: 1_000_000)
        let epoch = KeyEpoch(sessionID: 1, issuedAt: issued)
        #expect(epoch.isRotationDue(datagramsSent: KeyEpoch.maxDatagramsPerDirection - 1, now: issued) == false)
        #expect(epoch.isRotationDue(datagramsSent: KeyEpoch.maxDatagramsPerDirection, now: issued) == true)
    }

    @Test func overlapWindowIsTwoSeconds() {
        let issued = Date(timeIntervalSince1970: 1_000_000)
        let epoch = KeyEpoch(sessionID: 1, issuedAt: issued)
        let rotatedAt = issued.addingTimeInterval(KeyEpoch.rotationInterval)

        #expect(epoch.isWithinOverlap(rotatedAt: rotatedAt, now: rotatedAt) == true)
        #expect(epoch.isWithinOverlap(rotatedAt: rotatedAt, now: rotatedAt.addingTimeInterval(1.9)) == true)
        #expect(epoch.isWithinOverlap(rotatedAt: rotatedAt, now: rotatedAt.addingTimeInterval(2.0)) == false)
        #expect(epoch.isWithinOverlap(rotatedAt: rotatedAt, now: rotatedAt.addingTimeInterval(2.1)) == false)
    }

    @Test func retirementDeadlineIsRotationPlusOverlap() {
        let issued = Date(timeIntervalSince1970: 1_000_000)
        let epoch = KeyEpoch(sessionID: 1, issuedAt: issued)
        let rotatedAt = Date(timeIntervalSince1970: 2_000_000)
        #expect(epoch.retirementDeadline(rotatedAt: rotatedAt) == rotatedAt.addingTimeInterval(2))
    }
}
