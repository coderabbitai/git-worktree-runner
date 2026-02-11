#!/usr/bin/env bash
# OpenAI Codex CLI adapter

_AI_CMD="codex"
_AI_ERR_MSG="Codex CLI not found. Install with: npm install -g @openai/codex"
_AI_INFO_LINES=(
  "Or: brew install codex"
  "See https://github.com/openai/codex for more info"
)
_ai_define_standard
