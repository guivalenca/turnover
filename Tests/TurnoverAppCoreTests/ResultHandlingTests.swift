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

    let levels = DragSource.Levels(normal: 0, dragging: 500)
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    /// What `CGWindowListCopyWindowInfo` lists over the Desktop on macOS 26 and later: the
    /// wallpaper's and WindowManager's windows, and no window of Desktop icons.
    var wallpaper: [DragSource.Window] {
        [.init(isFinder: false, layer: -2_147_483_622, frame: screen), .init(isFinder: false, layer: -2_147_483_626, frame: screen)]
    }
    var onDesktop: [URL] { [desktop.appendingPathComponent("IMG_0001.heic")] }
    let inPictures = [URL(fileURLWithPath: "/Users/me/Pictures/IMG_0001.heic")]

    func source(of files: [URL], at point: CGPoint, under windows: [DragSource.Window]) -> DragSource {
        DragSource(of: files, at: point, windows: windows, levels: levels, desktopFolder: desktop)
    }

    @Test func aDragOfDesktopFilesFromTheDesktopIsTheDesktops() {
        #expect(source(of: onDesktop, at: CGPoint(x: 1660, y: 60), under: wallpaper) == .desktop)
    }

    /// Windows moved aside to show the Desktop keep their old bounds in the list.
    @Test func aDragOfDesktopFilesUnderAnotherAppsWindowIsStillTheDesktops() {
        let editor = DragSource.Window(isFinder: false, layer: 0, frame: CGRect(x: 0, y: 33, width: 1728, height: 1084))

        #expect(source(of: onDesktop, at: CGPoint(x: 1660, y: 60), under: [editor] + wallpaper) == .desktop)
    }

    @Test func aDragFromAFinderWindowIsTheWindows() {
        let window = DragSource.Window(isFinder: true, layer: 0, frame: CGRect(x: 100, y: 100, width: 800, height: 500))

        #expect(source(of: inPictures, at: CGPoint(x: 300, y: 300), under: [window] + wallpaper) == .finderWindow)
    }

    /// A Finder window showing the Desktop folder selects the new files in it.
    @Test func aDragOfDesktopFilesFromAFinderWindowIsTheWindows() {
        let window = DragSource.Window(isFinder: true, layer: 0, frame: CGRect(x: 100, y: 100, width: 800, height: 500))

        #expect(source(of: onDesktop, at: CGPoint(x: 300, y: 300), under: [window] + wallpaper) == .finderWindow)
    }

    @Test func aDragFromAnotherAppsWindowIsElsewhere() {
        let editor = DragSource.Window(isFinder: false, layer: 0, frame: CGRect(x: 0, y: 0, width: 900, height: 900))

        #expect(source(of: inPictures, at: CGPoint(x: 300, y: 300), under: [editor] + wallpaper) == .elsewhere)
    }

    @Test func aDragFromADockStackIsElsewhere() {
        let stack = DragSource.Window(isFinder: false, layer: 20, frame: CGRect(x: 1200, y: 600, width: 400, height: 400))
        let downloads = [URL(fileURLWithPath: "/Users/me/Downloads/IMG_0001.heic")]

        #expect(source(of: downloads, at: CGPoint(x: 1300, y: 700), under: [stack] + wallpaper) == .elsewhere)
    }

    /// The drag may have started before Turnover reads the windows, so its image can already be
    /// under the pointer.
    @Test func theDragImageIsSeenThrough() {
        let dragImage = DragSource.Window(isFinder: false, layer: levels.dragging, frame: CGRect(x: 250, y: 250, width: 100, height: 100))
        let window = DragSource.Window(isFinder: true, layer: 0, frame: CGRect(x: 100, y: 100, width: 800, height: 500))

        #expect(source(of: inPictures, at: CGPoint(x: 300, y: 300), under: [dragImage, window] + wallpaper) == .finderWindow)
    }

    /// Desktop files mixed with others aren't all the Desktop's.
    @Test func aDragOfSomeDesktopFilesIsElsewhere() {
        #expect(source(of: onDesktop + inPictures, at: CGPoint(x: 10, y: 10), under: wallpaper) == .elsewhere)
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
