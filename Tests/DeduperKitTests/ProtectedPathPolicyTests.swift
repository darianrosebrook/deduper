import Testing
import Foundation
@testable import DeduperKit

@Suite("ProtectedPathPolicy")
struct ProtectedPathPolicyTests {
    let policy = ProtectedPathPolicy.shared

    // MARK: - Protected (positive)

    @Test("Paths under /usr are protected")
    func usrProtected() {
        #expect(policy.isProtected(
            URL(fileURLWithPath: "/usr/lib/system/foo")
        ))
        #expect(policy.isProtected(path: "/usr/bin/ls"))
    }

    @Test("Paths under /System/Library are protected")
    func systemLibraryProtected() {
        #expect(policy.isProtected(
            URL(fileURLWithPath: "/System/Library/CoreServices/Foo.app")
        ))
    }

    // MARK: - Not protected (negative)

    @Test("User-space paths are not protected")
    func userSpaceNotProtected() {
        #expect(!policy.isProtected(
            URL(fileURLWithPath: "/Users/testuser/photos/bar.jpg")
        ))
    }

    // MARK: - Regression: firmlink over-blocking
    // The original bug: the UI's preview-time copy used the bare
    // prefix "/System" and compared non-canonical url.path, so a
    // legitimate user file reached via the /System/Volumes/Data
    // firmlink was falsely flagged "protected" in preview while
    // MergeService (matching only /System/Library on the canonical
    // path) would happily move it at execution. This test fails if
    // anyone restores the bare "/System" prefix.

    @Test("Firmlinked user space under /System/Volumes/Data is NOT protected")
    func firmlinkedUserSpaceNotProtected() {
        let firmlinked = URL(fileURLWithPath:
            "/System/Volumes/Data/Users/testuser/photos/bar.jpg"
        )
        #expect(!policy.isProtected(firmlinked))
        #expect(!policy.isProtected(path:
            "/System/Volumes/Data/Users/testuser/photos/bar.jpg"
        ))
    }

    // MARK: - Overload parity

    @Test("String and URL overloads agree")
    func overloadsAgree() {
        let path = "/usr/local/bin/foo"
        #expect(
            policy.isProtected(URL(fileURLWithPath: path))
                == policy.isProtected(path: path)
        )
    }
}
