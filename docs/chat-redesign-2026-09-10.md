# Chat redesign — 2026-09-10

## Requested behavior

- Replace the controller with a conversation screen.
- Use the existing Gemini assistant, as confirmed by the user.
- Move secondary controls into options.
- Put voice interaction and motion reactions on hold; keep video on idle.
- Move the prototype into its own project directory.

## Implementation

- Replaced the button-heavy AppKit panel with a resizable SwiftUI chat window, dark neutral palette, muted pink accent, conversation bubbles, selectable messages and a multiline composer.
- Added Return to send, Shift-Return for a newline, and an IME composition guard. Added native Edit menu commands so clipboard shortcuts work.
- Options contain video visibility and desktop mode, chat window pinning, new conversation, stop-waiting during requests, and application information.
- Kept the video renderer separate. The app loads only the idle clip; conversation requests cannot trigger phone or playful states.
- Current app sends `audio: false`. Legacy voice API requests retain the prior default, and the initial Git commit preserves the old native voice integration.
- Conversation state lives in memory. Requests contain up to six completed user/assistant pairs. Failures preserve retry state without duplicating the user's message, and canceled callbacks cannot append a late answer.
- Build targets macOS 13 explicitly and no longer links Speech or declares microphone/speech permission strings.

## Verified

- Project migration: 40 files moved with matching relative paths and SHA-256 hashes before redesign. Generated assets remain unchanged.
- App compiled and was locally signed successfully from the new project directory.
- Six Python tests passed, including HTTP text-only requests without TTS, history forwarding, legacy voice behavior, malformed input and authentication rejection.
- Native ChatStore tests passed for text-only payload, conversation context, input limit, error/retry, cancellation, new chat reset and missing local bridge.
- Live local bridge returned a real Gemini text answer with no audio field.
- Native UI: initial empty state and chat layout inspected visually.
- Native UI: Japanese text entry, paste, Shift-Return newline and Return submission exercised. The observed message contained only the intended synthetic test text before sending.
- Native UI: a real Gemini answer appeared in the conversation history, and the composer returned to its empty state.
- Native UI: suggestion button filled the draft without submitting; the Send button then submitted it and displayed a second real answer.
- Native UI: options listed all secondary controls; video display showed the seated idle clip after the conversation.
- Native UI: new-chat action required confirmation and cleared the synthetic conversation. Left the app open on a clean chat screen.
- The screen-capture connection briefly failed with SCStream error -3811. It later recovered; UI verification resumed and completed.

## Limits

- Japanese IME composition guard is implemented, but a full live conversion/commit sequence was not exercised; the Japanese UI test used paste and accessibility text entry.
- Cross-Space and physical multi-display layout were not exercised in this redesign pass.
- Captures verify individual app windows, not simultaneous visibility on the user's full desktop.
- Search, calendar, filesystem actions, durable chat history and other working-agent tools remain unconnected. The user explicitly chose the existing Gemini conversation provider.
