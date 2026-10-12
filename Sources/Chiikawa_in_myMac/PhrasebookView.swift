import Chiikawa_in_myMacCore
import SwiftUI

/// 우사기 말 사전: 모든 말과 뜻, 쓰는 때. 줄을 누르면 펫이 그 말을 해 보인다 (음성이 있으면 소리도).
struct PhrasebookView: View {
    var model: ChatModel
    var preview: (UsagiPhrasebook.Entry) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("줄을 누르면 우사기가 그 말을 해요. 🔈 표시가 있는 말은 소리도 나요.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BubbleToken.ink.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                if model.isRunning {
                    Text("AI 가 답하는 동안에는 들어 볼 수 없어요.")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(BubbleToken.danger)
                }
                ForEach(UsagiPhrasebook.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(section.title) · \(section.entries.count)")
                            .font(BubbleToken.display(18))
                            .accessibilityAddTraits(.isHeader)
                        ForEach(section.entries) { entry in
                            Button { preview(entry) } label: { PhraseRow(entry: entry) }
                                .buttonStyle(PhraseRowStyle())
                                .disabled(model.isRunning)
                        }
                    }
                }
            }
            .padding(16)
        }
        .foregroundStyle(BubbleToken.ink)
        .background(BubbleToken.bubble)
    }
}

private struct PhraseRow: View {
    let entry: UsagiPhrasebook.Entry

    var body: some View {
        let speech = entry.mumble.speech
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(speech.line)
                    .font(BubbleToken.display(18))
                Text("(=\(speech.meaning))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BubbleToken.ink.opacity(0.75))
            }
            Spacer(minLength: 8)
            if speech.voice != nil {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .bold))
                    .accessibilityLabel("음성 있음")
            }
            Text(entry.occasion)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(BubbleToken.ink.opacity(0.65))
                .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// 사전의 한 줄: 2px 잉크 테두리의 둥근 칸. 누르면 버터색으로 바뀐다.
private struct PhraseRowStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(configuration.isPressed ? BubbleToken.butter : Color.white.opacity(0.6))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(BubbleToken.ink, lineWidth: 2)
            }
            .opacity(isEnabled ? 1 : 0.5)
    }
}
