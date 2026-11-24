import type { NextConfig } from "next";

const STAGING_URL = "https://qqiiznmqxfoamqytjica.supabase.co";
const STAGING_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFxaWl6bm1xeGZvYW1xeXRqaWNhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIxODQ2NjksImV4cCI6MjA5Nzc2MDY2OX0.e4v0-wkAwchas5NMF7QIDvUDW32Y7V7Rl8WF4_BC0OA";

const securityHeaders = [
  { key: "X-Frame-Options", value: "DENY" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains; preload" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
];

const nextConfig: NextConfig = {
  env: {
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL || STAGING_URL,
    NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || STAGING_ANON_KEY,
  },
  async headers() {
    return [
      {
        source: "/(.*)",
        headers: securityHeaders,
      },
    ];
  },
};

export default nextConfig;
