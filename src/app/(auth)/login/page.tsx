// app/(auth)/login/page.tsx
'use client'
import { createClient } from '@/lib/supabase/client'
import { useRouter } from 'next/navigation'
import { useEffect, useState } from 'react'

export default function LoginPage() {
  const router = useRouter()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
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
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="w-full max-w-sm p-8 bg-white rounded-xl shadow space-y-4">
        <h1 className="text-2xl font-bold">OHMployee</h1>
        {error && <p className="text-red-500 text-sm">{error}</p>}
        <form onSubmit={handleLogin} className="space-y-4">
          <input className="w-full border rounded p-2" placeholder="Email"
            value={email} onChange={e => setEmail(e.target.value)} />
          <input className="w-full border rounded p-2" type="password" placeholder="Password"
            value={password} onChange={e => setPassword(e.target.value)} />
          <button
            type="submit"
            disabled={isSubmitting}
            className="w-full bg-blue-600 text-white py-2 rounded hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-blue-300">
            {isSubmitting ? 'Logging in...' : 'Login'}
          </button>
        </form>
        <a href="/forgot-password" className="text-sm text-blue-500 block text-center">
          Forgot password?
        </a>
      </div>
    </div>
  )
}
