import Testing
@testable import AirMouseCore
import AirMouseProtocol

@Suite struct HeldInputLedgerTests {
    @Test func recordDownThenUpClearsItem() {
        var ledger = HeldInputLedger()
        let item = HeldInputItem(.mouseButton(.left))
        ledger.recordDown(item, now: 0)
        #expect(ledger.isHeld(item))
        ledger.recordUp(item)
        #expect(!ledger.isHeld(item))
        #expect(ledger.isEmpty)
    }

    @Test func releaseAllClearsEveryItemAndReturnsThem() {
        var ledger = HeldInputLedger()
        let a = HeldInputItem(.mouseButton(.left))
        let b = HeldInputItem(.key(36))
        ledger.recordDown(a, now: 0)
        ledger.recordDown(b, now: 0)
        let released = ledger.releaseAll()
        #expect(Set(released) == Set([a, b]))
        #expect(ledger.isEmpty)
    }

    @Test func reDownDoesNotResetWatchdogClock() {
        var ledger = HeldInputLedger()
        let item = HeldInputItem(.key(36))
        ledger.recordDown(item, now: 0)
        ledger.recordDown(item, now: 30) // e.g. an auto-repeat re-affirming the key is still down
        #expect(ledger.itemsExceedingWatchdog(now: 59).isEmpty)
        #expect(ledger.itemsExceedingWatchdog(now: 60) == [item])
    }

    @Test func watchdogFiresAtSixtySeconds() {
        var ledger = HeldInputLedger()
        let item = HeldInputItem(.modifierKey(0x38))
        ledger.recordDown(item, now: 100)
        #expect(ledger.itemsExceedingWatchdog(now: 159).isEmpty)
        #expect(ledger.itemsExceedingWatchdog(now: 160) == [item])
    }

    @Test func watchdogOnlyReportsExceedingItems() {
        var ledger = HeldInputLedger()
        let old = HeldInputItem(.mouseButton(.left))
        let fresh = HeldInputItem(.mouseButton(.right))
        ledger.recordDown(old, now: 0)
        ledger.recordDown(fresh, now: 55)
        let exceeding = ledger.itemsExceedingWatchdog(now: 61)
        #expect(exceeding == [old])
    }

    @Test func releaseSpecificItemsLeavesOthersHeld() {
        var ledger = HeldInputLedger()
        let a = HeldInputItem(.mouseButton(.left))
        let b = HeldInputItem(.mouseButton(.right))
        ledger.recordDown(a, now: 0)
        ledger.recordDown(b, now: 0)
        ledger.release([a])
        #expect(!ledger.isHeld(a))
        #expect(ledger.isHeld(b))
        #expect(ledger.count == 1)
    }

    @Test func upOnItemNeverHeldIsANoOp() {
        var ledger = HeldInputLedger()
        ledger.recordUp(HeldInputItem(.key(1)))
        #expect(ledger.isEmpty)
    }
}
