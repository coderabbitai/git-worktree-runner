#!/usr/bin/env bash
# GitHub Copilot CLI adapter

_AI_CMD="copilot"
_AI_ERR_MSG="GitHub Copilot CLI not found."
_AI_INFO_LINES=(
  "Install with: npm install -g @github/copilot"
  "Or: brew install copilot-cli"
  "See https://github.com/github/copilot-cli for more information"
)
_ai_define_standard
