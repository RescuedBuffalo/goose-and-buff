---
name: long-watch-design
description: Use this skill to generate well-branded interfaces and assets for The Long Watch (a private 3-player co-op Roblox roguelite featuring three animal-totem heroes — Goose, Buffalo, Fox — and their shared Australian Shepherd companion Val), either for production Roblox UI specs, Blender character briefs, or throwaway prototypes/mocks. Contains essential design guidelines, colors, type, fonts, assets, and UI kit components for prototyping.
user-invocable: true
---

Read the README.md file within this skill, and explore the other available files (colors_and_type.css, ui_kits/, assets/, src/).

If creating visual artifacts (slides, mocks, throwaway prototypes, character briefs, HUD specs), copy assets out and create static HTML files for the user to view. The canonical color palette lives in `src/shared/Data/Sectors.lua` and is mirrored in `colors_and_type.css` — never invent new hero colors; extend from there.

If working on production Roblox code, read `src/` for the existing Lua patterns and use the CSS tokens as the source of truth for any UI you build (Color3.fromRGB values are documented in `colors_and_type.css` comments).

If the user invokes this skill without any other guidance, ask them what they want to build or design (HUD screen? Character brief? Title card? Wave-banner mockup?), ask 2–3 clarifying questions, and act as an expert designer who outputs HTML artifacts _or_ production code, depending on the need.

Voice rules (non-negotiable): warm, opinionated, never ironic. Sentence case in UI. No emoji. Hero names always written in full (Goose / Buffalo / Fox / Val).
