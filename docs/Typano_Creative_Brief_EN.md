# Typano — Creative Brief

**Project Name:** Typano (Type + Piano)
**Document Purpose:** A record of the original creative vision and intent, for handoff to development
**Date:** August 2026

---

## 1. Naming

**Typano** is a portmanteau of Type + Piano, directly capturing the product's core idea: playing music through the act of typing.

---

## 2. Origin: The Core Pain Point

On Windows, there are applications purpose-built for "keyboard music," such as Free Piano. On Mac OS, no directly comparable product exists.

While software such as KuGou Live (酷乐队) includes similar functionality, it falls short in key ways:

- It is not designed specifically for keyboard music — the feature is secondary, not core.
- The range of playable timbres/instrument sounds is very limited.
- The key mapping is incomplete, covering only a small subset of the keyboard rather than all keys.

This gap led to the initial concept of building a **Mac OS–exclusive keyboard music application**.

---

## 3. Core Functionality

Map the computer keyboard to piano keys, enabling the user to play piano music using the keyboard.

**Initial goal:** enable the playing of basic piano pieces.

---

## 4. Why Mac OS

1. **Sound quality advantage:** MacBooks have a strong soundstage and excellent built-in speaker output, producing genuinely good audio quality.
2. **Portability and battery life:** Particularly the MacBook Air — highly portable with long battery life, well suited as an on-the-go music device.
3. **Screen advantage:** High display fidelity enables interesting visual light effects — for example, triggering a note could produce a corresponding light effect on screen.

---

## 5. Future Expansion Directions

1. **Additional instrument types:** not limited to piano timbres.
2. **Mapping rule refinement:**
   - A single key need not correspond to only one sound.
   - When playing different types of music, the app could switch between preset mapping rule sets, or merge multiple mapping rules together.
3. **Partial customization support:**
   - Allow users to customize a limited number of keys to create additional effects.
   - **Full customization will not be supported.** If any arbitrary sequence of keystrokes could produce a melody, it would undermine the core logic that playing music requires practice to become fluent — such a design would be fundamentally unreasonable. This boundary is a deliberate product principle, not a technical limitation.

---

## 6. Core Product Philosophy

This represents the most important self-correction in the evolution of the concept, and the guiding principle throughout:

> **Typano is not a "Piano Simulator." It is not meant to compete with real instruments on the dimension of realism.**

Instead, Typano should create "**a music genre native to the computer itself**" — by leveraging the MacBook's own soundstage, screen-based light effects, and the flexibility of customizable key mapping, to create a musical experience that **only a computer is capable of producing**.

This implies:

- The project should not be designed around "compensating for the keyboard's shortcomings as a musical instrument" (for example, it should not chase realistic velocity/touch-sensitivity simulation as a design goal in itself).
- The project should focus on the computer's native strengths — soundstage, light effects, programmability, and flexibility — qualities that real instruments do not possess.
- If an AI model is later introduced to predict per-key velocity for a given piece, its purpose is to make the playing experience match the intended musical feel — not to simulate the physical velocity sensitivity of a real piano.

**Summary:** The software should leverage the MacBook's soundstage advantage, screen advantage, and the computer's inherent programmability and flexibility, while also taking advantage of the fact that a computer keyboard is naturally well-suited for playing music — creating a Mac-native keyboard music product distinct both from traditional instruments and from comparable software on other platforms.

---

## 7. Project Nature

Typano is currently intended as a **personal passion project**, not conceived from the outset as a product to be formally shipped and distributed. The initial goal is to build it for personal use. Whether and how to distribute it publicly is a decision to be made later.
