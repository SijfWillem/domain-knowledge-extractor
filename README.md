# DKE — Domain Knowledge Extractor

A macOS app that captures domain knowledge from meetings and conversations in real-time. DKE listens to what's being said, extracts knowledge atoms, and suggests high-reward follow-up questions to help interviewers dig deeper.

## What it does

- **Live transcription** — Captures mic audio (your voice) and system audio (remote participants) using Apple's Speech framework
- **Knowledge extraction** — AI identifies domain knowledge from the transcript every 30s, categorized as processes, heuristics, decisions, terminology, relationships, exceptions, or tacit assumptions
- **Smart nudges** — Generates high-reward interview questions every 15s using three techniques:
  - **Force a choice** — "If you could only keep X or Y, which matters more?"
  - **Speculate** — "What would break first if X doubled in volume?"
  - **Make it personal** — "What would YOUR ideal outcome look like?"
- **Pinnable questions** — Click a nudge to pin it; new suggestions stack on top
- **Session history** — Browse past sessions with full transcripts grouped by speaker
- **Knowledge base** — Search and browse all extracted knowledge across sessions

## Requirements

- macOS 14.0+
- Xcode 15.0+
- An LLM provider (Ollama running locally by default)

## Setup

1. Clone the repo and open `DKE.xcodeproj` in Xcode
2. Build and run (Cmd+R)
3. Grant permissions when prompted: microphone, speech recognition, and screen capture (for virtual mode)
4. Install [Ollama](https://ollama.ai) and pull a model:
   ```
   ollama pull llama3.2:3b
   ```

### Using other LLM providers

In Settings, you can register additional providers:
- **Ollama** (default) — local inference at `localhost:11434`
- **Anthropic Claude** — requires API key
- **OpenAI-compatible** — any OpenAI-compatible endpoint

Each task (analysis, nudge generation) can be assigned to a different provider.

## Usage

1. Click **New Session** in the sidebar to open the recording widget
2. Choose **In-Person** (mic only) or **Virtual** (mic + system audio for remote meetings)
3. Press **Record** — the app transcribes speech and generates nudges automatically
4. Click a nudge to pin it so it stays visible
5. Press **Stop** — the session is saved with its transcript and extracted knowledge

## Project structure

```
DKE/
├── Analysis/          # Knowledge extraction + nudge generation prompts
├── App/               # Session orchestrator (coordinates all components)
├── Audio/             # Mic capture (AVCaptureSession) + system audio (ScreenCaptureKit)
├── Models/            # LLM provider abstraction (Ollama, Anthropic, OpenAI)
├── Transcription/     # Speech-to-text (Apple Speech framework)
├── KnowledgeBase/     # Core Data persistence, browse/search UI
├── Sessions/          # Session history + detail views
├── Settings/          # Model config, language, prompt customization
└── Widget/            # Floating panel with controls, nudges, live transcript
```

## Audio design

DKE is designed to not interfere with your audio:
- Uses `AVCaptureSession` instead of `AVAudioEngine` so it doesn't take over the audio hardware
- Prefers the built-in Mac microphone over Bluetooth to avoid triggering HFP (which downgrades Bluetooth audio to 8kHz mono)
- Captures system audio at native 48kHz stereo and downsamples to 16kHz mono in software only for speech recognition

## Language support

Supports English and Dutch. The language setting (in Settings) affects speech recognition locale and instructs the LLM to generate questions in the selected language.

## License

MIT
