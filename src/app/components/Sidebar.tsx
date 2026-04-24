// components/Sidebar.tsx
'use client'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { LayoutDashboard, Users, ClipboardList, LogOut } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { useRouter } from 'next/navigation'

const nav = [
  { href: '/vacancy', label: 'Vacancy', icon: LayoutDashboard },
  { href: '/hr-emploc', label: 'HR Emploc', icon: Users },
  { href: '/plantilla', label: 'Plantilla', icon: ClipboardList },
]

export function Sidebar() {
  const path = usePathname()
  const router = useRouter()
  const supabase = createClient()

  const logout = async () => {
    await supabase.auth.signOut()
    router.push('/login')
  }

  return (
    <aside className="w-56 bg-white border-r flex flex-col py-6 px-4">
      <h2 className="text-lg font-bold mb-8 px-2">OHMployee</h2>
      <nav className="space-y-1 flex-1">
        {nav.map(({ href, label, icon: Icon }) => (
          <Link key={href} href={href}
            className={`flex items-center gap-3 px-3 py-2 rounded-lg text-sm
              ${path.startsWith(href) ? 'bg-blue-50 text-blue-600 font-medium' : 'text-gray-600 hover:bg-gray-100'}`}>
            <Icon size={16} />
            {label}
          </Link>
        ))}
      </nav>
      <button onClick={logout}
        className="flex items-center gap-3 px-3 py-2 text-sm text-gray-500 hover:text-red-500">
        <LogOut size={16} /> Logout
      </button>
    </aside>
  )
}