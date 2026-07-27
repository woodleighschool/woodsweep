import Foundation
import Testing

@Suite("Project")
struct SmokeTests {
    @Test("The test bundle is hosted by the WoodSweep application")
    func harnessRuns() {
        #expect(Bundle.main.bundleIdentifier == "au.edu.vic.woodleigh.WoodSweep")
    }
}
