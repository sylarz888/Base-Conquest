import type { Metadata } from 'next';
import { Inter, Cinzel, Fira_Code } from 'next/font/google';
import { Providers } from './providers';
import { Toaster } from 'sonner';
import './globals.css';

const inter    = Inter({ subsets: ['latin'], variable: '--font-inter' });
const cinzel   = Cinzel({ subsets: ['latin'], variable: '--font-cinzel', weight: ['400', '600', '700'] });
const firaCode = Fira_Code({ subsets: ['latin'], variable: '--font-fira-code', weight: ['400', '500'] });

export const metadata: Metadata = {
  title:       'Base-Conquest — On-chain strategy on Base',
  description: 'A provably-fair, on-chain strategy game. Conquer 42 territories. Forge alliances. Claim the prize pool.',
  openGraph: {
    title:       'Base-Conquest',
    description: 'On-chain strategy game powered by Chainlink VRF on Base.',
    type:        'website',
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="dark">
      <body className={`${inter.variable} ${cinzel.variable} ${firaCode.variable} font-body bg-ocean-950 text-white antialiased`}>
        <Providers>
          {children}
          <Toaster
            theme="dark"
            position="bottom-right"
            toastOptions={{
              style: {
                background: '#0d1829',
                border:     '1px solid #1a2e47',
                color:      '#f1f5f9',
              },
            }}
          />
        </Providers>
      </body>
    </html>
  );
}
