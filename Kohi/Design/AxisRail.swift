import SwiftUI

/// One taste axis, 0…10. The rail is a slosh slider: the handle is rigid,
/// the fill has mass, and letting go snaps to a whole number. Tapping the
/// current value clears it.
struct AxisRail: View {
    let axis: TasteAxis
    @Binding var value: Int?
    var enabled = true
    var onChange: () -> Void = {}

    var body: some View {
        SloshRail(label: axis.label, value: $value, enabled: enabled, onChange: onChange)
    }
}

/// The seven rails, in radar order.
struct AxisRails: View {
    @Binding var taste: TasteProfile
    var enabled = true
    var onChange: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            ForEach(TasteAxis.allCases) { axis in
                AxisRail(
                    axis: axis,
                    value: Binding(
                        get: { taste[axis] },
                        set: { taste[axis] = $0 }
                    ),
                    enabled: enabled,
                    onChange: onChange
                )
            }
        }
    }
}
