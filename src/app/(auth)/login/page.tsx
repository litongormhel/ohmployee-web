// app/(auth)/login/page.tsx
'use client'
import { createClient } from '@/lib/supabase/client'
import { useRouter } from 'next/navigation'
import { useEffect, useState } from 'react'
import { Mail, Lock, Eye, EyeOff, AlertCircle, LayoutDashboard } from 'lucide-react'

export default function LoginPage() {
  const router = useRouter()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [error, setError] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)

  useEffect(() => {
    let isMounted = true

    async function redirectAuthenticatedUser() {
      const supabase = createClient()
      const { data } = await supabase.auth.getSession()

      if (isMounted && data.session) {
        router.replace('/dashboard')
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
    const supabase = createClient()
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) {
      setIsSubmitting(false)
      return setError(error.message)
    }
    router.replace('/dashboard')
    router.refresh()
  }

  return (
    <div className="relative min-h-screen flex flex-col items-center justify-center bg-background px-4 overflow-hidden">
      {/* Ambient background glows */}
      <div className="absolute top-1/4 left-1/4 -translate-x-1/2 -translate-y-1/2 w-80 h-80 rounded-full bg-brand-500/10 blur-[100px] pointer-events-none" />
      <div className="absolute bottom-1/4 right-1/4 translate-x-1/2 translate-y-1/2 w-96 h-96 rounded-full bg-brand-600/10 blur-[120px] pointer-events-none" />

      <div className="w-full max-w-md z-10 space-y-6">
        <div className="flex flex-col items-center space-y-2 text-center">
          <div className="inline-flex h-12 w-12 items-center justify-center rounded-xl bg-gradient-to-tr from-brand-600 to-brand-500 text-white shadow-md shadow-brand-500/20">
            <LayoutDashboard className="h-6 w-6" />
          </div>
          <h1 className="text-3xl font-extrabold tracking-tight text-text-primary">
            OHMployee
          </h1>
          <p className="text-sm text-text-secondary">
            Workforce Operations Platform
          </p>
        </div>

        <div className="bg-surface-base border border-border-default rounded-2xl shadow-xl p-8 space-y-6 backdrop-blur-md">
          {error && (
            <div className="flex items-center gap-3 rounded-lg border border-status-danger-border bg-status-danger-bg p-3.5 text-sm text-status-danger-text">
              <AlertCircle className="h-5 w-5 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          <form onSubmit={handleLogin} className="space-y-4">
            <div className="space-y-1.5">
              <label className="text-xs font-semibold uppercase tracking-wider text-text-secondary">
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
              <div className="flex items-center justify-between">
                <label className="text-xs font-semibold uppercase tracking-wider text-text-secondary">
                  Password
                </label>
                <a href="/forgot-password" className="text-xs text-brand-600 hover:text-brand-700 font-medium transition-colors">
                  Forgot?
                </a>
              </div>
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
            </div>

            <div className="pt-2">
              <button
                type="submit"
                disabled={isSubmitting}
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
          </form>
        </div>

        <div className="text-center text-xs text-text-muted">
          &copy; {new Date().getFullYear()} OHMployee. All rights reserved.
        </div>
      </div>
    </div>
  )
}
