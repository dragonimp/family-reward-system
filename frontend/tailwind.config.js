/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        primary: {
          DEFAULT: '#4A90D9',
          light: '#6BA3E0',
          dark: '#3A7BC8',
        },
        accent: {
          orange: '#F5A623',
          green: '#7ED321',
          red: '#E74C3C',
        },
        background: '#F7F9FC',
      },
    },
  },
  plugins: [],
}
