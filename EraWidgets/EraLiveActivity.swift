import WidgetKit
import SwiftUI
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

// Now Playing Live Activity: spinning vinyl on the Lock Screen and in the
// Dynamic Island, with live progress while playing.
struct EraLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EraActivityAttributes.self) { context in
            let state = context.state
            HStack(spacing: 12) {
                VinylDiscView(seed: state.songID, isPlaying: state.isPlaying)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title).font(.headline).lineLimit(1)
                    Text(state.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    progressView(state)
                        .padding(.top, 2)
                }
                Spacer()
                Image(systemName: state.isPlaying ? "waveform" : "pause.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .symbolEffect(.variableColor.iterative, isActive: state.isPlaying)
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.55))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VinylDiscView(seed: state.songID, isPlaying: state.isPlaying)
                        .frame(width: 40, height: 40)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: state.isPlaying ? "waveform" : "pause.fill")
                        .symbolEffect(.variableColor.iterative, isActive: state.isPlaying)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(state.title).font(.headline).lineLimit(1)
                        Text(state.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    progressView(state)
                }
            } compactLeading: {
                VinylDiscView(seed: state.songID, isPlaying: state.isPlaying)
                    .frame(width: 20, height: 20)
            } compactTrailing: {
                Image(systemName: state.isPlaying ? "waveform" : "pause.fill")
                    .font(.caption2)
                    .symbolEffect(.variableColor.iterative, isActive: state.isPlaying)
            } minimal: {
                VinylDiscView(seed: state.songID, isPlaying: state.isPlaying)
                    .frame(width: 12, height: 12)
            }
        }
    }

    @ViewBuilder
    private func progressView(_ state: EraActivityAttributes.ContentState) -> some View {
        let start = state.referenceDate.addingTimeInterval(-state.position)
        let end = start.addingTimeInterval(state.duration / Double(max(state.rate, 0.01)))
        if state.isPlaying {
            ProgressView(timerInterval: start...end, countsDown: false)
                .progressViewStyle(.linear)
                .labelsHidden()
        } else {
            ProgressView(value: min(state.position, state.duration), total: max(state.duration, 0.01))
                .progressViewStyle(.linear)
                .labelsHidden()
        }
    }
}
#endif
