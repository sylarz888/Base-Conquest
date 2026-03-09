import Link from 'next/link';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { CONTINENTS } from '@/components/Map/territories';

// ── Static landing page ───────────────────────────────────────────────────────

function FeatureCard({ icon, title, desc }: { icon: string; title: string; desc: string }) {
  return (
    <div className="rounded-xl border border-white/5 bg-ocean-900/60 p-5 hover:border-gold-500/20 transition-colors">
      <div className="text-2xl mb-2">{icon}</div>
      <h3 className="font-display text-white font-semibold mb-1">{title}</h3>
      <p className="text-sm text-slate-400 leading-relaxed">{desc}</p>
    </div>
  );
}

function ContinentCard({ id, name, bonus, color, textColor, description }: {
  id: number; name: string; bonus: number; color: string; textColor: string; description: string;
}) {
  return (
    <div
      className="rounded-lg border px-4 py-3 text-sm"
      style={{ borderColor: textColor + '33', backgroundColor: color + '22' }}
    >
      <div className="flex items-center justify-between mb-1">
        <span className="font-display font-semibold" style={{ color: textColor }}>{name}</span>
        <span className="font-mono text-xs px-1.5 py-0.5 rounded" style={{ backgroundColor: textColor + '22', color: textColor }}>
          +{bonus} armies
        </span>
      </div>
      <p className="text-slate-500 text-xs">{description}</p>
    </div>
  );
}

export default function HomePage() {
  return (
    <main className="h-full overflow-y-auto bg-ocean-950">
      {/* Nav */}
      <nav className="sticky top-0 z-50 flex items-center justify-between px-6 py-4
        bg-ocean-950/90 backdrop-blur border-b border-white/5">
        <div className="flex items-center gap-3">
          <div className="w-7 h-7 rounded bg-gold-500/10 border border-gold-500/30 flex items-center justify-center text-gold-400 text-sm">
            ⚔
          </div>
          <span className="font-display text-white font-semibold text-lg">Base-Conquest</span>
          <span className="text-xs px-1.5 py-0.5 rounded bg-ocean-800 text-slate-400 border border-white/5">
            TESTNET
          </span>
        </div>
        <div className="flex items-center gap-3">
          <Link href="/game"
            className="text-sm text-slate-400 hover:text-white transition-colors px-3 py-1.5 rounded-lg hover:bg-ocean-800">
            Game Board
          </Link>
          <ConnectButton />
        </div>
      </nav>

      {/* Hero */}
      <section className="relative flex flex-col items-center justify-center text-center px-6 py-24 overflow-hidden">
        {/* Background effect */}
        <div className="absolute inset-0 bg-ocean-pattern opacity-20 pointer-events-none" />
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-96 h-96
          bg-gold-500/5 rounded-full blur-3xl pointer-events-none" />

        <div className="relative z-10 max-w-3xl">
          <p className="text-xs font-mono tracking-widest text-gold-500 uppercase mb-4">
            Powered by Chainlink VRF on Base
          </p>
          <h1 className="font-display text-5xl sm:text-6xl font-bold text-shimmer leading-tight mb-6">
            Conquer the Archipelago
          </h1>
          <p className="text-lg text-slate-400 mb-10 max-w-xl mx-auto leading-relaxed">
            A provably-fair on-chain strategy game. Capture 42 territories,
            forge alliances, and claim the ETH prize pool — all verified by
            Chainlink VRF dice rolls on Base.
          </p>
          <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
            <Link
              href="/game"
              className="px-8 py-3 rounded-xl bg-gold-500 text-ocean-950 font-display font-bold text-base
                hover:bg-gold-400 transition-colors shadow-lg shadow-gold-500/20"
            >
              Enter the Game
            </Link>
            <a
              href="https://github.com/sylarz888/Base-Conquest"
              target="_blank"
              rel="noopener noreferrer"
              className="px-8 py-3 rounded-xl border border-white/10 text-slate-300 font-medium text-sm
                hover:border-white/25 hover:text-white transition-colors"
            >
              View Contracts ↗
            </a>
          </div>
        </div>
      </section>

      {/* Key features */}
      <section className="max-w-5xl mx-auto px-6 pb-16">
        <h2 className="font-display text-2xl font-semibold text-white text-center mb-8">How it Works</h2>
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4 mb-12">
          <FeatureCard
            icon="🎲"
            title="Provably-Fair Dice"
            desc="Every attack is resolved by Chainlink VRF — tamper-proof randomness on-chain. No operator can influence outcomes."
          />
          <FeatureCard
            icon="🗺"
            title="42 Territories"
            desc="Six island continents, each with strategic bonus armies. Conquer all to claim world domination — or hold the most when the season timer expires."
          />
          <FeatureCard
            icon="🤝"
            title="Alliance System"
            desc="Forge Non-Aggression Pacts with other players. Betray your allies at the cost of attack power and a 5-turn diplomatic cooldown."
          />
          <FeatureCard
            icon="💰"
            title="ETH Prize Pool"
            desc="Auction proceeds and secondary sale royalties fund a live ETH prize pool. Winners take the majority; 20% rolls over to the next season."
          />
          <FeatureCard
            icon="⚡"
            title="Turn-Gated on Base"
            desc="One turn every 24 hours per player. Deploy armies, launch up to 3 VRF attacks, then fortify — all in a single on-chain session."
          />
          <FeatureCard
            icon="🃏"
            title="Territory Cards"
            desc="Earn a card every time you conquer a territory. Trade sets for escalating bonus armies — up to 25 extra per set as the season progresses."
          />
        </div>

        {/* Continents */}
        <h2 className="font-display text-2xl font-semibold text-white text-center mb-6">The Six Continents</h2>
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-3">
          {(Object.values(CONTINENTS) as typeof CONTINENTS[keyof typeof CONTINENTS][]).map(c => (
            <ContinentCard
              key={c.id}
              id={c.id}
              name={c.name}
              bonus={c.bonusArmies}
              color={c.color}
              textColor={c.textColor}
              description={c.description}
            />
          ))}
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-white/5 px-6 py-6 text-center text-xs text-slate-600">
        Base-Conquest is an experimental on-chain game. Play on Base Sepolia testnet only during development.
        Smart contracts are unaudited.
      </footer>
    </main>
  );
}
