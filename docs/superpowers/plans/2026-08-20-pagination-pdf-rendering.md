# Pagination + PDF Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `Press.Layout.Page`, `Press.Layout.Paginate`, `Press.PDF.Renderer`, and public `Press.render/2` — Phase 5 of `press`.

**Architecture:**
- `Press.Layout.Page`: page data structure containing dimensions and positioned boxes.
- `Press.Layout.Paginate`: splits the laid-out box tree into discrete pages, handles `<header>`/`<footer>` repetition, `page-break-*`, and table continuation across page boundaries.
- `Press.PDF.Renderer`: converts paginated boxes into PDF operations (`:text`, `:rect`) with correct PDF bottom-left coordinate transforms.
- `Press`: public entry point `Press.render(html, opts \\ [])`.

**Tech Stack:** Elixir, ExUnit. Zero runtime dependencies.

---

## Task 1: `Press.Layout.Page` — Page data model

**Files:**
- Create: `lib/press/layout/page.ex`
- Test: `test/press/layout/page_test.exs`

- [x] **Step 1: Write the failing tests**
- [x] **Step 2: Run the tests to verify they fail**
- [x] **Step 3: Write the implementation**
- [x] **Step 4: Run the tests to verify they pass**
- [x] **Step 5: Commit**

---

## Task 2: `Press.Layout.Paginate` — Page breaking & pagination engine

**Files:**
- Create: `lib/press/layout/paginate.ex`
- Test: `test/press/layout/paginate_test.exs`

- [x] **Step 1: Write the failing tests**
- [x] **Step 2: Run the tests to verify they fail**
- [x] **Step 3: Write the implementation**
- [x] **Step 4: Run the tests to verify they pass**
- [x] **Step 5: Commit**

---

## Task 3: `Press.PDF.Renderer` — PDF coordinate transforms & drawing

**Files:**
- Create: `lib/press/pdf/renderer.ex`
- Test: `test/press/pdf/renderer_test.exs`

- [x] **Step 1: Write the failing tests**
- [x] **Step 2: Run the tests to verify they fail**
- [x] **Step 3: Write the implementation**
- [x] **Step 4: Run the tests to verify they pass**
- [x] **Step 5: Commit**

---

## Task 4: `Press.render/2` — Public API

**Files:**
- Modify: `lib/press.ex`
- Test: `test/press_test.exs`

- [x] **Step 1: Write the failing tests**
- [x] **Step 2: Run the tests to verify they fail**
- [x] **Step 3: Write the implementation**
- [x] **Step 4: Run the tests to verify they pass**
- [x] **Step 5: Commit**

---

## Task 5: End-to-end invoice document integration test

**Files:**
- Create: `test/press/integration_test.exs`

- [x] **Step 1: Write the failing test**
- [x] **Step 2: Run the test**
- [x] **Step 3: Run the full test suite**
- [x] **Step 4: Commit**
