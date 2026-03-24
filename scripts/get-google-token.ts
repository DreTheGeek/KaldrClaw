/**
 * One-time script to get a Google OAuth refresh token.
 * Run: npx tsx scripts/get-google-token.ts
 */

import { createServer } from "http";
import { exec } from "child_process";

const CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
const CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;

if (!CLIENT_ID || !CLIENT_SECRET) {
  console.error("Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET env vars first.");
  console.error("Example: GOOGLE_CLIENT_ID=xxx GOOGLE_CLIENT_SECRET=yyy npx tsx scripts/get-google-token.ts");
  process.exit(1);
}
const REDIRECT_URI = "http://localhost:3456/callback";
const SCOPES = [
  "https://www.googleapis.com/auth/gmail.readonly",
  "https://www.googleapis.com/auth/gmail.send",
  "https://www.googleapis.com/auth/calendar.readonly",
  "https://www.googleapis.com/auth/calendar.events",
].join(" ");

const authUrl = new URL("https://accounts.google.com/o/oauth2/v2/auth");
authUrl.searchParams.set("client_id", CLIENT_ID);
authUrl.searchParams.set("redirect_uri", REDIRECT_URI);
authUrl.searchParams.set("response_type", "code");
authUrl.searchParams.set("scope", SCOPES);
authUrl.searchParams.set("access_type", "offline");
authUrl.searchParams.set("prompt", "consent");

console.log("\n=== Google OAuth Token Generator ===\n");
console.log("Opening browser for Google sign-in...\n");

const server = createServer(async (req, res) => {
  const url = new URL(req.url!, `http://localhost:3456`);

  if (url.pathname === "/callback") {
    const code = url.searchParams.get("code");
    const error = url.searchParams.get("error");

    if (error) {
      console.error("\nAuth failed:", error);
      res.writeHead(400);
      res.end("Auth failed: " + error);
      process.exit(1);
    }

    if (!code) {
      res.writeHead(400);
      res.end("No code received");
      return;
    }

    console.log("Got auth code, exchanging for tokens...\n");

    const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        code,
        client_id: CLIENT_ID,
        client_secret: CLIENT_SECRET,
        redirect_uri: REDIRECT_URI,
        grant_type: "authorization_code",
      }),
    });

    const tokens = await tokenRes.json() as any;

    if (tokens.error) {
      console.error("Token exchange failed:", tokens.error_description);
      res.writeHead(400);
      res.end("Token exchange failed: " + tokens.error_description);
      process.exit(1);
    }

    console.log("=== SUCCESS ===\n");
    console.log("GOOGLE_REFRESH_TOKEN=" + tokens.refresh_token);
    console.log("\n^ Copy that value and add it as a Railway env var.\n");

    res.writeHead(200, { "Content-Type": "text/html" });
    res.end("<html><body><h1>Success!</h1><p>Check your terminal for the refresh token. You can close this tab.</p></body></html>");

    setTimeout(() => process.exit(0), 1000);
    return;
  }

  res.writeHead(404);
  res.end("Not found");
});

server.listen(3456, () => {
  // Open browser
  const openCmd = process.platform === "win32" ? "start" : process.platform === "darwin" ? "open" : "xdg-open";
  exec(`${openCmd} "${authUrl.toString()}"`);

  console.log("If the browser didn't open, go to:\n");
  console.log(authUrl.toString());
  console.log("\nWaiting for callback on http://localhost:3456...\n");
});
