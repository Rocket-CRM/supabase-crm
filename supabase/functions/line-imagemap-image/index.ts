import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { Image } from "https://deno.land/x/imagescript@1.3.0/mod.ts";

// LINE imagemap fetcher: GET <baseUrl>/<width>, no auth headers.
// Route: /line-imagemap-image/<base64url(storage object path | public URL)>/<width>
const ALLOWED_WIDTHS = new Set([240, 300, 460, 700, 1040]);
const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
const PUBLIC_PREFIX = `${SUPABASE_URL}/storage/v1/object/public/`;
const CACHE_HEADERS = { "Cache-Control": "public, max-age=31536000, immutable" };

function notFound() {
  return new Response("Not found", { status: 404 });
}

function decodeBase64Url(s: string): string | null {
  try {
    const b64 = s.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(s.length / 4) * 4, "=");
    return new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)));
  } catch {
    return null;
  }
}

function toObjectPath(decoded: string): string | null {
  let path = decoded;
  if (/^https?:\/\//i.test(path)) {
    if (!path.startsWith(PUBLIC_PREFIX)) return null;
    path = path.slice(PUBLIC_PREFIX.length);
  }
  path = path.split("?")[0].replace(/^\/+/, "");
  if (!path.includes("/") || path.split("/").some((seg) => seg === "" || seg === "." || seg === "..")) return null;
  return path;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "GET" && req.method !== "HEAD") return new Response("Method not allowed", { status: 405 });

  const parts = new URL(req.url).pathname.split("/").filter(Boolean);
  const fnIndex = parts.indexOf("line-imagemap-image");
  const [encoded, widthStr] = parts.slice(fnIndex + 1);
  if (fnIndex === -1 || !encoded || !widthStr || parts.length !== fnIndex + 3) return notFound();

  const width = Number(widthStr);
  if (!/^\d+$/.test(widthStr) || !ALLOWED_WIDTHS.has(width)) return notFound();

  const decoded = decodeBase64Url(encoded);
  const objectPath = decoded ? toObjectPath(decoded) : null;
  if (!objectPath) return notFound();

  const encodedPath = objectPath.split("/").map(encodeURIComponent).join("/");
  const renderUrl = `${SUPABASE_URL}/storage/v1/render/image/public/${encodedPath}?width=${width}&resize=contain&format=origin`;
  const upstream = await fetch(renderUrl);
  if (!upstream.ok || !(upstream.headers.get("content-type") ?? "").startsWith("image/")) return notFound();

  const bytes = new Uint8Array(await upstream.arrayBuffer());
  const image = await Image.decode(bytes);
  // Storage render never upscales; LINE expects the exact requested width.
  if (image.width !== width) image.resize(width, Image.RESIZE_AUTO);
  const png = await image.encode(1);

  return new Response(req.method === "HEAD" ? null : png, {
    status: 200,
    headers: { "Content-Type": "image/png", "Content-Length": String(png.byteLength), ...CACHE_HEADERS },
  });
});
