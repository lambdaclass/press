# Image Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build pure-Elixir JPEG and PNG image decoding, layout scaling, and PDF XObject embedding (`/DCTDecode` and `/FlateDecode` with `/SMask`) for `<img>` tags — Phase 6 of `press`.

**Architecture:**
- `Press.Image`: image data model.
- `Press.Image.JPEG`: JPEG SOF marker parser for intrinsic dimensions and color space.
- `Press.Image.PNG`: PNG chunk parser, `:zlib` IDAT decompressor, scanline unfilter, and alpha channel separation.
- `Press.Image.Parser`: data URI (`data:image/...;base64,...`) and `opts[:images]` lookup.
- `Press.PDF`: image operations in `Document`, `ContentStream`, and `/XObject` writing in `Writer`.
- `Press.Layout` & `Press`: `<img>` element layout and end-to-end rendering.

**Tech Stack:** Elixir, Erlang `:zlib` (built-in OTP), ExUnit. Zero external Hex runtime dependencies.

---

## Task 1: `Press.Image` & `Press.Image.JPEG` — Image struct & JPEG decoder

**Files:**
- Create: `lib/press/image.ex`
- Create: `lib/press/image/jpeg.ex`
- Test: `test/press/image/jpeg_test.exs`

- [x] **Step 1: Write the failing tests**
- [x] **Step 2: Run the tests to verify they fail**
- [x] **Step 3: Write the implementation**
- [x] **Step 4: Run the tests to verify they pass**
- [x] **Step 5: Commit**

---

## Task 2: `Press.Image.PNG` — PNG decoder & alpha separation

**Files:**
- Create: `lib/press/image/png.ex`
- Test: `test/press/image/png_test.exs`

- [x] **Step 1: Write the failing tests**
- [x] **Step 2: Run the tests to verify they fail**
- [x] **Step 3: Write the implementation**
- [x] **Step 4: Run the tests to verify they pass**
- [x] **Step 5: Commit**

---

## Task 3: `Press.Image.Parser` — Unified image loader

**Files:**
- Create: `lib/press/image/parser.ex`
- Test: `test/press/image/parser_test.exs`

- [x] **Step 1: Write the failing tests**
- [x] **Step 2: Run the tests to verify they fail**
- [x] **Step 3: Write the implementation**
- [x] **Step 4: Run the tests to verify they pass**
- [x] **Step 5: Commit**

---

## Task 4: `Press.PDF` Image Drawing & `/XObject` Writer

**Files:**
- Modify: `lib/press/pdf/document.ex`
- Modify: `lib/press/pdf/content_stream.ex`
- Modify: `lib/press/pdf/writer.ex`
- Modify: `lib/press/pdf/renderer.ex`
- Test: `test/press/pdf/image_writer_test.exs`

- [x] **Step 1: Write the failing tests**
- [x] **Step 2: Run the tests to verify they fail**
- [x] **Step 3: Write the implementation**
- [x] **Step 4: Run the tests to verify they pass**
- [x] **Step 5: Commit**

---

## Task 5: `<img>` Layout & End-to-End Image Integration

**Files:**
- Modify: `lib/press/layout.ex`
- Modify: `lib/press/layout/box.ex`
- Modify: `lib/press.ex`
- Test: `test/press/image_integration_test.exs`

- [x] **Step 1: Write the failing test**
- [x] **Step 2: Run the test**
- [x] **Step 3: Run the full test suite**
- [x] **Step 4: Commit**
