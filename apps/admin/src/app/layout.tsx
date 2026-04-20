export const metadata = { title: "besetter admin" };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ko">
      <body style={{ margin: 0, fontFamily: "system-ui, sans-serif", background: "#0f1117", color: "#dde1ea" }}>
        {children}
      </body>
    </html>
  );
}
