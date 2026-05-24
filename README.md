# OHMployee Web

Next.js App Router foundation for the OHMployee workforce operations platform.

## Development

```bash
pnpm dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

## Foundation Layout

- Routes and layouts live in `src/app/**`.
- Reusable UI and feature presentation components live in `src/components/**`.
- Shared clients, providers, and integration contracts live in `src/lib/**`.

## Environment

Copy `.env.example` and provide Supabase project values before testing auth-backed flows.

```bash
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
```

## Architecture Notes

Keep the web client thin. Business rules, RBAC, RLS, and data integrity belong in Supabase.
