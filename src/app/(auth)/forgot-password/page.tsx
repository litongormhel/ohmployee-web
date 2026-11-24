"use client";

import { useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { Mail, ArrowLeft, CheckCircle2, AlertCircle } from "lucide-react";
import { sendPasswordResetEmail } from "@/lib/queries/signup";

export default function ForgotPasswordPage() {
  const [email, setEmail] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isSuccess, setIsSuccess] = useState(false);

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (!email.trim()) {
      setError("Please enter your registered email address.");
      return;
    }

    setIsSubmitting(true);
    setError(null);

    try {
      await sendPasswordResetEmail(email.trim());
      setIsSuccess(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to send password reset email.");
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="relative min-h-screen flex flex-col items-center justify-center bg-background px-4 overflow-hidden">
      {/* Ambient background glows */}
      <div className="absolute top-1/4 left-1/4 -translate-x-1/2 -translate-y-1/2 w-80 h-80 rounded-full bg-brand-500/10 blur-[100px] pointer-events-none" />
      <div className="absolute bottom-1/4 right-1/4 translate-x-1/2 translate-y-1/2 w-96 h-96 rounded-full bg-brand-600/10 blur-[120px] pointer-events-none" />

      <div className="w-full max-w-md z-10 space-y-6">
        {/* Brand Header */}
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

        {/* Card Container */}
        <div className="bg-surface-base border border-border-default rounded-2xl shadow-xl p-8 space-y-6 backdrop-blur-md">
          {isSuccess ? (
            <div className="space-y-4 text-center">
              <div className="w-12 h-12 bg-emerald-500/10 text-emerald-600 rounded-full flex items-center justify-center mx-auto">
                <CheckCircle2 className="w-6 h-6" />
              </div>
              <h2 className="text-xl font-bold text-text-primary">
                Check Your Email
              </h2>
              <p className="text-xs text-text-secondary leading-relaxed">
                We have sent a password reset link to{" "}
                <strong className="text-text-primary font-semibold">{email}</strong>.
                Click the link in the email to set a new password.
              </p>
              <div className="pt-2">
                <Link
                  href="/login"
                  className="w-full h-11 inline-flex items-center justify-center rounded-lg bg-brand-600 text-white font-medium text-sm transition-all hover:bg-brand-700 shadow-md shadow-brand-600/10 cursor-pointer"
                >
                  Back to Sign In
                </Link>
              </div>
            </div>
          ) : (
            <>
              <div>
                <h2 className="text-xl font-bold text-text-primary">
                  Reset Password
                </h2>
                <p className="text-xs text-text-secondary mt-1">
                  Enter your registered work email and we&apos;ll send you a recovery link.
                </p>
              </div>

              {error && (
                <div className="flex items-center gap-3 rounded-lg border border-status-danger-border bg-status-danger-bg p-3.5 text-sm text-status-danger-text">
                  <AlertCircle className="h-5 w-5 shrink-0" />
                  <span>{error}</span>
                </div>
              )}

              <form onSubmit={handleSubmit} className="space-y-4">
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
                      onChange={(e) => setEmail(e.target.value)}
                    />
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
                        Sending Reset Link...
                      </>
                    ) : (
                      "Send Reset Link"
                    )}
                  </button>
                </div>
              </form>

              <div className="text-center pt-1">
                <Link
                  href="/login"
                  className="inline-flex items-center gap-1.5 text-xs font-semibold text-brand-600 hover:text-brand-700 transition-colors"
                >
                  <ArrowLeft className="w-3.5 h-3.5" />
                  <span>Remembered your password? Sign In</span>
                </Link>
              </div>
            </>
          )}
        </div>

        <div className="text-center text-xs text-text-muted">
          &copy; {new Date().getFullYear()} OHMployee. All rights reserved.
        </div>
      </div>
    </div>
  );
}
