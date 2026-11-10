import test from "node:test";
import assert from "node:assert/strict";

import { sanitizeOrTerm } from "../postgrest.ts";

test("sanitizeOrTerm: strips , ( ) \" \\ and trims whitespace", () => {
  assert.equal(sanitizeOrTerm("a,b"), "ab");
  assert.equal(sanitizeOrTerm("x)"), "x");
  assert.equal(sanitizeOrTerm("("), "");
  assert.equal(sanitizeOrTerm("\"quoted\""), "quoted");
  assert.equal(sanitizeOrTerm("path\\injection"), "pathinjection");
  assert.equal(sanitizeOrTerm("  (test,one)\"  "), "testone");
});

test("sanitizeOrTerm: preserves dots for decimals and domains", () => {
  assert.equal(sanitizeOrTerm("123.45"), "123.45");
  assert.equal(sanitizeOrTerm("example.com"), "example.com");
});

test("sanitizeOrTerm: preserves normal alphanumeric search terms and hyphens", () => {
  assert.equal(sanitizeOrTerm("Juan Santos Dela Cruz"), "Juan Santos Dela Cruz");
  assert.equal(sanitizeOrTerm("2030-36363"), "2030-36363");
  assert.equal(sanitizeOrTerm("Super 8 - Angeles"), "Super 8 - Angeles");
});

test("sanitizeOrTerm: handles null and undefined safely", () => {
  assert.equal(sanitizeOrTerm(null), "");
  assert.equal(sanitizeOrTerm(undefined), "");
  assert.equal(sanitizeOrTerm(""), "");
});
