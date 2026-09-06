import Testing
@testable import Air_Control

@Suite struct LaunchArgumentsTests {
    @Test func defaultsToAllOff() {
        let args = LaunchArguments.parse([])
        #expect(args.loopback == false)
        #expect(args.bench == false)
        #expect(args.logLevel == nil)
    }

    @Test func parsesBareFlagsInAnyOrder() {
        let args = LaunchArguments.parse(["--bench", "--loopback"])
        #expect(args.loopback == true)
        #expect(args.bench == true)
    }

    @Test func parsesLogLevelAsASeparateToken() {
        let args = LaunchArguments.parse(["--log-level", "debug"])
        #expect(args.logLevel == .debug)
    }

    @Test func parsesLogLevelWithEqualsSign() {
        let args = LaunchArguments.parse(["--log-level=error"])
        #expect(args.logLevel == .error)
    }

    @Test func ignoresUnknownFlagsOwnedByOtherAgents() {
        let args = LaunchArguments.parse(["--port", "47801", "--identity", "abc", "--loopback"])
        #expect(args.loopback == true)
        #expect(args.logLevel == nil)
    }

    @Test func ignoresMalformedLogLevelValue() {
        let args = LaunchArguments.parse(["--log-level", "not-a-level"])
        #expect(args.logLevel == nil)
    }
}
