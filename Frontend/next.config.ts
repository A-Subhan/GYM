import type { NextConfig } from "next";

// Backend API location. All /api/* and /uploads/* requests made by the UI are
// proxied to the backend server (default http://localhost:4000), so the
// browser stays same-origin and the session cookie flows through unchanged.
const BACKEND_URL = process.env.BACKEND_URL || "http://localhost:4000";

const nextConfig: NextConfig = {
  typescript: {
    ignoreBuildErrors: true,
  },
  reactStrictMode: false,
  async rewrites() {
    return [
      { source: "/api/:path*", destination: `${BACKEND_URL}/api/:path*` },
      { source: "/uploads/:path*", destination: `${BACKEND_URL}/uploads/:path*` },
    ];
  },
};

export default nextConfig;
