import Testing
@testable import DeduperCore

@Test func testLibraryInfo() async throws {
    let info = DeduperCore.libraryInfo()
    
    #expect(info["version"] != nil)
    #expect(info["buildDate"] != nil)
    #expect(info["version"] == "1.0.0")
}
