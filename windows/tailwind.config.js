/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        mac: {
          bg: '#1c1c1e',
          card: '#2c2c2e',
          subcard: '#3a3a3c',
          border: 'rgba(255, 255, 255, 0.08)',
          accent: '#0A84FF',
        }
      }
    },
  },
  plugins: [],
}
