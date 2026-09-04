import Testing
@testable import AirMouseFilters

@Suite struct AirMouseFiltersSmokeTests {
    @Test func moduleLinks() {
        #expect(AirMouseFiltersModule.name == "AirMouseFilters")
    }
}
