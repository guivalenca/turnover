import Foundation
import Testing
import TurnoverAppCore

/// What happens to new files, by where the conversion started (#18): selected in a Finder
/// window, placed where the ring was dropped on the Desktop, or left alone. Never a new Finder
/// window for a conversion that didn't start in one.
@Suite struct ResultHandlingTests {
    let desktop = URL(fileURLWithPath: "/Users/me/Desktop", isDirectory: true)

    // MARK: Origins and their handling

    @Test func aFinderWindowSelectsTheNewFiles() {
        #expect(ConversionOrigin.finderWindow.handling == .selectInFinder)
    }

    @Test func aRingDropOnTheDesktopPlacesThemWhereItWasDropped() {
        let drop = CGPoint(x: 400, y: 300)

        #expect(ConversionOrigin.desktop(drop: drop).handling == .placeOnDesktop(at: drop))
    }

    @Test func theDesktopMenuLeavesThemWhereFinderPutsThem() {
        #expect(ConversionOrigin.desktop(drop: nil).handling == .leave)
    }

    @Test func aDockStackOrAnotherAppOpensNothing() {
        #expect(ConversionOrigin.elsewhere.handling == .leave)
    }

    @Test func theMenuOnDesktopFilesIsTheDesktops() {
        let files = [desktop.appendingPathComponent("a.heic"), desktop.appendingPathComponent("b.mov")]

        #expect(ConversionOrigin(menuFiles: files, desktopFolder: desktop) == .desktop(drop: nil))
    }

    @Test func theMenuAnywhereElseIsAFinderWindows() {
        let files = [URL(fileURLWithPath: "/Users/me/Pictures/a.heic")]

        #expect(ConversionOrigin(menuFiles: files, desktopFolder: desktop) == .finderWindow)
    }

    /// A folder on the Desktop is shown in a Finder window, not on the Desktop.
    @Test func theMenuInAFolderOnTheDesktopIsAFinderWindows() {
        let files = [desktop.appendingPathComponent("Trip/a.heic")]

        #expect(ConversionOrigin(menuFiles: files, desktopFolder: desktop) == .finderWindow)
    }

    @Test func onlyFilesSavedOnTheDesktopAreMoved() {
        let onDesktop = desktop.appendingPathComponent("a.png")
        let inDownloads = URL(fileURLWithPath: "/Users/me/Downloads/b.png")

        #expect(ResultHandling.placeable([onDesktop, inDownloads], desktopFolder: desktop) == [onDesktop])
    }

    // MARK: Where a drag started

    let levels = DragSource.Levels(desktopIcons: -2_147_483_603, normal: 0, dragging: 500)
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    var desktopIcons: DragSource.Window { .init(isFinder: true, layer: levels.desktopIcons, frame: screen) }

    @Test func aDragFromTheDesktopIsTheDesktops() {
        let source = DragSource(at: CGPoint(x: 1660, y: 60), windows: [desktopIcons], levels: levels)

        #expect(source == .desktop)
    }

    @Test func aDragFromAFinderWindowOverTheDesktopIsTheWindows() {
        let window = DragSource.Window(isFinder: true, layer: 0, frame: CGRect(x: 100, y: 100, width: 800, height: 500))

        let source = DragSource(at: CGPoint(x: 300, y: 300), windows: [window, desktopIcons], levels: levels)

        #expect(source == .finderWindow)
    }

    @Test func aDragFromAnotherAppsWindowIsElsewhere() {
        let editor = DragSource.Window(isFinder: false, layer: 0, frame: CGRect(x: 0, y: 0, width: 900, height: 900))

        let source = DragSource(at: CGPoint(x: 300, y: 300), windows: [editor, desktopIcons], levels: levels)

        #expect(source == .elsewhere)
    }

    @Test func aDragFromADockStackIsElsewhere() {
        let stack = DragSource.Window(isFinder: false, layer: 20, frame: CGRect(x: 1200, y: 600, width: 400, height: 400))

        let source = DragSource(at: CGPoint(x: 1300, y: 700), windows: [stack, desktopIcons], levels: levels)

        #expect(source == .elsewhere)
    }

    /// The drag may have started before Turnover reads the windows, so its image can already be
    /// under the pointer.
    @Test func theDragImageIsSeenThrough() {
        let dragImage = DragSource.Window(isFinder: true, layer: levels.dragging, frame: CGRect(x: 1600, y: 20, width: 100, height: 100))

        let source = DragSource(at: CGPoint(x: 1660, y: 60), windows: [dragImage, desktopIcons], levels: levels)

        #expect(source == .desktop)
    }

    @Test func noWindowUnderThePointIsElsewhere() {
        #expect(DragSource(at: CGPoint(x: 10, y: 10), windows: [], levels: levels) == .elsewhere)
    }

    @Test func onlyADesktopDragPlacesTheFilesWhereTheyWereDropped() {
        let drop = CGPoint(x: 500, y: 400)

        #expect(DragSource.desktop.origin(drop: drop) == .desktop(drop: drop))
        #expect(DragSource.finderWindow.origin(drop: drop) == .finderWindow)
        #expect(DragSource.elsewhere.origin(drop: drop) == .elsewhere)
    }

    // MARK: Slots on the Desktop

    let pitch = CGSize(width: 120, height: 140)

    @Test func theFirstFileGoesWhereTheRingWasDropped() {
        var slots = DesktopSlots(drop: CGPoint(x: 500, y: 400), pitch: pitch, screen: screen)

        #expect(slots.next() == CGPoint(x: 500, y: 400))
    }

    @Test func moreFilesGoInARowToTheRight() {
        var slots = DesktopSlots(drop: CGPoint(x: 500, y: 400), pitch: pitch, screen: screen)

        let points = (0..<3).map { _ in slots.next() }

        #expect(points == [CGPoint(x: 500, y: 400), CGPoint(x: 620, y: 400), CGPoint(x: 740, y: 400)])
    }

    @Test func theRowWrapsAtTheScreensEdge() {
        // 1728 wide, kept 60 inside: room for the drop column and two more.
        var slots = DesktopSlots(drop: CGPoint(x: 1400, y: 400), pitch: pitch, screen: screen)

        let points = (0..<4).map { _ in slots.next() }

        #expect(points == [
            CGPoint(x: 1400, y: 400), CGPoint(x: 1520, y: 400), CGPoint(x: 1640, y: 400),
            CGPoint(x: 1400, y: 540),
        ])
    }

    @Test func aDropAtTheEdgeIsPulledInside() {
        var slots = DesktopSlots(drop: CGPoint(x: 1725, y: 2), pitch: pitch, screen: screen)

        #expect(slots.next() == CGPoint(x: 1668, y: 70))
    }

    @Test func thePitchFollowsFindersDesktopSettings() {
        let pitch = DesktopSlots.pitch(iconSize: 64, gridSpacing: 57, textSize: 12)

        #expect(pitch == CGSize(width: 121, height: 145))
    }

    // MARK: Coordinates

    @Test func appKitPointsFlipToTopLeftOnes() {
        let coordinates = DesktopCoordinates(mainScreenHeight: 1117)

        #expect(coordinates.topLeft(CGPoint(x: 10, y: 1117)) == CGPoint(x: 10, y: 0))
        #expect(coordinates.topLeft(CGRect(x: 0, y: 0, width: 1728, height: 1084)) == CGRect(x: 0, y: 33, width: 1728, height: 1084))
    }
}
