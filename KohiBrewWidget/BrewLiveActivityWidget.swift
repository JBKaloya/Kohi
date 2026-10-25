import ActivityKit
import SwiftUI
import WidgetKit

@main
struct KohiBrewWidgetBundle: WidgetBundle {
    var body: some Widget {
        BrewLiveActivityWidget()
    }
}

struct BrewLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BrewActivityAttributes.self) { context in
            lockScreen(context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.coffeeName)
                        .font(.caption)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timer(context.state.startedAt)
                        .monospacedDigit()
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.stepLabel)
                            .font(.subheadline)
                        massLine(context.state)
                        stepBar(context.state)
                    }
                }
            } compactLeading: {
                Text(massShort(context.state))
                    .font(.caption2)
                    .monospacedDigit()
            } compactTrailing: {
                timer(context.state.startedAt)
                    .font(.caption2)
                    .monospacedDigit()
            } minimal: {
                Text(massShort(context.state))
                    .font(.caption2)
                    .monospacedDigit()
            }
        }
    }

    private func lockScreen(_ context: ActivityViewContext<BrewActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.coffeeName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(context.attributes.methodLabel)
                        .font(.caption)
                        .foregroundStyle(inkMuted)
                }
                Spacer()
                timer(context.state.startedAt)
                    .font(.title3.monospacedDigit())
            }
            Text(context.state.stepLabel)
                .font(.subheadline)
            if context.state.isRecording {
                Text("Recording")
                    .font(.caption)
                    .foregroundStyle(inkMuted)
            }
            massLine(context.state)
            stepBar(context.state)
        }
        .padding(16)
        .foregroundStyle(ink)
        .activityBackgroundTint(paper)
    }

    private func massLine(_ state: BrewActivityAttributes.ContentState) -> some View {
        Group {
            if let now = state.nowMass, let target = state.targetMass {
                Text("\(number(now)) g  /  \(number(target)) g")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(inkMuted)
            } else if let target = state.targetMass {
                Text("\(number(target)) g")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(inkMuted)
            }
        }
    }

    private func stepBar(_ state: BrewActivityAttributes.ContentState) -> some View {
        let end = max(state.finalMass, state.stepMasses.last ?? 0, 1)
        let fill = min(max((state.nowMass ?? 0) / end, 0), 1)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(hairline).frame(height: 3)
                Capsule()
                    .fill(ink)
                    .frame(width: max(3, geo.size.width * fill), height: 3)
                ForEach(Array(state.stepMasses.enumerated()), id: \.offset) { _, mass in
                    Circle()
                        .fill(ink)
                        .frame(width: 6, height: 6)
                        .offset(x: geo.size.width * min(max(mass / end, 0), 1) - 3)
                }
            }
        }
        .frame(height: 10)
    }

    private func timer(_ startedAt: Date) -> Text {
        Text(timerInterval: startedAt...startedAt.addingTimeInterval(60 * 180), countsDown: false)
    }

    private func massShort(_ state: BrewActivityAttributes.ContentState) -> String {
        if let now = state.nowMass { return number(now) + "g" }
        return "—"
    }

    private func number(_ value: Double) -> String {
        value == value.rounded()
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }

    private var paper: Color { Color(red: 0.980, green: 0.973, blue: 0.957) }
    private var ink: Color { Color(red: 0.102, green: 0.094, blue: 0.082) }
    private var inkMuted: Color { Color(red: 0.541, green: 0.514, blue: 0.471) }
    private var hairline: Color { Color(red: 0.886, green: 0.867, blue: 0.827) }
}
