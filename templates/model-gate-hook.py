#!/usr/bin/env python3
# model-gate-hook.py - send each sub-agent to the cheaper model unless the
# launch names a reason for the strongest one (rules D-6 and B-16).
#
# Install it as a hook that runs before each launch of a sub-agent (in Claude
# Code: a PreToolUse hook with the matcher "Agent", command
# "python3 -I <path>/model-gate-hook.py"). The hook reads the launch as JSON on
# standard input. To refuse, it exits with 2 and prints the reason; the tool
# gives that reason to the orchestrator, which launches again.
#
# A launch passes when it names a model that is not in JIDOKA_STRONG_MODELS, or
# when its description starts with JIDOKA_STRONG_TAG. A launch that names no
# model gets the model of the session, so the hook treats it as strong.
# Agent types in JIDOKA_GATE_FREE_TYPES pick their own model and always pass.
#
# Variables (fill them per project, or keep the defaults):
#   JIDOKA_STRONG_MODELS    names of the strongest model, with a space between
#                           them (default "opus")
#   JIDOKA_STRONG_TAG       the start of a description that names the reason
#                           (default "[strong:")
#   JIDOKA_GATE_FREE_TYPES  agent types that always pass (default "fork Explore")
#
# Exit codes: 0 the launch passes; 2 the launch is refused.

import json
import os
import sys

strong = os.environ.get("JIDOKA_STRONG_MODELS", "opus").lower().split()
tag = os.environ.get("JIDOKA_STRONG_TAG", "[strong:").lower()
free = os.environ.get("JIDOKA_GATE_FREE_TYPES", "fork Explore").split()

launch = (json.load(sys.stdin).get("tool_input") or {})
model = (launch.get("model") or "").lower()
kind = launch.get("subagent_type") or "general-purpose"
description = (launch.get("description") or "").lstrip().lower()

if kind in free:
    sys.exit(0)
if (model == "" or model in strong) and not description.startswith(tag):
    sys.stderr.write(
        "Model gate (B-16): name the cheaper model for builds, fix rounds, "
        "merges, reviews of routine code, research and walks. The strongest "
        "model takes screens, design, copy, risky code and judgement only: "
        "start the description with \"" + tag + " <reason>]\" and launch "
        "again.\n")
    sys.exit(2)
