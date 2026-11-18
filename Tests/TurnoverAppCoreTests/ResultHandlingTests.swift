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
        DragSource(of: files, at: point, windows: windows, levels: levels, screens: [screen], desktopFolder: desktop)
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

    /// While something is dragged, the Dock covers the screen with a window of its own.
    @Test func aDragFromAFinderWindowUnderTheDocksOverlayIsTheWindows() {
        let overlay = DragSource.Window(isFinder: false, layer: 20, frame: screen)
        let window = DragSource.Window(isFinder: true, layer: 0, frame: CGRect(x: 100, y: 100, width: 800, height: 500))

        #expect(source(of: inPictures, at: CGPoint(x: 300, y: 300), under: [overlay, window] + wallpaper) == .finderWindow)
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

    // MARK: Where new files go on the Desktop

    /// A 1728 × 1117 screen's visible frame, below the menu bar and above the Dock.
    let visible = CGRect(x: 0, y: 33, width: 1728, height: 1020)

    func layout(_ arrangement: DesktopLayout.Arrangement) -> DesktopLayout {
        DesktopLayout(arrangement: arrangement, screen: visible, iconSize: 64, textSize: 12)
    }

    /// Icons on Finder's grid for 64-point icons: columns 128 apart from 68 off the right
    /// edge, rows 112 apart from 73 down.
    let onGrid = [
        CGPoint(x: 1660, y: 73), CGPoint(x: 1660, y: 185), CGPoint(x: 1660, y: 297),
        CGPoint(x: 1532, y: 73), CGPoint(x: 124, y: 73), CGPoint(x: 124, y: 185),
    ]

    /// A real Desktop: two columns on each side, an icon a few points off its row, and the
    /// photo that was converted.
    let aRealDesktop = [
        CGPoint(x: 124, y: 73), CGPoint(x: 124, y: 181), CGPoint(x: 124, y: 297), CGPoint(x: 124, y: 409),
        CGPoint(x: 124, y: 521), CGPoint(x: 124, y: 633),
        CGPoint(x: 1660, y: 73), CGPoint(x: 1660, y: 184), CGPoint(x: 1660, y: 297), CGPoint(x: 1660, y: 409),
        CGPoint(x: 1660, y: 521), CGPoint(x: 1532, y: 297), CGPoint(x: 1532, y: 745),
        CGPoint(x: 1148, y: 521),
    ]

    @Test func withSnapToGridAFileTakesTheGridSpotNearestTheDrop() {
        let places = layout(.grid).places(for: 1, droppedAt: CGPoint(x: 1000, y: 500), icons: onGrid)

        #expect(places == [CGPoint(x: 1020, y: 521)])
    }

    /// Dropped just below and left of the photo, whose spot is taken.
    @Test func aTakenSpotPassesToTheNearestFreeOne() {
        let places = layout(.grid).places(for: 1, droppedAt: CGPoint(x: 1102, y: 555), icons: aRealDesktop)

        #expect(places == [CGPoint(x: 1020, y: 521)])
    }

    @Test func moreFilesTakeTheNextNearestSpotsBelowFirst() {
        let places = layout(.grid).places(for: 3, droppedAt: CGPoint(x: 1020, y: 521), icons: onGrid)

        #expect(places == [CGPoint(x: 1020, y: 521), CGPoint(x: 1020, y: 633), CGPoint(x: 1020, y: 409)])
    }

    /// Files placed before the grid was followed are off it, and don't move it.
    @Test func theGridIsFoundPastIconsOffIt() {
        let offGrid = [CGPoint(x: 1103, y: 555), CGPoint(x: 1216, y: 570)]

        let places = layout(.grid).places(for: 1, droppedAt: CGPoint(x: 650, y: 300), icons: aRealDesktop + offGrid)

        #expect(places == [CGPoint(x: 636, y: 297)])
    }

    /// Finder's settings only give a guess at the grid: the icons' spacing wins.
    @Test func theIconsSpacingWinsOverTheExpectedOne() {
        let biggerLabels = DesktopLayout(arrangement: .grid, screen: visible, iconSize: 64, textSize: 14)

        let places = biggerLabels.places(for: 1, droppedAt: CGPoint(x: 650, y: 300), icons: aRealDesktop)

        #expect(biggerLabels.expectedPitch.height == 120)
        #expect(places == [CGPoint(x: 636, y: 297)])
    }

    @Test func withOneIconTheGridFollowsFindersSettings() {
        let places = layout(.grid).places(for: 1, droppedAt: CGPoint(x: 1500, y: 100), icons: [CGPoint(x: 1660, y: 73)])

        #expect(places == [CGPoint(x: 1532, y: 73)])
    }

    /// The spot keeps the icon and its label on the screen.
    @Test func aDropAtTheScreensCornerTakesTheLastSpotInside() {
        let places = layout(.grid).places(for: 1, droppedAt: CGPoint(x: 1725, y: 1050), icons: onGrid)

        #expect(places == [CGPoint(x: 1660, y: 969)])
    }

    @Test func withoutAGridTheFirstFileGoesWhereTheRingWasDropped() {
        let places = layout(.free).places(for: 3, droppedAt: CGPoint(x: 500, y: 400), icons: onGrid)

        #expect(places == [CGPoint(x: 500, y: 400), CGPoint(x: 628, y: 400), CGPoint(x: 756, y: 400)])
    }

    @Test func withoutAGridTheRowWrapsAtTheScreensEdge() {
        let places = layout(.free).places(for: 4, droppedAt: CGPoint(x: 1400, y: 400), icons: [])

        #expect(places == [
            CGPoint(x: 1400, y: 400), CGPoint(x: 1528, y: 400), CGPoint(x: 1656, y: 400),
            CGPoint(x: 1400, y: 512),
        ])
    }

    @Test func withoutAGridADropAtTheEdgeIsPulledInside() {
        let places = layout(.free).places(for: 1, droppedAt: CGPoint(x: 1725, y: 2), icons: [])

        #expect(places == [CGPoint(x: 1664, y: 89)])
    }

    @Test func aDesktopFinderKeepsSortedIsLeftToFinder() {
        #expect(layout(.keptArranged).places(for: 2, droppedAt: CGPoint(x: 500, y: 400), icons: onGrid).isEmpty)
    }

    @Test func theArrangementComesFromFindersSortBy() {
        #expect(DesktopLayout.Arrangement(finderSetting: "grid") == .grid)
        #expect(DesktopLayout.Arrangement(finderSetting: "none") == .free)
        #expect(DesktopLayout.Arrangement(finderSetting: nil) == .free)
        #expect(DesktopLayout.Arrangement(finderSetting: "name") == .keptArranged)
        #expect(DesktopLayout.Arrangement(finderSetting: "dateAdded") == .keptArranged)
    }

    @Test func theExpectedGridIsTheOneMeasuredForFindersSizes() {
        #expect(layout(.grid).expectedPitch == CGSize(width: 128, height: 112))
    }

    // MARK: Coordinates

    @Test func appKitPointsFlipToTopLeftOnes() {
        let coordinates = DesktopCoordinates(mainScreenHeight: 1117)

        #expect(coordinates.topLeft(CGPoint(x: 10, y: 1117)) == CGPoint(x: 10, y: 0))
        #expect(coordinates.topLeft(CGRect(x: 0, y: 0, width: 1728, height: 1084)) == CGRect(x: 0, y: 33, width: 1728, height: 1084))
    }
}
