#!/usr/bin/env bash
# Gemini CLI adapter

_AI_CMD="gemini"
_AI_ERR_MSG="Gemini CLI not found. Install with: npm install -g @google/gemini-cli"
_AI_INFO_LINES=(
  "Or: brew install gemini-cli"
  "See https://github.com/google-gemini/gemini-cli for more info"
)
_ai_define_standard
