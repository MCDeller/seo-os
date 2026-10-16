/**
 * Tests that ADC detection honours CLOUDSDK_CONFIG, so installs with
 * isolated gcloud config dirs don't read each other's sign-in.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import fsp from "node:fs/promises";
import os from "node:os";
import path from "node:path";

test("adcFilePath follows CLOUDSDK_CONFIG and falls back to ~/.config/gcloud", async () => {
  const { adcFilePath, readAdcFileSync } = await import("../gcloud.ts");
  const previous = process.env.CLOUDSDK_CONFIG;
  const dir = await fsp.mkdtemp(path.join(os.tmpdir(), "seo-office-gcloud-"));
  try {
    process.env.CLOUDSDK_CONFIG = dir;
    assert.equal(
      adcFilePath(),
      path.join(dir, "application_default_credentials.json"),
    );
    assert.equal(readAdcFileSync(), null);
    await fsp.writeFile(
      path.join(dir, "application_default_credentials.json"),
      JSON.stringify({ type: "authorized_user", client_id: "isolated" }),
    );
    assert.equal(readAdcFileSync()?.client_id, "isolated");

    delete process.env.CLOUDSDK_CONFIG;
    assert.equal(
      adcFilePath(),
      path.join(os.homedir(), ".config", "gcloud", "application_default_credentials.json"),
    );
  } finally {
    if (previous === undefined) delete process.env.CLOUDSDK_CONFIG;
    else process.env.CLOUDSDK_CONFIG = previous;
    await fsp.rm(dir, { recursive: true, force: true });
  }
});
