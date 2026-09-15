import SnapshotTesting
import SwiftUI
import UIKit
@testable import Kohi

/// Image snapshots are pinned to an iPhone 15 Pro, light, @3x — the size the
/// brief names as the density target. Recording happens on first run (`missing`);
/// after that the committed files under `__Snapshots__/` are the contract.
enum SnapshotSupport {
    static let traits = UITraitCollection { traits in
        traits.userInterfaceStyle = .light
        traits.displayScale = 3
        traits.horizontalSizeClass = .compact
        traits.verticalSizeClass = .regular
    }

    static func image<V: View>(
        of view: V,
        width: CGFloat = 393,
        height: CGFloat,
        named name: String? = nil,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        assertSnapshot(
            of: view.background(Palette.paper),
            as: .image(
                layout: .fixed(width: width, height: height),
                traits: traits
            ),
            named: name,
            record: .missing,
            file: file,
            testName: testName,
            line: line
        )
    }
}
