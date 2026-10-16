/**
 * POST /api/brain/reindex
 *
 * Re-indexes every client vault found on disk into index.db. Used after
 * restoring a database backup or moving a portal to a new machine, where the
 * vaults exist (e.g. on a synced drive) but the fresh index.db has no client
 * rows yet. Idempotent and cheap — only frontmatter is parsed.
 */
import { NextRequest, NextResponse } from "next/server";
import { reindexAll } from "@/lib/brain/index-db";
import { sameOriginWriteAllowed } from "@/lib/http/same-origin";

export const dynamic = "force-dynamic";

export async function POST(req: NextRequest) {
  const allowed = sameOriginWriteAllowed(req);
  if (allowed !== true) return allowed;
  try {
    const result = await reindexAll();
    return NextResponse.json({ ok: true, ...result });
  } catch (err) {
    return NextResponse.json(
      { ok: false, error: err instanceof Error ? err.message : String(err) },
      { status: 500 },
    );
  }
}
