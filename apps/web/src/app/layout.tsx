import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "One Tap Trading",
  description: "Gamified trading on MegaETH",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
