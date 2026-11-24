// app/(auth)/login/page.tsx
'use client'
import { createClient, isSupabaseConfigured } from '@/lib/supabase/client'
import Image from 'next/image'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useEffect, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { Mail, Lock, Eye, EyeOff, AlertCircle } from 'lucide-react'

export default function LoginPage() {
  const router = useRouter()
  const queryClient = useQueryClient()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [error, setError] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)

  const isConfigured = isSupabaseConfigured()
  const configError = !isConfigured
    ? 'Supabase client is not configured: NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY are missing in this environment. Please configure them in Vercel Project Settings > Environment Variables.'
    : null

  useEffect(() => {
    // Ensure login view defaults to light mode and clears stale system theme
    try {
      const stored = localStorage.getItem('ohmployee_theme_mode')
      if (!stored || stored === 'system') {
        localStorage.setItem('ohmployee_theme_mode', 'light')
        window.dispatchEvent(new Event('ohmployee-theme-change'))
      }
    } catch {}

    let isMounted = true

    async function redirectAuthenticatedUser() {
      try {
        if (!isSupabaseConfigured()) return
        const supabase = createClient()
        const { data, error } = await supabase.auth.getSession()

        if (error) {
          console.warn("[login] Error fetching session:", error)
          return
        }

        if (isMounted && data?.session) {
          router.replace('/vacancy')
        }
      } catch (err) {
        console.warn("[login] Error during session check:", err)
      }
    }

    redirectAuthenticatedUser()

    return () => {
      isMounted = false
    }
  }, [router])

  const handleLogin = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setIsSubmitting(true)
    setError('')

    try {
      const supabase = createClient()
      const { error: signInError } = await supabase.auth.signInWithPassword({ email, password })
      if (signInError) {
        setIsSubmitting(false)
        return setError(signInError.message)
      }

      // Reset theme to light mode and clear stale query cache on new login
      try {
        localStorage.setItem('ohmployee_theme_mode', 'light')
        window.dispatchEvent(new Event('ohmployee-theme-change'))
        queryClient.clear()
      } catch {}

      router.replace('/vacancy')
      router.refresh()
    } catch (err) {
      setIsSubmitting(false)
      const message =
        err instanceof Error ? err.message : 'An unexpected error occurred during sign in.'
      console.error('[login] Sign in failure:', err)
      setError(message)
    }
  }

  return (
    <div className="relative min-h-screen flex flex-col items-center justify-center bg-background px-4 overflow-hidden">
      {/* Ambient background glows */}
      <div className="absolute top-1/4 left-1/4 -translate-x-1/2 -translate-y-1/2 w-80 h-80 rounded-full bg-brand-500/10 blur-[100px] pointer-events-none" />
      <div className="absolute bottom-1/4 right-1/4 translate-x-1/2 translate-y-1/2 w-96 h-96 rounded-full bg-brand-600/10 blur-[120px] pointer-events-none" />

      <div className="w-full max-w-md z-10 space-y-6">
        <div className="flex flex-col items-center space-y-2 text-center">
          <div className="h-20 w-20 flex items-center justify-center transition-transform hover:scale-105 duration-200">
            <Image
              src="/images/ohm_logo_transparent.png"
              alt="OHMployee Logo"
              width={80}
              height={80}
              priority
              className="h-20 w-20 object-contain drop-shadow-sm select-none"
            />
          </div>
          <h1 className="text-3xl font-extrabold tracking-tight text-text-primary">
            OHMployee
          </h1>
          <p className="text-sm text-text-secondary">
            Workforce Operations Platform
          </p>
        </div>

        <div className="bg-surface-base border border-border-default rounded-2xl shadow-xl p-8 space-y-6 backdrop-blur-md">
          {configError && (
            <div className="flex items-start gap-3 rounded-lg border border-status-danger-border bg-status-danger-bg p-3.5 text-sm text-status-danger-text">
              <AlertCircle className="h-5 w-5 shrink-0 mt-0.5" />
              <div className="space-y-1">
                <p className="font-semibold">Configuration Error</p>
                <p className="text-xs leading-relaxed">{configError}</p>
              </div>
            </div>
          )}

          {error && (
            <div className="flex items-center gap-3 rounded-lg border border-status-danger-border bg-status-danger-bg p-3.5 text-sm text-status-danger-text">
              <AlertCircle className="h-5 w-5 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          <form onSubmit={handleLogin} className="space-y-4">
            <div className="space-y-1.5">
              <label className="text-xs font-semibold text-text-secondary">
                Email Address
              </label>
              <div className="relative">
                <div className="pointer-events-none absolute left-3 top-1/2 h-5 w-5 -translate-y-1/2 text-text-muted flex items-center justify-center">
                  <Mail className="h-4.5 w-4.5" />
                </div>
                <input
                  required
                  type="email"
                  className="h-11 w-full rounded-lg border border-border-default bg-surface-muted pl-10 pr-3 text-sm text-text-primary outline-none transition-colors focus:border-brand-500"
                  placeholder="name@company.com"
                  value={email}
                  onChange={e => setEmail(e.target.value)}
                />
              </div>
            </div>

            <div className="space-y-1.5">
              <label className="text-xs font-semibold text-text-secondary">
                Password
              </label>
              <div className="relative">
                <div className="pointer-events-none absolute left-3 top-1/2 h-5 w-5 -translate-y-1/2 text-text-muted flex items-center justify-center">
                  <Lock className="h-4.5 w-4.5" />
                </div>
                <input
                  required
                  type={showPassword ? 'text' : 'password'}
                  className="h-11 w-full rounded-lg border border-border-default bg-surface-muted pl-10 pr-10 text-sm text-text-primary outline-none transition-colors focus:border-brand-500"
                  placeholder="••••••••"
                  value={password}
                  onChange={e => setPassword(e.target.value)}
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-3 top-1/2 h-5 w-5 -translate-y-1/2 text-text-muted hover:text-text-secondary flex items-center justify-center transition-colors focus:outline-none"
                >
                  {showPassword ? <EyeOff className="h-4.5 w-4.5" /> : <Eye className="h-4.5 w-4.5" />}
                </button>
              </div>
              <div className="flex justify-end pt-0.5">
                <Link
                  href="/forgot-password"
                  className="text-xs font-semibold text-brand-600 hover:text-brand-700 hover:underline transition-colors"
                >
                  Forgot password?
                </Link>
              </div>
            </div>

            <div className="pt-2">
              <button
                type="submit"
                disabled={isSubmitting || Boolean(configError)}
                className="w-full h-11 inline-flex items-center justify-center rounded-lg bg-brand-600 text-white font-medium text-sm transition-all hover:bg-brand-700 active:bg-brand-800 disabled:cursor-not-allowed disabled:opacity-50 shadow-md shadow-brand-600/10 cursor-pointer"
              >
                {isSubmitting ? (
                  <>
                    <span className="animate-spin mr-2 h-4 w-4 border-2 border-white border-t-transparent rounded-full" />
                    Signing in...
                  </>
                ) : (
                  'Sign In'
                )}
              </button>
            </div>

            <div className="text-center pt-2">
              <span className="text-xs text-text-secondary">
                Don&apos;t have an account?{' '}
                <Link
                  href="/signup"
                  className="font-semibold text-brand-600 hover:text-brand-700 hover:underline transition-colors"
                >
                  Request Account
                </Link>
              </span>
            </div>
          </form>
        </div>

        <div className="text-center text-xs text-text-muted">
          &copy; {new Date().getFullYear()} OHMployee. All rights reserved.
        </div>
      </div>
    </div>
  )
}
