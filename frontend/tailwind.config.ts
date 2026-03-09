import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./src/**/*.{js,ts,jsx,tsx,mdx}'],
  theme: {
    extend: {
      colors: {
        // Ocean / base
        ocean: {
          950: '#040810',
          900: '#080f1e',
          800: '#0d1829',
          700: '#122033',
          600: '#1a2e47',
        },
        // Continent palette
        northlands: '#4a90d9',
        merchant:   '#2ab5a0',
        ironcoast:  '#8a9bb0',
        barrens:    '#d4a03a',
        verdant:    '#4aae6a',
        deepex:     '#3a5fc4',
        // UI chrome
        gold: {
          400: '#f6c84e',
          500: '#e8a820',
          600: '#c48a10',
        },
        danger: '#e05252',
        success: '#4aae6a',
      },
      fontFamily: {
        display: ['var(--font-cinzel)', 'Georgia', 'serif'],
        body: ['var(--font-inter)', 'system-ui', 'sans-serif'],
        mono: ['var(--font-fira-code)', 'monospace'],
      },
      animation: {
        'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        'float': 'float 3s ease-in-out infinite',
        'dice-roll': 'diceRoll 0.6s ease-out forwards',
        'conquest': 'conquest 0.8s ease-out forwards',
        'shimmer': 'shimmer 2s linear infinite',
      },
      keyframes: {
        float: {
          '0%, 100%': { transform: 'translateY(0px)' },
          '50%': { transform: 'translateY(-6px)' },
        },
        diceRoll: {
          '0%':   { transform: 'rotate(0deg) scale(0.5)', opacity: '0' },
          '50%':  { transform: 'rotate(180deg) scale(1.2)', opacity: '1' },
          '100%': { transform: 'rotate(360deg) scale(1)', opacity: '1' },
        },
        conquest: {
          '0%':   { transform: 'scale(1)', filter: 'brightness(1)' },
          '50%':  { transform: 'scale(1.4)', filter: 'brightness(2)' },
          '100%': { transform: 'scale(1)', filter: 'brightness(1)' },
        },
        shimmer: {
          '0%':   { backgroundPosition: '-200% 0' },
          '100%': { backgroundPosition: '200% 0' },
        },
      },
      backgroundImage: {
        'ocean-pattern': "url(\"data:image/svg+xml,%3Csvg width='60' height='60' viewBox='0 0 60 60' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' fill-rule='evenodd'%3E%3Cg fill='%231a2e47' fill-opacity='0.4'%3E%3Cpath d='M36 34v-4h-2v4h-4v2h4v4h2v-4h4v-2h-4zm0-30V0h-2v4h-4v2h4v4h2V6h4V4h-4zM6 34v-4H4v4H0v2h4v4h2v-4h4v-2H6zM6 4V0H4v4H0v2h4v4h2V6h4V4H6z'/%3E%3C/g%3E%3C/g%3E%3C/svg%3E\")",
        'gold-gradient': 'linear-gradient(135deg, #f6c84e 0%, #c48a10 50%, #e8a820 100%)',
        'shimmer-gradient': 'linear-gradient(90deg, transparent 0%, rgba(255,255,255,0.1) 50%, transparent 100%)',
      },
    },
  },
  plugins: [],
};

export default config;
