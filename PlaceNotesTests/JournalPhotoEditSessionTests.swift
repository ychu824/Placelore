import XCTest
@testable import PlaceNotes

final class JournalPhotoEditSessionTests: XCTestCase {

    func testRemovingSavedPhotoDefersDeletionUntilSave() {
        var session = JournalPhotoEditSession(original: ["a.jpg", "b.jpg"])

        let deletedNow = session.remove("a.jpg")

        XCTAssertEqual(deletedNow, [])
        XCTAssertEqual(session.filenames, ["b.jpg"])
        XCTAssertEqual(session.filesToDeleteOnSave, ["a.jpg"])
        XCTAssertEqual(session.filesToDeleteOnDiscard, [])
    }

    func testRemovingNewPhotoDeletesItImmediately() {
        var session = JournalPhotoEditSession(original: ["a.jpg"])
        session.add("new.jpg")

        let deletedNow = session.remove("new.jpg")

        XCTAssertEqual(deletedNow, ["new.jpg"])
        XCTAssertEqual(session.filenames, ["a.jpg"])
        XCTAssertEqual(session.filesToDeleteOnSave, [])
        XCTAssertEqual(session.filesToDeleteOnDiscard, [])
    }

    func testDiscardDeletesOnlyPhotosAddedThisSession() {
        var session = JournalPhotoEditSession(original: ["a.jpg"])
        session.add("new1.jpg")
        session.add("new2.jpg")
        _ = session.remove("a.jpg")

        XCTAssertEqual(Set(session.filesToDeleteOnDiscard), ["new1.jpg", "new2.jpg"])
    }

    func testSaveKeepsAddedPhotos() {
        var session = JournalPhotoEditSession()
        session.add("new.jpg")

        XCTAssertEqual(session.filenames, ["new.jpg"])
        XCTAssertEqual(session.filesToDeleteOnSave, [])
    }
}
