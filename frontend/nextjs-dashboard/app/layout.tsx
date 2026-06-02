import "./globals.css";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "EMQX Interview Dashboard",
  description: "Demo dashboard for EMQX cluster interview walkthrough"
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
