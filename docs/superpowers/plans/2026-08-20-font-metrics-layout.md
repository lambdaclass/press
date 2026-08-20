# Font Metrics + Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `Press.Font.Metrics` (AFM font metrics & text measurement) and `Press.Layout` (styled tree → positioned geometric box tree) — Phase 4 of `press`.

**Architecture:** 
- `Press.Font.Metrics`: character width tables for standard PDF base fonts, font selector (`font_for/3`), and string measurement (`text_width/3`).
- `Press.Layout.Box`: box tree data structures representing rectangular blocks, lines, text fragments, and table cells.
- `Press.Layout.Inline`: whitespace collapsing, greedy word-wrapping, and text alignment.
- `Press.Layout.Block`: block formatting context, vertical flow, percentage resolution, and margin collapsing.
- `Press.Layout.Table`: column width calculation, table cell layout, and row height alignment.
- `Press.Layout`: public entry point (`Press.Layout.build/2`).

**Tech Stack:** Elixir, ExUnit. Zero runtime dependencies.

---

## Task 1: `Press.Font.Metrics` — AFM font metrics and text measurement

**Files:**
- Create: `lib/press/font/metrics.ex`
- Test: `test/press/font/metrics_test.exs`

- [x] **Step 1: Write the failing tests**
- [x] **Step 2: Run the tests to verify they fail**
- [x] **Step 3: Write the implementation**
- [x] **Step 4: Run the tests to verify they pass**
- [x] **Step 5: Commit**

---

## Task 2: `Press.Layout.Box` — Box tree data model

**Files:**
- Create: `lib/press/layout/box.ex`
- Test: `test/press/layout/box_test.exs`

- [x] **Step 1: Write the failing tests**
- [x] **Step 2: Run the tests to verify they fail**
- [x] **Step 3: Write the implementation**
- [x] **Step 4: Run the tests to verify they pass**
- [x] **Step 5: Commit**

---

## Task 3: `Press.Layout.Inline` — Line wrapping and text alignment

**Files:**
- Create: `lib/press/layout/inline.ex`
- Test: `test/press/layout/inline_test.exs`

- [x] **Step 1: Write the failing tests**
- [x] **Step 2: Run the tests to verify they fail**
- [x] **Step 3: Write the implementation**
- [x] **Step 4: Run the tests to verify they pass**
- [x] **Step 5: Commit**

---

## Task 4: `Press.Layout.Block` — Block layout, vertical flow & margin collapse

**Files:**
- Create: `lib/press/layout/block.ex`
- Test: `test/press/layout/block_test.exs`

- [x] **Step 1: Write the failing tests**
- [x] **Step 2: Run the tests to verify they fail**
- [x] **Step 3: Write the implementation**
- [x] **Step 4: Run the tests to verify they pass**
- [x] **Step 5: Commit**

---

## Task 5: `Press.Layout.Table` — Table layout & column widths

**Files:**
- Create: `lib/press/layout/table.ex`
- Test: `test/press/layout/table_test.exs`

- [x] **Step 1: Write the failing tests**
- [x] **Step 2: Run the tests to verify they fail**
- [x] **Step 3: Write the implementation**
- [x] **Step 4: Run the tests to verify they pass**
- [x] **Step 5: Commit**

---

## Task 6: `Press.Layout` — Public layout engine entry point

**Files:**
- Create: `lib/press/layout.ex`
- Test: `test/press/layout_test.exs`

- [x] **Step 1: Write the failing tests**
- [x] **Step 2: Run the tests to verify they fail**
- [x] **Step 3: Write the implementation**
- [x] **Step 4: Run the tests to verify they pass**
- [x] **Step 5: Commit**

---

## Task 7: End-to-end integration test

**Files:**
- Test: `test/press/layout/integration_test.exs`

- [x] **Step 1: Write the failing test**
- [x] **Step 2: Run the test**
- [x] **Step 3: Run the full test suite**
- [x] **Step 4: Commit**
