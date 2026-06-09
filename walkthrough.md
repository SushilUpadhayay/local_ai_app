# Trek Knowledge Tool Calling Walkthrough

This project is still the existing Flutter Local AI app. The Trek Knowledge system was added as an offline capability inside the current chat workflow, model loading flow, streaming response flow, TTS/STT support, and conversation persistence.

## What Changed

The integration added a tool-calling layer around the existing local LLM chat pipeline:

1. The user sends a normal chat message.
2. The local LLM is asked whether a Trek Knowledge tool is needed.
3. Dart validates any proposed tool call.
4. The tool registry executes the approved tool against local JSON data.
5. The tool result is injected into a second local LLM prompt.
6. The LLM streams the final natural-language answer back into the same chat UI.
7. The assistant message stores execution metadata for the "View Reasoning" UI.

If no Trek Knowledge tool is needed, the app falls back to the existing normal chat path.

## Runtime Flow

### Normal Chat

```text
User Query
  -> AppState.sendMessage()
  -> Local LLM tool-selection prompt
  -> No tool required
  -> Existing context-window chat prompt
  -> Local LLM streaming response
  -> Assistant message saved
```

### Trek Tool Calling

```text
User Query
  -> AppState.sendMessage()
  -> Local LLM tool-selection prompt
  -> ToolRegistryService validation
  -> TrekKnowledgeService tool execution
  -> Tool result JSON
  -> Local LLM synthesis prompt
  -> Streaming final answer
  -> Assistant message saved with ReasoningTrace
```

The app also keeps the older local trek-intent detector as a fallback. This helps when a smaller local model does not return parseable tool-selection JSON.

## Important Files

### `lib/models/app_state.dart`

`AppState` is the main orchestrator.

It now coordinates:

- user message insertion
- tool selection prompt execution
- fallback Trek intent detection
- Dart-side tool validation and execution
- tool result injection into the LLM
- streaming response handling
- TTS sentence buffering
- conversation persistence
- reasoning trace attachment to assistant messages

The key method is:

```dart
Future<void> sendMessage(String text)
```

That method now has two major branches:

- Trek tool branch, when tool calls are selected or detected
- normal chat branch, when no tool is required

### `lib/services/tool_registry_service.dart`

This is the new tool registry layer.

It owns:

- tool registration
- tool-call validation
- tool execution
- standardized execution results
- tool history tracking
- used-tool tracking
- current-response reasoning trace

Registered tools:

- `search_trek`
- `get_trek_info`
- `get_route_info`
- `get_landmarks`
- `get_villages`
- `get_health_posts`
- `get_emergency_info`
- `get_transport_info`
- `get_faq_answer`
- `list_available_treks`
- `get_used_tools`
- `get_tool_history`
- `get_reasoning_trace`

The registry is intentionally Dart-side. The local LLM can suggest tool calls, but it cannot directly execute them. This keeps execution controlled, validated, and offline.

### `lib/services/trek_knowledge_service.dart`

This service remains the local knowledge source.

It loads JSON files from:

```text
trek_info/
```

Current trek files:

- `annapurna_base_camp_trek_data.json`
- `everest_base_camp_trek_data.json`
- `langtang_valley_base_trek_data.json`

It provides the actual data lookup methods used by the registry. It also still includes local intent detection as a fallback path.

### `lib/services/local_llm_service.dart`

The local LLM service still handles model loading and token streaming.

It now also includes helper methods for:

- generating non-streamed text for tool selection
- building the tool-selection prompt
- building the tool-result synthesis prompt

The important additions are:

```dart
Future<String> generateText(...)
String buildToolSelectionPrompt(...)
String buildToolSynthesisPrompt(...)
```

Tool selection is non-streamed because the app needs a complete JSON decision before executing a tool.

Final user-facing answers still stream normally.

### `lib/models/conversation.dart`

Messages now support optional reasoning metadata:

```dart
class ReasoningTrace {
  final String matchedTrek;
  final List<String> toolsUsed;
  final List<String> sourceFiles;
  final int executionTimeMs;
}
```

This metadata is persisted with conversations, so old assistant messages can still show their execution details after reload.

The trace stores only application execution metadata. It does not store or expose chain-of-thought.

### `lib/screens/chat_screen.dart`

Assistant messages now show a "View Reasoning" expandable section when a message has Trek tool execution metadata.

It displays:

- Selected Trek
- Tools Used
- Source Files
- Execution Time

It does not show hidden reasoning, prompts, raw model thoughts, or chain-of-thought.

## Reasoning Trace

Every Trek-assisted response can carry:

```json
{
  "matchedTrek": "...",
  "toolsUsed": [],
  "sourceFiles": [],
  "executionTimeMs": 0
}
```

This is built by `ToolRegistryService` while tools execute.

Example:

```json
{
  "matchedTrek": "everest_base_camp",
  "toolsUsed": ["get_route_info"],
  "sourceFiles": ["everest_base_camp_trek_data.json"],
  "executionTimeMs": 2
}
```

## Tool History

Every tool execution records:

- tool name
- arguments
- timestamp
- execution time
- source file

This supports:

- `get_used_tools()`
- `get_tool_history()`
- `get_reasoning_trace()`

These are runtime/session tools. They are handled by the registry and do not require network access.

## Offline Behavior

All Trek Knowledge data comes from bundled local JSON assets under `trek_info/`.

No network calls are required for:

- tool selection
- validation
- tool execution
- tool result synthesis
- reasoning trace display
- tool history

The only required runtime dependency is that a local LLM model must be loaded for model-based selection and final answer synthesis. If tool selection fails, the app can still use the Dart fallback detector for Trek queries.

## Error Handling

The architecture is defensive:

- Unknown tool names are rejected by the registry.
- Invalid arguments return standardized error results.
- If the LLM returns invalid tool-selection JSON, the app falls back to local intent detection.
- If no model is loaded, the app shows the existing model-loading guidance.
- If a tool returns `success: false`, the synthesis prompt instructs the model to explain that the information is unavailable.

## Verification

After the integration:

```text
flutter analyze
```

passed with no issues.

```text
flutter test
```

passed all tests.
