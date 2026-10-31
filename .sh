mkdir -p app/api/track lib

cat > package.json <<'EOF'
{
  "name": "tiktok-tracker",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "next dev --webpack",
    "build": "next build --webpack",
    "start": "next start"
  },
  "dependencies": {
    "next": "^14.2.0",
    "react": "^18.3.0",
    "react-dom": "^18.3.0",
    "apify-client": "^2.9.0"
  },
  "devDependencies": {
    "typescript": "^5.4.0",
    "@types/node": "^20.0.0",
    "@types/react": "^18.3.0",
    "tailwindcss": "^3.4.0",
    "postcss": "^8.4.0",
    "autoprefixer": "^10.4.0"
  }
}
EOF

cat > .env.local <<'EOF'
SCAVIO_API_KEY=isi_di_sini
APIFY_TOKEN=isi_di_sini
EOF

cat > tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [{ "name": "next" }],
    "paths": { "@/*": ["./*"] }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}
EOF

cat > next.config.js <<'EOF'
/** @type {import('next').NextConfig} */
const nextConfig = {};
module.exports = nextConfig;
EOF

cat > postcss.config.js <<'EOF'
module.exports = {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
};
EOF

cat > tailwind.config.ts <<'EOF'
import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./app/**/*.{ts,tsx}'],
  theme: { extend: {} },
  plugins: [],
};
export default config;
EOF

cat > app/globals.css <<'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;
EOF

cat > app/layout.tsx <<'EOF'
import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'tiktok tracker',
  description: 'lacak profil publik TikTok',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="id">
      <body className="bg-zinc-950">{children}</body>
    </html>
  );
}
EOF

cat > lib/scavio.ts <<'EOF'
export interface ScavioRegionResult {
  username: string;
  country: string | null;
  user_id: string | null;
  sec_user_id: string | null;
  error: string | null;
}

export async function getRegion(username: string): Promise<ScavioRegionResult> {
  const clean = username.replace(/^@/, '').trim();
  if (!clean) {
    return { username: clean, country: null, user_id: null, sec_user_id: null, error: 'username kosong' };
  }
  try {
    const res = await fetch('https://api.scavio.dev/api/v1/tiktok/user/region', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${process.env.SCAVIO_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ username: clean }),
    });
    if (res.status === 404) {
      return { username: clean, country: null, user_id: null, sec_user_id: null, error: 'akun tidak ditemukan' };
    }
    if (!res.ok) {
      return { username: clean, country: null, user_id: null, sec_user_id: null, error: `scavio http ${res.status}` };
    }
    const data = await res.json();
    const payload = data?.data ?? data;
    return {
      username: clean,
      country: payload?.country ?? null,
      user_id: payload?.user_id ? String(payload.user_id) : null,
      sec_user_id: payload?.sec_user_id ?? null,
      error: null,
    };
  } catch (err: any) {
    return { username: clean, country: null, user_id: null, sec_user_id: null, error: err.message ?? 'scavio gagal' };
  }
}
EOF

cat > lib/apify.ts <<'EOF'
import { ApifyClient } from 'apify-client';

const client = new ApifyClient({ token: process.env.APIFY_TOKEN! });

export interface ApifyProfile {
  uniqueId: string;
  nickname: string;
  followerCount: number;
  followingCount: number;
  heartCount: number;
  videoCount: number;
  isVerified: boolean;
  region: string | null;
  language: string | null;
  accountCreatedAt: string | null;
  avatarUrl: string;
  bio: string;
}

export interface ApifyResult {
  profile: ApifyProfile | null;
  error: string | null;
}

const ACTOR_ID = 'futurizerush/tiktok-profile-scraper';

export async function getProfile(username: string): Promise<ApifyResult> {
  const clean = username.replace(/^@/, '').trim();
  if (!clean) return { profile: null, error: 'username kosong' };
  try {
    const run = await client.actor(ACTOR_ID).call({ usernames: [clean] });
    const { items } = await client.dataset(run.defaultDatasetId).listItems();
    if (!items || items.length === 0) return { profile: null, error: 'tidak ada hasil' };
    const raw = items[0] as any;
    if (raw.error) return { profile: null, error: raw.error };
    const profile: ApifyProfile = {
      uniqueId: raw.uniqueId ?? clean,
      nickname: raw.nickname ?? '',
      followerCount: raw.followerCount ?? 0,
      followingCount: raw.followingCount ?? 0,
      heartCount: raw.heartCount ?? 0,
      videoCount: raw.videoCount ?? 0,
      isVerified: raw.isVerified ?? false,
      region: raw.region ?? null,
      language: raw.language ?? null,
      accountCreatedAt: raw.accountCreatedAt ?? null,
      avatarUrl: raw.avatarUrl ?? '',
      bio: raw.bio ?? '',
    };
    return { profile, error: null };
  } catch (err: any) {
    return { profile: null, error: err.message ?? 'apify gagal' };
  }
}
EOF

cat > app/api/track/route.ts <<'EOF'
import { NextRequest, NextResponse } from 'next/server';
import { getRegion } from '@/lib/scavio';
import { getProfile } from '@/lib/apify';

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const username = body?.username;
    if (!username || typeof username !== 'string') {
      return NextResponse.json({ error: 'username wajib diisi' }, { status: 400 });
    }
    const [regionResult, apifyResult] = await Promise.all([
      getRegion(username),
      getProfile(username),
    ]);
    return NextResponse.json({
      region: regionResult,
      apify: apifyResult,
      scrapedAt: new Date().toISOString(),
    });
  } catch {
    return NextResponse.json({ error: 'request tidak valid' }, { status: 400 });
  }
}

export const runtime = 'nodejs';
export const maxDuration = 60;
EOF

cat > app/page.tsx <<'EOF'
'use client';

import { useState } from 'react';

interface RegionData { username: string; country: string | null; user_id: string | null; sec_user_id: string | null; error: string | null; }
interface ProfileData { uniqueId: string; nickname: string; followerCount: number; followingCount: number; heartCount: number; videoCount: number; isVerified: boolean; region: string | null; language: string | null; accountCreatedAt: string | null; avatarUrl: string; bio: string; }
interface TrackResponse { region: RegionData; apify: { profile: ProfileData | null; error: string | null }; scrapedAt: string; }

function fmt(n: number): string { return n.toLocaleString('id-ID'); }
function fmtDate(iso: string | null): string {
  if (!iso) return 'tidak tersedia';
  try { return new Date(iso).toLocaleString('id-ID', { year: 'numeric', month: 'long', day: 'numeric', hour: '2-digit', minute: '2-digit' }); }
  catch { return iso; }
}

export default function Home() {
  const [username, setUsername] = useState('');
  const [loading, setLoading] = useState(false);
  const [data, setData] = useState<TrackResponse | null>(null);

  async function handleTrack(e: React.FormEvent) {
    e.preventDefault();
    if (!username.trim()) return;
    setLoading(true);
    setData(null);
    try {
      const res = await fetch('/api/track', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username: username.trim() }),
      });
      const json = await res.json();
      setData(json);
    } catch {
      alert('gagal menghubungi server');
    } finally {
      setLoading(false);
    }
  }

  const profile = data?.apify?.profile;

  return (
    <main className="min-h-screen bg-zinc-950 text-zinc-100 p-6 md:p-12">
      <div className="max-w-3xl mx-auto space-y-8">
        <header className="space-y-2">
          <h1 className="text-3xl font-mono font-bold">tiktok tracker</h1>
          <p className="text-zinc-400 text-sm font-mono">negara (scavio) · followers · tanggal buat · profil (apify)</p>
          <p className="text-amber-500/80 text-xs font-mono border-l-2 border-amber-500/40 pl-3">negara &amp; tanggal buat adalah metadata publik, bukan field resmi API TikTok.</p>
        </header>

        <form onSubmit={handleTrack} className="flex gap-3">
          <input type="text" value={username} onChange={(e) => setUsername(e.target.value)} placeholder="@username" disabled={loading}
            className="flex-1 bg-zinc-900 border border-zinc-800 rounded px-4 py-3 font-mono text-sm focus:outline-none focus:border-zinc-600 placeholder:text-zinc-600" />
          <button type="submit" disabled={loading || !username.trim()}
            className="bg-zinc-100 text-zinc-950 font-mono text-sm font-bold px-6 py-3 rounded hover:bg-white disabled:opacity-40 transition">
            {loading ? 'proses...' : 'lacak'}
          </button>
        </form>

        {data && (
          <div className="space-y-4">
            {profile ? (
              <div className="border border-zinc-800 rounded-lg p-6 bg-zinc-900/50 space-y-4">
                <div className="flex items-start gap-4">
                  {profile.avatarUrl && <img src={profile.avatarUrl} alt="" className="w-16 h-16 rounded-full object-cover border border-zinc-700" />}
                  <div className="space-y-1">
                    <div className="flex items-center gap-2">
                      <h2 className="font-mono text-xl font-bold">@{profile.uniqueId}</h2>
                      {profile.isVerified && <span className="text-xs bg-blue-500/20 text-blue-400 px-1.5 py-0.5 rounded font-mono">✓</span>}
                    </div>
                    <p className="text-zinc-300 text-sm">{profile.nickname}</p>
                    {profile.bio && <p className="text-zinc-500 text-xs max-w-md">{profile.bio}</p>}
                  </div>
                </div>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4 pt-4 border-t border-zinc-800">
                  <Stat label="followers" value={fmt(profile.followerCount)} />
                  <Stat label="following" value={fmt(profile.followingCount)} />
                  <Stat label="total like" value={fmt(profile.heartCount)} />
                  <Stat label="video" value={fmt(profile.videoCount)} />
                </div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 pt-4 border-t border-zinc-800">
                  <Field label="negara (scavio)" value={data.region.country ?? 'tidak tersedia'} />
                  <Field label="negara (apify)" value={profile.region ?? 'tidak tersedia'} />
                  <Field label="tanggal buat" value={fmtDate(profile.accountCreatedAt)} />
                  <Field label="bahasa app" value={profile.language ?? 'tidak tersedia'} />
                  <Field label="sec_user_id" value={data.region.sec_user_id ?? 'tidak tersedia'} />
                  <Field label="scraped" value={new Date(data.scrapedAt).toLocaleString('id-ID')} />
                </div>
              </div>
            ) : (
              <div className="border border-red-900/60 bg-red-950/30 text-red-400 font-mono text-sm p-4 rounded">
                {data.apify.error ?? 'profil tidak ditemukan'}
              </div>
            )}
            {data.region.error && !profile && (
              <div className="border border-amber-900/60 bg-amber-950/30 text-amber-400 font-mono text-xs p-3 rounded">scavio: {data.region.error}</div>
            )}
          </div>
        )}
      </div>
    </main>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (<div><p className="text-[10px] font-mono text-zinc-500 uppercase tracking-wider">{label}</p><p className="font-mono text-lg font-bold">{value}</p></div>);
}
function Field({ label, value }: { label: string; value: string }) {
  return (<div><p className="text-[10px] font-mono text-zinc-500 uppercase tracking-wider">{label}</p><p className="font-mono text-sm text-zinc-200 break-all">{value}</p></div>);
}
EOF
