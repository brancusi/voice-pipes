import Foundation

/// JSON Schemas for config.toml and vocabulary.toml, written beside them so editors (Taplo, Even Better TOML) and
/// agents can validate before saving. `vp config schema` prints the config one.
enum ConfigSchema {
    static let config = #"""
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "$id": "https://voicepipes.app/schema/config-1.json",
      "title": "Voice Pipes config.toml",
      "description": "Tracks (hotkey-triggered pipelines of blocks) and settings for Voice Pipes. Keys and secrets never go here: use `vp auth` and `vp secret`.",
      "type": "object",
      "additionalProperties": false,
      "required": ["version", "track"],
      "properties": {
        "version": { "const": 1, "description": "File format version." },
        "settings": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "appearance": { "enum": ["auto", "daylight", "sundown"], "default": "auto", "description": "auto follows macOS; the HUD stays dark either way." },
            "input": { "type": "string", "minLength": 1, "default": "system", "description": "Which mic tracks record from: \"system\" (follows macOS) or a mic's name (`vp inputs`). A track's Microphone block can name its own." },
            "microphone": { "enum": ["always", "after-use", "off"], "default": "always", "description": "Keep the microphone open between takes so a take starts instantly and keeps the half second before the press: always, for 5 minutes after each take, or off (opened per take). Bluetooth mics are never kept open." }
          }
        },
        "track": { "type": "array", "items": { "$ref": "#/$defs/track" } }
      },
      "$defs": {
        "track": {
          "type": "object",
          "additionalProperties": false,
          "required": ["id", "name", "step"],
          "properties": {
            "id": { "type": "string", "pattern": "^[a-z0-9]+(-[a-z0-9]+)*$", "description": "Unique; what `vp run <id>` uses." },
            "name": { "type": "string", "minLength": 1 },
            "color": {
              "anyOf": [
                { "enum": ["apricot", "dusk-blue", "lavender", "sage", "marigold", "rose", "red-rock"] },
                { "type": "string", "pattern": "^#[0-9A-Fa-f]{6}$" }
              ]
            },
            "enabled": { "type": "boolean", "default": true },
            "hotkeys": {
              "type": "array",
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["keys"],
                "properties": {
                  "keys": { "type": "string", "description": "Modifiers then one key, joined with +: \"option+space\", \"control+shift+r\", \"command+f5\"." },
                  "mode": { "enum": ["hold", "toggle", "once"], "default": "toggle", "description": "hold: runs while held. toggle: press to start and stop. once: each press runs it once (a microphone track records until you pause)." }
                }
              }
            },
            "step": { "type": "array", "minItems": 1, "items": { "$ref": "#/$defs/step" } }
          }
        },
        "step": {
          "type": "object",
          "required": ["type"],
          "properties": { "type": { "enum": ["microphone", "text", "transcribe", "llm", "route", "branch", "http", "template", "fix-words", "paste", "copy", "speak", "show-hud"] } },
          "oneOf": [
            { "properties": { "type": { "const": "microphone" }, "input": { "type": "string", "description": "\"system\" (follows macOS) or a mic's name (`vp inputs`). Leave out to use [settings] input. Bluetooth mics are never kept open, so they start a little later." } }, "additionalProperties": false, "description": "Records a microphone. — → audio" },
            { "properties": { "type": { "const": "text" }, "sources": { "type": "array", "items": { "enum": ["selection", "page", "clipboard", "previous-clipboard"] } } }, "additionalProperties": false, "description": "The first source with text. — → text" },
            { "properties": { "type": { "const": "transcribe" }, "model": { "type": "string", "default": "parakeet", "description": "\"parakeet\" (on this Mac) or an OpenRouter transcription model id." }, "mode": { "enum": ["on-release", "pause-chunks", "streaming"], "default": "on-release" }, "pause_ms": { "type": "integer", "minimum": 300, "maximum": 1200, "default": 500 } }, "additionalProperties": false, "description": "audio → text" },
            { "properties": { "type": { "const": "llm" }, "model": { "type": "string", "description": "An OpenRouter model id." }, "prompt": { "type": "string", "description": "Instructions; {{input}} places the text, otherwise it's the user message." }, "on_failure": { "enum": ["pass-through", "stop"], "default": "pass-through" } }, "required": ["model"], "additionalProperties": false, "description": "text → text" },
            { "properties": { "type": { "const": "route" }, "route": { "type": "array", "minItems": 1, "items": { "type": "object", "additionalProperties": false, "required": ["name", "model"], "properties": { "name": { "type": "string" }, "when": { "type": "string", "description": "What Jev chooses this route by." }, "model": { "type": "string" }, "prompt": { "type": "string" } } } } }, "required": ["route"], "additionalProperties": false, "description": "Jev picks a route; its model answers. text → text" },
            { "properties": { "type": { "const": "branch" }, "question": { "type": "string", "description": "What Jev decides about the text, e.g. how hard it is to read aloud." }, "branch": { "type": "array", "items": { "type": "object", "additionalProperties": false, "required": ["name"], "properties": { "name": { "type": "string" }, "when": { "type": "string", "description": "What Jev chooses this branch by." }, "step": { "type": "array", "items": { "$ref": "#/$defs/step" }, "description": "This branch's blocks; none passes the text through." } } } } }, "required": ["branch"], "additionalProperties": false, "description": "Jev picks a branch; its own steps run. text → what the branches give" },
            { "properties": { "type": { "const": "http" }, "url": { "type": "string" }, "method": { "enum": ["GET", "POST", "PUT", "PATCH"], "default": "POST" }, "headers": { "type": "object", "additionalProperties": { "type": "string" } }, "body": { "type": "string" }, "response_field": { "type": "string", "description": "Dotted path into a JSON reply; empty = whole body." } }, "required": ["url"], "additionalProperties": false, "description": "{{input}}, {{input_json}}, ${secret:name}, ${env:NAME}. text → text" },
            { "properties": { "type": { "const": "template" }, "template": { "type": "string" } }, "required": ["template"], "additionalProperties": false, "description": "text → text" },
            { "properties": { "type": { "const": "fix-words" } }, "additionalProperties": false, "description": "vocabulary.toml, on this Mac. text → text" },
            { "properties": { "type": { "const": "paste" }, "restore_clipboard": { "type": "boolean", "default": true } }, "additionalProperties": false, "description": "Pastes at the cursor. text → text" },
            { "properties": { "type": { "const": "copy" } }, "additionalProperties": false, "description": "text → text" },
            { "properties": { "type": { "const": "speak" }, "model": { "type": "string", "default": "pocket", "description": "pocket | supertonic | macos | an OpenRouter speech model id." }, "voice": { "type": "string" }, "speed": { "type": "number", "minimum": 0.6, "maximum": 2.0, "default": 1.0 } }, "additionalProperties": false, "description": "text → —" },
            { "properties": { "type": { "const": "show-hud" } }, "additionalProperties": false, "description": "text → text" }
          ]
        }
      }
    }
    """#

    static let vocabulary = #"""
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "$id": "https://voicepipes.app/schema/vocabulary-1.json",
      "title": "Voice Pipes vocabulary.toml",
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "version": { "const": 1 },
        "word": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["write"],
            "properties": {
              "write": { "type": "string", "minLength": 1, "description": "The spelling you want." },
              "heard_as": { "type": "array", "items": { "type": "string" }, "description": "What transcription writes instead." },
              "always_exact": { "type": "boolean", "default": false }
            }
          }
        }
      }
    }
    """#
}
