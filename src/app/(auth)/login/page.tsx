// app/(auth)/login/page.tsx
'use client'
import { createClient } from '@/lib/supabase/client'
import { useRouter } from 'next/navigation'
import { useState } from 'react'

export default function LoginPage() {
  const supabase = createClient()
  const router = useRouter()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')

  const handleLogin = async () => {
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) return setError(error.message)
    router.push('/vacancy')
    router.refresh()
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="w-full max-w-sm p-8 bg-white rounded-xl shadow space-y-4">
        <h1 className="text-2xl font-bold">OHMployee</h1>
        {error && <p className="text-red-500 text-sm">{error}</p>}
        <input className="w-full border rounded p-2" placeholder="Email"
          value={email} onChange={e => setEmail(e.target.value)} />
        <input className="w-full border rounded p-2" type="password" placeholder="Password"
          value={password} onChange={e => setPassword(e.target.value)} />
        <button onClick={handleLogin}
          className="w-full bg-blue-600 text-white py-2 rounded hover:bg-blue-700">
          Login
        </button>
        <a href="/forgot-password" className="text-sm text-blue-500 block text-center">
          Forgot password?
        </a>
      </div>
    </div>
  )
}