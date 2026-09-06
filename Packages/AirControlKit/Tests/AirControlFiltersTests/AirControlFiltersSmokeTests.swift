import Testing
@testable import AirControlFilters

@Suite struct AirControlFiltersSmokeTests {
    @Test func moduleLinks() {
        #expect(AirControlFiltersModule.name == "AirControlFilters")
    }
}
