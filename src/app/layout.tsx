import type { Metadata } from "next";
import {
  DM_Sans,
  DM_Mono,
  Inter,
  Geist,
  JetBrains_Mono,
  Roboto_Mono,
} from "next/font/google";
import "./globals.css";
import { Providers } from "./providers";

const dmSans = DM_Sans({
  subsets: ["latin"],
  variable: "--font-dm-sans",
  display: "swap",
});

const dmMono = DM_Mono({
  subsets: ["latin"],
  weight: ["400", "500"],
  variable: "--font-dm-mono",
  display: "swap",
});

const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
  display: "swap",
});

const geistSans = Geist({
  subsets: ["latin"],
  variable: "--font-geist-sans",
  display: "swap",
});

const jetbrainsMono = JetBrains_Mono({
  subsets: ["latin"],
  variable: "--font-jetbrains-mono",
  display: "swap",
});

const robotoMono = Roboto_Mono({
  subsets: ["latin"],
  variable: "--font-roboto-mono",
  display: "swap",
});

export const metadata: Metadata = {
  title: "OHMployee",
  description: "OHMployee workforce operations platform",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      suppressHydrationWarning
      className={`h-full antialiased ${dmSans.variable} ${dmMono.variable} ${inter.variable} ${geistSans.variable} ${jetbrainsMono.variable} ${robotoMono.variable}`}
    >
      <head>
        <script
          dangerouslySetInnerHTML={{
            __html: `
              (function() {
                try {
                  var stored = localStorage.getItem('ohmployee_theme_mode');
                  var storedFont = localStorage.getItem('ohm_font_preference');
                  var prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
                  var theme = stored || 'light';
                  var isDark = theme === 'dark' || (theme === 'system' && prefersDark);
                  var root = document.documentElement;
                  root.setAttribute('data-theme', theme);
                  root.setAttribute('data-resolved-theme', isDark ? 'dark' : 'light');
                  root.style.colorScheme = isDark ? 'dark' : 'light';
                  if (storedFont) {
                    root.setAttribute('data-font', storedFont);
                  }
                  if (isDark) {
                    root.classList.add('dark');
                    root.classList.remove('light');
                  } else {
                    root.classList.add('light');
                    root.classList.remove('dark');
                  }
                } catch (e) {}
              })();
            `,
          }}
        />
      </head>
      <body className="min-h-full flex flex-col">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}

