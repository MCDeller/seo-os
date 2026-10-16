/**
 * Tests for src/lib/brain/minimal-intake.ts — slug handling.
 */
import { test } from "node:test";
import assert from "node:assert/strict";

test("minimal intake derives the slug from clientName by default", async () => {
  const { expandMinimalClientInput } = await import("../minimal-intake.ts");
  const input = expandMinimalClientInput({
    siteUrl: "https://termsofus.com",
    clientName: "Terms of Us",
  });
  assert.equal(input.slug, undefined);
  assert.equal(input.clientName, "Terms of Us");
});

test("minimal intake passes an explicit slug through", async () => {
  const { expandMinimalClientInput, looksMinimal } = await import(
    "../minimal-intake.ts"
  );
  const payload = {
    siteUrl: "https://termsofus.com",
    clientName: "Terms of Us",
    slug: "tou",
  };
  assert.equal(looksMinimal(payload), true);
  assert.equal(expandMinimalClientInput(payload).slug, "tou");
});

test("minimal intake rejects a malformed slug", async () => {
  const { expandMinimalClientInput } = await import("../minimal-intake.ts");
  assert.throws(() =>
    expandMinimalClientInput({ siteUrl: "https://termsofus.com", slug: "Bad Slug" }),
  );
});
